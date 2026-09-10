# API Contracts Guidelines

## OLM API Group Structure

All OLM (Operator Lifecycle Manager) APIs live under the `operators.coreos.com` group with three active versions:

- `v1alpha1`: ClusterServiceVersion, CatalogSource, InstallPlan, Subscription (core lifecycle types)
- `v1alpha2`: OperatorGroup (legacy, superseded by v1)
- `v1`: Operator, OperatorGroup, OperatorCondition, OLMConfig (promoted/stable types)

When a type is promoted (e.g., OperatorGroup from v1alpha2 to v1), the v1 version must carry `+kubebuilder:storageversion`. The older version remains registered for backward compatibility but must not add new fields.

## Required Kubebuilder Markers on Root Types

Every CRD root type in this repo follows a mandatory marker set. Missing any of these breaks generation or kubectl output.

```go
// +k8s:deepcopy-gen:interfaces=k8s.io/apimachinery/pkg/runtime.Object
// +genclient
// +kubebuilder:resource:shortName={short},categories=olm
// +kubebuilder:subresource:status
```

Rules:

- All OLM types use `categories=olm` so `kubectl get olm` works across types.
- Short names are mandatory for user-facing types (csv, sub, catsrc, og, ip, condition).
- Cluster-scoped types add `scope=Cluster` to `+kubebuilder:resource` and `+genclient:nonNamespaced`.
- `+kubebuilder:storageversion` is required on exactly one version when multiple API versions exist for the same Kind.

## Print Columns Convention

The user-facing v1alpha1 OLM types (ClusterServiceVersion, CatalogSource, InstallPlan, Subscription) declare `+kubebuilder:printcolumn` markers. The convention:

- First columns show the most useful spec fields (Display, Package, CSV name).
- Status phase/state is always the last column when present.
- Use `description` on every column.
- Types: `string`, `boolean`, `date`. Use `date` only for `metadata.creationTimestamp`.

## Status Subresource Patterns

Two condition styles coexist in this repo. New code must use the second (standard) pattern.

**Legacy (OLM-specific condition types):** CSV, Subscription, InstallPlan define their own condition structs with custom Phase/State enums and `ConditionReason` string types. These carry both `LastUpdateTime` and `LastTransitionTime` as `*metav1.Time`.

**Standard (metav1.Condition):** OLMConfig, CatalogSource (new fields), OperatorGroup, OperatorCondition, and scaffolded operators use `[]metav1.Condition`. When using this pattern:

- Apply `+patchMergeKey=type`, `+patchStrategy=merge`, `+listType=map`, `+listMapKey=type` on the Conditions field.
- Add `patchStrategy:"merge" patchMergeKey:"type"` struct tags.

Status helper methods `GetCondition`, `SetCondition`, `RemoveConditions` are defined as value/pointer receiver methods on the Status struct -- follow this pattern for new types.

## Phase-Based Status (CSV and InstallPlan)

ClusterServiceVersion and InstallPlan use a `Phase` field (typed string enum) as their primary status signal rather than conditions-only. Rules:

- Define the phase type and all values as named constants with `Phase` prefix (e.g., `CSVPhaseSucceeded`, `InstallPlanPhaseComplete`).
- Include a "None" constant set to empty string `""` for zero-value.
- `ConditionReason` values are CamelCase constants (e.g., `RequirementsNotMet`, `InstallSucceeded`).
- The Status struct mirrors the top-level phase/message/reason AND keeps a Conditions slice as a history.

## JSON Tag and Field Conventions

- Spec and Status are always separate top-level fields on root types: `json:"spec"` and `json:"status"`.
- Status is always `+optional` on the root type.
- Use `json:"metadata"` (not `json:"metadata,omitempty"`) on OLM core types -- the metadata field is never optional.
- `json:",inline"` is used for TypeMeta and ObjectMeta embedding.
- Fields excluded from serialization use `json:"-"` (see `RegistryPoll.Interval`, `RegistryPoll.ParsingError`).
- `json.RawMessage` is used for descriptor Values to allow arbitrary JSON in CSV spec/status/action descriptors.

## Kubebuilder Validation Markers

Validation markers used in this repo:

- `+kubebuilder:validation:Enum=` for typed string fields with a closed set (WebhookAdmissionType, SecurityConfig, UpgradeStrategy).
- `+kubebuilder:validation:Minimum/Maximum` for numeric bounds (ContainerPort 1-65535, scaffolded Size 1-3).
- `+kubebuilder:validation:Pattern` for regex constraints (duration format on `PackageServerSyncInterval`).
- `+kubebuilder:validation:Type=string` when the Go type differs from the JSON schema type (e.g., `metav1.Duration` rendered as string).
- `+kubebuilder:validation:Required` for fields that must be set.
- `+kubebuilder:default=` for server-side defaulting (ContainerPort=443, UpgradeStrategy=Default).

## Operator-SDK CSV Descriptor Markers

The `+operator-sdk:csv:customresourcedefinitions` marker drives CSV generation. Rules:

- On root type: `displayName`, `resources` (e.g., `resources={{Deployment,v1,name}}`).
- On spec fields: `type=spec` plus optional `displayName`, `xDescriptors`.
- On status fields: `type=status` plus optional `displayName`, `xDescriptors`.
- xDescriptors use URN format: `urn:alm:descriptor:io.kubernetes:Secret`, `urn:alm:descriptor:com.tectonic.ui:podCount`, etc.
- Inlined types (`json:",inline"`) have their fields promoted into the parent's descriptors.
- Fields with `json:"-"` are excluded from descriptor generation even if annotated.

## OpenAPI Schema Generation

- OLM API types use `+k8s:openapi-gen=true` on individual structs to include them in OpenAPI schema generation.
- Scaffolded (kubebuilder-style) types use `+kubebuilder:object:generate=true` at the package level and `+kubebuilder:object:root=true` on root types instead.
- Types excluded from OpenAPI use `+k8s:openapi-gen=false`.

## Webhook Contracts

Scaffolded webhook pattern:

- Webhook structs implement `webhook.CustomDefaulter` or `webhook.CustomValidator` interfaces from controller-runtime.
- The `+kubebuilder:webhook` marker on the struct specifies path, mutating/validating, failurePolicy, sideEffects, groups, resources, verbs, versions, admissionReviewVersions.
- Defaulter webhooks set zero-value fields to sensible defaults; they must not error on valid objects.
- Webhook structs carry `+kubebuilder:object:generate=false` to skip DeepCopy generation.
- CSV WebhookDescription declares webhooks for OLM-managed operators with `generateName`, typed `WebhookAdmissionType` enum, and required `sideEffects` and `admissionReviewVersions` fields.

## CSV Upgrade Graph

Three mechanisms control the operator upgrade path:

- `spec.replaces`: names the single CSV this version replaces (forms a linked list).
- `spec.skips`: names CSV versions to skip over during upgrade resolution.
- `metadata.annotations["olm.skipRange"]`: semver range of versions to skip (e.g., `">=1.0.0 <1.2.0"`).

These fields are set in the CSV spec and consumed only during catalog resolution, not at cluster runtime.

## CatalogSource gRPC Contract

CatalogSource supports three source types: `internal` (deprecated), `configmap`, `grpc`.

- For `grpc` type, the `image` field takes precedence over `address` when both are set.
- `GrpcPodConfig` controls pod-level overrides (nodeSelector, tolerations, affinity, securityContextConfig, memoryTarget).
- `securityContextConfig` is validated with `+kubebuilder:validation:Enum=legacy;restricted`.
- Status tracks the gRPC connection via `GRPCConnectionState` (address, lastObservedState, lastConnect).

## Deprecation Conventions

- Deprecated fields: retain the field, add `// DEPRECATED: <replacement>` comment, keep the json tag.
- Deprecated enum values: add `// (deprecated)` in the const comment.
- Subscription tracks three deprecation scopes via conditions: `PackageDeprecated`, `ChannelDeprecated`, `BundleDeprecated`, rolled up into a parent `Deprecated` condition.

## List Type Annotations

- `+listType=set` on slices where order does not matter and duplicates are forbidden.
- `+listType=map` with `+listMapKey=type` on condition slices for server-side apply merge semantics.
- Default (atomic) list type is used for most other slices.

## Bundle Validation Pipeline

The `operator-framework/api/pkg/validation` package provides validators that run against bundle artifacts. When defining new CRDs or modifying CSVs, the bundle must pass:

- `ClusterServiceVersionValidator`: validates CSV structure.
- `CustomResourceDefinitionValidator`: validates CRD definitions.
- `BundleValidator`: validates bundle integrity (CSV + CRDs + metadata).
- `AlphaDeprecatedAPIsValidator`: warns/errors on removed Kubernetes APIs for target k8s versions.
- `GoodPracticesValidator`: enforces conventions.
- `OperatorHubV2Validator`: validates OperatorHub.io listing requirements.
