# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2019 Intel Corporation

id -u 1>/dev/null
if [[ $? -ne 0 ]]; then
  echo "ERROR: Script requires root permissions"
  exit 1
fi

if [ ${0##*/} == ${BASH_SOURCE[0]##*/} ]; then
    echo "ERROR: This script cannot be executed directly"
    exit 1
fi

command -v ansible-playbook 1>/dev/null
if [[ $? -ne 0 ]]; then
  echo "Ansible not installed..."
  rpm -qa | grep -q ^epel-release
  if [[ $? -ne 0 ]]; then
    echo "EPEL repository not present in system, adding EPEL repository..."
    yum -y install epel-release
    if [[ $? -ne 0 ]]; then
      echo "ERROR: Could not add EPEL repository. Check above for possible root cause"
      exit 1
    fi
  fi
  echo "Installing ansible..."
  yum -y install ansible
  if [[ $? -ne 0 ]]; then
    echo "ERROR: Could not install Ansible package from EPEL repository"
    exit 1
  fi
  echo "Ansible successfully instaled"
fi

command -v pip 1>/dev/null
if [[ $? -ne 0 ]]; then
  yum -y install python-pip
  if [[ $? -ne 0 ]]; then
    echo "ERROR: Could not install pip"
    exit 1
  fi
  echo "pip successfully installed"
fi

pip show netaddr 1>/dev/null
if [[ $? -ne 0 ]]; then
  echo "netaddr not installed. Installing.."
  pip install netaddr
  if [[ $? -ne 0 ]]; then
    echo "ERROR: Could not install netaddr"
    exit 1
  fi
  echo "netaddr successfully installed"
fi
