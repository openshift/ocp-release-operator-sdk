# Operator SDK - Agentic Documentation

**Component**: Operator SDK (OSDK)
**Repository**: openshift/ocp-release-operator-sdk

> **AI agents**: Start with this file for conventions and architecture, then see `CLAUDE.md` for build commands and quick reference.
> **Platform Patterns**: See [openshift/enhancements/ai-docs/](https://github.com/openshift/enhancements/tree/master/ai-docs/) for operator patterns, testing, security, and cross-repo ADRs.

## What is Operator SDK?

A toolkit for building, testing, and packaging Kubernetes operators. This repository is the downstream OpenShift fork of [operator-framework/operator-sdk](https://github.com/operator-framework/operator-sdk), tracking upstream v1.42.3. The Go module path retains the upstream path (`github.com/operator-framework/operator-sdk`).

**Key Principle**: Two binaries from one module. `operator-sdk` is the developer CLI; `helm-operator` is the runtime reconciler. Everything is internal (no `pkg/`).

## Core Components

| Component | Location | Purpose |
|---|---|---|
| operator-sdk CLI | `cmd/operator-sdk/` -> `internal/cmd/operator-sdk/cli/` | Scaffold, build, validate, run operators |
| helm-operator | `cmd/helm-operator/` -> `internal/cmd/helm-operator/run/` | Reconcile Helm-based operators at runtime |
| Kubebuilder Plugins | `internal/plugins/` | Helm/v1, Manifests/v2, Scorecard/v2 |
| OLM Integration | `internal/olm/` | OLM install, client, operator lifecycle |
| Code Generation | `internal/generate/` | CSV generation, package manifests |
| Helm Runtime | `internal/helm/` | Controller, release management, watches |
| Scorecard | `internal/scorecard/` | Test runner and built-in conformance tests |
| Bundle Validation | `internal/validate/` | OLM bundle validation |
| Version Injection | `internal/version/` | Build-time ldflags (5 variables) |

## Critical Patterns

1. **DO NOT hand-edit generated files** -- `zz_generated*`, `testdata/`, `internal/bindata/`, `*fakes/` are all generated. Run `make generate` or `make bindata`.
2. **DO NOT forget the build tag** -- All Go commands require `-tags containers_image_openpgp`. Use Makefile targets.
3. **DO NOT mix logging frameworks** -- logrus for `operator-sdk` CLI, logr for `helm-operator` runtime.
4. **DO NOT commit vendor changes with source changes** -- Vendor updates are separate commits with `UPSTREAM: <drop>: Update vendor directory`.
5. **Update design docs** when changing architectural boundaries -- see [docs/design/](docs/design/) for preconditions, invariants, and rationale.

## Documentation Structure

```text
docs/
├── design/
│   ├── helm-reconciler.md      # Reconcile loop, watch dedup, status updates, concurrency
│   ├── olm-lifecycle.md        # Install/uninstall, timeout contexts, polling patterns
│   └── plugin-system.md        # Plugin naming, scaffolding contracts, extension points
└── patterns/
    ├── cli-changes.md           # Adding or modifying CLI commands
    ├── downstream-patches.md    # Creating and applying downstream patches
    ├── upstream-sync.md         # Merging upstream releases
    └── ...                      # Additional pattern guides
```

**AI Agent Path**: `AGENTS.md` -> `CLAUDE.md` -> `docs/design/` or `docs/patterns/` (as relevant)

## Quick Reference

| Action | Command |
|---|---|
| Bootstrap checkout | `make setup` |
| Full pre-PR gate | `make verify` |
| Single-file check | `make verify-file FILE=internal/olm/client/client.go` |
| Build binaries | `make build` |
| Unit tests | `make test-unit` |
| Sanity checks | `make test-sanity` |
| Lint | `make lint` |
| Auto-fix | `make fix` |
| Regenerate code | `make generate` |
| E2E tests | `make test-e2e` |

**Framework**: controller-runtime v0.21.0 | **Go**: 1.26.3 | **golangci-lint**: 2.9.0 | **Build tag**: `containers_image_openpgp`

## Pattern References

| Change type | Reference implementation | Guide |
|---|---|---|
| New CLI subcommand | `internal/cmd/operator-sdk/olm/cmd.go` | `.claude/skills/cli-change/SKILL.md` |
| Helm reconciler change | `internal/helm/controller/reconcile.go` | `.claude/skills/helm-runtime/SKILL.md` |
| Downstream patch | `patches/03-setversion.patch` | `.claude/skills/downstream-patch/SKILL.md` |
| Upstream merge | `UPSTREAM-MERGE.sh` | `.claude/skills/upstream-sync/SKILL.md` |
| Generated artifacts | `hack/generate/cli-doc/gen-cli-doc.go` | `.claude/skills/generate-artifacts/SKILL.md` |
| OLM lifecycle operation | `internal/olm/installer/manager.go` | `docs/design/olm-lifecycle.md` |
| Scorecard test addition | `internal/scorecard/tests/bundle_test.go` | `docs/patterns/scorecard-tests.md` |
| Bundle validation change | `internal/validate/external.go` | `docs/patterns/bundle-validation.md` |

## Downstream Fork Conventions

- **`UPSTREAM: <carry>:`** -- Persistent changes surviving upstream rebases
- **`UPSTREAM: <drop>:`** -- Temporary commits regenerated on each rebase
- **`<subsystem>: <what changed>`** -- Regular upstream-style (max 70 chars)
- **Patches**: `patches/` applied by `make -f ci/prow.Makefile patch`
- **Vendor**: Committed `vendor/`; updates are separate `<drop>` commits
- **Changelog**: User-facing PRs need a fragment in `changelog/fragments/`

## Knowledge Graph

```text
        [AGENTS.md] <- Start here
             |
      +------+------+
      |             |
  [CLAUDE.md]  [docs/design/]
  Quick ref    Invariants
  Commands     Rationale
      |             |
      +------+------+
             |
      [docs/patterns/]
      Common changes
      Step-by-step
```

## External References

- [Upstream Operator SDK](https://sdk.operatorframework.io/)
- [Downstream OpenShift Docs](https://docs.openshift.com/)
- [OLM Documentation](https://olm.operatorframework.io/)
- [Enhancement Proposals](https://github.com/openshift/enhancements/)

---

**Platform Documentation**: [openshift/enhancements/ai-docs/](https://github.com/openshift/enhancements/tree/master/ai-docs/)
