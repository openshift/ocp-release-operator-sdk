# Threat Model

This document describes the threat model for the OpenShift Operator SDK build and release pipeline. It does not contain credentials or operational secrets.

## System Context

The Operator SDK is a CLI toolkit (`operator-sdk`) and a Helm-based reconciler runtime (`helm-operator`) used to build, test, and package Kubernetes operators. The build pipeline produces Go binaries and container images published to quay.io. CI runs on GitHub Actions (upstream) and OpenShift Prow (downstream).

```text
Developer --> GitHub PR --> CI (GitHub Actions / Prow) --> Release artifacts
                                                           ├── Go binaries
                                                           ├── Container images
                                                           └── Checksums
```

## Assets

| Asset | Description | Sensitivity |
|---|---|---|
| Source code | Go source in `cmd/`, `internal/`, `hack/` | High — integrity critical for all downstream consumers |
| Vendored dependencies | Third-party code in `vendor/` | High — supply-chain attack surface |
| Release binaries | `operator-sdk`, `helm-operator` built by goreleaser | Critical — executed by operator developers |
| Container images | Images in `images/` published to quay.io | Critical — run in production clusters |
| CI/CD secrets | GitHub Actions tokens, registry credentials | Critical — ephemeral, not stored in repo |
| Generated artifacts | `testdata/`, `internal/bindata/`, CLI docs | Medium — drift detection via `git diff --exit-code` |

## Entry Points and Trust Boundaries

| # | Entry point | Trust boundary | Authentication |
|---|---|---|---|
| 1 | GitHub Pull Request | Untrusted fork code enters CI | GitHub identity; `GITHUB_TOKEN` read-only for forks |
| 2 | Release tag push | Triggers binary/image builds | Only maintainers in `OWNERS` can approve |
| 3 | Dependabot PRs | Automated dependency updates | GitHub App identity; subject to PR review |
| 4 | Fetched tools (curl) | External binaries enter build env | HTTPS + pinned versions; no checksum verification |
| 5 | Container base images | External image layers | Registry TLS; Trivy scanning for CVEs |
| 6 | Upstream merge | Upstream code enters fork | Manual review + `UPSTREAM-MERGE.sh` script |

## Threats

| ID | Threat | Actor | Impact | Likelihood | Status |
|---|---|---|---|---|---|
| T1 | Malicious PR exfiltrates CI secrets | External contributor | CI secret exposure | Low | Mitigated |
| T2 | Compromised upstream GH Action | Supply chain | Arbitrary CI code execution | Low | Mitigated |
| T3 | Artifact tampering during release | Insider / compromised CI | Distributed malicious binaries | Very Low | Partial |
| T4 | Supply-chain vulnerability in vendor | External attacker | Code execution in operator | Medium | Mitigated |
| T5 | Base image CVE inherited | External attacker | Container compromise | Medium | Monitored |
| T6 | Fetched tool binary compromise | Supply chain | Build-time code execution | Low | Accepted |
| T7 | Compromised generator produces malicious testdata | Insider | Malicious code in e2e tests | Very Low | Mitigated |
| T8 | Credential leak via Dockerfile or build logs | Misconfiguration | Secret exposure | Low | Mitigated |

## Deprioritized

| ID | Threat | Rationale |
|---|---|---|
| T6 | Fetched tool binary compromise | All tool versions are pinned; binaries are git-ignored. SHA256 verification would further reduce risk but is deferred (low likelihood). |

## Open Questions

1. Should fetched tool binaries (golangci-lint, kind, kubectl) include SHA256 checksum verification?
2. Should goreleaser be vendored or pinned by checksum rather than fetched at build time?
3. Should GitHub Actions be pinned by full commit SHA instead of semver tags (M2)? Deferred for now to match existing repo convention.
4. Should container images be signed with cosign/Sigstore in addition to binary checksum signing (M3)?

## Provenance

| Field | Value |
|---|---|
| Mode | Manual analysis by repository maintainers |
| Date | 2025-01-15 |
| Last reviewed | 2025-01-15 |
| Owners | Repository maintainers (see `OWNERS` file) |
| Tool | N/A (narrative threat model) |

## Recommended Mitigations

| ID | Mitigation | Threat(s) | Status |
|---|---|---|---|
| M1 | Fork PRs use read-only `GITHUB_TOKEN`; `pull_request` trigger (not `pull_request_target`) | T1 | Implemented |
| M2 | GitHub Actions pinned to semver tags (e.g. `@v6`), consistent with existing repo workflows | T2 | Partial — full SHA pinning is a future improvement |
| M3 | goreleaser signs `checksums.txt` with GPG for binary releases; only `OWNERS` approve release commits | T3 | Partial — container images are not cosign/Sigstore-signed; consumers can only verify binary checksums today |
| M4 | `govulncheck` + Dependabot + OSV scan in CI | T4 | Implemented |
| M5 | Trivy Dockerfile scanning in Prow CI | T5 | Implemented |
| M6 | Tool versions pinned in Makefile; downloaded over HTTPS to git-ignored `tools/bin/` | T6 | Partial |
| M7 | `testdata/` regenerated deterministically; `git diff --exit-code` in CI | T7 | Implemented |
| M8 | No secrets in repo or images; ephemeral CI credentials | T8 | Implemented |
| M9 | CodeQL SAST scanning (available via GitHub Advanced Security) | T1, T4 | Planned |
| M10 | Documented exceptions in `docs/security-exceptions.md` | T4, T5 | Implemented |

## Cross-References

- [SECURITY.md](SECURITY.md) — Vulnerability reporting process
- [docs/security-exceptions.md](docs/security-exceptions.md) — Accepted vulnerability exceptions
- CI security scanning is handled by OpenShift Prow (downstream) and `make test-sanity` checks
