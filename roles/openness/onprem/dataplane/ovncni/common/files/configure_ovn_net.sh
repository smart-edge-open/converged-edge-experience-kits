#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

set -e

Cluster_Router="cluster-router"
Cluster_Switch="cluster-switch"
Cluster_Subnet="10.100.0.0"
Cluster_Mask=16
Cluster_Gateway="10.100.0.1"

Node_Switch="node-switch"
Node_Subnet="10.20.0.0"
Node_Mask=16
Node_Gateway="10.20.0.1"
Node_Port="ovn-local"
OVN_NB_DB_PATH="/usr/etc/openvswitch/ovnnb_db.db"
ME="--may-exist"

# AddOVNNetwork switch subnet mask gw
function AddOVNNetwork {
    switch="${1}"
    subnet="${2}"
    mask="${3}"
    gw="${4}"
    
    rp="${Cluster_Router}-to-${switch}"
    lp="${switch}-to-${Cluster_Router}"

    # Add a router port to the cluster router if it does not yet exist
    # --may-exist is not enough as the MAC is random
    if ! ovn-nbctl lrp-get-enabled "${rp}"; then
        MAC="0e:00:$(openssl11 rand -hex 4 | sed 's/\(..\)/\1:/g; s/:$//')"
        ovn-nbctl "${ME}" lrp-add "${Cluster_Router}" "${rp}" "${MAC}" "${gw}/${mask}"
    fi
    # Create logical switch
    ovn-nbctl "${ME}" ls-add "${switch}" -- \
        set logical_switch "${switch}" other_config:subnet="${subnet}/${mask}" -- \
        set logical_switch "${switch}" other_config:gateway="${gw}" -- \
        set logical_switch "${switch}" other_config:exclude_ips="${gw}" -- \
        "${ME}" acl-add "${switch}" to-lport 1000 ip4.src=="${Node_Subnet}/${Node_Mask}" allow-related

    # Add the gateway port to the switch
    mac=$(ovn-nbctl get logical_router_port "${rp}" mac | tr -d '"')
    ovn-nbctl "${ME}" lsp-add "${switch}" "${lp}" -- \
        set logical_switch_port "${lp}" type=router -- \
        set logical_switch_port "${lp}" options:router-port="${rp}" -- \
        set logical_switch_port "${lp}" addresses=\""${mac}"\"
}


#----------- Cluster Init -----------
if [ -f "${OVN_NB_DB_PATH}" ]; then
    # Controller only
    echo "Initializing cluster network"

    ovn-nbctl "${ME}" lr-add "${Cluster_Router}"
    AddOVNNetwork "${Cluster_Switch}" "${Cluster_Subnet}" "${Cluster_Mask}" "${Cluster_Gateway}"
    AddOVNNetwork "${Node_Switch}" "${Node_Subnet}" "${Node_Mask}" "${Node_Gateway}"
    #----------- Local breakout Init -----------
    # Add local-ovs-phy port to local switch
    ovn-nbctl "${ME}" ls-add local

    # Add local-ovs-phy port to local switch
    ovn-nbctl "${ME}" lsp-add local local-ovs-phy

    # Configure local-ovs-phy port
    ovn-nbctl lsp-set-addresses local-ovs-phy unknown
    ovn-nbctl lsp-set-type local-ovs-phy localnet
    ovn-nbctl lsp-set-options local-ovs-phy network_name=local-network
    #-------------------------------------------

    # Configure DHCP options
    if [[ ! $(ovn-nbctl find dhcp_options cidr="${Cluster_Subnet}/${Cluster_Mask}") ]]; then
        mac=$(ovn-nbctl get logical_router_port "${Cluster_Router}-to-${Cluster_Switch}" mac | tr -d '"')
        ovn-nbctl create dhcp_options cidr="${Cluster_Subnet}/${Cluster_Mask}" \
            options="\"lease_time\"=\"3600\" \"router\"=\"${Cluster_Gateway}\" \"server_id\"=\"${Cluster_Gateway}\" \"server_mac\"=\"${mac}\""
    fi
fi
#------------------------------------

#----------- Node Init -----------
# Add new node port to node switch
p="$HOSTNAME"
ovn-nbctl "${ME}" lsp-add "${Node_Switch}" "${p}" -- \
    lsp-set-addresses "${p}" dynamic 

# Add routing entry for the defult node IP
nodeIP=$(ip route get 1 | awk '{print $NF;exit}')
data=$(ovn-nbctl wait-until logical_switch_port "${p}" dynamic_addresses!=[] -- get logical_switch_port "${p}" dynamic-addresses | tr -d '"')
portIP=$(echo "${data}" | awk '{ print $2 }')
portMAC=$(echo "${data}" | awk '{ print $1 }')
ovn-nbctl "${ME}" --policy=dst-ip lr-route-add "${Cluster_Router}" "${nodeIP}" "${portIP}"

# Configure local ovs port
ovs-vsctl "${ME}" add-port br-int "${Node_Port}" -- \
    set interface "${Node_Port}" type=internal -- \
    set interface "${Node_Port}" external_ids:iface-id="${p}"

# Configure host part of the just created interface

ip addr flush dev "${Node_Port}"
ip addr add "${portIP}/${Node_Mask}" dev "${Node_Port}"
ip link set dev "${Node_Port}" address "${portMAC}"
ip link set dev "${Node_Port}" up
ip route add "${Cluster_Subnet}/${Cluster_Mask}" via "${Node_Gateway}"


ping "${Node_Gateway}" -c 1
#---------------------------------

if [ ! -f "${OVN_NB_DB_PATH}" ]; then
    # Node only
    #----------- Local breakout Init -----------
    ovs-vsctl set open . external-ids:ovn-bridge-mappings=local-network:br-local
    # Add bridge local
    ovs-vsctl "${ME}" add-br br-local
    #-------------------------------------------
fi
