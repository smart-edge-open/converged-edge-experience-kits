#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2019-2020 Intel Corporation

# Usage:
#  Regular Network Edge mode:
#   ./cleanup_ne.sh -f <flavor>               cleanup both controller & nodes
#   ./cleanup_ne.sh -f <flavor> c[ontroller]  cleanup only controller
#   ./cleanup_ne.sh -f <flavor> n[odes]       cleanup only nodes

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
    echo -e "   $0 -f <flavor> <filter>"
    echo "Available flavors: minimal, $(ls -m flavors -I minimal)"
    exit 1
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
        if [[ -f "${dir}/30_${flavor}_flavor.yml" ]]; then
            rm -f "${dir}/30_${flavor}_flavor.yml"
        fi
    done
fi

limit=""
filter="${1:-}"

playbook="network_edge_cleanup.yml"

if [[ "${flavor}" == central_orchestrator ]]; then
    limit=$(get_limit "c")
else
    limit=$(get_limit "${filter}")
fi

eval ansible-playbook -vv \
    "${playbook}" \
    --inventory inventory.ini "${limit}"
