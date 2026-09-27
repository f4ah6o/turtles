# Isolate filesystem side effects between mutant runs

- Status: implemented
- GitHub issue: #9
- Origin: current codebase review
- Affected area: `cmd/turtles/runner.mbt`
- Related task: `20260927-temp-workspace-copy-fidelity.md`

## Problem

`run_mutations` creates one temporary workspace, copies the module once, and then runs every mutant sequentially in that same workspace.

After each run it restores only the mutated source file. Any other files changed or created by `moon check`, `moon test`, build hooks, or the test suite remain visible to later mutants.

Examples include generated fixtures, caches, snapshots, databases, lockfiles, or sentinel files. Later outcomes can therefore depend on execution order.

## Implementation scope

Choose and enforce a pristine-workspace boundary for each mutant. Reasonable implementations include:

- a fresh temporary workspace per mutant; or
- a validated restore/recreate strategy that guarantees equivalent filesystem state before every mutant.

Do not assume test/build side effects are harmless merely to optimize performance.

The solution should compose with the workspace-fidelity task rather than creating a second inconsistent copy mechanism.

## Acceptance criteria

- Every mutant starts from equivalent filesystem state.
- Running the same candidates in a different order yields the same classifications.
- A test that writes state during one run cannot alter the next mutant's result.
- Temporary workspace cleanup remains reliable on success, timeout, and failure.
- The implementation remains safe for future parallel workers.

## Verification

Add a regression fixture where the test suite writes a file that would alter the behavior of a second run if state leaked.

Test at least two candidate orders and assert identical outcomes.
