# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

FROM centos:7.6.1810

ENV http_proxy=$http_proxy
ENV https_proxy=$https_proxy

RUN yum install -y gcc gcc-c++ cmake make autoconf automake libxml2 libxml2-devel json-c-devel boost ncurses ncurses-devel ncurses-libs boost-devel libuuid libuuid-devel python2-jsonschema doxygen hwloc-devel libpng12 rsync openssl-devel bc python-devel python-libs python-sphinx openssl unzip which wget python36 epel-release flex bison libtool pkgconfig git patch OpenIPMI ipmitool OpenIPMI-devel yajl yajl-devel protobuf-c protobuf-c-devel libmicrohttpd libmicrohttpd-devel
RUN easy_install pip && pip install intelhex

# RT repo
RUN wget http://linuxsoft.cern.ch/cern/centos/7/rt/CentOS-RT.repo -O /etc/yum.repos.d/CentOS-RT.repo
RUN wget http://linuxsoft.cern.ch/cern/centos/7/os/x86_64/RPM-GPG-KEY-cern -O /etc/pki/rpm-gpg/RPM-GPG-KEY-cern

# install kernel sources to compile DPDK
RUN export isRT=$(uname -r | grep rt -c) && if [ $isRT = "1" ] ; then yum install -y "kernel-rt-devel-uname-r == $(uname -r)"; else yum install -y "kernel-devel-uname-r == $(uname -r)"; fi
RUN mkdir -p /lib/modules/$(uname -r)
RUN ln -s /usr/src/kernels/$(uname -r) /lib/modules/$(uname -r)/build

#install PMU collectd dependencies
WORKDIR /root
RUN git clone https://github.com/andikleen/pmu-tools.git

WORKDIR /root/pmu-tools/jevents
RUN make
RUN make install

#install RDT collectd dependencies
WORKDIR /root
COPY rdt_gcc_version.patch .
RUN git clone https://github.com/01org/intel-cmt-cat.git

WORKDIR /root/intel-cmt-cat
RUN patch -p1 -i ../rdt_gcc_version.patch
RUN make
RUN make install PREFIX=/usr

WORKDIR /root/collectd_plugin
COPY fpga_telemetry_plugin.patch .

#clone the collectd repostitory
RUN git clone --branch collectd-5.11.0 https://github.com/collectd/collectd.git

#Apply FPGA Plugin patch
WORKDIR /root/collectd_plugin/collectd
RUN patch -p1 -i ../fpga_telemetry_plugin.patch

#Build collectd
RUN ./build.sh
RUN ./configure --enable-intel_pmu --enable-intel_rdt --enable-ipmi --enable-ovs_stats --enable-write_prometheus --prefix=/root/collectd_plugin/collectd_install PACKAGE_VERSION=5.11.0
RUN make
RUN make -j install

#copy packages
WORKDIR /root

COPY n3000-1-3-5-beta-rte-setup.zip .
COPY n3000-1-3-5-beta-cfg-2x2x25g-setup.zip .

#unzip packages
RUN unzip n3000-1-3-5-beta-rte-setup.zip
RUN unzip n3000-1-3-5-beta-cfg-2x2x25g-setup.zip

#make scripts executable
RUN chmod +x n3000-1.3.5-beta-rte-setup.sh
RUN chmod +x n3000-1.3.5-beta-cfg-2x2x25G-setup.sh

#install OPAE packages
RUN echo "proxy=$http_proxy/" | tee -a /etc/yum.conf
RUN yum clean expire-cache
RUN ./n3000-1.3.5-beta-rte-setup.sh -y --owner root
RUN source /root/intelrtestack/bin/init_env.sh

#install PAC N3000 configuration
RUN ./n3000-1.3.5-beta-cfg-*-setup.sh -y

#copy module check script
COPY check_if_modules_loaded.sh .
