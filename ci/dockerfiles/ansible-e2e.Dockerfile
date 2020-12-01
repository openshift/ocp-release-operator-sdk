FROM osdk-builder as builder

# RUN ci/tests/scaffolding/e2e-ansible-scaffold.sh

# osdk-ansible is built from the release/ansible/upstream.Dockerfile
FROM osdk-ansible

COPY --from=builder /go/src/github.com/operator-framework/operator-sdk/testdata/ansible/memcached-operator/watches.yaml ${HOME}/watches.yaml
COPY --from=builder /go/src/github.com/operator-framework/operator-sdk/testdata/ansible/memcached-operator/roles/ ${HOME}/roles/
