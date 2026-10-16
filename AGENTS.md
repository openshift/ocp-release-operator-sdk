# OpenShift Release Operator SDK

**Repository**: openshift/ocp-release-operator-sdk

Downstream Operator SDK sources and packaging for OpenShift; the downstream
build selects the Helm operator (`ci/prow.Makefile:15`).

## Critical Warnings

1. Never confuse this downstream with the upstream SDK: read [README.md](README.md) before a rebase.
2. Never use the root build as proof of downstream patch compatibility: the gate is `make -f ci/prow.Makefile patch build` (`README.md:296`).
3. Never replace Helm drift correction with assumed SSA: inspect `createPatch` (`internal/helm/release/manager.go:317`).
4. Never bypass `watches.Load` defaults with direct YAML unmarshalling (`internal/helm/watches/watches.go:47`).

## Architecture at a Glance

| Surface | Start here |
|---|---|
| SDK scaffolding and commands | `internal/cmd/operator-sdk/cli/cli.go:84` |
| Helm runtime startup | `internal/cmd/helm-operator/run/cmd.go:95` |
| Helm reconciliation | `internal/helm/controller/reconcile.go:79` |
| Downstream image build | `release/helm/Dockerfile:1` |

## Documentation

Read [architecture and source map](ai-docs/ARCHITECTURE.md) →
[development](ai-docs/DEVELOPMENT.md) → [testing](ai-docs/TESTING.md).

```text
ai-docs/
├── ARCHITECTURE.md  # Runtime, source map, contracts, integrations
├── DEVELOPMENT.md   # Downstream build and change workflows
├── TESTING.md       # Checks, fixtures, and limits
└── ENHANCEMENTS.md  # Repository design references
```

[REVIEW.md](REVIEW.md) defines review policy; [.coderabbit.yaml](.coderabbit.yaml) translates it.

## Key Files

| Need | File |
|---|---|
| Downstream context | [README.md](README.md) |
| Upstream project overview | [README-sdk.md](README-sdk.md) |
| Build/test targets | [Makefile](Makefile), [Prow wrapper](ci/prow.Makefile) |
| Merge automation | [UPSTREAM-MERGE.sh](UPSTREAM-MERGE.sh), [auto-rebase](hack/auto-rebase.sh) |
| Contribution format | [CONTRIBUTING.MD](CONTRIBUTING.MD) |

## External References

- [Platform development conventions](https://github.com/openshift/enhancements/tree/master/dev-guide)
- [Platform conventions](https://github.com/openshift/enhancements/blob/master/CONVENTIONS.md)

`CLAUDE.md` is a symlink to this file.
