#!/usr/bin/env bash

#
# This script is used by the ansible-e2e.Dockerfile to create an operator
# image using the upstream sample operator.
#
source hack/lib/common.sh

set -eux

ROOTDIR="$(pwd)"

mkdir -p /ansible
cp -r $ROOTDIR/testdata/ansible/memcached-operator/ /ansible/
cp -r $ROOTDIR/ci/tests/scaffolding/service-account-token.yaml /ansible/