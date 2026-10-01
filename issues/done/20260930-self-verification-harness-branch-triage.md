# Branch triage: feat/self-verification-harness

- Status: done (2026-09-30)
- Scope: `origin/feat/self-verification-harness` (last commit 2026-09-27), triaged against `main`.
- Context: the branch has **no common history** with `main` — its root
  commit `4bb83c9` is a reconstructed baseline. It was triaged commit by
  commit and *not* merged; genuinely missing value was ported into `main`
  instead. The branch can be deleted once this lands.

## Commit-by-commit triage

| commit | subject | verdict |
|---|---|---|
| `4bb83c9` | chore: record reconstructed remote main baseline | **dropped** — bookkeeping commit anchoring the reconstructed baseline; no content |
| `2de828c` | feat: use parser AST for mutation discovery | **already on main** — `AstCandidateVisitor` drives `@parser.parse_string` discovery (`cmd/turtles/scanner.mbt`, `moonbitlang/parser@0.4.0`); `docs/moonbit-parser.md` documents the boundary table the branch added |
| `574b131` | feat: add if condition structural mutations | **already on main** — `visit_Expr_If` records `cond → true` / `cond → false` range replacements; see `issues/done/20260927-structural-if-operator-group.md` |
| `021da98` | test: cover if condition structural mutations | **already on main** — `fixtures/basic` `choose()` + tests, `scanner_wbtest` coverage, and the CI fixture assertions all exist |
| `f7f8e35` | feat: add self-verification harness | **split** — see below |
| `b051b3e` | fix: update parser ident pattern | **already on main** — `LongIdent::Ident(name~)` at `scanner.mbt:212,268,453,523` |
| `b7e4bfb` | fix: separate conditional mutation group | **already on main** — `OperatorGroup::Condition` in `types.mbt`, attributed by the scanner, gated by `operator_enabled` |
| `2321995`, `0286edd` | style commits | **dropped** — formatting-only |

## f7f8e35 detail (the harness commit)

**Ported:**

- `scripts/self_e2e.sh` — black-box e2e of the built binary's JSON report
  against `fixtures/basic`, including the nested non-existent `--json`
  directory case. Adapted to main's schema-2 report (assertions no longer
  reference `gates`/`gate`, which do not exist on main; now also asserts
  `killed == 6`).
- Root `turtles.toml` — checked-in self-run config, `include =
  ["cmd/turtles/"]`. The `gates` key was **not** ported (the config parser
  on main does not support it).
- `docs/verification.md` — rewritten for main: unit + `*_pbt_wbtest`
  QuickCheck layers, self-mutation via root `turtles.toml`, binary e2e, and
  the survivor-triage discipline (equivalent / test gap / unobservable)
  carried over from the branch doc.
- CI self-dogfood — `--dir . --list`, a bounded self-mutation run gated on
  `cmd/turtles/fingerprint.mbt` (3 deterministic kills), and
  `sh scripts/self_e2e.sh`. The branch's report.mbt/main.mbt self-mutation
  steps were adapted: bounding to fingerprint.mbt keeps the gate fast on a
  much larger mutant set than the branch had.
- Config string-array round-trip property — the one QuickCheck property in
  the branch's `quickcheck_wbtest.mbt` not covered by main's `*_pbt_wbtest`
  suite; landed as `cmd/turtles/config_pbt_wbtest.mbt` (unpinned seed,
  matching main's convention).

**Dropped:**

- The `Gate`/multi-gate pipeline (`gates` key in `turtles.toml`, custom
  `name=command` gates, builtin `prove` gate, per-mutant `gate`
  attribution, `gates` array in the report, `--prove` flag). Reason:
  porting it requires reworking `classify_mutant` (`runner.mbt`) and the
  report schema (`report.mbt`) — exactly the code the in-flight
  target-aware session
  (`issues/open/2026-09-30-target-aware-mutation-testing.md`, schema 3) is
  changing, and the branch's design predates `--target`: builtin gate
  commands would need to forward the selected backend and join the
  `--iterate` reuse identity. Worth revisiting as a follow-up once
  target-aware lands; the e2e script and docs are written so they still
  work when per-mutant command gates exist.
- `exit_code_for` helper — main's `final_exit_code` (with `--fail-under`)
  is a superset.
- QuickCheck properties for `count_outcomes`, `mutation_score`,
  `source_byte_boundaries`, `apply_mutation` — already covered by main's
  unit tests and `scanner_pbt_wbtest.mbt` properties.
- `moon prove` documentation — gate not ported (see above); the branch doc
  itself marks its Why3 requirement as unverified.

**Already on main (from the same commit):**

- Schema-2 JSON report — main's schema 2 is richer than the branch's
  (`group`, `visibility`, `killed_by`, `reused`, `test_scope`,
  `skipped_files`, `regressions`, version/fingerprint fields).
- `Mutation` struct field layout the harness tests assumed.
