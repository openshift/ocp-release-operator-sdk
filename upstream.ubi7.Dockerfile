FROM openshift/origin-release:golang-1.12 AS builder

ENV GO111MODULE=on

COPY . /go/src/github.com/operator-framework/operator-sdk
RUN cd /go/src/github.com/operator-framework/operator-sdk \
 && rm -rf vendor/github.com/operator-framework/operator-sdk \
 && make build/operator-sdk-dev-x86_64-linux-gnu VERSION=dev

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

# Install python dependencies

RUN yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm \
 && yum install -y python-devel gcc inotify-tools \
 && easy_install pip \
 && pip install -U --no-cache-dir setuptools pip \
 && pip install --no-cache-dir --ignore-installed ipaddress \
      ansible-runner==1.2 \
      ansible-runner-http==1.0.0 \
      openshift==0.8.9 \
      ansible==2.8 \
 && yum remove -y gcc python-devel \
 && yum clean all \
 && rm -rf /var/cache/yum

COPY --from=builder /go/src/github.com/operator-framework/operator-sdk/build/operator-sdk-dev-x86_64-linux-gnu ${OPERATOR}
COPY bin /usr/local/bin
COPY library/k8s_status.py /usr/share/ansible/openshift/

# Ensure directory permissions are properly set
RUN mkdir -p ${HOME}/.ansible/tmp \
 && chown -R ${USER_UID}:0 ${HOME} \
 && chmod -R ug+rwx ${HOME}

ADD https://github.com/krallin/tini/releases/latest/download/tini /tini
RUN chmod +x /tini

ENTRYPOINT ["/tini", "--", "/usr/local/bin/entrypoint"]

USER ${USER_UID}
