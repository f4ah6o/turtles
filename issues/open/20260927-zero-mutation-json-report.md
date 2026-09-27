# Emit a JSON report when no mutations are discovered

- Status: open
- GitHub issue: #10
- Origin: PR #2 review, confirmed after MoonBit rewrite
- Affected area: `cmd/turtles/main.mbt`, `cmd/turtles/report.mbt`, CI

## Problem

When discovery returns no mutations, `execute` prints `No mutations found.` and returns success before the baseline/reporting path.

A caller can therefore request:

```sh
turtles --dir ... --json report.json
```

and receive exit code 0 without `report.json` being created.

This occurs naturally when a project has no currently supported operators or when `--file` / `turtles.toml` filters reduce the candidate set to zero.

The early return also bypasses baseline execution, so zero-mutant semantics are currently accidental rather than explicit.

## Implementation scope

- Define the non-`--list` zero-mutant behavior.
- When `--json` is requested, emit a schema-valid report for a valid empty candidate set, or return an explicit non-success error. The preferred behavior is a successful empty report.
- If schema 1 continues to require `baseline_duration_ms`, obtain it from a real baseline run rather than inventing a value.
- Keep `--list` free from test execution.
- Avoid duplicating normal report-summary construction.

## Acceptance criteria

For a valid module with zero candidates and `--json`:

- exit status is defined and documented;
- the requested JSON file exists on successful completion;
- `mutants` is empty;
- summary counts are zero;
- score semantics are consistent with the current result model;
- baseline timing is truthful if present.

The same behavior must hold when a filter reduces a normally non-empty module to zero candidates.

## Verification

Add CI coverage for:

1. an intrinsically empty candidate set with `--json`;
2. a non-empty fixture filtered to zero candidates;
3. `--list` with zero candidates, confirming no baseline execution is introduced.
