# Pattern: CLI Command Changes

How to add, modify, or remove a CLI subcommand in `operator-sdk` or `helm-operator`.

## Files to Touch

- `internal/cmd/operator-sdk/<subcommand>/` or `internal/cmd/helm-operator/<subcommand>/`
- `internal/cmd/operator-sdk/cli/cli.go` (if adding a new top-level command to operator-sdk)
- `cmd/helm-operator/main.go` (if adding to helm-operator)
- `website/content/en/docs/cli/` (CLI docs, regenerated)

## Command Function Pattern

All commands follow the `NewCmd() *cobra.Command` convention:

```go
func NewCmd() *cobra.Command {
    c := cmdState{}
    cmd := &cobra.Command{
        Use:   "subcommand",
        Short: "Short description",
        RunE:  c.run,
    }
    cmd.Flags().StringVar(&c.flagName, "flag-name", "", "Flag description")
    return cmd
}
```

Flag state lives in a private struct constructed inside `NewCmd()`. Do not use global variables for flags.

## Adding a New Command

1. Create a package under `internal/cmd/operator-sdk/<name>/`.
2. Implement `NewCmd() *cobra.Command` following the pattern above.
3. Wire it into `cli.go` via `WithExtraCommands` or into a parent command's subcommand list.
4. Regenerate CLI docs:

   ```bash
   make generate
   ```

5. Add unit tests in the same package.

## Logging

- `operator-sdk` commands: use `github.com/sirupsen/logrus`
- `helm-operator` commands: use `sigs.k8s.io/controller-runtime/pkg/log` (logr)

Do not mix these frameworks.

## Targeted Tests

```bash
make verify-file FILE=internal/cmd/operator-sdk/<name>/cmd.go
make generate   # regenerate CLI docs
make verify
```

## Review Risks

- New subcommands must have a changelog fragment in `changelog/fragments/`.
- CLI doc generation (`make generate`) must be run; CI enforces `git diff --exit-code`.
- Error messages must start lowercase with no trailing punctuation (CI-enforced).
- Log messages must start uppercase (CI-enforced).
