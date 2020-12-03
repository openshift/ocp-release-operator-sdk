#!/usr/bin/env bash

source hack/lib/test_lib.sh

set -eux

component="osdk-helm-e2e"
eval IMAGE=$IMAGE_FORMAT
# component="osdk-helm-e2e-hybrid"
# eval IMAGE2=$IMAGE_FORMAT
ROOTDIR="$(pwd)"
GOTMP="$(mktemp -d -p $GOPATH/src)"
trap_add 'rm -rf $GOTMP' EXIT

mkdir -p $ROOTDIR/bin
export PATH=$ROOTDIR/bin:$PATH

if ! [ -x "$(command -v kubectl)" ]; then
    curl -Lo kubectl https://storage.googleapis.com/kubernetes-release/release/v1.15.4/bin/linux/amd64/kubectl && chmod +x kubectl && mv kubectl bin/
fi

if ! [ -x "$(command -v oc)" ]; then
    curl -Lo oc.tar.gz https://github.com/openshift/origin/releases/download/v3.11.0/openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit.tar.gz
    tar xvzOf oc.tar.gz openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit/oc > oc && chmod +x oc && mv oc bin/ && rm oc.tar.gz
fi

oc version

echo $ROOTDIR
make install

# deploy_operator() {
#     echo "ENTERED deploy_operator"
#     kubectl create -f "$OPERATORDIR/deploy/service_account.yaml"
#     if oc api-versions | grep openshift; then
#         oc adm policy add-cluster-role-to-user cluster-admin -z nginx-operator || :
#     fi
#     kubectl create -f "$OPERATORDIR/deploy/role.yaml"
#     kubectl create -f "$OPERATORDIR/deploy/role_binding.yaml"
#     kubectl create -f "$OPERATORDIR/deploy/crds/helm.example.com_nginxes_crd.yaml"
#     kubectl create -f "$OPERATORDIR/deploy/operator.yaml"
#     cat << EOF > "$OPERATORDIR/deploy/network-policy.yaml"
# ---
# apiVersion: networking.k8s.io/v1
# kind: NetworkPolicy
# metadata:
#   name: allow-all
# spec:
#   podSelector: {}
#   ingress:
#   - {}
#   egress:
#   - {}
#   policyTypes:
#   - Ingress
#   - Egress
# EOF
#     kubectl create -f "$OPERATORDIR/deploy/network-policy.yaml"
# }
#
# remove_operator() {
#     echo "ENTERED remove_operator"
#     for cr in $(ls $OPERATORDIR/deploy/crds/*_cr.yaml) ; do
#       kubectl delete --wait=true --ignore-not-found=true -f "${cr}" || true
#     done
#     kubectl delete --wait=true --ignore-not-found=true -f "$OPERATORDIR/deploy/service_account.yaml"
#     kubectl delete --wait=true --ignore-not-found=true -f "$OPERATORDIR/deploy/role.yaml"
#     kubectl delete --wait=true --ignore-not-found=true -f "$OPERATORDIR/deploy/role_binding.yaml"
#     kubectl delete --wait=true --ignore-not-found=true -f "$OPERATORDIR/deploy/crds/helm.example.com_nginxes_crd.yaml"
#     kubectl delete --wait=true --ignore-not-found=true -f "$OPERATORDIR/deploy/network-policy.yaml"
#     kubectl delete --wait=true --ignore-not-found=true -f "$OPERATORDIR/deploy/operator.yaml"
# }

test_operator() {
    local metrics_test_image="registry.access.redhat.com/ubi8/ubi-minimal:latest"

    # wait for operator pod to run
    if ! timeout 1m kubectl rollout status deployment/memcached-operator-controller-manager;
    then
        echo FAIL: for operator pod to run
        kubectl logs deployment/memcached-operator-controller-manager -c manager
        exit 1
    fi

    # verify that metrics service was created
    if ! timeout 60s bash -c -- "until kubectl get service/memcached-operator-controller-manager-metrics-service > /dev/null 2>&1; do sleep 1; done";
    then
        echo "Failed to get metrics service"
        kubectl describe pods
        kubectl logs deployment/memcached-operator-controller-manager -c manager
        exit 1
    fi

    serviceaccount_secret=$(kubectl get serviceaccounts default -o jsonpath='{.secrets[0].name}')
    token=$(kubectl get secret ${serviceaccount_secret} -o jsonpath={.data.token} | base64 -d)

    # verify that the metrics endpoint exists
    if ! timeout 1m bash -c -- "until kubectl run --attach --rm --restart=Never test-metrics --image=registry.access.redhat.com/ubi8/ubi-minimal:latest -- curl -sfkH \"Authorization: Bearer ${token}\" https://memcached-operator-controller-manager-metrics-service:8443/metrics; do sleep 1; done";
    then
        echo "Failed to verify that metrics endpoint exists"
        kubectl describe pods
        kubectl logs deployment/memcached-operator-controller-manager -c manager
        exit 1
    fi

    # create CR
    kubectl apply -f config/samples/cache_v1alpha1_memcached.yaml
    #if ! timeout 1m bash -c -- 'until kubectl get memcachedes.helm.example.com example-memcached -o jsonpath="{..status.deployedRelease.name}" | grep "example-memcached"; do sleep 1; done';
    if ! timeout 60s bash -c -- 'until kubectl get deployment -l app=memcached | grep memcached; do sleep 1; done';
    then
        echo "Failed to create CR"
        kubectl describe pods
        kubectl logs deployment/memcached-operator-controller-manager -c manager
        exit 1
    fi

    # # verify that the custom resource metrics endpoint exists
    # if ! timeout 1m bash -c -- "until kubectl run --attach --rm --restart=Never test-cr-metrics --image=$metrics_test_image -- curl -sfo /dev/null http://memcached-operator-metrics:8686/metrics; do sleep 1; done";
    # then
    #     echo "Failed to verify that custom resource metrics endpoint exists"
    #     kubectl logs deployment/memcached-operator-controller-manager -c manager
    #     exit 1
    # fi

    release_name=$(kubectl get memcachedes.helm.example.com example-memcached -o jsonpath="{..status.deployedRelease.name}")
    memcached_deployment=$(kubectl get deployment -l "app.kubernetes.io/instance=${release_name}" -o jsonpath="{..metadata.name}")

    if ! timeout 1m kubectl rollout status deployment/${memcached_deployment};
    then
        echo FAIL: to rollout status deployment
        kubectl describe pods -l "app.kubernetes.io/instance=${release_name}"
        kubectl describe deployments ${memcached_deployment}
        kubectl logs deployment/memcached-operator-controller-manager -c manager
        exit 1
    fi

    memcached_service=$(kubectl get service -l "app.kubernetes.io/instance=${release_name}" -o jsonpath="{..metadata.name}")
    kubectl get service ${memcached_service}

    # scale deployment replicas to 2 and verify the
    # deployment automatically scales back down to 1.
    kubectl scale deployment/${memcached_deployment} --replicas=2
    if ! timeout 1m bash -c -- "until test \$(kubectl get deployment/${memcached_deployment} -o jsonpath='{..spec.replicas}') -eq 1; do sleep 1; done";
    then
        echo FAIL: to scale deployment replicas to 2 and verify the
        kubectl describe pods -l "app.kubernetes.io/instance=${release_name}"
        kubectl describe deployments ${memcached_deployment}
        kubectl logs deployment/memcached-operator-controller-manager -c manager
        exit 1
    fi

    # update CR to replicaCount=2 and verify the deployment
    # automatically scales up to 2 replicas.
    kubectl patch memcachedes.helm.example.com example-memcached -p '[{"op":"replace","path":"/spec/replicaCount","value":2}]' --type=json
    if ! timeout 1m bash -c -- "until test \$(kubectl get deployment/${memcached_deployment} -o jsonpath='{..spec.replicas}') -eq 2; do sleep 1; done";
    then
        echo FAIL: to update CR to replicaCount=2 and verify the deployment
        kubectl describe pods -l "app.kubernetes.io/instance=${release_name}"
        kubectl describe deployments ${memcached_deployment}
        kubectl logs deployment/memcached-operator-controller-manager -c manager
        exit 1
    fi

    # kubectl delete -f deploy/crds/helm.example.com_v1alpha1_memcached_cr.yaml --wait=true
    kubectl delete -f config/samples/cache_v1alpha1_memcached.yaml --wait=true
    kubectl logs deployment/memcached-operator-controller-manager -c manager | grep "Uninstalled release" | grep "${release_name}"
}

# switch to the "default" namespace
oc project default

# # create and build the operator
# pushd "$GOTMP"
# operator-sdk new nginx-operator --api-version=helm.example.com/v1alpha1 --kind=Nginx --type=helm
#
# pushd nginx-operator
# cp deploy/operator.yaml deploy/operator-copy.yaml
# sed -i "s|REPLACE_IMAGE|$IMAGE|g" deploy/operator.yaml

OPERATORDIR="$(pwd)"

# use sample in testdata
pushd $ROOTDIR/testdata/helm/memcached-operator
ls

# trap_add 'remove_operator' EXIT

# deploy_operator
echo "running make kustomize"
make kustomize
if [ -f ./bin/kustomize ] ; then
  KUSTOMIZE="$(realpath ./bin/kustomize)"
else
  KUSTOMIZE="$(which kustomize)"
fi
pushd config/default
${KUSTOMIZE} edit set namespace default
popd

echo "running make deploy"
make deploy IMG=$IMAGE

echo "running test_operator"
test_operator

# remove_operator
echo "running make undeploy"
trap_add 'make undeploy' EXIT

# the memcached-operator pods remain after the deployment is gone; wait until the pods are removed
if ! timeout 60s bash -c -- "until kubectl get pods -l control-plane=controller-manager |& grep \"No resources found\"; do sleep 2; done";
then
    echo FAIL: memcached-operator Deployment did not get garbage collected
    kubectl describe pods -l "app.kubernetes.io/instance=${release_name}"
    kubectl describe deployments ${memcached_deployment}
    kubectl logs deployment/memcached-operator-controller-manager -c manager
    exit 1
fi

# cp deploy/operator-copy.yaml deploy/operator.yaml
# sed -i "s|REPLACE_IMAGE|$IMAGE2|g" deploy/operator.yaml
# deploy_operator
# test_operator
# remove_operator
#
# popd
popd
