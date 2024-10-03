// Copyright 2021 The Operator-SDK Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package v1

import (
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"sigs.k8s.io/kubebuilder/v3/pkg/machinery"

	"github.com/spf13/afero"
)

var _ = Describe("RunInit", func() {

	Describe("replaceImages", func() {
		var (
			fs machinery.Filesystem

			dockerfilePath = "Dockerfile"
			proxyPatchPath = "config/default/manager_auth_proxy_patch.yaml"
		)

		BeforeEach(func() {
			fs = machinery.Filesystem{FS: afero.NewMemMapFs()}
		})

		It("substitutes all images correctly", func() {
			Expect(afero.WriteFile(fs.FS, dockerfilePath, []byte(dockerfileAll), 0644)).To(Succeed())
			Expect(afero.WriteFile(fs.FS, proxyPatchPath, []byte(proxyPatch), 0644)).To(Succeed())
			Expect(replaceImages(fs)).To(Succeed())
			dockerfileOut, err := afero.ReadFile(fs.FS, dockerfilePath)
			Expect(err).NotTo(HaveOccurred())
			Expect(string(dockerfileOut)).To(ContainSubstring(dockerfileAllExp), "Dockerfile match")
			proxyPatchOut, err := afero.ReadFile(fs.FS, proxyPatchPath)
			Expect(err).NotTo(HaveOccurred())
			Expect(string(proxyPatchOut)).To(ContainSubstring(proxyPatchExp), "manager_auth_proxy_patch.yaml match")
		})
	})
})

const dockerfileAll = `FROM foo:bar

FROM quay.io/operator-framework/ansible-operator:v1.2.3
FROM quay.io/operator-framework/ansible-operator:v1.2
FROM quay.io/operator-framework/ansible-operator:latest
FROM quay.io/operator-framework/ansible:latest
FROM foo/ansible-operator:latest

FROM quay.io/operator-framework/helm-operator:v1.2.3
FROM quay.io/operator-framework/helm-operator:v1.2
FROM quay.io/operator-framework/helm-operator:latest
FROM quay.io/operator-framework/helm:latest
FROM foo/helm-operator:latest

FROM gcr.io/distroless/static:nonroot
FROM gcr.io/distroless/static:latest
FROM distroless/static:latest

FROM registry.access.redhat.com/ubi8/ubi-micro:8.1
`

const dockerfileAllExp = `FROM foo:bar

FROM registry.redhat.io/openshift4/ose-ansible-rhel9-operator:v` + ocpProductVersion + `
FROM registry.redhat.io/openshift4/ose-ansible-rhel9-operator:v` + ocpProductVersion + `
FROM registry.redhat.io/openshift4/ose-ansible-rhel9-operator:v` + ocpProductVersion + `
FROM quay.io/operator-framework/ansible:latest
FROM foo/ansible-operator:latest

FROM registry.redhat.io/openshift4/ose-helm-rhel9-operator:v` + ocpProductVersion + `
FROM registry.redhat.io/openshift4/ose-helm-rhel9-operator:v` + ocpProductVersion + `
FROM registry.redhat.io/openshift4/ose-helm-rhel9-operator:v` + ocpProductVersion + `
FROM quay.io/operator-framework/helm:latest
FROM foo/helm-operator:latest

FROM registry.access.redhat.com/ubi8/ubi-minimal:` + ubiMinimalVersion + `
FROM registry.access.redhat.com/ubi8/ubi-minimal:` + ubiMinimalVersion + `
FROM distroless/static:latest

FROM registry.access.redhat.com/ubi8/ubi-micro:` + ubiMinimalVersion + `
`

const proxyPatch = `apiVersion: apps/v1
kind: Deployment
metadata:
  name: controller-manager
  namespace: system
spec:
  template:
    spec:
      containers:
      - name: kube-rbac-proxy
        image: gcr.io/kubebuilder/kube-rbac-proxy:v0.5.0
      - name: kube-rbac-proxy-latest
        image: gcr.io/kubebuilder/kube-rbac-proxy:latest
      - name: upstream
        image: quay.io/brancz/kube-rbac-proxy:v0.5.0
`

const proxyPatchExp = `apiVersion: apps/v1
kind: Deployment
metadata:
  name: controller-manager
  namespace: system
spec:
  template:
    spec:
      containers:
      - name: kube-rbac-proxy
        image: registry.redhat.io/openshift4/ose-kube-rbac-proxy:v` + ocpProductVersion + `
      - name: kube-rbac-proxy-latest
        image: registry.redhat.io/openshift4/ose-kube-rbac-proxy:v` + ocpProductVersion + `
      - name: upstream
        image: quay.io/brancz/kube-rbac-proxy:v0.5.0
`
