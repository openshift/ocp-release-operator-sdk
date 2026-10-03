# PR1: RHCOS10 Compatibility Test — Existing UBI9 Images

## Purpose

This PR contains **no Dockerfile changes**. Its goal is to validate that the existing
UBI9-based images build and run correctly on RHCOS10 cluster nodes, before committing
to a full base-image migration.

## Background

Red Hat CoreOS 10 (RHCOS10) ships with RHEL10 as its host OS. While UBI9-based container
images are expected to remain compatible with RHCOS10 (containers are isolated from the
host), this PR triggers CI against an RHCOS10 cluster to confirm there are no runtime
surprises before we proceed with the UBI10 migration (see PR2).

## Images Under Test

All images currently use `registry.access.redhat.com/ubi9/ubi-minimal:9.6` or
`registry.access.redhat.com/ubi9/ubi:9.5` as their final base image:

| Image | Dockerfile | Base Image |
|---|---|---|
| helm-operator | `images/helm-operator/Dockerfile` | `ubi9/ubi-minimal:9.6` |
| operator-sdk | `images/operator-sdk/Dockerfile` | `ubi9/ubi-minimal:9.6` |
| scorecard-test | `images/scorecard-test/Dockerfile` | `ubi9/ubi-minimal:9.6` |
| custom-scorecard-tests | `images/custom-scorecard-tests/Dockerfile` | `ubi9/ubi-minimal:9.6` |
| scorecard-untar | `images/scorecard-untar/Dockerfile` | `ubi9/ubi:9.5` |
| go-e2e (CI) | `ci/dockerfiles/go-e2e.Dockerfile` | `ubi9/ubi-minimal:latest` |
| scorecard-proxy (CI) | `ci/dockerfiles/scorecard-proxy.Dockerfile` | `ubi9/ubi-minimal:latest` |

## Expected Outcome

- All existing CI jobs pass on RHCOS10 nodes with UBI9 base images unchanged
- No runtime incompatibilities between UBI9 containers and the RHCOS10 host

## Follow-up

If this PR passes, PR2 (`rhcos10-ubi10-migration`) migrates all base images to UBI10,
which is the native base for RHCOS10.
