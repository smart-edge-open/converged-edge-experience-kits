```text
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation
```
# Machine describe
OS: CentOS Linux release 7.8.2003 (Core)

# How to use

## Use steps

OPC is a download script, which mainly includes rpms, pip packages and docker images; in addition, it also includes compiling specified docker images.

Such as eaa,interfaceservice,biosfw,tas,sriov_cni,sriov_network,bb_config,rmd,collectd_fpga.

No root user.
To configure first and the configuration file is located in "scripts/initrc"


| Option | Values | Description |
| ------ | ------ | ----------- |
| BUILD_BIOSFW | enable\|disable | Enable build the image of 'biosfw' (default: disable), if enable it, you should set the value of 'DIR_OF_BIOSFW_ZIP' |
| BUILD_OPAE | enable\|disable | Enable build the image of 'opae' (default: disable), if enable it, you should set the value of 'DIR_OF_OPAE_ZIP' |
| BUILD_BB_CONFIG | enable\|disable | Enable build the image of 'bb_config' (default: disable), if enable it, you should set the value of 'DIR_BBDEV_CONFIG' |
| BUILD_COLLECTD_FPGA | enable\|disable | Enable build the image of 'collectd_fpga_plugin' (default: disable), if enable it, you should set the value of 'DIR_OF_FPGA_ZIP' |

```sh
cp ../roles/telemetry/collectd/controlplane/files/* ./file/collectd
bash offline_package_creator.sh all
```
Maybe the machine will be restarted twice!
The one is for making docker user effective, another is for updating the kernel.

After rebooting, run the command of "bash offline_package_creator.sh all".
