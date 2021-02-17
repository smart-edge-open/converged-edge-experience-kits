```text
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation
```
# Preconditions

The preconditions are:

- There should be at least 40GiB of available storage in the directory you are operating in, you can use this command to view the available space.
```sh
[open@dev offline_package_creator]$ df -h ./
Filesystem               Size  Used Avail Use% Mounted on
/dev/mapper/centos-home  169G   12G  158G   7% /home
```
- CentOS\* 7.8.2003 must be installed on host. It is highly recommended to install the operating system using a minimal ISO image on host.

- The network can connect with internet, such as docker hub, google...etc.

# How to use

## Usage help
```sh
[open@dev offline_package_creator]$ ./offline_package_creator.sh  help
Usage: Use this script as ordinary user, not root
./offline_package_creator.sh options
options:
        help         show help
        all          download all and zip it
        rpm          download rpm only
        k8s          download k8s commands only
        code         download code from github only
        go_modules   download go_modules
        pip_packages download pip packages
        yaml         download yaml fils only
        images       download docker images only
        build        build docker images
                     cli,common,interfaceservice,biosfw,tas,sriov_cni,sriov_network,bb_config,rmd,collectd_fpga;all(default)
                     like: ./offline_package_creator.sh build common
        charts       download charts file only
        others       download other file only
        zip          zip the directory of opcdownloads and mv it to a target directory
```

## Use steps

OPC is a download script for OpenNess flexran flavor, which mainly includes rpms, pip packages and docker images; In addition, it also includes compiled specified docker images such as eaa, biosfw...etc.

### Step 1
No root user.
If there is not normal user on your machine, please reference below:
```sh
[root@dev ~]# useradd open
[root@dev ~]# passwd open
New password:
Retype new password:
passwd: all authentication tokens updated successfully.
[root@dev ~]# chmod -v u+w /etc/sudoers
[root@dev ~]# vi /etc/sudoers
```
Add one line into the file, /etc/sudoers

root ALL=(ALL) ALL # Existing

open ALL=(ALL) ALL # new line

To configure first and the configuration file is located in "scripts/initrc"


| Option | Values | Description |
| ------ | ------ | ----------- |
| GITHUB_USERNAME | must not be nil | Your name of gitHub account |
| GITHUB_TOKEN | must not be nil | The token of accessing github.[How to set token](https://docs.github.com/en/free-pro-team@latest/github/authenticating-to-github/creating-a-personal-access-token) |
| HTTP_PROXY | must not be nill | Proxy |
| HTTPS_PROXY | must not be nill | Prox for HTTPS |
| GIT_PROXY | must not be nill | In most cases, the value is the same as HTTP proxy |
| BUILD_BIOSFW | enable\|disable | Enable build the image of 'biosfw' (default: disable), if enable it, you should set the value of 'DIR_OF_BIOSFW_ZIP' |
| BUILD_OPAE | enable\|disable | Enable build the image of 'opae' (default: disable), if enable it, you should set the value of 'DIR_OF_OPAE_ZIP' |
| BUILD_COLLECTD_FPGA | enable\|disable | Enable build the image of 'collectd_fpga_plugin' (default: disable), if enable it, you should set the value of 'DIR_OF_FPGA_ZIP' |

For example:
```shell
[worknode@worknode offline_package_creator]$ cat scripts/initrc
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

# Source global definitions
# Declare a dictionary.
declare -A SOURCES_TABLES
SOURCES_TABLES=(
[python3]='python3' \
[pip3]='python3-pip' \
[wget]='wget' \
[dockerd]='docker-ce' \
[git]='git' \
[patch]='patch' \
[pip]='python2-pip-8.1.2-14.el7.noarch' \
[curl-config]='libcurl-devel' \
)

sudo_cmd() {
  echo $PASSWD | sudo -S $@
}

# otcshare token
GITHUB_USERNAME="name"
GITHUB_TOKEN="1111234rr47af7f1130d385f912fcfafdafdaf"

# User add ones
HTTP_PROXY="http://example.com:1234" #Add proxy first
HTTPS_PROXY="http://example.com:2345" #Add proxy for HTTPS
GIT_PROXY="http://example.com:3456"

# location of OPAE_SDK_1.3.7-5_el7.zip
BUILD_OPAE=enable
DIR_OF_OPAE_ZIP="/home/worknode/download"

# location of syscfg_package.zip
BUILD_BIOSFW=enable
DIR_OF_BIOSFW_ZIP="/home/worknode/download"

# location of the zip packages for collectd-fpga
BUILD_COLLECTD_FPGA=enable
DIR_OF_FPGA_ZIP="/home/worknode/download"
```
### Step 2
if http proxy needed to access internet, you need to add http proxy into the file of "/etc/yum.conf"
```sh
[open@dev offline_package_creator]$ sudo echo "proxy=http://proxy.example.org:3128" >> /etc/yum.conf
[sudo] password for open:
[open@dev offline_package_creator]$ cat /etc/yum.conf
[main]
cachedir=/var/cache/yum/$basearch/$releasever
keepcache=0
debuglevel=2
logfile=/var/log/yum.log
exactarch=1
obsoletes=1
gpgcheck=1
installonly_limit=5
bugtracker_url=http://bugs.centos.org/set_project.php?project_id=23&ref=http://bugs.centos.org/bug_report_page.php?category=yum
distroverpkg=centos-release


#  This is the default, if you make this bigger yum won't see if the metadata
# is newer on the remote and so you'll "gain" the bandwidth of not having to
# download the new metadata and "pay" for it by yum not having correct
# information.
#  It is esp. important, to have correct metadata, for distributions like
# Fedora which don't keep old packages around. If you don't like this checking
# interupting your command line usage, it's much better to have something
# manually check the metadata once an hour (yum-updatesd will do this).
# metadata_expire=90m

# PUT YOUR REPOS HERE OR IN separate files named file.repo
# in /etc/yum.repos.d
proxy=http://proxy.example.org:3128
```

### Step 3

```sh
sudo chown -R $USER:$USER ./*
./offline_package_creator.sh all
```
If the current user is not in the docker group and the kernel version is not "3.10.0-1127.19.1.rt56.1116.el7.x86_64", the machine will restart twice.

The one is for making new docker user effective, another is for updating the kernel.

After rebooting, run the command of "./offline_package_creator.sh all".

At the end, the script will download all the files defined in the [pdl_flexran.yml](https://github.com/otcshare/openness-experience-kits/blob/master/offline_package_creator/package_definition_list/pdl_flexran.yml) and build other necessary images, then copy them to a designated directory. Once the script is finished executing, the user should expect three files under the `openness-experience-kits/roles/offline_roles/unpack_offline_package/files` directory:
```shell
[root@dev offline_package_creator]# ls -l ../roles/offline_roles/unpack_offline_package/files
total 7888744
-rw-r--r--. 1 root root         33 Dec 12 09:11 checksum.txt
-rw-r--r--. 1 root root 8037916377 Dec 12 09:12 opcdownloads.tar.gz
-rw-r--r--. 1 root root   40146215 Dec 12 09:12 prepackages.tar.gz
-rw-r--r--. 1 root root        222 Dec 12 09:12 README
```
