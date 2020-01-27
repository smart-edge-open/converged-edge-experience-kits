#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2019 Intel Corporation

source scripts/ansible-precheck.sh
source scripts/task_log_file.sh
source scripts/parse_args.sh

ansible-playbook -vv \
    ./on_premises.yml \
    --inventory inventory.ini ${limit_param}
