# PBT survivor analysis: property suggestions, differential witness, amplification

- Status: open (2026-09-29)
- Origin: residual P2 scope of [`../done/20260929-moonbit-idioms-and-pbt-integration.md`](../done/20260929-moonbit-idioms-and-pbt-integration.md)
- Builds on: #18 (structured oracle, `killed_by`), #19 (`body`, skip markers), #20 (`--emit-regressions`), #21 (visibility split), #22 (self-tests)
- Affected area: `cmd/turtles/` (runner, report, a new survivor-analysis module, main/config), `fixtures/pbt`, `README.md`

## Problem

turtles now tells users *which* test killed a mutant and keeps QuickCheck
counterexamples, but `SURVIVED` is still a single opaque bucket. A survivor may
be a real gap, an equivalent mutant, or a gap that the existing properties would
catch with more samples. MoonBit's built-in QuickCheck can separate these cases
automatically, which cargo-mutants cannot do for Rust.

## Scope

This issue is the **normative contract** for the P2 implementation. The P2
sections of the done record are historical rationale / original design only;
where the two differ, this issue wins.

All three analyses are opt-in. A default run (no new flags) performs none of
them and keeps the existing verdict and JSON semantics.

1. **Survivor → property suggestions.** For survivors whose parameter and
   return types have `Arbitrary + Shrink + Debug` instances, write
   `<output>/properties/<mutant-id>.mbt` skeletons chosen by signature shape
   (idempotence/involution for `(A) -> A`, commutativity/associativity for
   `(A, A) -> A`, round-trip for `encode`/`decode`-style pairs, otherwise a
   `@quickcheck.check` stub over the parameter tuple). Files only; user tests are
   never edited. Enabled only by `--emit-properties` (named like
   `--emit-regressions`); without it no `properties/` files are written.
2. **Differential witness.** Enabled only by `--pbt-witness` (named like
   `--pbt-amplify`). Without the flag turtles runs no witness analysis,
   generates no witness QuickCheck test or manifest import, and adds no
   `witness` / `witness_skipped` field. With the flag, for a surviving top-level function `f` with
   Arbitrary parameters and `Eq + Debug` result, generate inside the temporary
   workspace the original body as `f__turtles_orig`, the mutated `f`, and a
   white-box `@quickcheck.check(args => f(args) == f__turtles_orig(args))`.
   Each eligible survivor gets `witness`: the counterexample when falsified (observable
   mutant, real gap), or `none` ("possibly equivalent") within the budget.
   Requirements:
   - **Self-contained import.** The generated test must not assume the
     project already uses PBT. Even core QuickCheck needs an explicit package
     import, so in the temporary workspace only, add
     `"moonbitlang/core/quickcheck" for "wbtest"` to the target package's
     `moon.pkg` (or the `moon.pkg.json` equivalent) when missing, and restore
     the manifest together with the source after the witness run.
   - **Recursive functions.** Copying only `f`'s original body is not an
     original implementation when `f` is recursive or mutually recursive:
     calls inside the clone still reach the mutated `f`, so the comparison is
     against a hybrid and may wrongly yield `witness: none`. The first
     implementation excludes functions in a recursive SCC of the package call
     graph (no `witness` field, reason recorded, e.g.
     `witness_skipped: "recursive"`). Cloning the SCC with rewritten recursive
     references is a later extension.
3. **Property amplification.** `--pbt-amplify <N>`: for survivors only, re-run
   the property tests with `max_success` × N and additional seeds by rewriting
   `quick_check*` / `check` arguments in the temporary workspace. A mutant killed
   only after amplification is `KILLED` with `amplified: true`. Without the
   flag no re-run happens and no `amplified` field is written.

## Target selection

When `--target <TARGET>` (see `2026-09-30-target-aware-mutation-testing.md`)
is given, all three analyses follow the same target semantics as the verdicts:

- Every Moon invocation they make (witness runs, `--pbt-amplify` re-runs)
  goes through the target-aware Moon command helper (`moon_args`), so the
  current `--target` is always forwarded. No analysis builds its own
  unqualified `moon test`. Without `--target`, the existing no-target
  command lines are used.
- Target-inactive mutants get no suggestion, witness or amplification.
- `witness`, suggestions and `amplified: true` results belong to the same
  target identity as the mutant's verdict, `killed_by` and counterexample.
- `--iterate` never reuses a witness, suggestion or amplified verdict from a
  prior report with a different target.

## Remaining gaps and open questions

- Regression templates from #20 carry the counterexample only as comments.
  When a differential witness exists, a template could contain an executable
  call plus `debug_inspect`, because the witness input is produced from typed
  arguments rather than parsed from text.
- `score_public` is vacuous for executable packages (e.g. `cmd/turtles`
  itself, which has no `pub` declarations). Consider reporting the split only
  when both buckets are non-empty, or documenting this.
- Should `body` become a default group once the UNVIABLE rate is measured on
  real modules (`moonbitlang/x`, `f4ah6o/duckdb.mbt`)?
- Should suggestions use the extended `moonbitlang/quickcheck` (`@laws`,
  FEAT), or stay core-only to avoid a dependency?

## Acceptance criteria

- [ ] `--emit-properties` writes suggestion files for eligible survivors; no writes outside the output directory.
- [ ] With `--pbt-witness`, eligible survivors get `witness` (or a `witness_skipped` reason); falsified and not-falsified cases covered on `fixtures/pbt`.
- [ ] Without `--pbt-witness`, no witness test or manifest import is generated and no `witness` / `witness_skipped` field appears.
- [ ] Witness runs compile in a fixture with no QuickCheck import, and the manifest is restored afterwards.
- [ ] Recursive and mutually-recursive functions are excluded from witnesses with a recorded reason.
- [ ] `--pbt-amplify <N>` re-runs properties only for survivors and marks `amplified: true` kills.
- [ ] Default runs (no new flags) produce identical verdicts and JSON on existing fixtures. "Additive" applies only to opt-in runs: the default JSON does not change.
- [ ] Fixture E2E covers both a default run and runs with each of `--emit-properties`, `--pbt-witness` and `--pbt-amplify <N>`.
- [ ] With `--target`, witness / amplification runs forward the target and skip target-inactive mutants; `--iterate` does not reuse PBT analysis results across targets.
- [ ] README documents `--emit-properties`, `--pbt-witness`, `--pbt-amplify` and the new fields.

## Verification plan

```sh
git diff --check
moon fmt --check
moon check --target native --deny-warn
moon test --target native
moon -C fixtures/basic test
moon -C fixtures/isolation test
moon -C fixtures/empty test
moon -C fixtures/pbt test
moon -C fixtures/body test
turtles --dir fixtures/pbt
turtles --dir fixtures/pbt --emit-properties --pbt-witness --pbt-amplify 4
turtles --dir .   # self-application
```
