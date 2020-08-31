#!/usr/bin/python

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

import os, sys, subprocess, StringIO, tarfile, json
from datetime import datetime


def read_cfg(path):
    #to avoid script error default git configuration is also available.
    config = ["git status", "git diff", "git log -n100"]
    if os.path.isfile(path):
        with open(path, "r") as f:
            try:
                config = json.load(f)["commands"]
                f.close()
                return config
            except:
                f.close()
                return config
    return config


if __name__ == "__main__":
    start = (datetime.now()).strftime("%Y_%m_%d_%H_%M_%S")
    file_name = "../%s_Openness_experience_kit_archive.tar.gz" % start
    config = read_cfg("scripts/log_all.json")
    host = ""

    with open("inventory.ini", "r") as f:
        lines = f.read().split("\n")
        f.close()
        host = [v for v in lines if "controller ansibl" in v][0].split("=")[-1]

    with tarfile.open(file_name, "w:gz") as tar:
        try:
            main_dir = os.path.abspath(os.getcwd())
            tar.add(main_dir, arcname=os.path.basename(main_dir))
            if os.path.isdir(main_dir + "/.git"):
                for com in config:
                    out = StringIO.StringIO("")
                    out.write(subprocess.check_output(com.split(" ")))
                    out.seek(0)
                    out_file = tarfile.TarInfo(name="".join(com) + ".log")
                    out_file.size = len(out.buf)
                    tar.addfile(tarinfo=out_file, fileobj=out)
        except:
            tar.close()
            print(
                "ERROR: Openness experience kit archive failed with message: %s"
                % sys.exc_info()[0])
            sys.exit(-1)
        tar.close()

    subprocess.call(["scp", "-C", file_name, "root@{0}:~".format(host)])
    sys.exit(0)
