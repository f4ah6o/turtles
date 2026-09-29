# MoonBit-idiomatic mutation testing with deep QuickCheck (PBT) integration

- Status: P0/P1 implemented (2026-09-29); P2 tracked in [`../open/2026-09-29-pbt-survivor-analysis.md`](../open/2026-09-29-pbt-survivor-analysis.md)
- Origin: user direction (2026-09-29), turtles baseline `76bfd78`
- Affected area: `cmd/turtles/` (types, scanner, runner, report, config, main), `fixtures/`, `README.md`
- References:
  - cargo-mutants concept: <https://github.com/sourcefrog/cargo-mutants>
  - MoonBit agent guide: <https://github.com/moonbitlang/skills/tree/master/skills/moonbit-agent-guide>
  - MoonBit skills index: <https://github.com/moonbitlang/skills/tree/master/skills>
  - `moonbitlang/quickcheck` (0.15.0): <https://github.com/moonbitlang/quickcheck>
  - QuickCheck tutorial part 1: <https://www.moonbitlang.com/pearls/quickcheck-tutorial-part-1>

## Implementation record

This file is kept as the design record. The P0/P1 scope and self-application
(G7) landed in:

- #18 — structured oracle (`--test-failure-json`, never `--update`/`-u`),
  `killed_by` / `kills_by_kind` / `property_only_kills`, `attribution:
  "unavailable"` fallback, baseline determinism guard, `fixtures/pbt`,
  `--iterate` preserving `killed_by`.
- #19 — typed `body` operator group, `#turtles.skip` and `// turtles: skip`,
  `--operators`, `fixtures/body`.
- #20 — counterexample → regression templates behind `--emit-regressions`.
- #21 — per-mutant `visibility` and `score_public` / `score_private`.
- #22 — core `@quickcheck` property tests for turtles itself.

Deviations from the design below:

- Regression templates are **opt-in** (`--emit-regressions`) and named
  `regressions/<mutant-id>.mbt`. The counterexample, killing test and mutant
  edit are recorded as comments inside a compilable `test` block; the user
  writes the call and assertion, because counterexample text is not guaranteed
  to parse as MoonBit.
- `DocTest` detection: moon 0.1.20260920 reports doc tests with an empty
  `test_name` (`.mbt.md` under its own filename, docstring blocks under the
  source `.mbt` file), so the empty name — not only the `.mbt.md` suffix —
  selects `DocTest`, checked before `Snapshot`. This resolves the doc-test
  open question.
- Visibility has a third `Test` bucket for mutants inside `test` blocks,
  excluded from both split scores. MoonBit rejects `priv fn`, so private code
  is exercised through default-visibility functions. For executable packages
  such as `cmd/turtles` (no `pub` declarations) the public score is vacuous.
- `body` stays opt-in (not a default group).
- Determinism guard: the design text below says both baseline runs happen in
  the reference workspace. As implemented (#18), both runs use the pristine
  validation copy, and `sweep_workspace` restores the snapshot between them,
  so side effects of the first run cannot leak into the second. The design
  sections below are historical and non-normative; the P2 witness design is
  superseded by `../open/2026-09-29-pbt-survivor-analysis.md` (QuickCheck import
  and recursive-function handling).
- The README documents these features in "Kill attribution and determinism"
  and "Skipping blocks" rather than a single "Property-based testing" section.
- Self-run after #22 on the merged tree: 844 mutants, 67.39%
  (560 KILLED / 271 SURVIVED / 13 UNVIABLE / 0 TIMEOUT), 83 property kills;
  pre-rebase baseline was 68.85% on 696 mutants.

## Direction

Keep the cargo-mutants concept, and specialise it for MoonBit along two axes:

1. **MoonBit idioms and practices** — follow the conventions of `moonbit-agent-guide`
   (`///|` top-level blocks, `moon.pkg` packages, black-box `*_test.mbt` vs white-box
   `*_wbtest.mbt`, `*.mbt.md` / docstring `mbt check` tests, `inspect` / `debug_inspect` /
   `json_inspect` snapshot tests, `pkg.generated.mbti` as the public-API signal,
   `moon fmt`, `--target`).
2. **Deep property-based testing (PBT) integration** — MoonBit ships first-party PBT
   (`moonbitlang/core/quickcheck` in the standard library, plus the extended
   `moonbitlang/quickcheck` driver / laws / FEAT module). Unlike Rust, where
   cargo-mutants cannot assume any PBT framework, turtles can assume one and
   treat properties as first-class mutant killers, witnesses, and suggestions.

### cargo-mutants concepts to keep

| cargo-mutants | turtles today | Keep / adapt |
|---|---|---|
| caught / missed / unviable / timeout | KILLED / SURVIVED / UNVIABLE / TIMEOUT | keep |
| baseline run in a scratch copy | `validate_workspace` | keep |
| function-body replacement by return type (`Default::default()`, `true`/`false`, `0`/`1`, `vec![]`, `None`, ...) — cargo-mutants' **primary** generator | not implemented (operator mutations only) | **add**, typed by MoonBit return type |
| `#[mutants::skip]` | only `turtles.toml` include/exclude | **add** a MoonBit-native skip marker |
| `--in-diff`, `--iterate`, `-j`, test-package selection | `--iterate`, `--jobs`, `--affected` (#15) | keep |
| `mutants.out/{caught,missed,unviable,timeout}.txt`, per-mutant diffs | JSON report + diffs | keep; add kill attribution |
| `cargo test` is the oracle | `moon test` is the oracle | keep, but make the oracle **structured** (below) |

## Verified facts (moon 0.1.20260920, 2026-09-29)

Probed with a scratch module (one property test, one snapshot test, a buggy `clamp`):

1. `moon test --test-failure-json` emits one JSON line per failing test:

   ```json
   {"package":"probe/p","filename":"lib_test.mbt","index":"0","test_name":"prop idempotent",
    "message":"lib_test.mbt:3:3-3:71@probe/p FAILED: QuickCheck falsified after 1 test(s)\ncounterexample: 0\nsize: 0\nshrinks: 2 successful, 2 attempted"}
   {"package":"probe/p","filename":"lib_test.mbt","index":"1","test_name":"example",
    "message":"@EXPECT_FAILED {\"loc\": {...}, \"expect\": \"3\", \"actual\": \"4\", ...}"}
   ```

   So turtles can attribute each kill to a concrete test **and** distinguish a
   QuickCheck falsification (with shrunk counterexample) from a snapshot
   (`@EXPECT_FAILED`) failure without scraping human-readable output.
2. `moonbitlang/core/quickcheck` is available from the standard library with no
   extra dependency (`@quickcheck.check(...)`); its default `seed` is `37`, i.e.
   deterministic by default. `moonbitlang/quickcheck` (`@qc.quick_check`,
   `quick_check_fn`, `forall`, `laws`, `feat`) also defaults to `seed = 37`,
   `max_success = 100`.
3. An unknown attribute such as `#turtles.skip` on a top-level function is
   accepted by `moon check` without a diagnostic. (Must be re-verified with
   `--deny-warn` and on each supported moon version before relying on it.)
4. `moon test` supports `-p <pkg>`, `-i <index>` (single file), `--filter <glob>`
   and `--target`, which is enough for per-test re-execution.

## Problems

1. **Opaque oracle.** `classify_mutant` only looks at the exit status of `moon test`.
   A KILLED verdict does not say *which* test killed the mutant, whether it was a
   property, a snapshot, a doc test or an `assert_*`, or what input falsified it.
   The most valuable PBT output — the shrunk counterexample — is discarded.
2. **No MoonBit-typed body replacement.** The operator groups (comparison,
   boolean, arithmetic, literal, condition) miss the cargo-mutants class that
   finds the most gaps in practice: "this whole function could return a trivial
   value and nothing notices".
3. **Snapshot-test hazards are implicit.** MoonBit test culture is snapshot-heavy
   (`inspect(..., content=...)`). A mutant run must never use `moon test --update`
   (it would rewrite the expectation and turn a KILL into a SURVIVE), and a
   snapshot failure is a legitimate kill that should be reported as such.
4. **Survivors are not actionable for PBT users.** A survivor tells the user
   "your tests are weak here" but not "which property is missing", even though
   MoonBit has Arbitrary/Shrink instances for standard types and a `laws`
   package with reusable algebraic laws.
5. **PBT nondeterminism is unguarded.** A property that seeds from time or uses
   a very small `max_success` can make verdicts flaky; the baseline does not
   detect this.

## Goals

- G1 Structured oracle: parse `--test-failure-json`, attribute kills to tests, and
  classify the killing test kind.
- G2 Capture QuickCheck counterexamples for killed mutants and turn them into
  ready-to-paste regression tests.
- G3 MoonBit-typed function-body replacement mutations (cargo-mutants' core idea).
- G4 MoonBit-native skip marker, honoured by discovery.
- G5 PBT-aware survivor guidance: property skeletons derived from signatures
  and `laws`, and (later) differential witnesses that prove a survivor is a real gap.
- G6 Determinism guard for property tests.
- G7 Self-application: turtles' own tests adopt QuickCheck where it is the right tool.
- Preserve current behaviour (verdicts, CLI, JSON fields) unless a flag opts in;
  new JSON fields are additive.

## Non-goals

- Implementing a PBT framework inside turtles, or depending on `moonbitlang/quickcheck`
  in user projects (turtles must work with core-only, extended, or no PBT).
- Parsing QuickCheck's human-readable `message` beyond the documented
  `counterexample:` / `size:` / `shrinks:` lines; unknown formats fall back to
  "property failure, counterexample unavailable".
- Changing user test sources in the original tree. Any test rewriting
  (amplification, differential harness) happens only inside the temporary workspace.
- Coverage-guided generation, `classify`/`collect` distribution analysis.

## Design

### P0 — Structured oracle and kill attribution

- Always invoke the mutant test run as `moon test --test-failure-json [...]`
  (plus existing `-p` / `--target` args). Never pass `--update` / `-u`; add a
  white-box test asserting the argv never contains them.
- Parse each JSON line into:

  ```moonbit nocheck
  ///|
  enum TestKind {
    Property    // message contains "QuickCheck falsified"
    Snapshot    // message starts with "@EXPECT_FAILED"
    DocTest     // filename ends with ".mbt.md" or failure located in a docstring block
    Assertion   // anything else (assert_eq, fail, panic, ...)
  } derive(Eq, Debug, ToJson)

  ///|
  struct Kill {
    package : String
    filename : String
    index : Int
    test_name : String
    kind : TestKind
    counterexample : String?   // only for Property
  } derive(Debug, ToJson)
  ```

- Report (additive): each KILLED row gets `killed_by : Array[Kill]`; summary gets
  per-kind kill counts and a "property-only kills" count (mutants that *only* a
  property caught — the headline value of PBT).
- If the JSON stream is missing/unparseable (older moon, runtime crash, abort
  before tests run), the verdict still comes from the exit status, and
  `killed_by` is empty with `attribution: "unavailable"`.
- Text output for a survivor stays as today; for kills, `--list-kills` (or the
  existing verbose path) prints `mut-XXXX killed by lib_test.mbt:2 "prop idempotent" (property, counterexample: 0)`.

### P0 — Determinism guard

- Baseline runs `moon test` twice in the reference workspace. If the set of
  tests/outcomes differs, abort with an actionable error naming the unstable
  tests (same philosophy as the existing baseline divergence check).
- Documented recommendation in README: keep QuickCheck's fixed default seed or
  pass an explicit `seed~`; never derive seeds from time in tests used as a
  mutation oracle.

### P1 — Counterexample → regression test

- For every Property kill with a counterexample, write
  `<output>/regressions/mut-XXXX.mbt` containing a black-box snippet in MoonBit
  style (`///|` block, `debug_inspect` / `assert_*`), e.g.:

  ```moonbit nocheck
  ///|
  test "turtles regression mut-0012: prop idempotent @ counterexample 0" {
    // counterexample reported by `prop idempotent` against mut-0012
    // replace `input` with the shrunk value and assert the property body
  }
  ```

  The snippet is a template (turtles cannot reliably reconstruct the property
  body); its value is recording the exact shrunk input, test location and mutant
  diff next to each other. The report links it.

### P1 — MoonBit-typed function-body replacement (`body` operator group)

- New operator group `body` (opt-in in P1, considered for default later).
- Target: top-level `fn` / `pub fn` / method bodies (one `///|` block each),
  excluding `test`, `async` functions, `extern`/FFI declarations, functions whose
  body is already a single trivial literal, and `#turtles.skip` blocks.
- Replacement values by declared return type (from the parser AST, no type inference):

  | Return type | Replacements |
  |---|---|
  | `Unit` / omitted | `()` |
  | `Bool` | `true`, `false` |
  | `Int`, `Int64`, `UInt`, `UInt64`, `Byte`, ... | `0`, `1` (and `-1` for signed) |
  | `Double`, `Float` | `0.0`, `1.0` |
  | `String` | `""`, `"xyzzy"` |
  | `T?` / `Option[T]` | `None` |
  | `Array[T]`, `FixedArray[T]` | `[]` |
  | `Map[K, V]` | `{}` |
  | `Result[T, E]` | *(skip in P1)* |
  | other / type parameter | skip (no `Default` guess; avoids UNVIABLE noise) |

  Functions with `raise` keep their signature; the replaced body simply does not raise.
- Mutant ids and `--iterate` fingerprints include the operator group, so reports
  from previous runs are not reused across group changes.

### P1 — MoonBit-native skip marker

- Recognise `#turtles.skip` on a top-level block (verified accepted by the
  compiler, see fact 3) and a `// turtles: skip` line comment inside a `///|`
  block as the fallback if the attribute ever becomes a warning. Both exclude
  every mutation inside that block. `--list` shows skipped block counts.

### P1 — Test-kind-aware prioritisation (MoonBit practice)

- Tag each mutant with whether its enclosing function is part of the public API
  (`pub` / appears in `pkg.generated.mbti`) and report the score separately for
  public vs private code: black-box tests (the guide's default) can only kill
  public-API-reachable mutants, so private survivors are a different signal.

### P2 — Survivor → property suggestions

- For survivors in functions whose parameter/return types have standard
  `Arbitrary + Shrink + Debug` instances, emit `<output>/properties/mut-XXXX.mbt`
  skeletons using signature shapes:
  - `(A) -> A` → idempotence / involution candidates (`@laws.idempotent`)
  - `(A, A) -> A` → commutativity / associativity (`@laws.associative`)
  - `encode`/`decode`, `to_*`/`from_*`, `parse`/`to_string` pairs in the same
    package → round-trip property
  - otherwise → a `@quickcheck.check` / `@qc.quick_check_fn` stub with the tuple
    of parameters (the tutorial's idiomatic multi-argument form)
- Suggestions are files only; turtles never edits user tests.

### P2 — Differential witness for survivors (PBT-only capability)

- For a surviving mutant in a top-level function `f` whose parameter types are
  Arbitrary and whose return type is `Eq + Debug`, generate *inside the
  temporary workspace*: the original body as `f__turtles_orig`, the mutated `f`,
  and a white-box test
  `@quickcheck.check(args => f(args) == f__turtles_orig(args))`.
- Outcome refinement (additive field `witness`):
  - falsified → `witness: <counterexample>`: proof that the mutant is observable
    and the suite has a real gap, with the concrete distinguishing input.
  - not falsified within budget → `witness: none` ("possibly equivalent mutant").
- This directly addresses cargo-mutants' biggest usability pain (equivalent vs
  real survivors) using MoonBit's built-in PBT.

### P2 — Property amplification (opt-in)

- `--pbt-amplify <N>`: for survivors only, re-run the packages' property tests
  with `max_success` × N and additional seeds by rewriting `quick_check*` /
  `check` call arguments in the temporary workspace. A mutant killed only after
  amplification is reported as `KILLED` with `amplified: true`, signalling "your
  properties are right but under-sampled".

### P0/P1 — Self-application (G7)

- Add property tests to turtles itself where laws are natural, using core
  `@quickcheck` first (no new dependency):
  - `source_byte_boundaries` / `source_byte_offset` monotonicity and bounds
  - `apply_mutation` on the identity replacement is a no-op; applying a mutation
    changes exactly the recorded byte range
  - `ProjectConfig::path_enabled` invariant under `\` → `/` normalisation
  - fingerprint stability for identical inputs
- Re-run turtles on itself and record the property-only kill count in the PR.

## Fixture design

New `fixtures/pbt/` module:

- `lib.mbt`: small pure functions (`clamp`, `abs_diff`, `rev_pair`, an
  `encode`/`decode` pair) plus one `#turtles.skip` function.
- `lib_test.mbt`: one property per function (core `@quickcheck`), one snapshot test,
  one plain `assert_eq`.
- `README.mbt.md`: one `mbt check` doc test.
- Expected: at least one property-only kill with a counterexample, at least one
  snapshot kill, the skipped function contributes zero mutants, and a `body`
  mutant of `rev_pair` that survives example tests but is killed by its property.

## Acceptance criteria

- [x] Mutant test runs pass `--test-failure-json` and never `--update`/`-u` (white-box test).
- [x] KILLED rows include `killed_by` with correct `kind` for property, snapshot,
      doc test and assertion failures on `fixtures/pbt`.
- [x] Property kills record the shrunk counterexample string; unknown message formats degrade gracefully.
- [x] Summary reports per-kind kill counts and property-only kills.
- [x] Baseline determinism guard aborts with the unstable test names when outcomes differ.
- [x] `regressions/<mutant-id>.mbt` generated for property kills (opt-in `--emit-regressions`) and listed in the report's `regressions` field.
- [x] `body` operator group implements the return-type table; unsupported types are skipped, not UNVIABLE.
- [x] `#turtles.skip` (and the comment fallback) excludes a block from discovery.
- [x] Public/private split in the score.
- [x] Existing fixtures (`basic`, `isolation`, `empty`, ...) produce byte-identical
      verdicts without new flags; JSON changes are additive only.
- [x] turtles gains property tests for the listed invariants; self-run documented.
- [x] README documents determinism, attribution, regressions, and skip marker ("Kill attribution and determinism", "Skipping blocks").
- [x] P2 items (suggestions, differential witness, amplification) tracked in `../open/2026-09-29-pbt-survivor-analysis.md`.

## Verification plan

Repository gates:

```sh
git diff --check
moon fmt --check
moon check --target native --deny-warn
moon test --target native
moon -C fixtures/basic test
moon -C fixtures/isolation test
moon -C fixtures/empty test
moon -C fixtures/pbt test
```

E2E:

```sh
turtles --dir fixtures/pbt --list
turtles --dir fixtures/pbt
turtles --dir fixtures/pbt --operators body
turtles --dir . --target native   # self-application
```

Checks: JSON `killed_by` kinds, counterexample strings, `regressions/` files,
skip marker, public/private split, and unchanged verdicts on old fixtures.

## Open questions

Resolved or moved: the doc-test shape is recorded above; the remaining
questions (`body` as a default group, extended `moonbitlang/quickcheck` in
suggestions, target keying) moved to
`../open/2026-09-29-pbt-survivor-analysis.md`.

Original questions:

- Should `body` become a default group once UNVIABLE rate is measured on real
  modules (`moonbitlang/x`, `f4ah6o/duckdb.mbt`)?
- Doc-test attribution: confirm how `--test-failure-json` reports `.mbt.md` and
  docstring `mbt check` failures (filename/index shape) before finalising `DocTest`.
- Should the extended `moonbitlang/quickcheck` (laws/FEAT) be recommended in
  suggestions, or stay core-only by default to avoid a dependency?
- Interaction with target-aware testing
  (`2026-09-30-target-aware-mutation-testing.md`): attribution and witnesses
  must be keyed by target.
