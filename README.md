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
- `moon check` and `moon test` for mutant classification

## What it mutates

The current vertical slice covers common expression mutations:

- comparisons: `== ↔ !=`, `> → <`, `< → >`, `>= → <`, `<= → >`
- boolean logic: `&& ↔ ||`
- arithmetic: `+ ↔ -`, `* ↔ /`, unary `-x → +x`
- boolean literals: `true ↔ false`
- conditions: whole `if` conditions → `true` or `false`

Comments, strings, character literals, test files (`*_test.mbt`, `*_wbtest.mbt`), generated/build directories, and function arrows are excluded by syntax rather than lexical heuristics. Mutations that make the program fail `moon check` are reported as **unviable**, rather than as killed tests.

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

The JSON report currently uses schema version `1`. An empty mutation set still produces a schema-1 report with `mutants: []` and a real measured `baseline_duration_ms` (the `moon check` + `moon test` validation run on the pristine workspace copy); `--list` never runs tests.

## Configuration

If `turtles.toml` exists in the target MoonBit module root, turtles reads mutation selection from it before scanning sources.

```toml
include = ["src/", "lib/"]
exclude = ["generated/", "vendor/"]
operators = ["comparison", "boolean", "arithmetic", "literal", "condition"]
```

- `include`: optional path substrings; when non-empty, at least one must match the normalized relative source path.
- `exclude`: optional path substrings; matching sources are skipped.
- `operators`: optional operator groups. Supported groups are `comparison`, `boolean`, `arithmetic`, `literal`, and `condition` (whole-`if`-condition replacement). `boolean` covers only logical `&&`/`||`; selecting `condition` alone gives structural mutations without logical ones, and vice versa.

- CLI `--file` remains an additional filter on top of `turtles.toml`.
- Test files remain excluded by default and cannot be enabled through this configuration.

The configuration parser intentionally supports a small TOML-compatible subset: top-level arrays of double-quoted strings, comments, trailing commas, and multiline arrays. Unknown keys and operator groups are rejected instead of silently ignored.

## Result model

For every viable mutant:

- **KILLED** — `moon check` succeeded and `moon test` failed.
- **SURVIVED** — both commands succeeded; tests did not detect the change.
- **TIMEOUT** — checking or testing exceeded the configured timeout.
- **UNVIABLE** — `moon check` rejected the mutated source.

The process exits with code `1` when any mutant survives or times out, `2` for setup/baseline failures, and `0` when all viable mutants are killed.

## Safety model

`turtles` never runs tests in the module's working tree. The module is copied into a temporary directory, excluding `.git`, `target`, `_build`, `.mooncakes`, `.moon`, and `node_modules`. The copy keeps the caller's read/write/execute permissions on files and directories and recreates symlinks that resolve inside the module as links; symlinks that point outside the module are dereference-copied so writes cannot escape the workspace, and dangling links are a hard error.

The first copy is a pristine `reference` tree, snapshotted before any test executes. The baseline runs `moon check` and `moon test` on a disposable `baseline` copy of that reference — a failure there is a setup error, not a mutant outcome — so state written by the baseline cannot leak into mutants either. Each mutant then runs in its own `mutant-N` workspace copied fresh from `reference`, so filesystem state written by earlier runs (sentinels, caches, generated files) cannot leak into later classifications and mutant order cannot change results. The temporary directory is removed when the run finishes.

On Windows, symlinks require privilege elevation and are dereference-copied instead of recreated.

## Development

The CI is MoonBit-only:

```sh
moon update
moon fmt --check
moon check --target native --deny-warn
moon test --target native
moon -C fixtures/basic test
moon run cmd/turtles -- --dir fixtures/basic --timeout 30
```

The real fixture E2E also validates schema-1 JSON report generation.

## Current scope

The rewrite preserves the trustworthy MVP behavior while making MoonBit the implementation language end to end. Candidate discovery is driven by the pinned experimental parser AST; parser diagnostics abort discovery instead of triggering a lexical fallback. The current AST boundary covers the existing operator and boolean-literal mutations while preserving byte-accurate application and parser line/column reporting. See `docs/moonbit-parser.md`.

Planned follow-ups include test selection, parallel workers (the per-mutant workspace layout is already parallel-safe), survived-mutant source/diff artifacts, JUnit reports, resume/retry, and incremental/cached execution.
