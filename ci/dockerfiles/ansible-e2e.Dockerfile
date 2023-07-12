FROM osdk-builder as builder

# TODO: remove this in favor of something else
RUN ci/tests/scaffolding/e2e-ansible-scaffold.sh

# osdk-ansible is built from the release/ansible/Dockerfile.rhel8
FROM osdk-ansible

COPY --from=builder /ansible/memcached-operator/watches.yaml ${HOME}/watches.yaml
COPY --from=builder /ansible/memcached-operator/roles/ ${HOME}/roles/
COPY --from=builder /ansible/memcached-operator/playbooks/ ${HOME}/playbooks/
