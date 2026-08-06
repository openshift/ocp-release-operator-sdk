FROM openshift/origin-release:golang-1.13

WORKDIR /go/src/github.com/operator-framework/operator-sdk
ENV GOPATH=/go \
    PATH=/go/src/github.com/operator-framework/operator-sdk/build:$PATH \
    GO111MODULE=on \
    GOFLAGS=-mod=vendor

COPY . .

RUN echo $PATH ; which go ; make -f ci/prow.Makefile patch build
