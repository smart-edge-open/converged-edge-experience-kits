#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation
set -eo pipefail

if [[ $# -eq 0 ]] ; then
   echo ""
   echo "Usage: $0 <cn_name> : give cn name as server ip address" 
   echo -e "Example:"
   echo -e "    $0 192.168.1.1" 
   exit 1 # Exit with help
fi
echo "Generate Docker registry certificate"

root_cn_name="docker-registry"
server_cn_name=$1

shopt -s expand_aliases
alias openssl=openssl11

if ! openssl version | awk '$2 ~ /(^0\.)|(^1\.(0\.|1\.0))/ { exit 1 }'; then
   echo "Not supported openssl:"
   openssl version
fi

echo "Generating RootCA Key and Cert:"
openssl ecparam -genkey -name secp384r1 -out "ca.key"

openssl req -key "ca.key" -new -x509 -days 1000 -subj "/CN=$root_cn_name" -out "ca.crt" 

echo "Generating Server Key and Cert:"
openssl ecparam -genkey -name secp384r1 -out "server.key"

openssl req -new -key "server.key"  -out "server.csr" -subj "/CN=$server_cn_name"
rm -f extfile.cnf
echo "subjectAltName = IP.1:$server_cn_name" >> extfile.cnf

echo "Generate server.cert for  registry server  from root ca.key and ca.crt"
openssl x509 -req -extfile extfile.cnf -in "server.csr" -CA "ca.crt" -CAkey "ca.key" -days 1000 -out "server.cert" -CAcreateserial

echo "Generate Master Node  registry access client.key and client.csr"
openssl req -new -sha256 -nodes -out client.csr -newkey rsa:2048 -keyout client.key -subj "/CN=$server_cn_name"

echo "Generate client.cert for  Master Node  from root ca.key and ca.crt"

openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out client.cert -days 1000

