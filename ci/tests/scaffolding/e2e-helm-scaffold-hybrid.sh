#!/usr/bin/env bash

source hack/lib/test_lib.sh

set -eux

ROOTDIR="$(pwd)"
HELMDIR="/go/src/github.com/helm-op"

mkdir -p $HELMDIR
cd $HELMDIR

# create and build the operator
pushd "$HELMDIR"
operator-sdk new nginx-operator --api-version=helm.example.com/v1alpha1 --kind=Nginx --type=helm

pushd nginx-operator
operator-sdk migrate

if [[ ! -e build/Dockerfile.sdkold ]];
then
    echo FAIL the old Dockerfile should have been renamed to Dockerfile.sdkold
    exit 1
fi

# Fixup the operator-sdk dependency in go.mod
sed -i -E '/github.com\/operator-framework\/operator-sdk .+/d' go.mod
add_go_mod_replace "github.com/operator-framework/operator-sdk" "$ROOTDIR"
go mod edit -require "github.com/operator-framework/operator-sdk@v0.0.0"
go mod vendor

# Build the project to resolve dependency versions in the modfile.
go build ./...

WD="$(dirname "$(pwd)")"
go build -gcflags "all=-trimpath=${WD}" -asmflags "all=-trimpath=${WD}" -o /nginx-operator github.com/helm-op/nginx-operator/cmd/manager
popd
popd
mv $HELMDIR /helm
