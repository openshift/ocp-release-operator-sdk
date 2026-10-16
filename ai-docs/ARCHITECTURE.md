# Architecture

## Repository Layout

This is downstream packaging plus SDK source, not a single cluster operator.
Start with [the downstream overview](../README.md) and
[the upstream SDK overview](../README-sdk.md).

| Path | Responsibility and navigation |
|---|---|
| `cmd/operator-sdk/` | SDK executable; delegates to `cli.Run` (`cmd/operator-sdk/main.go:28`) |
| `cmd/helm-operator/` | Runtime executable; registers run and version commands (`cmd/helm-operator/main.go:29`) |
| `internal/cmd/operator-sdk/` | SDK command implementations (`internal/cmd/operator-sdk/cli/cli.go:55`) |
| `internal/helm/` | Helm watches, controller, and release machinery (`internal/helm/controller/controller.go:59`) |
| `internal/plugins/` | Local Helm, manifests, and scorecard scaffolding (`internal/cmd/operator-sdk/cli/cli.go:46`) |
| `internal/bindata/olm/` | Embedded generated OLM assets (`internal/bindata/olm/manifests.go:1`) |
| `patches/` | Downstream patches; apply before downstream compilation (`ci/prow.Makefile:12`) |
| `release/helm/` | Downstream Helm image packaging (`release/helm/Dockerfile:1`) |
| `testdata/` | Generated samples; `make generate` removes and recreates them (`Makefile:43`) |
| `website/` | Website sources; link checks build this tree (`hack/check-links.sh:9`) |

Do not treat the sample operators as the downstream runtime implementation.
Sample regeneration and runtime compilation are separate targets (`Makefile:43`, `Makefile:98`).

## Key Domain Concepts

### SDK executable

`operator-sdk` starts through `cli.Run` (`cmd/operator-sdk/main.go:29`).
`GetPluginsCLIAndRoot` assembles the plugin-aware CLI (`internal/cmd/operator-sdk/cli/cli.go:84`).

The CLI combines scaffolding plugins with extra SDK commands.
The extra command list includes bundle, cleanup, generate, OLM, run,
scorecard, and package-manifest conversion (`internal/cmd/operator-sdk/cli/cli.go:55`).

The default configuration version is v3, with the Go v4 bundle selected by default
(`internal/cmd/operator-sdk/cli/cli.go:124`).

### Helm runtime

`helm-operator` is a separate executable, not an SDK CLI subcommand
(`cmd/helm-operator/main.go:29`).
Its root registers `run` and `version` (`cmd/helm-operator/main.go:38`).

The runtime reads a watches file and creates controllers for the configured GVKs
(`internal/cmd/helm-operator/run/cmd.go:147`).
Each watch ties a custom-resource kind to a Helm chart directory
(`internal/helm/watches/watches.go:36`).

### End-to-end runtime flow

1. `run` loads watches and prepares manager options (`internal/cmd/helm-operator/run/cmd.go:147`).
2. It creates a controller-runtime manager (`internal/cmd/helm-operator/run/cmd.go:163`).
3. It constructs a release manager factory for each chart (`internal/cmd/helm-operator/run/cmd.go:190`).
4. `controller.Add` registers a watch for the primary resource (`internal/helm/controller/controller.go:59`).
5. `HelmOperatorReconciler.Reconcile` handles the requested CR (`internal/helm/controller/reconcile.go:79`).
6. Release operations install, upgrade, or reconcile chart resources (`internal/helm/release/manager.go:169`).

## Component Details

### CLI plugin composition

| Bundle | Composition source |
|---|---|
| Go v4 | Kustomize, Go v4, manifests, scorecard (`internal/cmd/operator-sdk/cli/cli.go:73`) |
| Ansible v1 | External Ansible plugin plus Kustomize, manifests, scorecard (`internal/cmd/operator-sdk/cli/cli.go:84`) |
| Helm v1 | Local Helm plugin plus Kustomize, manifests, scorecard (`internal/cmd/operator-sdk/cli/cli.go:95`) |
| Deploy-image alpha | Deploy-image plugin plus manifests (`internal/cmd/operator-sdk/cli/cli.go:106`) |

Do not infer local Ansible runtime ownership from the SDK's plugin import.
The Ansible scaffolding import is `ansible-operator-plugins` (`internal/cmd/operator-sdk/cli/cli.go:32`).

### Runtime startup

Watches are loaded before the manager starts (`internal/cmd/helm-operator/run/cmd.go:147`).
Namespace configuration and cache selectors are prepared before `manager.New`
(`internal/cmd/helm-operator/run/cmd.go:153`).

The startup installs health and readiness ping checks
(`internal/cmd/helm-operator/run/cmd.go:169`).
The manager starts with a signal-handler context (`internal/cmd/helm-operator/run/cmd.go:209`).

### Controller framework

| Controller | Framework | Registration |
|---|---|---|
| Helm per-watch controller | controller-runtime | `controller.New` in `internal/helm/controller/controller.go:74` |

`WatchOptions` carries the GVK, manager factory, period, overrides,
dependent-watch switch, concurrency, selector, and dry-run option
(`internal/helm/controller/controller.go:46`).

The controller name is derived from the lowercased kind
(`internal/helm/controller/controller.go:60`).
Dependent-resource watches are installed only when enabled
(`internal/helm/controller/controller.go:89`).

## Resource Management

### Separate CR writes from chart writes

| Object | Write mechanism | Source |
|---|---|---|
| Primary CR metadata/spec | controller-runtime `Client.Update`, with retry | `internal/helm/controller/reconcile.go:480` |
| Primary CR status | `Client.Status().Update`, with retry | `internal/helm/controller/reconcile.go:486` |
| Missing chart resource during drift repair | resource helper `Create` | `internal/helm/release/manager.go:285` |
| Existing chart resource during drift repair | resource helper `Patch` | `internal/helm/release/manager.go:308` |

Do not describe the Helm drift-repair path as server-side apply.
Read `createPatch` rather than inferring patch semantics from comments
(`internal/helm/release/manager.go:317`).

### Patch-type split

Unstructured objects and CRDs take the JSON patch path.
Despite the helper name `createJSONMergePatch`, that branch returns
`apitypes.JSONPatchType` (`internal/helm/release/manager.go:341`).

Other versioned objects use a strategic three-way merge patch
(`internal/helm/release/manager.go:352`).
Empty strategic patches are suppressed (`internal/helm/release/manager.go:358`).

### Install and upgrade

`InstallRelease` and `UpgradeRelease` wrap Helm action execution
(`internal/helm/release/manager.go:169`, `internal/helm/release/manager.go:213`).
Drift correction is a separate `ReconcileRelease` path
(`internal/helm/release/manager.go:267`).

### Downstream image resolution

The downstream Dockerfile builds from the repository's vendored dependencies
with `GOFLAGS=-mod=vendor` (`release/helm/Dockerfile:3`).
It applies patches and builds the Helm executable before copying it into the runtime image
(`release/helm/Dockerfile:8`).

The image entrypoint runs Helm with `./watches.yaml`
(`release/helm/Dockerfile:25`).
SDK scaffold image-version injection is separately defined in the root Makefile
(`Makefile:29`, `internal/version/version.go:25`).

## Feature Configuration

For this runtime, start with watch configuration and CLI flags rather than
assuming a platform FeatureGate chain (`internal/cmd/helm-operator/run/cmd.go:69`).

`Watch` contains `watchDependentResources`, overrides, a label selector,
reconcile period, and a dry-run option (`internal/helm/watches/watches.go:36`).
Startup forwards these watch settings into `WatchOptions`
(`internal/cmd/helm-operator/run/cmd.go:190`).

## Error Classification

Invalid watch configuration is returned as an error from `LoadReader`
(`internal/helm/watches/watches.go:87`).
Startup logs a watch-loading failure and exits nonzero
(`internal/cmd/helm-operator/run/cmd.go:148`).

Reconciliation has separate uninstall, install, and upgrade error paths;
inspect their condition handling before changing retry semantics
(`internal/helm/controller/reconcile.go:130`, `internal/helm/controller/reconcile.go:237`).

The SDK main function treats a returned CLI error as fatal
(`cmd/operator-sdk/main.go:29`).
This is distinct from warning-only bundle validation, documented in command help
(`internal/cmd/operator-sdk/bundle/validate/cmd.go:31`).

## OpenShift Integration Points

| Boundary | Repository evidence | Scope |
|---|---|---|
| Go builder selection | `.ci-operator.yaml:1` | Build-root image configuration, not a runtime support guarantee |
| Helm downstream container | `release/helm/Dockerfile:1` | Patch/build stage and runtime entrypoint |
| OLM tooling | `internal/cmd/operator-sdk/cli/cli.go:54` | SDK command registration |
| Dependency module identity | `go.mod:1` | Remains `github.com/operator-framework/operator-sdk` |

The build-root configuration alone does not describe live Prow job scheduling.
For local downstream behavior use the wrapper (`ci/prow.Makefile:1`).

## Generated Code Inventory

| Output | Regeneration entry point |
|---|---|
| CLI docs and samples | `make generate` (`Makefile:42`) |
| Embedded OLM manifests | `make bindata` (`Makefile:51`) |
| Counterfeiter generator fake | `go:generate` directive (`internal/generate/packagemanifest/packagemanifest.go:48`) |

Never hand-edit `internal/bindata/olm/manifests.go`; its header identifies generated code.
`make bindata` also invokes `make fix`, so inspect its full diff (`Makefile:53`).

## API Behavioral Contracts

### Watch loading

Use `Load` or `LoadReader`, not the deprecated `UnmarshalYAML` hook
(`internal/helm/watches/watches.go:47`).
The loader checks version and kind; an empty group is allowed
(`internal/helm/watches/watches.go:149`).

Duplicate GVKs are rejected (`internal/helm/watches/watches.go:111`).
Each chart directory is validated (`internal/helm/watches/watches.go:107`).
An omitted dependent-watch switch defaults to true (`internal/helm/watches/watches.go:115`).

### Override evaluation

Override strings first expand environment variables, then execute text templates
with Sprig functions (`internal/helm/watches/watches.go:128`).
Malformed templates fail loading rather than silently falling back
(`internal/helm/watches/watches.go:138`).

### Reconcile period

A nonzero per-watch period overrides the CLI-level period at startup
(`internal/cmd/helm-operator/run/cmd.go:185`).
The reconciler additionally handles a resource annotation through
`determineReconcilePeriod` (`internal/helm/controller/reconcile.go:434`).

## Deployment Scope

Runtime namespace selection reads `WATCH_NAMESPACE` through the shared constant
(`internal/cmd/helm-operator/run/cmd.go:224`).
Do not interpret namespace selection as a certification for SNO, hosted control
planes, or MicroShift; this guide makes no support claim for those topologies.

## Design References

### Downstream patches stay separate

The downstream workflow keeps patches in `patches/` and applies them sequentially
with `patch -p0` (`ci/prow.Makefile:12`).
This keeps the carried changes visible separately from the mirrored source.
See [Patching](../README.md#patching) for the documented contribution workflow.

### Scaffolding and runtime are separate entrypoints

The SDK CLI assembles plugins; the Helm executable registers runtime commands
(`internal/cmd/operator-sdk/cli/cli.go:84`, `cmd/helm-operator/main.go:29`).
Changing one executable is not evidence that the other path was exercised.
See [design catalog](ENHANCEMENTS.md) for repository proposals.

## Platform Documentation

- [Development guidance](https://github.com/openshift/enhancements/tree/master/dev-guide)
- [Enhancement process](https://github.com/openshift/enhancements/tree/master/guidelines)
- [Platform conventions](https://github.com/openshift/enhancements/blob/master/CONVENTIONS.md)

## SME Review Recommended

Validate release-specific image availability and deployment support with maintainers;
source inspection here describes behavior, not product support or certification.
