FROM openshift/origin-release:golang-1.13 AS builder

ENV GO111MODULE=on \
    GOFLAGS=-mod=vendor

COPY . /go/src/github.com/operator-framework/operator-sdk
RUN cd /go/src/github.com/operator-framework/operator-sdk \
 && rm -rf vendor/github.com/operator-framework/operator-sdk \
 && make build/helm-operator VERSION=$(git describe --tags --always)

FROM registry.access.redhat.com/ubi8/ubi-minimal:latest

ENV OPERATOR=/usr/local/bin/helm-operator \
    USER_UID=1001 \
    USER_NAME=helm \
    HOME=/opt/helm

# install operator binary
COPY --from=builder /go/src/github.com/operator-framework/operator-sdk/build/helm-operator ${OPERATOR}
COPY release/helm/bin /usr/local/bin

RUN /usr/local/bin/user_setup

ENTRYPOINT ["/usr/local/bin/entrypoint"]

USER ${USER_UID}
