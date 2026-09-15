# Architecture

This document captures institutional knowledge about the OpenShift Operator SDK's design, the reasoning behind key architectural decisions, and how the major subsystems fit together.

## System Overview

The Operator SDK is a toolkit for building, testing, and packaging Kubernetes operators. This repository (`ocp-release-operator-sdk`) is the downstream OpenShift fork of [operator-framework/operator-sdk](https://github.com/operator-framework/operator-sdk), tracking upstream version v1.42.3. The Go module path remains `github.com/operator-framework/operator-sdk` -- it retains the upstream path to minimize import churn.

The repository produces **two distinct CLI binaries** from a single Go module:

- **`operator-sdk`** -- A developer CLI for scaffolding, building, validating, and running operators. It wraps kubebuilder's CLI framework (`cli.New()`) and injects SDK-specific commands and plugins.
- **`helm-operator`** -- A runtime binary deployed inside a container that reconciles Helm-based operators. It uses raw Cobra and controller-runtime directly.

Both binaries share implementation code from `internal/` but have separate entry points (`cmd/operator-sdk/main.go`, `cmd/helm-operator/main.go`) and separate command trees (`internal/cmd/operator-sdk/`, `internal/cmd/helm-operator/`).

## Why Everything Is Internal

There is no `pkg/` directory. All implementation code lives under `internal/`, which means nothing is exported as a Go library. This is a deliberate decision:

1. **The SDK is a tool, not a library.** External consumers interact through CLI binaries, not Go imports. Keeping everything internal avoids the burden of maintaining a stable Go API surface.
2. **Freedom to refactor.** Internal packages can change signatures, restructure, or merge without breaking external consumers.
3. **Upstream alignment.** The upstream operator-sdk made this same choice, and diverging would complicate rebases.

## Why Two Binaries Share One Module

A single Go module contains both `cmd/operator-sdk` and `cmd/helm-operator` because:

1. **Shared subsystems.** The Helm plugin in `operator-sdk` (scaffolding) and the `helm-operator` runtime both use `internal/helm/`. Splitting into separate modules would require extracting shared code into a library -- contradicting the "everything internal" design.
2. **Coordinated releases.** Both binaries track the same upstream version and share version injection (`internal/version/`). A single module ensures version consistency.
3. **Simplified vendoring.** One `vendor/` directory, one `go.mod`, one set of dependency updates.

The tradeoff is that building either binary pulls in the entire dependency graph, but static binaries with `CGO_ENABLED=0` mitigate the runtime cost.

## High-Level Architecture

```text
cmd/
  operator-sdk/main.go ─── internal/cmd/operator-sdk/cli/cli.go
  │                          │
  │                          ├── kubebuilder cli.New() framework
  │                          │     └── Plugin bundles (go/v4, helm/v1, ansible/v1)
  │                          │           ├── internal/plugins/helm/v1/
  │                          │           ├── internal/plugins/manifests/v2/
  │                          │           └── internal/plugins/scorecard/v2/
  │                          │
  │                          └── Extra commands (not plugin-based)
  │                                ├── bundle     (validate, create)
  │                                ├── run        (bundle, bundle-upgrade)
  │                                ├── cleanup    (remove OLM-managed operators)
  │                                ├── olm        (install, uninstall, status)
  │                                ├── generate   (bundle, kustomize)
  │                                ├── scorecard  (run conformance tests)
  │                                └── pkgmantobundle
  │
  helm-operator/main.go ─── internal/cmd/helm-operator/run/
                              │
                              ├── watches.yaml loading
                              ├── controller-runtime manager setup
                              └── Per-GVK controller registration
                                    ├── internal/helm/controller/   (reconciler)
                                    ├── internal/helm/release/      (Helm release manager)
                                    ├── internal/helm/client/       (action config)
                                    └── internal/helm/watches/      (config parsing)
```

## Plugin Architecture

The `operator-sdk` CLI delegates scaffolding commands (`init`, `create api`, `create webhook`) to kubebuilder's plugin system. SDK-specific plugins use the `.sdk.operatorframework.io` naming suffix (defined in `internal/plugins/plugins.go`) to distinguish them from upstream kubebuilder plugins.

Plugins are composed into **bundles** -- ordered collections that each handle a phase of scaffolding. For example, the Go bundle chains: `kustomize/v2` (base kustomize layout) + `golang/v4` (Go scaffolding) + `manifests/v2` (OLM manifest generation) + `scorecard/v2` (scorecard config). This composition means adding OLM support to a new operator type requires only adding `manifests/v2` and `scorecard/v2` to its bundle.

Each plugin implements kubebuilder interfaces (`plugin.Init`, `plugin.CreateAPI`) with compile-time assertions (`var _ plugin.Plugin = Plugin{}`). The plugin key (`name + version`) determines which plugin handles a given project.

**Extension point:** To add a new operator type, create a new plugin under `internal/plugins/<type>/v1/`, implement the kubebuilder interfaces, and register it as a bundle in `internal/cmd/operator-sdk/cli/cli.go`.

## Helm Operator Data Flow

The helm-operator binary follows this flow at startup:

1. **Load watches.yaml** -- Each entry maps a GVK (Group/Version/Kind) to a Helm chart directory, with optional label selectors, reconcile periods, and override values.
2. **Create controller-runtime Manager** -- Configures namespace scoping, cache selectors (optimized to watch only resources labeled with the chart name), and health/readiness probes.
3. **Register one controller per watch entry** -- Each controller watches its GVK using `source.Kind()` and optionally watches dependent resources discovered from Helm release manifests.

During reconciliation (`HelmOperatorReconciler.Reconcile`):

1. Fetch the CR (custom resource) from the API server.
2. Create a Helm release `Manager` via `ManagerFactory` -- this loads the chart, merges CR `.spec` values with override values, and configures the Helm action.
3. Compare desired state (chart + values) against current Helm release state.
4. Install, upgrade, or reconcile the release as needed. On CR deletion, the uninstall finalizer (`helm.sdk.operatorframework.io/uninstall-release`) triggers Helm uninstall.
5. If `WatchDependentResources` is enabled, a release hook dynamically adds watches for every resource type found in the rendered Helm manifest. This uses owner references (same-namespace) or annotations (cross-namespace) for enqueue mapping.

**Key design choice:** The `ManagerFactory` interface decouples reconciliation logic from Helm backend details. The factory is created once at startup, but produces a fresh `Manager` for each reconciliation, ensuring the chart and values reflect the current CR state.

## OLM Integration

OLM (Operator Lifecycle Manager) integration is central to the SDK and spans several subsystems:

- **`internal/olm/installer/`** -- Installs/uninstalls OLM itself on a cluster. Embeds OLM release manifests via go-bindata (`internal/bindata/`).
- **`internal/olm/operator/`** -- Manages operator lifecycle through OLM. The install flow follows a strict ordering: CatalogSource, OperatorGroup, Subscription, InstallPlan, CSV. The `OperatorInstaller` orchestrates this sequence.
- **`internal/olm/fbcutil/`** -- File-Based Catalog utilities for building OLM index images.
- **`internal/generate/clusterserviceversion/`** -- Generates CSV manifests from Go source annotations, CRDs, and RBAC rules. Uses a `collector.Manifests` struct to aggregate inputs.

The `operator-sdk run bundle` command demonstrates end-to-end OLM integration: it builds an index image containing the operator's bundle, creates a CatalogSource pointing to that image, then creates the Subscription/OperatorGroup to trigger OLM's install machinery.

## Code Generation

The `internal/generate/` package handles generating OLM artifacts:

- **CSV Generator** (`clusterserviceversion/`) -- Produces ClusterServiceVersion YAML from collected manifests. Uses a base CSV (from `bases/`) and enriches it with CRDs, RBAC rules, deployment specs, and related images.
- **Package Manifest Generator** (`packagemanifest/`) -- Generates legacy package manifest format (deprecated in favor of bundles).
- **Collector** (`collector/`) -- Aggregates manifests from the filesystem (CRDs, RBAC, deployments) into a unified structure consumed by generators.

## Scorecard

The scorecard system (`internal/scorecard/`) runs conformance tests against operator bundles. It uses a pod-based test runner (`PodTestRunner`) that:

1. Creates a ConfigMap with the bundle contents.
2. Launches test pods that mount the bundle and execute test images.
3. Collects results via the scorecard API (`v1alpha3.TestList`).

Tests run in configurable stages (parallel or sequential). A `FakeTestRunner` exists for unit testing the scorecard orchestration without a cluster.

**Extension point:** Custom scorecard tests are container images conforming to the scorecard test interface. Add test configurations to `scorecard/config.yaml` in the operator bundle.

## Version Injection

Five variables in `internal/version/` are populated at build time via `-ldflags`:

| Variable | Source | Purpose |
|---|---|---|
| `Version` | `SIMPLE_VERSION` | Human-readable version |
| `GitVersion` | `git describe --dirty --tags --always` | Precise git version |
| `GitCommit` | `git rev-parse HEAD` | Exact commit hash |
| `KubernetesVersion` | `K8S_VERSION` in Makefile | Target k8s compatibility |
| `ImageVersion` | `IMAGE_VERSION` in Makefile | Subproject image tag |

Downstream overrides `SIMPLE_VERSION` and `GIT_VERSION` to `v1.42.3-ocp` via `patches/03-setversion.patch`.

## Key Dependencies

| Dependency | Role |
|---|---|
| `sigs.k8s.io/kubebuilder/v4` | Plugin system, CLI framework, project scaffolding |
| `sigs.k8s.io/controller-runtime` | Controller lifecycle, manager, caching, client (helm-operator) |
| `helm.sh/helm/v3` | Chart loading, release management, template rendering |
| `github.com/operator-framework/api` | OLM API types (CSV, Subscription, CatalogSource) |
| `github.com/operator-framework/operator-registry` | Bundle format, FBC (File-Based Catalog) |
| `github.com/operator-framework/operator-lib` | Shared operator utilities (predicate, handler) |
| `github.com/operator-framework/ansible-operator-plugins` | Ansible plugin (external, imported as dependency) |
| `github.com/spf13/cobra` | CLI command framework |
| `github.com/sirupsen/logrus` | Logging for operator-sdk CLI |

## Downstream Fork Architecture

### The Patch System

The downstream fork keeps upstream source as pristine as possible. Instead of modifying upstream files directly, changes are captured as patches in `patches/` and applied during CI builds via `make -f ci/prow.Makefile patch`. Each patch uses `diff -up` format and is applied sequentially:

| Patch | Purpose |
|---|---|
| `00-fixsanity` | Adjusts sanity checks for downstream environment |
| `02-disable-security-context` | Removes security contexts unsupported in CI |
| `03-setversion` | Overrides version strings to `v1.42.3-ocp` |
| `08-fix-downstream-stamps` | Fixes build timestamp injection |
| `09-do-not-use-docker` | Replaces Docker references (CI lacks Docker) |
| `12-skip-pkgman-docker-test` | Skips tests requiring Docker |

This design means the `main` branch always contains unpatched upstream code plus downstream-only additions (`ci/`, `patches/`, `images/`). Patches are applied transiently during builds, never committed to source.

### Dual CI Systems

- **Upstream CI** (GitHub Actions in `.github/workflows/`): Runs upstream's test suite. Largely untouched.
- **Downstream CI** (OpenShift Prow via `ci/prow.Makefile`): Applies patches first, then builds and tests. Only builds `helm-operator` (not `operator-sdk`) because the downstream only ships the Helm operator binary. E2E tests run in OpenShift CI infrastructure without Docker.

### Upstream Sync Process

Rebasing to a new upstream release uses `UPSTREAM-MERGE.sh`, which:

1. Creates a branch from the target downstream branch.
2. Merges the upstream tag, preferring upstream for conflicts.
3. Produces a merge commit listing all incoming upstream changes.
4. The developer then verifies patches still apply and creates a PR.

Downstream-specific commits use prefixes: `UPSTREAM: <carry>:` (persists across rebases) or `UPSTREAM: <drop>:` (regenerated each rebase, e.g., vendor updates).

## Extension Points Summary

| To add... | Where |
|---|---|
| New operator type scaffolding | `internal/plugins/<type>/v1/`, register in `cli.go` |
| New CLI command | `internal/cmd/operator-sdk/<command>/`, add to `cli.go` commands slice |
| New scorecard test | Container image + config entry in bundle's `scorecard/config.yaml` |
| New OLM version support | Update `internal/bindata/` via `make bindata`, update `OLM_VERSIONS` in Makefile |
| New downstream patch | Create backup files, modify originals, run `gendiff`, add to `patches/` |
| New Helm watch configuration | Add entry to `watches.yaml` (runtime configuration, no code change) |
