# Target-aware mutation testing for multi-backend MoonBit modules

- Status: open (2026-09-30)
- Origin: `f4ah6o/duckdb.mbt` dogfood review (2026-09-30), turtles baseline `598820c1`
- Affected area: `cmd/turtles/` (config, runner, plan, report, iterate, main), `fixtures/`, `README.md`
- Primary dogfood target: `f4ah6o/duckdb.mbt`

## Problem

turtles currently classifies every mutant with fixed commands:

```text
moon check
moon test
```

and `--affected` builds its dependency plan with:

```text
moon test --dry-run
```

There is no way to select a Moon backend. That is a correctness gap for real modules that use conditional compilation.

`f4ah6o/duckdb.mbt` is a concrete example. Its `src/moon.pkg` contains backend-specific files such as:

- `duckdb_native.mbt` / `duckdb_arrow_native.mbt` for native
- `duckdb_js.mbt` / `duckdb_arrow_js.mbt` for js
- wasm / wasm-gc fallback files
- common source files with no `targets` restriction

Moon's current build model selects files by backend. A file omitted from `targets` is active for all conditions, while files listed in `targets` are compiled only when the selected backend satisfies their condition. `moon check` and `moon test` both accept `--target`; `--target all` expands across the standard backends.

With the current turtles behavior, a mutant can be discovered in a backend-specific file but never compiled by the backend chosen implicitly by Moon. Such a mutant can be reported as `SURVIVED` even though no test actually observed the mutated code.

A second correctness risk is `--iterate`: target selection is not recorded today, so a future target-aware implementation must not reuse a KILLED/UNVIABLE verdict produced under a different backend.

## Goals

1. Let users select the Moon backend turtles uses for baseline, check, test, and `--affected` planning.
2. Exclude mutants in files Moon does not compile for that explicit target instead of treating them as survivors.
3. Keep Moon itself as the authority for conditional file selection; do not implement a second parser/evaluator for `moon.pkg` target expressions.
4. Make target selection part of the report and `--iterate` reuse identity.
5. Preserve current behavior when `--target` is omitted.
6. Validate the feature on `f4ah6o/duckdb.mbt`.

## Non-goals for this milestone

- Evaluating declaration-level `#cfg(...)` inside an otherwise active file.
- Arbitrary target subsets in one invocation (for example native+js but not wasm).
- Merging several separately-produced target reports into one score.
- Changing Moon's conditional-compilation semantics.
- Making `duckdb.mbt` itself depend on turtles or adding turtles configuration to it.

Declaration-level `#cfg` should be tracked separately: the dry-run plan can prove that a file is active, but not that every declaration inside that file is active for the selected backend.

## CLI contract

Add:

```text
--target <TARGET>   Select the Moon backend used for mutation testing
```

Examples:

```sh
turtles --dir . --target native
turtles --dir . --target js
turtles --dir . --target all
turtles --dir . --target native --affected
```

Implementation rules:

- Store the value as `Config.target : String?`.
- No `--target` keeps the current command lines and current discovery semantics.
- With an explicit target, append `--target <TARGET>` consistently to every relevant Moon invocation.
- Do not maintain a turtles-owned list of valid backend names. Reject only a missing/empty CLI value; let the installed Moon version validate the target. This avoids turtles lagging behind Moon when target names evolve.
- Repeating `--target` is an argument error in P0.
- `--target all` is the supported way to ask Moon to exercise all of its standard backends in one turtles run.

## Command propagation

Introduce one small helper that builds Moon arguments so target forwarding cannot drift between call sites, for example conceptually:

```text
moon_args(["check"], target)
moon_args(["test"], target)
moon_args(["test", "--dry-run"], target)
```

The selected target must be applied to:

1. pristine baseline `moon check`
2. pristine baseline `moon test`
3. every mutant `moon check`
4. every mutant `moon test`
5. `moon test --dry-run` used for `--affected`
6. the dry-run used to discover which source files are active for an explicit target

Package narrowing remains additive:

```text
moon test --target native -p some/package
```

not a separate execution path.

## Active-source discovery

Do **not** parse `moon.pkg` / `moon.pkg.json` target expressions in turtles.

Reuse the existing dry-run plan mechanism and extend it to collect source files from Moon's own `moonc build-package ...` command lines.

A current Moon dry-run emits build-package commands shaped like:

```text
moonc build-package ./foo.mbt ./bar.mbt ... -pkg ... -target native ...
```

Those positional source paths are the authoritative set that Moon selected after evaluating:

- package/module `supported_targets`
- file-level `targets`
- `preferred_target` / explicit `--target`
- the selected backend's package graph

### Plan structure

Refactor the current `TestPlan` parsing so one dry-run can provide both concerns:

```text
MoonPlan
  active_sources: Set[normalized module-relative path]
  affected_test_plan: TestPlan data
```

The dependency graph already parsed for `--affected` should remain fail-closed exactly as it is today.

For source collection:

- inspect `moonc build-package` lines only
- collect positional `*.mbt` inputs belonging to the module tree
- normalize `./`, separators, and absolute paths to module-relative paths
- ignore generated files under `_build`
- test files can be present in the plan but remain excluded by the scanner's existing test-file rule
- union source paths across all emitted backend plans when `--target all` is used

If plan parsing cannot determine the active-source set reliably for an explicit target, fail the run as a setup error (exit 2). Falling back to “all discovered files are active” would reintroduce false survivors.

## Mutant filtering

The scanner can continue discovering syntactic mutations as it does today.

When `--target` is explicit:

1. build the target-aware dry-run plan in the temporary reference workspace
2. partition discovered mutants into:
   - **active**: `mutation.path` is present in `active_sources`
   - **target-inactive**: the file is absent from `active_sources`
3. classify only active mutants
4. exclude target-inactive mutants from the mutation score
5. report the excluded count/files explicitly

This keeps “not compiled for this backend” distinct from:

- `SURVIVED`: compiled and tests passed
- `UNVIABLE`: selected source was compiled, but the mutation made `moon check` fail
- `TIMEOUT`: selected source could not be classified within the bound

### Temporary-workspace constraint

Do not run target-plan discovery in the user's working tree.

Today `load_test_plan` intentionally runs inside the pristine temporary reference. Preserve that safety property because even a dry-run can involve dependency/build-system setup outside turtles' control.

Refactor workspace preparation so the same reference tree can be used for:

- target active-source discovery
- optional `--affected` dependency planning
- baseline validation
- worker creation

For `--list --target ...`, create the same temporary reference and run only the dry-run plan; do not execute baseline tests.

## Reporting

Bump report schema from 2 to 3 because classification semantics now depend on target selection.

Add at least:

```json
{
  "schema": 3,
  "target": "native",
  "inactive_mutants": 12,
  "inactive_files": [
    "src/duckdb_js.mbt",
    "src/duckdb_arrow_js.mbt"
  ]
}
```

Rules:

- `target: null` when the option was omitted.
- `inactive_mutants` is excluded from `viable` and therefore from the mutation score.
- `inactive_files` is sorted and deterministic.
- classified mutant rows remain the existing KILLED/SURVIVED/TIMEOUT/UNVIABLE set; do not invent a fifth outcome for target-inactive code.
- console summary prints the target and inactive count when an explicit target is used.
- survivor diff artifacts are generated only for classified active mutants.

The report's `test_scope` remains about module-wide vs `--affected`; target is a separate field.

## `--iterate` correctness

Target selection is part of prior-report compatibility.

A prior verdict is reusable only when all existing reuse conditions match **and**:

```text
prior.target == current.target
```

Examples that must not reuse each other:

- no explicit target vs `--target native`
- `--target native` vs `--target js`
- `--target js` vs `--target all`

Schema-2 reports are not reusable after this change.

The existing manifest fingerprints remain valuable because changes to `moon.mod` / `moon.pkg` can alter target applicability. Target equality is an additional guard, not a replacement for file fingerprints.

## `--affected` interaction

`--affected` must derive its package graph from the **same target-aware dry-run** used for active-source discovery.

Do not do this:

```text
active sources: moon test --dry-run --target native
affected graph: moon test --dry-run
```

because the package/test graph can differ by backend.

One dry-run should feed both active-source and dependency-plan data wherever possible.

If dependency resolution is incomplete, preserve the current safe fallback to a target-aware full-module test:

```text
moon test --target <TARGET>
```

not to an unqualified `moon test`.

## Interaction with PBT features

Since this issue was written, #18–#21 added `killed_by` attribution, property
counterexamples, `--emit-regressions` templates and visibility split scores.
These are per-run results and must be keyed by the selected target like the
verdicts: a prior report's `killed_by` is reused only when the target matches,
and regression templates / counterexamples are recorded with the target that
produced them.

The planned opt-in PBT analyses (`--emit-properties`, `--pbt-witness`,
`--pbt-amplify <N>`, specified in `2026-09-29-pbt-survivor-analysis.md`) follow
the same rules:

- their Moon invocations (witness runs, amplification re-runs) are built with
  the same `moon_args` helper, so the current `--target` is always forwarded;
  without `--target`, no-target semantics are unchanged
- target-inactive mutants get no suggestion, witness or amplification
- `amplified: true`, `witness` and suggestions belong to the same target as
  the verdict, `killed_by` and counterexample they refine
- `--iterate` does not reuse any of them across a target change

## Fixture design

Add a small multi-target fixture, for example `fixtures/targets`, with:

- one common implementation file
- one js-only file
- one native-only file
- target-specific tests that kill a simple arithmetic/comparison mutant in the matching file
- `moon.pkg` file-level `targets` entries

Required E2E assertions:

### native

```sh
turtles --dir fixtures/targets --target native --list
```

- lists common + native mutations
- does not list js-only mutations

A full native run classifies the common/native mutants and reports js-only candidates as target-inactive.

### js

```sh
turtles --dir fixtures/targets --target js --list
```

- lists common + js mutations
- does not list native-only mutations

### all

```sh
turtles --dir fixtures/targets --target all --list
```

- union contains common + native + js mutations
- no file that is active in one of those emitted backend plans is lost

### iterate

Run native, then run js with `--iterate` against the same output directory. Zero native verdicts may be reused by the js run.

### PBT analysis (once the PBT survivor-analysis issue is implemented)

With `--target native --pbt-witness --pbt-amplify <N>`, js-only mutants get no
witness or amplification, and every Moon command the analyses run carries
`--target native`.

## duckdb.mbt dogfood acceptance

After the fixture gates pass, validate against `f4ah6o/duckdb.mbt`.

Expected behavior:

1. `--target native --list`
   - common source appears
   - native source appears
   - js-only source does not appear as an active mutant
2. `--target js --list`
   - common source appears
   - js source appears
   - native-only source does not appear as an active mutant
3. `--target all --list`
   - active-source union follows Moon's own dry-run output
4. entries whose `moon.pkg` condition can never match any selected backend are reported as target-inactive rather than becoming false survivors
5. a full run on any target is attempted only when that target's external runtime requirements are installed (for example native DuckDB libraries or JS runtime dependencies)

The dogfood step should not modify `duckdb.mbt`; it validates turtles against a real multi-backend consumer.

## Acceptance criteria

- `--target` is parsed, documented, and propagated to baseline/check/test/dry-run commands.
- Explicit-target runs never classify a mutant from a file absent from Moon's target-specific dry-run source set.
- Target-inactive mutants are visible in console/reporting and excluded from score.
- `--affected` and active-source discovery use the same target-aware plan.
- `--iterate` cannot reuse across target changes.
- PBT analyses (witness, suggestions, amplification) never cross the selected target boundary.
- report schema is 3 and remains deterministic.
- `--list --target ...` filters by target without running tests.
- no-target invocation preserves current behavior and output semantics apart from the schema/version changes required by implementation.
- existing safety guarantees remain: no working-tree mutation, temporary reference isolation, deterministic ordering, worker restore, timeout process cleanup, and survivor diff behavior.
- all existing tests pass plus the new multi-target fixture E2E.
- `duckdb.mbt` target-specific listing behaves as described above.

## Verification plan

Unit / white-box:

- argument parsing: missing target, one target, repeated target
- Moon command arg construction
- dry-run source-path normalization (relative and absolute)
- `--target all` union parsing
- active/inactive mutant partitioning
- report schema-3 fields and deterministic ordering
- prior-report target mismatch blocks `--iterate` reuse
- `--affected` plan retains target selection

Repository gates:

```sh
git diff --check
moon fmt --check
moon check --target native --deny-warn
moon test --target native
moon -C fixtures/basic test
moon -C fixtures/isolation test
moon -C fixtures/empty test
```

New E2E:

```sh
turtles --dir fixtures/targets --target native --list
turtles --dir fixtures/targets --target js --list
turtles --dir fixtures/targets --target all --list
turtles --dir fixtures/targets --target native
turtles --dir fixtures/targets --target js
```

Dogfood (environment permitting):

```sh
cd /path/to/duckdb.mbt
turtles --dir . --target native --list
turtles --dir . --target js --list
turtles --dir . --target all --list
```

## Follow-up after P0

- declaration-level `#cfg(target=...)` applicability
- platform-aware native cfg (`#cfg(platform=...)`)
- arbitrary target subsets and report aggregation
- target-specific default output directories if repeated single-target runs become a common workflow
