# MoonBit parser integration note

## Status

`turtles` is now implemented entirely in MoonBit, so AST-aware mutation no longer needs a cross-language adapter.

The official `moonbitlang/parser` module exposes:

- `parse_string` and `parse_file`
- public MoonBit AST types
- expression variants such as infix operations, constants, conditionals, returns, calls, and function bodies
- source `Location` values
- visitor APIs for traversing and transforming syntax trees

This is enough structure to replace the current lexical candidate discovery with syntax-aware mutation discovery.

## Stability constraint

The parser repository explicitly describes the module as highly experimental and unstable. That remains the main integration risk even though turtles and the parser now share the same implementation language.

The parser dependency should therefore be pinned, and its unstable API should be isolated behind a small internal turtles package rather than used throughout the runner.

## Proposed MoonBit boundary

A future internal package such as `internal/syntax` should own all direct `moonbitlang/parser` usage and expose turtles-owned mutation candidates:

```moonbit
struct MutationCandidate {
  start : Int
  end : Int
  line : Int
  column : Int
  original : String
  replacement : String
  kind : String
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

## Migration plan

1. Pin a known-good `moonbitlang/parser` version.
2. Add direct parser-backed discovery for the existing token mutations.
3. Compare parser-backed and lexical candidate sets on the real fixture and dedicated syntax fixtures.
4. Keep the lexical scanner only as a temporary compatibility fallback while parity is measured.
5. Switch the default to parser-backed discovery after location/offset handling is proven stable.
6. Add structural mutations through the AST path: function-body replacement, return-value replacement, conditional mutation, numeric constants, and call deletion/replacement.
7. Preserve `UNVIABLE` classification even for AST-produced candidates; syntax awareness does not guarantee type-correct mutations.

## Decision

Do not grow the lexical scanner with structural MoonBit grammar rules. The MoonBit-only rewrite makes direct parser integration the preferred next architecture: a pinned parser dependency behind a small internal MoonBit boundary.
