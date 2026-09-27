# Prevent false mutant classifications from lossy temporary-workspace copies

- Status: open
- GitHub issue: #7
- Origin: PR #3 review + current codebase review
- Affected area: `cmd/turtles/fs_ops.mbt`, `cmd/turtles/runner.mbt`, baseline/setup flow

## Problem

The baseline runs in the original module, while mutant classification runs in a temporary workspace created by `copy_tree`.

The current copy implementation only handles `Directory` and `Regular` entries. Symlinks are omitted. Regular files are recreated with `@fs.write_file`; the dependency's default creation permission is `0644`, so executable bits and other relevant file mode differences are not preserved.

The original baseline can therefore pass while the pristine copied workspace already behaves differently. A mutant may then be reported as `KILLED` or `UNVIABLE` because of the copy, not because of the mutation.

## Implementation scope

- Define the fidelity contract for the temporary workspace.
- Preserve semantically relevant regular-file permissions, especially executable bits.
- Handle symlinks explicitly; do not silently discard them.
- Keep isolation safe for symlinks that point outside the module root.
- Validate the unchanged temporary workspace before using it for mutant evidence. Copy/environment divergence should become a setup error.
- Keep the existing exclusions for generated/build/cache directories intentional and documented.

## Acceptance criteria

- A fixture whose tests execute a checked-in helper script behaves the same in the original and copied workspace.
- Symlink behavior is explicit and covered on supported platforms.
- A pristine copied workspace that fails validation aborts classification instead of producing mutant outcomes.
- No source file in the user's working tree is modified.
- Cleanup still occurs on success, timeout, and failure.

## Verification

Add regression fixtures for:

1. an executable helper invoked by tests;
2. a symlinked fixture/source where supported;
3. a deliberately divergent copied workspace that must fail as setup, not classify a mutant.

Run the normal MoonBit CI command set plus the real fixture E2E.
