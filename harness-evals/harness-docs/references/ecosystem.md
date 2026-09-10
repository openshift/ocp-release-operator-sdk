# Ecosystem References

## Platform Patterns

- [openshift/enhancements/ai-docs/](https://github.com/openshift/enhancements/tree/master/ai-docs/) — Operator patterns, testing, security, cross-repo ADRs

## Domain Guidelines

Detailed guidelines for each development area:

- [docs/security-guidelines.md](../../../docs/security-guidelines.md) — RBAC, TLS, container security, webhook security, credential handling
- [docs/performance-guidelines.md](../../../docs/performance-guidelines.md) — Concurrency, caching, watch efficiency, retry/polling, goroutine patterns
- [docs/error-handling-guidelines.md](../../../docs/error-handling-guidelines.md) — Error wrapping, custom types, reconciler errors, CLI errors, validation
- [docs/api-contracts-guidelines.md](../../../docs/api-contracts-guidelines.md) — OLM API groups, kubebuilder markers, JSON tags, status patterns, CSV descriptors
- [docs/testing-guidelines.md](../../../docs/testing-guidelines.md) — Ginkgo/Gomega, test layout, fake clients, table-driven tests, async assertions
- [docs/integration-guidelines.md](../../../docs/integration-guidelines.md) — OLM lifecycle, webhook integration, Helm watches.yaml, plugin system, metrics
- [docs/kubernetes-operator-patterns-guidelines.md](../../../docs/kubernetes-operator-patterns-guidelines.md) — Reconciliation loop, CRD conventions, finalizers, owner refs, manager setup
- [docs/cli-architecture-guidelines.md](../../../docs/cli-architecture-guidelines.md) — Command structure, flag binding, output formatting, plugin system, logging
- [docs/code-generation-guidelines.md](../../../docs/code-generation-guidelines.md) — Template machinery, CSV generation, generated file conventions, scaffold patterns
- [docs/build-release-guidelines.md](../../../docs/build-release-guidelines.md) — Downstream fork workflow, patches, CI/CD, container images, vendor management

## Task-Oriented Patterns

Step-by-step guides for common changes:

- [docs/patterns/upstream-sync.md](../../../docs/patterns/upstream-sync.md) — Merging upstream releases
- [docs/patterns/downstream-patches.md](../../../docs/patterns/downstream-patches.md) — Creating and applying downstream patches
- [docs/patterns/cli-changes.md](../../../docs/patterns/cli-changes.md) — Adding or modifying CLI commands
- [docs/patterns/release-versioning.md](../../../docs/patterns/release-versioning.md) — Release preparation, version strings, changelog
- [docs/patterns/generated-and-ci.md](../../../docs/patterns/generated-and-ci.md) — Modifying generators, linter config, CI workflows

## External Documentation

- [Upstream Operator SDK](https://sdk.operatorframework.io/)
- [Downstream OpenShift Docs](https://docs.openshift.com/)
- [OLM Documentation](https://olm.operatorframework.io/)
