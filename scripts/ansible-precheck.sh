#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2019 Intel Corporation

set -euxo pipefail

PYTHON3_PKG=python3
PYTHON3_VERSION=3.6.8-18.el7

PYTHON_SH_PKG=python36-sh
PYTHON_SH_VERSION=1.12.14-7.el7

PYTHON_NETADDR_PKG=python-netaddr
PYTHON_NETADDR_VERSION=0.7.5-9.el7

PYTHON_PYYAML_PKG=python36-PyYAML
PYTHON_PYYAML_VERSION=3.13-1.el7

ANSIBLE_PKG=ansible
ANSIBLE_VERSION=2.9.18-1.el7

ensure_installed () {
  if [[ ${2-} ]]
  then
      package_name="$1-$2"
  else
      package_name="$1"
  fi

  if ! sudo rpm -qa | grep -q ^"$package_name"; then
    echo "Instaling $package_name"
    if ! sudo yum -y install "$package_name"; then
      echo "ERROR: Failed to install package $package_name"
      exit 1
    else
      echo "$package_name successfully installed"
    fi
  else
    echo "$package_name already installed"
  fi
}

# Check the value of offline_enable
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TOP_PATH="$SCRIPT_DIR/.."
if grep "offline_enable" "$TOP_PATH"/inventory/default/group_vars/all/*.yml | grep -qE "[T|t]rue"; then
  prepackagePath=""
  if [ -e "${TOP_PATH}/roles/offline_roles/unpack_offline_package/files/prepackages.tar.gz" ]; then
     prepackagePath="${TOP_PATH}/roles/offline_roles/unpack_offline_package/files/prepackages.tar.gz"
  elif [ -e "${TOP_PATH}/../roles/offline_roles/unpack_offline_package/files/prepackages.tar.gz" ]; then
     prepackagePath="${TOP_PATH}/../roles/offline_roles/unpack_offline_package/files/prepackages.tar.gz"
  else
    echo "ERROR: Miss package: roles/offline_roles/unpack_offline_package/files/prepackages.tar.gz!"
    exit 1
  fi
  tmpDir=$(mktemp -d)
  tar xvf "$prepackagePath" -C "$tmpDir"
  sudo yum localinstall -y "$tmpDir"/*
  rm -rf "$tmpDir"
else
  # EPEL repository
  ensure_installed epel-release
fi

# Python 3
ensure_installed $PYTHON3_PKG $PYTHON3_VERSION

# ansible
ensure_installed $ANSIBLE_PKG $ANSIBLE_VERSION

# netaddr
ensure_installed $PYTHON_NETADDR_PKG $PYTHON_NETADDR_VERSION

# pyyaml
ensure_installed $PYTHON_PYYAML_PKG $PYTHON_PYYAML_VERSION

# sh
ensure_installed $PYTHON_SH_PKG $PYTHON_SH_VERSION
