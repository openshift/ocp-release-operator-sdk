FROM registry.access.redhat.com/ubi8/ubi

RUN yum install -y \
      libffi-devel \
      openssl-devel \
      python3 \
      python3-devel \
      gcc \
      python3-pip \
      python3-setuptools \
 && pip3 install \
      pyasn1==0.4.7 \
      pyasn1-modules==0.2.6 \
      idna==2.8 \
      ipaddress==1.0.22 \
      molecule==3.0.2 \
      ansible-lint \
      yamllint \
      docker \
      openshift \
      jmespath \
      ansible \
 && ansible-galaxy collection install community.kubernetes

COPY . /src

WORKDIR /src
