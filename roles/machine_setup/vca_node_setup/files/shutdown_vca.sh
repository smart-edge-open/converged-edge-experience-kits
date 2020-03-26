#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

vcactl pwrbtn-long 0 0
vcactl pwrbtn-short 0 0
vcactl reset 0 0 --force
