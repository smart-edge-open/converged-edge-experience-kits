#!/usr/bin/env python3

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation
"""
This tool collects logs from Openness Experience Kit deployment phase for
further deployment analysis and troubleshooting.
It uses accompanying JSON configuration file with a list of files and commands
output that will be gathered and stored in separate log file.
The output of running this script is a tar.gz file with all important
information about nodes, that is uploaded to OEK Controller.
"""

import os
import sys
import subprocess
import tarfile
import json
import re
from datetime import datetime

def read_cfg(path):
    """
    Function reads json configuration file.

    Parameters:
    path (string): JSON configuration file path.

    Returns:
    dict: Tool configuration dictionary. Read config on success,
          empty config otherwise.
    """
    # to avoid script error default git configuration is also available.
    if os.path.isfile(path):
        with open(path, "r") as config_file:
            return json.load(config_file)
    return dict()

def tar_filter_with_exclude(exclude_paths):
    """
    Filters out files which paths match any RE from exclude_paths list

    Parameters:
    exclude_paths (list(RE)): List of regular expresions with excluded paths

    Returs:
    function: Function performing TarInfo base filtering depending on exclude_paths size
    """
    def tar_filter_none(tar_info):
        return tar_info

    def tar_filter(tar_info):
        dir_sep_pos = tar_info.name.find(os.sep)
        if dir_sep_pos > 0:
            file_path_without_base = tar_info.name[dir_sep_pos + 1:]

            for exclude_path in exclude_paths:
                if exclude_path.search(file_path_without_base):
                    print('Excluding: ', tar_info.name)
                    return None
        return tar_info

    if len(exclude_paths) > 0:
        return tar_filter
    return tar_filter_none


def collect_logs(user, host):
    """
    Function creates archive file with Openness experience kit information and
    send it to controller root directory.
    """
    start = (datetime.now()).strftime("%Y_%m_%d_%H_%M_%S")
    file_name = "../%s_Openness_experience_kit_archive.tar.gz" % start
    config = read_cfg("scripts/log_all.json")

    commands = ["git status", "git diff", "git log -n100"]
    if "commands" in config:
        commands = config["commands"]

    exclude_paths = []
    if "excludePaths" in config:
        exclude_paths = [re.compile(excluded_path) for excluded_path in config["excludePaths"]]

    try:
        with tarfile.open(file_name, "w:gz") as tar:
            main_dir = os.path.abspath(os.getcwd())
            tar.add(main_dir, arcname=os.path.basename(main_dir),
                    filter=tar_filter_with_exclude(exclude_paths))
            if os.path.isdir(main_dir + "/.git"):
                for com in commands:
                    path = com.replace(" ", "_") + ".log"
                    with open(path, "w") as log_file:
                        subprocess.run(com,
                                       shell=True,
                                       stdout=log_file,
                                       stderr=subprocess.STDOUT,
                                       check=False,
                                       universal_newlines=True)
                        tar.add(path, arcname=path)
    except OSError as os_error:
        print("ERROR: %s" % os_error)
        return -1

    try:
        user_prefix = ""
        if user != "":
            user_prefix = f"{user}@"


        subprocess.run(
            "scp -C %s scripts/log_collector scripts/log_collector.json %s%s:~"
            % (file_name, user_prefix, host),
            shell=True,
            check=True)

    except subprocess.CalledProcessError as process_error:
        print("Collecting controller logs failed: %s" % process_error)
        print("Please check connection and run: `python3 scripts/log_all.py`")

    return 0


def main():
    """
    Function creates archive file with Openness experience kit information and
    send it to controller root directory.
    """
    with open("inventory/default/inventory.ini", "r") as inventory_file:
        lines = inventory_file.read().split("\n")
        name = lines[lines.index("[controller_group]") + 1].strip()
        controller = [x for x in lines
                      if name in x and len(name) < len(x)][0].split(" ")
        host = [x for x in controller if x.startswith("ansible_host")][0].split("=")[-1]
        if any(item.startswith("ansible_user") for item in controller):
            user = [x for x in controller if x.startswith("ansible_user")][0].split("=")[-1]
        else:
            user = ""

    return collect_logs(user, host)


if __name__ == "__main__":
    sys.exit(main())
