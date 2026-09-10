# Integration Guidelines

## OLM Integration

### Scheme Registration

Always register OLM API types via `AddToScheme` before creating clients. The codebase uses an `init()` pattern in `internal/olm/client/client.go` for `v1alpha1` and explicit registration loops in `internal/olm/operator/config.go` for both `v1` and `v1alpha1`. When adding new OLM API versions, add them to the `Configuration.Load()` registration loop alongside `apiextv1.AddToScheme`.

### Field Ownership

All objects created through the OLM operator client must use `client.FieldOwner("operator-sdk")`. The `operatorClient` wrapper in `internal/olm/operator/config.go` enforces this automatically. Do not bypass this wrapper when creating OLM-managed resources.

### CatalogSource Lifecycle

CatalogSource creation follows the `CatalogCreator`/`CatalogUpdater` interface pattern defined in `internal/olm/operator/registry/catalog.go`. Implementations must:

- Store metadata in CatalogSource annotations using the `operators.operatorframework.io` group prefix.
- Update CatalogSource via `retry.RetryOnConflict(retry.DefaultBackoff, ...)` to handle concurrent modifications.
- Clean up the previous registry pod after linking a new one, blocking on deletion to ensure OLM disconnects from the old pod.

### Install Flow Ordering

The `OperatorInstaller.InstallOperator` sequence must follow: CatalogSource creation, OperatorGroup check/creation, Subscription creation, InstallPlan wait, InstallPlan approval, CSV wait. Deviating from this order causes OLM reconciliation failures.

### Install Mode Validation

Use `InstallMode.CheckCompatibility()` from `internal/olm/operator/install_mode.go` before creating OperatorGroups. Key rule: `OwnNamespace` must be used (not `SingleNamespace`) when watching the operator's own namespace.

### OLM Resource Naming

Subscription names are derived via `getSubscriptionName()`, which DNS-sanitizes the CSV name and appends `-sub`. CatalogSource names use `CatalogNameForPackage()` appending `-catalog`. OperatorGroups always use the fixed name `operator-sdk-og`.

### File-Based Catalog (FBC) Detection

Before choosing a registry strategy, check `fbcutil.IsFBC()` against the index image. FBC images are identified by the `containertools.ConfigsLocationLabel` label. When FBC is detected, bundle add modes (`--bundle-add-mode`) are not supported and must be rejected.

## Webhook Integration

### CSV Webhook Collection

Webhooks are collected by the `collector.Manifests` struct, which flattens `ValidatingWebhookConfiguration` and `MutatingWebhookConfiguration` objects into individual webhook entries. The collector stores `[]admissionregv1.ValidatingWebhook` and `[]admissionregv1.MutatingWebhook`, not the parent configuration objects.

### Webhook-to-Deployment Matching

The `applyWebhooks` function matches webhooks to deployments through a two-step process:

1. Find the Service referenced by `webhook.ClientConfig.Service.Name`.
2. Match that Service's label selector against Deployment pod template labels.

If no matching deployment is found, it falls back to stripping the `-service` suffix from the service name. Ensure webhook services have selectors that match deployment pod template labels.

### Default Webhook Values

When `AdmissionReviewVersions` is empty, the CSV generator defaults to `["v1beta1"]`. When `SideEffects` is nil, it defaults to `SideEffectClassNone`. Do not rely on upstream defaults; these are applied during CSV generation.

### cert-manager Cleanup for Non-Go Projects

Helm and Ansible plugins strip cert-manager and webhook kustomize sections during scaffolding via `internal/plugins/util/cleanup.go`. The `UpdateKustomizationsInit()` function removes `[WEBHOOK]`, `[CERTMANAGER]`, and `[METRICS-WITH-CERTS]` blocks from `config/default/kustomization.yaml`.

## Helm Operator Integration

### watches.yaml Contract

Each entry in `watches.yaml` must have a unique GVK. Duplicate GVKs cause a load error. The `WatchDependentResources` field defaults to `true` when nil. Override values support environment variable expansion via `os.ExpandEnv` and Go `text/template` with sprig functions.

### Helm Reconciler Annotations

The Helm reconciler reads these annotations from custom resources at runtime:

- `helm.sdk.operatorframework.io/upgrade-force`: forces Helm upgrade with `--force`.
- `helm.sdk.operatorframework.io/rollback-force`: controls rollback force (defaults to `true` when absent).
- `helm.sdk.operatorframework.io/uninstall-wait`: blocks finalizer removal until all release resources are deleted.
- `helm.sdk.operatorframework.io/reconcile-period`: overrides the controller's reconcile period per-resource.

### Finalizer Convention

The active finalizer is `helm.sdk.operatorframework.io/uninstall-release`. A legacy finalizer `uninstall-helm-release` is also checked for backward compatibility. Both must be handled during deletion; new code should only add the namespaced finalizer.

### Helm Release Status Updates

Status updates use `retry.RetryOnConflict(retry.DefaultBackoff, ...)` and write to the `status` subresource. Condition types are: `Initialized`, `Deployed`, `ReleaseFailed`, `Irreconcilable`. Only update status when it actually changed (deep equality check against `originalStatus`).

### WatchedSecrets Optimization

The `WatchedSecrets` wrapper in `internal/helm/client/secrets_watch.go` uses a shared informer filtered by label `owner=helm` to reduce API server load during Helm storage queries. The informer refreshes every 30 seconds. Write operations (Create, Update, Delete) still go directly to the API server.

### Dependent Resource Watches

When `WatchDependentResources` is enabled, watches are dynamically added via a release hook. The hook uses owner references for namespaced-to-namespaced relationships and annotation-based tracking (`EnqueueRequestForAnnotation`) for cross-scope relationships. A `sync.RWMutex`-guarded map prevents duplicate watch registration.

### Cache Selector Configuration

The Helm operator configures cache selectors per-GVK from `watches.yaml` selectors and applies a default label selector to limit cache scope. Namespace filtering uses `WATCH_NAMESPACE` environment variable, split on commas.

## Prometheus Metrics

### Build Info Registration

Call `metrics.RegisterBuildInfo(crmetrics.Registry)` during operator startup. This registers a `helm_operator_build_info` gauge with `commit` and `version` const labels from `internal/version`. Use the controller-runtime metrics registry, not a custom one.

### Bundle Metrics Annotations

Use `metrics.MakeBundleMetadataLabels(layout)` for `bundle.Dockerfile` and `annotations.yaml`. Use `metrics.MakeBundleObjectAnnotations(layout)` for CRD and CSV objects. Both use the `operators.operatorframework.io` annotation prefix.

## Plugin System

### Plugin Naming

All SDK plugins use the suffix `.sdk.operatorframework.io` (the `DefaultNameQualifier` constant). Plugin keys are derived via `plugin.KeyFor()`.

### Plugin Interface Compliance

Plugins must satisfy the kubebuilder `plugin.Plugin` interface and optionally `plugin.Init` and `plugin.CreateAPI`. Use compile-time interface checks:

```go
var _ plugin.Plugin    = Plugin{}
var _ plugin.Init      = Plugin{}
var _ plugin.CreateAPI = Plugin{}
```

### Scaffolding Operator Type Detection

Use `projutil.PluginChainToOperatorType(config.GetPluginChain())` to determine whether the project is Go, Helm, or Ansible. Makefile fragments and kustomize scaffolding differ by operator type. Return an error if the operator type is `OperatorTypeUnknown`.

## External Service Communication

### Operator-Registry Integration

The `fbcutil.RenderRefs()` function creates a `containerdregistry` with TLS skip and HTTP options, renders bundle/index images into `DeclarativeConfig`, and cleans up the cache directory on return. Always pass `skipTLSVerify` and `useHTTP` through from user-facing flags; never hardcode these.

### Polling and Wait Patterns

All external waits use `wait.PollUntilContextCancel` with context-based cancellation. Standard poll intervals: 200ms for lightweight checks (pod existence, install plan), 1 second for heavier operations (deployment rollout, CSV status). Use `sync.Once` to log wait messages only on first occurrence.

### SecurityContext Configuration

Registry pods support `legacy` and `restricted` security context modes via the `SecurityContext` type. Default is `legacy`. The value is propagated to `CatalogSource.Spec.GrpcPodConfig.SecurityContextConfig`. Validate enum values in the `Set()` method of the flag type.
