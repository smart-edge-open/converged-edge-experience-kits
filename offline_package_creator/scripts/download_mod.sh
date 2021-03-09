#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

set -e

PWD=$(pwd)
dirs=$(find . -name go.mod)

for d in $dirs
do
  mod_dir=$(dirname "$d")
  if [[ "$mod_dir" != "./pkg/topology/testdata" ]];then
    pushd "$mod_dir"
    go mod download -x
    popd
  fi
done
