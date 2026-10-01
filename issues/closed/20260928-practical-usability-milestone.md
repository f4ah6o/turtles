# Practical usability milestone: install, parallel workers, CI threshold, actionable results

- Status: closed (triaged 2026-10-02)
- Previous record: implemented (2026-09-28)
- Origin: user milestone request (2026-09-28), baseline `7a44bcc`
- Affected area: `cmd/turtles/` (config, runner, report, main, fs_ops), `fixtures/`, `README.md`, `.github/workflows/ci.yml`

## Current state

Verified on `main` (`7a44bcc`):

- Full suite green: `moon fmt --check`, `moon check --target native --deny-warn`, `moon test --target native` (72 tests), all three fixture baselines, fixture E2E.
- `moon install` works end to end for both a local path and the GitHub git URL:
  - `moon install ./cmd/turtles --bin DIR` produces a working 11 MB native binary.
  - `moon install https://github.com/f4ah6o/turtles.git cmd/turtles --branch main` installs the same binary from source.
- Self-scan scope today: `--dir .` discovers 289 mutants under `cmd/turtles/` **plus 12 under `fixtures/`** — nested modules are not excluded.

## User journeys

- A. Install and run like a normal CLI: `moon install <git-url> cmd/turtles [--tag vX.Y.Z]` then `turtles --help`, `turtles --version`, `turtles --dir .`.
- B. Bounded parallel execution: `turtles --dir . --jobs 4` finishes a real project scan in practical wall time.
- C. Gradual CI adoption: `turtles --dir . --fail-under 80` passes when the mutation score meets the bar even if survivors exist; setup failures still exit 2.
- D. A survivor report must be actionable enough to fix from `path:line:col`, `original -> replacement`, and operator group.

## Identified gaps (ranked)

1. No installable entry point documented — users must clone + `moon run`. **Fix: `moon install` is the official mechanism (verified); document it and add `--version`.**
2. `run_mutations` is strictly sequential; each mutant pays a full `moon check` + `moon test` (~200 ms+ on fixtures, tens of seconds on real modules). **Fix: worker pool bounded by `--jobs`.**
3. Exit code 1 on any survivor makes CI adoption all-or-nothing. **Fix: `--fail-under` score threshold.**
4. `collect_moonbit_files` descends into nested MoonBit modules (`fixtures/*/` with their own `moon.mod`). Their mutants can never be killed by the root module's `moon test`, producing guaranteed false survivors and wasted runs. **Fix: skip child directories that contain `moon.mod`/`moon.mod.json`.**
5. Survivor output ends in a scroll of interleaved progress lines; JSON has no operator-group field. **Fix: survivors recap + additive `group` field in JSON (schema stays 1).**

## P0 (this milestone)

- `--jobs <N>` (positive int, default 1 — no fake CPU auto-detection; no stable toolchain API exists). Worker pool bounded at N; results indexed by mutation order; per-mutant workspace isolation and timeout/cancel/cleanup preserved.
- `--fail-under <0..100>` (float allowed). Score below threshold → exit 1; at/above → exit 0 even with survivors. TIMEOUT remains in the viable denominator (counts as not-killed — conservative, documented). Without the flag: unchanged behavior.
- `--version` → `turtles 0.2.0` (kept in sync with `moon.mod` via test).
- Nested-module exclusion during source discovery.
- JSON report: additive `group` field per mutant; `schema` stays `1` (additive, backward compatible).
- Console: survivors/timeout recap block after the summary counts.
- README restructure: install → 30-second first run → usage → CI → results → config → safety → internals.
- Focused tests per test plan below; distribution smoke test from a clean directory on the installed artifact.

## P1 (only if cheap during implementation)

- `turtles.toml` at repo root scoped to `cmd/turtles/` as a hedge (nested-module skip makes this unnecessary).

## Non-goals (confirmed for this milestone)

- Test selection, JUnit, resume/retry, incremental/cached execution, mutation-operator expansion.
- GitHub Release prebuilt binaries — turtles needs `moon` at runtime anyway, so `moon install` (build-from-source) is sufficient and verified; release CI can't be verified without cutting a tag.
- Publishing to mooncakes.io (requires registry account/login).
- Cross-platform packaging beyond what `moon install` already provides on the host.
- Breaking JSON schema changes.

## Acceptance criteria

- `moon install https://github.com/f4ah6o/turtles.git cmd/turtles --branch main` → `turtles --help`, `turtles --version`, `turtles --dir <fixture>` all verified from a clean directory.
- `--jobs N`: validated `N > 0`; concurrency never exceeds N; results complete and ordered by discovery order, not completion order; baseline runs exactly once before mutants; `--jobs 1` behaves as before; timeout/cancel/cleanup intact.
- `--fail-under N`: `0..100` validated; `score >= N` → exit 0; `score < N` → exit 1; unset → legacy exit semantics; baseline/setup failure → exit 2 always.
- `--dir .` on this repo reports only `cmd/turtles` mutants (no `fixtures/` entries).
- Schema 1 JSON unchanged except additive `group` per mutant.
- All existing regression commands pass; new focused tests pass.

## Test plan

- Unit/wbtest: arg parsing & validation for `--jobs`, `--fail-under`, `--version`; `final_exit_code` matrix (score >, =, < threshold; timeout semantics; default compat); mutation-score math; pool bound/completeness/determinism with an injected classifier; nested-module skip; version constant matches `moon.mod`.
- E2E (run locally + mirrored in CI): fixture `--jobs 4` run; `--fail-under 50` on `fixtures/isolation` (score 50 → exit 0); installed-binary smoke test from `/tmp`.
- Self-dogfood: run turtles on its own `cmd/turtles` sources at `--jobs 8`, triage survivors near new concurrency/CLI/threshold code.

## Outcome (2026-09-28)

All P0 items implemented and verified. `moon install` (local path and git URL)
is the documented install mechanism; the installed binary passes
`--version`/`--help`/`--dir` smoke tests from a clean directory.

Self-dogfood at `--jobs 8` over `cmd/turtles` (326 mutants): 271 killed,
50 survived, 3 timeout, 2 unviable — score 83.6%. Survivor triage: the recap
selection logic was extracted to `needs_attention`/`describe_result` and is now
tested; remaining survivors are display-only text (progress counter, "met/NOT
met" line), defensive guards whose alternatives are unobservable
(`recursive=true` mkdir args under existing parents, scanner position
verification, runaway-loop step counters), or include-pattern no-ops. The 3
TIMEOUTs are real infinite-loop mutants in the TOML parser detected correctly.
