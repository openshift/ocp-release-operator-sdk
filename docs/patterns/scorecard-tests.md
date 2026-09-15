# Pattern: Adding Scorecard Tests

## When to use

When adding a new built-in conformance or custom test to the scorecard framework.

## Reference implementation

`internal/scorecard/tests/bundle_test.go` -- existing OLM bundle validation tests.

## Steps

1. Create a new test function in `internal/scorecard/tests/` following the `Test` interface.
2. Register the test in the scorecard configuration (test names must be unique).
3. Parallel tests run concurrently via `sync.WaitGroup` + buffered channel (`scorecard.go:127-137`). Ensure your test is safe for concurrent execution.
4. Tests receive a `context.Context` with a timeout ceiling. Respect context cancellation and do not create unbounded operations.
5. Add unit tests alongside the implementation. Scorecard tests should validate both pass and fail scenarios.
6. Update `testdata/` if the test requires sample bundles or manifests.

## Invariants

- Test output must be a `v1alpha3.TestResult` with `State`, `Log`, and optional `Errors`.
- Tests must not modify cluster state beyond their own namespace. The scorecard runner handles namespace lifecycle.
- Cleanup contexts use `context.WithTimeout(context.Background(), 30s)`, not the expired parent context.
