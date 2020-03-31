# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

# Check first parameter given to script and sets Ansible's --limit accordingly.
# If it starts with 'c' ('c', 'controller', 'ctrl', etc.), then '--limit controller_group' is used.
# If it starts with 'n' ('n', 'node', 'nodes', etc.), then '--limit edgenode_group' is used.

case "$1" in
    c*) limit_param="--limit controller_group";;
    n*) limit_param="--limit edgenode_group";;
    *) limit_param=""
esac
