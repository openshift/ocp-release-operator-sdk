FROM openshift/origin-release:golang-1.11 AS builder
COPY . /go/src/github.com/operator-framework/operator-sdk
RUN cd /go/src/github.com/operator-framework/operator-sdk \
 && make build/operator-sdk-dev-x86_64-linux-gnu VERSION=dev

FROM ansible-runner:1.2.0
RUN yum -y install ansible-runner-http python-kubernetes python-openshift

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
COPY --from=builder /go/src/github.com/operator-framework/operator-sdk/bin /usr/local/bin

RUN /usr/local/bin/user_setup
ENTRYPOINT ["/usr/local/bin/entrypoint"]
USER ${USER_UID}
