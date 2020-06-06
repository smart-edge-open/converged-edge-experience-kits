# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

FROM centos:7.6.1810 AS builder

ENV http_proxy=$http_proxy
ENV https_proxy=$https_proxy
ENV INIH_PATH=/root/bbdev_config/inih/extra

RUN yum install -y git build-essential cmake gcc-c++ make

WORKDIR /root/bbdev_config
COPY bbdev_config_service .

RUN git clone -b r47 https://github.com/benhoyt/inih
RUN cd inih/extra && make -f Makefile.static && cp ../ini.h .
RUN make

FROM centos:7.6.1810

RUN yum install -y sudo

ARG username=fpga_config
ARG user_dir=/home/$username

RUN useradd -d $user_dir -m -s /bin/bash $username
RUN groupadd sudo
RUN usermod -aG sudo $username
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

USER $username
WORKDIR $user_dir

COPY --from=builder /root/bbdev_config/config_bbdev .
