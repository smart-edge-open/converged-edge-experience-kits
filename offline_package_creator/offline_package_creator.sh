#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

set -o errexit
set -o nounset
set -o pipefail

# Download precheck yum packages
precheck_yum_download() {
  sudo_cmd yum install --downloadonly --downloaddir="$PRERPM_DOWNLOAD_PATH" ansible
  sudo_cmd yum install --downloadonly --downloaddir="$PRERPM_DOWNLOAD_PATH" python-netaddr
  sudo_cmd yum install --downloadonly --downloaddir="$PRERPM_DOWNLOAD_PATH" python3
  sudo_cmd tar czvf prepackages.tar.gz -C "$PRERPM_DOWNLOAD_PATH" ./
  sudo_cmd mv prepackages.tar.gz ../roles/offline_roles/unpack_offline_package/files
}

# Download yum packages
yum_download() {
  download_yum_list=$(python3 scripts/get_yum_list.py)
  if [[ -z ${download_yum_list} ]];then
    opc::log::error "ERROR: Can not get yum packages list"
  fi
  opc::download::yum "${download_yum_list[@]}"
  opc::download::yum "httpd mod_ssl expect"
}

# Download github code
code_download() {
  download_github_repo_list=$(python3 scripts/parse_yml.py github-repos)
  if [[ -z ${download_github_repo_list} ]];then
    opc::log::error "ERROR: Can not parse the data yaml file"
  fi
  opc::download::github "${download_github_repo_list[@]}"
}

# Download go modules
go_modules_download() {
  download_go_modules_list=$(python3 scripts/parse_yml.py go-modules)
  if [[ -z ${download_go_modules_list} ]];then
    opc::log::error "ERROR: Can not parse the data yaml file"
  fi
  opc::download::gomodules "${download_go_modules_list[@]}"
}

# Download pip packages
pip_packages_download() {
  download_pip_list=$(python3 scripts/parse_yml.py pip-packages)
  if [[ -z ${download_pip_list} ]];then
    opc::log::error "ERROR: Can not parse the data yaml file"
  fi
  opc::download::pippackage "${download_pip_list[@]}"
}

# Download yaml files
yaml_download() {
  download_yaml_list=$(python3 scripts/parse_yml.py yaml-files)
  if [[ -z ${download_yaml_list} ]];then
    opc::log::error "ERROR: Can not parse the data yaml file"
  fi
  opc::download::yamls "${download_yaml_list[@]}"
}

# Download docker images
images_download() {
  download_image_list=$(python3 scripts/parse_yml.py docker-images)
  if [[ -z ${download_image_list} ]];then
    opc::log::error "ERROR: Can not parse the data yaml file"
  fi
  opc::download::images "${download_image_list[@]}"
}

# Build private images
images_build() {
  opc::build::images "$1"
}

# Download other files
others_download() {
  download_other_list=$(python3 scripts/parse_yml.py other-files)
  if [[ -z ${download_other_list} ]];then
    opc::log::error "ERROR: Can not parse the data yaml file"
  fi
  opc::download::others "${download_other_list[@]}"
}

# Download charts
charts_download() {
  download_chart_list=$(python3 scripts/parse_yml.py charts-files)
  if [[ -z ${download_chart_list} ]];then
    opc::log::error "ERROR: Can not parse the data yaml file"
  fi
  opc::download::charts "${download_chart_list[@]}"
}

zip_and_move() {
  cd "$OPC_BASE_DIR"
  # remove an existing package
  if [ -e opcdownloads.tar.gz ];then
    rm -f opcdownloads.tar.gz
  fi
  # zip the opcdownloads
  tar czvf opcdownloads.tar.gz --transform s=opcdownloads/== opcdownloads/*
  md5sum opcdownloads.tar.gz | awk '{print $1}' > checksum.txt
  sudo_cmd mv -f opcdownloads.tar.gz checksum.txt  ../roles/offline_roles/unpack_offline_package/files
}

usage() {
  echo -e "\033[33mUsage: Use this script as ordinary user, not root\033[0m"
  echo "$0 sudo_password options"
  echo -e "options:"
  echo -e "	""\033[33mhelp\033[0m         show help"
  echo -e "	""\033[33mall\033[0m          download all and zip it"
  echo -e "	""\033[33myum\033[0m          download yum packages only"
  echo -e "	""\033[33mcode\033[0m         download code from github only"
  echo -e "	""\033[33mgo_modules\033[0m   download go_modules"
  echo -e "	""\033[33mpip_packages\033[0m download pip packages"
  echo -e "	""\033[33myaml\033[0m         download yaml fils only"
  echo -e "	""\033[33mimages\033[0m       download docker images only"
  echo -e "	""\033[33mbuild\033[0m        build docker images"
  echo -e "	""             cli,common,interfaceservice,biosfw,tas,sriov_cni,sriov_network,bb_config,rmd,collectd_fpga;all(default)"
  echo -e "	""             like: \033[33m$0 build common\033[0m"
  echo -e "	""\033[33mcharts\033[0m       download charts file only"
  echo -e "	""\033[33mothers\033[0m       download other file only"
  echo -e "	""\033[33mzip\033[0m          zip the directory of opcdownloads and mv it to a target directory"
}

main() {
  id=$(id -u)

  if [[ $# -lt 1 || "$1" == "help" ]];then
    usage
    exit
  fi

  if [[ "$id" -ne 0 ]];then
    read -r -p "Please Input sudo password:" -s PASSWD
    echo "$PASSWD" | sudo -S ls /root > /dev/null || exit
  fi

OPC_BASE_DIR=$(dirname "$(readlink -f "$0")")

# load the system environment variable
source /etc/environment

source scripts/initrc
source scripts/common.sh

rpm -aq | grep -qe "^epel-release" || sudo_cmd yum install -y epel-release ||
  opc::log::error "ERROR:Install epel-release"

for item in "$RPM_DOWNLOAD_PATH" "$PRERPM_DOWNLOAD_PATH" "$CODE_DOWNLOAD_PATH" \
    "$GOMODULE_DOWNLOAD_PATH" "$PIP_DOWNLOAD_PATH" "$YAML_DOWNLOAD_PATH" \
    "$IMAGE_DOWNLOAD_PATH" "$OTHER_DOWNLOAD_PATH" "$CHARTS_DOWNLOAD_PATH"
do
  if [ ! -e "$item" ];then
    opc::dir::create "$item"
    opc::log::status "Create the directory $OPC_DOWNLOAD_PATH successful"
  fi
done

# tuned-2.11.0-9.el7 and tuned-profiles-realtime-2.11.0-9.el7.noarch.rpm are from OEK's groups file
# the location is "../inventory/default/group_vars/controller_group/10-*.yml"
# must download first, then to install the tool
yum install --downloadonly --downloaddir="$RPM_DOWNLOAD_PATH" wget python-setuptools python3 python3-pip tuna tuned-2.11.0-9.el7
sudo_cmd yum install -y wget python-setuptools python3 python3-pip tuned-2.11.0-9.el7

opc::download::yum "http://ftp.scientificlinux.org/linux/scientific/7.9/x86_64/os/Packages/tuned-profiles-realtime-2.11.0-9.el7.noarch.rpm"
set +e
sudo_cmd yum install -y install http://ftp.scientificlinux.org/linux/scientific/7.9/x86_64/os/Packages/tuned-profiles-realtime-2.11.0-9.el7.noarch.rpm
set -e

# install repos on this machine
host_repos_required

# download precheck yum package first
precheck_yum_download

# Python libs
host_pylibs_required "configparser" "pyyaml" "jinja2"

  case $1 in
    yum)
      yum_download
      exit
    ;;
    code)
      source scripts/precheck.sh
      code_download
      exit
    ;;
    go_modules)
      source scripts/precheck.sh
      code_download
      go_modules_download
      exit
    ;;
    pip_packages)
      pip_packages_download
      exit
    ;;
    yaml)
      yaml_download
      exit
    ;;
    build)
      source scripts/precheck.sh
      if [ $# -lt 2 ];then
        images_build all
      else
        images_build "$2"
      fi
      exit
    ;;
    images)
      source scripts/precheck.sh
      images_download
      exit
    ;;
    charts)
      charts_download
      exit
    ;;
    others)
      others_download
      exit
    ;;
    zip)
      zip_and_move
      exit
    ;;
    all)
      yum_download
      source scripts/precheck.sh
      code_download
      go_modules_download
      pip_packages_download
      yaml_download
      images_download
      images_build all
      others_download
      charts_download
      zip_and_move
      printf "\n\nOPC INFO:  Completed Successfully\n"
      exit
    ;;
    *)
      echo "+++ give me a valid choice!"
      usage
      exit
    ;;
  esac
}

main "$@"
