# Restore unary arithmetic mutation discovery after the AST migration

- Status: open
- GitHub issue: #6
- Origin: PR #4 post-merge review
- Affected area: `cmd/turtles/scanner.mbt`, scanner tests

## Problem

PR #4 moved mutation discovery from lexical scanning to `moonbitlang/parser`. The current visitor records infix operators, boolean constants, and `if` expressions, but it does not implement `visit_Expr_Unary`.

As a result, valid code such as:

```moonbit
fn negate(x : Int) -> Int {
  -x
}
```

no longer produces the previously supported arithmetic mutation `- -> +`.

The parser exposes a dedicated `Expr::Unary` / `visit_Expr_Unary` form, so this should be recovered through AST traversal rather than source-text scanning.

## Impact

The mutation set is silently smaller for code using unary negation, which can overstate the mutation score.

## Implementation scope

- Add `visit_Expr_Unary` to `AstCandidateVisitor`.
- Use the parser-provided operator location and the existing Unicode-scalar to UTF-8 byte conversion path.
- Reuse the existing arithmetic operator filtering.
- Preserve the base visitor call so nested expressions are still traversed.
- Do not accidentally turn unsupported unary operators such as `!` into mutations unless that behavior is intentionally added separately.

## Acceptance criteria

- `-x` produces exactly the intended `- -> +` arithmetic candidate.
- Disabling the arithmetic group removes that candidate.
- Nested unary expressions are traversed correctly.
- UTF-8 source locations remain byte-accurate.
- Existing infix/literal/structural mutation tests continue to pass.

## Verification

Run at minimum:

```sh
moon fmt --check
moon check --target native --deny-warn
moon test --target native
```

Add focused scanner tests for unary mutation discovery and operator filtering.
