#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

set -euo pipefail

args=()
if [ -n "${GIT_TOKEN}" ]; then args+=("-t"  "${GIT_TOKEN}"); fi
if [ -n "${GIT_REPO}" ]; then args+=("-r"  "${GIT_REPO}"); fi
if [ -n "${ANSIBLE_USER}" ]; then args+=("-u"  "${ANSIBLE_USER}"); fi
if [ -n "${OEK_FLAVOR}" ]; then args+=("-f"  "${OEK_FLAVOR}"); fi
if [ -n "${OEK_VARS}" ]; then args+=("-o"  "${OEK_VARS}"); fi
if [ -n "${ANSIBLE_LIMITS}" ]; then args+=("-l"  "${ANSIBLE_LIMITS}"); fi

ip_addresses=$(az vmss list-instance-public-ips  -n "${AZ_VMSS}" -g "${AZ_RESOURCE_GROUP}" --query  [].ipAddress)
hosts=$(echo "${ip_addresses}" | jq -r 'join(",")')
declare -a hosts_array
readarray -d "," -t hosts_array < <(printf '%s' "${hosts}")

for host in "${hosts_array[@]}"
do
    :
    echo "Waiting for ${host}"
    until ssh -o StrictHostKeyChecking=no "${AZ_VM_USERNAME}@${host}" 'echo $(hostname) is up'
    do
        sleep 2
    done
    
    if [ -n "${SSH_IDENTITY}" ]; then
        echo "Copying SSH identity to ${host}"
        echo "${SSH_IDENTITY}" > /tmp/id_ssh.pub
        ssh-copy-id -f -i /tmp/id_ssh.pub "${AZ_VM_USERNAME}@${host}" > /dev/null
    fi

    echo "Configuring ${host}"
    # Allow for root login, required by OEK scripts
    ssh "${AZ_VM_USERNAME}@${host}" sudo cp -r .ssh /root/.ssh
    ssh "${AZ_VM_USERNAME}@${host}" sudo systemctl enable --now firewalld
    ssh "${AZ_VM_USERNAME}@${host}" 'sudo sed  -i "/localhost/s/\$/ $(hostname)/" /etc/hosts'
    ssh "${AZ_VM_USERNAME}@${host}" sudo yum install -y cloud-utils-growpart
    ssh "${AZ_VM_USERNAME}@${host}" sudo growpart /dev/sda 2
    ssh "${AZ_VM_USERNAME}@${host}" sudo partprobe
    ssh "${AZ_VM_USERNAME}@${host}" sudo pvresize /dev/sda2
    ssh "${AZ_VM_USERNAME}@${host}" sudo lvextend -l +50%FREE -r /dev/rootvg/varlv
    ssh "${AZ_VM_USERNAME}@${host}" sudo lvextend -l +100%FREE -r /dev/rootvg/optlv
done

python3 oek_setup.py "${hosts}" "${args[@]}"

