#!/usr/bin/python3
# coding: utf-8

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation
""" python script for oek setup """
import argparse
import logging
import subprocess
import os
import configparser
import sys
from urllib.parse import urlparse, urlunparse
from pathlib import Path
import glob

_LOG = None
OEK_PATH = "oek"

def make_parser():
    """Create command-line parser object"""
    log_levels = ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")
    levels_str = "{0:s} or {1:s}".format(
        ", ".join(log_levels[:-1]), log_levels[-1])

    parser = argparse.ArgumentParser()

    parser.add_argument(
        "-r", "--repo", action="store", metavar="GIT_REPO", dest="git_repo",
        default="https://github.com/open-ness/openness-experience-kits",
        help="OpenNESS experience kit repository")
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
        "-o", "--oek-vars", action="store", metavar="OEK_VARS", dest="oek_vars",
        help="Extra OpenNESS experience kit variables to override the defaults")
    parser.add_argument(
        "-f", "--flavor", action="store", metavar="OEK_FLAVOR", dest="oek_flavor",
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
        default="/var/log/oek_setup.log",
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


def create_inventory(options, oek_path):
    """Create Ansible inventory.ini file in the specified oek directory"""
    cfg = configparser.ConfigParser(allow_no_value=True)
    cfg['all'] = {}
    cfg['edgenode_group'] = {}
    cfg['edgenode_vca_group'] = {}
    cfg['controller_group'] = {}

    hosts = options.hosts.split(',')

    cfg['all']["ctrl ansible_ssh_user={} ansible_host={}".format(
        options.ansible_user, hosts[0])] = None
    cfg['controller_group']['ctrl'] = None

    if len(hosts) == 1:
        _LOG.info("Single node deployment")
        cfg['all']["node-0 ansible_ssh_user={} ansible_host={}".format(
            options.ansible_user, hosts[0])] = None
        cfg['edgenode_group']["node-0"] = None
    else:
        for i, node in enumerate(hosts[1:]):
            cfg['all']["node-{} ansible_ssh_user={} ansible_host={}".format(
                i, options.ansible_user, node)] = None
            cfg['edgenode_group']["node-{}".format(i)] = None

    with open(os.path.join(oek_path, "inventory.ini"), "w") as inv:
        cfg.write(inv)


def main(options):
    """Script entry function"""
    clone_repository(options.git_repo, options.git_token, OEK_PATH)
    create_inventory(options, OEK_PATH)

    # Clean previous flavor links
    for flavor in glob.glob(os.path.join(OEK_PATH, "group_vars", "*", "30_*_flavor.yml")):
        if os.path.islink(flavor):
            os.unlink(flavor)

    if options.oek_flavor:
        flavor_path = os.path.join(OEK_PATH, "flavors", options.oek_flavor)
        if not (os.path.exists(flavor_path) and os.path.isdir(flavor_path)):
            _LOG.fatal("Failed to find flavor directory %s", flavor_path)
        for flavor in Path(flavor_path).iterdir():
            group_name = flavor.stem
            dst_dir = os.path.join(OEK_PATH, "group_vars", group_name)
            if not (os.path.exists(dst_dir) and os.path.isdir(dst_dir)):
                _LOG.fatal(
                    "Failed to find group_vars directory %s", dst_dir)
            dst = Path(os.path.join(
                dst_dir, "30_{}_flavor.yml".format(options.oek_flavor)))
            dst.symlink_to(flavor.resolve())

    command = ["ansible-playbook", "-vv"]
    playbook = os.path.join(OEK_PATH, "network_edge.yml")
    if len(options.hosts.split(',')) == 1:
        playbook = os.path.join(OEK_PATH, "single_node_network_edge.yml")
    command.append(playbook)
    command.extend(["--inventory", os.path.join(OEK_PATH, "inventory.ini")])
    if options.ansible_limits:
        command.extend(["--limit", options.ansible_limits])
    if options.oek_vars:
        command.extend(["--extra-vars", options.oek_vars])
    if options.git_token:
        command.extend(
            ["--extra-vars", "git_repo_token={}".format(options.git_token)])

    try:
        _LOG.debug("Running '%s'", " ".join(command))
        subprocess.run(command, check=True)
        _LOG.info(
            "Ansible finished successfully on following hosts(First IP is of controller)")
        _LOG.info(options.hosts)
    except subprocess.CalledProcessError as err:
        _LOG.error("Installation failed(%d)", err.returncode)
        _LOG.fatal("\"%s\" failed[%d]: %s",
                   ' '.join(err.cmd), err.returncode, err.output)
        sys.exit(err.returncode)


if __name__ == '__main__':
    OPTIONS = make_parser().parse_args()
    _LOG = setup_logger(OPTIONS)
    sys.exit(main(OPTIONS))
