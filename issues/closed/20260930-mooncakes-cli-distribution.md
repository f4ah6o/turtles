# Publish turtles to Mooncakes as the stable CLI distribution channel

- Status: closed (triaged 2026-10-02)
- Previous record: implemented (2026-09-29) — `f4ah6o/turtles@0.2.0` published to Mooncakes and verified
- Origin: distribution decision after reviewing current CLI/package layout
- Affected area: `moon.mod`, `cmd/turtles/moon.pkg`, `README.md`, release/publish workflow
- Primary user-facing command: `turtles`

## Decision

Publish `f4ah6o/turtles` to Mooncakes and treat it primarily as an installable MoonBit CLI, not as a library API.

The intended distribution model is:

1. **Stable releases:** install the published Mooncakes version.
2. **Development snapshots:** install directly from the GitHub repository and branch/tag.
3. **Contributors:** clone the repository and run/build locally.
4. **Prebuilt GitHub release binaries:** optional follow-up, not required for the first Mooncakes release.

Do not introduce a public library API merely to justify registry publication. The product is the `turtles` executable.

## Why this fits the current repository

The repository is already organized around an executable package:

```text
cmd/turtles/moon.pkg
  pkgtype(kind: "executable")
  supported_targets = "+native"
```

The CLI already owns the user-facing behavior:

- mutation discovery and application
- baseline `moon check` / `moon test`
- temporary workspace isolation
- bounded parallel execution
- `--iterate`
- `--affected`
- `--fail-under`
- JSON/schema-2 reporting
- configuration through `turtles.toml`

This is a developer tool that operates on a MoonBit module from the outside. Consumers do not need to import turtles into application code.

## Distribution contract

### Stable installation

After publication, the README should present the Mooncakes-hosted executable as the default stable installation path.

Target UX:

```sh
moon install f4ah6o/turtles/cmd/turtles@<version>
turtles --version
```

For the initial publish, use the repository's release version if the package is ready to ship unchanged.

The exact install command must be validated against the Moon toolchain used for publication before documenting it as canonical.

### Development installation

Keep GitHub installation as the explicit development/latest path:

```sh
moon install https://github.com/f4ah6o/turtles.git cmd/turtles --branch main
```

For tagged source installs, continue supporting:

```sh
moon install https://github.com/f4ah6o/turtles.git cmd/turtles --tag v<version>
```

README wording should make the distinction visible:

```text
Stable        -> Mooncakes
Development   -> GitHub main
Contributor   -> local clone / moon run
```

### Library consumption

Do not make `moon add f4ah6o/turtles` the primary documented workflow.

A future reusable internal API may be extracted if there is a concrete consumer, but registry publication must not force a premature library surface or compatibility commitment.

## Release scope

### P0 — publishable package

Before publishing:

1. Confirm `moon.mod` metadata is complete and valid:
   - `name = "f4ah6o/turtles"`
   - release version
   - README
   - repository
   - MIT license
   - description
   - keywords
   - native target preference
2. Confirm `cmd/turtles/moon.pkg` remains an executable native package.
3. Run the normal repository verification suite.
4. Run the package/publish validation command supported by the current Moon toolchain.
5. Publish the selected release version to Mooncakes.
6. From a clean environment/module, install the published package and verify the installed `turtles` executable.
7. Update README installation documentation after the registry install path is proven.

### P1 — CI consumption example

Document a minimal CI use case based on an exact published version:

```sh
moon install f4ah6o/turtles/cmd/turtles@<version>
turtles --dir . --fail-under 80 --json turtles-report.json
```

The goal is reproducibility. CI examples should pin a released version rather than follow `main`.

### P2 — release ergonomics

After the first successful publish, consider automating:

- version consistency checks
- tag/release creation
- Mooncakes publication
- post-publish install smoke test

This automation must be added only after the manual flow is known-good and repeatable.

## Prebuilt binaries

Prebuilt binaries are explicitly not required for this milestone.

They may later reduce installation/build time, especially in CI, but turtles still relies on the MoonBit toolchain at runtime because it executes `moon check` and `moon test`. Therefore prebuilt binaries do not remove the fundamental Moon toolchain dependency.

Track binary distribution separately if install latency becomes a meaningful problem.

## README changes

Replace the current statement that Mooncakes publishing is intentionally out of scope.

The installation section should become structurally similar to:

```md
## Install

### Stable

moon install f4ah6o/turtles/cmd/turtles@<version>

### Development

moon install https://github.com/f4ah6o/turtles.git cmd/turtles --branch main

### From a local clone

moon install ./cmd/turtles
```

Do not publish a stable command until it has actually succeeded against the registry.

## Verification

Run at least:

```sh
moon update
moon fmt --check
moon check --target native --deny-warn
moon test --target native
moon -C fixtures/basic test
moon run cmd/turtles -- --dir fixtures/basic --timeout 30
```

Also run the current Moon package/publish validation command appropriate for the installed toolchain.

After publication, verify from a clean location:

```sh
moon install f4ah6o/turtles/cmd/turtles@<published-version>
turtles --version
turtles --help
```

Then execute turtles against a small fixture/module and confirm it can invoke `moon check` and `moon test` successfully.

## Acceptance criteria

- [x] `f4ah6o/turtles` is published successfully to Mooncakes at a version that matches the repository release metadata. (`f4ah6o/turtles@0.2.0`, `moon publish` → "Server status: 200 OK")
- [x] The published module exposes/installably builds the `cmd/turtles` executable. (`moon install f4ah6o/turtles/cmd/turtles@0.2.0` builds and installs the binary)
- [x] A clean install of the published version produces a working `turtles` command.
- [x] `turtles --version` reports the published version. (`turtles 0.2.0`)
- [x] A clean smoke mutation-test run succeeds against a known fixture/module. (6/6 KILLED, score 100, exit 0)
- [x] README documents Mooncakes as the stable installation path.
- [x] README keeps GitHub `main` installation as the development path.
- [x] CI documentation pins an explicit Mooncakes release version. (README CI example + a CI step pin `@0.2.0`)
- [x] README no longer says Mooncakes publishing is out of scope.
- [x] No unnecessary public library API is introduced solely for publication.
- [x] Existing repository tests and fixture E2E remain green.

## Progress (2026-09-29, Phase 1 — pre-publish readiness)

Verified on `moon 0.1.20260920`:

- **P0 metadata**: `moon.mod` has `name = "f4ah6o/turtles"`, `version = "0.2.0"`, `readme`, `repository`, `license = "MIT"`, `description`, `keywords`, `preferred_target = "native"`. `cmd/turtles/moon.pkg` is `pkgtype(kind: "executable")` with `supported_targets = "+native"`. `turtles_version` in `cmd/turtles/config.mbt` matches (`0.2.0`). No git tags exist yet.
- **`moon package --list`**: builds `_build/publish/f4ah6o-turtles-0.2.0.zip`; the list is written to **stderr**. Initially packaged 52 files including the whole `issues/` tree — added a root `.moonignore` (`issues/`; the modern mechanism — `include`/`exclude` fields in `moon.mod` are deprecated). Result: 42 files, `_build/`/dot-dirs excluded by default, `issues/` now excluded; `fixtures/` and `docs/` retained (small, part of the source distribution).
- **`moon publish --dry-run`**: exits 255 with `failed to open credentials file ... please login first` — the dry-run still requires registry credentials on this toolchain, so `moon package --list` is the credential-free publish validation (now also in CI).
- **Clean-install smoke**: `moon install --path ./cmd/turtles --bin <tmpdir>` (closest available simulation of the registry path — `moon install` has no "install from packaged zip" mode) produced a working binary: `turtles --version` → `turtles 0.2.0`; `turtles --help` ok; `turtles --dir <copy of fixtures/basic> --timeout 30` → 6/6 mutants KILLED, score 100, exit 0.
- **CI (P2-lite)**: added a `moon.mod` version ⇔ `turtles_version` consistency assertion and a `moon package --list` step to `.github/workflows/ci.yml`.
- **README**: Install restructured into Stable (Mooncakes) / Development (GitHub) / local-clone. The registry command is documented as the target UX but clearly marked *pending first publish*; the git-URL install remains the verified path. The "out of scope" claim now reads "planned — pending first publish".

### Phase 2 — publish + post-publish verification

- **Publish**: `f4ah6o/turtles@0.2.0` published to Mooncakes from this branch's HEAD (`d149b81`) — `moon publish` → "Server status: 200 OK".
- **Toolchain quirk**: `moon publish --dry-run` *with* credentials returns server "202 Accepted, Dry run completed successfully" but `moon` still exits `255`; without credentials it exits `255` at `please login first`. Treat `moon package --list` as the credential-free validation and read the server status line, not the exit code, for dry runs.
- **Registry clean-install smoke** (clean location): `moon install f4ah6o/turtles/cmd/turtles@0.2.0 --bin <tmp>` → `Success: Installed turtles`; `turtles --version` → `turtles 0.2.0`; `turtles --help` ok; `turtles --dir <copy of fixtures/basic> --timeout 30` → 6/6 KILLED, score 100, exit 0. Confirmed from a second clean environment as well.
- **README**: Stable section is now the live `moon install f4ah6o/turtles/cmd/turtles@0.2.0` command; GitHub stays the development path; added a CI usage example pinned to `@0.2.0` (`turtles --dir . --fail-under 80 --json turtles-report.json`).
- **CI**: added a "Smoke-test the published Mooncakes release" step — `moon install f4ah6o/turtles/cmd/turtles@0.2.0 --bin <tmp>` then asserts `turtles --version` prints `turtles 0.2.0`.

Remaining follow-ups (not part of this milestone):

- Git tag `v0.2.0` at the published commit (enables the `--tag` install path documented in README).
- Optional release automation after the manual flow repeats cleanly: tag/release creation, publish automation, post-publish install smoke in release CI.

## Non-goals

- Homebrew or other OS package managers.
- Removing the MoonBit toolchain runtime dependency.
- Designing a stable importable turtles library API.
- Publishing prebuilt binaries in the first Mooncakes milestone.
- Changing mutation semantics, scoring, reporting, or workspace isolation.
