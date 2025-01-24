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
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"sigs.k8s.io/kubebuilder/v4/pkg/machinery"

	"github.com/spf13/afero"
)

var _ = Describe("RunInit", func() {

	Describe("replaceImages", func() {
		var (
			fs machinery.Filesystem

			dockerfilePath = "Dockerfile"
		)

		BeforeEach(func() {
			fs = machinery.Filesystem{FS: afero.NewMemMapFs()}
		})

		It("substitutes all images correctly", func() {
			Expect(afero.WriteFile(fs.FS, dockerfilePath, []byte(dockerfileAll), 0644)).To(Succeed())
			Expect(replaceImages(fs)).To(Succeed())
			dockerfileOut, err := afero.ReadFile(fs.FS, dockerfilePath)
			Expect(err).NotTo(HaveOccurred())
			Expect(string(dockerfileOut)).To(ContainSubstring(dockerfileAllExp), "Dockerfile match")
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

FROM registry.access.redhat.com/ubi9/ubi-minimal:` + ubiMinimalVersion + `
FROM registry.access.redhat.com/ubi9/ubi-minimal:` + ubiMinimalVersion + `
FROM distroless/static:latest
`
