#!/usr/bin/python3
# coding: utf-8

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation
""" python script for ceek setup """
import argparse
import logging
import subprocess
import os
import sys
from urllib.parse import urlparse, urlunparse
import yaml

_LOG = None
CEEK_PATH = "ceek"
INVENTORY_DIRECTORY = os.path.join(CEEK_PATH, "inventory", "default")

def make_parser():
    """Create command-line parser object"""
    log_levels = ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")
    levels_str = "{0:s} or {1:s}".format(
        ", ".join(log_levels[:-1]), log_levels[-1])

    parser = argparse.ArgumentParser()

    parser.add_argument(
        "-r", "--repo", action="store", metavar="GIT_REPO", dest="git_repo",
        default="https://github.com/open-ness/converged-edge-experience-kits",
        help="OpenNESS converged edge experience kit repository")
    parser.add_argument(
        "-t", "--token", action="store", metavar="GIT_TOKEN", dest="git_token",
        default="",
        help="git token for accessing private repository")
    parser.add_argument(
        "hosts",
        help="Comma separated IP addresses of edge hosts to provision. First one is always the "
             "controller. If there is only one IP provided then single node cluster is provisioned")
    parser.add_argument(
        "-u", "--user", action="store", metavar="ANSIBLE_USER", dest="ansible_user",
        default="root",
        help="Username used by ansible automation scripts")
    parser.add_argument(
        "-o", "--ceek-vars", action="store", metavar="CEEK_VARS", dest="ceek_vars",
        help="Extra OpenNESS experience kit variables to override the defaults")
    parser.add_argument(
        "-f", "--flavor", action="store", metavar="CEEK_FLAVOR", dest="ceek_flavor",
        help="OpenNESS experience kit flavor")
    parser.add_argument(
        "-l", "--limits", action="store", metavar="ANSIBLE_LIMITS", dest="ansible_limits",
        help="OpenNESS experience kit ansible limits")

    parser.add_argument(
        "-v", "--verbosity", action="store", metavar="LEVEL", dest="verbosity", default="INFO",
        choices=log_levels,
        help="Application diagnostic output verbosity ({0:s})".format(levels_str))
    parser.add_argument(
        "-p", "--log-path", action="store", metavar="LOG_PATH", dest="log_path",
        default="/var/log/ceek_setup.log",
        help="Log file path")

    return parser


def setup_logger(options):
    """Configure Python logging module"""
    log_fmt = "OpenNESS Setup: [%(levelname)s] %(module)s(%(lineno)d): %(message)s"
    ts_fmt = "%Y-%m-%dT%H:%M:%S"

    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter(log_fmt, ts_fmt))
    root_logger = logging.getLogger('')
    root_logger.addHandler(handler)
    root_logger.setLevel(options.verbosity)
    return root_logger


def clone_repository(git_repo, git_token, path):
    """Clone specified git repository"""
    _LOG.info("Cloning %s", git_repo)
    git_url = urlparse(git_repo)
    if git_token:
        git_url = git_url._replace(
            netloc="{}:x-oauth-basic@{}".format(git_token, git_url.netloc))
    try:
        ret = subprocess.run(
            ["/usr/bin/git", "clone", urlunparse(git_url), path], check=True)
        _LOG.info("git finished: %d", ret.returncode)
    except subprocess.CalledProcessError as err:
        _LOG.fatal("\"%s\" failed[%d]: %s",
                   ' '.join(err.cmd), err.returncode, err.output)


def create_inventory(options, inventory_path):
    """Create Ansible inventory.yml file in the specified ceek directory"""

    hosts = options.hosts.split(',')

    cfgyaml = {}

    #Set flavor
    cfgyaml["all"] = {}
    cfgyaml["all"]["vars"] = {}
    cfgyaml["all"]["vars"]["cluster_name"] = "_".join(["ceek", options.ceek_flavor, "cluster"])
    cfgyaml["all"]["vars"]["flavor"] = options.ceek_flavor
    #Enable single node deployment if only one host is provisioned
    cfgyaml["all"]["vars"]["single_node_deployment"] = len(hosts) == 1
    cfgyaml["all"]["vars"]["limit"] = options.ansible_limits

    cfgyaml["controller_group"] = {}
    cfgyaml["controller_group"]["hosts"] = {}
    cfgyaml["controller_group"]["hosts"]["controller"] = {}
    #Set the first host as the controller
    cfgyaml["controller_group"]["hosts"]["controller"]["ansible_host"] = hosts[0]
    cfgyaml["controller_group"]["hosts"]["controller"]["ansible_user"] = options.ansible_user


    cfgyaml["edgenode_group"] = {}
    cfgyaml["edgenode_group"]["hosts"] = {}

    if len(hosts) == 1:
        cfgyaml["edgenode_group"]["hosts"]["node-0"] = {}
        cfgyaml["edgenode_group"]["hosts"]["node-0"]["ansible_host"] = hosts[0]
        cfgyaml["edgenode_group"]["hosts"]["node-0"]["ansible_user"] = options.ansible_user
    else:
        for i, node in enumerate(hosts[1:]):
            node_name = "node-" + str(i)
            cfgyaml["edgenode_group"]["hosts"][node_name] = {}
            cfgyaml["edgenode_group"]["hosts"][node_name]["ansible_host"] = node
            cfgyaml["edgenode_group"]["hosts"][node_name]["ansible_user"] = options.ansible_user

    cfgyaml["edgenode_vca_group"] = {}
    cfgyaml["edgenode_vca_group"]["hosts"] = None

    cfgyaml["ptp_master"] = {}
    cfgyaml["ptp_master"]["hosts"] = None

    cfgyaml["ptp_slave_group"] = {}
    cfgyaml["ptp_slave_group"]["hosts"] = None

    with open(os.path.join(inventory_path, "inventory.yml"), "w") as inv:
        yaml.dump(cfgyaml, inv, sort_keys=False)

    with open(os.path.join(INVENTORY_DIRECTORY, "group_vars", "all", "10-default.yml"), "r") as group_vars:
        cfgvars = yaml.load(group_vars, Loader=yaml.FullLoader)

    #Add token to group_vars
    if options.git_token:
        cfgvars["git_repo_token"] = options.git_token

    #Note: Calico is not supported by Azure
    cfgvars["kubernetes_cnis"] = ["kubeovn"]

    with open(os.path.join(INVENTORY_DIRECTORY, "group_vars", "all", "10-default.yml"), "w") as group_vars:
        yaml.dump(cfgvars, group_vars, sort_keys=False)

def main(options):
    """Script entry function"""
    clone_repository(options.git_repo, options.git_token, CEEK_PATH)
    create_inventory(options, CEEK_PATH)

if __name__ == '__main__':
    OPTIONS = make_parser().parse_args()
    _LOG = setup_logger(OPTIONS)
    sys.exit(main(OPTIONS))
