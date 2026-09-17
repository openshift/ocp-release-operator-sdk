# CLAUDE.md

@AGENTS.md

## Claude Code Quick Reference

### Pre-commit Workflow

Before committing changes, always run:
```bash
make test-sanity
```

This runs formatters, linters, license checks, error format validation, and ensures no uncommitted generated files. CI will fail if this check doesn't pass.

### Common Commands

**Setup & Verification:**
```bash
make setup              # One-time bootstrap for a clean checkout
make verify             # Full pre-PR check (build + test-static)
make verify-file FILE=internal/olm/client/client.go  # Single-file check
```

**Build:**
```bash
make build                 # Build both operator-sdk and helm-operator
make build/operator-sdk    # Build operator-sdk only
make build/helm-operator   # Build helm-operator only
```

**Test:**
```bash
make test-sanity    # Format, lint, license, error format checks (REQUIRED before commit)
make test-unit      # Unit tests with race detection
make test-static    # All non-cluster tests (sanity + unit + docs)
make test-e2e       # E2E tests (requires KIND cluster)
make test-docs      # Validate changelog and check doc links
```

**Fix/Lint:**
```bash
make fix     # Auto-fix: go mod tidy, go fmt, golangci-lint --fix
make lint    # Run golangci-lint (read-only)
```

**Generate:**
```bash
make generate    # Regenerate CLI docs, samples, testdata
make bindata     # Update embedded OLM data
```

### Build Tag Requirement

ALL Go commands require the build tag `containers_image_openpgp`. The Makefile handles this automatically via `GO_BUILD_TAGS`. If running `go` commands directly:
```bash
go build -tags containers_image_openpgp ./...
go test -tags containers_image_openpgp ./...
go vet -tags containers_image_openpgp ./...
```

### Claude Code Behavior

- **Never edit generated files**: Files with `zz_generated` prefix, `DO NOT EDIT` headers, files in `testdata/`, `internal/bindata/`, or `*fakes/` directories are auto-generated. Edit the generator/template instead.
- **Run test-sanity before commits**: CI enforces `make test-sanity` including `git diff --exit-code`. Any uncommitted changes after generators/formatters will fail the build.
- **Vendor directory**: After modifying `go.mod`, run `go mod tidy` then `go mod vendor`, and commit the vendor update as a separate commit with prefix `UPSTREAM: <drop>: Update vendor directory`.
- **Downstream commit prefixes**: Use `UPSTREAM: <carry>:` for persistent downstream changes or `UPSTREAM: <drop>:` for temporary/auto-generated commits. See AGENTS.md for details.
- **Changelog fragments**: Add a YAML file to `changelog/fragments/` for user-facing changes.

### CI Configuration

- **Upstream CI**: GitHub Actions (`.github/workflows/`), primary gate: `quality-gate.yml`
- **Downstream CI**: OpenShift Prow (`ci/prow.Makefile`, `ci/tests/`)
- **Patches**: Downstream patches in `patches/` applied via `make -f ci/prow.Makefile patch`
- **Security**: `govulncheck` runs via `make test-sanity`; downstream Prow handles additional scanning

### Single-File Verification

Fast feedback without a full build or e2e suite:

```bash
# Lint (package-scoped; replace path with target package)
golangci-lint run --build-tags containers_image_openpgp ./internal/olm/client/

# Type-check / static analysis
go vet -tags containers_image_openpgp ./internal/olm/client/

# Convenience wrapper (runs both + package tests)
make verify-file FILE=internal/olm/client/client.go

# Shell scripts
shellcheck hack/verify-file.sh
bash -n hack/verify-file.sh
```

### Detailed Documentation

For design intent (preconditions, invariants, rationale), see `docs/design/`:
- `helm-reconciler.md` -- Reconcile loop, watch dedup, status updates, concurrency
- `olm-lifecycle.md` -- Install/uninstall, timeout contexts, polling patterns
- `plugin-system.md` -- Plugin naming, scaffolding contracts, extension points
