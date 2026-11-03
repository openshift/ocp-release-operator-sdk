# Testing Guide

## Test Suites

| Suite | Command | Description |
|-------|---------|-------------|
| **All static** | `make test-static` | Sanity + unit + docs (no cluster) |
| **Unit tests** | `make test-unit` | Go unit tests with race detector (`-race`) |
| **Sanity** | `make test-sanity` | Generate, fix, lint, vet, license check |
| **Doc tests** | `make test-docs` | Changelog validation, link checking |
| **E2E (all)** | `make test-e2e` | Go + Helm e2e (requires KinD cluster) |
| **E2E Go** | `make test-e2e-go` | Go operator e2e tests |
| **E2E Helm** | `make test-e2e-helm` | Helm operator e2e tests |
| **Integration** | `make test-e2e-integration` | Packagemanifests + OLM integration |
| **All** | `make test-all` | Static + e2e |

## Test Directory Structure

```
test/
├── e2e/
│   ├── go/                    # Go operator e2e tests (Ginkgo v2)
│   │   ├── cluster_test.go    # Cluster-based tests (deploy, scorecard)
│   │   ├── local_test.go      # Local project scaffolding tests
│   │   ├── scorecard_test.go  # Scorecard e2e tests
│   │   └── suite_test.go      # Ginkgo suite setup
│   └── helm/                  # Helm operator e2e tests (Ginkgo v2)
│       ├── cluster_test.go    # Cluster-based Helm operator tests
│       ├── local_test.go      # Local Helm scaffolding tests
│       ├── olm_test.go        # OLM integration tests
│       ├── scorecard_test.go  # Scorecard e2e tests
│       └── suite_test.go      # Ginkgo suite setup
├── integration/               # Integration tests
│   ├── packagemanifests_test.go
│   └── suite_test.go
└── common/                    # Shared test helpers
    ├── sa_secret.go           # Service account secret helpers
    └── scorecard.go           # Scorecard test helpers
```

## Test Framework

- **Unit tests**: Standard `go test` with `-race` flag, coverage via `-coverprofile`
- **E2E tests**: [Ginkgo v2](https://onsi.github.io/ginkgo/) + [Gomega](https://onsi.github.io/gomega/) matchers
- **Test utilities**: `internal/testutils/` — shared helpers for project scaffolding and command execution
- **Common helpers**: `test/common/` — service account secrets, scorecard utilities

## Running Tests Locally

### Unit Tests (no cluster required)

```bash
make test-unit
# Equivalent to:
# CGO_ENABLED=1 go test -race -tags=containers_image_openpgp -coverprofile=coverage.out -covermode=atomic -short $(go list ./... | grep -v test/)
```

Unit tests exclude the `test/` directory and run with `-short` flag.

### Sanity Checks

```bash
make test-sanity
```

This runs in sequence:
1. `make generate` — regenerates CLI docs, samples, testdata
2. `make fix` — `go mod tidy`, `go fmt`, `golangci-lint --fix`
3. `git diff --exit-code` — fails if generate/fix produced changes
4. `./hack/check-license.sh` — license header check
5. `./hack/check-error-log-msg-format.sh` — error message format check
6. `go vet -tags=containers_image_openpgp ./...`
7. `make lint` — golangci-lint
8. `git diff --exit-code` — fails if any check produced changes

### E2E Tests (cluster required)

```bash
# Setup: creates KinD cluster, installs tools
make test-e2e-setup

# Run specific suite
make test-e2e-go
make test-e2e-helm
make test-e2e-integration

# Teardown
make test-e2e-teardown
```

E2E tests use a KinD cluster (`osdk-test`) with Kubernetes `v1.33.1`. The setup installs `kind` and `kubectl` via `tools/scripts/fetch`.

### CI-Specific Tests

CI uses `ci/prow.Makefile` targets:

```bash
make -f ci/prow.Makefile test-e2e-go ARGS="..."   # Patches first, then runs e2e
make -f ci/prow.Makefile test-e2e-helm              # Patches first, then runs Helm e2e
make -f ci/prow.Makefile test-subcommand            # Tests SDK subcommands
```

## Test Patterns

### Ginkgo E2E Pattern

E2E tests scaffold a project using `internal/testutils.TestContext`, run SDK commands, deploy to the KinD cluster, and verify behavior:

```go
// test/e2e/go/cluster_test.go pattern
tc, err := testutils.NewTestContext("operator-sdk", "GO111MODULE=on")
Expect(err).NotTo(HaveOccurred())
// ... scaffold, build, deploy, verify
```

### Unit Test Pattern

Unit tests are colocated with source files (e.g., `internal/scorecard/scorecard_test.go`). They use standard `go test` conventions with `testing.T`.

## Coverage

```bash
make test-unit
# Generates coverage.out
go tool cover -html=coverage.out  # View coverage report
```

## Platform Conventions

For generic OpenShift testing practices and conventions, see [openshift/enhancements](https://github.com/openshift/enhancements) — `dev-guide/`.
