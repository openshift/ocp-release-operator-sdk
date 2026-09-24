# Skill: Downstream Patch Creation

## When to use

Creating or modifying patches in `patches/` for downstream CI adaptation.

## Reference implementation

See `patches/03-setversion.patch` for a typical version-override patch.

## Steps

1. Copy the target file with a suffix: `cp Makefile Makefile.patchname`.
2. Edit the original file with your changes.
3. Generate patch: `diff -up Makefile.patchname Makefile > patches/NN-description.patch`.
4. Restore the original: `mv Makefile.patchname Makefile` (preserves the file exactly as before your edits, including any uncommitted changes that predated this patch; `git checkout -- Makefile` would discard those).
5. Verify: `patch -p0 --dry-run < patches/NN-description.patch`.

## Verification

```bash
patch -p0 --dry-run < patches/NN-description.patch
make -f ci/prow.Makefile patch
make test-sanity
```

## Constraints

- Patches apply with `-p0` — paths must match repo root.
- Never edit source and patch for the same line simultaneously.
- Full guide: [docs/patterns/downstream-patches.md](../../../docs/patterns/downstream-patches.md)
