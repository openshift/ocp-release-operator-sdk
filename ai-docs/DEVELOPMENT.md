# Development

## Start with the downstream workflow

Read [README.md](../README.md) before using upstream instructions.
[CONTRIBUTING.MD](../CONTRIBUTING.MD) defines commit formatting.
[The inherited developer guide](../website/content/en/docs/contribution-guidelines/developer-guide.md)
is useful context, but its Go prerequisite is older than the current module directive.

## Toolchain and module identity

`go.mod:3` declares Go **1.26.3**; there is no separate `toolchain` directive.
The module path remains `github.com/operator-framework/operator-sdk` (`go.mod:1`).
Do not rename imports to the downstream repository path.
The build exports `CGO_ENABLED=0` and uses `containers_image_openpgp`
(`Makefile:36`, `Makefile:33`).

## Build choices

| Intent | Command | Effect |
|---|---|---|
| Downstream compatibility gate | `make -f ci/prow.Makefile patch build` | Applies carried patches and builds Helm (`ci/prow.Makefile:12`) |
| Compile both upstream-style executables | `make build` | Produces binaries in `build/` (`Makefile:95`) |
| Compile Helm only | `make build/helm-operator` | Uses the root target without applying patches (`Makefile:99`) |
| Install both executables | `make install` | Installs via Go into the selected Go binary directory (`Makefile:90`) |

The patch target modifies the checkout. Use a disposable worktree for patch/build
validation and inspect its status afterward; do not commit patched mirror files accidentally.
See the [documented patch workflow](../README.md#patching).

## Common Tasks

### Change SDK commands

Start at `internal/cmd/operator-sdk/cli/cli.go:55` for command registration.
Commands belong under `internal/cmd/operator-sdk/`; scaffolding bundles are assembled
in `GetPluginsCLIAndRoot` (`internal/cmd/operator-sdk/cli/cli.go:84`).
For bundle validation changes read the command help and implementation together:
`internal/cmd/operator-sdk/bundle/validate/cmd.go:31` and
`internal/cmd/operator-sdk/bundle/validate/validate.go:113`.

### Change Helm watch behavior

Update loading in `internal/helm/watches/watches.go:87`, startup forwarding in
`internal/cmd/helm-operator/run/cmd.go:190`, and controller options in
`internal/helm/controller/controller.go:46` as needed.
Keep omitted-field defaults covered in `internal/helm/watches/watches_test.go`.

### Change Helm release behavior

Trace `internal/helm/controller/reconcile.go:79` into the manager interface at
`internal/helm/release/manager.go:47` before editing release actions.
Keep CR updates separate from chart-resource repair; see
[resource management](ARCHITECTURE.md#resource-management).

### Refresh generated artifacts

`make generate` builds first, removes `testdata`, regenerates docs and samples,
then runs Go generators (`Makefile:42`).
`make bindata` invokes the OLM asset script and `make fix` (`Makefile:51`).
These are mutating workflows, not lightweight documentation checks.

## Build-time metadata

The Makefile injects version, Git version, Git commit, Kubernetes version,
and image version with linker flags (`Makefile:25`).
The corresponding variables default to `unknown` in
`internal/version/version.go:18`.
Direct Go builds without those flags are not equivalent metadata checks.

## Downstream release navigation

`UPSTREAM-VERSION` records the upstream tag used by the rebase wrapper;
see [automatic rebase documentation](../README.md#automatic-rebase-periodic).
`release/helm/Dockerfile:8` invokes the downstream patch/build path.
Do not run merge automation as part of an unrelated documentation change.

## CI and validation choices

| Check | Defined behavior |
|---|---|
| `make test-unit` | Short race-enabled Go package tests (`Makefile:171`) |
| `make test-sanity` | Generation, formatting, lint, license/log checks, vet (`Makefile:153`) |
| `make test-docs` | Changelog validation, website submodules, website link build (`Makefile:163`) |

Downstream patches alter the root sanity target; inspect the patch before comparing
patched CI behavior with an unpatched local run (`patches/00-fixsanity.patch:1`).
The GitHub sanity workflow runs `make test-sanity` and `make test-docs`
(`.github/workflows/test-sanity.yml:42`, `.github/workflows/test-sanity.yml:52`).

## Documentation-only work

[The documentation contribution guide](../website/content/en/docs/contribution-guidelines/documentation.md)
describes website previews and `make test-docs`.
Root agent docs are outside the website HTML input (`hack/check-links.sh:10`).
Check their relative links, YAML, symlink, line counts, and diff separately.
Do not assume the docs-only CI detector recognizes YAML sidecars: its patterns
are listed in `.github/workflows/check-docs-only.sh:11`.

## Common Mistakes

1. DO NOT apply downstream patches twice to the same tree; inspect the patch target (`ci/prow.Makefile:12`).
2. DO NOT infer JSON merge semantics from a helper name; inspect the returned patch type (`internal/helm/release/manager.go:341`).
3. DO NOT run `make fix` expecting read-only lint: the unpatched recipe runs
   `go mod tidy`, formatting, and automatic lint fixes (`Makefile:56`).
   The downstream patch removes `go mod tidy` but retains formatting and automatic
   lint fixes (`patches/00-fixsanity.patch:8`).
4. DO NOT mistake inherited upstream branch examples for this checkout's `main` base.

## SME Review Recommended

Confirm current release procedures before executing image publication or rebase automation.
This guide does not claim to validate release credentials, product support, or live CI schedules.

## Further Reading

- [Test navigation](TESTING.md)
- [Design catalog](ENHANCEMENTS.md)
- [Platform development guidance](https://github.com/openshift/enhancements/tree/master/dev-guide)
