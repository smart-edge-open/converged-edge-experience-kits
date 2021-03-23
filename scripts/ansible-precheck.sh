#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2019 Intel Corporation

set -euxo pipefail

PYTHON3_VERSION=python3-3.6.8-18.el7

PYTHON_SH_VERSION=python36-sh-1.12.14-7.el7
PYTHON_NETADDR_VERSION=python-netaddr-0.7.5-9.el7
PYTHON_PYYAML_VERSION=python36-PyYAML-3.13-1.el7
ANSIBLE_VERSION=ansible-2.9.18-1.el7

# Check if script called from main directory
if [ ! -d "oek/roles" ] && [ ! -d "roles" ]
then
  echo "ERROR: Script should be called from main directory!"
  exit 1
fi

# Check the value of offline_enable
TOP_PATH=$(cd "$(dirname "$0")";pwd)
if grep "offline_enable" "$TOP_PATH"/inventory/default/group_vars/all/*.yml | grep -qE "[T|t]rue"; then
  prepackagePath=""
  if [ -e "${TOP_PATH}/roles/offline_roles/unpack_offline_package/files/prepackages.tar.gz" ]; then
     prepackagePath="${TOP_PATH}/roles/offline_roles/unpack_offline_package/files/prepackages.tar.gz"
  elif [ -e "${TOP_PATH}/oek/roles/offline_roles/unpack_offline_package/files/prepackages.tar.gz" ]; then
     prepackagePath="${TOP_PATH}/oek/roles/offline_roles/unpack_offline_package/files/prepackages.tar.gz"
  else
    echo "ERROR: Miss package: [oek/]roles/offline_roles/unpack_offline_package/files/prepackages.tar.gz!"
    exit 1
  fi
  tmpDir=$(mktemp -d)
  tar xvf "$prepackagePath" -C "$tmpDir"
  sudo yum localinstall -y "$tmpDir"/*
  rm -rf "$tmpDir"
fi

# EPEL repository
if ! sudo rpm -qa | grep -q ^epel-release; then
  echo "EPEL repository not present in system, adding EPEL repository..."
  if ! sudo yum -y install epel-release; then
    echo "ERROR: Could not add EPEL repository. Check above for possible root cause"
    exit 1
  fi
fi

# Python 3
if ! command -v python3 1>/dev/null; then
  echo "Python3 not installed..."
  sudo yum updateinfo
  if ! sudo yum -y install $PYTHON3_VERSION; then
    echo "ERROR: Could not install $PYTHON3_VERSION package."
    exit 1
  fi
  echo "Python3 successfully instaled"
else
  INSTALL=$(python3 -c "import sys; print( $PYTHON3_MINIMAL_SUPPORTED_VERSION > int('%d%d%d' % sys.version_info[:3]))")
  if [ "$INSTALL" = "True" ]; then
    sudo yum updateinfo
    echo "Installing the supported version of python3 package."
    if ! sudo yum -y install $PYTHON3_VERSION; then
      echo "ERROR: Could not install $PYTHON3_VERSION package."
      exit 1
    fi
    echo "Python3 successfully installed."
  fi
fi

# ansible
if ! command -v ansible-playbook 1>/dev/null; then
  echo "Installing ansible..."
  if ! sudo yum -y install $ANSIBLE_VERSION; then
    echo "ERROR: Could not install Ansible package from EPEL repository"
    exit 1
  fi
  echo "Ansible successfully instaled"
else
  echo "Ansible already installed"
fi

# netaddr
if ! sudo rpm -qa | grep -q ^$PYTHON_NETADDR_VERSION; then
  echo "netaddr not installed. Installing.."
  if ! sudo yum install -y $PYTHON_NETADDR_VERSION; then
    echo "ERROR: Could not install netaddr"
    exit 1
  fi
  echo "netaddr successfully installed"
else
  echo "netaddr already installed"
fi

# pyyaml
if ! sudo rpm -qa | grep -q ^$PYTHON_PYYAML_VERSION; then
  echo "pyyaml not installed. Installing.."
  if ! sudo yum install -y $PYTHON_PYYAML_VERSION; then
    echo "ERROR: Could not install pyyaml"
    exit 1
  fi
  echo "pyyaml successfully installed"
else
  echo "pyyaml already installed"
fi

# sh
if ! sudo rpm -qa | grep -q ^$PYTHON_SH_VERSION; then
  echo "python36-sh not installed. Installing.."
  if ! sudo yum install -y $PYTHON_SH_VERSION; then
    echo "ERROR: Could not install python36-sh"
    exit 1
  fi
  echo "python36-sh successfully installed"
else
  echo "python36-sh already installed"
fi


# pip upgrade
if command sudo python3 -m pip install -U pip 1>/dev/null; then
  echo "pip upgraded"
else 
  echo "ERROR: Failed to upgrade pip"
fi
