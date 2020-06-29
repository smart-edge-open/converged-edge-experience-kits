#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2019-2020 Intel Corporation

source scripts/ansible-precheck.sh
source scripts/task_log_file.sh
source scripts/parse_args.sh

filter="${1:-}"
limit=$(get_limit "${filter}")

ansible-playbook -vv \
    ./on_premises_cleanup.yml \
    --inventory inventory.ini ${limit}
