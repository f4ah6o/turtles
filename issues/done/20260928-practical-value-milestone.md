# Practical value milestone: warm workspaces, iterate mode, actionable survivors

- Status: open (2026-09-28)
- Origin: user milestone request (2026-09-28), baseline `33efbf8`
- Affected area: `cmd/turtles/` (runner, scanner, config, report, main), `fixtures/`, `README.md`

## Current state

Verified on `main` (`33efbf8`):

- `moon fmt --check`, `moon check --target native --deny-warn`, `moon test --target native` all pass; all three fixture baselines pass.
- Every mutant pays a **fresh full-tree copy plus a cold `moon check` + `moon test`** (`run_one_mutant` copies `reference` into `mutant-N`, classifies, deletes). `_build` never persists across mutants, so each mutant rebuilds the whole module from scratch.
- One unparseable `.mbt` file aborts the entire scan (`scan_source` fails hard; `moonbitlang/x` cannot even be scanned without `turtles.toml` excluding `time/zone.mbt`).
- `--timeout` is a flat 60 s per command regardless of how fast the project is.
- No resume: re-running after fixing a survivor re-pays the full cost of every already-killed mutant.
- Survivor output is a text recap + flat JSON rows; no per-mutant id, no diff artifact, no source context.

## Real-world benchmark (measured, 2026-09-28)

Host: 8-core Linux, `moon` nightly.

| project | scale | mutants | wall @ `--jobs 8` | per-mutant wall | result |
|---|---|---|---|---|---|
| turtles (self) | 1 pkg, ~13 src files | 322 | ~26 min | ~4.9 s | 271K / 37S / 12T / 2U, score 84.7% |
| moonbitlang/x | 14 pkgs, 87 src, 754 tests | 3,273 | ~3.0 h (projected) | ~3.2 s (uuid subset: 112 mutants in 5m57s) | uuid subset: 99K / 13S, score 88.4% |
| moonbitlang/parser (moon.work) | workspace, generated lexer/parser | n/a | baseline `moon test` alone = **85 s** | cold copy per mutant is infeasible | not run |
| moonbitlang/core (`strconv_uint.mbt`, `--affected --timeout-multiplier 2`) | ~60 pkgs, 7,819 tests | 50 | ~9.5 min | ~11 s | 18K / 32T — mutant in `internal/strconv` (hub pkg): `--affected` selects ~all packages; most timeouts are check-phase recompile bounds, not hangs |

Per-mutant cost decomposition on moonbitlang/x (serial): workspace copy ~1.2 s, cold `moon check` ~0.4 s, cold `moon test` ~6.5 s. Under `--jobs 8` contention the CPU cost per mutant is ~15-25 s.

**Warm-workspace measurement (same dir, stable path):** mutate `uuid/uuid.mbt` in place, `moon test -p moonbitlang/x/uuid` rebuild+run = **0.37 s**; warm full-module `moon test` = ~2.3 s. Killing `moon` with SIGKILL 50 ms into a build leaves `_build` recoverable — n2 rebuilds the interrupted tasks on the next run and still classifies the mutant correctly.

**Copy does not transfer `_build`:** moving a warmed tree to a new path rebuilds ~94 tasks anyway (path-sensitive build db), so the workspace must stay at a *stable path per worker* — reuse in place, not copy-per-mutant.

## Observed bottlenecks

1. **Cold-build-per-mutant** dominates: ~8 s serial / ~3.2 s parallel-wall on x; ~5 s on turtles; infeasible on parser. The fix is not faster copies — it is never copying again.
2. **Full-module `moon test` per mutant**: warm exec of all 754 x tests is ~2.3 s vs ~0.01 s for the affected package. Second-order once builds are warm.
3. **Single-file scan abort**: any file the bundled parser cannot read kills the whole run — blocks adoption on real codebases.
4. **Flat timeout**: every hang-mutant burns 60 s; on the self-run 12 timeouts ≈ up to 12 min of pure waste.
5. **No resume**: fixing survivors → full re-run.
6. **Survivor actionability**: `path:line:col + a -> b` requires manual file lookup; no diff artifact for CI review.

## `moon test --patch-file` investigation (decided: not usable as the engine)

Format verified against `moonbitlang/moonbit-compiler` (`src/patch.ml`): `{"drops":[{"file","index"}],"patches":[{"name","content"}]}`.

- `patches` **only add virtual files** — a same-name entry collides with the real file ("declared twice", error 4051). Whole-file mutation replacement is impossible.
- `drops` remove the *index-th top-level declaration* of a file — deleting decls, not editing expressions. turtles' operators mutate infix operators inside function bodies; drops cannot express that.
- Patch targets are suffix-scoped (`_test.json`→Blackbox, `_wbtest.json`→Whitebox, else under `moon test`→InlineTest) and `moon test --patch-file` requires `-p <PACKAGE>` — one package, one test target only. Downstream packages keep seeing the original `.mi`, so kills in dependent packages could never be observed.

Verdict: patch-file cannot apply whole-file mutations at the Source layer under `moon test`. Documented; not implemented.

## Correctness risks (chosen design)

Persistent workspaces trade "fresh copy" for "restore in place":

- *File restore*: only the mutant's file is ever mutated; exact original bytes are written back after each classification. `apply_mutation`'s existing guard (original text must sit at `[start,end)`) detects any restore corruption on the next mutant → workspace rebuilt once, then abort.
- *Stray files from test side effects*: after each mutant, entries not present in the workspace's setup manifest are deleted.
- *`_build` cross-mutant state*: n2 is content-keyed (`dirty_on_output`); interrupted/partial outputs rebuild on the next run (verified). Timeout-killed `moon` leaves no lock behind.
- *`--affected` missed-dependency edge → false SURVIVED*: opt-in flag; the package set is derived from moon's own `moon test --dry-run` plan (authoritative dep graph, includes `test-import`/`wbtest-import` edges); any resolution failure falls back to full-module `moon test`.
- *Hub packages*: a mutant in a package everything links (e.g. core `internal/strconv`) makes `--affected` select ~every package — no speedup, and each mutant's `moon check` must recompile all dependents. The check-phase timeout therefore scales off `max(baseline_check, baseline_test)`, not the warm check baseline alone (a >10s check on core is legitimate work, not a hang).
- *Timeout orphans*: killing a timed-out `moon` by pid leaves `moonc`/test-exe children running for hours (observed in dogfood). Mutants run moon under GNU `timeout --signal=KILL` (fresh process group, group-wide signal) when the binary probes present; the single-pid path remains as fallback.
- *`--iterate` stale reuse*: reuse limited to KILLED/UNVIABLE mutants whose **file content hash + identity tuple (path, offsets, original, replacement, group)** match a schema-2 report. Identity never keys on line numbers. Survived/Timeout always re-run. Report marks reused entries (`"reused": true`) and `summary.reused` so assumption is visible. Residual: a change in a *different* source/test file can in principle flip a reused outcome — the fingerprint fields (`files`, `moon_version`) make the assumption auditable, and deleting `.turtles/report.json` forces a clean run.

## Candidate improvements

1. Persistent per-worker workspaces (warm `_build`) — *selected*.
2. Per-file scan-failure isolation — *selected* (hard adoption blocker).
3. `--iterate` resume — *selected*.
4. `--timeout-multiplier` adaptive timeout — *selected*.
5. `--output-dir` report + survivor diff artifacts — *selected*.
6. `--affected` dependency-scoped `moon test -p` — *selected, opt-in (experimental)*.
7. `moon --patch-file` engine — *rejected* (cannot express whole-file source mutation; see above).
8. Coverage-guided mutant subsetting, cross-run result cache, `.mooncakes` preseed tuning — *deferred*.

## Selected scope (P0)

- **Warm workspaces**: `jobs` workspaces are copied once from `reference` and reused for every assigned mutant (mutate → classify → restore bytes → drop stray files). Fresh-copy path stays as `--fresh-workspaces` escape hatch? No — single code path; parity is enforced by the outcome-equivalence tests instead.
- **Scan isolation**: a file the parser rejects is skipped with a warning and listed in the report (`skipped_files`), not fatal.
- **`--iterate`**: reads `<dir>/.turtles/report.json` (schema 2); reuses KILLED/UNVIABLE for file-hash+identity-matched mutants (marked `reused`); reruns everything else.
- **`--timeout-multiplier <f>`**: per-phase timeout = `max(10 s, f × baseline phase duration)`; the check phase uses `max(baseline_check, baseline_test)` as its baseline since a mutant's recompile can dwarf the warm check. Overrides flat `--timeout` when set.
- **`--output-dir <d>`** (default `<dir>/.turtles`, self-gitignored): `report.json` + `survivors/<id>.diff` (unified hunk, ±3 context lines). Mutant `id` = `m-` + 16-hex FNV-1a of the identity tuple — stable across runs when the source is unchanged.
- **`--affected`**: per-mutant `moon test -p` restricted to the mutated package plus packages whose test targets transitively link it (from `moon test --dry-run`). Fallback to full-module test on any resolution failure. `moon check` stays module-wide for Unviable classification.
- Report schema → 2: adds `turtles_version`, `moon_version`, `baseline_check_ms`, `baseline_test_ms`, `test_scope`, `files` (path→hash), `skipped_files`, per-mutant `id`/`offset`/`reused`, `summary.reused`. All schema-1 fields unchanged.

## Explicitly deferred

- `moon --patch-file` mutation application (impossible semantics; see investigation).
- Making `--affected` the default (needs broader real-project validation of dep-graph completeness).
- Cross-run `_build` carry-over between separate turtles invocations (tmpdirs are per-run by design).
- Coverage-informed mutant subsetting / equivalent-mutant detection.
- README/release plumbing beyond documenting new flags.

## Acceptance criteria

- moonbitlang/x `uuid/` subset run reproduces identical outcomes (99K/13S) with warm workspaces; per-mutant wall drops ≥3x.
- `turtles --iterate` on the same tree reuses all KILLED/UNVIABLE mutants and only re-runs SURVIVED/TIMEOUT.
- A repo with one unparseable `.mbt` file completes the scan and reports it under `skipped_files`.
- Hang mutants under `--timeout-multiplier 3` classify as TIMEOUT in ~`max(10s, 3×baseline)` not 60 s.
- `.turtles/report.json` + `survivors/*.diff` are written; diffs apply contextually to the real file.
- `--affected` on `fixtures/` produces identical outcomes to full-module runs; on x it selects only the mutated package's dependents.
- All regression guarantees hold: no working-tree mutation, baseline/mutant isolation, deterministic ordering, timeout subprocess cleanup, temp cleanup, symlink/permission handling, JSON determinism, exit codes, `--fail-under`, installed-binary parity.

## Verification plan

- `git diff --check`, `moon fmt --check`, `moon check --target native --deny-warn`, `moon test --target native`.
- `moon -C fixtures/basic test`, `moon -C fixtures/isolation test`, `moon -C fixtures/empty test`.
- E2E: fixtures run; `--iterate` reuse on a real tree; `--affected` equivalence run on `fixtures/isolation` (needs a multi-package fixture — extend or accept turtles repo itself); timeout-multiplier run on a hang fixture.
- Unit: identity/fingerprint matching, diff hunk emission, dry-run plan parsing (snapshot fixture of captured plan text), arg validation, report schema-2 fields, restore-stray-file cleanup.
- Outcome equivalence: same project + same mutant set before/after → identical outcomes.
- Self-dogfood at `--jobs 8` at the end; survivors triaged as test-gap / equivalent / unobservable.
