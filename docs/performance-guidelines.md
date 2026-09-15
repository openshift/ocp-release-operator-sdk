# Performance Guidelines

## Concurrency Defaults

- `--max-concurrent-reconciles` defaults to `runtime.NumCPU()`. On large nodes this can overload the API server. Set it explicitly based on workload, not host capacity. Defined in `internal/helm/flags/flag.go:66-69`.

- The Helm operator creates one `controller.Options{MaxConcurrentReconciles: N}` per GVK watch entry (`internal/helm/controller/controller.go:74-77`). Multiple watched GVKs multiply the effective concurrency. Account for all entries in `watches.yaml` when sizing.

## Mutex and Sync Primitives

- `sync.RWMutex` protects the dependent-resource watch map in `internal/helm/controller/controller.go:101`. The intended pattern: use `RLock` for the "already watched?" check, release it, then call `c.Watch(...)` without holding any lock, and finally acquire `Lock` only to register the new watch. Do not hold the write lock across the `c.Watch(...)` call. Note: the current implementation (`controller.go:126-162`) has a check-then-act race between the `RUnlock` and the later `Lock` -- concurrent reconciles for the same GVK can both pass the "not yet watched" check and both call `c.Watch(...)` before either registers the entry. This is believed benign today because `c.Watch` is idempotent, but new code should not assume this race is closed; fixing it is tracked separately from documentation changes.

- `sync.Mutex` in `actionConfigGetter` (`internal/helm/client/actionconfig.go:78`) guards per-namespace `WatchedSecrets` creation. The lock scope must stay narrow -- acquire, check-or-create, release, then return. Do not put network calls inside this lock.

- `sync.Once` is the standard pattern for lazy one-time initialization (discovery client caching in `restclientgetter.go:45`, OLM installer client in `installer/manager.go:42`). Prefer `sync.Once` over double-checked locking for any setup-once resource.

## Retry and Polling Conventions

### retry.RetryOnConflict

Always use `retry.DefaultBackoff` when wrapping `Client.Update` or `Client.Status().Update` calls. This is the established pattern across the codebase for handling Kubernetes conflict (409) errors:

```go
retry.RetryOnConflict(retry.DefaultBackoff, func() error {
    return r.Client.Update(ctx, o)
})
```

Do not use custom backoff parameters for conflict retries; `DefaultBackoff` is consistent across all six call sites (`reconcile.go:481,487`, `configmap.go:107`, `index_image.go:582`, `operator_installer.go:327`, `fbc_registry_pod.go:511`).

### wait.PollUntilContextCancel

Polling intervals follow this convention by resource type:

- **Pod readiness checks**: 200ms (`registry/index_image.go:656`, `fbcindex/fbc_registry_pod.go:197`, `index/registry_pod.go:192`)
- **Resource creation/deletion waits**: 100ms-1s depending on expected latency
- **Deployment rollout / CSV phase**: 1s (`olm/client/client.go:250,288`)
- **Cache deletion confirmation**: 10ms with a 5s hard timeout (`reconcile.go:496-498`)

Always pass `false` for the `immediate` parameter (third arg) to avoid running the condition check before the first interval elapses.

## Reconcile Period and Requeue

- The default reconcile period is 1 minute (`internal/helm/flags/flag.go:62-64`). Per-watch overrides are supported in `watches.yaml` via `reconcilePeriod` (`internal/helm/watches/watches.go:42`).

- The `helm.sdk.operatorframework.io/reconcile-period` annotation on a CR overrides both the flag and the watches.yaml value at runtime (`reconcile.go:434-446`). This is parsed via `time.ParseDuration` -- invalid values cause an error return, not a fallback.

- Every successful reconcile returns `reconcile.Result{RequeueAfter: finalReconcilePeriod}` (`reconcile.go:111,121`). Only error paths return an empty `Result{}` (which triggers immediate exponential-backoff requeue). Do not return `Requeue: true` from the Helm reconciler -- always use `RequeueAfter` with the computed period.

## Cache and Informer Configuration

- Namespace-scoped caches use `cache.Config` via `options.Cache.DefaultNamespaces`. When watching specific namespaces, each gets its own `cache.Config{}` entry. When watching all namespaces, a single `metav1.NamespaceAll` entry with `LabelSelector: labels.Everything()` overrides any per-object selectors that would otherwise restrict the cluster-wide watch. This is set in `internal/cmd/helm-operator/run/cmd.go:224-248`.

- Per-GVK label selectors are applied through `cache.ByObject` and a global `DefaultLabelSelector` scoped to `helm.sdk.operatorframework.io/chart` (`run/cmd.go:263-291`). The selector is built from chart names loaded from `watches.yaml`, using a `selection.In` requirement. This ensures the shared informer cache only stores objects relevant to the watched charts. Preserve this filtering -- removing it causes the cache to store all cluster objects of those types.

- The Helm secrets informer (`secrets_watch.go:151`) uses a 30-second resync period and namespace-scoped factories (`informers.WithNamespace`). Each namespace gets its own `SharedInformerFactory` and the factory is started with `wait.NeverStop`. New namespaces lazily create new factories via `actionConfigGetter.getWatchedSecretsForNamespace`.

## Watch Efficiency

- The `WatchedSecrets` wrapper (`internal/helm/client/secrets_watch.go`) exists specifically to reduce API server load. Helm queries release secrets multiple times per reconciliation. The wrapper intercepts `List` calls matching `owner=helm` and serves them from the informer lister instead of hitting the API server. If a List call includes options beyond a label selector (checked via `hasListOptionsOtherThanLabelSelector` at line 107), it falls through to the direct API call with a log warning. Do not bypass this wrapper.

- Dependent resource watches are deduplicated via a `map[schema.GroupVersionKind]struct{}` guarded by `sync.RWMutex` (`controller.go:101-102`). Under normal operation a watch is registered once per GVK, but the TOCTOU race described above means concurrent reconciles can register duplicate watches for the same GVK before either records the entry. This is wasteful (duplicate event deliveries) but not harmful, since the reconciler handles duplicates idempotently.

- Use `predicate.DependentPredicate{}` on all dependent resource watches to filter out events that do not represent meaningful changes (`controller.go:145,155`).

- The primary CR watch uses `InstrumentedEnqueueRequestForObject` (`controller.go:85`) for metrics-aware event enqueuing. Dependent watches use either `EnqueueRequestForOwner` (when owner references are supported) or `EnqueueRequestForAnnotation` (cross-namespace or cross-scope). This distinction is determined by `k8sutil.SupportsOwnerReference` at line 134.

## Goroutine Patterns

- Scorecard parallel test execution uses `sync.WaitGroup` + buffered channel (`internal/scorecard/scorecard.go:127-137`). The channel is pre-allocated to `len(tests)` capacity. Follow this pattern for buffered result collection: pre-size the channel, launch goroutines, `wg.Wait()`, then close and drain. Note that this pattern does not limit concurrency -- all goroutines run simultaneously. Add a semaphore or worker pool if an actual concurrency cap is needed.

- Background streaming (e.g., `storage.go:68`) launches a goroutine that owns `io.Pipe` writers. Always `defer` closing both `outStream` and `errStream` inside the goroutine to prevent reader hangs.

- Note: there is no upper bound on parallel scorecard tests -- all tests in a parallel stage run concurrently. For stages with many tests, this can create excessive pod pressure. The concurrency is bounded only by the number of tests in the stage configuration.

## Context and Timeout Conventions

- Long-running operations without a caller context (OLM install/uninstall, scorecard) use `context.WithTimeout(context.Background(), timeout)` where timeout defaults to 2 minutes (`installer/manager.go:76,95,123`). `operator-sdk run bundle` instead derives its timeout from `cmd.Context()` (`run/bundle/cmd.go:48`), since a caller context is available. Always call `defer cancel()` immediately after creating the context.

- Cleanup operations after a primary context expires must use a fresh context: `context.WithTimeout(context.Background(), cleanupTimeout)` with a 30-second ceiling (`scorecard.go:70,108`). Do not reuse the expired parent context for cleanup.

- The `waitForDeletion` helper wraps a tight 10ms poll in a 5-second hard timeout (`reconcile.go:496-498`). This pattern is appropriate only for cache-backed reads where staleness is the concern, not for waiting on actual API operations.

- Avoid `context.TODO()` in production code paths. Several existing uses in `fbc_registry_pod.go:513-523` and `storage.go:71` are technical debt -- new code should always propagate an explicit context from the caller.

## Status Update Optimization

- The Helm reconciler compares `status` to `originalStatus` using `reflect.DeepEqual` before issuing a status update (`reconcile.go:424`). This avoids unnecessary writes when the status has not changed. Apply this pattern in any new reconciler: snapshot the status at the top of `Reconcile` via `DeepCopy` (line 108), compare at the end.

## Leader Election

- The resource lock type defaults to `resourcelock.LeasesResourceLock` (`flags.go:176`). Do not change to ConfigMap-based locks as Leases have lower API server overhead and better consistency semantics.

## Logging Performance

- Use `log.V(1).Info(...)` for per-reconcile diagnostics, not `log.Info(...)`. The `V(1)` guard suppresses log emission when debug logging is disabled, but Go still evaluates all call arguments. The diff output in `reconcile.go:151,276,353` is additionally guarded by an explicit `log.V(1).Enabled()` check to avoid computing the diff string at all -- use this `.Enabled()` pattern whenever arguments are expensive to construct.

- Helm debug logs use a closure (`debugLog` in `actionconfig.go:47-49`) that checks `log.Enabled()` before formatting. Follow this pattern when passing log functions to third-party libraries.

- The `WatchedSecrets` constructor uses `log.V(2)` (line 131) for per-namespace factory creation logs. Use verbosity level 2 or higher for setup-time diagnostics that fire once per namespace, not per request.

## OLM Wait Patterns

- `sync.Once` is used inside `PollUntilContextCancel` callbacks to emit progress logs exactly once per phase transition (`olm/client/client.go:196-200`). This prevents log spam during extended waits (deployment rollout, CSV phase). Use this pattern in any new polling loop that could run for minutes.

- Delete operations use `DeletePropagationBackground` (`olm/client/client.go:165`) followed by a 100ms poll to confirm actual deletion. This is faster than `Foreground` propagation for bulk teardown and avoids blocking on dependent object deletion.
