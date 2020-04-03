# Makefile specifically intended for use in prow/api-ci only.

export CGO_ENABLED := 0

build:
	$(MAKE) -f Makefile build/operator-sdk

test-e2e-go test/e2e/go:
	./ci/tests/e2e-go.sh $(ARGS)

test-e2e-ansible test/e2e/ansible:
	./ci/tests/e2e-ansible.sh

test-e2e-helm test/e2e/helm:
	./ci/tests/e2e-helm.sh

test-subcommand test/subcommand:
	./ci/tests/subcommand.sh

ci-images:
	docker build -f ci/dockerfiles/builder.Dockerfile -t osdk-builder .
	docker build -f release/ansible/upstream.Dockerfile -t osdk-ansible .
	docker build -f ci/dockerfiles/ansible-e2e-hybrid.Dockerfile -t osdk-ansible-e2e-hybrid .
	docker build -f test/ansible/build/Dockerfile -t osdk-ansible-full-e2e test/ansible/
