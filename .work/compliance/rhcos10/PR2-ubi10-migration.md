# PR2: RHCOS10 — Migrate Base Images from UBI9 to UBI10

## Purpose

Migrate all container base images from UBI9 to UBI10 to align with the RHCOS10 host OS.
This is the follow-up to PR1 (`rhcos10-ubi9-compat-test`), which validated that UBI9 images
run on RHCOS10 nodes. This PR adopts UBI10 as the native base for RHCOS10 deployments.

## Changes

### Registry change

All images move from the unauthenticated public registry to the authenticated Red Hat registry:

```
registry.access.redhat.com  →  registry.redhat.io
```

### UBI minimal images (pinned version)

`ubi9/ubi-minimal:9.6` → `ubi10/ubi-minimal:10.1`

| Dockerfile | Before | After |
|---|---|---|
| `images/helm-operator/Dockerfile` | `registry.access.redhat.com/ubi9/ubi-minimal:9.6` | `registry.redhat.io/ubi10/ubi-minimal:10.1` |
| `images/operator-sdk/Dockerfile` | `registry.access.redhat.com/ubi9/ubi-minimal:9.6` | `registry.redhat.io/ubi10/ubi-minimal:10.1` |
| `images/scorecard-test/Dockerfile` | `registry.access.redhat.com/ubi9/ubi-minimal:9.6` | `registry.redhat.io/ubi10/ubi-minimal:10.1` |
| `images/custom-scorecard-tests/Dockerfile` | `registry.access.redhat.com/ubi9/ubi-minimal:9.6` | `registry.redhat.io/ubi10/ubi-minimal:10.1` |

### Full UBI image (pinned version)

`ubi9/ubi:9.5` → `ubi10/ubi:10.1`

| Dockerfile | Before | After |
|---|---|---|
| `images/scorecard-untar/Dockerfile` | `registry.access.redhat.com/ubi9/ubi:9.5` | `registry.redhat.io/ubi10/ubi:10.1` |

### UBI minimal images (floating latest tag)

`ubi9/ubi-minimal:latest` → `ubi10/ubi-minimal:latest`

| Dockerfile | Before | After |
|---|---|---|
| `ci/dockerfiles/go-e2e.Dockerfile` | `registry.access.redhat.com/ubi9/ubi-minimal:latest` | `registry.redhat.io/ubi10/ubi-minimal:latest` |
| `ci/dockerfiles/scorecard-proxy.Dockerfile` | `registry.access.redhat.com/ubi9/ubi-minimal:latest` | `registry.redhat.io/ubi10/ubi-minimal:latest` |

### OCP product image (release/helm/Dockerfile)

Previously used OCP CI registry images pinned to RHEL9. Replaced with publicly available Red Hat registry images:

| Stage | Before | After |
|---|---|---|
| Builder | `registry.ci.openshift.org/ocp/builder:rhel-9-golang-1.24-openshift-4.22` | `registry.redhat.io/ubi10/go-toolset:10.1` |
| Runtime | `registry.ci.openshift.org/ocp/4.22:base-rhel9` | `registry.redhat.io/ubi10:10.1` |

### E2E test curl pod (ci/tests/e2e-helm.sh)

The metrics verification step spins up a temporary `kubectl run` pod using a UBI image to curl the metrics endpoint. Updated from UBI9 to UBI10:

```
registry.access.redhat.com/ubi9/ubi-minimal:latest
→
registry.redhat.io/ubi10/ubi-minimal:latest
```

## Files NOT Changed

| File | Reason |
|---|---|
| `release/helm/upstream.Dockerfile` | Uses `ubi8/ubi-minimal` — separate RHEL8 lineage, unrelated to this migration |
| `ci/dockerfiles/builder.Dockerfile` | Uses `openshift/origin-release:golang-1.13` — legacy, not RHEL9-specific |
| `.ci-operator.yaml` | Build root (`rhel-9-release-golang-1.24-openshift-4.22`) is managed by OCP CI team in `openshift/release` |

## Test Plan

- [ ] All images build successfully against `ubi10` base
- [ ] `release/helm/Dockerfile` builds successfully with `go-toolset:10.1` as builder
- [ ] CI jobs pass on RHCOS10 cluster nodes with UBI10 base images
- [ ] `microdnf` commands in `images/operator-sdk/Dockerfile` work under UBI10
- [ ] E2e metrics check passes with UBI10 curl pod (`ci/tests/e2e-helm.sh`)
- [ ] No regressions observed compared to UBI9 baseline (PR1)

## References

- [Red Hat UBI10 Container Catalog](https://catalog.redhat.com/en/software/containers/ubi10/ubi/66f2b46b122803e4937d11ae)
- [Red Hat UBI10 Minimal Container Catalog](https://catalog.redhat.com/en/software/containers/ubi10/ubi-minimal)
- PR1 baseline: `.work/compliance/rhcos10/PR1-ubi9-compat-test.md`
