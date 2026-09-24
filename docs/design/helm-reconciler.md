# Helm Reconciler Design Intent

## Overview

The Helm reconciler (`internal/helm/controller/`) bridges controller-runtime's reconciliation model with Helm's release lifecycle. One `HelmOperatorReconciler` is created per GVK entry in `watches.yaml`.

## Invariants

1. **One controller per GVK.** `Add()` registers exactly one controller-runtime controller per `WatchOptions.GVK`. Multiple watches for the same GVK are not supported and would conflict on the controller name.

2. **Watch deduplication is append-only.** The `watches` map (`map[schema.GroupVersionKind]struct{}`) in `watchDependentResources` only grows; watches are never removed. A TOCTOU race between the `RLock` check and the later `Lock` registration means concurrent reconciles for the same GVK can both call `c.Watch()` before either registers the entry. This can result in duplicate watch registrations (wasteful but not crash-inducing, since duplicate event deliveries are handled idempotently by the reconciler). Fixing this race is tracked separately.

3. **Status updates are conditional.** The reconciler snapshots `originalStatus` via `DeepCopy` at the top of `Reconcile` (line 108) and only issues a status sub-resource update when `!reflect.DeepEqual(status, originalStatus)` (line 424). New reconcilers must preserve this pattern to avoid unnecessary API writes.

4. **Finalizer lifecycle is two-phase.** The `uninstallFinalizer` is added during install/upgrade and removed only after a successful Helm uninstall. The legacy finalizer (`uninstall-helm-release`) is migrated transparently. Both finalizers must never coexist on the same resource.

5. **Override values are immutable per reconciler.** `OverrideValues` are set once during `Add()` from `watches.yaml` and are not modified during reconciliation. `SuppressOverrideValues` controls whether they appear in status output.

## Preconditions

- The manager's cache must be started and synced before `Reconcile` is called. `controller.New()` handles this via controller-runtime's lifecycle.
- `ManagerFactory` must be initialized with a valid Helm action configuration for the target namespace. This is set up by `watches.yaml` parsing in `cmd/helm-operator/`.
- `WatchDependentResources` requires a functioning REST mapper. If the API server is unreachable during dependent resource discovery, the release hook returns an error that is surfaced at the next reconciliation.

## Concurrency

- `MaxConcurrentReconciles` defaults to `runtime.NumCPU()` (set in `flags.go:176`). Multiple GVK watches multiply effective concurrency.
- The `sync.RWMutex` guarding the dependent-watch map uses `RLock` for the "already watched?" check and promotes to `Lock` only to register a new watch. The write lock is not held across the `c.Watch()` call itself.
- Known issue: a TOCTOU race exists between the `RLock` check and the `Lock` registration. This is benign because `c.Watch()` is idempotent, but a future fix should use `sync.Map` or a single `Lock` with early return.

## Annotations

| Annotation | Effect |
|---|---|
| `helm.sdk.operatorframework.io/upgrade-force` | Passes `--force` to Helm upgrade |
| `helm.sdk.operatorframework.io/rollback-force` | Passes `--force` to Helm rollback |
| `helm.sdk.operatorframework.io/uninstall-wait` | Waits for resource deletion during uninstall |
| `helm.sdk.operatorframework.io/reconcile-period` | Overrides the controller's default reconcile period |

## Rationale

- **Why Unstructured?** The reconciler operates on arbitrary CRDs. Using `unstructured.Unstructured` avoids compile-time type registration and supports any GVK defined in `watches.yaml`.
- **Why owner refs vs. annotations for dependent watches?** Owner references are preferred when supported (same namespace, compatible scope). Cross-namespace or cross-scope dependencies fall back to annotation-based watches via `EnqueueRequestForAnnotation`, determined by `k8sutil.SupportsOwnerReference` at runtime.
- **Why `retry.RetryOnConflict` for status updates?** Concurrent reconciliations for the same resource can race on status writes. The retry loop handles optimistic concurrency conflicts transparently.
