# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

FROM centos:7.9.2009

ENV http_proxy=$http_proxy
ENV https_proxy=$https_proxy

RUN yum install -y gcc gcc-c++ cmake make autoconf automake libxml2 libxml2-devel json-c-devel boost ncurses ncurses-devel ncurses-libs boost-devel libuuid libuuid-devel python2-jsonschema doxygen hwloc-devel libpng12 rsync openssl-devel bc python-devel python-libs python-sphinx openssl unzip which wget python36 epel-release flex bison libtool pkgconfig git patch OpenIPMI ipmitool OpenIPMI-devel yajl yajl-devel protobuf-c protobuf-c-devel libmicrohttpd libmicrohttpd-devel
RUN curl https://bootstrap.pypa.io/pip/2.7/get-pip.py -o get-pip.py
RUN python get-pip.py
RUN pip install --upgrade pip==20.3.3
RUN pip install intelhex

# RT repo
RUN wget http://linuxsoft.cern.ch/cern/centos/7.9.2009/rt/CentOS-RT.repo -O /etc/yum.repos.d/CentOS-RT.repo
RUN wget http://linuxsoft.cern.ch/cern/centos/7.9.2009/os/x86_64/RPM-GPG-KEY-cern -O /etc/pki/rpm-gpg/RPM-GPG-KEY-cern

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

#copy package
WORKDIR /root

COPY OPAE_SDK_1.3.7-5_el7.zip .

#unzip package
RUN unzip OPAE_SDK_1.3.7-5_el7.zip

#install OPAE packages
RUN echo "proxy=$http_proxy" | tee -a /etc/yum.conf
RUN yum clean expire-cache
RUN bash -c 'cd OPAE/installation_packages && yum localinstall -y \
    opae.admin-1.0.3-2.el7.noarch.rpm \
    opae-libs-1.3.7-5.el7.x86_64.rpm opae-tools-1.3.7-5.el7.x86_64.rpm \
    opae-tools-extra-1.3.7-5.el7.x86_64.rpm \
    opae-intel-fpga-driver-2.0.1-10.x86_64.rpm \
    opae-devel-1.3.7-5.el7.x86_64.rpm'

#copy module check script
COPY check_if_modules_loaded.sh .
