#!/bin/bash

ansible-galaxy collection install --force -r $(dirname "${BASH_SOURCE}")/requirements.yml -p $(dirname "${BASH_SOURCE}")
