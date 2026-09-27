# Separate structural if-condition mutations from the boolean-logic operator group

- Status: implemented
- GitHub issue: #8
- Origin: PR #5 post-merge review
- Affected area: `cmd/turtles/types.mbt`, `cmd/turtles/scanner.mbt`, config tests, README

## Problem

PR #5 added whole-condition structural mutations:

- `if cond { ... }` -> `if true { ... }`
- `if cond { ... }` -> `if false { ... }`

They are currently recorded as `OperatorGroup::Boolean`.

Before #5, that group represented logical `&& <-> ||` mutations and the config alias `boolean-logic` maps to it. Therefore:

```toml
operators = ["boolean-logic"]
```

now also enables structural `if` replacements. There is no independent way to select or disable the new structural mutation.

README also does not list the whole-condition replacements under "What it mutates", and the current-scope text still describes structural AST mutations as a future follow-up.

## Implementation scope

- Define an explicit operator-selection policy for structural condition replacement.
- Prefer a dedicated group such as `condition` or `structural` unless a different compatibility policy is deliberately chosen.
- Keep `boolean-logic` scoped to logical operators unless the compatibility change is explicitly documented.
- Update parser/scanner wiring, configuration parsing, tests, README, and current-scope documentation together.

## Acceptance criteria

- Logical and structural mutations can be selected independently.
- Existing `boolean-logic` configuration has documented, deterministic semantics.
- No-op filtering and literal/structural deduplication remain intact.
- README accurately describes all currently implemented mutation classes.
- The "planned follow-ups" text no longer lists the already-implemented first structural mutation as wholly future work.

## Verification

Add config/scanner tests covering:

- logical-only selection;
- structural-only selection;
- both enabled;
- neither enabled;
- literal `true` / `false` conditions where deduplication matters.
