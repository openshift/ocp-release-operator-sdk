# Pattern: Generated Artifacts and CI/Lint Changes

How to modify generators, linter configuration, or CI workflows.

## Generated Artifacts

| Artifact | Generator | Regenerate Command |
|---|---|---|
| `testdata/` | `hack/generate/samples/generate_testdata.go` | `make generate` |
| CLI docs (`website/content/en/docs/cli/`) | `hack/generate/cli-doc/gen-cli-doc.go` | `make generate` |
| CNCF maintainers | `hack/generate/cncf-maintainers/main.go` | `make generate` |
| OLM bindata (`internal/bindata/`) | `hack/generate/olm_bindata.sh` | `make bindata` |
| Counterfeiter fakes (`*fakes/`) | `go generate ./...` | `make generate` |

Do not hand-edit any of these files. Edit the generator or template, then regenerate.

## Changing Linter Rules

1. Edit `.golangci.yml` (v2 format).
2. Run `make lint` to verify the new rules pass.
3. Run `make fix` to auto-fix where possible.
4. Run `make verify` to confirm no regressions.

Current enabled linters: `dupl`, `ginkgolinter`, `goconst`, `gocyclo`, `gosec`, `misspell`, `nakedret`, `revive`, `unconvert`, `unparam`, `depguard`.

## Changing CI Workflows

### GitHub Actions (upstream-style)

Workflows live in `.github/workflows/`. The primary required gate is `quality-gate.yml`, which runs `make setup`, `make build`, and `make test-static`.

### OpenShift Prow (downstream)

Prow configuration is in `ci/prow.Makefile`. Prow always applies `patches/` before running builds or tests. If you change a Makefile target that Prow uses, check whether a patch modifies that target.

## Targeted Tests

```bash
make generate        # regenerate all artifacts
make verify          # full pre-PR gate (includes git diff --exit-code)
```

## Review Risks

- `make test-sanity` runs `make generate` and then `git diff --exit-code`. Any uncommitted generated change fails CI.
- Changing golangci-lint configuration may surface new lint failures across the codebase.
- Prow patches may conflict with Makefile changes; test with `make -f ci/prow.Makefile patch`.
