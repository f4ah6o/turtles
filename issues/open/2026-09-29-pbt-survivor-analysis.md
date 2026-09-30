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
   `--emit-regressions`); without it no `properties/` files are written and
   the `properties/` directory is not touched.
   Artifact lifecycle (same model as the `regressions/` writer):
   - Each run with `--emit-properties` builds the live set from the current
     run's final survivors (see "Execution order") and writes
     `properties/<mutant-id>.mbt` for each.
   - Every generated file starts with a fixed marker line
     (`// turtles: generated property suggestion`) followed by the target
     that produced it (`// target: native`, or `// target: none` without
     `--target`).
   - After writing, turtles removes `.mbt` files in `properties/` that carry
     the marker but are not in the live set. Files without the marker
     (user-created or user-edited with the marker removed) are never deleted.
   - The report lists the live files under a top-level `properties` array,
     next to the report's `target`. Only files in that list are results of
     the current run.
2. **Differential witness.** Enabled only by `--pbt-witness` (named like
   `--pbt-amplify`). Without the flag turtles runs no witness analysis,
   generates no witness QuickCheck test or manifest import, and adds no
   `witness` / `witness_skipped` field. With the flag, for a surviving top-level function `f` with
   Arbitrary parameters and `Eq + Debug` result, generate inside the temporary
   workspace the original body as a collision-free helper `f__turtles_orig`
   (see "Collision-safe generated identifiers"), the mutated `f`, and a
   white-box `@quickcheck.check(args => f(args) == f__turtles_orig(args))`.
   Each eligible survivor gets `witness`: the counterexample when falsified,
   or `none` ("possibly equivalent") within the budget. A falsified witness
   is evidence that the mutant is observable only under the eligibility rules
   below; it is not reported for functions outside them.
   Requirements:
   - **Soundness boundary (effects).** Calling the mutated `f` and
     `f__turtles_orig` one after the other in one process only compares them
     when neither call can observe state changed by the other, or by time,
     randomness or I/O. The baseline determinism guard does not cover this,
     because the interference happens between the two calls inside the
     generated test. The first implementation therefore uses a conservative,
     syntactic eligibility check over `f` and every function it reaches in
     the module's call graph (the same graph used for the recursive-SCC
     check):
     - every parameter and the result are immutable value types: `Bool`,
       integer / floating types, `Char`, `Byte`, `String`, and tuples /
       `Option` of these (no `Array`, `Map`, `Ref`, `Bytes` buffers or
       structs with `mut` fields that the callee could modify);
     - no reference to a top-level `let` binding, other than one whose type
       is itself an immutable value type as above;
     - no assignment to a field or index of a non-local value;
     - no `async` function and no call to a function outside the module,
       except an explicit allowlist of pure `moonbitlang/core` packages kept
       in the implementation (for example `@math`, `@string`, `@char`,
       `@int`, `@option`, `@tuple`); `@random`, `@env`, `@fs`, `@time` and
       any FFI (`extern`) are never allowlisted;
     - calls through closures, trait objects or trait-method dispatch count
       as unknown.
     A function that fails any rule, or that the check cannot decide, is
     not eligible: it gets `witness_skipped: "effects-unknown"` and no
     `witness`. As a final guard the generated test first checks
     `f__turtles_orig(args) == f__turtles_orig(args)` for each input; if that
     fails, the result is `witness_skipped: "nondeterministic"`. An
     unsupported or unsafe function never gets `witness: none`; `none` means
     only "eligible and not falsified within the budget". Evaluating each
     side in an isolated process to cover effectful functions is a later
     extension and must define its own soundness argument.
   - **Target applicability of the harness.** `f__turtles_orig` and the
     generated `test` block are appended to the temporary copy of the source
     file that defines `f`, not to a separate test file. They therefore have
     exactly the file-level `targets` applicability that Moon already gives
     `f`, so a `--target all` witness run compiles the harness only for the
     backends where `f` exists. turtles does not reimplement Moon's target
     conditions. Functions guarded by declaration-level `#cfg(...)` are
     skipped with `witness_skipped: "cfg"` until declaration-level cfg is
     supported (target-aware issue, "Follow-up after P0").
   - **Self-contained import.** The generated test must not assume the
     project already uses PBT. Even core QuickCheck needs an explicit package
     import. Because the harness lives in a regular source file, in the
     temporary workspace only, add `"moonbitlang/core/quickcheck"` to the
     package's regular imports in `moon.pkg` (or the `moon.pkg.json`
     equivalent) when missing, and restore the manifest together with the
     source after the witness run. Outside tests this import is unused and can
     produce a warning; witness runs, like mutant runs, do not use
     `--deny-warn`, so the warning does not make the run UNVIABLE.
   - **Recursive functions.** Copying only `f`'s original body is not an
     original implementation when `f` is recursive or mutually recursive:
     calls inside the clone still reach the mutated `f`, so the comparison is
     against a hybrid and may wrongly yield `witness: none`. The first
     implementation excludes functions in a recursive SCC of the package call
     graph (no `witness` field, reason recorded, e.g.
     `witness_skipped: "recursive"`). Cloning the SCC with rewritten recursive
     references is a later extension.
   - **Collision-safe generated identifiers.** A valid module may already
     declare `<fn>__turtles_orig`, or any other helper/test name turtles picks;
     a collision turns an otherwise eligible survivor into a harness compile
     failure (UNVIABLE) instead of a witness result. Every identifier turtles
     injects — the cloned-original helper and the generated test name — is
     therefore chosen from a collision-free candidate set:
     - the base name embeds the mutant id (for example
       `<fn>__turtles_orig__mut0042` for the helper and
       `turtles witness mut-0042 <fn>` for the test), which already makes
       accidental collisions rare;
     - before injecting, turtles collects the target package's top-level
       symbol set from the parsed AST (the same pass that enumerates
       functions) and rejects a candidate that is taken;
     - on a taken candidate it retries with a numeric suffix
       (`<fn>__turtles_orig__mut0042_1`, `_2`, …) until the name is free.
     Collision handling never renames or edits user symbols: only turtles'
     own generated identifiers change. If a bounded retry budget (e.g. 16)
     finds no free name, the function gets `witness_skipped: "name-collision"`
     rather than a broken harness.
3. **Property amplification.** `--pbt-amplify <N>`: for survivors only, re-run
   the property tests with `max_success` × N and additional seeds by rewriting
   `quick_check*` / `check` arguments in the temporary workspace. A mutant killed
   only after amplification is `KILLED` with `amplified: true`. Without the
   flag no re-run happens and no `amplified` field is written.

## Execution order

All three analyses take survivors as input, and `--pbt-amplify` can turn a
survivor into `KILLED`. The order is fixed and independent of the order of
the flags on the command line:

1. Normal mutation classification.
2. `--pbt-amplify <N>` on the initial survivors.
3. Final outcomes are fixed: amplified kills become `KILLED` with
   `amplified: true`.
4. `--pbt-witness` on the final survivors only.
5. `--emit-properties` on the final survivors only.
6. The report and all artifacts (`properties/`, `regressions/`, survivor
   diffs) are generated from the final outcomes.

A mutant whose final outcome is `KILLED` (including `amplified: true`) has
no `witness` / `witness_skipped` field and no `properties/` file. Any
combination of the three flags gives the same result as running them in
this order.

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
- [ ] `--emit-properties` sweeps stale marker-bearing files in `properties/`, keeps files without the marker, and records the live list and target in the report.
- [ ] With all three flags, a fixture mutant that only amplification kills ends as `KILLED` with `amplified: true`, with no `witness` / `witness_skipped` field and no `properties/` file; changing the flag order changes nothing.
- [ ] A mutable-state fixture (a function reading and updating a top-level `Ref`, or taking a mutable argument) gets `witness_skipped: "effects-unknown"` and no false `witness`, even when the mutant survives.
- [ ] With `--pbt-witness`, eligible survivors get `witness` (or a `witness_skipped` reason); falsified and not-falsified cases covered on `fixtures/pbt`.
- [ ] Without `--pbt-witness`, no witness test or manifest import is generated and no `witness` / `witness_skipped` field appears.
- [ ] Witness runs compile in a fixture with no QuickCheck import, and the manifest is restored afterwards.
- [ ] Recursive and mutually-recursive functions are excluded from witnesses with a recorded reason.
- [ ] A fixture whose source already defines `<fn>__turtles_orig` still gets a witness result: the harness compiles without renaming the user's symbol (it retries its own identifier instead) and the survivor is not turned UNVIABLE.
- [ ] `--pbt-amplify <N>` re-runs properties only for survivors and marks `amplified: true` kills.
- [ ] Default runs (no new flags) produce identical verdicts and JSON on existing fixtures. "Additive" applies only to opt-in runs: the default JSON does not change.
- [ ] Fixture E2E covers both a default run and runs with each of `--emit-properties`, `--pbt-witness` and `--pbt-amplify <N>`.
- [ ] With `--target`, witness / amplification runs forward the target and skip target-inactive mutants; `--iterate` does not reuse PBT analysis results across targets.
- [ ] Target-switch and `--target all` witness cases pass in `fixtures/targets` (see the target-aware issue's fixture design).
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
