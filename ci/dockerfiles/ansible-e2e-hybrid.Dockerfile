FROM osdk-builder as builder

RUN make image-scaffold-ansible
RUN ci/tests/scaffolding/e2e-ansible-scaffold-hybrid.sh

FROM registry.access.redhat.com/ubi7/ubi

RUN mkdir -p /etc/ansible \
    && echo "localhost ansible_connection=local" > /etc/ansible/hosts \
    && echo '[defaults]' > /etc/ansible/ansible.cfg \
    && echo 'roles_path = /opt/ansible/roles' >> /etc/ansible/ansible.cfg \
    && echo 'library = /usr/share/ansible/openshift' >> /etc/ansible/ansible.cfg

ENV OPERATOR=/usr/local/bin/ansible-operator \
    USER_UID=1001 \
    USER_NAME=ansible-operator\
    HOME=/opt/ansible

RUN (yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm || true) \
 && yum -y update \
 && yum install -y python36-devel gcc inotify-tools python2-pip python-devel \
 && pip install --no-cache-dir --upgrade setuptools pip \
 && pip install --no-cache-dir --ignore-installed ipaddress \
      ansible-runner==1.3.4 \
      ansible-runner-http==1.0.0 \
      openshift==0.8.9 \
      ansible~=2.8 \
 && yum remove -y gcc python-devel \
 && yum clean all \
 && rm -rf /var/cache/yum/*

# install operator binary
COPY --from=builder /memcached-operator ${OPERATOR}
COPY --from=builder /go/src/github.com/operator-framework/operator-sdk/library/k8s_status.py /usr/share/ansible/openshift/
COPY --from=builder /go/src/github.com/operator-framework/operator-sdk/bin/* /usr/local/bin/
COPY --from=builder /ansible/memcached-operator/watches.yaml ${HOME}/watches.yaml
COPY --from=builder /ansible/memcached-operator/roles/ ${HOME}/roles/

RUN /usr/local/bin/user_setup

ADD https://github.com/krallin/tini/releases/latest/download/tini /tini
RUN chmod +x /tini

ENTRYPOINT ["/tini", "--", "/usr/local/bin/entrypoint"]

USER ${USER_UID}
