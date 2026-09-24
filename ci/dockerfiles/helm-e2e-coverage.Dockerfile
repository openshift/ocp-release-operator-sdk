FROM osdk-builder as builder

FROM osdk-helm

COPY --from=builder /go/src/github.com/operator-framework/operator-sdk/testdata/helm/memcached-operator/watches.yaml ${HOME}/watches.yaml
COPY --from=builder /go/src/github.com/operator-framework/operator-sdk/testdata/helm/memcached-operator/helm-charts/ ${HOME}/helm-charts/
