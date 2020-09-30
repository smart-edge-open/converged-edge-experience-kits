#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

echo 1 > /proc/sys/net/ipv4/ip_forward

# firewalld is inactive, set iptables
systemctl status firewalld.service|grep "Active"|grep "running"
if [ $? -ne 0 ];then
    ## firewalld is inactive, exit
    echo -e "\ERROR: firewalld is inactive\n"
    exit 1
fi

## get number of VCAC-A cards
eth_host=$(ip route get 8.8.8.8 | grep via | awk '{print $5}')

## add interfaces eth0 (VCAC-A) to internal zone
firewall-cmd --permanent --zone=internal --change-interface=eth0
## enable masquerading for public zone
firewall-cmd --permanent --zone=public --add-masquerade
## enable masquerading for internal zone
firewall-cmd --permanent --zone=internal --add-masquerade
# set NAT & forwarding rules
firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -o "$eth_host" -j MASQUERADE
firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i eth0 -o "$eth_host" -j ACCEPT
firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i "$eth_host" -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT

## reload firewall
firewall-cmd --reload
systemctl restart firewalld

## list-all
firewall-cmd --zone=public --list-all
firewall-cmd --zone=internal --list-all
##end
