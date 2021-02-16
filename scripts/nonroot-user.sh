#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2021 Intel Corporation

node_ip=""
node_name=""
root_password=""
nonroot_user="openness"
nonroot_password="openness"
remote_file_name="create_user_by_script.sh"


while getopts i:r:n:U:P: flag
do
  case "${flag}" in
    i) node_ip=${OPTARG};;
    r) root_password=${OPTARG};;
    n) node_name=${OPTARG};;
    U) nonroot_user=${OPTARG};;
    P) nonroot_password=${OPTARG};;
  esac
done

usage () {
  echo "Usage: $0 -i REMOTE_NODE_IP -r REMOTE_ROOT_PASSWORD"
  echo "      [-n REMOTE_NODE_NAME] [-U NONROOT_USER] [-P NONROOT_PASSWD]"  
}

print_error () {
  echo "No '$1' parameter provided"
  usage
  exit 1
}

validate_vars () {
  [ -z "$node_ip" ] && print_error "-i REMOTE_NODE_IP"
  [ -z "$root_password" ] && print_error "-i REMOTE_NODE_IP"
}

print_vars () {
  echo node_ip "$node_ip"
  echo node_name "$node_name"
  echo root_password "$root_password"
  echo nonroot_user "$nonroot_user"
  echo nonroot_password "$nonroot_password"
  echo remote_file_name "$remote_file_name"
}

create_pass_files () {
  echo "$root_password" > root.txt
  echo "$nonroot_password" > nonroot.txt
}

create_remote_file () {
cat <<-EOF > $remote_file_name
  adduser $nonroot_user
  echo $nonroot_password | passwd $nonroot_user --stdin
  echo "$nonroot_user  ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$nonroot_user
  [ -z "$node_name" ] || grep -q $node_name /etc/hosts || sed -i'.bak' 's/$/ $node_name/' /etc/hosts
EOF
  chmod +x $remote_file_name
}

install_sshpass () {
  which sshpass || yum install sshpass -y
}

send_file () {
  sshpass -f root.txt scp $remote_file_name "$node_ip:~"
}

exec_remote_file () {
  sshpass -f root.txt ssh "$node_ip" "$HOME/$remote_file_name"
}

ssh_copy_id_nonroot () {
  sshpass -f nonroot.txt ssh-copy-id "$nonroot_user@$node_ip"
}

mkdir -p tmp
cd tmp

validate_vars
print_vars
create_pass_files
create_remote_file
install_sshpass
send_file
exec_remote_file
ssh_copy_id_nonroot
