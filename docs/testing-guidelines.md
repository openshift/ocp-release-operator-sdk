# Testing Guidelines

## Test Framework

This repo uses two test frameworks side-by-side. The choice depends on which layer you are testing.

- **Ginkgo/Gomega** -- primary framework for unit tests in `internal/` packages and all E2E/integration tests. Most packages have a `suite_test.go` (or `*_suite_test.go`) that bootstraps a Ginkgo suite.
- **Standard `testing` + `testify/assert`** -- used in parts of the Helm subsystem (`internal/helm/`) and some scorecard tests. The scorecard package has a mix of Ginkgo and standard testing. Do not convert existing standard tests to Ginkgo without coordinating upstream.

When adding tests to a package that already has a `suite_test.go`, use Ginkgo. When the package uses `func TestXxx(t *testing.T)` without Ginkgo, use standard `testing`.

## Suite Files

Every Ginkgo package requires a `suite_test.go` file. Follow the existing pattern exactly:

```go
func TestSuiteName(t *testing.T) {
    RegisterFailHandler(Fail)
    RunSpecs(t, "Suite Name")
}
```

E2E and integration suites must guard against accidental runs in `make test-unit` by calling `testing.Short()`:

```go
if testing.Short() {
    t.Skip("skipping E2E suite in short mode")
}
```

The `test-unit` Makefile target passes `-short` and excludes `test/` entirely via `go list ... | grep -v test/`.

## Package Naming

Test package naming varies across the codebase:

- Some packages use the **external test package** pattern (`package foo_test`) in their suite files while using the internal package name in implementation test files.
- Tests in `internal/helm/` and registry subsystems typically use the **same package name** (white-box testing) to access unexported functions.
- E2E suites use descriptive external packages: `e2e_go_test`, `e2e_helm_test`.

Follow the existing pattern in the package you're modifying.

## Directory Layout

| Path | Purpose | Framework |
|------|---------|-----------|
| `internal/**/` | Unit tests, co-located with source | Ginkgo or standard |
| `test/e2e/go/` | Go operator E2E (requires Kind cluster) | Ginkgo |
| `test/e2e/helm/` | Helm operator E2E (requires Kind cluster) | Ginkgo |
| `test/integration/` | OLM integration (requires Kind cluster) | Ginkgo |
| `test/common/` | Shared spec functions reused across E2E suites | Ginkgo |
| `internal/testutils/` | TestContext helpers for E2E/integration | Ginkgo |
| `testdata/` | Sample operator projects copied into E2E temp dirs | N/A |
| `internal/*/testdata/` | Package-level fixture files (YAML, bundles) | N/A |

## Makefile Targets

| Target | What it runs |
|--------|-------------|
| `make test-unit` | `go test -race -short` on all packages except `test/` |
| `make test-static` | `test-sanity` + `test-unit` + `test-docs` |
| `make test-e2e` | All cluster-based E2E suites (requires `test-e2e-setup`) |
| `make test-e2e-go` | Go operator E2E only |
| `make test-e2e-helm` | Helm operator E2E only |
| `make test-e2e-integration` | OLM integration tests |
| `make test-all` | `test-static` + `test-e2e` |

Unit tests run with build tag `containers_image_openpgp` and coverage flags: `-coverprofile=coverage.out -covermode=atomic`.

## TestContext (E2E and Integration)

All cluster-based tests use `testutils.TestContext`, which wraps kubebuilder's `kbtestutils.TestContext`. It provides:

- Temp directory management and cleanup via `Destroy()`
- `tc.Make(target, args...)` to invoke Makefile targets in the sample project
- `tc.Kubectl` for cluster interaction (namespaced commands, apply, delete, wait, logs)
- `tc.Run(cmd)` to execute and capture output
- Kind cluster detection via `tc.IsRunningOnKind()`
- Image loading: `tc.LoadImageToKindCluster()` and `tc.LoadImageToKindClusterWithName(image)`
- OLM lifecycle: `tc.InstallOLMVersion(version)` / `tc.UninstallOLM()`

Create the context in `BeforeSuite` with `testutils.NewTestContext(testutils.BinaryName, "GO111MODULE=on")`, then configure `tc.Domain`, `tc.Group`, `tc.Version`, `tc.Kind`, `tc.Resources`, and `tc.ProjectName`.

E2E tests copy a sample project from `testdata/` into the temp directory. Do not modify `testdata/` samples at test time -- copy first, then mutate the copy.

## Shared Spec Functions (test/common/)

Reusable Ginkgo specs live in `test/common/`. Import and delegate with `Describe`:

```go
var _ = Describe("scorecard", common.ScorecardSpec(&tc, "go"))
```

`ScorecardSpec` returns a `func()` containing `It` blocks. This pattern keeps E2E suites DRY across Go and Helm operator types.

## Fake Client Patterns

For controller-runtime based code, use `fake.NewClientBuilder()`:

```go
fakeClient = fake.NewClientBuilder().
    WithScheme(sch).
    WithObjects(&corev1.Pod{...}, &appsv1.Deployment{...}).
    Build()
```

Register CRD schemes before building (`v1alpha1.AddToScheme(sch)`). To test error paths, wrap the fake client with a custom struct implementing `client.Client` that injects errors on specific object names.

## Table-Driven Tests

Two patterns coexist:

**Ginkgo `DescribeTable`/`Entry`** -- preferred for Ginkgo suites:

```go
DescribeTable("should return the expected config",
    func(input, expected string) { ... },
    Entry("basic", basicConfig, basicConfigExp),
    Entry("complex", complexConfig, complexConfigExp),
)
```

**Standard `testCases` slice** -- used in `testing`-based packages:

```go
testCases := []struct {
    name      string
    input     string
    expectErr bool
}{...}
for _, tc := range testCases {
    t.Run(tc.name, func(t *testing.T) { ... })
}
```

Include a `name` field in the struct and use `t.Run(tc.name, ...)` for subtests. In Ginkgo, label each `Entry`.

## Async Assertions (E2E)

Use `Eventually` with explicit timeout and poll interval for cluster state checks:

```go
Eventually(verifyControllerUp, 2*time.Minute, time.Second).Should(Succeed())
```

Use `EventuallyWithOffset(1, ...)` inside helper functions so failures report the caller's line. Standard timeouts in this repo: 1-3 minutes for pod readiness, 4-6 minutes for OLM operations.

## Test Output

- In Ginkgo tests, use `fmt.Fprintln(GinkgoWriter, ...)` for diagnostic output. Never use `fmt.Println` -- it bypasses Ginkgo's output capture.
- Import Ginkgo/Gomega with dot-import: `. "github.com/onsi/ginkgo/v2"`

## Testdata and Fixtures

- Top-level `testdata/go/v4/memcached-operator` and `testdata/helm/memcached-operator` are complete sample projects used by E2E tests. They are regenerated by `make generate`.
- Package-level `testdata/` directories contain YAML configs, bundles, shell scripts. Reference them with `filepath.Join("testdata", "bundle")` (relative to the test file).

## Adding New Tests

1. Determine if your code lives in a Ginkgo or `testing`-based package -- match the existing style.
2. For a new Ginkgo package, create `suite_test.go` with `RegisterFailHandler(Fail)` and `RunSpecs`.
3. Place test helpers that are only used within one package in the `_test.go` files, not in separate helper packages.
4. For cross-suite helpers, add them to `internal/testutils/` (cluster-oriented) or `test/common/` (shared specs).
5. E2E tests should clean up cluster resources in `AfterEach` or `AfterSuite` to avoid leaving CRDs, namespaces, or OLM installations behind.
6. Use `By("description")` annotations to document E2E test steps for readable output.
