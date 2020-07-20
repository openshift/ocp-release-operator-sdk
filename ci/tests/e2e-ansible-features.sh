#!/usr/bin/env bash

source hack/lib/test_lib.sh

header_text "Running molecule tests to check advanced Ansible features"

cd test/ansible
component="osdk-ansible-full-e2e"
eval OPERATOR_IMAGE=$IMAGE_FORMAT
molecule test -s cluster
