# OLM Lifecycle Design Intent

## Overview

The OLM subsystem (`internal/olm/`) manages the lifecycle of Operator Lifecycle Manager itself: install, uninstall, status check, and operator run (bundle/packagemanifests). It is consumed exclusively by the `operator-sdk` CLI, not by the `helm-operator` runtime.

## Invariants

1. **Timeout contexts are always bounded.** Every OLM operation wraps its work in `context.WithTimeout(context.Background(), timeout)` with a default of 2 minutes (`installer/manager.go:76,95,123`). `defer cancel()` must be called immediately after context creation. `run bundle` is the exception: it derives its context from `cmd.Context()` because it operates within a CLI command that already has a signal-aware context.

2. **Cleanup uses a fresh context.** When a primary operation context expires, cleanup (uninstall, resource deletion) must create a new context rather than reusing the expired parent. The scorecard enforces a 30-second ceiling for cleanup contexts (`scorecard.go:70,108`).

3. **Version validation is pre-install.** `Manager.initialize()` validates the OLM version, namespace defaults, and client configuration via `sync.Once`. Errors during initialization are fatal and prevent Install/Uninstall/Status from proceeding.

4. **Version mismatch is an error.** If a `--version` flag is supplied and differs from the installed version, Uninstall and Status return an error rather than silently operating on the wrong version.

5. **`ErrOLMNotInstalled` is a sentinel.** Code that checks for OLM presence must compare against `client.ErrOLMNotInstalled` using `errors.Is()`, not string matching.

## Preconditions

- A valid kubeconfig with cluster-admin-equivalent permissions is required. OLM install creates cluster-scoped resources (CRDs, ClusterRoles, Deployments in the OLM namespace).
- The OLM namespace (default: `olm`) must either not exist (for install) or exist with a valid OLM deployment (for uninstall/status).
- `run bundle` requires a running OLM instance on the target cluster. It creates an ephemeral `CatalogSource` and `Subscription` to install the operator under test.

## Polling patterns

- `PollUntilContextCancel` is used for waiting on deployment rollouts and CSV phase transitions. Each polling callback uses `sync.Once` to emit progress logs exactly once per phase change, preventing log spam during multi-minute waits.
- `waitForDeletion` uses a tight 10ms poll with a 5-second hard timeout. This is appropriate only for cache-backed reads where the concern is informer staleness, not actual API latency.

## Rationale

- **Why `context.Background()` instead of propagating a parent?** The OLM installer is invoked from CLI commands where the only context is the process lifetime. `cmd.Context()` carries signal handling; `context.Background()` is used when the operation needs its own independent timeout.
- **Why `sync.Once` in polling callbacks?** Long-running waits (deployment rollout, CSV pending) can poll hundreds of times. Without `sync.Once`, each poll iteration would log, creating thousands of identical log lines.
- **Why `logrus` instead of `logr`?** The OLM subsystem runs inside the `operator-sdk` CLI binary, which uses logrus throughout. The `helm-operator` binary uses logr. Mixing frameworks within a single binary is prohibited.
