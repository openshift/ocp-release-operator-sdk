# Enhancements & Design Proposals

## Upstream SDK Proposals

Design proposals are maintained in the [`proposals/`](../proposals/) directory. These are upstream design documents from `operator-framework/operator-sdk` — use the [template](../proposals/TEMPLATE.md) for new proposals.

| Proposal | Status | Description |
|----------|--------|-------------|
| [Ansible Operator](../proposals/ansible-operator.md) | Implemented | Ansible-based operator support |
| [Helm Operator](../proposals/helm-operator.md) | Implemented | Helm chart-based operator support |
| [Kubebuilder Integration](../proposals/kubebuilder-integration.md) | Implemented | Integration with kubebuilder scaffolding |
| [Scorecard Plugin System](../proposals/scorecard-plugin-system.md) | Implemented | Extensible scorecard test framework |
| [Scorecard Custom Tests v2](../proposals/scorecard-custom-tests-2.md) | Implemented | Custom scorecard test improvements |
| [SDK-OLM Integration](../proposals/sdk-integration-with-olm.md) | Implemented | OLM workflow integration |
| [CLI UX Phase 1](../proposals/cli-ux-phase1.md) | Implemented | CLI user experience improvements |
| [Ansible Operator Testing](../proposals/ansible-operator-testing.md) | Implemented | Ansible operator test framework |
| [Ansible Operator Status](../proposals/ansible-operator-status.md) | Implemented | Status condition management for Ansible operators |
| [Ansible/Helm Add API](../proposals/ansible-helm-addapi.md) | Implemented | Add API command for Ansible/Helm |
| [Operator Testing Tool](../proposals/operator-testing-tool.md) | Implemented | Operator testing framework |
| [Metering Operator Metrics](../proposals/metering-operator-metrics.md) | Implemented | Metrics collection for operators |
| [Leader for Life](../proposals/leader-for-life.md) | Implemented | Leader election strategy |
| [Hugo Doc Build](../proposals/hugo-doc-build.md) | Implemented | Documentation site build system |
| [Improved Scorecard Config](../proposals/improved-scorecard-config.md) | Implemented | Scorecard configuration improvements |
| [Improve CSV CLI](../proposals/improve-csv-cli.md) | Implemented | CSV generation CLI improvements |
| [Automating Releases](../proposals/automating-releases.md) | Implemented | Release automation |
| [SDK Code Annotations](../proposals/sdk-code-annotations.md) | Implemented | Code annotation markers |
| [TLS Utilities](../proposals/tls-utilities.md) | Implemented | TLS certificate management |
| [Ansible Operator DevEx](../proposals/ansible-operator-devex.md) | Implemented | Ansible developer experience |
| [QA Samples Proposal](../proposals/qa-samples-proposal.md) | Implemented | QA sample projects |
| [Kubernetes 1.17](../proposals/kubernetes-1.17.md) | Implemented | Kubernetes 1.17 support |
| [Tech Debt](../proposals/tech-debt.md) | Implemented | Technical debt reduction |
| [Upstream OSDK Features into CR](../proposals/upstream-osdk-features-into-controller-runtime.md) | Implemented | Upstreaming SDK features |

## Downstream-Specific Enhancements

| Enhancement | Reference | Description |
|-------------|-----------|-------------|
| OAPE-110 | Internal | Removed downstream `operator-sdk` binary packaging |
| OAPE-829 | Internal | Automated upstream rebase periodic (`hack/auto-rebase.sh`) |

## Related OpenShift Enhancements

For OLM and operator framework enhancements that affect this project, see:
- [openshift/enhancements](https://github.com/openshift/enhancements) — `enhancements/olm/`
