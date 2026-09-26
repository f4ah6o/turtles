# MoonBit parser integration note

## Status

AST-aware mutation is feasible, but turtles should not couple its Rust core directly to MoonBit parser internals yet.

The official `moonbitlang/parser` module currently exposes:

- `parse_string` and `parse_file`
- public MoonBit AST types
- expression variants such as infix operations, constants, conditionals, returns, calls, and function bodies
- source `Location` values
- visitor APIs for traversing and transforming syntax trees

This is enough structure to support substantially safer mutation discovery than continuing to grow lexical special cases.

## Stability constraint

The parser repository explicitly describes the module as highly experimental and unstable. It is implemented as a MoonBit package, while turtles is currently a standalone Rust binary.

For that reason, the next AST step should use a versioned adapter boundary rather than importing or duplicating unstable parser internals in Rust.

## Proposed adapter

A small MoonBit helper can depend on a pinned `moonbitlang/parser` version and expose a stable protocol to turtles.

Suggested request:

```json
{
  "protocol": 1,
  "path": "src/math.mbt",
  "source": "..."
}
```

Suggested response:

```json
{
  "protocol": 1,
  "mutants": [
    {
      "kind": "binary-operator",
      "start": 42,
      "end": 43,
      "line": 3,
      "column": 5,
      "original": "+",
      "replacement": "-"
    }
  ]
}
```

The Rust side should continue to own:

- module discovery
- include/exclude configuration
- temporary-workspace isolation
- mutation application
- `moon check` / `moon test`
- timeout handling and outcome classification
- reporting

The MoonBit adapter should own only syntax-aware candidate discovery.

## Migration plan

1. Keep the current lexical scanner as the default/fallback while the adapter is experimental.
2. Add an adapter fixture covering nested expressions, strings/comments, conditionals, returns, and function bodies.
3. Pin the parser package version and protocol version independently.
4. Compare lexical and AST candidate sets on the existing fixture before switching defaults.
5. Add new structural mutations only through the AST path once source locations are proven stable enough.
6. Preserve `UNVIABLE` classification even for AST-produced candidates; syntax awareness does not guarantee type-correct mutations.

## Decision

Do not add more ad-hoc lexical grammar rules for structural mutations. Small token replacements may remain in the fallback scanner, but function-body replacement, return-value replacement, conditional mutation, numeric constants, and call deletion/replacement should target the AST adapter.
