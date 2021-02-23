#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

NCARDS=$(vcactl status | grep -c Card)
if [ "$NCARDS" -le 0 ];then
  echo "No VCAC-A card detected!"
  exit 1
fi

for CARD in $(seq 0 $((NCARDS-1)))
do
  vcactl pwrbtn-long "${CARD}" 0
  vcactl pwrbtn-short "${CARD}" 0
  vcactl reset "${CARD}" 0 --force
done
