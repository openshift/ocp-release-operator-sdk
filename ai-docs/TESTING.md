# Testing

## Read the target before running it

[The inherited testing guide](../website/content/en/docs/contribution-guidelines/testing.md)
provides SDK test context. The current [Makefile](../Makefile) defines executable commands.
Downstream [Prow targets](../ci/prow.Makefile) can apply patches first.

## Non-cluster targets

| Target | Scope | Important side effect |
|---|---|---|
| `make test-unit` | Go packages excluding the `test/` subtree | Writes `coverage.out`; enables CGO and race detection (`Makefile:168`) |
| `make test-sanity` | Generated consistency, lint, license, log formatting, vet | Runs generation and automatic fixes (`Makefile:152`) |
| `make test-docs` | Changelog and website links | Initializes website submodules and runs containers (`Makefile:162`) |
| `make test-static` | Sanity, unit, docs | Aggregates mutating targets (`Makefile:149`) |

`make test-all` also includes E2E (`Makefile:146`).
Do not use it as a fast documentation-only gate.

## Helm watch tests

Start with `internal/helm/watches/watches_test.go`.
The implementation under test is `LoadReader` (`internal/helm/watches/watches.go:87`).

When modifying the loader, inspect these contracts:

- Missing version or kind returns an error (`internal/helm/watches/watches.go:149`).
- Empty group is permitted (`internal/helm/watches/watches.go:149`).
- Duplicate GVKs are rejected (`internal/helm/watches/watches.go:111`).
- Chart directories are checked (`internal/helm/watches/watches.go:107`).
- Omitted dependent-resource watches default to true (`internal/helm/watches/watches.go:115`).
- Overrides expand the environment before template evaluation (`internal/helm/watches/watches.go:128`).

Do not replace the loader in tests with direct YAML unmarshalling; the deprecated hook
does not represent the supported loading path (`internal/helm/watches/watches.go:47`).

## Helm reconciliation and release tests

| Area | Start here |
|---|---|
| Reconcile-period and annotation helpers | `internal/helm/controller/reconcile_test.go` |
| Helm release behavior | `internal/helm/release/manager_test.go` |
| Helm keep-resource policy detection | `internal/helm/client/client_test.go` |
| Runtime flags | `internal/helm/flags/flag_test.go` |

Keep install, upgrade, and drift repair distinct when selecting regression coverage.
They have separate entrypoints in `internal/helm/release/manager.go:169`,
`internal/helm/release/manager.go:213`, and `internal/helm/release/manager.go:267`.

CR metadata updates and status updates are also separate paths
(`internal/helm/controller/reconcile.go:480`).
For patch changes inspect both strategic and JSON branches, not only a successful install
(`internal/helm/release/manager.go:317`).

## Bundle validation tests

The validator package includes `validate_test.go`, `optional_test.go`, and
`cmd_suite_test.go` under `internal/cmd/operator-sdk/bundle/validate/`.
Its command help promises nonzero exit for errors but success for warnings only
(`internal/cmd/operator-sdk/bundle/validate/cmd.go:31`).
Avoid treating a warning-only result as an installability or certification guarantee.
The helper also supports image unpacking, so directory and image inputs have different
setup paths (`internal/cmd/operator-sdk/bundle/validate/validate.go:113`).

## Cluster and integration targets

| Root target | Dispatch |
|---|---|
| `make test-e2e-go` | Go E2E package (`Makefile:205`) |
| `make test-e2e-helm` | Helm E2E package (`Makefile:207`) |
| `make test-e2e-integration` | Integration package and OLM subcommand script (`Makefile:209`) |
| `make test-e2e-sample-go` | Generated Memcached sample Makefile (`Makefile:203`) |

Root E2E targets share setup prerequisites (`Makefile:200`).
Read them before assuming an existing cluster is sufficient.
The downstream Go/Helm E2E wrappers instead start in `ci/prow.Makefile:18`.

## Documentation checks

`make test-docs` first runs the changelog generator with `-validate-only`, then
initializes website submodules and runs `hack/check-links.sh` (`Makefile:162`).
The script builds `website/` with a Hugo container and checks the resulting HTML
with html-proofer (`hack/check-links.sh:9`).
It does not render root agent docs into that website; validate those directly.

For agent-doc edits, inspect:

- Relative links from each file's own directory.
- `CLAUDE.md` as a relative symlink to `AGENTS.md`.
- YAML parseability and synchronization with `REVIEW.md`.
- Referenced symbols and source line anchors.
- No source backups or review caches in the staged diff.

## CI interpretation

`.github/workflows/test-go.yml` invokes the root Go E2E and unit targets.
`.github/workflows/test-sanity.yml` invokes sanity and docs checks.
The shared docs-only detector uses filename patterns
(`.github/workflows/check-docs-only.sh:11`), not semantic risk.
A `.coderabbit.yaml` edit therefore should not be assumed to skip Go jobs.

## Evidence Limits

Passing static documentation checks does not demonstrate a cluster test pass.
Keep validator output, independent claim review, and runtime test results separate.
Do not report unexecuted commands as passed.

## Further Reading

- [Development](DEVELOPMENT.md)
- [Architecture](ARCHITECTURE.md)
- [Platform guidance](https://github.com/openshift/enhancements/tree/master/dev-guide)
