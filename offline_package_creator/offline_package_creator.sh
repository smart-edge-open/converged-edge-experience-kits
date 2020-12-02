#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

set -o errexit
set -o nounset
set -o pipefail

# Download rpms
rpms_download() {
  download_rpm_list=$(python3 scripts/parse_yml.py rpm-packages) 
  if [[ -z ${download_rpm_list} ]];then
    opc::log::error "ERROR: Can not parse the data yaml file"
  fi
  opc::download::rpm "${download_rpm_list[@]}"
}

# Download kubeadm kubelet kubectl command
k8s_cmd() {
  opc::download::k8s_commands
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
  opc::build::images "${1}"
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
  local str
  local nline
  local tmpDir

  # remove an existing package
  if [ -e opcdownloads.tar.gz ];then
    rm -f opcdownloads.tar.gz
  fi
  # zip the opcdownloads
  tar czvf opcdownloads.tar.gz --transform s=opcdownloads/== opcdownloads/*
  md5sum opcdownloads.tar.gz | awk '{print $1}' > checksum.txt

  # zip the pakcages for prechecking
  tmpDir=$(mktemp -d)
  str=$(ls opcdownloads/rpms -l)
  while read line
  do
    nline=${line//#*/}
    if [[ -z "$nline" ]];then
      continue
    fi
    names=$(echo "$str" | grep -oE " ${nline}-[0-9]")
    for name in ${names}
    do
      cp "opcdownloads/rpms/${name}"* "${tmpDir}"
    done
  done < file/precheck/precheck_requirements.txt
  tar czvf prepackages.tar.gz -C "${tmpDir}" ./
  rm -rf "${tmpDir}"
}

usage() {
  echo -e "\033[33mUsage: Use it under ordinary users, not root\033[0m"
  echo "$0 sudo_password options"
  echo -e "options:"
  echo -e "	""\033[33mhelp\033[0m         show help"
  echo -e "	""\033[33mall\033[0m          download all and zip it"
  echo -e "	""\033[33mrpm\033[0m          download rpm only"
  echo -e "	""\033[33mk8s\033[0m          download k8s commands only"
  echo -e "	""\033[33mcode\033[0m         download code from github only"
  echo -e "	""\033[33mgo_modules\033[0m   download go_modules"
  echo -e "	""\033[33mpip_packages\033[0m download pip packages"
  echo -e "	""\033[33myaml\033[0m         download yaml fils only"
  echo -e "	""\033[33mimages\033[0m       download docker images only"
  echo -e "	""\033[33mbuild\033[0m        build docker images"
  echo -e "	""             common,interfaceservice,biosfw,tas,sriov_cni,sriov_network,fpga_cfg,rmd,collectd_fpga;all(default)"
  echo -e "	""             like: \033[33m$0 build common\033[0m"
  echo -e "	""\033[33mcharts\033[0m       download charts file only"
  echo -e "	""\033[33mothers\033[0m       download other file only"
  echo -e "	""\033[33mzip\033[0m          zip the directory of opcdownloads and mv it to a target directory"
}

main() {
  id=$(id -u)
  if [[ "$id" -eq 0 ]];then
    usage
    exit
  fi

  if [[ $# -lt 2 || "$1" == "help" ]];then
    usage
    exit
  fi
  PASSWD=$1
  echo "$PASSWD" | sudo -S ls /root > /dev/null || exit

declare OPC_BASE_DIR
OPC_BASE_DIR=$(dirname "$(readlink -f "$0")")
export OPC_BASE_DIR

source scripts/initrc
source scripts/common.sh
source scripts/precheck.sh

  case $2 in
    rpm)
      rpms_download
      exit
    ;;
    k8s)
      k8s_cmd
      exit
    ;;
    code)
      code_download
      exit
    ;;
    go_modules)
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
      code_download
      go_modules_download
      if [ $# -lt 3 ];then
        images_build all
      else
        images_build "$3"
      fi
      exit
    ;;
    images)
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
      rpms_download
      k8s_cmd
      code_download
      go_modules_download
      pip_packages_download
      yaml_download
      images_download
      images_build all
      others_download
      charts_download
      zip_and_move
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
