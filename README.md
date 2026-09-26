# turtles

Mutation testing for MoonBit projects — the `cargo-mutants` idea, adapted to `moon test`.

`turtles` finds small source-level changes ("mutants"), applies them one at a time in a **temporary copy** of your MoonBit module, and asks your tests to catch them. Your working tree is never intentionally modified.

## What it mutates

The first vertical slice covers common expression mutations:

- comparisons: `== ↔ !=`, `> → <`, `< → >`, `>= → <`, `<= → >`
- boolean logic: `&& ↔ ||`
- arithmetic: `+ ↔ -`, `* ↔ /`
- boolean literals: `true ↔ false`

Comments, strings, character literals, test files (`*_test.mbt`, `*_wbtest.mbt`), generated/build directories, and function arrows are skipped. Mutations that make the program fail `moon check` are reported as **unviable**, rather than as killed tests.

## Install

From this repository:

```sh
cargo install --path .
```

Then, in a MoonBit module:

```sh
turtles
```

Or run it against another module:

```sh
turtles --dir path/to/module
```

MoonBit's `moon` executable must be on `PATH`.

## CLI

```text
turtles [OPTIONS]

-d, --dir <PATH>       MoonBit module directory (default: .)
    --timeout <SECS>   Per-command timeout (default: 60)
    --file <TEXT>      Only mutate source paths containing TEXT
    --list             List mutations without running tests
-h, --help             Print help
```

`--list` is useful for inspecting the mutation set before spending time running tests:

```sh
turtles --list
```

## Result model

For every viable mutant:

- **KILLED** — `moon check` succeeded and `moon test` failed.
- **SURVIVED** — both commands succeeded; tests did not detect the change.
- **TIMEOUT** — checking or testing exceeded the configured timeout.
- **UNVIABLE** — `moon check` rejected the mutated source.

The process exits with code `1` when any mutant survives or times out, `2` for setup/baseline failures, and `0` when all viable mutants are killed.

## Safety model

Before mutation testing, `turtles` runs an unchanged `moon test` baseline. It then copies the module into a temporary directory, excluding `.git`, `target`, `.mooncakes`, `.moon`, and `node_modules`. All mutations and test runs happen there. The temporary workspace is removed when the run finishes.

## Current scope

This is an MVP focused on a trustworthy end-to-end loop rather than maximum mutation count. Planned follow-ups include AST-aware mutation via MoonBit compiler/tooling APIs when a stable interface is available, test selection, parallel workers, per-mutant output capture, config files, JSON/JUnit reports, and incremental/cached execution.
