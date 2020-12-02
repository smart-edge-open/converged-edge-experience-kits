#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

set -o nounset
set -o pipefail

host_commands_required() {
  local cmd=${1:-}
  if [[ ! -e "/etc/yum.repos.d/docker.repo" ]];then
sudo_cmd ls > /dev/null
echo "[docker]
baseurl = https://download.docker.com/linux/centos/7/\$basearch/stable
gpgcheck = 1
gpgkey = https://download.docker.com/linux/centos/gpg
name = Docker CE repository" | sudo tee /etc/yum.repos.d/docker.repo
  fi
  if [[ ! -e "/etc/yum.repos.d/ius.repo" ]];then
    sudo_cmd yum install -y https://repo.ius.io/ius-release-el7.rpm || opc::log::error "ERROR:ius-release-el7.rpm"
  fi
  for cmd; do
    echo "--->$cmd"
    which "$cmd" > /dev/null 2>&1 || sudo_cmd yum install -y "${SOURCES_TABLES[${cmd}]}" \
    || opc::log::error "ERROR: Install package ${cmd}"
  done
  if [[ ! -e "/etc/yum.repos.d/CentOS-RT.repo" ]];then
    sudo_cmd wget -e http_proxy="$HTTP_PROXY" -e https_proxy="$HTTP_PROXY" \
      http://linuxsoft.cern.ch/cern/centos/7.8.2003/rt/CentOS-RT.repo -O /etc/yum.repos.d/CentOS-RT.repo
    sudo_cmd wget -e http_proxy="$HTTP_PROXY" -e https_proxy="$HTTP_PROXY" \
      http://linuxsoft.cern.ch/cern/centos/7.8.2003/os/x86_64/RPM-GPG-KEY-cern -O /etc/pki/rpm-gpg/RPM-GPG-KEY-cern
  fi
}

host_pylibs_required() {
  local lib=${1:-}
  for lib;do
    sudo_cmd pip3 list --format=columns | grep -qi "$lib" || \
    sudo_cmd pip3 install "$lib" --proxy "$HTTP_PROXY" || opc::log::error "ERROR: Pip3 install package $lib"
  done
}

restart_dep() {
  local choice
  sudo_cmd usermod -aG docker "$USER"
  echo -n "You need to restart the machine and active the new docker user. Take effect after restart, whether to restart now?(Y/N) ";read choice
  choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
  if [[ "$choice" == "y" ]];then
    sudo_cmd reboot
  else
    exit
  fi
}

# Check token and proxy
if [[ -z "$GITHUB_TOKEN" || -z "$GITHUB_USERNAME" ]];then
  opc::log::error "ERROR: GITHUB_TOKEN and GITHUB_USERNAME should not be NULL.
Open scripts/initrc and configure"
fi

if [[ -z "$HTTP_PROXY" || -z "$GIT_PROXY" ]];then
  opc::log::error "ERROR: HTTP_PROXY and GIT_PROXY should not be NULL.
Open scripts/initrc and configure"
fi

if [[ "$BUILD_BIOSFW" == "enable" && -z "$DIR_OF_BIOSFW_ZIP" ]];then
    opc::log::error "ERROR: DIR_OF_BIOSFW_ZIP should not be NULL.
Open scripts/initrc and configure"
fi

if [[ "$BUILD_FPGA_CONFIG" == "enable" && -z "$DIR_BBDEV_CONFIG" ]];then
  opc::log::error "ERROR:  DIR_BBDEV_CONFIG should not be NULL.
Open scripts/initrc and configure"
fi

if [[ "$BUILD_COLLECTD_FPGA" == "enable" && -z "$DIR_OF_FPGA_ZIP" ]];then
  opc::log::error "ERROR:  DIR_OF_FPGA_ZIP should not be NULL.
Open scripts/initrc and configure"
fi

#if ! id -u 1>/dev/null; then
#  opc::log::error "ERROR: Script requires root permissions"
#fi

for item in "$RPM_DOWNLOAD_PATH" "$CODE_DOWNLOAD_PATH" \
    "$GOMODULE_DOWNLOAD_PATH" "$PIP_DOWNLOAD_PATH" "$YAML_DOWNLOAD_PATH" \
    "$IMAGE_DOWNLOAD_PATH" "$OTHER_DOWNLOAD_PATH" "$CHARTS_DOWNLOAD_PATH"
do
  if [ ! -e "$item" ];then
    opc::dir::create "$item"
    opc::log::status "Create the directory $OPC_DOWNLOAD_PATH successful"
  fi
done

rpm -aq | grep -e "^epel-release" || sudo_cmd yum install -y epel-release ||
  opc::log::error "ERROR:Install epel-release"

# Install necessary commands
host_commands_required "python3" "pip3" "wget" "dockerd" "patch" "pip" "curl-config"
# Python libs
host_pylibs_required "pyyaml"

readonly DOCKER_CONF_DIR=/etc/systemd/system/docker.service.d
readonly DOCKER_PROXY="$DOCKER_CONF_DIR"/http-proxy.conf
# Check proxy for docker daemon
if [ ! -d "$DOCKER_CONF_DIR" ];then
  sudo_cmd mkdir -p $DOCKER_CONF_DIR
fi
if [ ! -e "$DOCKER_PROXY" ];then
sudo_cmd ls > /dev/null
echo "[Service]
Environment=\"HTTP_PROXY=${HTTP_PROXY}\"
Environment=\"HTTPS_PROXY=${HTTP_PROXY}\"
Environment=\"NO_PROXY=localhost,127.0.0.1\"" | sudo tee "${DOCKER_PROXY}"
  # Add user into docker group
  sudo_cmd usermod -aG docker "$USER"
  sudo_cmd systemctl daemon-reload
  sudo_cmd systemctl restart docker || opc::log::error "Error at precheck.sh:$LINENO" "systemctl restart docker"
  sudo_cmd systemctl enable docker
fi
# check $USER authority
docker images > /dev/null 2>&1 || restart_dep
# Check docker daemon
sudo_cmd systemctl is-active docker || sudo_cmd systemctl start docker
