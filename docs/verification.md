# turtles' own verification harness

turtles verifies itself with the same machinery it applies to other projects,
plus two additional techniques that ship in `moon test`:

1. **Unit tests** (`*_wbtest.mbt`) — deterministic behavior checks.
2. **Official QuickCheck PBT** (`cmd/turtles/quickcheck_wbtest.mbt`) —
   `moonbitlang/core/quickcheck` `@quickcheck.check` properties over pure
   invariants: UTF-8 boundary construction, mutation application splicing,
   outcome counting, score bounds, and config round-tripping. All properties
   pin a `seed=` so mutation runs are reproducible. The property suite needs
   a toolchain whose bundled core includes `moonbitlang/core/quickcheck`
   (MoonBit 0.9-era cores and later); it is imported `for "wbtest"` only, so
   production builds never depend on it.
3. **Mutation testing** — turtles runs itself (see *Self-mutation* below).
4. **`moon prove`** — an optional gate, disabled by default (see below).

## Multi-gate harness

Each mutant is classified by an ordered list of named gates
(`Gate { name, program, args }` in `cmd/turtles/types.mbt`). Gates run against
the temporary workspace copy; the first failure decides the outcome and the
mutant is attributed to that gate (`MutationResult.gate`, JSON `gate` field,
`(gate: name)` in console output).

- A failing gate named `check` reports UNVIABLE.
- Any other failing gate reports KILLED.
- A timeout reports TIMEOUT, attributed to the gate that timed out.
- All gates passing reports SURVIVED.

Gate specs come from the `gates` key in `turtles.toml`:

- `"check"` / `"test"` / `"prove"` are builtins mapping to `moon <name>`.
- `"name=program args..."` is a custom command split on whitespace.

`--prove` appends the `prove` gate when it is not already configured.

## `moon prove` status

`moon prove` exists upstream (`moon prove [OPTIONS] [PATH]`; it lowers
proof-enabled packages to Why3 and discharges obligations with SMT solvers).
It is wired in as a builtin gate so projects with `*.mbtp` proof specs can
adopt it by adding `"prove"` to `gates` (or passing `--prove`).

Observed limitations:

- Verification on the development host could not be confirmed: the delegated
  environment permits only repo-local read commands and skipped every `moon`
  invocation, so the installed toolchain's `moon prove` support is unverified
  here. The gate is opt-in rather than default, so nothing fakes support.
- `moon prove` requires a working Why3 installation/provers and proof-enabled
  packages; turtles' own sources ship no `*.mbtp` specs, so the gate is
  vacuous for self-verification today and is intentionally not in the root
  `turtles.toml`.
- Proof/spec sources are not mutated anyway: `*.mbtp` files do not match the
  `*.mbt` scan suffix. Inline proof regions inside regular `.mbt` files are
  *not* excluded — parser coverage of proof syntax is unverified, so no
  inline-exclusion claim is made. Use `exclude` patterns for spec-heavy files.

## Self-mutation

The root `turtles.toml` is the checked-in self-verification config:

```toml
include = ["cmd/turtles/"]
gates = [
  "check",
  "test",
  "self-e2e=sh scripts/self_e2e.sh",
]
```

Run it with a generous per-command timeout (the e2e gate rebuilds the binary
and runs the whole fixture sweep):

```sh
moon run cmd/turtles -- --dir . --timeout 300 --json target/turtles-self.json
```

The `self-e2e` gate is what exercises mutants in `runner.mbt`, `report.mbt`,
and `main.mbt`: `scripts/self_e2e.sh` runs `moon run cmd/turtles` inside the
mutated workspace — i.e. it builds and runs the *mutated* binary — against
`fixtures/basic`, then validates the JSON report (schema, gate list, six
fixture mutants, zero survivors/timeouts/unviables). Mutants that keep the
binary exit-successful but break its behavior are still caught, because the
script asserts on the report, not just the exit code.

The script runs the fixture sweep twice with different `--json` targets so
both `mkdir` flag mutants in `write_json_report` are reachable: the first
report lands in an existing directory (a dropped `allow_exist=true` fails),
the second in a nested non-existent directory (a dropped `recursive=true`
fails).

The fixture path is hard-coded inside the script and the inner run uses the
default `check`/`test` gates, so self-mutation cannot recurse: the mutated
binary always targets `fixtures/basic`, never `.`.

### Survivors and the baseline

An authoritative survivor count requires running the command above on a host
where `moon` executes. On the delegation host every `moon` invocation was
skipped by the environment, so no baseline is claimed in this revision.

Known/expected survivor classes to audit when the baseline is established:

- Empty-input guards such as `if mutations.is_empty()` — a `cond → false`
  mutant only differs for modules without mutations, which the fixture sweep
  never produces. These are equivalent mutants for the e2e path unless unit
  tests or a dedicated empty-module e2e cover them.
- Purely cosmetic output mutations (e.g. progress counters like `index + 1`)
  that no gate observes.

Document each confirmed-equivalent survivor here rather than weakening
operators or hiding production files to reach green.

## JSON report schema

Schema `2` adds, on top of schema `1` fields:

- `gates: string[]` — the ordered gate names that were run.
- per-mutant `gate: string | null` — the gate that produced the outcome
  (`null` for SURVIVED).
