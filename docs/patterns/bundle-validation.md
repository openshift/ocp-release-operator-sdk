# Pattern: Bundle Validation Changes

## When to use

When adding or modifying OLM bundle validation rules in the `operator-sdk bundle validate` command.

## Reference implementation

`internal/validate/validators.go` -- validator registration and execution.

## Steps

1. Add a new validator function in `internal/validate/`. Validators receive a `bundle.Bundle` and return `[]errors.ManifestResult`.
2. Register the validator in the validator list. Validators are executed in registration order.
3. Optional validators should be gated behind a `--select-optional` flag value. Document the selector name.
4. Add test cases covering both valid and invalid bundle inputs in `internal/validate/` tests.
5. Update CLI documentation if the validator introduces new flags or selectors.

## Invariants

- Validators must be pure functions of their input bundle. They must not make network calls or access cluster state.
- Error messages must include the file path and field that caused the validation failure.
- Validators must not panic on malformed input. Return a `ManifestResult` with error details instead.
