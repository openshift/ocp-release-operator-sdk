---
paths:
  - ".github/workflows/**"
  - "ci/**"
  - "Makefile"
---
# CI Rules

## Two CI Systems

- **GitHub Actions** (`.github/workflows/`): upstream-style checks. The primary required gate is `quality-gate.yml` which runs `make setup`, pre-commit, `make build`, `make lint`, `go vet`, and `make test-static`.
- **OpenShift Prow** (`ci/prow.Makefile`): downstream CI. Always applies `patches/` before running builds or tests.

## Quality Gate

The single required PR check is the `quality-gate` job. It runs, in order:

```bash
make setup                                    # bootstrap tools
python3 -m pip install --user pre-commit && make precommit  # formatting/lint/secret hooks
make build                                    # compile binaries
make lint                                     # golangci-lint
go vet -tags containers_image_openpgp ./...   # type check
make test-static                              # test-sanity + test-unit + test-docs
```

## Security Scanning

Security scanning (govulncheck, OSV, Trivy) is handled by OpenShift Prow CI downstream. Exceptions must be documented in `docs/security-exceptions.md`.

## Prow Patches

Downstream Prow CI applies patches from `patches/` before any build step. If you modify a Makefile target that Prow uses, check whether a patch modifies that same target. See [docs/patterns/downstream-patches.md](../../docs/patterns/downstream-patches.md).
