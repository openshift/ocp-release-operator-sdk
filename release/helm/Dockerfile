FROM registry.ci.openshift.org/ocp/builder:rhel-9-golang-1.23-openshift-4.19 AS builder

ENV GO111MODULE=on \
    GOFLAGS=-mod=vendor

# we need to patch the Makefile prior to building
COPY . /go/src/github.com/operator-framework/operator-sdk
RUN cd /go/src/github.com/operator-framework/operator-sdk \
 && make -f ci/prow.Makefile patch build

FROM registry.ci.openshift.org/ocp/4.19:base-rhel9

ENV HOME=/opt/helm \
    USER_NAME=helm \
    USER_UID=1001

# install operator binary
COPY --from=builder /go/src/github.com/operator-framework/operator-sdk/build/helm-operator /usr/local/bin/helm-operator
COPY release/helm/bin /usr/local/bin

RUN /usr/local/bin/user_setup

WORKDIR ${HOME}
USER ${USER_UID}
ENTRYPOINT ["/usr/local/bin/helm-operator", "run", "--watches-file=./watches.yaml"]
