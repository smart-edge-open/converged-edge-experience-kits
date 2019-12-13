#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2019 Intel Corporation

# Keep rpm cache for further use as we need older packages versions for offline host
sed '/^keepcache=/g' -i /etc/yum.conf
echo 'keepcache=1' >> /etc/yum.conf

source scripts/ansible-precheck.sh
source scripts/task_log_file.sh

# Prepare a local rpm cache if missing
ansible_cache_folder='/temp/ansible_base_package_with_deps'
if ! [ -d $ansible_cache_folder ]; then
  echo "Storing Ansible rpm package with deps for further use"
  mkdir -p  $ansible_cache_folder
  find /var/cache/yum -type f -iname "*rpm" -exec cp -v "{}" $ansible_cache_folder/  \;
  (cd $ansible_cache_folder && tar cf /temp/ansible_offline_packages.tar ./*)
fi

# Run the main playbook for creating offline package
ansible-playbook -vv \
    ./offline_prepare.yml \
    --inventory offline_preparation_inventory.ini
