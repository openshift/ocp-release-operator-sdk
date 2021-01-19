FROM registry.svc.ci.openshift.org/ocp/builder:rhel-8-golang-1.15-openshift-4.7 AS builder

ENV GO111MODULE=on \
    GOFLAGS=-mod=vendor

COPY . /go/src/github.com/operator-framework/operator-sdk
RUN cd /go/src/github.com/operator-framework/operator-sdk \
 && make -f ci/prow.Makefile patch build

FROM registry.svc.ci.openshift.org/ocp/4.7:base

RUN yum install -y \
      golang \
      make \
 && yum clean all \
 && rm -rf /var/cache/yum

ENV USER_UID=1001 \
    USER_NAME=sdk \
    HOME=/opt/sdk

# install operator binary
COPY --from=builder /go/src/github.com/operator-framework/operator-sdk/build/operator-sdk /usr/local/bin/operator-sdk
COPY release/sdk/bin /usr/local/bin
RUN /usr/local/bin/user_setup

WORKDIR ${HOME}
USER ${USER_UID}
ENTRYPOINT ["/usr/local/bin/operator-sdk"]
