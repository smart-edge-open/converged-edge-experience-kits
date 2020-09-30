#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

rm -f /tmp/notifications
while read x y
do
  echo "$x$y" >> /tmp/notifications
done
