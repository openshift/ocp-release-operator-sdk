#!/usr/bin/env bash
set -eux

mkdir -p /helm
# cd /helm

cp -r $ROOTDIR/testdata/helm/memcached-operator/ /helm/

# # create and build the operator
# operator-sdk new nginx-operator --api-version=helm.example.com/v1alpha1 --kind=Nginx --type=helm
