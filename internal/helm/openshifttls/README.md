# `openshifttls`: OpenShift centralized TLS security profile support

This package ([`tls.go`](tls.go)) implements a `run.ClusterTLSPolicy` that lets
the helm-operator manager honor OpenShift's centralized TLS security profile
(configured cluster-wide via the `apiservers.config.openshift.io/cluster`
object) for its metrics server. On startup it reads the cluster's configured
profile (e.g. `Old`, `Intermediate`, `Modern`, or `Custom`) and applies the
corresponding minimum TLS version and cipher suites to the metrics server's
TLS configuration. It then watches that object for changes and triggers a
graceful restart so a new profile takes effect.

This package is downstream-only (never proposed upstream) -- see the package
doc in [`tls.go`](tls.go).

## This document: what operator authors must do

**This RBAC permission is never scaffolded automatically, by any version of
this SDK.** There is no `operator-sdk init`/`create api` flow, past or
present, that adds it to a generated project's RBAC manifests. If you want
your Helm-based operator to honor the cluster's centralized TLS security
profile, you must add the permission below to your operator's own RBAC
manifests yourself.

This also means: if you already have an operator built on an earlier version
of this SDK and you simply rebuild it on a new base image to pick up this
feature, it will **not** gain this permission just from the rebuild -- RBAC
is a separate, declarative Kubernetes manifest, and the manager binary has no
way to grant itself new permissions at runtime. See
["What happens if the rule is missing"](#what-happens-if-the-rule-is-missing)
below for why this is safe to leave unaddressed temporarily, and
["Verifying it worked"](#verifying-it-worked) for how to confirm the fix once
applied.

## The rule to add

Add this rule to the `ClusterRole` bound to your operator's manager
ServiceAccount (typically `config/rbac/role.yaml` in a kustomize-based
project, named `manager-role` before any `namePrefix` transformation):

```yaml
- apiGroups:
  - config.openshift.io
  resources:
  - apiservers
  verbs:
  - get
  - list
  - watch
```

### If your operator is packaged with OLM

Also add the equivalent entry to your CSV's `spec.install.spec.clusterPermissions`
for the same ServiceAccount, for example:

```yaml
clusterPermissions:
- serviceAccountName: <your-manager-service-account>
  rules:
  - apiGroups:
    - config.openshift.io
    resources:
    - apiservers
    verbs:
    - get
    - list
    - watch
```

Note that OLM only reconciles RBAC as part of installing or upgrading a CSV.
Adding this to your CSV source has no effect on an already-running cluster
until you publish a new CSV version and it gets installed/upgraded there --
OLM does not retroactively grant new permissions to an existing installation.

## Why this permission is needed

`Apply()` (see [`tls.go`](tls.go)) fetches the live `APIServer` object to
read the configured profile:

```go
// from Apply() in tls.go:
profile, err := tlspkg.FetchAPIServerTLSProfile(ctx, k8sClient)
if err != nil {
	p.profileSourceAvailable = false
	profile, err = tlspkg.GetTLSProfileSpec(nil)
	if err != nil {
		return options, fmt.Errorf("failed to get default TLS profile: %w", err)
	}
	log.Error(err, "Unable to fetch TLS profile from APIServer (not running on OpenShift, or APIServer/cluster object missing?); falling back to default TLS profile")
} else {
	p.profileSourceAvailable = true
}
```

Without the RBAC rule above, that `Get` call returns a `403 Forbidden`, which
is handled by the same code path as "the object doesn't exist" (e.g. running
on non-OpenShift Kubernetes): the manager falls back to the Go runtime's
default TLS settings for the metrics server instead of the cluster's
configured profile.

## What happens if the rule is missing

The manager fails open, safely:

- It does **not** crash or fail to start.
- It logs an error (`"Unable to fetch TLS profile from APIServer ..."`) and
  falls back to Go's default TLS settings for the metrics server.
- `profileSourceAvailable` is left `false`, so `WatchIfProfileAvailable`
  skips setting up the profile-change watcher entirely (no point watching an
  object it can't read):

  ```go
  // from WatchIfProfileAvailable() in tls.go:
  if !p.profileSourceAvailable {
  	log.Info("Cluster TLS security profile was not read from a live APIServer object at startup; " +
  		"skipping profile-change watch to avoid stalling on a missing config.openshift.io/apiservers resource")
  	return nil
  }
  ```

The practical impact of leaving this unaddressed is that your operator will
not honor cluster-mandated TLS policy (e.g. a stricter minimum TLS version)
on its metrics server -- it keeps working, just without that compliance
guarantee.

## Verifying it worked

Check the manager's logs for one of these two outcomes:

- **Compliant** (RBAC present, live profile applied):
  `"Applied cluster TLS security profile to metrics server"`
- **Fail-open** (RBAC missing, or not running on OpenShift):
  `"falling back to default TLS profile"`

The repo's e2e tests exercise both states for reference:

- [`ci/tests/e2e-helm.sh`](../../../ci/tests/e2e-helm.sh) deploys the test
  fixture operator as-is (no RBAC for this resource), exercising the
  fail-open path.
- [`ci/tests/e2e-helm-with-openshift-tls-rbac.sh`](../../../ci/tests/e2e-helm-with-openshift-tls-rbac.sh)
  additively patches the rule above onto the same manifests at deploy time,
  exercising the compliant path.
