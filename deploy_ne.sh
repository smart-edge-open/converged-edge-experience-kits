#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2019-2020 Intel Corporation

# Usage:
#  Regular Network Edge mode:
#   ./deploy_ne.sh               deploy both controller & nodes
#   ./deploy_ne.sh c[ontroller]  deploy only controller
#   ./deploy_ne.sh n[odes]       deploy only nodes
#
#  Single-node cluster:
#   ./deploy_ne.sh s[ingle]      deploy single-node cluster playbook

set -eu

source scripts/ansible-precheck.sh
source scripts/task_log_file.sh
source scripts/parse_args.sh

filter=${1:-}
limit=""

if [[ "${filter}" == s* ]]; then
    playbook="single_node_network_edge.yml"
else
    playbook="network_edge.yml"
    limit=$(get_limit ${filter})
fi

ansible-playbook -vv \
    "${playbook}" \
    --inventory inventory.ini ${limit}
