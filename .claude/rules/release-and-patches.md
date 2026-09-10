---
paths:
  - "patches/**"
  - "release/**"
  - "changelog/**"
---
# Release and Patches Rules

## Commit Message Prefixes

All downstream-specific commits must use one of:

- `UPSTREAM: <carry>:` — persistent changes that survive upstream rebases
- `UPSTREAM: <drop>:` — temporary commits regenerated on each rebase

Upstream-style commits use: `<subsystem>: <what changed>` (subject max 70 chars).

## Patch System

Downstream patches live in `patches/` and use `diff -up` format. They are applied by `make -f ci/prow.Makefile patch` in downstream CI.

See [docs/patterns/downstream-patches.md](../../docs/patterns/downstream-patches.md) for the full workflow.

## Vendor Updates

After changing `go.mod`:
1. `go mod tidy`
2. `go mod vendor`
3. Commit vendor changes separately with `UPSTREAM: <drop>: Update vendor directory`

## Changelog

User-facing PRs require a fragment in `changelog/fragments/`. See `changelog/fragments/00-template.yaml` for the template.
