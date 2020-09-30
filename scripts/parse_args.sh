#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

# Check first parameter given to script and sets Ansible's --limit accordingly.
# If it starts with 'c' ('c', 'controller', 'ctrl', etc.), then '--limit controller_group' is used.
# If it starts with 'n' ('n', 'node', 'nodes', etc.), then '--limit edgenode_group' is used.
get_limit() {
    local arg=${1:-}
    case "$arg" in
        c*) echo "--limit controller_group";;
        n*) echo "--limit edgenode_group";;
        *) echo ""
    esac
}
