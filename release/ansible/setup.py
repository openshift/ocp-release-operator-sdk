#!/usr/bin/env python
# -*- coding: utf-8 -*-

import setuptools

requirements = [
    'kubernetes==25.3.0',
    'oauthlib==2.1.0',
    'requests-oauthlib==1.0.0',
    'jmespath==0.9.0',
]

dependency_links = [
]

test_requirements = [
    # TODO: put package test requirements here
]

setuptools.setup(
    name='ose-ansible-operator',
    version='4.14',
    description=("Ansible Operator base image"),
    url='https://github.com/openshift/ocp-release-operator-sdk',
    install_requires=requirements
)
