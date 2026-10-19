# Pattern: Downstream Patch Creation and Application

How to create, modify, or debug patches in the `patches/` directory.

## Files to Touch

- `patches/NN-description.patch` (the patch file itself)
- The target file being patched (e.g., `Makefile`, test files)
- `ci/prow.Makefile` (applies patches via `make -f ci/prow.Makefile patch`)

## How Patches Are Applied

In downstream CI, patches are applied before any build or test step:

```bash
for i in ./patches/*.patch; do patch -p0 < "$i" || exit 1; done
```

Patches use numbered naming (`NN-description.patch`) and `diff -up` format.

## Creating a New Patch

1. **Make your modification** to the target file.

2. **Generate the patch** using `diff -up` with a suffix marker:

   ```bash
   cp Makefile Makefile.patchname
   # edit Makefile with your changes
   diff -up Makefile.patchname Makefile > patches/NN-description.patch
   ```

3. **Restore the original target file** (the patch is applied in CI, not committed to the source):

   ```bash
   mv Makefile.patchname Makefile
   ```

   Use `mv` rather than `git checkout -- Makefile`: the latter discards any
   pre-existing uncommitted changes to the file, while `mv` restores exactly
   the content you copied in step 2.

4. **Test the patch applies cleanly:**

   ```bash
   patch -p0 --dry-run < patches/NN-description.patch
   ```

## Existing Patches

| Patch | Purpose |
|---|---|
| `00-fixsanity` | Adjusts `test-sanity` for downstream |
| `02-disable-security-context` | Disables security context in Helm test values |
| `03-setversion` | Hardcodes `SIMPLE_VERSION` to `<version>-ocp` |
| `08-fix-downstream-stamps` | Adds `-ocp` suffix handling in metrics |
| `09-do-not-use-docker` | Disables Docker in pkgmantobundle tests |
| `12-skip-pkgman-docker-test` | Skips Docker-dependent tests |

## Targeted Tests

```bash
# Verify patch applies
patch -p0 --dry-run < patches/NN-description.patch

# After applying, run the affected test target
make -f ci/prow.Makefile patch
make test-sanity
```

## Review Risks

- Patches can silently break on upstream rebase if the target file changed significantly.
- Never edit the source file and the patch for the same line simultaneously.
- Patches apply with `-p0` (no path stripping), so paths in the patch must match the repo root.
