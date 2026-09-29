# turtles

Mutation testing for MoonBit projects — the `cargo-mutants` idea, implemented entirely in MoonBit and adapted to `moon test`.

`turtles` finds small source-level changes ("mutants"), applies them one at a time in a **temporary copy** of your MoonBit module, and asks your tests to catch them. Surviving mutants point at behavior your tests don't actually pin down. Your working tree is never intentionally modified.

## Install

The supported way to install `turtles` is `moon install`, which builds the native executable from source (requires the MoonBit toolchain). It puts a `turtles` binary in `~/.moon/bin` (the same directory `moon` itself lives in, so it is usually already on `PATH`). Override the destination with `--bin <DIR>`.

### Stable — Mooncakes *(pending first publish)*

Once `f4ah6o/turtles` is published to Mooncakes, the registry install becomes the default path:

```sh
moon install f4ah6o/turtles/cmd/turtles@<version>
```

*This command is not live yet — the first publish is tracked in `issues/open/2026-09-30-mooncakes-cli-distribution.md`.*

### Development — GitHub *(verified path today)*

```sh
moon install https://github.com/f4ah6o/turtles.git cmd/turtles --branch main
```

Pin a release once tags are published:

```sh
moon install https://github.com/f4ah6o/turtles.git cmd/turtles --tag v0.2.0
```

### From a local clone

```sh
moon install ./cmd/turtles
```

## First run in 30 seconds

```sh
turtles --version          # turtles 0.2.0
turtles --help

cd path/to/your-moonbit-module
turtles --dir .            # or: turtles --list to preview the mutation set
```

Every mutant runs in its own temporary workspace; on a small module the whole run takes seconds.

## Typical local usage

```sh
turtles --dir .                    # run all discovered mutants
turtles --dir . --list             # preview mutations without running tests
turtles --dir . --file src/parser  # only mutate paths containing TEXT
turtles --dir . --timeout 120      # per-command timeout in seconds (default 60)
turtles --dir . --json report.json # machine-readable report (schema 2)
turtles --dir . --iterate          # reuse KILLED/UNVIABLE outcomes from the last run
turtles --dir . --affected         # run only tests that can observe each mutant
turtles --dir . --timeout-multiplier 3   # per-phase timeout = 3x the measured baseline (min 10s)
```

### Parallel execution

```sh
turtles --dir . --jobs 4
```

`--jobs N` runs up to `N` mutants concurrently (validated as a positive integer; default `1`). Each worker gets a persistent `worker-N` workspace with a warm `_build`, restored to its snapshot after every mutant, and the baseline `moon check` + `moon test` runs exactly once before any mutant. Results and the JSON report are always ordered by discovery order, not completion order — parallelism never makes reports flaky.

Note that `moon` itself already parallelizes a single build; `--jobs` parallelizes *across mutants*, so values above ~2× your CPU count only add contention.

## CI usage

By default turtles exits `1` when any mutant survives or times out — the right behavior once a codebase is clean, but awkward when introducing mutation testing to an existing suite. Use `--fail-under` to ratchet the bar gradually:

```sh
turtles --dir . --fail-under 80
```

- `score >= threshold` → exit `0`, even if survivors exist.
- `score < threshold` → exit `1`.
- Setup or baseline failures → exit `2` regardless of thresholds.
- Without `--fail-under`, the previous rule applies: exit `1` on any `SURVIVED` or `TIMEOUT` mutant.

The range `0..100` is validated; fractional values like `--fail-under 79.5` are accepted.

### Mutation score semantics

```
score = killed / viable * 100     where viable = killed + survived + timeout
```

- `UNVIABLE` mutants (which fail `moon check`) are excluded from the score entirely.
- `TIMEOUT` mutants count as *not killed* — a mutant that makes your tests hang drags the score down instead of being silently forgiven.
- An empty mutation set scores `100`.

## Reading results

Per mutant, turtles reports `path:line:column`, `original -> replacement`, and its operator group:

- comparisons: `== ↔ !=`, `> → <`, `< → >`, `>= → <`, `<= → >`
- boolean logic: `&& ↔ ||`
- arithmetic: `+ ↔ -`, `* ↔ /`, unary `-x → +x`
- boolean literals: `true ↔ false`
- conditions: whole `if` conditions → `true` or `false`

Outcome classification:

- **KILLED** — `moon check` succeeded and `moon test` failed.
- **SURVIVED** — both commands succeeded; tests did not detect the change.
- **TIMEOUT** — checking or testing exceeded the configured timeout.
- **UNVIABLE** — `moon check` rejected the mutated source.

After the summary counts, every `SURVIVED`/`TIMEOUT` mutant is reprinted under `Mutants needing attention:` so the actionable list is at the end of the output.

Every run writes a schema-`2` report and per-survivor unified diffs to `<dir>/.turtles/` (which git-ignores itself): `report.json` plus `survivors/<id>.diff` for each surviving or timed-out mutant. The report adds stable mutant `id`s (FNV-1a over path + byte offsets + original + replacement + group), per-phase baseline durations (`baseline_check_ms`/`baseline_test_ms`), `test_scope`, a `files` fingerprint map, `skipped_files`, and `reused` counts:

```json
{
  "schema": 2,
  "module": "/abs/path",
  "turtles_version": "0.2.0",
  "moon_version": "moon 0.1.20260920 (914d7da 2026-09-20) ~/.moon/bin/moon",
  "baseline_duration_ms": "216",
  "baseline_check_ms": "70",
  "baseline_test_ms": "146",
  "test_scope": "module",
  "mutants": [
    { "id": "m-e7ccdf47c3b8bc0b", "path": "math.mbt", "line": 3, "column": 5,
      "offset": 47, "end": 48, "group": "arithmetic",
      "original": "+", "replacement": "-", "outcome": "KILLED",
      "duration_ms": "202", "reused": false }
  ],
  "summary": { "killed": 6, "survived": 0, "timeout": 0, "unviable": 0,
               "reused": 0, "score": 100 }
}
```

`--output-dir <path>` relocates the report directory; `--json` additionally writes a plain report anywhere for CI. `--iterate` loads the previous `<output-dir>/report.json` and reuses `KILLED`/`UNVIABLE` outcomes for mutants whose file content hash and identity tuple are unchanged (marked `"reused": true`); `SURVIVED`/`TIMEOUT` mutants always re-run. Reuse is refused wholesale when the schema, turtles version, or moon version differ. `--affected` is opt-in test selection: it parses `moon test --dry-run` to learn the package graph and runs `moon test -p` on just the mutated package plus packages whose test targets transitively link it, falling back to a module-wide run whenever resolution is uncertain. An empty mutation set still produces a schema-2 report with `mutants: []`; `--list` never runs tests.

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

## Safety model

`turtles` never runs tests in the module's working tree. The module is copied into a temporary directory, excluding `.git`, `target`, `_build`, `.mooncakes`, `.moon`, and `node_modules`. The copy keeps the caller's read/write/execute permissions on files and directories and recreates symlinks that resolve inside the module as links; symlinks that point outside the module are dereference-copied so writes cannot escape the workspace, and dangling links are a hard error.

The first copy is a pristine `reference` tree, snapshotted before any test executes. The baseline runs `moon check` and `moon test` on a disposable `baseline` copy of that reference — a failure there is a setup error (exit `2`), not a mutant outcome — so state written by the baseline cannot leak into mutants either. Each mutant then runs in one of `jobs` persistent `worker-N` workspaces copied once from `reference`: the mutation is written in place, classified, and the workspace is swept back to its manifest snapshot — recorded bytes are restored and any file the snapshot did not contain is deleted — so state written by earlier runs (sentinels, caches, generated files) cannot leak into later classifications, and mutant order cannot change results. `_build` stays warm inside each workspace, which is where most of the speedup comes from. This holds under `--jobs N` as well: workers share the read-only `reference` and never share a workspace. The temporary directory is removed when the run finishes.

Nested MoonBit modules — child directories carrying their own `moon.mod`/`moon.mod.json` — are excluded from discovery: the root module's `moon test` cannot reach their code, so their mutants would falsely survive.

On Windows, symlinks require privilege elevation and are dereference-copied instead of recreated.

## Implementation notes

`turtles` itself is a native MoonBit executable. The CLI, configuration parser, mutation discovery/application, temporary-workspace handling, subprocess execution, timeout handling, bounded parallelism, classification, and JSON reporting are all written in MoonBit. There is no Rust or Cargo implementation.

The project currently uses:

- `moonbitlang/async` for subprocess execution, cancellation, timing, the worker-pool task group, and async filesystem operations
- `moonbitlang/parser@0.4.0` for syntax-aware mutation candidate discovery
- `moonbitlang/x` for native path/system support
- `moon check` and `moon test` for mutant classification

Comments, strings, character literals, test files (`*_test.mbt`, `*_wbtest.mbt`), generated/build directories, and function arrows are excluded by syntax rather than lexical heuristics. Candidate discovery is driven by the pinned experimental parser AST; parser diagnostics abort discovery instead of triggering a lexical fallback. The unstable API is confined to `cmd/turtles/scanner.mbt`; see `docs/moonbit-parser.md`.

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

The real fixture E2E also validates schema-2 JSON report generation, deterministic ordering under `--jobs`, and `--fail-under` exit codes.

## Planned follow-ups

JUnit reports, richer survivor context, and smarter default test selection are still open. Mooncakes publishing is planned — pending the first publish tracked in `issues/open/2026-09-30-mooncakes-cli-distribution.md`; prebuilt release binaries remain out of scope. `moon install` from the git URL is the verified install path today.
