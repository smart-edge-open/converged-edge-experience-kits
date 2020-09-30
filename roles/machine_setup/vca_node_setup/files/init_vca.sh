#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

net_rule=/etc/udev/rules.d/00-net.rules
# detect VCAC-A cards
NCARDS=$(vcactl status | grep -c Card)
if [ "$NCARDS" -le 0 ];then
  echo "No VCAC-A card detected!"
  exit 1
fi
echo "$NCARDS VCAC-A card(s) detected"

# add udev roles to prevent vca virtual interface managed by NetworkManager
rm -f $net_rule
CARDS_NUM=$((NCARDS-1))
for CARD in $(seq 0 $CARDS_NUM)
do
  echo "ACTION==\"add\", SUBSYSTEM==\"net\", KERNEL==\"eth${CARD}\", ENV{NM_UNMANAGED}=\"1\"" >> $net_rule
done
systemctl restart systemd-udevd

for CARD in $(seq 0 $CARDS_NUM)
do
  vcactl pwrbtn-long "${CARD}" 0
  vcactl pwrbtn-short "${CARD}" 0
  vcactl reset "${CARD}" 0 --force
done
sleep 10

for CARD in $(seq 0 $CARDS_NUM)
do
  vcactl boot "${CARD}" 0 vcablk0 --force
done
sleep 30

vcactl status
vcactl network ip
