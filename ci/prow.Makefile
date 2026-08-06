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
	$(MAKE) -f Makefile build/helm-operator

test-e2e-go: patch
	./ci/tests/e2e-go.sh $(ARGS)

test-e2e-helm: patch
	./ci/tests/e2e-helm.sh
	#./hack/tests/e2e-helm.sh

test-subcommand: patch
	./ci/tests/subcommand.sh

.PHONY: patch build test-e2e-go test-e2e-helm patch test-subcommand
