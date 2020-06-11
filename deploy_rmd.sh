#!/bin/sh

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

set -x
ansible-playbook -i inventory.ini -vv rmd.yml
