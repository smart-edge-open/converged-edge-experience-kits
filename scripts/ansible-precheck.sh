#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2019 Intel Corporation

PYTHON3_MINIMAL_SUPPORTED_VERSION=368

if ! id -u 1>/dev/null; then
  echo "ERROR: Script requires root permissions"
  exit 1
fi

if [ "${0##*/}" = "${BASH_SOURCE[0]##*/}" ]; then
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

if ! command -v python3 1>/dev/null; then
  echo "Python3 not installed..."
  yum updateinfo
  if ! yum -y install python3; then
    echo "ERROR: Could not install python3 package."
    exit 1
  fi
  echo "Python3 successfully instaled"
else
  INSTALL=$(python3 -c "import sys; print( $PYTHON3_MINIMAL_SUPPORTED_VERSION > int('%d%d%d' % sys.version_info[:3]))")
  if [ "$INSTALL" = "True" ]; then
    yum updateinfo
    echo "Installing the latest version of python3 package."
    if ! yum -y install python3; then
      echo "ERROR: Could not install python3 package."
      exit 1
    fi
    echo "Python3 successfully installed."
  fi
fi
