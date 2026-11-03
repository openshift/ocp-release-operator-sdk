# Architecture

## Repository Layout

```
ocp-release-operator-sdk/
├── cmd/
│   ├── operator-sdk/          # CLI entrypoint — delegates to internal/cmd/operator-sdk/cli
│   └── helm-operator/         # Helm Operator entrypoint — delegates to internal/cmd/helm-operator
├── internal/                  # Core implementation packages
│   ├── cmd/                   # CLI command implementations
│   │   ├── operator-sdk/cli/  # SDK CLI wiring (kubebuilder plugin system)
│   │   └── helm-operator/     # Helm Operator run + version subcommands
│   ├── helm/                  # Helm Operator core: controller, release manager, watches
│   │   ├── controller/        # controller-runtime based reconciler for Helm releases
│   │   ├── release/           # Helm release manager (install/upgrade/uninstall)
│   │   ├── watches/           # watches.yaml parser — GVK-to-chart mapping
│   │   ├── client/            # REST client factory for Helm actions
│   │   ├── flags/             # Helm Operator CLI flags
│   │   ├── metrics/           # Helm release metrics
│   │   ├── manifestutil/      # Manifest utilities
│   │   └── internal/          # Internal types (HelmAppCondition, HelmAppStatus) and diff utilities
│   ├── olm/                   # OLM integration: installer, operator management, FBC utils
│   ├── plugins/               # SDK-specific kubebuilder plugins (helm/v1, manifests/v2, scorecard/v2)
│   ├── scorecard/             # Scorecard test runner and configuration
│   ├── generate/              # CSV and packagemanifest generation
│   ├── validate/              # Bundle validation
│   ├── bindata/               # Embedded OLM manifests (generated — DO NOT hand-edit)
│   │   └── olm/               # manifests.go, versions.go
│   ├── registry/              # FBC (File-Based Catalog) index handling
│   ├── annotations/           # OLM bundle annotation parsing
│   ├── flags/                 # Common CLI flag helpers
│   ├── markers/               # Go code markers for SDK scaffolding
│   ├── testutils/             # Shared test utilities
│   ├── util/                  # General utilities (project detection, k8s helpers)
│   └── version/               # Version variables injected via ldflags
├── patches/                   # Downstream-only patches (applied sequentially in CI)
├── release/
│   ├── helm/                  # Helm Operator Dockerfile + entrypoint scripts
│   └── changelog/             # Changelog generation tooling
├── ci/
│   ├── prow.Makefile           # Downstream CI build: `patch` then `build`
│   └── tests/                 # CI test scripts (e2e-go, e2e-helm, subcommand)
├── hack/
│   ├── auto-rebase.sh         # Automated upstream rebase periodic (OAPE-829)
│   ├── generate/              # Code generation scripts (CLI docs, samples, OLM bindata)
│   └── tests/                 # Additional test scripts
├── images/                    # Dockerfiles for all SDK images
│   ├── helm-operator/         # Helm Operator image (primary deliverable)
│   ├── operator-sdk/          # SDK CLI image
│   ├── scorecard-test/        # Scorecard test image
│   ├── scorecard-test-kuttl/  # Scorecard KUTTL test image
│   ├── scorecard-storage/     # Scorecard storage image
│   ├── scorecard-untar/       # Scorecard untar helper image
│   └── custom-scorecard-tests/ # Custom scorecard test image
├── test/                      # Test suites
│   ├── e2e/                   # End-to-end tests (go/, helm/)
│   ├── integration/           # Integration tests (packagemanifests)
│   └── common/                # Shared test helpers
├── testdata/                  # Generated sample projects for testing
├── vendor/                    # Vendored dependencies (downstream-only)
├── website/                   # Upstream documentation site (Hugo, git submodule)
├── proposals/                 # Historical SDK design proposals
├── UPSTREAM-MERGE.sh          # Manual upstream merge script
├── UPSTREAM-VERSION           # Currently tracked upstream tag
├── Makefile                   # Primary build system
└── .ci-operator.yaml          # CI builder image configuration
```

## Key Domain Concepts

This repo is a **downstream mirror** (midstream) of [`operator-framework/operator-sdk`](https://github.com/operator-framework/operator-sdk). It is NOT an OpenShift operator itself — it provides **tooling** that helps others build operators.

### Primary Workflow

1. Upstream `operator-framework/operator-sdk` cuts a release tag (e.g., `v1.42.3`)
2. `UPSTREAM-MERGE.sh` merges that tag into the downstream `main` branch via `git merge`
3. Downstream patches in `patches/` are applied during CI builds (`make -f ci/prow.Makefile patch`)
4. CI builds the **Helm Operator** binary and image (`release/helm/Dockerfile`)
5. The Helm Operator image ships as part of OpenShift releases

### Two Binaries

| Binary | Purpose | Entrypoint |
|--------|---------|-----------|
| `operator-sdk` | CLI for scaffolding, bundle management, scorecard, OLM workflows | `cmd/operator-sdk/main.go` → `internal/cmd/operator-sdk/cli` |
| `helm-operator` | Runtime operator that reconciles Helm charts from CR specs | `cmd/helm-operator/main.go` → `internal/cmd/helm-operator` |

### Helm Operator Reconciliation Flow

1. `watches.yaml` defines GVK → Helm chart mappings (`internal/helm/watches/`)
2. For each watch, a controller-runtime controller is registered (`internal/helm/controller/controller.go`, `Add` function)
3. On CR create/update, the reconciler (`internal/helm/controller/reconcile.go`) invokes the release manager
4. The release manager (`internal/helm/release/manager.go`) uses Helm v3 actions (install/upgrade/rollback/uninstall)
5. Release status is reflected back to the CR's status conditions

## Component Details

### SDK CLI (operator-sdk)

Built on the [kubebuilder](https://github.com/kubernetes-sigs/kubebuilder) plugin system (`sigs.k8s.io/kubebuilder/v4/pkg/cli`). The CLI registers plugins from multiple sources:

| Plugin | Source | Purpose |
|--------|--------|---------|
| `go/v4` | kubebuilder | Go operator scaffolding |
| `ansible/v1` | `operator-framework/ansible-operator-plugins` | Ansible operator scaffolding |
| `helm/v1` | `internal/plugins/helm/v1` | Helm operator scaffolding |
| `manifests/v2` | `internal/plugins/manifests/v2` | OLM manifest generation |
| `scorecard/v2` | `internal/plugins/scorecard/v2` | Scorecard configuration |
| `deploy-image/v1alpha1` | kubebuilder | Deploy-image plugin |
| `grafana/v1alpha` | kubebuilder | Grafana dashboard plugin |

Plugin name suffix: `".sdk.operatorframework.io"` (`internal/plugins/plugins.go`, `DefaultNameQualifier` constant)

CLI commands: `bundle`, `cleanup`, `generate`, `olm`, `run`, `scorecard`, `pkgman-to-bundle` (`internal/cmd/operator-sdk/cli/cli.go`, `commands` variable)

### Helm Operator Runtime

Uses `controller-runtime` for the operator loop. Key types:

- `WatchOptions` (`internal/helm/controller/controller.go`) — configures a GVK watch with chart, reconcile period, and dependent watches
- `HelmOperatorReconciler` (`internal/helm/controller/reconcile.go`) — reconciles CRs by managing Helm releases
- `Manager` interface (`internal/helm/release/manager.go`) — wraps Helm v3 actions
- `ManagerFactory` (`internal/helm/release/manager_factory.go`) — creates release managers per CR

### Scorecard

Runs conformance and custom tests against deployed operators (`internal/scorecard/scorecard.go`). Tests execute as pods in the cluster. Configuration via `config.yaml` bundle annotation.

## Upstream Sync Process

The downstream-to-upstream relationship is the most important architectural concept:

| Step | Tool | Details |
|------|------|---------|
| **Manual merge** | `UPSTREAM-MERGE.sh` | Merges upstream tag into downstream branch, resolves conflicts by taking upstream |
| **Automatic rebase** | `hack/auto-rebase.sh` | Prow periodic (OAPE-829), discovers newest upstream `v*` tag beyond `UPSTREAM-VERSION` |
| **Patch application** | `make -f ci/prow.Makefile patch` | Applies `patches/*.patch` files sequentially |
| **Version tracking** | `UPSTREAM-VERSION` | Single file containing the currently tracked upstream tag |
| **Builder pin** | `.ci-operator.yaml` | Pins the CI builder image (`rhel-9-release-golang-1.26-openshift-5.0`) |

### Downstream Patches

Patches in `patches/` modify upstream source for downstream compatibility:

| Patch | Purpose |
|-------|---------|
| `00-fixsanity.patch` | Fix sanity check differences |
| `02-disable-security-context.patch` | Disable security context for CI |
| `03-setversion.patch` | Set downstream version stamps |
| `08-fix-downstream-stamps.patch` | Fix downstream build stamps |
| `09-do-not-use-docker.patch` | Use podman instead of docker |
| `12-skip-pkgman-docker-test.patch` | Skip tests requiring Docker |

**Creating patches**: Use the `gendiff` workflow documented in [README.md](../README.md#gendiff-method).

## Build System

### Version Injection

Build-time variables injected via ldflags (see `GO_BUILD_ARGS` in `Makefile`):

| Variable | Source | Package |
|----------|--------|---------|
| `Version` | `IMAGE_VERSION` (from Makefile) | `internal/version` |
| `GitVersion` | `git describe --dirty --tags --always` | `internal/version` |
| `GitCommit` | `git rev-parse HEAD` | `internal/version` |
| `KubernetesVersion` | `K8S_VERSION` constant | `internal/version` |
| `ImageVersion` | `IMAGE_VERSION` | `internal/version` |

### Build Tags

All Go builds require the `containers_image_openpgp` build tag (see `GO_BUILD_TAGS` in `Makefile`):
```
GO_BUILD_TAGS = containers_image_openpgp
```

### Image Build

| Image | Dockerfile | Base |
|-------|-----------|------|
| Helm Operator | `release/helm/Dockerfile` | `registry.ci.openshift.org/ocp/5.0:base-rhel9` |
| SDK CLI | `images/operator-sdk/Dockerfile` | upstream base |
| Scorecard Test | `images/scorecard-test/Dockerfile` | upstream base |

The Helm Operator Dockerfile uses a two-stage build: the builder stage applies patches and builds via `ci/prow.Makefile`, then copies the binary to a minimal RHEL 9 base.

## Generated Code Inventory

| What | Location | Generation Command |
|------|----------|-------------------|
| CLI documentation | `doc/` | `make generate` (runs `hack/generate/cli-doc/gen-cli-doc.go`) |
| Sample test projects | `testdata/` | `make generate` (runs `hack/generate/samples/generate_testdata.go`) |
| CNCF maintainers | `.cncf-maintainers` | `make generate` (runs `hack/generate/cncf-maintainers/main.go`) |
| OLM bindata | `internal/bindata/olm/` | `make bindata` (runs `hack/generate/olm_bindata.sh`) |

**NEVER hand-edit** these files — always regenerate with the appropriate `make` target.

## OLM Integration

The SDK provides tooling for OLM (Operator Lifecycle Manager) workflows:

- **Bundle management**: `operator-sdk bundle validate/create` (`internal/cmd/operator-sdk/bundle/`)
- **OLM installation**: `operator-sdk olm install/uninstall/status` (`internal/olm/`)
- **Run with OLM**: `operator-sdk run bundle` (`internal/cmd/operator-sdk/run/`)
- **CSV generation**: `operator-sdk generate kustomize manifests` (`internal/generate/`)
- **Package manifest migration**: `operator-sdk pkgman-to-bundle` (`internal/cmd/operator-sdk/pkgmantobundle/`)

OLM bindata for supported versions (0.26.0, 0.27.0, 0.28.0) is embedded in `internal/bindata/olm/` (see `OLM_VERSIONS` in `Makefile`).

## Error Handling

The Helm Operator reconciler uses standard controller-runtime requeue patterns (`internal/helm/controller/reconcile.go`):
- Failed Helm actions → update CR status conditions → requeue with backoff
- Release not found → install
- Release exists but values changed → upgrade
- CR deleted → uninstall (with finalizer)

## OpenShift Integration Points

| Integration | Details |
|-------------|---------|
| **CI System** | Prow-based CI via `ci/prow.Makefile`; ci-operator config in `.ci-operator.yaml` |
| **CI Build Root** | `.ci-operator.yaml` → `rhel-9-release-golang-1.26-openshift-5.0` (note: `release-` prefix) |
| **Dockerfile Builder** | `release/helm/Dockerfile` → `rhel-9-golang-1.26-openshift-5.0` (different tag, no `release-` prefix) |
| **Base Images** | `registry.ci.openshift.org/ocp/5.0:base-rhel9` |
| **Release Payload** | Helm Operator image included in OCP release payload |
| **Upstream Bot** | `openshift-app-platform-shift-bot` GitHub App for automated rebases |

## Design References

### Downstream Mirror Architecture (established)

**Decision**: Mirror upstream via `git merge` (not `git rebase`) with sequential patch application.
**Rationale**: Merge preserves upstream commit history intact, making conflict resolution and upstream tracking simpler. Patches provide a clear, auditable set of downstream-only changes.
**Consequences**: Patches must be maintained across upstream releases — they may fail to apply when upstream changes the patched files. The `gendiff` workflow provides a structured way to create and manage patches.

### Helm Operator as Primary Deliverable (OAPE-110)

**Decision**: Downstream-only `operator-sdk` binary packaging was removed. The primary downstream deliverable is the Helm Operator image.
**Rationale**: Simplifies the downstream build and release process by focusing on the component that ships in the OCP release payload.
**Consequences**: The `operator-sdk` CLI is still buildable and testable but is not packaged as a separate downstream image.

### Automated Rebase (OAPE-829)

**Decision**: A Prow periodic runs `hack/auto-rebase.sh` weekly to discover and merge new upstream tags.
**Rationale**: Reduces manual toil for tracking upstream releases while maintaining human review before merge.
**Consequences**: The bot opens PRs (or draft PRs on build failure) but never auto-merges. Patch conflicts and builder pin updates still require manual intervention.

## Platform Documentation

For generic OpenShift development patterns, coding standards, and contribution guidelines, refer to the [openshift/enhancements](https://github.com/openshift/enhancements) repository:

- `dev-guide/` — Development conventions and guides
- `guidelines/` — Enhancement proposal process
- `CONVENTIONS.md` — Coding standards

## SME Review Recommended

- Patch compatibility testing across major upstream version bumps
- Helm Operator performance characteristics under high CRD counts
- Interaction between the Helm Operator and OCP-specific admission webhooks or network policies
