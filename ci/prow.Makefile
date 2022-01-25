# Makefile specifically intended for use in prow/api-ci only.

ifeq ($(BUILD_VERBOSE),1)
  Q =
else
  Q = @
endif
TEST_PKGS = $(shell go list ./... | grep -v -E 'github.com/operator-framework/operator-sdk/test/')

export CGO_ENABLED := 0

patch:
	for i in ./patches/*.patch; do patch -p0 < $$i; done

build:
	$(MAKE) -f Makefile build/operator-sdk build/ansible-operator build/helm-operator build-darwin

test-e2e-go: patch
	./ci/tests/e2e-go.sh $(ARGS)

test-e2e-ansible: patch
	./ci/tests/e2e-ansible-scaffolding.sh

#test-e2e-ansible test/e2e/ansible:test-scaffolding-e2e-ansible

#test-scaffolding-e2e-ansible:
	#./ci/tests/e2e-ansible-scaffolding.sh
	#./hack/tests/e2e-ansible.sh

test-e2e-helm: patch
	./ci/tests/e2e-helm.sh
	#./hack/tests/e2e-helm.sh

test-subcommand: patch
	./ci/tests/subcommand.sh

ci-images:
	docker build -f ci/dockerfiles/builder.Dockerfile -t osdk-builder .
	docker build -f release/ansible/upstream.Dockerfile -t osdk-ansible .
	docker build -f test/ansible/build/Dockerfile -t osdk-ansible-full-e2e test/ansible/
	docker build -f ci/dockerfiles/ansible-molecule.Dockerfile -t osdk-ansible-molecule .

.PHONY: patch build test-e2e-go test-e2e-ansible test-e2e-helm patch test-subcommand ci-images
