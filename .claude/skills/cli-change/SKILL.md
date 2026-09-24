# Skill: CLI Command Changes

## When to use

Adding, modifying, or removing a CLI subcommand in `operator-sdk`.

## Reference implementation

See `internal/cmd/operator-sdk/olm/cmd.go` for the canonical pattern.

## Steps

1. Create package under `internal/cmd/operator-sdk/<name>/`.
2. Implement `NewCmd() *cobra.Command` with flag state in a private struct.
3. Wire into `internal/cmd/operator-sdk/cli/cli.go` via `WithExtraCommands`.
4. Regenerate CLI docs: `make generate`.
5. Add changelog fragment to `changelog/fragments/`.

## Verification

```bash
make verify-file FILE=internal/cmd/operator-sdk/<name>/cmd.go
golangci-lint run --build-tags containers_image_openpgp ./internal/cmd/operator-sdk/<name>/
go vet -tags containers_image_openpgp ./internal/cmd/operator-sdk/<name>/
make generate && git diff --exit-code
make verify
```

## Constraints

- Error messages: start lowercase, no trailing punctuation.
- Log messages: start uppercase. Use `logrus` (not logr) for CLI code.
- Full guide: [docs/patterns/cli-changes.md](../../../docs/patterns/cli-changes.md)
