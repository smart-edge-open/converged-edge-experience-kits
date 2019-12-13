#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2019 Intel Corporation

source scripts/ansible-precheck.sh

ansible-playbook -vv \
    ./ne_cleanup.yml \
    --inventory inventory.ini
