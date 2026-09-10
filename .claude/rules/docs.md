---
paths:
  - "docs/**"
  - "website/**"
  - "harness-evals/**"
---
# Documentation Rules

## Website

The `website/` directory is a Git submodule. Initialize it with:

```bash
git submodule update --init --recursive website/
```

or use `make setup` which does this automatically.

## Changelog Fragments

Every user-facing change needs a YAML fragment in `changelog/fragments/`. Valid kinds: `addition`, `change`, `deprecation`, `removal`, `bugfix`.

Validate with: `make test-docs`

## CLI Documentation

CLI docs under `website/content/en/docs/cli/` are auto-generated. After changing any command:

```bash
make generate
```

CI enforces `git diff --exit-code` after generation.

## Pattern Guides

Task-oriented guides live in `docs/patterns/`:

- [upstream-sync.md](../../docs/patterns/upstream-sync.md)
- [downstream-patches.md](../../docs/patterns/downstream-patches.md)
- [cli-changes.md](../../docs/patterns/cli-changes.md)
- [release-versioning.md](../../docs/patterns/release-versioning.md)
- [generated-and-ci.md](../../docs/patterns/generated-and-ci.md)
