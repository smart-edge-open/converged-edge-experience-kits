#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

vca_dockerio_url="https://download.docker.com/linux/ubuntu/dists/xenial/pool/stable/amd64/containerd.io_1.2.6-3_amd64.deb"
vca_dockercli_url="https://download.docker.com/linux/ubuntu/dists/xenial/pool/stable/amd64/docker-ce-cli_19.03.2~3-0~ubuntu-xenial_amd64.deb"
vca_dockerce_url="https://download.docker.com/linux/ubuntu/dists/xenial/pool/stable/amd64/docker-ce_19.03.2~3-0~ubuntu-xenial_amd64.deb"

vca_dockerio_deb="containerd.io_1.2.6-3_amd64.deb"
vca_dockerce_deb="docker-ce_19.03.2~3-0~ubuntu-xenial_amd64.deb"
vca_dockercli_deb="docker-ce-cli_19.03.2~3-0~ubuntu-xenial_amd64.deb"


wget --no-check-certificate $vca_dockerio_url $vca_dockercli_url $vca_dockerce_url
if [ $? -ne 0 ]; then
   echo "get docker pakcages  failed"
   exit 1
fi

apt-get install iptables -y
apt --fix-broken install -y
apt-get install iptables -y

dpkg -i $vca_dockerio_deb $vca_dockerce_deb $vca_dockercli_deb
if [ $? -ne 0 ]; then
   echo "install docker  failed"
   exit 1
fi

mkdir -p /etc/systemd/system/docker.service.d/
cp -f /root/http-proxy.conf /etc/systemd/system/docker.service.d/
mkdir -p ~/.docker
cp -f /root/config.json /root/.docker/

systemctl enable docker --now
systemctl daemon-reload
systemctl restart docker
