# CLI Architecture Guidelines

## Binary Entry Points

Two CLI binaries live in `cmd/`: `operator-sdk` and `helm-operator`. Both are thin wrappers -- `main()` calls into `internal/cmd/` for all logic. Never add business logic to `cmd/`; keep it to import, construct, and execute.

- `cmd/operator-sdk/main.go` delegates to `internal/cmd/operator-sdk/cli.Run()`.
- `cmd/helm-operator/main.go` builds a root `cobra.Command` inline, adding subcommands from `internal/cmd/helm-operator/`.

## CLI Construction via Kubebuilder

The `operator-sdk` binary uses Kubebuilder's `cli.New()` to construct its root command. This provides `init`, `create api`, `create webhook`, and plugin-based scaffolding. SDK-specific commands are injected through two separate lists:

- `cli.WithExtraCommands(commands...)` -- stable commands (bundle, cleanup, generate, olm, run, scorecard, pkgman-to-bundle).
- `cli.WithExtraAlphaCommands(alphaCommands...)` -- unstable commands placed under `alpha` subgroup.

New top-level commands go into the `commands` slice in `internal/cmd/operator-sdk/cli/cli.go`. Alpha/experimental commands go into `alphaCommands`.

## Command File Layout

Each subcommand lives in its own package under `internal/cmd/operator-sdk/<name>/`. The convention:

- `cmd.go` -- exports `NewCmd() *cobra.Command` as the single public entry point.
- Business logic in sibling files (e.g., `bundle.go`, `validate.go`).
- Nested subcommands get nested packages (e.g., `run/bundle/cmd.go`, `run/bundleupgrade/cmd.go`).

Parent commands that only group subcommands are minimal: create the `cobra.Command`, call `AddCommand`, return.

## Command Struct Pattern

Commands with flags use a private struct to hold flag values. The struct is constructed inside `NewCmd()`, and flag binding happens in the same function or via a dedicated method:

```go
type scorecardCmd struct {
    namespace    string
    outputFormat string
}

func NewCmd() *cobra.Command {
    c := scorecardCmd{}
    cmd := &cobra.Command{ /* ... */ }
    cmd.Flags().StringVarP(&c.namespace, "namespace", "n", "", "...")
    return cmd
}
```

## Flag Binding Conventions

Three patterns exist for binding flags; use the one matching the domain layer that owns them:

1. **Inline in `NewCmd()`** -- for command-specific flags. Bind directly with `cmd.Flags().StringVar(...)`.
2. **`BindFlags(fs *pflag.FlagSet)`** -- for reusable config structs (e.g., `operator.Configuration.BindFlags`). The command calls `cfg.BindFlags(cmd.Flags())`.
3. **`AddTo(fs *pflag.FlagSet)` / `AddToFlagSet(fs *pflag.FlagSet)`** -- used by operator runtime flag structs (e.g., `helm/flags.Flags.AddTo`). Same idea, different naming for operator-runtime code.

When a flag is irrelevant to a specific subcommand, hide it: `cmd.Flags().MarkHidden("service-account")`.

Short flags, when used, follow kubectl conventions: `-n` (namespace), `-o` (output), `-l` (selector), `-v` (version), `-s` (service-account).

## Shared Configuration Objects

Commands that interact with a Kubernetes cluster share `operator.Configuration`. The parent creates one instance and passes it to child `NewCmd(cfg)` functions. Each leaf command calls `cfg.Load()` in `PreRunE` to initialize the client lazily.

```go
cfg := &operator.Configuration{}
cmd.AddCommand(bundle.NewCmd(cfg), bundleupgrade.NewCmd(cfg))
// In leaf command:
PreRunE: func(*cobra.Command, []string) error { return cfg.Load() },
```

## Run vs RunE

**Prefer `RunE` for all new commands.** Return errors so Cobra can format and print them consistently; do not call `log.Fatalf` from inside `RunE`. Some existing commands (e.g. scorecard, bundle generate, olm install) use `Run` with `log.Fatalf` on errors -- this is a legacy pattern, not one to follow for new commands.

## Argument Validation

- Use `cobra.ExactArgs(1)` for commands requiring a single positional argument (bundle image, package name).
- Use `cobra.MaximumNArgs(1)` when the argument is optional with a default.
- For custom validation, use `PreRunE` with a `validate(args)` method on the command struct.

## Global Flags

The only global flag is `--verbose`, defined as a `PersistentFlag` on the root command and read via `viper.GetBool(flags.VerboseOpt)`. It sets logrus to `DebugLevel` and enables Go verbose mode. The constant lives in `internal/flags/flags.go`.

## Output Formatting

Two output patterns exist:

1. **Scorecard**: supports `text`, `json`, `xunit` via `-o` flag. Text uses `MarshalText()`, JSON uses `json.MarshalIndent`, xunit uses `xml.MarshalIndent`.
2. **Bundle validate**: supports `text`, `json-alpha1` via `-o` flag. Uses `Result.PrintWithFormat()` from `internal/validate/result.go`.

Tabular output (e.g., `--list-optional`) uses `text/tabwriter` with params `(out, 8, 4, 4, ' ', 0)`.

When a command produces structured output alongside logs, logs go to stderr and structured output to stdout so output can be piped.

## Plugin System

Plugins implement Kubebuilder's `plugin.Plugin` interface under `internal/plugins/<type>/v<N>/`. Each plugin package contains:

- `plugin.go` -- type definition, `Name()`, `Version()`, `SupportedProjectVersions()`, interface assertions.
- `init.go` -- `initSubcommand` implementing `plugin.InitSubcommand`.
- `api.go` -- `createAPISubcommand` implementing `plugin.CreateAPISubcommand` (if applicable).

Plugin names use the suffix `.sdk.operatorframework.io` (defined as `plugins.DefaultNameQualifier`). Plugins are composed into bundles using `plugin.NewBundleWithOptions`.

## Help Text Conventions

- `Use`: shows argument placeholders in angle brackets: `"cleanup <operatorPackageName>"`, `"run bundle <bundle-image>"`.
- `Short`: one-line imperative description, no period.
- `Long`: multi-paragraph explanation. Use raw string literals. Reference external docs with full URLs.
- `Example`: indented shell examples showing realistic usage.
- Deprecated commands use `Deprecated` field with migration instructions.

## Logging

Use `github.com/sirupsen/logrus` throughout the `operator-sdk` CLI layer (`cmd/operator-sdk/`, `internal/cmd/operator-sdk/`). The `helm-operator` binary uses controller-runtime's `logr` instead (`cmd/helm-operator/`, `internal/cmd/helm-operator/`, `internal/helm/`) -- its `main.go` only uses stdlib `log.Fatal` as a terminal exit handler. Never mix `logrus` and `logr` in the same package. Fatal errors in `Run` handlers use `log.Fatalf`; errors in `RunE` handlers are returned to Cobra.

## Version String

The version string includes SDK version, git commit, kubernetes version, Go version, GOOS, and GOARCH. It is assembled in `internal/cmd/operator-sdk/cli/version.go` using `internal/version` package variables set at build time via ldflags.

## Adding a New Command Checklist

1. Create `internal/cmd/operator-sdk/<name>/cmd.go` with `func NewCmd() *cobra.Command`.
2. Define a private struct for flag state if the command has flags.
3. Add the command to `commands` (or `alphaCommands`) in `internal/cmd/operator-sdk/cli/cli.go`.
4. If the command needs a k8s client, accept `*operator.Configuration` and call `cfg.Load()` in `PreRunE`.
5. Use `-o` with `text` default for any command producing structured output.
6. Validate arguments in `PreRunE` or via `Args` field, not inside `Run`/`RunE`.
7. Write logs to stderr; write structured/pipeable output to stdout.
