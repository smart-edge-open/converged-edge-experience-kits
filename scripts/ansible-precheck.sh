# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2019 Intel Corporation


if ! id -u 1>/dev/null; then
  echo "ERROR: Script requires root permissions"
  exit 1
fi

if [ ${0##*/} == ${BASH_SOURCE[0]##*/} ]; then
    echo "ERROR: This script cannot be executed directly"
    exit 1
fi


if ! command -v ansible-playbook 1>/dev/null; then
  echo "Ansible not installed..."
  if ! rpm -qa | grep -q ^epel-release; then
    echo "EPEL repository not present in system, adding EPEL repository..."
    if ! yum -y install epel-release; then
      echo "ERROR: Could not add EPEL repository. Check above for possible root cause"
      exit 1
    fi
  fi
  echo "Installing ansible..."
  if ! yum -y install ansible; then
    echo "ERROR: Could not install Ansible package from EPEL repository"
    exit 1
  fi
  echo "Ansible successfully instaled"
fi

if ! python -c 'import netaddr' 2>/dev/null; then
  echo "netaddr not installed. Installing.."
  if ! yum install -y python-netaddr; then
    echo "ERROR: Could not install netaddr"
    exit 1
  fi
  echo "netaddr successfully installed"
fi
