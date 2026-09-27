# turtles

Mutation testing for MoonBit projects — the `cargo-mutants` idea, implemented entirely in MoonBit and adapted to `moon test`.

`turtles` finds small source-level changes ("mutants"), applies them one at a time in a **temporary copy** of your MoonBit module, and asks your tests to catch them. Your working tree is never intentionally modified.

## Implementation

`turtles` itself is a native MoonBit executable. The CLI, configuration parser, mutation discovery/application, temporary-workspace handling, subprocess execution, timeout handling, classification, and JSON reporting are all written in MoonBit.

There is no Rust or Cargo implementation.

The project currently uses:

- `moonbitlang/async` for subprocess execution, cancellation, timing, and async filesystem operations
- `moonbitlang/parser@0.4.0` for syntax-aware mutation candidate discovery
- `moonbitlang/x` for native path/system support
- `moonbitlang/core/quickcheck` for property-based tests of its own pure invariants (wbtest-only import)
- `moon check` and `moon test` for mutant classification, plus optional extra verification gates

## What it mutates

The current vertical slice covers common expression mutations:

- comparisons: `== ↔ !=`, `> → <`, `< → >`, `>= → <`, `<= → >`
- boolean logic: `&& ↔ ||`
- arithmetic: `+ ↔ -`, `* ↔ /`
- boolean literals: `true ↔ false`
- if conditions: `cond → true`, `cond → false`

Comments, strings, character literals, test files (`*_test.mbt`, `*_wbtest.mbt`), generated/build directories, and function arrows are excluded by syntax rather than lexical heuristics. Proof/spec files (`*.mbtp`) are never scanned (they do not match `*.mbt`), but expressions inside inline proof regions of regular `.mbt` sources are not excluded — the parser boundary there is unverified, so exclude spec-heavy files with `turtles.toml` if needed. Mutations that make the program fail `moon check` are reported as **unviable**, rather than as killed tests.

## Run from source

MoonBit's `moon` executable must be on `PATH`.

From this repository:

```sh
moon update
moon run cmd/turtles -- --help
```

Run against a MoonBit module:

```sh
moon run cmd/turtles -- --dir path/to/module
```

The executable package is `cmd/turtles` and targets MoonBit native.

## CLI

```text
turtles [OPTIONS]

-d, --dir <PATH>       MoonBit module directory (default: .)
    --timeout <SECS>   Per-command timeout (default: 60)
    --file <TEXT>      Only mutate source paths containing TEXT
    --json <PATH>      Write a JSON report to PATH
    --list             List mutations without running tests
    --prove            Append a 'moon prove' gate (requires Why3)
-h, --help             Print help
```

`--list` is useful for inspecting the mutation set before spending time running tests:

```sh
moon run cmd/turtles -- --dir path/to/module --list
```

Use `--json` to persist machine-readable results, including baseline duration, per-mutant outcome/timing, and the final summary:

```sh
moon run cmd/turtles -- --dir path/to/module --json target/turtles-report.json
```

The JSON report uses schema version `2`: each mutant records `gate` (the name of the gate that produced its outcome, or `null` for SURVIVED) and the report records the ordered `gates` that were run.

## Configuration

If `turtles.toml` exists in the target MoonBit module root, turtles reads mutation selection from it before scanning sources.

```toml
include = ["src/", "lib/"]
exclude = ["generated/", "vendor/"]
operators = ["comparison", "boolean", "arithmetic", "literal"]
gates = ["check", "test"]
```

- `include`: optional path substrings; when non-empty, at least one must match the normalized relative source path.
- `exclude`: optional path substrings; matching sources are skipped.
- `operators`: optional operator groups. Supported groups are `comparison`, `boolean`, `arithmetic`, and `literal`.
- `gates`: optional ordered verification gates (see below). Defaults to `["check", "test"]`.
- CLI `--file` remains an additional filter on top of `turtles.toml`.
- Test files remain excluded by default and cannot be enabled through this configuration.

Gate specs are either builtin names or custom commands:

```toml
gates = [
  "check",                           # moon check (viability)
  "test",                            # moon test
  "self-e2e=sh scripts/self_e2e.sh", # name=program args...
]
```

- Builtin names `check`, `test`, and `prove` map to `moon <name>` run at the module root of the mutated copy.
- `name=command args...` defines a custom gate; the command line is split on whitespace (no quoting) and run inside the mutated workspace.
- Gates run in order and the first failure decides the outcome. A failing `check` gate reports UNVIABLE; every other gate failure reports KILLED, and the mutant is attributed to that gate in the console output and the JSON report.
- `--prove` appends a `moon prove` gate when the configured gates do not already include one. `moon prove` is an optional gate: it requires a toolchain with `moon prove` support, an installed Why3 toolchain, and proof-enabled packages (`*.mbtp`); it is never enabled by default.

The configuration parser intentionally supports a small TOML-compatible subset: top-level arrays of double-quoted strings, comments, trailing commas, and multiline arrays. Unknown keys, operator groups, gate specs, and an empty `gates` list are rejected instead of silently ignored.

## Result model

For every mutant:

- **UNVIABLE** — the `check` gate (`moon check`) rejected the mutated source.
- **KILLED** — a later gate failed: `moon test` caught the change, a `prove` gate could not discharge it, or a custom gate command exited non-zero.
- **SURVIVED** — every gate passed; nothing detected the change.
- **TIMEOUT** — a gate exceeded the configured timeout.

The process exits with code `1` when any mutant survives or times out, `2` for setup/baseline failures, and `0` when all viable mutants are killed.

## Safety model

Before mutation testing, `turtles` runs an unchanged `moon test` baseline. It then copies the module into a temporary directory, excluding `.git`, `target`, `_build`, `.mooncakes`, `.moon`, and `node_modules`. All mutations and test runs happen there. The temporary workspace is removed when the run finishes.

## Self-verification

turtles mutation-tests itself. The checked-in `turtles.toml` at the module root selects `cmd/turtles/` production sources and a three-stage gate pipeline:

```sh
moon run cmd/turtles -- --dir . --timeout 300 --json target/turtles-self.json
```

- `check` — the mutated copy must still compile.
- `test` — the unit tests plus the `moonbitlang/core/quickcheck` property suite (`cmd/turtles/quickcheck_wbtest.mbt`, fixed seeds) must catch the change.
- `self-e2e` — `scripts/self_e2e.sh` rebuilds the *mutated* turtles binary inside the copied workspace and runs it against `fixtures/basic`, validating the JSON report. The fixture directory is hard-coded, so the mutated binary can never recurse into `.`.

`--timeout` covers every gate command; the `self-e2e` gate rebuilds and runs the whole fixture sweep, so give self-runs a generous budget. See `docs/verification.md` for the harness design, the `moon prove` status, and survivor policy.

## Development

The CI is MoonBit-only:

```sh
moon update
moon fmt --check
moon check --target native --deny-warn
moon test --target native
moon -C fixtures/basic test
moon run cmd/turtles -- --dir fixtures/basic --timeout 30
moon run cmd/turtles -- --dir . --list
moon run cmd/turtles -- --dir . --file report.mbt --timeout 300
```

The real fixture E2E also validates schema-2 JSON report generation.

## Current scope

The rewrite preserves the trustworthy MVP behavior while making MoonBit the implementation language end to end. Candidate discovery is driven by the pinned experimental parser AST; parser diagnostics abort discovery instead of triggering a lexical fallback. The current AST boundary covers the existing operator and boolean-literal mutations while preserving byte-accurate application and parser line/column reporting. See `docs/moonbit-parser.md`.

Planned follow-ups include structural AST mutations, test selection, parallel workers, survived-mutant source/diff artifacts, JUnit reports, resume/retry, and incremental/cached execution.
