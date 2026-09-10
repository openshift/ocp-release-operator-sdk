# Build and Release Guidelines

## Repository Structure

This is the OpenShift downstream fork of `operator-framework/operator-sdk`. The upstream remote must point to `https://github.com/operator-framework/operator-sdk.git`. The current upstream version is tracked in the `UPSTREAM-VERSION` file.

## Upstream Merge Process

Run `./UPSTREAM-MERGE.sh <version> [branch] [remote]` to merge a new upstream tag. The script:

1. Creates a branch named `<version>-rebase-<branch>`
2. Merges the upstream tag, resolving all conflicts by taking upstream's version
3. Preserves `OWNERS_ALIASES` and `README.md` from downstream
4. Copies upstream README to `README-sdk.md`
5. Updates `UPSTREAM-VERSION` with the new tag
6. Updates `patches/03-setversion.patch` to append `-ocp` to the new version
7. Runs `go mod tidy && go mod vendor` and commits vendor changes separately

After merging, vendor changes are committed as `UPSTREAM: <drop>: Update vendor directory`.

## Commit Message Conventions

All downstream-specific commits must use one of two prefixes:

- `UPSTREAM: <carry>:` -- Changes that must survive future upstream merges (fixes, OpenShift adaptations). These are manually re-applied after each merge.
- `UPSTREAM: <drop>:` -- Changes that are regenerated or no longer needed after the next merge (vendor updates, generated code).

## Downstream Patch System

The `patches/` directory contains diff files applied before CI builds via `make -f ci/prow.Makefile patch`:

```shell
for i in ./patches/*.patch; do patch -p0 < "$i" || exit 1; done
```

Patches use a numbered naming scheme (`NN-description.patch`) and modify the upstream Makefile and test files for downstream compatibility. Current patches:

| Patch | Purpose |
|---|---|
| `00-fixsanity` | Removes `go mod tidy` from `fix`, adjusts `test-sanity` to not run `generate`, adds build tags |
| `02-disable-security-context` | Disables security context in Helm test values for CI |
| `03-setversion` | Hardcodes `SIMPLE_VERSION` to `<version>-ocp` instead of git-derived |
| `08-fix-downstream-stamps` | Adds `-ocp` suffix handling in metrics version parsing |
| `09-do-not-use-docker` | Comments out Docker base image usage in pkgmantobundle tests |
| `12-skip-pkgman-docker-test` | Skips tests requiring Docker in CI |

To create a new patch, use the standard `diff -up` format against the original file with a `.patchname` suffix:

```shell
diff -up ./path/file.patchname ./path/file > ./patches/NN-description.patch
```

## Build System

### Build Tags

Always pass `-tags=containers_image_openpgp` (via `GO_BUILD_TAGS`). This is required for `containers/image` compatibility. Omitting it causes build failures.

### CGO

CGO is disabled (`CGO_ENABLED=0`) for all production builds. Unit tests re-enable it (`CGO_ENABLED=1`) for race detection.

### Key Make Targets

| Target | Purpose |
|---|---|
| `build` | Builds `operator-sdk` and `helm-operator` into `build/` |
| `build/operator-sdk` | Builds only operator-sdk |
| `build/helm-operator` | Builds only helm-operator |
| `install` | Installs binaries to `$GOBIN` |
| `test-sanity` | Formatting, linting, license checks, `go vet` |
| `test-unit` | Unit tests with race detection |
| `test-e2e` | Full e2e suite (requires KIND cluster) |
| `image-build` | Builds all container images |
| `lint` | Runs golangci-lint |
| `fix` | Auto-formats code and fixes lint issues |

### Version Injection

Five ldflags are injected at build time via `GO_BUILD_ARGS`:

- `internal/version.Version` -- from `SIMPLE_VERSION` (downstream: `v1.42.3-ocp`)
- `internal/version.GitVersion` -- from `GIT_VERSION` (downstream: same as `SIMPLE_VERSION`)
- `internal/version.GitCommit` -- from `git rev-parse HEAD`
- `internal/version.KubernetesVersion` -- from `K8S_VERSION` in Makefile
- `internal/version.ImageVersion` -- from `IMAGE_VERSION` in Makefile

`IMAGE_VERSION` must be updated in the Makefile to match `RELEASE_VERSION` before creating a release commit.

## Container Images

### Production Images (in `images/`)

All production Dockerfiles use multi-stage builds:

- Builder stage: `golang:1.26` with `BUILDPLATFORM`/`TARGETARCH` for cross-compilation
- Runtime stage: `registry.access.redhat.com/ubi9/ubi-minimal:9.8`

Supported platforms: `linux/amd64`, `linux/arm64`, `linux/ppc64le`, `linux/s390x`.

### CI Images (in `ci/dockerfiles/`)

CI Dockerfiles reference `osdk-builder` as a base image (built from `ci/dockerfiles/builder.Dockerfile`). The builder image uses `openshift/origin-release:golang-*` and runs `make -f ci/prow.Makefile patch build`.

### CI-Operator Base Image

Defined in `.ci-operator.yaml`:

```yaml
build_root_image:
  name: release
  namespace: openshift
  tag: rhel-9-release-golang-1.26-openshift-5.0
```

Update this tag when changing Go versions downstream (use `UPSTREAM: <carry>:` commit prefix).

## CI/CD

### Prow (OpenShift CI)

The `ci/prow.Makefile` is the entry point for Prow jobs. It always runs `patch` before build or test targets to apply downstream patches. Key targets:

- `patch` -- Applies all patches from `patches/`
- `build` -- Delegates to main Makefile's `build/helm-operator`
- `test-e2e-go` / `test-e2e-helm` -- E2E tests with patches applied first

### GitHub Actions (Upstream)

Workflows in `.github/workflows/` handle upstream CI. These workflows are preserved from upstream but are not the primary CI for the downstream fork.

## Release Process

### Upstream Release (goreleaser)

1. Set `RELEASE_VERSION` and update `IMAGE_VERSION` in Makefile to match
2. `make prerelease` -- generates changelog, updates website
3. `make tag` -- creates a signed git tag matching pattern `v*.*.*` or `v*.*.*-(alpha|beta|rc).*`
4. `make release` -- runs goreleaser to build cross-platform binaries and publish

### Downstream Version Scheme

Downstream versions append `-ocp` to the upstream version (e.g., `v1.42.3-ocp`). This is enforced by `patches/03-setversion.patch` which hardcodes `SIMPLE_VERSION` and `GIT_VERSION`. The metrics parsing code in `internal/annotations/metrics/metrics.go` is also patched to recognize the `-ocp` suffix.

## Vendor Management

- The vendor directory is committed to the repository
- After upstream merges, run `go mod tidy && go mod vendor`
- Vendor updates get their own commit: `UPSTREAM: <drop>: Update vendor directory`
- The CI builder uses `GOFLAGS=-mod=vendor` to ensure builds use vendored dependencies
- Do not run `go mod tidy` as part of `make fix` downstream (removed by `00-fixsanity.patch`)

## Linting

golangci-lint is fetched on-demand via `tools/scripts/fetch golangci-lint`. The configuration in `.golangci.yml` enables `dupl`, `ginkgolinter`, `goconst`, `gocyclo`, `gosec`, `misspell`, `nakedret`, `revive`, `unconvert`, and `unparam`. Dot imports are allowed only for ginkgo/gomega. Every source file must have a license header (checked by `hack/check-license.sh`).

## Binary Outputs

Two CLI binaries are built from `cmd/`:

- `operator-sdk` -- The main SDK CLI
- `helm-operator` -- Helm-based operator runtime

Additional scorecard binaries are built from `images/`. All binaries go to the `build/` directory (cleaned by `make clean`). Tools go to `tools/bin/`.
