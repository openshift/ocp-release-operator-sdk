# Plugin System Design Intent

## Overview

The Operator SDK plugin system (`internal/plugins/`) extends Kubebuilder's plugin interface to support Helm-based, Manifests-based, and Scorecard-based operator scaffolding. All plugins share the `.sdk.operatorframework.io` name qualifier defined in `plugins.go`.

## Invariants

1. **Plugin names are globally unique.** Each plugin is identified by `<short-name>.sdk.operatorframework.io/v<N>`. The short name plus version must be unique across all registered plugins. Duplicate registration panics at CLI initialization time.

2. **Scaffolding is idempotent for existing files.** Plugins that scaffold files (Helm/v1, Manifests/v2) must not overwrite existing files unless the user explicitly opts in. The Kubebuilder machinery's `Scaffold()` method enforces this by checking file existence before writing.

3. **Generated files carry a DO NOT EDIT header.** Files produced by code generation (`zz_generated*` prefix, files in `testdata/`, `internal/bindata/`, `*fakes/`) must include a generation header. Editing these files directly is prohibited; the generator or template must be modified instead.

4. **Plugin version matches API version.** The Helm/v1 plugin scaffolds `watches.yaml` and Helm chart structure for Helm v3. The Manifests/v2 plugin generates OLM bundle manifests compatible with the `bundle.mediatype` format. Version bumps require a new plugin version directory.

## Preconditions

- Kubebuilder must be initialized (`PROJECT` file must exist) before running plugin-specific subcommands. The CLI validates this via `config.LoadInitialized()`.
- For Helm/v1: a valid Helm chart must exist at the specified path, or the `--helm-chart` flag must point to a fetchable chart repository.
- For Scorecard/v2: the bundle directory must contain a valid `bundle.Dockerfile` and `manifests/` directory.

## Extension points

| To add... | Where | Contract |
|---|---|---|
| New operator type | `internal/plugins/<type>/v1/` | Implement `plugin.Plugin` interface, register in `cli.go` |
| New scaffolding resource | Add to plugin's `Scaffolder` | Must respect file existence check, add DO NOT EDIT header |
| New scorecard test | `internal/scorecard/tests/` | Implement `Test` interface, register in scorecard config |
| New CLI flag | Plugin's `BindFlags()` method | Must not conflict with Kubebuilder core flags |

## Rationale

- **Why internal-only?** All plugin code is under `internal/` with no `pkg/` directory. This is deliberate: the plugin API is not stable for external consumption. External plugins use the Kubebuilder external plugin protocol (JSON over stdin/stdout) instead.
- **Why separate Manifests/v2 from the operator type plugins?** Manifests generation (CSV, bundle) is orthogonal to the operator type (Go, Helm, Ansible). Separating them allows any operator type to use OLM bundle generation without coupling.
- **Why `DefaultNameQualifier`?** The `.sdk.operatorframework.io` suffix distinguishes Operator SDK plugins from Kubebuilder core plugins (`.kubebuilder.io`) and third-party plugins, preventing naming collisions in the plugin registry.
