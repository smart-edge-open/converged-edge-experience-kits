#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

net_rule=/etc/udev/rules.d/00-net.rules
# detect VCAC-A cards
NCARDS=`vcactl status | grep Card | wc -l`
if [ "$NCARDS" -le 0 ];then
  echo "No VCAC-A card detected!"
  exit 1
fi
echo "$NCARDS VCAC-A card(s) detected"

# add udev roles to prevent vca virtual interface managed by NetworkManager
rm -f $net_rule
CARDS_NUM=$[NCARDS-1]
for CARD in $(seq 0 $CARDS_NUM)
do
  echo "ACTION==\"add\", SUBSYSTEM==\"net\", KERNEL==\"eth${CARD}\", ENV{NM_UNMANAGED}=\"1\"" >> $net_rule
done
systemctl restart systemd-udevd
vcactl pwrbtn-long 0 0
vcactl pwrbtn-short 0 0
vcactl reset 0 0 --force
systemctl stop firewalld
sleep 10

for CARD in $(seq 0 $CARDS_NUM)
do
  vcactl config 0 0 node-name vcanode0${CARD}
  vcactl boot ${CARD} 0 vcablk0 --force
done
sleep 30
vcactl status
vcactl network ip
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -s 172.32.1.1 -d 0/0 -j MASQUERADE
