FROM registry.ci.openshift.org/ocp/builder:rhel-8-golang-1.15-openshift-4.7 AS builder

ENV GO111MODULE=on \
    GOFLAGS=-mod=vendor

COPY . /go/src/github.com/operator-framework/operator-sdk
RUN cd /go/src/github.com/operator-framework/operator-sdk \
 && make build/helm-operator

FROM registry.ci.openshift.org/ocp/4.7:base

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
