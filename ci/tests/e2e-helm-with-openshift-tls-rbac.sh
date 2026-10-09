#!/usr/bin/env bash

# Downstream-only e2e test: to faciliate testing that when operator's ClusterRole DOES
# grant read access to the cluster's centralized TLS security profile
# (config.openshift.io/apiservers -- see internal/helm/openshifttls), the
# operator actually reads the live profile and applies it to its metrics
# server, instead of silently falling back to the default TLS profile.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/e2e-helm.sh"

# The RBAC rule is added via an additive kustomize patch

OVERLAY_DIR="$(mktemp -d -p "$GOTMP")"
DEFAULT_DIR_REL=$(realpath --relative-to="$OVERLAY_DIR" "$ROOTDIR/testdata/helm/memcached-operator/config/default")

cat > "$OVERLAY_DIR/kustomization.yaml" <<EOF
resources:
- $DEFAULT_DIR_REL
patches:
- path: add_openshift_tls_rbac.yaml
  target:
    kind: ClusterRole
    name: memcached-operator-manager-role
EOF

cat > "$OVERLAY_DIR/add_openshift_tls_rbac.yaml" <<'EOF'
# Additively grants read access to the cluster's centralized TLS security
# profile (config.openshift.io/apiservers), simulating an operator author who
# has manually added this rule per the release-notes migration guidance,
# rather than removing/replacing the rest of the manager ClusterRole's rules.
- op: add
  path: /rules/-
  value:
    apiGroups:
    - config.openshift.io
    resources:
    - apiservers
    verbs:
    - get
    - list
    - watch
EOF

pushd "$ROOTDIR/testdata/helm/memcached-operator"

deploy_operator "$OVERLAY_DIR"

# verify the manager actually read the live TLS profile instead of falling
# back to the default one
logs=$(kubectl logs deployment/memcached-operator-controller-manager -c manager)

if ! echo "$logs" | grep -q "Applied cluster TLS security profile to metrics server"; then
    echo "FAIL: expected 'Applied cluster TLS security profile to metrics server' log message not found"
    echo "$logs"
    exit 1
fi

if echo "$logs" | grep -q "falling back to default TLS profile"; then
    echo "FAIL: manager unexpectedly fell back to the default TLS profile despite the apiservers RBAC rule being present"
    echo "$logs"
    exit 1
fi

if [ "${DEPLOY_ONLY:-false}" = "true" ]; then
    echo "DEPLOY_ONLY=true: operator deployed with the apiservers RBAC rule and confirmed reading the live TLS profile; skipping test_operator, cleanup, and undeploy"
    popd
    exit 0
fi

# prove the operator is still fully functional with the rule present
echo "running test_operator"
test_operator

# clean up the clusterrolebinding for metrics
kubectl delete clusterrolebinding memcached-operator-metrics-reader-rolebinding

echo "running make undeploy"
make undeploy

if ! timeout 60s bash -c -- "until kubectl get pods -l control-plane=controller-manager |& grep \"No resources found\"; do sleep 2; done";
then
    echo FAIL: memcached-operator Deployment did not get garbage collected
    kubectl describe pods
    kubectl describe deployments
    kubectl logs deployment/memcached-operator-controller-manager -c manager
    exit 1
fi

popd
