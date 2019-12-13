#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2019 Intel Corporation

source scripts/ansible-precheck.sh
source scripts/task_log_file.sh

ansible-playbook -vv \
    ./onprem_node.yml \
    --inventory inventory.ini

