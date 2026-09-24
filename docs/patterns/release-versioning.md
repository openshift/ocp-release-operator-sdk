# Pattern: Release, Versioning, and Changelog Changes

How to prepare a release, update version strings, or add changelog fragments.

## Files to Touch

- `Makefile` (`IMAGE_VERSION`, `SIMPLE_VERSION`, `GIT_VERSION`)
- `internal/version/version.go` (injected via ldflags, not edited directly)
- `changelog/fragments/<name>.yaml` (new changelog entry)
- `release/` (goreleaser config)
- `patches/03-setversion.patch` (downstream version override)

## Version Injection

Five variables are injected at build time via ldflags into `internal/version/`:

| Variable | Source |
|---|---|
| `Version` | `SIMPLE_VERSION` (Makefile) |
| `GitVersion` | `git describe --dirty --tags --always` |
| `GitCommit` | `git rev-parse HEAD` |
| `KubernetesVersion` | `K8S_VERSION` (Makefile) |
| `ImageVersion` | `IMAGE_VERSION` (Makefile) |

The downstream build overrides `SIMPLE_VERSION` to `v1.42.3-ocp` via `patches/03-setversion.patch`.

## Adding a Changelog Fragment

Create a YAML file in `changelog/fragments/` following the template:

```yaml
entries:
  - description: >
      Brief description of the change.
    kind: "addition"  # addition | change | deprecation | removal | bugfix
```

See `changelog/fragments/00-template.yaml` for the full template.

## Preparing a Release

1. Update `IMAGE_VERSION` in the Makefile to the new release tag.
2. Run `make prerelease RELEASE_VERSION=vX.Y.Z`.
3. Run `make generate` to regenerate docs.
4. Commit, tag with `make tag`, and push.

## Targeted Tests

```bash
make test-docs       # validate changelog
make verify          # full pre-PR gate
```

## Review Risks

- `IMAGE_VERSION` must match `RELEASE_VERSION` before `make prerelease`.
- The downstream setversion patch must be updated if the upstream version changes.
- Changelog fragments are required for all user-facing PRs.
