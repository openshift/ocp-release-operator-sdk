#!/bin/bash

set -o nounset
set -o pipefail

# TODO: DELETE THIS FILE ONCE openshift/release is updated.
./check-error-log-msg-format.sh
