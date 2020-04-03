#!/bin/bash
echo $@

for collection in $@ ; do 
  echo $(dirname "${BASH_SOURCE}")/collections
  ansible-galaxy collection install --force ${collection} -p $(dirname "${BASH_SOURCE}")
done
