#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2019 Intel Corporation

set -euxo pipefail

PYTHON3_MINIMAL_SUPPORTED_VERSION=368

if ! id -u 1>/dev/null; then
  echo "ERROR: Script requires root permissions"
  exit 1
fi

if [ "${0##*/}" = "${BASH_SOURCE[0]##*/}" ]; then
    echo "ERROR: This script cannot be executed directly"
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

if ! command -v ansible-playbook 1>/dev/null; then
  echo "Ansible not installed..."
  if ! sudo rpm -qa | grep -q ^epel-release; then
    echo "EPEL repository not present in system, adding EPEL repository..."
    if ! sudo yum -y install epel-release; then
      echo "ERROR: Could not add EPEL repository. Check above for possible root cause"
      exit 1
    fi
  fi
  echo "Installing ansible..."
  if ! sudo yum -y install ansible; then
    echo "ERROR: Could not install Ansible package from EPEL repository"
    exit 1
  fi
  echo "Ansible successfully instaled"
fi

if ! python -c 'import netaddr' 2>/dev/null; then
  echo "netaddr not installed. Installing.."
  if ! sudo yum install -y python-netaddr; then
    echo "ERROR: Could not install netaddr"
    exit 1
  fi
  echo "netaddr successfully installed"
fi

if ! command -v python3 1>/dev/null; then
  echo "Python3 not installed..."
  sudo yum updateinfo
  if ! sudo yum -y install python3; then
    echo "ERROR: Could not install python3 package."
    exit 1
  fi
  echo "Python3 successfully instaled"
else
  INSTALL=$(python3 -c "import sys; print( $PYTHON3_MINIMAL_SUPPORTED_VERSION > int('%d%d%d' % sys.version_info[:3]))")
  if [ "$INSTALL" = "True" ]; then
    sudo yum updateinfo
    echo "Installing the latest version of python3 package."
    if ! sudo yum -y install python3; then
      echo "ERROR: Could not install python3 package."
      exit 1
    fi
    echo "Python3 successfully installed."
  fi
fi
