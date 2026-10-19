# Contributing to OpenShift Operator SDK

This guide covers the contribution workflow for the OpenShift downstream fork of [operator-framework/operator-sdk](https://github.com/operator-framework/operator-sdk). For detailed repository conventions, architecture, and domain-specific guidelines, see [AGENTS.md](AGENTS.md) and the files in [docs/](docs/).

## Prerequisites

- **Go 1.26.3+** (see `go.mod` for the exact version)
- **make** as the build system
- **git** with access to this repository

The build tag `containers_image_openpgp` is required for all Go commands. The Makefile handles this automatically, so prefer `make` targets over raw `go` commands.

## Quick Start

```bash
# Build both binaries (operator-sdk and helm-operator)
make build

# Run all pre-commit checks (REQUIRED before every commit)
make test-sanity

# Run unit tests
make test-unit

# Auto-fix formatting and lint issues
make fix
```

## Development Workflow

### 1. Create a Branch

Branch from `main` for new work. Use a descriptive branch name (e.g., `fix-csv-generation`, `add-helm-watch-filter`).

### 2. Make Changes

- All implementation code lives in `internal/` -- nothing is exported as a Go library.
- CLI commands follow the `NewCmd() *cobra.Command` pattern (see `internal/cmd/operator-sdk/` for examples).
- Never hand-edit generated files (`zz_generated*`, `testdata/`, `internal/bindata/`, `*fakes/`). Edit the generator or template instead.

### 3. Run Pre-commit Checks

```bash
make test-sanity
```

This runs formatters, linters, license checks, error message format validation, and verifies no uncommitted generated files remain. **CI will reject your PR if this does not pass.**

### 4. Commit and Push

Follow the commit message conventions below, then open a PR.

## Commit Message Conventions

### Downstream Commits (OpenShift-specific changes)

All downstream-specific commits **must** use one of these prefixes:

- **`UPSTREAM: <carry>:`** -- Persistent changes that survive upstream rebases (OpenShift-specific modifications, CI config, image references).
- **`UPSTREAM: <drop>:`** -- Temporary commits regenerated on each rebase (vendor updates, auto-generated content).

### Regular Commits

Use the format: `<subsystem>: <what changed>` -- subject line max 70 chars, body wrapped at 80 chars.

Examples:
```
helm: fix release history lookup for upgrades
generate/csv: handle multiple GVKs in a single package
UPSTREAM: <carry>: Update Go builder images to golang-1.26-openshift-5.0
UPSTREAM: <drop>: Update vendor directory
```

## Code Style Requirements

These are enforced by CI and will fail your PR if violated.

### Error and Log Message Formatting

Checked by `hack/check-error-log-msg-format.sh`:

```go
// CORRECT
log.Info("Creating resource")                          // Log messages: uppercase start
return fmt.Errorf("failed to create resource: %w", err) // Errors: lowercase start, no trailing punctuation

// WRONG -- CI will reject
log.Info("creating resource")           // lowercase log message
return fmt.Errorf("Failed to create.")  // uppercase + trailing punctuation
```

### License Header

Every `.go` file must contain `Copyright`, `generated`, `GENERATED`, or `Licensed` in its first 3 lines. Use the Apache 2.0 header:

```go
// Copyright 2026 The Operator-SDK Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
```

### Import Ordering

Three groups separated by blank lines: (1) standard library, (2) third-party, (3) internal packages.

### Logging Libraries

- **CLI commands** (`operator-sdk`): use `github.com/sirupsen/logrus`
- **Controller runtime** (`helm-operator`): use `sigs.k8s.io/controller-runtime/pkg/log`

Never mix these within a component.

### Linting

Configured in `.golangci.yml` (v2 format). Run `make lint` to check, `make fix` to auto-fix. Dot imports are allowed only for Ginkgo/Gomega in test files.

## Testing

| Command | Purpose |
|---------|---------|
| `make test-sanity` | Format, lint, license, error format checks **(run before every commit)** |
| `make test-unit` | Unit tests with race detection |
| `make test-static` | All non-cluster tests (sanity + unit + docs) |
| `make test-e2e` | E2E tests (requires KIND cluster) |

If running `go test` directly, you **must** include the build tag:
```bash
go test -tags containers_image_openpgp ./...
```

For testing conventions (Ginkgo/Gomega, table-driven tests, async assertions), see [CLAUDE.md](CLAUDE.md).

## Vendor Directory

Dependencies are vendored (committed `vendor/` directory). After modifying `go.mod`:

1. Run `go mod tidy`
2. Run `go mod vendor`
3. Commit the vendor update as a **separate commit** with prefix `UPSTREAM: <drop>: Update vendor directory`

## Changelog Fragments

User-facing changes require a changelog fragment. Add a YAML file to `changelog/fragments/` following the template in `changelog/fragments/00-template.yaml`:

```yaml
entries:
  - description: >
      Brief description of the change in markdown format.
    kind: "bugfix"  # One of: addition, change, deprecation, removal, bugfix
    breaking: false
```

For plugin changes, prefix the description with `(<language>/<plugin version>)`. For runtime changes, prefix with `For <language>-based operators,`.

## Pull Request Expectations

1. **Run `make test-sanity`** before pushing -- CI enforces this including `git diff --exit-code`.
2. **Include a changelog fragment** for user-facing changes.
3. **Use correct commit prefixes** for downstream changes (`UPSTREAM: <carry>:` or `UPSTREAM: <drop>:`).
4. **Ansible changes** belong in the separate [ansible-operator-plugins](https://github.com/operator-framework/ansible-operator-plugins) repo.
5. PRs are reviewed by teams defined in `OWNERS_ALIASES`: `sdk-admins`, `sdk-approvers`, and `sdk-reviewers`.

## Patch System

Downstream patches live in `patches/` and are applied during CI via `make -f ci/prow.Makefile patch`. Before modifying build behavior, check whether a patch already exists. Patches use `diff -up` format. See the [README](README.md#patching) for the full patching workflow using `gendiff`.

## Domain-Specific Documentation

For design rationale and architectural constraints, see `docs/design/`. For common change patterns, see `docs/patterns/`. For build commands and conventions, see [CLAUDE.md](CLAUDE.md) and [AGENTS.md](AGENTS.md).

## For AI Agents

If you are an AI agent contributing to this repository, read [AGENTS.md](AGENTS.md) first. It contains the complete onboarding guide including repository layout, architectural context, code style conventions, common pitfalls, and all the rules that apply to automated contributions. The domain-specific guidelines in `docs/` provide deeper context for each area of the codebase.
