# Open implementation tasks

This directory contains review findings that should remain actionable even if the corresponding GitHub issue or pull-request context becomes hard to reconstruct.

## Suggested order

1. [20260927-temp-workspace-copy-fidelity.md](./20260927-temp-workspace-copy-fidelity.md) — make the pristine temporary workspace faithfully represent the tested module.
2. [20260927-mutant-workspace-isolation.md](./20260927-mutant-workspace-isolation.md) — prevent one mutant run from contaminating later runs.
3. [20260927-unary-arithmetic-mutation-regression.md](./20260927-unary-arithmetic-mutation-regression.md) — restore unary arithmetic mutation discovery lost in the AST migration.
4. [20260927-zero-mutation-json-report.md](./20260927-zero-mutation-json-report.md) — make `--json` reliable for an empty candidate set.
5. [20260927-structural-if-operator-group.md](./20260927-structural-if-operator-group.md) — separate structural condition replacement from boolean-logic selection and update docs.

Each task includes the affected code, implementation boundary, acceptance criteria, and verification work needed to close it.
