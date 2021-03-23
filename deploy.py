#!/usr/bin/env python3

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2021 Intel Corporation

"""
Deploy OpenNESS with inventory.yml file.
"""

import argparse
import sys
from re import match
import os
import signal
import logging
import subprocess
import shutil
import time
from datetime import datetime

import sh # pylint: disable=import-error

from deployment_handlers import inventory_handlers
from scripts import log_all


DEPLOYMENT_INTERVAL = 5
ERROR_EXIT_CODE = 1
DIR_PATH = 0
FILENAMES = 2
ROOT_PART = 0

START_WORKING_DIR = os.getcwd()
GROUP_VARS_DIR = "group_vars"
HOST_VARS_DIR = "host_vars"
DEFAULT_INVENTORY_PATH = os.path.join(START_WORKING_DIR, "inventory", "default")
DEFAULT_GROUP_VARS_PATH = os.path.join(DEFAULT_INVENTORY_PATH, GROUP_VARS_DIR)
DEFAULT_HOST_VARS_PATH = os.path.join(DEFAULT_INVENTORY_PATH, HOST_VARS_DIR)
ANSIBLE_LOGS_PATH = os.path.join(START_WORKING_DIR, "logs")
TEMP_DIR_PATH = os.path.join(START_WORKING_DIR, "tmp")
ALT_INVENTORIES_PATH = os.path.join(START_WORKING_DIR, "inventory", "automated")
FLAVORS_PATH = os.path.join(START_WORKING_DIR, "flavors")
FLAVOR_LINK_PREFIX = "30_"
FLAVOR_LINK_POSTFIX = "_flavor.yml"
FLAVOR_LINK_PATTERN = f"{FLAVOR_LINK_PREFIX}.*{FLAVOR_LINK_POSTFIX}"
DEFAULT_CLUSTER_NAME = "single_cluster"
MULTI_INVENTORY_FILE = "inventory.yml"


class DeploymentWrapper:
    """DeploymentWrapper is an object that contains information about Network Edge deployment"""
    def __init__(self, process, inventory, playbook_file_name, log_file):
        self.process = process
        self.inventory = inventory
        self.cluster_name = inventory.cluster_name
        self.playbook_file_name = playbook_file_name
        self.log_file = log_file
        self.has_ended = False
        self.ended_successfully = False

    def kill_deployment(self):
        """kill deployment"""


    def pull_logs(self):
        """pull_logs pulls .tar.gz package with deployment logs"""
        log_all.collect_logs(self.inventory.controller_ansible_user,
                             self.inventory.controller_ansible_host)


# Global variable to be shared between main and signal handler.
deployment_wrappers = []


def create_log_dir_if_not_exists():
    """Creates ANSIBLE_LOGS_PATH directory if it does not exists"""
    if not os.path.exists(ANSIBLE_LOGS_PATH):
        os.mkdir(path=ANSIBLE_LOGS_PATH, mode=0o755)


def get_log_file_path(flavor, cluster_name, playbook_basename):
    """Returns generated ansible log filename"""
    create_log_dir_if_not_exists()
    current_date_time = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    filename = f"{cluster_name}_{flavor}_{current_date_time}_{playbook_basename}.log"
    return os.path.join(ANSIBLE_LOGS_PATH, filename)


def remove_files_recurse_by_pattern(path, pattern):
    """Iterates recursively over files in given path and removes which match pattern"""
    for root, _, files in os.walk(path):
        for filename in files:
            if match(pattern, filename):
                os.remove(os.path.join(root, filename))


def remove_any_flavor_symlinks(group_vars_path):
    """Removes any flavor symlinks files in group_vars folders"""
    remove_files_recurse_by_pattern(group_vars_path, FLAVOR_LINK_PATTERN)


def verify_flavor(flavor, flavor_path):
    """Checks if given flavor is valid for deployment"""
    return os.path.exists(os.path.join(flavor_path, flavor))


def create_sym_links_for_flavor(flavor, flavor_path, group_vars_path=DEFAULT_GROUP_VARS_PATH):
    """Creates symlinks from flavor files for ansible"""
    flavor_path_content = next(os.walk(flavor_path))
    for flavor_file in flavor_path_content[FILENAMES]:
        if match(".*.yml", flavor_file):

            file_path = os.path.join(flavor_path_content[DIR_PATH], flavor_file)
            basename_path = os.path.splitext(file_path)[ROOT_PART]
            # Flavor filename without extension (e.g. `controller_group`)
            fname = os.path.basename(basename_path)
            dirname = os.path.join(group_vars_path, fname)

            # Check if directory exists in group_vars regarding to flavor filename (e.g. `all`)
            if not os.path.exists(dirname):
                logging.error('Flavor "%s" does not match a directory in /group_vars:', dirname)
                list_dir = ', '.join(os.listdir(group_vars_path))
                logging.info(list_dir)
                sys.exit(ERROR_EXIT_CODE)

            flavor_link_name = f"{FLAVOR_LINK_PREFIX}{flavor}{FLAVOR_LINK_POSTFIX}"
            link_path = os.path.join(dirname, flavor_link_name)
            os.symlink(file_path, link_path)


def handle_flavor_for_deployment(flavor, group_vars_path):
    """Handles flavor for deployment"""
    remove_any_flavor_symlinks(group_vars_path)
    flavor_path = os.path.join(FLAVORS_PATH, flavor)
    verify_flavor(flavor, flavor_path)
    create_sym_links_for_flavor(flavor, flavor_path, group_vars_path)


def prepare_alt_dir_layout():
    """Prepares alternative directory layout for multiple clusters"""
    if not os.path.exists(ALT_INVENTORIES_PATH):
        os.makedirs(ALT_INVENTORIES_PATH)


def create_symlinks_for_inventory(src_vars_path, dest_vars_path):
    """Creates symlinks for alternative directory layout"""
    for root, dirs, files in os.walk(src_vars_path):
        for dir_name in dirs:
            group_vars_group_dir = os.path.join(dest_vars_path, dir_name)
            if not os.path.exists(group_vars_group_dir):
                os.makedirs(group_vars_group_dir)
        for file in files:
            # Get last directory of file
            orig_host_vars_yaml = os.path.join(root, file)
            dirname = os.path.basename(os.path.dirname(orig_host_vars_yaml))
            inventory_group_vars = os.path.join(dest_vars_path, dirname, file)
            if not os.path.exists(inventory_group_vars):
                os.symlink(orig_host_vars_yaml, inventory_group_vars)


def handle_cluster_inventory_dir(cluster_inventory_path, group_vars_path, host_vars_path):
    """Creates inventory directory for specific cluster"""
    if not os.path.exists(cluster_inventory_path):
        os.mkdir(cluster_inventory_path)

    create_symlinks_for_inventory(DEFAULT_GROUP_VARS_PATH, group_vars_path)
    create_symlinks_for_inventory(DEFAULT_HOST_VARS_PATH, host_vars_path)


def run_deployment(inventory, cleanup=False):
    """Deploys OpenNESS with given settings, returns Popen object"""
    inventory_dir = os.path.join(ALT_INVENTORIES_PATH, inventory.cluster_name)
    inventory_location = inventory.dump_to_yaml(inventory_dir)
    group_vars_path = os.path.join(inventory_dir, GROUP_VARS_DIR)
    host_vars_path = os.path.join(inventory_dir, HOST_VARS_DIR)
    handle_cluster_inventory_dir(inventory_dir, group_vars_path, host_vars_path)

    handle_flavor_for_deployment(inventory.flavor, group_vars_path)

    if cleanup:
        playbook = "network_edge_cleanup.yml"
    else:
        if inventory.is_single_node:
            playbook = "single_node_network_edge.yml"
        else:
            playbook = "network_edge.yml"

    ansible_playbook_path = shutil.which("ansible-playbook")
    ansible_playbook_command = f"{ansible_playbook_path} " \
                               f"-vv {playbook} " \
                               f"--inventory {inventory_location}"

    if inventory.limit is not None:
        ansible_playbook_command = f"{ansible_playbook_command} --limit {inventory.limit}"

    playbook_basename = os.path.basename(playbook)
    deployment_log_file_path = get_log_file_path(
        inventory.flavor,
        inventory.cluster_name,
        playbook_basename)
    log_file = open(deployment_log_file_path, "a+")

    logging.info('%s %s: command: "%s"',
                 inventory.cluster_name, playbook_basename, ansible_playbook_command)
    logging.info('%s %s: log file: "%s"',
                 inventory.cluster_name, playbook_basename, os.path.realpath(log_file.name))

    deployment_process = subprocess.Popen(ansible_playbook_command.split(),
                                          stdout=log_file, stderr=subprocess.STDOUT)

    return DeploymentWrapper(process=deployment_process,
                             inventory=inventory,
                             playbook_file_name=playbook_basename,
                             log_file=log_file,
                             )


def kill_deployments(deployments):
    """Kills every executed deployment"""
    for deployment in deployments:
        if (deployment is not None) and (deployment.process.poll() is None):
            try:
                os.kill(deployment.process.pid, signal.SIGTERM)
            except ProcessLookupError:
                logging.info('Playbook "%s" | cluster "%s" already terminated.',
                             deployment.playbook_file_name, deployment.name)
                continue
            deployment.process.terminate()
            deployment.process.wait()
            deployment.has_ended = True
            deployment.ended_successfully = False
            if deployment.log_file is not None:
                deployment.log_file.close()
            logging.info('Playbook "%s" | cluster "%s" terminated.',
                         deployment.playbook_file_name, deployment.cluster_name)


def print_log_line(line):
    """Print ansible deployment log line callback"""
    print(line, end='')


def has_deployments_successful(deployments):
    """Check if whole deployment was successful"""
    for deployment in deployments:
        if not deployment.ended_successfully:
            return False
    return True


def has_deployments_ended(deployments):
    """Check if deployments has ended"""
    for deployment in deployments:
        if not deployment.has_ended:
            return False
    return True


def check_deployments_status(deployments, exit_on_error=False):
    """Simple asynchronous checks if some deployment is finished"""

    # In single cluster deployment, logs are forwarded to stdout.
    if len(deployments) == 1:
        logging.info("Only one cluster is being deployed. Redirecting logs to stdout.")
        sh.tail("-n", "100000", "-f", # pylint: disable=no-member
                deployments[0].log_file.name,
                _out=print_log_line,
                _bg=True,
                _new_session=False)
    else:
        logging.info("More than one deployment is running,"
                     "please check the log files for detailed deployment logs.")

    while not has_deployments_ended(deployments):
        for _, deployment in enumerate(deployments):
            if deployment.process.poll() is None or deployment.has_ended:
                pass
            elif deployment.process.poll() == 0:
                logging.info('%s %s: succeed.',
                             deployment.cluster_name,
                             deployment.playbook_file_name)
                deployment.log_file.close()
                deployment.has_ended = True
                deployment.ended_successfully = True
            elif deployment.process.poll() != 0:
                logging.error('%s %s: failed. Please check the logs: %s',
                              deployment.cluster_name,
                              deployment.playbook_file_name,
                              os.path.realpath(deployment.log_file.name))
                deployment.log_file.close()
                deployment.has_ended = True
                deployment.ended_successfully = False
                if exit_on_error is True:
                    logging.info("--any-errors-fatal flag raised, terminating other deployments...")
                    kill_deployments(deployments)
        time.sleep(1)


def exit_gracefully(signum, _):
    """Exit when signal is caught"""
    logging.info("")
    logging.info('Signal "%s" caught, killing deployments...', signum)
    kill_deployments(deployment_wrappers)
    logging.info('All deployments stopped')
    print_deployment_recap(deployment_wrappers)
    sys.exit(ERROR_EXIT_CODE)


def print_deployment_recap(deployments):
    """Prints deployment recap on stdout"""
    deployment_count = len(deployments)
    successful_count = 0
    failure_count = 0
    for deployment in deployments:
        if deployment.ended_successfully:
            successful_count = successful_count + 1
        else:
            failure_count = failure_count + 1
    logging.info("====================")
    logging.info("DEPLOYMENT RECAP:")
    logging.info("====================")
    logging.info("DEPLOYMENT COUNT: %d", deployment_count)
    logging.info("SUCCESSFUL DEPLOYMENTS: %d", successful_count)
    logging.info("FAILED DEPLOYMENTS: %d", failure_count)
    for deployment in deployments:
        deployment_status = "SUCCESSFUL" if deployment.ended_successfully else "FAILED"
        logging.info('DEPLOYMENT "%s": %s', deployment.cluster_name, deployment_status)
    logging.info("====================")


def parse_arguments():
    """Parse argument passed to function"""
    script_description = ("Script for Deploying OpenNESS using inventory.yml file. " +
                          "Deployment is controlled through inventory.yml.")
    parser = argparse.ArgumentParser(
        description=script_description)
    parser.add_argument("-f", "--any-errors-fatal", dest="any_errors_fatal", action="store_true",
                        help="Terminate all running actions when any of them fail")
    parser.add_argument("-c", "--clean", dest="clean", action="store_true",
                        help="Run cleanup scripts on clusters")
    return parser.parse_args()


def main(args):
    """Run parallel network edge deployments"""
    signal.signal(signal.SIGINT, exit_gracefully)
    signal.signal(signal.SIGTERM, exit_gracefully)

    create_log_dir_if_not_exists()
    current_date_time = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    deploy_log_path = os.path.join(ANSIBLE_LOGS_PATH, f"deploy_script_{current_date_time}.log")
    logging.basicConfig(level=logging.INFO,
                        format='%(asctime)s.%(msecs)03d %(levelname)s: %(message)s',
                        datefmt='%Y-%m-%d %H:%M:%S',
                        handlers=[
                            logging.FileHandler(deploy_log_path),
                            logging.StreamHandler()
                            ]
                        )
    inventory_handler = inventory_handlers.InventoryHandler(MULTI_INVENTORY_FILE)
    for inventory in inventory_handler.get_inventories:
        if not verify_flavor(inventory.flavor, FLAVORS_PATH):
            logging.fatal('Parsing inventory failed: flavor "%s" does not exists in "%s"',
                          inventory.flavor, FLAVORS_PATH)
            sys.exit(ERROR_EXIT_CODE)

    prepare_alt_dir_layout()
    for inventory in inventory_handler.get_inventories:
        deploy_wrapper = run_deployment(inventory, args.clean)
        deployment_wrappers.append(deploy_wrapper)
        time.sleep(DEPLOYMENT_INTERVAL)

    check_deployments_status(deployment_wrappers, args.any_errors_fatal)

    print_deployment_recap(deployment_wrappers)
    if has_deployments_successful(deployment_wrappers):
        sys.exit(0)
    else:
        logging.info("Deployment failed, pulling logs")
        for deployment in deployment_wrappers:
            deployment.pull_logs()
        sys.exit(ERROR_EXIT_CODE)


if __name__ == '__main__':
    try:
        main(parse_arguments())
    except argparse.ArgumentTypeError as arg_type_exception:
        logging.error(arg_type_exception)
        sys.exit(ERROR_EXIT_CODE)
