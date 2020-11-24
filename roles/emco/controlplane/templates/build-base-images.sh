#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

#########################################################

# build the "base build image" that will be used as the base for all containerized builds & deployments

# if you update Dockerfile.build-base, please bump up the version here so as to not overwrite older base images
# BUILD_BASE_VERSION=1.0

echo "Building build-base container"
docker build -t emco-service-build-base -f build/docker/Dockerfile.build-base .

#########################################################