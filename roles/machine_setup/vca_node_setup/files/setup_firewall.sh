#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

echo 1 > /proc/sys/net/ipv4/ip_forward

# firewalld is inactive, set iptables
systemctl status firewalld.service|grep "Active"|grep "running"
if [ $? -ne 0 ];then
    ## firewalld is inactive, not running, must set iptables
    echo -e "\nWarning: firewalld is inactive\n"
    echo -e "\nBegin to set iptables for agent\n"
   
    ## num of vcad
    num1_vcad=`vcactl blockio list|sed -n '3,$'p|wc -l`
    num1_port=5000
    for i in `seq 1 $num1_vcad`
    do
        ip_vcad="172.32."$i".1"
        iptables -t nat -A PREROUTING -p tcp -m tcp --dport $num1_port -j DNAT --to-destination "$ip_vcad":5000 
        iptables -t nat -A POSTROUTING -s $ip_vcad -d 0/0  -j MASQUERADE
        let num1_port=${num1_port}+1
    done
    ## exit
    echo -e "\nFinish iptables setting\n"
    exit
fi

####
eth_host=`ip route get 8.8.8.8 | grep via | awk '{print $5}'`
num_vcad=`vcactl status | grep Card | wc -l`

## set Host eg, 10.67.118.227
firewall-cmd --permanent --zone=external --change-interface=$eth_host
sleep 1
firewall-cmd --zone=external --add-masquerade --permanent
sleep 1
## add ssh service
firewall-cmd --permanent --zone=public --add-service=ssh
sleep 1
firewall-cmd --permanent --zone=external --add-service=ssh
sleep 1
## enable firewall
firewall-cmd  --reload
sleep 3

## set for each vcad
## node0 , 172.32.1.1, set the vcad network transfer
for i in `seq 1 $num_vcad`
do
    ## get ip for each vcad
    ip_vcad="172.32."$i".1"
    ## set the vcad network transfer
    firewall-cmd --permanent --direct --passthrough ipv4 -t nat POSTROUTING -o $eth_host -j MASQUERADE -s $ip_vcad
    sleep 1
    ## add nat port transfer rule. For vcaa_agent, keep 5000-5020 ports
    ## agent--5000
    firewall-cmd --zone=external --add-forward-port=port=5000:proto=tcp:toport=5000:toaddr=$ip_vcad --permanent 
    sleep 1
    ## http ---8080
    firewall-cmd --zone=external --add-forward-port=port=8080:proto=tcp:toport=8080:toaddr=$ip_vcad --permanent 
    sleep 1
    ## k8s ---6443
    firewall-cmd --zone=external --add-forward-port=port=6443:proto=tcp:toport=6443:toaddr=$ip_vcad --permanent
    sleep 1
    ## k8s ---2379-2380
    firewall-cmd --zone=external --add-forward-port=port=2379-2380:proto=tcp:toport=2379-2380:toaddr=$ip_vcad --permanent
    sleep 1
    ## k8s ---10250
    firewall-cmd --zone=external --add-forward-port=port=10250:proto=tcp:toport=10250:toaddr=$ip_vcad --permanent
    sleep 1
    ## k8s ---10251
    firewall-cmd --zone=external --add-forward-port=port=10251:proto=tcp:toport=10251:toaddr=$ip_vcad --permanent
    sleep 1
    ## k8s ---10252
    firewall-cmd --zone=external --add-forward-port=port=10252:proto=tcp:toport=10252:toaddr=$ip_vcad --permanent
    sleep 1
    ## k8s ---10255
    firewall-cmd --zone=external --add-forward-port=port=10255:proto=tcp:toport=10255:toaddr=$ip_vcad --permanent
    sleep 1
done

## enable firewall
firewall-cmd  --reload
sleep 3
## list-all
firewall-cmd --zone=external --list-all
sleep 1
firewall-cmd --zone=public --list-all
sleep 1
##end
