---
status: Accepted
applies_to: ocp-release-operator-sdk
---
# ADR-0003: Release Signing and Build Automation

## Status

Accepted

## Context

The Operator SDK produces two CLI binaries and several container images. Releases must be verifiable and reproducible. The downstream build uses OpenShift Prow CI, while upstream uses GitHub Actions with goreleaser.

## Decision

1. **Use goreleaser for upstream-style releases** with checksums for all binary artifacts. The goreleaser configuration lives in [`.goreleaser.yml`](../../.goreleaser.yml) at the repository root.
2. **Sign the checksum file, not individual binaries or images.** goreleaser's `signs` stanza GPG-signs `checksums.txt` using the CI signing subkey decrypted into `.ci/gpg/keyring`. This covers the release binaries' checksum manifest; it does **not** sign container images. Container images have no cosign/Sigstore signature today (tracked in [THREAT_MODEL.md](../../THREAT_MODEL.md) M3 as `Partial`).
3. **Inject version information via ldflags** at build time into `internal/version/`. Five variables (`Version`, `GitVersion`, `GitCommit`, `KubernetesVersion`, `ImageVersion`) are set in the Makefile.
4. **Downstream releases override the version** to append `-ocp` via `patches/03-setversion.patch`, so downstream binaries are clearly distinguishable from upstream.
5. **Container images are built with `CGO_ENABLED=0`** for static binaries. Dockerfiles live in `images/`.
6. **Release commits update `IMAGE_VERSION`** in the Makefile and must pass `make prerelease` validation.

## Consequences

- Release binary checksums are GPG-signed for integrity verification; consumers can verify `checksums.txt.asc` against the checksums, but there is currently no equivalent signature for container images.
- Downstream builds are clearly versioned with the `-ocp` suffix.
- The version patch must be updated on each upstream merge to reference the new version.
- goreleaser is fetched at build time via `tools/scripts/fetch`, introducing a supply-chain dependency. Fetches are pinned to a specific version and use HTTPS, but `tools/scripts/fetch` does not verify a SHA256 checksum of the downloaded binary -- this residual gap is tracked as an open question in [THREAT_MODEL.md](../../THREAT_MODEL.md) rather than addressed here.

## Alternatives Considered

- **Manual release process:** Rejected for lack of reproducibility and auditability.
- **Using `go install` for distribution:** Does not produce container images or cross-compiled binaries.
- **Embedding version at source level:** Would cause merge conflicts on every upstream sync; ldflags injection avoids this.
