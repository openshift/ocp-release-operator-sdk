#!/usr/bin/env bash

set -ex

source hack/lib/test_lib.sh

header_text "Running molecule tests to check advanced Ansible features"

cd /src
component="osdk-ansible-full-e2e"
eval OPERATOR_IMAGE=$IMAGE_FORMAT
export OPERATOR_IMAGE
molecule test -s cluster
