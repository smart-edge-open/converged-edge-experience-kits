#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

set -o nounset
set -o pipefail

# Check token and proxy
if [[ -z "$GITHUB_TOKEN" ]];then
  opc::log::error "ERROR: GITHUB_TOKEN should not be NULL.
Open scripts/initrc and configure"
fi

if [[ "$BUILD_BIOSFW" == "enable" && -z "$DIR_OF_BIOSFW_ZIP" ]];then
    opc::log::error "ERROR: DIR_OF_BIOSFW_ZIP should not be NULL.
Open scripts/initrc and configure"
fi

if [[ "$BUILD_COLLECTD_FPGA" == "enable" && -z "$DIR_OF_FPGA_ZIP" ]];then
  opc::log::error "ERROR:  DIR_OF_FPGA_ZIP should not be NULL.
Open scripts/initrc and configure"
fi

# Install necessary commands
host_commands_required "dockerd" "patch" "curl-config"

readonly DOCKER_CONF_DIR=/etc/systemd/system/docker.service.d
readonly DOCKER_PROXY="$DOCKER_CONF_DIR"/http-proxy.conf
# Check proxy for docker daemon
if [[ -n "$HTTP_PROXY" && ! -d "$DOCKER_CONF_DIR" ]];then
  sudo_cmd mkdir -p $DOCKER_CONF_DIR
fi
if [[ -n "$HTTP_PROXY" && ! -e "$DOCKER_PROXY" ]];then
sudo_cmd ls > /dev/null
echo "[Service]
Environment=\"HTTP_PROXY=${HTTP_PROXY}\"
Environment=\"HTTPS_PROXY=${HTTP_PROXY}\"
Environment=\"NO_PROXY=localhost,127.0.0.1\"" | sudo tee "${DOCKER_PROXY}"
fi

# Add user into docker group
sudo_cmd usermod -aG docker "$USER"
sudo_cmd systemctl daemon-reload
sudo systemctl is-active docker || sudo_cmd systemctl restart docker || opc::log::error "Error at precheck.sh:$LINENO" "systemctl restart docker"
sudo_cmd systemctl enable docker

# check $USER authority
docker images > /dev/null 2>&1 || restart_dep
