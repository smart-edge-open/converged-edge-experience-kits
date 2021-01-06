#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

declare -A oneLine
declare -A longName
declare -A urlDic
urlDic=(
[base]='http://mirror.centos.org/centos/7/os/x86_64/Packages/' \
[updates]='http://mirror.centos.org/centos/7/updates/x86_64/Packages/' \
[epel]='https://download-ib01.fedoraproject.org/pub/epel/7/x86_64/Packages/' \
[extras]='http://mirror.centos.org/centos/7/extras/x86_64/Packages/' \
[rt]='http://linuxsoft.cern.ch/cern/centos/7/rt/x86_64/Packages/' \
[docker]='https://download.docker.com/linux/centos/7/x86_64/stable/Packages/' \
[ius]='https://repo.ius.io/archive/7/x86_64/packages/' \
[ius-archive]='https://repo.ius.io/archive/7/x86_64/packages/' \
[other]='http://ftp.scientificlinux.org/linux/scientific/7.8/x86_64/os/Packages/' \
)

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

# Downoad package from network
do_download() {
  local i=0
  longName=$(echo "$1" | rev | cut -d '/' -f 1 | rev)
  if [ -e "${RPM_DOWNLOAD_PATH}"/"$longName" ];then
    return
  fi
  wget --progress=bar:force -e http_proxy="${HTTP_PROXY}" -e https_proxy="${HTTP_PROXY}" \
    -P "${RPM_DOWNLOAD_PATH}" "$1" 2>&1 | progressfilt || \
  if [[ "$2" -eq 0 ]];then
    echo "Wget Error"
    exit
  fi
}

# Try to find the package on the all possible addresses list
do_try_download() {
  local rname=$1
  local arch=$2
  local ignore=$3

  if [ -e "${RPM_DOWNLOAD_PATH}"/"${rname}"."${arch}".rpm ];then
    return
  fi

  for url in "${urlDic[@]}"
  do
    wget --progress=bar:force -e http_proxy="${HTTP_PROXY}" -e https_proxy="${HTTP_PROXY}" -P \
      "${RPM_DOWNLOAD_PATH}" "${url}${rname}.${arch}.rpm" 2>&1 | progressfilt || continue
    return
  done

  if [[ "$ignore" -eq 0 ]];then
    echo "Wget Error"
    exit
  fi
}

# Find the key in the map urlDic
do_try_find_key() {
  for key in "${!urlDic[@]}"
  do
    if [[ "$1" == "$key" ]];then
      echo 0
      return
    fi
  done
  echo 1
}

# Remove the '@' if it exists
do_remove_at() {
  local type

  type="$1"
  if [[ "${type:0:1}" == "@" ]];then
    echo "${type:1}"
  else
    echo "$type"
  fi
}

# Deal with the broken row in the file tmp/list.log
# Example :
# kernel-rt.x86_64                        3.10.0-1127.19.1.rt56.1116.el7
#                                                                      @/kernel-rt-3.10.0-1127.19.1.rt56.1116.el7.x86_64
do_broken_row() {
  local n
  local item
  local type
  local version
  local rname
  local columns
  local ret
  local name=$1
  local arch=$2

  n=$(echo "${oneLine[@]}" | awk '{print $1}' | cut -d ':' -f 1)
  n=$(( n + 1 ))
  item=$(sed -n "${n}p" /tmp/list.log)
  columns=$(( 3 - $3 ))
  type=$(echo "$item" | awk -v x="${columns}" '{print $x}')
  type=$(do_remove_at "$type")
  if [[ "$3" -eq 1 ]];then
    version=$(echo "$item" | awk '{print $1}' | cut -d ':' -f 2)
    rname="${name}-${version}"
  elif [[ "$3" -eq 2 ]];then
    version=$(echo "${oneLine[@]}" | awk '{print $2}' | cut -d ':' -f 2)
    rname="${name}-${version}"
  fi
  ret=$(do_try_find_key "$type")
  if [[ "$ret" -eq 0 ]];then
    do_download "${urlDic[$type]}${rname}.${arch}.rpm" "$4"
  else
    do_try_download "$rname" "$arch" "$4"
  fi
}

# Deal with the normal row in the file /tmp/list.log
# Example:
# libacl.x86_64                           2.2.51-15.el7                @anaconda
do_row() {
  local version
  local rname
  local type
  local ret
  local name=$1
  local arch=$2

  version=$(echo "${oneLine[@]}" | awk '{print $2}' | cut -d ':' -f 2)
  rname="${name}-${version}"
  type=$(echo "${oneLine[@]}" | awk '{print $3}')
  type=$(do_remove_at "$type")
  if [[ "$type" == "epel" || "$type" == "ius" \
     || "$type" == "ius-archive" ]];then
    do_download "${urlDic[$type]}${name:0:1}/${rname}.${arch}.rpm" "$3"
  else
    ret=$(do_try_find_key "$type")
    if [[ "$ret" == "0" ]];then
      if [[ "$type" == "updates" ]];then
        do_download "${urlDic[base]}${rname}.${arch}.rpm" 1
        do_download "${urlDic[updates]}${rname}.${arch}.rpm" 1
      else
        do_download "${urlDic[$type]}${rname}.${arch}.rpm" "$3"
      fi
    else
      do_try_download "$rname" "$arch" "$3"
    fi
  fi
}

# Deal with multiple versions function
# Example:
# gcc.x86_64                              4.8.5-39.el7                 base
# gcc.x86_64                              4.8.5-44.el7                 base
do_multi_version() {
  local columns
  local name=$1
  local arch=$2
  local n=$3

  i=1
  echo "===== $name.$arch"
  n=$(( n + 1 ))
  while [ $i -lt $n ]
  do
    oneLine=$(grep -nE "^$name.${arch}" /tmp/list.log | sed -n "${i}p")
    let i++
    columns=$(echo "${oneLine[@]}" | awk -F ' ' '{print NF}')
    if [[ "$columns" -lt 3 ]];then
      do_broken_row "$name" "$arch" "$columns" 1
    else
      do_row "$name" "$arch" 1
    fi
  done
}

# Download rpm main function
# Parse the address through each line of the file
# that generated by one command, sudo yum list > list.log
do_rpm_main() {
  local ret
  local columns
  local name=$1
  local arch=$2

  ret=$(grep -cE "^${name}.${arch}" /tmp/list.log)
  if [[ "$ret" -gt 1 ]];then
    do_multi_version "$name" "$arch" "$ret"
  elif [[ "$ret" -eq 1 ]];then
    oneLine=$(grep -nE "^$name.$arch" /tmp/list.log)
    columns=$(echo "${oneLine[@]}" | awk -F ' ' '{print NF}')
    if [[ "$columns" -lt 3 ]];then
      do_broken_row "$name" "$arch" "$columns" 0
    else
      do_row "$name" "$arch" 0
    fi
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

# Create directory under the path of '../'
opc::dir::create() {
  local dir=${1:-}
  opc::log::status "Create the directory $dir"
  mkdir -p "$dir" || opc::log::error "mkdir $OPC_DOWNLOAD_PATH"
}

# Download the rpms from internet
opc::download::rpm() {
  local url
  local ret
  local shortName

  sudo_cmd yum clean all
  sudo_cmd yum makecache fast
  sudo_cmd yum list --enablerepo=ius-archive > /tmp/list.log
  for list in $1
  do
    url=$(echo "$list" | cut -d ',' -f 2)
    longName=$(echo "$url" | rev | cut -d '/' -f 1 | rev)
    shortName=$(echo "$longName" | sed 's/-[0-9]/ /' | awk '{print $1}')
    echo "------> $shortName"
    ret=$(opc::check::exist "$longName" "noarch")
    if [[ "$ret" -eq 0 ]];then
      do_rpm_main "$shortName" "noarch"
    else
      do_rpm_main "$shortName" "x86_64"
    fi
  done
  # for special packages
  do_download "http://mirror.centos.org/centos/7/os/x86_64/Packages/gcc-c++-4.8.5-44.el7.x86_64.rpm" 0
  do_download "http://mirror.centos.org/centos/7/os/x86_64/Packages/libstdc++-devel-4.8.5-44.el7.x86_64.rpm" 0
  do_download "http://mirror.centos.org/centos/7/os/x86_64/Packages/libstdc++-4.8.5-44.el7.x86_64.rpm" 0
  do_download "https://github.com/alauda/ovs/releases/download/2.12.0-5/openvswitch-2.12.0-5.el7.x86_64.rpm" 0
  do_download "https://github.com/alauda/ovs/releases/download/2.12.0-5/ovn-2.12.0-5.el7.x86_64.rpm" 0
  do_download "http://ftp.scientificlinux.org/linux/scientific/7.8/x86_64/os/Packages/tuned-2.11.0-8.el7.noarch.rpm" 0
  do_download "http://ftp.scientificlinux.org/linux/scientific/7.8/x86_64/os/Packages/tuned-profiles-realtime-2.11.0-8.el7.noarch.rpm" 0
  do_download "http://linuxsoft.cern.ch/cern/centos/7/rt/x86_64/Packages/kernel-rt-3.10.0-1127.19.1.rt56.1116.el7.x86_64.rpm" 0
  do_download "http://linuxsoft.cern.ch/cern/centos/7/rt/x86_64/Packages/kernel-rt-kvm-3.10.0-1127.19.1.rt56.1116.el7.x86_64.rpm" 0
  do_download "http://linuxsoft.cern.ch/cern/centos/7/rt/x86_64/Packages/kernel-rt-devel-3.10.0-1127.19.1.rt56.1116.el7.x86_64.rpm" 0
}

# Download the k8s commands from internet
opc::download::k8s_commands() {
  local new_name
  local files

  # generate the repo files
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
  # Create temp dir
  tmp_dir=$(mktemp -d)
  # Install yum plugin
  sudo_cmd yum install yum-utils -y
  # Downloading for dependencies
  sudo_cmd yumdownloader cri-tools-1.13.0-0 --resolve --destdir="$tmp_dir"
  sudo_cmd yumdownloader kubernetes-cni-0.8.7-0 --resolve --destdir="$tmp_dir"
  # Download kubeadm-1.18.4
  sudo_cmd yumdownloader kubeadm-1.19.3-0 --resolve --destdir="$tmp_dir"
  # Download kubelet-1.18.4
  sudo_cmd yumdownloader kubelet-1.19.3-0 --resolve --destdir="$tmp_dir"
  # Download kubectl-1.18.4
  sudo_cmd yumdownloader kubectl-1.19.3-0 --resolve --destdir="$tmp_dir"

  # Rename
  files=$(ls "$tmp_dir")
  set +e
  for f in $files
  do
    new_name=$(echo "$f" | grep -o -E '\-[k|c][u|r].*' | sed 's/^-//')
    if [[ "$f" == "$new_name" || -z "$new_name" ]];then
      continue
    else
      mv "${tmp_dir}/$f" "${tmp_dir}/${new_name}"
    fi
  done
  set -e
  cp -n "${tmp_dir}"/* "${RPM_DOWNLOAD_PATH}"
  rm -rf "${tmp_dir}"
}

# Download the github code from internet
opc::download::github() {
  local name
  local url
  local flag
  local value
  local ret
  local pwd=$PWD

  # make the directory to be clean
  cd "$CODE_DOWNLOAD_PATH" && sudo_cmd rm ./* -rf
  for list in $1
  do
    name=$(echo "$list" | cut -d ',' -f 1)
    url=$(echo "$list" | cut -d ',' -f 2)
    flag=$(echo "$list" | cut -d ',' -f 3)
    value=$(echo "$list" | cut -d ',' -f 4)
    # open-ness git repo need a token
    ret=$(opc::check::exist "$url" "open-ness")
    if [[ "$ret" -eq 0 ]];then
      if [ -z "$GITHUB_TOKEN" ];then
        opc::log::error "Cannot download open-ness code!"
      fi
      part1=$(echo "$url" | cut -d ':' -f 1)
      part2=$(echo "$url" | cut -d ':' -f 2)
      part2="${part2:2}"
      docker run --rm -ti \
      -v "$PWD":/opt/app \
      -w /opt/app \
      golang:1.14.9 bash -c "git config --global http.proxy ${GIT_PROXY} \
        && git clone ${part1}://${GITHUB_TOKEN}@${part2}"
    else
      if [[ "$flag" == "tag" ]];then
        docker run --rm -ti \
        -v "$PWD":/opt/app \
        -w /opt/app \
        golang:1.14.9 bash -c "git config --global http.proxy ${GIT_PROXY} \
          && git clone $url && cd $name && git checkout $value"
      else
        docker run --rm -ti \
        -v "$PWD":/opt/app \
        -w /opt/app \
        golang:1.14.9 bash -c "git config --global http.proxy ${GIT_PROXY} \
          && git clone $url && cd $name && git reset --hard $value"
      fi
    fi
  done
  sudo_cmd chown -R "$USER":"$USER" "${CODE_DOWNLOAD_PATH}"
  cd "${pwd}"
}

download::module() {
  docker run -ti --rm  \
    -v "$PWD":/opt/app   \
    -v "${OPC_BASE_DIR}"/scripts/run.sh.bak:/root/run.sh:ro \
    -v "${GOMODULE_DOWNLOAD_PATH}":/go/pkg              \
    -v "${OPC_DOWNLOAD_PATH}"/ret:/root/.ret            \
    -e http_proxy="${HTTP_PROXY}"                   \
    -e https_proxy="${HTTP_PROXY}"                  \
    -e git_proxy="${GIT_PROXY}"                     \
    -e DOCKER_NETRC="machine github.com login $GITHUB_USERNAME password $GITHUB_TOKEN" \
    golang:1.14.9 bash /root/run.sh
}

# Download go modules
opc::download::gomodules() {
  local name
  local pwd="$PWD"

  for list in $1
  do
    name=$(echo "$list" | cut -d ',' -f 1)
    cd "${CODE_DOWNLOAD_PATH}"/"$name"
    if [[ ! -e "go.mod" ]];then
      continue
    fi
    if [ -e "$OPC_DOWNLOAD_PATH"/ret ];then
      rm -f "$OPC_DOWNLOAD_PATH"/ret
    fi
    touch "$OPC_DOWNLOAD_PATH"/ret
    if [[ "$name" == "edgenode" || "$name" == "x-epcforedge" ]];then
      dirs=$(find . -name go.mod)
      for dir in $dirs
      do
        mod_dir=$(dirname "$dir")
        pushd "$mod_dir"
        download::module
        popd
      done
    else
      download::module
    fi
    ret=$(cat "$OPC_DOWNLOAD_PATH"/ret)
    if [[ -z "$ret" ]];then
      rm "$OPC_DOWNLOAD_PATH"/ret -f
      opc::log::error "ERROR: Project $name ---> go mod download"
    fi
    rm "$OPC_DOWNLOAD_PATH"/ret -f
    opc::log::status "Download mod successful for $name"
  done
  cd "$GOMODULE_DOWNLOAD_PATH"
  if [ -e "gomod.tar.gz" ];then
    rm -f gomod.tar.gz
  fi
  sudo_cmd chown -R "$USER":"$USER" "$GOMODULE_DOWNLOAD_PATH"
  tar czvf gomod.tar.gz ./*
  cd "${pwd}"
}

# Download pip packages
opc::download::pippackage() {
  local url
  local name

  for list in $1
  do
    url=$(echo "$list" | cut -d ',' -f 2)
    name=$(echo "$url" | rev | cut -d '/' -f 1 | rev)
    if [[ ! -e "$PIP_DOWNLOAD_PATH/$name" ]];then
      wget --progress=bar:force -e https_proxy="${HTTP_PROXY}" -e http_proxy="${HTTP_PROXY}" \
        -P "$PIP_DOWNLOAD_PATH" https://files.pythonhosted.org/packages/"$url" 2>&1 | progressfilt \
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
      wget --progress=bar:force -e https_proxy="${HTTP_PROXY}" \
           -e http_proxy="${HTTP_PROXY}" -P "${YAML_DOWNLOAD_PATH}" "$url" 2>&1 | progressfilt \
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
  cd "$CODE_DOWNLOAD_PATH"/edgenode/edgecontroller
  docker run --rm -ti \
    -v "$GOMODULE_DOWNLOAD_PATH":/go/pkg \
    -v "$PWD":/opt/app \
    -w /opt/app golang:1.14.9 \
    go build -o dist/edgednscli ./cmd/edgednscli
}

build::common_services() {
  cd "$CODE_DOWNLOAD_PATH"/edgenode
  docker run --rm -ti \
    -v "$GOMODULE_DOWNLOAD_PATH":/go/pkg \
    -v "$PWD":/opt/app \
    -w /opt/app golang:1.14.9 \
    bash -c "ln -sf /bin/cp /usr/bin/cp \
    && make common-services SKIP_DOCKER_IMAGES=1"
    docker build --build-arg http_proxy="${HTTP_PROXY}" -t eaa:1.0 dist/eaa
    docker build --build-arg http_proxy="${HTTP_PROXY}" -t edgednssvr:1.0 dist/edgednssvr
    docker build --build-arg http_proxy="${HTTP_PROXY}" -t certsigner:1.0 dist/certsigner
    docker build --build-arg http_proxy="${HTTP_PROXY}" -t certrequester:1.0 dist/certrequester
    docker save eaa:1.0 > "$IMAGE_DOWNLOAD_PATH"/eaa.tar.gz
    docker save edgednssvr:1.0 > "$IMAGE_DOWNLOAD_PATH"/edgednssvr.tar.gz
    docker save certsigner:1.0 > "$IMAGE_DOWNLOAD_PATH"/certsigner.tar.gz
    docker save certrequester:1.0 > "$IMAGE_DOWNLOAD_PATH"/certrequester.tar.gz
}

build::interfaceservice() {
  cd "$CODE_DOWNLOAD_PATH"/edgenode
  docker run --rm -ti \
    -v "$GOMODULE_DOWNLOAD_PATH":/go/pkg \
    -v "$PWD":/opt/app \
    -w /opt/app golang:1.14.9 \
    bash -c "ln -sf /bin/cp /usr/bin/cp \
    && make interfaceservice SKIP_DOCKER_IMAGES=1"
    docker build --build-arg http_proxy="${HTTP_PROXY}" \
      --build-arg https_proxy="${HTTP_PROXY}" \
      -t interfaceservice:1.0 dist/interfaceservice
    docker save interfaceservice:1.0 > "$IMAGE_DOWNLOAD_PATH"/interfaceservice.tar.gz
}

build::fpga-opae-pacn3000() {
  local kernel_version

  kernel_version=$(uname -r)
  if [[ "$BUILD_OPAE" == "enable" ]];then
    if [[ "$kernel_version" != "3.10.0-1127.19.1.rt56.1116.el7.x86_64" ]];then
      echo -n "Update the kernel to kernel-rt-kvm-3.10.0-1127.19.1.rt56.1116.el7.x86_64, do you agree?(Y/N) ";read update_kernel
      update_kernel=$(echo "${update_kernel}" | tr '[:upper:]' '[:lower:]')
      if [[ "$update_kernel" == "y" ]];then
        opc::update_kernel
      fi
    else
      cd "$CODE_DOWNLOAD_PATH"/edgenode
      sudo_cmd chown -R "$USER":"$USER" ./*
      cp "$DIR_OF_OPAE_ZIP"/OPAE_SDK_1.3.7-5_el7.zip build/fpga_opae
      docker build --build-arg http_proxy="${HTTP_PROXY}" \
        --build-arg https_proxy="${HTTP_PROXY}" \
        -t fpga-opae-pacn3000:1.0 -f ./build/fpga_opae/Dockerfile ./build/fpga_opae
      docker save fpga-opae-pacn3000:1.0 > "$IMAGE_DOWNLOAD_PATH"/fpga-opae-pacn3000.tar.gz
      rm ./build/fpga_opae/OPAE_SDK_1.3.7-5_el7.zip
    fi
  fi
}

build::sriov_network() {
  cd "${CODE_DOWNLOAD_PATH}"/sriov-network-device-plugin
  make image HTTP_PROXY="${HTTP_PROXY}" HTTP_PROXYS="${HTTP_PROXY}" \
    || opc::log::error "make image sriov_network_device_plugin"
  docker save nfvpe/sriov-device-plugin:latest > "$IMAGE_DOWNLOAD_PATH"/sriov-device-plugin.tar.gz
}

build::sriov_cni() {
  cd "$CODE_DOWNLOAD_PATH"/sriov-cni
  make image HTTP_PROXY="${HTTP_PROXY}" HTTP_PROXYS="${HTTP_PROXY}" \
    || opc::log::error "make image sriov_cni"
  docker save nfvpe/sriov-cni:latest > "$IMAGE_DOWNLOAD_PATH"/sriov_cni.tar.gz
}

build::biosfw() {
  if [[ "${BUILD_BIOSFW}" == "enable" ]];then
    cd "$CODE_DOWNLOAD_PATH"/edgenode
    sudo_cmd chown -R "${USER}":"${USER}" ./*
    cp "$DIR_OF_BIOSFW_ZIP"/syscfg_package.zip dist/biosfw
    docker build --build-arg http_proxy="${HTTP_PROXY}" -t openness-biosfw dist/biosfw
    docker save openness-biosfw:latest > "${IMAGE_DOWNLOAD_PATH}"/biosfw.tar.gz
    rm dist/biosfw/syscfg_package.zip -f
  fi
}

build::bb_config() {
  docker build --build-arg http_proxy="${HTTP_PROXY}" --build-arg https_proxy="${HTTP_PROXY}" -t \
    bb-config-utility:0.1.0  "${OPC_BASE_DIR}"/../roles/bb_config/files
  docker save bb-config-utility:0.1.0 > "${IMAGE_DOWNLOAD_PATH}"/bb-config-utility.tar.gz
}

build::tas() {
  cd "$CODE_DOWNLOAD_PATH"/telemetry-aware-scheduling
  docker run --rm -ti \
    -v "${PWD}":/opt/app \
    -v "${GOMODULE_DOWNLOAD_PATH}":/go/pkg \
    -w /opt/app \
    golang:1.14.9 make build
  docker build -f deploy/images/Dockerfile_extender bin/ -t tas-extender
  docker build -f deploy/images/Dockerfile_controller bin/ -t tas-controller
  docker save tas-extender:latest > "$IMAGE_DOWNLOAD_PATH"/tas-extender.tar.gz
  docker save tas-controller:latest > "$IMAGE_DOWNLOAD_PATH"/tas-controller.tar.gz
}

build::rmd() {
  cd "${CODE_DOWNLOAD_PATH}"/rmd
  docker build --build-arg https_proxy="$GIT_PROXY" --build-arg http_proxy="$HTTP_PROXY" -t rmd ./
  docker save rmd:latest > "${IMAGE_DOWNLOAD_PATH}"/rmd.tar.gz
}

build::intel_rmd_operator() {
  cd "${CODE_DOWNLOAD_PATH}"/rmd-operator
  docker run --rm -ti \
    -v "$PWD":/opt/app \
    -v "${OPC_BASE_DIR}"/scripts/build_rmd_operator.sh.bak:/root/build_rmd_operator.sh:ro \
    -v "${GOMODULE_DOWNLOAD_PATH}":/go/pkg \
    -e http_proxy="$GIT_PROXY" \
    golang:1.14.9 bash /root/build_rmd_operator.sh

  docker build --build-arg https_proxy="${GIT_PROXY}" -t intel-rmd-node-agent -f build/Dockerfile.nodeagent .
  docker build --build-arg https_proxy="${GIT_PROXY}" -t intel-rmd-operator   -f build/Dockerfile  .
  docker save intel-rmd-node-agent:latest > "${IMAGE_DOWNLOAD_PATH}"/intel-rmd-node-agent.tar.gz
  docker save intel-rmd-operator:latest > "${IMAGE_DOWNLOAD_PATH}"/intel-rmd-operator.tar.gz
}

opc::update_kernel() {
  local tmp_dir
  local tuned_list
  local kernel_list

  tmp_dir=$(mktemp -d)
  # clean tuned version
  sudo_cmd yum remove tuned -y
  sudo_cmd rpm -ivh "${RPM_DOWNLOAD_PATH}"/tuned-2.11.0-8.el7.noarch.rpm
  tuned_list=(libnl-1.1.4-3.el7.x86_64.rpm  \
                    python-ethtool-0.8-8.el7.x86_64.rpm  \
                    tuna-0.13-9.el7.noarch.rpm  \
                    tuned-profiles-realtime-2.11.0-8.el7.noarch.rpm)
  kernel_list=(kernel-rt-3.10.0-1127.19.1.rt56.1116.el7.x86_64.rpm  \
                    kernel-rt-kvm-3.10.0-1127.19.1.rt56.1116.el7.x86_64.rpm  \
                    kernel-rt-devel-3.10.0-1127.19.1.rt56.1116.el7.x86_64.rpm \
                    rt-setup-2.0-9.el7.x86_64.rpm)
  for f in "${tuned_list[@]}"
  do
    cp "${RPM_DOWNLOAD_PATH}"/"$f" "$tmp_dir"
  done
  for f in "${kernel_list[@]}"
  do
    cp "${RPM_DOWNLOAD_PATH}"/"$f" "$tmp_dir"
  done
  sudo_cmd yum localinstall -y "$tmp_dir"/* && rm "$tmp_dir" -rf

  sudo_cmd grubby --set-default /boot/vmlinuz-3.10.0-1127.19.1.rt56.1116.el7.x86_64
  echo -n "Take effect after restart, whether to restart now?(Y/N) ";read choice
  choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
  if [[ "$choice" == "y" ]];then
    sudo_cmd reboot
  fi
}

build::collectd_fpga_plugin() {
  local kernel_version collectd_dir

  kernel_version=$(uname -r)
  if [[ "$BUILD_COLLECTD_FPGA" == "enable" && ! -z "${DIR_OF_FPGA_ZIP}" ]];then
    if [[ "$kernel_version" != "3.10.0-1127.19.1.rt56.1116.el7.x86_64" ]];then
      echo -n "Update the kernel to kernel-rt-kvm-3.10.0-1127.19.1.rt56.1116.el7.x86_64, do you agree?(Y/N) ";read update_kernel
      update_kernel=$(echo "${update_kernel}" | tr '[:upper:]' '[:lower:]')
      if [[ "${update_kernel}" == "y" ]];then
        opc::update_kernel
      fi
    else
      collectd_dir=$(mktemp -d)
      cp -f "$OPC_BASE_DIR"/../roles/telemetry/collectd/controlplane/files/* "$collectd_dir"
      cp "$DIR_OF_FPGA_ZIP"/OPAE_SDK_1.3.7-5_el7.zip "$collectd_dir"
      set +e
      docker build --build-arg http_proxy="${HTTP_PROXY}" \
        --build-arg https_proxy="${HTTP_PROXY}" \
        -t collectd_fpga_plugin:0.1.0 "$collectd_dir"
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
      wget --progress=bar:force -e https_proxy="${HTTP_PROXY}" \
           -e http_proxy="${HTTP_PROXY}" "$url" -P "$OTHER_DOWNLOAD_PATH" 2>&1 | progressfilt \
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
    array=($list)
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
        wget --progress=bar:force -e https_proxy="${HTTP_PROXY}" -e http_proxy="${HTTP_PROXY}" \
          https://raw.githubusercontent.com/"$tmp_file" -P "$tmp_dir" 2>&1 | progressfilt \
        || opc::log::error "wget https://raw.githubusercontent.com/$tmp_file"
      fi
    done
  done
}

