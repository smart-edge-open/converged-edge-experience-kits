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
from datetime import datetime


def read_cfg(path):
    """
    Function reads json configuration file.

    Parameters:
    path (string): JSON configuration file path.

    Returns:
    dict: Tool configuration dictionary. Read config on success,
          default config otherwise.
    """
    # to avoid script error default git configuration is also available.
    config = ["git status", "git diff", "git log -n100"]
    if os.path.isfile(path):
        with open(path, "r") as f:
            config = json.load(f)["commands"]
            return config
    return config


def main():
    """
    Function creates archive file with Openness experience kit information and
    send it to controller root directory.
    """
    start = (datetime.now()).strftime("%Y_%m_%d_%H_%M_%S")
    file_name = "../%s_Openness_experience_kit_archive.tar.gz" % start
    config = read_cfg("scripts/log_all.json")

    with open("inventory.ini", "r") as f:
        lines = f.read().split("\n")
        name = lines[lines.index("[controller_group]") + 1].strip()
        controller = [x for x in lines
                      if name in x and len(name) < len(x)][0].split(" ")
        host = [x for x in controller if "ansible_host" in x][0].split("=")[-1]

    try:
        with tarfile.open(file_name, "w:gz") as tar:
            main_dir = os.path.abspath(os.getcwd())
            tar.add(main_dir, arcname=os.path.basename(main_dir))
            if os.path.isdir(main_dir + "/.git"):
                for com in config:
                    path = com.replace(" ", "_") + ".log"
                    with open(path, "w") as f:
                        subprocess.run(com,
                                       shell=True,
                                       stdout=f,
                                       stderr=subprocess.STDOUT,
                                       check=False,
                                       universal_newlines=True)
                        tar.add(path, arcname=path)
    except OSError as e:
        print("ERROR: %s" % e)
        return -1

    try:
        subprocess.run(
            "scp -C %s scripts/log_collector scripts/log_collector.json root@%s:~"
            % (file_name, host),
            shell=True,
            check=True)

    except subprocess.CalledProcessError as e:
        print("Collecting controller logs failed.")
        print("Please check connection and run: `python3 scripts/log_all.py`")

    return 0


if __name__ == "__main__":
    sys.exit(main())
