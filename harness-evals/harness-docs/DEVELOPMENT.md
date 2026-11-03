# Development Guide

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Go | 1.26.3 | See `go.mod` `go` directive |
| Make | any | GNU Make |
| Git | any | With upstream remote configured |
| `gendiff` | any | For creating downstream patches |
| Docker/Podman | any | For image builds (downstream uses podman) |

## Quick Start

```bash
# Clone and set up remotes
git clone https://github.com/openshift/ocp-release-operator-sdk.git
cd ocp-release-operator-sdk

# Downstream build (applies patches first — REQUIRED)
make -f ci/prow.Makefile patch build

# Local build (no patches, for upstream-compatible development)
make build

# Run tests
make test-unit
make test-sanity
```

## Build Commands

| Task | Command | Notes |
|------|---------|-------|
| **Downstream build** | `make -f ci/prow.Makefile patch build` | Applies patches then builds helm-operator |
| **Local build (both binaries)** | `make build` | Builds operator-sdk + helm-operator to `build/` |
| **Build operator-sdk only** | `make build/operator-sdk` | |
| **Build helm-operator only** | `make build/helm-operator` | |
| **Install to GOBIN** | `make install` | Installs both binaries |
| **Build all images** | `make image-build` | Builds operator-sdk, helm-operator, scorecard-test, scorecard-test-kuttl images |
| **Build single image** | `make image/helm-operator` | Uses docker buildx |
| **Clean** | `make clean` | Removes `build/`, `dist/`, `tools/bin/` |

## Build Tags

All Go commands require the `containers_image_openpgp` build tag:
```bash
go test -tags=containers_image_openpgp ./...
go build -tags=containers_image_openpgp ./cmd/operator-sdk
```

The `Makefile` sets this automatically via `GO_BUILD_TAGS`.

## Common Tasks

### Syncing a New Upstream Release

1. Verify upstream remote: `git remote -v` (should show `operator-framework/operator-sdk`)
2. Fetch upstream tags: `git fetch -t upstream`
3. Run merge script: `./UPSTREAM-MERGE.sh <tag>` (e.g., `./UPSTREAM-MERGE.sh v1.42.3`)
4. Verify patches apply: `make -f ci/prow.Makefile patch build`
5. Fix any patch conflicts, push the `<tag>-rebase-main` branch, open PR

For release branches: `./UPSTREAM-MERGE.sh <tag> release-4.x`

### Automated Rebase (CI Periodic)

The `hack/auto-rebase.sh` script runs weekly as a Prow periodic:

```bash
# Dry run (no push/PR)
DRY_RUN=1 ./hack/auto-rebase.sh

# Force a specific tag
OVERRIDE_TAG=v1.42.3 DRY_RUN=1 ./hack/auto-rebase.sh
```

### Creating a Downstream Patch

Use the `gendiff` workflow (see [README.md patching section](../README.md#gendiff-method)):

1. Back up files: `cp path/to/file.go path/to/file.go.bugxxx`
2. Edit the originals
3. Generate patch: `gendiff . .bugxxx > patches/NN-description.patch`
4. Add and commit the patch file
5. Restore originals: `git restore path/to/file.go`
6. Verify: `make -f ci/prow.Makefile patch`

Patch numbering: files are applied sequentially (00, 02, 03, 08, 09, 12...). Use the next available number.

### Regenerating Code

| What | Command |
|------|---------|
| CLI docs, samples, testdata | `make generate` |
| OLM bindata | `make bindata` |
| Format + tidy | `make fix` |
| Lint setup | `make setup-lint` |

### Updating the Builder Image

When the upstream Go version changes, update these files:
1. `.ci-operator.yaml` — `build_root_image.tag` field
2. `release/helm/Dockerfile` — builder `FROM` line

The `hack/auto-rebase.sh` script does this automatically for automated rebases.

## Linting

```bash
make lint          # Run golangci-lint with containers_image_openpgp tag
make setup-lint    # Fetch golangci-lint v2.9.0 to tools/bin/
```

Linter configuration: `.golangci.yml` enables `dupl`, `ginkgolinter`, `goconst`, `gocyclo`, `gosec`, `misspell`, `nakedret`, `revive`, `unconvert`, `unparam`.

## Common Mistakes

1. **Running `make build` for downstream CI** — patches are NOT applied. Always use `make -f ci/prow.Makefile patch build` for downstream builds.
2. **Forgetting the build tag** — `go build ./cmd/operator-sdk` will fail without `-tags=containers_image_openpgp`.
3. **Editing upstream source directly** — changes will be overwritten on the next upstream merge. Use the `patches/` mechanism instead.
4. **Editing generated files** — `testdata/`, `doc/`, `internal/bindata/olm/` are generated. Run `make generate` or `make bindata`.
5. **Deleting vendor/** — downstream vendors all dependencies. Upstream does not. Do not remove.
6. **Wrong branch for sync** — `UPSTREAM-MERGE.sh` defaults to `main`. For release branches, pass the branch as the second argument.

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `IMAGE_VERSION` | `v1.42.3` (Makefile) | Helm/scorecard image version stamp |
| `K8S_VERSION` | `1.33.1` (Makefile) | Kubernetes version for tests |
| `KIND_VERSION` | `0.29.0` (Makefile) | KinD version for e2e setup |
| `GO_BUILD_TAGS` | `containers_image_openpgp` | Required build tag |
| `CGO_ENABLED` | `0` | CGO disabled for builds |
| `GO111MODULE` | `on` | Go modules enabled |
| `DRY_RUN` | `0` | Set to `1` for auto-rebase dry run |
| `OVERRIDE_TAG` | unset | Force a specific tag in auto-rebase |

## CI Configuration

- **ci-operator config**: `.ci-operator.yaml` pins builder image `rhel-9-release-golang-1.26-openshift-5.0`
- **Prow CI build**: `ci/prow.Makefile` — `patch` target applies patches, `build` target builds `helm-operator`
- **CI test scripts**: `ci/tests/` — `e2e-go.sh`, `e2e-helm.sh`, `subcommand.sh`

## Platform Conventions

For generic OpenShift development conventions and coding standards, see [openshift/enhancements](https://github.com/openshift/enhancements) — `dev-guide/`, `CONVENTIONS.md`.

## SME Review Recommended

- Patch maintenance strategy across major upstream version bumps
- Downstream-specific test coverage gaps vs upstream CI
