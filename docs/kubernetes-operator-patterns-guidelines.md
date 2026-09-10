# Kubernetes Operator Patterns Guidelines

## Reconciliation Loop

Always fetch the primary resource at the start of `Reconcile`. Return `nil` error on `IsNotFound` to stop reconciliation for deleted resources. Return the raw error for all other `Get` failures to trigger a requeue.

Re-fetch the CR after every status update (`r.Status().Update`) before making further mutations. This prevents "the object has been modified" conflicts due to stale `resourceVersion`.

Use `ctrl.Result{RequeueAfter: time.Minute}` after creating a child resource. Use `ctrl.Result{Requeue: true}` after updating a child resource. Return `ctrl.Result{}, nil` when the desired state is fully reached.

Reconcilers must embed `client.Client` and accept `*runtime.Scheme` and `record.EventRecorder`. Instantiate in `main.go` with `mgr.GetClient()`, `mgr.GetScheme()`, and `mgr.GetEventRecorderFor("<name>-controller")`.

The Helm operator reconciler adds a `ReconcilePeriod` field and supports per-CR override via the `helm.sdk.operatorframework.io/reconcile-period` annotation. Go operators should define explicit requeue durations rather than relying on periodic resyncs.

Wrap resource updates and status updates in `retry.RetryOnConflict(retry.DefaultBackoff, ...)` for Helm-based operators. Go-based operators rely on controller-runtime's built-in requeue-on-error.

## Custom Resource Definitions

Place API types in `api/<version>/` with one `<kind>_types.go` per Kind and a `groupversion_info.go` that registers the `SchemeBuilder` and `AddToScheme`.

Mark spec fields with `+operator-sdk:csv:customresourcedefinitions:type=spec` and status fields with `type=status`. Mark the root type with `+operator-sdk:csv:customresourcedefinitions:resources={{Kind,version,name}}` to declare owned sub-resources for CSV generation.

Use `+kubebuilder:validation:Minimum`, `+kubebuilder:validation:Maximum` markers on numeric spec fields. Always add `+kubebuilder:subresource:status` to the root type so status is a distinct sub-resource.

Status uses `[]metav1.Condition` with `patchStrategy:"merge"` and `patchMergeKey:"type"`. Condition types are string constants defined at the controller level (e.g., `typeAvailableMemcached = "Available"`, `typeDegradedMemcached = "Degraded"`).

Register all API types in `init()` of the types file via `SchemeBuilder.Register(&Kind{}, &KindList{})`. In `main.go`, call `utilruntime.Must(api.AddToScheme(scheme))` before manager creation.

## Status Conditions

Initialize status on first reconcile: when `len(cr.Status.Conditions) == 0`, set the primary condition to `ConditionUnknown` with reason `"Reconciling"`, then update and re-fetch.

Use `meta.SetStatusCondition(&cr.Status.Conditions, metav1.Condition{...})` for Go operators. The Helm operator uses its own `HelmAppStatus.SetCondition`/`RemoveCondition` methods with custom types (`ConditionInitialized`, `ConditionDeployed`, `ConditionReleaseFailed`, `ConditionIrreconcilable`).

Always call `r.Status().Update()` (the status sub-resource client), never `r.Update()`, for status changes. Conversely, never use `r.Status().Update()` for spec/metadata changes.

## Finalizers

Finalizer names follow the pattern `<group>/finalizer` for Go operators (e.g., `cache.example.com/finalizer`). Helm operators use `helm.sdk.operatorframework.io/uninstall-release`.

Add finalizer early in reconciliation, before any deletion check. Use `controllerutil.AddFinalizer` then `r.Update(ctx, cr)`. Check the return value of `AddFinalizer`/`RemoveFinalizer` -- they return `false` if the operation was a no-op.

Deletion flow: check `GetDeletionTimestamp() != nil`, execute cleanup, update status to `Degraded`/`Finalizing`, re-fetch the CR, then `controllerutil.RemoveFinalizer` followed by `r.Update`. Do not use finalizers for resources that have owner references -- those are garbage-collected automatically.

The Helm operator supports a legacy finalizer (`uninstall-helm-release`) alongside the current one. When checking for finalizer presence, check both.

## Owner References and Watches

Set owner references via `ctrl.SetControllerReference(owner, owned, r.Scheme)` when creating child resources. This enables automatic garbage collection and triggers reconciliation through `Owns()` watches.

Owner references only work when owner and dependent are in the same namespace (or owner is cluster-scoped). Use `k8sutil.SupportsOwnerReference(restMapper, owner, dependent, "")` to check at runtime. When owner refs are unsupported, fall back to annotation-based watches via `libhandler.EnqueueRequestForAnnotation`.

In `SetupWithManager`, use `For(&PrimaryKind{})` for the CR and `Owns(&ChildKind{})` for owned resources. The Helm operator uses lower-level `c.Watch(source.Kind(...))` with `EnqueueRequestForOwner` and `DependentPredicate{}` to filter events.

## Manager and Controller Setup

Manager configuration pattern in `cmd/main.go`:

```go
mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
    Scheme:                 scheme,
    LeaderElection:         enableLeaderElection,
    LeaderElectionID:       "<unique-hash>.<domain>",
    HealthProbeBindAddress: probeAddr,
})
```

Always register health and readiness probes: `mgr.AddHealthzCheck("healthz", healthz.Ping)` and `mgr.AddReadyzCheck("readyz", healthz.Ping)`. The manager Deployment must configure `livenessProbe` and `readinessProbe` on port 8081 at `/healthz` and `/readyz`.

Disable HTTP/2 by default to prevent CVE-2023-44487 (Rapid Reset) and CVE-2023-39325 (Stream Cancellation). Set `NextProtos: []string{"http/1.1"}` on both webhook and metrics server TLS configs unless `--enable-http2` is explicitly passed.

The Helm operator loads watches from `watches.yaml` (configurable via `--watches-file`). Each entry maps a GVK to a Helm chart directory. Duplicate GVKs are rejected. `WatchDependentResources` defaults to `true`.

## Leader Election

Leader election uses Lease-based locks (`resourcelock.LeasesResourceLock`). The `LeaderElectionID` must be unique per operator (Go operators use `<hash>.<domain>`, Helm operators use `--leader-election-id` or the deprecated `OPERATOR_NAME` env var).

`LeaderElectionReleaseOnCancel` is commented out by default in scaffolded code. Only enable it if the binary exits immediately after manager stop -- otherwise a new leader may start before cleanup completes.

## Namespace Scoping

Namespace scoping is controlled by `WATCH_NAMESPACE` env var (defined in `k8sutil.WatchNamespaceEnvVar`). Empty value means cluster-wide. Multiple namespaces are comma-separated. The Helm operator translates these into `cache.DefaultNamespaces` configs.

## Helm Operator Specifics

The Helm reconciler manages lifecycle through Install/Upgrade/Reconcile/Uninstall. It compares deployed release manifests against candidate releases to determine if upgrade is needed. Override values from `watches.yaml` are applied and logged as `OverrideValuesInUse` warning events.

Annotations control Helm behavior per CR: `helm.sdk.operatorframework.io/upgrade-force` (force upgrade), `helm.sdk.operatorframework.io/rollback-force` (force rollback, defaults to true), `helm.sdk.operatorframework.io/uninstall-wait` (wait for resource deletion).

Failed upgrades trigger automatic rollback. The reconciler distinguishes between `ErrUpgradeFailed` (rollback needed) and other errors. Rollback force defaults to `true` when the annotation is absent.

MaxConcurrentReconciles defaults to `runtime.NumCPU()` for Helm operators. Configure via `--max-concurrent-reconciles`.

## RBAC Markers

Declare RBAC requirements via `+kubebuilder:rbac` markers on the `Reconcile` method. Always include separate entries for the CR's main resource, `/status` sub-resource, and `/finalizers` sub-resource. Add entries for `events` (create;patch) and every child resource type.

## Webhooks

Separate webhook logic from controller logic. Place webhooks in `internal/webhook/<version>/` with a standalone `Setup<Kind>WebhookWithManager` function. Gate webhook registration behind `ENABLE_WEBHOOKS != "false"` in `main.go` for local development.

## Testing

Controller tests use envtest with Ginkgo/Gomega. `suite_test.go` bootstraps `envtest.Environment` with CRD paths pointing to `config/crd/bases/`. Tests instantiate the reconciler directly and call `Reconcile` with explicit `reconcile.Request`, then verify outcomes via `Eventually` with `k8sClient.Get`.

Set `SetDefaultEventuallyTimeout(2 * time.Minute)` and `SetDefaultEventuallyPollingInterval(time.Second)` for controller test suites to handle async reconciliation.

## Operand Image Management

Pass operand images via environment variables (e.g., `MEMCACHED_IMAGE`) defined in `config/manager/manager.yaml`, not hardcoded in Go source. The controller reads them with `os.LookupEnv` and fails with a descriptive error if unset.

## Labels

Apply Kubernetes recommended labels to all managed resources: `app.kubernetes.io/name`, `app.kubernetes.io/version`, `app.kubernetes.io/managed-by`. The managed-by value should be the controller name.
