# Architecture: Components

For the full architectural rationale, see [docs/ARCHITECTURE.md](../../../docs/ARCHITECTURE.md).

## Repository Layout

```
cmd/                      # Binary entry points (operator-sdk, helm-operator)
internal/                 # ALL implementation code (nothing exported as a Go library)
  cmd/                    # CLI command implementations (mirrors cmd/ structure)
  generate/               # Code generation (CSV, package manifests)
  helm/                   # Helm operator runtime (controller, release, watches)
  olm/                    # OLM install/client/operator logic
  plugins/                # Kubebuilder plugins (helm/v1, manifests/v2, scorecard/v2)
  scorecard/              # Scorecard test runner and built-in tests
  util/                   # Shared utilities (bundleutil, k8sutil, projutil)
  validate/               # Bundle validation
  version/                # Version info (injected via ldflags at build time)
test/                     # E2E and integration tests
testdata/                 # Generated sample projects (never hand-edited)
hack/                     # Build, check, and generation scripts
ci/                       # OpenShift Prow configuration (downstream only)
patches/                  # Downstream-only patches applied during Prow CI
images/                   # Production container image Dockerfiles
release/                  # Release tooling (goreleaser, changelog)
vendor/                   # Vendored dependencies (committed, unlike upstream)
changelog/fragments/      # Changelog entries for PRs (YAML format)
```

## Two Binaries, One Module

| Binary | Entry Point | CLI Framework | Purpose |
|---|---|---|---|
| `operator-sdk` | `cmd/operator-sdk/main.go` | kubebuilder `cli.New()` | Developer CLI: scaffold, build, validate operators |
| `helm-operator` | `cmd/helm-operator/main.go` | raw Cobra | Runtime: reconcile Helm-based operators |

Both share code from `internal/` but have separate command trees.

## Why Everything Is Internal

There is no `pkg/` directory. All implementation code lives under `internal/`. This is deliberate:

1. The SDK is a tool, not a library. External consumers interact through CLI binaries.
2. Freedom to refactor without breaking external consumers.
3. Upstream alignment (upstream made the same choice).

## OLM Integration

Much of the codebase revolves around OLM (Operator Lifecycle Manager). The install flow: CatalogSource -> OperatorGroup -> Subscription -> InstallPlan -> CSV. The `internal/olm/` package handles this lifecycle. OLM data is embedded via go-bindata in `internal/bindata/`.

## Version Injection

Five variables injected at build time via ldflags into `internal/version/`:

| Variable | Source |
|---|---|
| `Version` | `SIMPLE_VERSION` (Makefile) |
| `GitVersion` | `git describe --dirty --tags --always` |
| `GitCommit` | `git rev-parse HEAD` |
| `KubernetesVersion` | `K8S_VERSION` (Makefile) |
| `ImageVersion` | `IMAGE_VERSION` (Makefile) |

Downstream overrides `SIMPLE_VERSION` to `v1.42.3-ocp` via `patches/03-setversion.patch`.

## Downstream Fork Model

This repository is a downstream fork. Key conventions:

- **Commit prefixes**: `UPSTREAM: <carry>:` (persistent) or `UPSTREAM: <drop>:` (temporary)
- **Patch system**: `patches/` applied by `make -f ci/prow.Makefile patch`
- **Vendored deps**: Committed `vendor/` directory (required by downstream build infra)
