#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

sudo python /pmd/ovs_pmd_stats.py --socket-pid-file /var/run/openvswitch/ovs-vswitchd.pid
