FROM openshift/origin-release:golang-1.12 AS builder

ENV GO111MODULE=on \
    GOFLAGS=-mod=vendor

COPY . /go/src/github.com/operator-framework/operator-sdk
RUN cd /go/src/github.com/operator-framework/operator-sdk \
 && make build/operator-sdk-dev-x86_64-linux-gnu VERSION=dev

FROM registry.access.redhat.com/ubi7/ubi

RUN yum install -y \
      ansible \
      ansible-runner \
      ansible-runner-http \
      python-kubernetes \
      python-openshift \
      python-jmespath \
      tini \
      inotify-tools \
 && yum clean all \
 && rm -rf /var/cache/yum

RUN mkdir -p /etc/ansible \
    && echo "localhost ansible_connection=local" > /etc/ansible/hosts \
    && echo '[defaults]' > /etc/ansible/ansible.cfg \
    && echo 'roles_path = /opt/ansible/roles' >> /etc/ansible/ansible.cfg \
    && echo 'library = /usr/share/ansible/openshift' >> /etc/ansible/ansible.cfg

ENV OPERATOR=/usr/local/bin/ansible-operator \
    USER_UID=1001 \
    USER_NAME=ansible-operator\
    HOME=/opt/ansible

COPY --from=builder /go/src/github.com/operator-framework/operator-sdk/build/operator-sdk-dev-x86_64-linux-gnu ${OPERATOR}
COPY bin /usr/local/bin
COPY library/k8s_status.py /usr/share/ansible/openshift/

# Ensure directory permissions are properly set
RUN mkdir -p ${HOME}/.ansible/tmp \
 && chown -R ${USER_UID}:0 ${HOME} \
 && chmod -R ug+rwx ${HOME}

ENTRYPOINT ["/tini", "--", "/usr/local/bin/entrypoint"]

USER ${USER_UID}
