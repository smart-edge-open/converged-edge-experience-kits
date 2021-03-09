#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

progressfilt() {
  local flag=false c count cr=$'\r' nl=$'\n'
  set +e
  while IFS='' read -d '' -rn 1 c
  do
    if $flag;then
      printf '%c' "$c"
    else
      if [[ "$c" != "$cr" && "$c" != "$nl" ]];then
        count=0
      else
        (( count++ ))
        if ((count > 1));then
          flag=true
        fi
      fi
    fi
  done
  set -e
}

# Install required repos
host_repos_required() {
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
  if [[ ! -e "/etc/yum.repos.d/kubernetes.repo" ]];then
sudo_cmd ls > /dev/null
echo "[kubernetes]
baseurl = https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled = 1
gpgcheck = 1
gpgkey = https://packages.cloud.google.com/yum/doc/yum-key.gpg
        https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
name = Kubernetes repository
repo_gpgcheck = 1" | sudo tee /etc/yum.repos.d/kubernetes.repo
  fi
  if [[ ! -e "/etc/yum.repos.d/CentOS-RT.repo" ]];then
    sudo_cmd wget http://linuxsoft.cern.ch/cern/centos/7.9.2009/rt/CentOS-RT.repo -O /etc/yum.repos.d/CentOS-RT.repo \
    || opc::log::error "ERROR: Install CentOS-RT.repo"
    sudo_cmd wget http://linuxsoft.cern.ch/cern/centos/7.9.2009/os/x86_64/RPM-GPG-KEY-cern -O /etc/pki/rpm-gpg/RPM-GPG-KEY-cern \
    || opc::log::error "ERROR: Install CentOS-RT.repo key"
  fi
  sudo_cmd yum makecache fast
}

host_commands_required() {
  local cmd=${1:-}
  for cmd; do
    echo "--->$cmd"
    which "$cmd" > /dev/null 2>&1 || sudo_cmd yum install -y "${SOURCES_TABLES[${cmd}]}" \
    || opc::log::error "ERROR: Install package ${cmd}"
  done
}

host_pylibs_required() {
  local lib=${1:-}
  for lib;do
    sudo_cmd pip3 install "$lib" || opc::log::error "ERROR: pip3 install package $lib"
  done
}

restart_dep() {
  local choice
  sudo_cmd usermod -aG docker "$USER"
  echo -n "You need to restart the machine and active the new docker user. Take effect after restart, whether to restart now?(Y/N) ";read -r choice
  choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
  if [[ "$choice" == "y" ]];then
    sudo_cmd reboot
  else
    exit
  fi
}

# Log an error but keep going.
opc::log::error() {
  local message=${1:-}
  timestamp=$(date +"[%m/%d %H:%M:%S]")
  echo "!!! $timestamp ${1-}" >&2
  shift
  for message; do
    echo "    $message" >&2
  done
  exit 1
}

# Print out some info that isn't a top level status line
opc::log::info() {
  local message=${1:-}
  for message; do
    echo "$message"
  done
}

# Print a status line.  Formatted to show up in a stream of output.
opc::log::status() {
  local message=${1:-}
  timestamp=$(date +"[%m/%d %H:%M:%S]")
  echo "+++ $timestamp $1"
  shift
  for message; do
    echo "    $message"
  done
}

opc::check::exist() {
  local ret

  ret=0
  echo "$1" | grep -q "$2" || ret=1

  echo "$ret"
}

readonly OPC_DOWNLOAD_PATH="$OPC_BASE_DIR/opcdownloads"
readonly RPM_DOWNLOAD_PATH="$OPC_DOWNLOAD_PATH/rpms"
readonly CODE_DOWNLOAD_PATH="$OPC_DOWNLOAD_PATH/github"
readonly GOMODULE_DOWNLOAD_PATH="$OPC_DOWNLOAD_PATH/gomodule"
readonly PIP_DOWNLOAD_PATH="$OPC_DOWNLOAD_PATH/pip_packages"
readonly YAML_DOWNLOAD_PATH="$OPC_DOWNLOAD_PATH/yaml"
readonly IMAGE_DOWNLOAD_PATH="$OPC_DOWNLOAD_PATH/images"
readonly OTHER_DOWNLOAD_PATH="$OPC_DOWNLOAD_PATH/other"
readonly CHARTS_DOWNLOAD_PATH="$OPC_DOWNLOAD_PATH/charts"
export PRERPM_DOWNLOAD_PATH="$OPC_DOWNLOAD_PATH/prerpms"

# Create directory under the path of '../'
opc::dir::create() {
  local dir=${1:-}
  opc::log::status "Create the directory $dir"
  mkdir -p "$dir" || opc::log::error "mkdir $OPC_DOWNLOAD_PATH"
}

# Download the rpms from internet
opc::download::yum() {
  for list in $1
  do
    set +e
    if echo "$list" | grep "\.rpm" ; then
      name=$(echo "$list" | rev | cut -d '/' -f 1 | rev)
      if [[ ! -e "$RPM_DOWNLOAD_PATH"/"$name" ]];then
        wget --progress=bar:force "$list" -P "$RPM_DOWNLOAD_PATH" 2>&1 | progressfilt \
        || opc::log::error "Wget $list"
      fi
    else
      sudo_cmd yum install --disableexcludes=all --enablerepo=ius-archive --skip-broken \
        --downloadonly --downloaddir="$RPM_DOWNLOAD_PATH" "$list"
    fi
    set -e
  done
}

# Download the github code from internet
opc::download::github() {
  local name
  local url
  local flag
  local value
  local ret
  local arr
  local pwd=$PWD

  # make the directory to be clean
  cd "$CODE_DOWNLOAD_PATH" && sudo_cmd rm ./* -rf
  for list in $1
  do
    name=$(echo "$list" | cut -d ',' -f 1)
    url=$(echo "$list" | cut -d ',' -f 2)
    flag=$(echo "$list" | cut -d ',' -f 3)
    value=$(echo "$list" | cut -d ',' -f 4)
    # otcshare git repo need a token
    ret=$(opc::check::exist "$url" "otcshare")
    if [[ "$ret" -eq 0 ]];then
      if [ -z "$GITHUB_TOKEN" ];then
        opc::log::error "Cannot download otcshare code!"
      fi
      # shellcheck disable=SC2206
      arr=( ${url//\/\// } )

      docker run --rm -ti -v "$PWD":/opt/app \
        -w /opt/app golang:1.14.9 bash -c "if [[ -n ${HTTP_PROXY} ]];then \
        if [[ -n $GIT_PROXY ]];then git config --global http.proxy ${GIT_PROXY}; \
        else git config --global http.proxy ${HTTP_PROXY};fi;fi;git clone https://${GITHUB_TOKEN}@${arr[1]}"
    else
      if [[ "$flag" == "tag" ]];then
        docker run --rm -ti \
        -v "$PWD":/opt/app -w /opt/app \
        golang:1.14.9 bash -c "if [[ -n ${HTTP_PROXY} ]];then \
        if [[ -n $GIT_PROXY ]];then git config --global http.proxy ${GIT_PROXY}; \
        else git config --global http.proxy ${HTTP_PROXY};fi;fi;git clone $url && cd $name && git checkout $value"
      else
        docker run --rm -ti -v "$PWD":/opt/app \
        -w /opt/app golang:1.14.9 bash -c "if [[ -n ${HTTP_PROXY} ]];then \
        if [[ -n $GIT_PROXY ]];then git config --global http.proxy ${GIT_PROXY}; \
        else git config --global http.proxy ${HTTP_PROXY};fi;fi;git clone $url && cd $name && git reset --hard $value"
      fi
    fi
  done
  sudo_cmd chown -R "$USER":"$USER" "${CODE_DOWNLOAD_PATH}"
  cd "${pwd}"
}

download::module() {
  docker run -ti --rm    \
    -v "$PWD":/opt/app   \
    -v "$GOMODULE_DOWNLOAD_PATH":/go/pkg \
    -v "$OPC_BASE_DIR"/scripts/download_mod.sh:/root/dmod.sh:ro \
    -w /opt/app         \
    golang:1.15.5 bash -c "if [[ -n ${HTTP_PROXY} ]];then \
      if [[ -n $GIT_PROXY ]];then \
      git config --global http.proxy ${GIT_PROXY}; else \
      git config --global http.proxy ${HTTP_PROXY};fi; \
      fi;if [[ -n ${HTTP_PROXY} ]];then \
      export http_proxy=$HTTP_PROXY;export https_proxy=$HTTP_PROXY;fi;\
      git config --global --add url.\"https://$GITHUB_TOKEN@github.com/\".insteadOf \"https://github.com/\" \
      && go env -w GOPRIVATE=github.com/otcshare && /root/dmod.sh"
}

# Download go modules
opc::download::gomodules() {
  local pwd="$PWD"
  cd "$CODE_DOWNLOAD_PATH"
  for dir in $1
  do
    pushd "$dir"
    download::module
    popd
  done
  cd "$GOMODULE_DOWNLOAD_PATH"
  if [ -e "gomod.tar.gz" ];then
    rm -f gomod.tar.gz
  fi
  sudo_cmd chown -R "$USER":"$USER" "$GOMODULE_DOWNLOAD_PATH"
  tar czvf gomod.tar.gz ./*
  cd "${pwd}"
}

# Download pip3 packages
opc::download::pippackage() {
  local url
  local name

  for list in $1
  do
    url=$(echo "$list" | cut -d ',' -f 2)
    name=$(echo "$url" | rev | cut -d '/' -f 1 | rev)
    if [[ ! -e "$PIP_DOWNLOAD_PATH/$name" ]];then
      wget --progress=bar:force -P "$PIP_DOWNLOAD_PATH" https://files.pythonhosted.org/packages/"$url" 2>&1 | progressfilt \
      || opc::log::error "Wget https://files.pythonhosted.org/packages/$url"
    fi
  done
}

# Download yaml files
opc::download::yamls() {
  local url
  local name

  for list in $1
  do
    url=$(echo "$list" | cut -d ',' -f 2)
    name=$(echo "$url" | rev | cut -d '/' -f 1 | rev)
    if [ ! -e "$YAML_DOWNLOAD_PATH"/"$name" ];then
      wget --progress=bar:force -P "${YAML_DOWNLOAD_PATH}" "$url" 2>&1 | progressfilt \
      || opc::log::error "Wget $url"
    fi
  done
  # special for kubevirt
  cp -f "${OPC_BASE_DIR}"/file/virt_yaml/kubevirt-operator.yaml.bak "${YAML_DOWNLOAD_PATH}"/kubevirt-operator.yaml
}

# Download docker image
opc::download::images() {
  local name
  local image

  for list in $1
  do
    name=$(echo "$list" | cut -d ',' -f 1)
    image=$(echo "$list" | cut -d ',' -f 2)
    docker pull "$image" || exit
    docker save "$image" > "$IMAGE_DOWNLOAD_PATH"/"$name".tar.gz
  done
  # special for kubevirt images
  if [ -e "$IMAGE_DOWNLOAD_PATH"/virt-operator.tar.gz ];then
    docker tag 3c8ecae5a47b kubevirt/virt-operator:3c8ecae5a47b
    docker save kubevirt/virt-operator:3c8ecae5a47b > "$IMAGE_DOWNLOAD_PATH"/virt-operator.tar.gz
  fi
  if [ -e "$IMAGE_DOWNLOAD_PATH"/virt-api.tar.gz ];then
    docker tag cc8748b28f49 kubevirt/virt-api:3c8ecae5a47b
    docker save kubevirt/virt-api:3c8ecae5a47b > "$IMAGE_DOWNLOAD_PATH"/virt-api.tar.gz
  fi
  if [ -e "$IMAGE_DOWNLOAD_PATH"/virt-controller.tar.gz ];then
    docker tag 4d4ed62406a2 kubevirt/virt-controller:3c8ecae5a47b
    docker save kubevirt/virt-controller:3c8ecae5a47b > "$IMAGE_DOWNLOAD_PATH"/virt-controller.tar.gz
  fi
  if [ -e "$IMAGE_DOWNLOAD_PATH"/virt-handler.tar.gz ];then
    docker tag 26097c0b9d66 kubevirt/virt-handler:3c8ecae5a47b
    docker save kubevirt/virt-handler:3c8ecae5a47b > "$IMAGE_DOWNLOAD_PATH"/virt-handler.tar.gz
  fi
  if [ -e "$IMAGE_DOWNLOAD_PATH"/virt-launcher.tar.gz ];then
    docker tag c6672d186608 kubevirt/virt-launcher:3c8ecae5a47b
    docker save kubevirt/virt-launcher:3c8ecae5a47b > "$IMAGE_DOWNLOAD_PATH"/virt-launcher.tar.gz
  fi
}

build::cli() {
  cd "$CODE_DOWNLOAD_PATH"/edgeservices/edgecontroller
  docker run --rm -ti \
    -v "$GOMODULE_DOWNLOAD_PATH":/go/pkg \
    -v "$PWD":/opt/app \
    -w /opt/app golang:1.14.9 \
    go build -o dist/edgednscli ./cmd/edgednscli
}

build::common_services() {
  cd "$CODE_DOWNLOAD_PATH"/edgeservices
  docker run --rm -ti \
    -v "$GOMODULE_DOWNLOAD_PATH":/go/pkg \
    -v "$PWD":/opt/app \
    -w /opt/app golang:1.14.9 \
    bash -c "ln -sf /bin/cp /usr/bin/cp \
    && make common-services SKIP_DOCKER_IMAGES=1"
    if [[ -n "$HTTP_PROXY" ]];then
      docker build --build-arg http_proxy="${HTTP_PROXY}" -t eaa:1.0 dist/eaa
      docker build --build-arg http_proxy="${HTTP_PROXY}" -t edgednssvr:1.0 dist/edgednssvr
      docker build --build-arg http_proxy="${HTTP_PROXY}" -t certsigner:1.0 dist/certsigner
      docker build --build-arg http_proxy="${HTTP_PROXY}" -t certrequester:1.0 dist/certrequester
    else
      docker build -t eaa:1.0 dist/eaa
      docker build -t edgednssvr:1.0 dist/edgednssvr
      docker build -t certsigner:1.0 dist/certsigner
      docker build -t certrequester:1.0 dist/certrequester
    fi
    docker save eaa:1.0 > "$IMAGE_DOWNLOAD_PATH"/eaa.tar.gz
    docker save edgednssvr:1.0 > "$IMAGE_DOWNLOAD_PATH"/edgednssvr.tar.gz
    docker save certsigner:1.0 > "$IMAGE_DOWNLOAD_PATH"/certsigner.tar.gz
    docker save certrequester:1.0 > "$IMAGE_DOWNLOAD_PATH"/certrequester.tar.gz
}

build::interfaceservice() {
  cd "$CODE_DOWNLOAD_PATH"/edgeservices
  docker run --rm -ti \
    -v "$GOMODULE_DOWNLOAD_PATH":/go/pkg \
    -v "$PWD":/opt/app \
    -w /opt/app golang:1.14.9 \
    bash -c "ln -sf /bin/cp /usr/bin/cp \
    && make interfaceservice SKIP_DOCKER_IMAGES=1"
    if [[ -n "$HTTP_PROXY" ]];then
      docker build --build-arg http_proxy="${HTTP_PROXY}" \
      --build-arg https_proxy="${HTTP_PROXY}" -t interfaceservice:1.0 dist/interfaceservice
    else
      docker build -t interfaceservice:1.0 dist/interfaceservice
    fi
    docker save interfaceservice:1.0 > "$IMAGE_DOWNLOAD_PATH"/interfaceservice.tar.gz
}

build::fpga-opae-pacn3000() {
  local kernel_version
  local target_kernel_version

  kernel_version=$(uname -r)
  target_kernel_version=$(grep "^kernel_version" "$OPC_BASE_DIR"/../group_vars/* -rsh | sort -u | cut -d ':' -f 2 | sed s/[[:space:]]//g)
  if [[ "$BUILD_OPAE" == "enable" ]];then
    if [[ "$kernel_version" != "$target_kernel_version" ]];then
      echo -n "Update the kernel to $target_kernel_version, do you agree?(Y/N) ";read -r update_kernel
      update_kernel=$(echo "${update_kernel}" | tr '[:upper:]' '[:lower:]')
      if [[ "$update_kernel" == "y" ]];then
        opc::update_kernel
      fi
    else
      cd "$CODE_DOWNLOAD_PATH"/edgeservices
      sudo_cmd chown -R "$USER":"$USER" ./*
      cp "$DIR_OF_OPAE_ZIP"/*.zip build/fpga_opae
      if [[ -n "$HTTP_PROXY" ]];then
        docker build --build-arg http_proxy="${HTTP_PROXY}" --build-arg https_proxy="${HTTP_PROXY}" \
          -t fpga-opae-pacn3000:1.0 -f ./build/fpga_opae/Dockerfile ./build/fpga_opae
      else
        docker build -t fpga-opae-pacn3000:1.0 -f ./build/fpga_opae/Dockerfile ./build/fpga_opae
      fi
      docker save fpga-opae-pacn3000:1.0 > "$IMAGE_DOWNLOAD_PATH"/fpga-opae-pacn3000.tar.gz
      rm ./build/fpga_opae/*.zip
    fi
  fi
}

build::sriov_network() {
  cd "${CODE_DOWNLOAD_PATH}"/sriov-network-device-plugin
  sed -i 's/FROM golang:alpine as builder/FROM golang:alpine3.10 as builder/g' images/Dockerfile
  make image || opc::log::error "make image sriov_network_device_plugin"
  docker save nfvpe/sriov-device-plugin:latest > "$IMAGE_DOWNLOAD_PATH"/sriov-device-plugin.tar.gz
}

build::sriov_cni() {
  cd "$CODE_DOWNLOAD_PATH"/sriov-cni
  sed -i 's/FROM golang:alpine as builder/FROM golang:alpine3.10 as builder/g' Dockerfile
  make image || opc::log::error "make image sriov_cni"
  docker save nfvpe/sriov-cni:latest > "$IMAGE_DOWNLOAD_PATH"/sriov_cni.tar.gz
}

build::biosfw() {
  if [[ "${BUILD_BIOSFW}" == "enable" ]];then
    cd "$CODE_DOWNLOAD_PATH"/edgeservices
    sudo_cmd chown -R "${USER}":"${USER}" ./*
    cp "$DIR_OF_BIOSFW_ZIP"/syscfg_package.zip dist/biosfw
    if [[ -n "$HTTP_PROXY" ]];then
      docker build --build-arg http_proxy="${HTTP_PROXY}" -t openness-biosfw dist/biosfw
    else
      docker build -t openness-biosfw dist/biosfw
    fi
    docker save openness-biosfw:latest > "${IMAGE_DOWNLOAD_PATH}"/biosfw.tar.gz
    rm dist/biosfw/syscfg_package.zip -f
  fi
}

build::bb_config() {
  if [[ -n "$HTTP_PROXY" ]];then
    if [[ -n "$GIT_PROXY" ]];then
      docker build --build-arg http_proxy="${GIT_PROXY}" --build-arg https_proxy="${GIT_PROXY}" \
        -t bb-config-utility:0.1.0  "${OPC_BASE_DIR}"/../roles/kubernetes/bb_config/files
    else
      docker build --build-arg http_proxy="${HTTP_PROXY}" --build-arg https_proxy="${HTTP_PROXY}" \
        -t bb-config-utility:0.1.0  "${OPC_BASE_DIR}"/../roles/kubernetes/bb_config/files
    fi
  else
    docker build -t bb-config-utility:0.1.0  "${OPC_BASE_DIR}"/../roles/kubernetes/bb_config/files
  fi
  docker save bb-config-utility:0.1.0 > "${IMAGE_DOWNLOAD_PATH}"/bb-config-utility.tar.gz
}

build::tas() {
  cd "$CODE_DOWNLOAD_PATH"/telemetry-aware-scheduling
  docker run --rm -ti \
    -v "${PWD}":/opt/app \
    -v "${GOMODULE_DOWNLOAD_PATH}":/go/pkg \
    -w /opt/app \
    golang:1.14.9 make build
  if [[ -n "$HTTP_PROXY" ]];then
    docker build --build-arg http_proxy="${HTTP_PROXY}" -f deploy/images/Dockerfile_extender bin/ -t tas-extender
    docker build --build-arg http_proxy="${HTTP_PROXY}" -f deploy/images/Dockerfile_controller bin/ -t tas-controller
  else
    docker build -f deploy/images/Dockerfile_extender bin/ -t tas-extender
    docker build -f deploy/images/Dockerfile_controller bin/ -t tas-controller
  fi
  docker save tas-extender:latest > "$IMAGE_DOWNLOAD_PATH"/tas-extender.tar.gz
  docker save tas-controller:latest > "$IMAGE_DOWNLOAD_PATH"/tas-controller.tar.gz
}

build::rmd() {
  cd "${CODE_DOWNLOAD_PATH}"/rmd
  if [[ -n "$HTTP_PROXY" ]];then
    if [[ -n "$GIT_PROXY" ]];then
      docker build --build-arg http_proxy="${GIT_PROXY}" \
                   --build-arg https_proxy="${GIT_PROXY}" -t rmd ./
    else
      docker build --build-arg http_proxy="${HTTP_PROXY}" \
                   --build-arg https_proxy="${HTTP_PROXY}" -t rmd ./
    fi
  else
    docker build -t rmd ./
  fi
  docker save rmd:latest > "${IMAGE_DOWNLOAD_PATH}"/rmd.tar.gz
}

build::intel_rmd_operator() {
  cd "${CODE_DOWNLOAD_PATH}"/rmd-operator
  docker run --rm -ti \
    -v "$PWD":/opt/app \
    -v "${GOMODULE_DOWNLOAD_PATH}":/go/pkg \
    golang:1.14.9 bash -c "cd /root && if [[ -n ${HTTP_PROXY} ]];then \
      if [[ -n $GIT_PROXY ]];then \
      git config --global http.proxy $GIT_PROXY; \
      else git config --global http.proxy $HTTP_PROXY;fi;fi;git clone https://github.com/intel/intel-cmt-cat.git && \
      cd intel-cmt-cat && make && make install && cd /opt/app && make build"

  if [[ -n "$HTTP_PROXY" ]];then
    docker build --build-arg http_proxy="${HTTP_PROXY}" -t intel-rmd-node-agent -f build/Dockerfile.nodeagent .
    docker build --build-arg http_proxy="${HTTP_PROXY}" -t intel-rmd-operator   -f build/Dockerfile  .
  else
    docker build -t intel-rmd-node-agent -f build/Dockerfile.nodeagent .
    docker build -t intel-rmd-operator   -f build/Dockerfile  .
  fi
  docker save intel-rmd-node-agent:latest > "${IMAGE_DOWNLOAD_PATH}"/intel-rmd-node-agent.tar.gz
  docker save intel-rmd-operator:latest > "${IMAGE_DOWNLOAD_PATH}"/intel-rmd-operator.tar.gz
}

opc::update_kernel() {
  target_kernel_version=$(grep "^kernel_version" "$OPC_BASE_DIR"/../group_vars/* -rsh | sort -u | cut -d ':' -f 2 | sed s/[[:space:]]//g)
  target_kernel_package=$(grep "^kernel_package" "$OPC_BASE_DIR"/../group_vars/* -rsh | sort -u | cut -d ':' -f 2 | sed s/[[:space:]]//g)
  target_kernel_devel_package=$(grep "^kernel_devel_package" "$OPC_BASE_DIR"/../group_vars/* -rsh | sort -u | cut -d ':' -f 2 | sed s/[[:space:]]//g)

  sudo_cmd yum install --disableexcludes=all -y "$target_kernel_package"-"$target_kernel_version" "$target_kernel_devel_package"-"$target_kernel_version"
  sudo_cmd grubby --set-default /boot/vmlinuz-"$target_kernel_version"
  echo -n "Take effect after restart, whether to restart now?(Y/N) ";read -r choice
  choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
  if [[ "$choice" == "y" ]];then
    sudo_cmd reboot
  fi
}

build::collectd_fpga_plugin() {
  local kernel_version collectd_dir
  local target_kernel_version

  kernel_version=$(uname -r)
  target_kernel_version=$(grep "^kernel_version" "$OPC_BASE_DIR"/../group_vars/* -rsh | sort -u | cut -d ':' -f 2 | sed s/[[:space:]]//g)
  if [[ "$BUILD_COLLECTD_FPGA" == "enable" && -n "${DIR_OF_FPGA_ZIP}" ]];then
    if [[ "$kernel_version" != "$target_kernel_version" ]];then
      echo -n "Update the kernel to $target_kernel_version, do you agree?(Y/N) ";read -r update_kernel
      update_kernel=$(echo "${update_kernel}" | tr '[:upper:]' '[:lower:]')
      if [[ "${update_kernel}" == "y" ]];then
        opc::update_kernel
      fi
    else
      collectd_dir=$(mktemp -d)
      cp -f "$OPC_BASE_DIR"/../roles/telemetry/collectd/controlplane/files/* "$collectd_dir"
      cp "$DIR_OF_FPGA_ZIP"/* "$collectd_dir"
      set +e
      if [[ -n "$HTTP_PROXY" ]];then
        docker build --build-arg http_proxy="${HTTP_PROXY}" \
          --build-arg https_proxy="${HTTP_PROXY}" \
          -t collectd_fpga_plugin:0.1.0 "$collectd_dir"
      else
        docker build -t collectd_fpga_plugin:0.1.0 "$collectd_dir"
      fi
      rm -f "$collectd_dir" -rf
      docker save collectd_fpga_plugin:0.1.0 > "${IMAGE_DOWNLOAD_PATH}"/collectd_fpga_plugin.tar.gz
      set -e
    fi
  fi
}

build::help() {
  echo "$0 sudo_password build options"
  echo -e "options:"
  echo -e "cli                    EdgeDns CLI"
  echo -e "common                 eaa image"
  echo -e "interfaceservice       interfaceservice image"
  echo -e "fpga_opae              fpga-opae-pacn3000 image"
  echo -e "sriov_network          sriov_network_device_plugin image"
  echo -e "biosfw                 biosfw image"
  echo -e "bb_config              bb-config-utility image"
  echo -e "tas                    tas-controller image"
  echo -e "rmd                    intel-rmd-operator image"
  echo -e "rmd_operator           intel-rmd-operator image"
  echo -e "collectd_fpga          collectd_fpga_plugin"
}

opc::build::images() {
  local pwd

  pwd="$PWD"
  case $@ in
    cli)
      build::cli
    ;;
    common)
      build::common_services
    ;;
    interfaceservice)
      build::interfaceservice
    ;;
    fpga_opae)
      build::fpga-opae-pacn3000
    ;;
    sriov_cni)
      build::sriov_cni
    ;;
    sriov_network)
      build::sriov_network
    ;;
    biosfw)
      build::biosfw
    ;;
    bb_config)
      build::bb_config
    ;;
    tas)
      build::tas
    ;;
    rmd)
      build::rmd
    ;;
    rmd_operator)
      build::intel_rmd_operator
    ;;
    collectd_fpga)
      build::collectd_fpga_plugin
    ;;
    help)
      build::help
    ;;
    all)
      build::cli
      build::common_services
      build::interfaceservice
      build::fpga-opae-pacn3000
      build::sriov_cni
      build::sriov_network
      build::biosfw
      build::bb_config
      build::tas
      build::rmd
      build::intel_rmd_operator
      build::collectd_fpga_plugin
    ;;
  esac
  cd "${pwd}"
}

opc::download::others() {
  local url
  local name

  for list in $1
  do
    url=$(echo "$list" | cut -d ',' -f 2)
    name=$(echo "$url" | rev | cut -d '/' -f 1 | rev)
    if [[ ! -e "$OTHER_DOWNLOAD_PATH"/"$name" ]];then
      wget --progress=bar:force "$url" -P "$OTHER_DOWNLOAD_PATH" 2>&1 | progressfilt \
      || opc::log::error "Wget $url"
    fi
  done
}

opc::download::charts() {
  local tmp_dir
  local tmp_file
  local short_name

  for list in $1
  do
    OLD_IFS="$IFS"
    IFS=','
    # shellcheck disable=SC2206
    array=( $list )
    IFS="$OLD_IFS"
    for i in "${!array[@]}"
    do
      tmp_dir=$(echo "${array[i]}" | cut -d '|' -f 1)
      tmp_file=$(echo "${array[i]}" | cut -d '|' -f 2)
      short_name=$(echo "$tmp_file" | rev | cut -d '/' -f 1 | rev)
      tmp_dir="${CHARTS_DOWNLOAD_PATH}${tmp_dir}"
      if [[ ! -e "$tmp_dir" ]];then
        mkdir -p "$tmp_dir"
      fi
      if [[ ! -e "${tmp_dir}"/"${short_name}" ]];then
        wget --progress=bar:force https://raw.githubusercontent.com/"$tmp_file" -P "$tmp_dir" 2>&1 | progressfilt \
        || opc::log::error "wget https://raw.githubusercontent.com/$tmp_file"
      fi
    done
  done
}

