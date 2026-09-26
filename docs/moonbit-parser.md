# MoonBit parser integration note

## Status

`turtles` is now implemented entirely in MoonBit, and production candidate discovery uses the pinned `moonbitlang/parser@0.4.0` AST. AST diagnostics are surfaced as errors; discovery never silently falls back to lexical scanning.

The official `moonbitlang/parser` module exposes:

- `parse_string` and `parse_file`
- public MoonBit AST types
- expression variants such as infix operations, constants, conditionals, returns, calls, and function bodies
- source `Location` values
- visitor APIs for traversing and transforming syntax trees

This is enough structure for the syntax-aware mutation discovery implemented in `cmd/turtles/scanner.mbt`.

## Stability constraint

The parser repository explicitly describes the module as highly experimental and unstable. That remains the main integration risk even though turtles and the parser now share the same implementation language.

The parser dependency is pinned, and its unstable API is isolated in `cmd/turtles/scanner.mbt`; the runner continues to consume turtles-owned `Mutation` values.

## MoonBit boundary

`cmd/turtles/scanner.mbt` owns all direct `moonbitlang/parser` usage and exposes turtles-owned mutation values:

```moonbit
struct Mutation {
  path : String
  start : Int
  end : Int
  line : Int
  column : Int
  group : OperatorGroup
  original : String
  replacement : String
}
```

The rest of turtles should continue to own:

- module and source discovery
- include/exclude configuration
- temporary-workspace isolation
- mutation application
- `moon check` / `moon test`
- timeout handling and outcome classification
- reporting

This keeps parser churn local without introducing another language, process, or serialization protocol.

## Migration notes

1. Pin a known-good `moonbitlang/parser` version.
2. Discover the existing token mutations from `Expr::Infix` and boolean `Expr::Constant` nodes.
3. Traverse all implementations and nested expressions with the parser `IterVisitor` base traversal.
4. Convert the parser’s default Unicode-scalar source offsets to UTF-8 byte offsets only when constructing a `Mutation`; `apply_mutation` remains byte-safe.
5. Preserve `UNVIABLE` classification even for AST-produced candidates; syntax awareness does not guarantee type-correct mutations.
6. Add structural mutations through the AST path: function-body replacement, return-value replacement, conditional mutation, numeric constants, and call deletion/replacement.

The default `parse_string` lexer mode reports `Position.cnum` and `Position.bol` in Unicode-scalar/code-point units, not UTF-8 bytes or UTF-16 code units. `Position.column()` is `cnum - bol + 1`. The scanner therefore converts each parser offset through a UTF-8 boundary table before storing `Mutation.start` and `Mutation.end`.

## Decision

Do not grow the old lexical scanner with structural MoonBit grammar rules. Direct parser integration is now the default architecture: a pinned parser dependency behind the scanner’s small internal MoonBit boundary.
