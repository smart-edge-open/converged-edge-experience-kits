# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

#!/bin/python3
# coding:utf-8

'''
This is a funcion to get yum pakcages name list from OEK
'''

import os
from configparser import ConfigParser
from jinja2 import Template
from yaml import safe_load

curPath = os.path.dirname(os.path.realpath(__file__))
if os.path.exists(curPath + '/../../../.git'):
    CWD = '../../'
    EDGENODE_GROUP_FILE = "inventory/default/group_vars/edgenode_group/10-open.yml"
else:
    CWD = '../'
    EDGENODE_GROUP_FILE = "inventory/default/group_vars/edgenode_group/10-default.yml"

os.chdir(CWD)
CONFIG_FILE = "ansible.cfg"

config = ConfigParser()
config.read(CONFIG_FILE)
dirs = config.get("defaults", "roles_path").split(':')

class ObjectPackage:
    """ yum name class
    """
    def __init__(self):
        """ init
        """
        self._yumlist = []

    def get_yumlist(self):
        """ export yum package name
        """
        return self._yumlist

    def get_and_save(self, dir_name):
        """ get yum package name
        """
        global_vars = {}

        # not support
        if "local_fileshare_server" in dir_name:
            return
        if "vca_host_setup" in dir_name:
            return
        if "init_app_acc100" in dir_name:
            return
        if "ptp/common/" in dir_name:
            return
        if not os.path.exists(dir_name + 'defaults'):
            return

        with open(EDGENODE_GROUP_FILE, 'r') as fd:
            groups_vars = safe_load(fd.read())
        global_vars.update(groups_vars)
        with open(dir_name + "defaults/main.yml", 'r') as fd:
            temp1 = fd.read()
            global_vars.update(safe_load(temp1))
            parse1 = Template(temp1).render(global_vars)

        groups_vars.update(safe_load(parse1))

        subcmd = "grep \"  yum:\" " + dir_name + " -rA 2 | grep -v \"cleanup.yml\" | \
        grep -v \"uninstall.yml\" | grep \"name:\" | awk \'{$1=\"\";print $0}\' > /tmp/nameList.txt"
        if os.system(subcmd) != 0:
            return
        with open("/tmp/nameList.txt", 'r') as fd:
            done0 = 0
            while not done0:
                line = fd.readline()
                if line != '':
                    temp2 = line.strip('\n')
                    parse2 = Template(temp2).render(groups_vars)
                    self._yumlist = self._yumlist + safe_load(parse2)['name'].split(',')
                else:
                    done0 = 1

if __name__ == '__main__':
    YUMSTRING = ""
    obj = ObjectPackage()
    for tmpdir in dirs:
        if not os.path.exists(tmpdir):
            continue

        cmd = "grep \"  yum:\" " + tmpdir + " -rn | sed 's/tasks.*//g' | uniq > /tmp/opcYumList.txt"
        if os.system(cmd) != 0:
            continue

        with open("/tmp/opcYumList.txt", 'r') as f:
            DONE = 0
            while not DONE:
                subDir = f.readline()
                if subDir != '':
                    subDir = subDir.strip('\n')
                    obj.get_and_save(subDir)
                else:
                    DONE = 1
    for name in list(set(obj.get_yumlist())):
        if name:
            YUMSTRING = YUMSTRING + name + " "

    print(YUMSTRING)
