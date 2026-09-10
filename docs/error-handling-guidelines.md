# Error Handling Guidelines

## Error Wrapping

**Use `%w` for errors callers may need to inspect; use `%v` for opaque errors.**
The codebase uses both `fmt.Errorf` with `%w` (wrapping) and `%v` (non-wrapping). Prefer `%w` in new code so callers can use `errors.Is`/`errors.As`. Never import `github.com/pkg/errors` -- use only stdlib `fmt.Errorf` and `errors`.

**Prefer including a colon separator before the verb.**

```go
// correct
return fmt.Errorf("failed to load chart: %w", err)

// less clear -- missing separator
return fmt.Errorf("could not find config file %w", err)
```

Some existing code omits the colon; new code should include it for consistency.

**Use lowercase, verb-first error messages.** The repo uses two prefixes interchangeably: `"failed to <verb>"` and `"error <verb>ing"`. Pick one per package and stay consistent.

## Custom Error Types and Sentinels

**Create custom error types only when callers must extract structured data.** The repo defines very few (~6) custom types, each carrying fields callers inspect:

- `ErrPackageNotFound` (carries `PackageName`) -- checked via `errors.As`
- `deploymentErrors` / `podErrors` -- aggregate multiple sub-errors for status reporting

**Use exported sentinel variables for errors checked with `errors.Is`.**

```go
var ErrUpgradeFailed = errors.New("upgrade failed")   // in internal/helm/release/manager.go
var ErrOLMNotInstalled = errors.New("no existing installation found") // in internal/olm/client/client.go
```

Do not create sentinels for errors that are only ever returned, never matched.

## Kubernetes API Errors

**Use `apierrors.Is*` functions, not `errors.Is`, for Kubernetes status errors.**

```go
import apierrors "k8s.io/apimachinery/pkg/api/errors"
```

**Idempotent operations follow fixed patterns -- do not deviate:**

| Operation | Error Check | Action |
|-----------|------------|--------|
| Get + NotFound in Reconcile | `apierrors.IsNotFound(err)` | `return reconcile.Result{}, nil` (stop) |
| Delete + NotFound | `apierrors.IsNotFound(err)` | Ignore, treat as success |
| Create + AlreadyExists | `apierrors.IsAlreadyExists(err)` | Ignore, treat as success |
| Get + NotFound in polling | `apierrors.IsNotFound(err)` | `return false, nil` (keep polling) |

**Combine `IsNotFound` with `meta.IsNoMatchError` to detect missing CRDs/OLM:**

```go
if apierrors.IsNotFound(err) || meta.IsNoMatchError(err) {
    return ErrOLMNotInstalled
}
```

## Reconciler Error Conventions

**Return `reconcile.Result{}, err` to trigger requeue with backoff.** Never set `Requeue: true` on the Result when also returning an error -- the error alone triggers the requeue.

**Use `RequeueAfter` only for successful periodic reconciliation:**

```go
return reconcile.Result{RequeueAfter: r.ReconcilePeriod}, nil
```

**Set status conditions before returning errors.** Map errors to typed conditions (`ConditionReleaseFailed`, `ConditionIrreconcilable`) with `err.Error()` as the message. Remove failure conditions on success.

**When a status update fails after a primary error, log the status error but return the primary error:**

```go
if err := r.updateResourceStatus(ctx, o, status); err != nil {
    log.Error(err, "Failed to update status after release failure")
}
return reconcile.Result{}, primaryErr
```

## Logging Errors

**Two logging libraries, scoped by binary:**

- **`operator-sdk` CLI** (`cmd/operator-sdk/`, `internal/cmd/operator-sdk/`): `logrus` (imported as `log`)
- **`helm-operator`** (`cmd/helm-operator/`, `internal/cmd/helm-operator/`, `internal/helm/`): `logr` via `controller-runtime/pkg/log`. The `helm-operator` `main.go` entrypoint uses the stdlib `log` package only for a terminal `log.Fatal` on startup failure -- it does not use `logrus`.

**The log-and-return pattern is accepted in reconcilers.** Although this causes duplicate logging (controller-runtime also logs returned errors), the codebase treats this as intentional for observability:

```go
log.Error(err, "Failed to install release")
return reconcile.Result{}, err
```

**In CLI code, do not both log and return.** Return the error from `RunE` and let cobra handle printing. Exception: `log.Fatal` is acceptable in `Run` (not `RunE`) functions as the terminal error handler.

**Obtain loggers by layer:**

- Controllers: package-level `var log = logf.Log.WithName("helm.controller")`, enriched per-reconcile with `.WithValues()`
- CLI: direct `logrus` import, flat calls

## CLI Command Errors

**Prefer `RunE` over `Run` for all commands.** Return errors instead of calling `log.Fatal` inside `RunE`. Several existing commands violate this (scorecard, bundle generate, olm install) -- do not follow that pattern.

**Use `errors.New` for static validation failures in `PreRunE`:**

```go
return errors.New("--version must be set")
```

**Downgrade known-benign errors to warnings using `errors.As`:**

```go
var notFound *operator.ErrPackageNotFound
if errors.As(err, &notFound) {
    log.Warnf("Package %s not found, skipping", notFound.PackageName)
    return nil
}
```

## Validation Error Handling

**Always aggregate validation errors; never return on first failure.** The repo uses a two-layer system:

1. **Upstream layer** (`github.com/operator-framework/api/pkg/validation/errors.ManifestResult`): validators return `[]ManifestResult`, each containing separate `Errors` and `Warnings` slices.
2. **SDK layer** (`internal/validate.Result`): flattens upstream results into a unified pass/fail with typed `Output` entries (info/warn/error).

**Use `Result.AddError` for errors that may wrap multiple failures.** It detects `registrybundle.ValidationError` via `errors.As` and unpacks nested errors automatically.

**Merge same-named results with `appendResult`.** When multiple validators produce results for the same manifest, append errors to the existing `ManifestResult` rather than creating duplicates.

**Support both text and JSON output.** Validation results must be printable via `Result.PrintWithFormat(format)` -- text mode uses logrus, JSON mode uses `json-alpha1` schema.

## Summary of `errors.Is` / `errors.As` Usage

| Function | Used For |
|----------|---------|
| `errors.Is(err, ErrUpgradeFailed)` | Triggering Helm rollback |
| `errors.Is(err, driver.ErrReleaseNotFound)` | Detecting first install |
| `errors.Is(err, os.ErrNotExist)` | File existence checks |
| `errors.Is(err, context.DeadlineExceeded)` | Timeout handling |
| `errors.As(err, &ErrPackageNotFound{})` | Extracting package name for warnings |
| `errors.As(err, &ValidationError{})` | Unpacking nested validation errors |
| `apierrors.IsNotFound(err)` | K8s resource not found (use this, not errors.Is) |
