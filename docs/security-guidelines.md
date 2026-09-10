# Security Guidelines

## RBAC Conventions

### Role Hierarchy

This repo scaffolds a five-tier RBAC structure under `config/rbac/`. All operator-created RBAC must follow this pattern:

1. **manager-role** (ClusterRole) -- minimum verbs the controller needs on its managed resources. Generated from `+kubebuilder:rbac` markers on the Reconcile method. Never use wildcard (`*`) verbs here.
2. **leader-election-role** (namespace-scoped Role) -- grants access to `configmaps`, `leases`, and `events` for leader election only. Must stay namespace-scoped; never promote to ClusterRole.
3. **metrics-auth-role** (ClusterRole) -- grants `tokenreviews` and `subjectaccessreviews` create so the metrics endpoint can perform authn/authz. Always pair with `metrics-auth-rolebinding`.
4. **metrics-reader** (ClusterRole) -- grants `get` on the `/metrics` nonResourceURL only. Bind this to Prometheus service accounts, not to the operator itself.
5. **CRD access roles** (admin/editor/viewer) -- scaffolded per-CRD for cluster administrators. These are not used by the operator; they exist to help admins delegate permissions to users.

### Naming and Binding Rules

- ServiceAccount name: `controller-manager`, defined in `config/rbac/service_account.yaml` and referenced by `config/manager/manager.yaml`.
- ClusterRoleBindings bind to `subjects[].namespace: system` (kustomize replaces this with the real namespace).
- Leader election uses a RoleBinding (not ClusterRoleBinding) to confine the lock to the operator namespace.
- For the monitoring variant (`testdata/go/v4/monitoring/`), add a `prometheus-role` (namespace Role) and `prometheus-role-binding` granting `get`/`list` on services/endpoints/pods to the `prometheus-k8s` ServiceAccount in the `monitoring` namespace.

### kubebuilder RBAC Markers

Place `+kubebuilder:rbac` markers directly above the `Reconcile` method. Each marker must specify explicit verbs; never use `verbs=*`. Example from the canonical testdata:

```go
// +kubebuilder:rbac:groups=cache.example.com,resources=memcacheds,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=cache.example.com,resources=memcacheds/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=cache.example.com,resources=memcacheds/finalizers,verbs=update
```

### Helm Operator RBAC

The Helm plugin auto-generates `config/rbac/role.yaml` by dry-running the chart and introspecting the rendered manifests. This role uses `VerbAll` (`"*"`) for Helm release secrets. Always review the generated role after scaffolding -- the auto-generated rules are based on default chart values and may be too broad or incomplete.

## TLS and Metrics Security

### HTTP/2 Disabled by Default

HTTP/2 is disabled by default to mitigate CVE-2023-44487 (Rapid Reset) and CVE-2023-39325 (Stream Cancellation). The pattern is:

```go
disableHTTP2 := func(c *tls.Config) {
    c.NextProtos = []string{"http/1.1"}
}
```

This is applied to both the webhook server and the metrics server TLS configs unless `--enable-http2` is explicitly set.

### Secure Metrics Endpoint

- Metrics default to `--metrics-secure=true` (Go operator) or `--metrics-secure=false` (Helm operator -- opt-in).
- When secure, use `filters.WithAuthenticationAndAuthorization` as the `FilterProvider` to protect `/metrics` with TokenReview/SubjectAccessReview.
- The `--metrics-require-rbac` flag (Helm) must be paired with `--metrics-secure`; the CLI validates this and rejects the combination `--metrics-require-rbac=true --metrics-secure=false`.
- Metrics port is `8443` (HTTPS) in `config/default/metrics_service.yaml`.

### Certificate Management

- Use cert-manager `Certificate` and `Issuer` resources under `config/certmanager/`.
- Two separate certificates: `metrics-certs` (secretName `metrics-server-cert`) and `serving-cert` (secretName `webhook-server-cert`).
- DNS names are injected via kustomize replacements from the Service name/namespace.
- The issuer is `selfSigned` -- for production, replace with a proper CA issuer.
- Mount cert secrets as volumes with `readOnly: true`.
- Use `certwatcher.CertWatcher` for hot-reloading certificates at runtime; add the watcher to the manager via `mgr.Add()`.

### Prometheus ServiceMonitor TLS

- The base `monitor.yaml` uses `insecureSkipVerify: true` (development only).
- The `monitor_tls_patch.yaml` patches this to `insecureSkipVerify: false` with proper CA, cert, and key references from the `metrics-server-cert` secret. Enable via `[PROMETHEUS-WITH-CERTS]` in `config/prometheus/kustomization.yaml`.

## Leader Election

- Leader election ID must be a unique DNS-compatible string (e.g., `86f835c3.example.com`).
- The lock resource type is `leases` (via `resourcelock.LeasesResourceLock`).
- `LeaderElectionReleaseOnCancel` is commented out in scaffolded code. Only enable it if the binary exits immediately when the manager stops; otherwise it is unsafe.
- The OPERATOR_NAME env var for leader election ID is deprecated. Use `--leader-election-id` instead.

## Webhook Security

- Webhook manifests set `failurePolicy: Fail` and `sideEffects: None`.
- Only `admissionReviewVersions: [v1]` is used.
- Webhook certificates are mounted at `/tmp/k8s-webhook-server/serving-certs` with `readOnly: true`.
- The cert-manager CA injection annotation `cert-manager.io/inject-ca-from` is set via kustomize replacements in `config/default/kustomization.yaml`.
- Webhooks are gated by the `ENABLE_WEBHOOKS` environment variable (set to `"false"` to disable in dev).

## Network Policies

- `config/network-policy/allow-metrics-traffic.yaml` restricts metrics ingress to namespaces labeled `metrics: enabled` on port 8443.
- `config/network-policy/allow-webhook-traffic.yaml` restricts webhook ingress to namespaces labeled `webhook: enabled` on port 443.
- Network policies are commented out by default in `config/default/kustomization.yaml`. Uncomment for production deployments.

## Container Security Contexts

### Scaffolded Go Operators (Restricted PSS)

Pod-level:

```yaml
securityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
```

Container-level:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

### Registry Pods (run bundle / run bundle-upgrade)

- Default: no security context set (`legacy` mode) to maintain OpenShift compatibility across versions. OpenShift Security Context Constraints (SCC), not upstream Pod Security Admission, apply the `MustRunAsRange` UID strategy automatically via namespace annotations.
- `--security-context-config=restricted` flag adds the full restricted context: `SeccompProfileTypeRuntimeDefault`, `Privileged: false`, `AllowPrivilegeEscalation: false`, `Capabilities.Drop: ["ALL"]`.
- `RunAsUser` and `RunAsNonRoot` are intentionally not hardcoded in registry pods because OpenShift namespaces have allocated UID ranges (`openshift.io/sa.scc.uid-range`) that conflict with static values.

### Scorecard Test Pods

- The `--pod-security` flag adds the restricted PSS context to scorecard test pods including init containers.

### Container Images

- Scaffolded Go operators use `gcr.io/distroless/static:nonroot` with `USER 65532:65532`.
- OpenShift-shipped images (helm-operator, scorecard-test, scorecard-untar, scorecard-storage) use UBI minimal with `USER_UID=1001` and a `/sbin/nologin` shell entry.
- Secret volumes in registry pods use `DefaultMode: 0400` (read-only by owner).

## Credential Handling

- Image pull secrets for `run bundle` use `--pull-secret-name`. The secret must be of type `kubernetes.io/dockerconfigjson` and mounted as a volume with key `.dockerconfigjson`.
- CA certificates for private registries use `--ca-secret-name`. The secret key must be `cert.pem`.
- Both secret volumes are mounted `readOnly: true`.
- The `--skip-tls-verify` and `--use-http` flags exist for development; never use them in production.

## CI Security Checks

- `gosec` is enabled in `.golangci.yml` with exclusions for G110 (decompression bomb), G601 (aliasing), G404 (weak random), G204 (subprocess), and G306 (file permissions).
- `make test-sanity` runs `go vet` and `golangci-lint` (including gosec) on every PR.

## OpenShift-Specific Considerations

- Do not hardcode `RunAsUser` values in pod specs targeting OpenShift. Each namespace has a valid UID range annotation.
- Do not set `RunAsNonRoot: true` on pods using images that do not specify a USER directive in their Dockerfile.
- The `SeccompProfile` field requires OpenShift >= 4.11 / Kubernetes >= 1.19.
- Use `--security-context-config=restricted` for clusters that enforce the restricted Pod Security Standard.
