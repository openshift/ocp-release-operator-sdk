# Pattern: Upstream Synchronization

How to merge a new upstream `operator-sdk` release into this downstream fork.

## Files to Touch

- `UPSTREAM-VERSION` (updated by the merge script)
- `patches/03-setversion.patch` (updated by the merge script)
- `go.mod` / `go.sum` (upstream dependency changes)
- `vendor/` (re-vendored after merge)
- Any file with merge conflicts

## Steps

1. **Verify the upstream remote:**

   ```bash
   git remote -v  # ensure "upstream" points to operator-framework/operator-sdk
   git fetch upstream
   ```

2. **Run the merge script:**

   ```bash
   ./UPSTREAM-MERGE.sh v1.XX.Y [branch] [remote]
   ```

   The script creates a branch `v1.XX.Y-rebase-<branch>`, merges the upstream tag, preserves `OWNERS_ALIASES` and `README.md`, and updates `UPSTREAM-VERSION` and the setversion patch.

3. **Resolve conflicts:** The script resolves most conflicts by taking upstream. Manually review any remaining conflicts, especially in `internal/` or `hack/`.

4. **Vendor dependencies:**

   ```bash
   go mod tidy
   go mod vendor
   ```

   Commit vendor changes separately with `UPSTREAM: <drop>: Update vendor directory`.

5. **Re-apply carry patches:** Review each `UPSTREAM: <carry>:` commit from the previous branch and re-apply if still needed.

## Targeted Tests

```bash
make verify-file FILE=<any conflicted Go file>
make verify  # full pre-PR gate
```

## Review Risks

- Upstream changes to Makefile targets may conflict with downstream patches in `patches/`.
- New upstream dependencies may introduce vendoring issues; run `go mod tidy && go mod vendor` and inspect `vendor/modules.txt`.
- Generated files (`testdata/`, CLI docs) must be regenerated with `make generate`.
