#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2019-2020 Intel Corporation

# Usage:
#  Regular Network Edge mode:
#   ./deploy_ne.sh [-f <flavor>]               deploy both controller & nodes
#   ./deploy_ne.sh [-f <flavor>] c[ontroller]  deploy only controller
#   ./deploy_ne.sh [-f <flavor>] n[odes]       deploy only nodes
#
#  Single-node cluster:
#   ./deploy_ne.sh [-f <flavor>] s[ingle]      deploy single-node cluster playbook

set -eu

source scripts/ansible-precheck.sh
source scripts/task_log_file.sh
source scripts/parse_args.sh

flavor=""
while getopts ":f:" o; do
    case "${o}" in
        f)
            flavor=${OPTARG}
            ;;
        *)
            echo "Invalid flag"
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

# Remove all previous flavors
find "${PWD}/group_vars/" -type l -name "30_*_flavor.yml" -delete

if [[ -z "${flavor}" ]]; then
    echo "No flavor provided"
    echo -e "   $0 [-f <flavor>] <filter>. Available flavors: $(ls -m flavors)"
else
    flavor_path="${PWD}/flavors/${flavor}"
    if [[ ! -d "${flavor_path}" ]]; then
        echo "Flavor ${flavor} does not exist[${flavor_path}]"
        exit 1
    fi

    for f in "${flavor_path}"/*.yml
    do
        fname=$(basename "${f}" .yml)
        dir="${PWD}/group_vars/${fname}"
        if [[ ! -d "${dir}" ]]; then
            echo "${f} does not match a directory in group_vars:"
            ls "${PWD}/group_vars/"
            exit 1
        fi
        ln -sfn "${f}" "${dir}/30_${flavor}_flavor.yml"
    done
fi

limit=""
filter="${1:-}"

if [[ "${filter}" == s* ]]; then
    playbook="single_node_network_edge.yml"
else
    playbook="network_edge.yml"
    limit=$(get_limit "${filter}")
fi

eval ansible-playbook -vv \
    "${playbook}" \
    --inventory inventory.ini "${limit}"

if ! python3 scripts/log_all.py; then
    echo "[Warning] Log collection failed"
fi
