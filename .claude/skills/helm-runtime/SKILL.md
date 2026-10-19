# Skill: Helm Reconciler Changes

## When to use

Modifying Helm operator runtime behavior — controller, release management, watches.

## Reference implementation

See `internal/helm/controller/reconcile.go` for the reconciliation loop.

## Key packages

- `internal/helm/controller/` — reconciler
- `internal/helm/release/` — Helm release install/upgrade/uninstall
- `internal/helm/watches/` — `watches.yaml` parsing
- `internal/helm/client/` — action client factory

## Steps

1. Modify the relevant package under `internal/helm/`.
2. Use `logr` (controller-runtime log), not `logrus`.
3. Run targeted checks, then full verification.

## Verification

```bash
make verify-file FILE=internal/helm/controller/reconcile.go
golangci-lint run --build-tags containers_image_openpgp ./internal/helm/controller/
go vet -tags containers_image_openpgp ./internal/helm/controller/
make verify
```

## Constraints

- `helm-operator` uses raw Cobra, not kubebuilder `cli.New()`.
- Full guide: [docs/patterns/cli-changes.md](../../../docs/patterns/cli-changes.md)
