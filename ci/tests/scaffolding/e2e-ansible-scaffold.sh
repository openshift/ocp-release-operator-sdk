#!/usr/bin/env bash

source hack/lib/test_lib.sh

set -eux

ROOTDIR="$(pwd)"

mkdir -p /ansible
cd /ansible

# create and build the operator
#operator-sdk new memcached-operator --api-version=ansible.example.com/v1alpha1 --kind=Memcached --type=ansible
mkdir memcached-operator
pushd memcached-operator
operator-sdk init --plugins ansible.sdk.operatorframework.io/v1 \
  --domain example.com \
  --group ansible \
  --version v1alpha1 \
  --kind Memcached \
  --generate-playbook \
  --generate-role

# cp "$ROOTDIR/test/ansible-memcached/tasks.yml" memcached-operator/roles/memcached/tasks/main.yml
# cp "$ROOTDIR/test/ansible-memcached/defaults.yml" memcached-operator/roles/memcached/defaults/main.yml
# cp -a "$ROOTDIR/test/ansible-memcached/memfin" memcached-operator/roles/
# cat "$ROOTDIR/test/ansible-memcached/watches-finalizer.yaml" >> memcached-operator/watches.yaml
# # Append Foo kind to watches to test watching multiple Kinds
# cat "$ROOTDIR/test/ansible-memcached/watches-foo-kind.yaml" >> memcached-operator/watches.yaml
cp "$ROOTDIR/test/ansible-memcached/tasks.yml" roles/memcached/tasks/main.yml
cp "$ROOTDIR/test/ansible-memcached/defaults.yml" roles/memcached/defaults/main.yml
cp "$ROOTDIR/test/ansible-memcached/memcached_test.yml"  molecule/default/tasks/memcached_test.yml
cp -a "$ROOTDIR/test/ansible-memcached/memfin" roles/
cp -a "$ROOTDIR/test/ansible-memcached/secret" roles/
marker=$(tail -n1 watches.yaml)
sed -i'.bak' -e '$ d' watches.yaml;rm -f watches.yaml.bak
cat "$ROOTDIR/test/ansible-memcached/watches-finalizer.yaml" >> watches.yaml
header_text "Append v1 kind to watches to test watching already registered GVK"
cat "$ROOTDIR/test/ansible-memcached/watches-v1-kind.yaml" >> watches.yaml
echo $marker >> watches.yaml
sed -i'.bak' -e '/- secrets/a \ \ \ \ \ \ - services' config/rbac/role.yaml; rm -f config/rbac/role.yaml.bak

