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
import shutil
import logging
import subprocess
import time
from datetime import datetime
from collections import namedtuple
from deployment_handlers import inventory_handlers, output_handling

LOGGER_LEVEL = logging.INFO
LOGGER = logging.getLogger(__name__)

DeploymentWrapper = namedtuple("DeploymentWrapper",
                               ["process", "cluster_name", "playbook_file_name", "log_file"])
# Global variable to be shared between main and signal handler.
deployment_wrappers = []
RT_OUTPUT_HANDLER = output_handling.RtOutputHandler(logging)

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


def handle_alt_dir_layout_cleanup():
    """Removes alternative layout"""
    if os.path.exists(ALT_INVENTORIES_PATH):
        shutil.rmtree(ALT_INVENTORIES_PATH)


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
    log_file = open(deployment_log_file_path, "w")

    logging.info('%s %s: command: "%s"',
                 inventory.cluster_name, playbook_basename, ansible_playbook_command)
    logging.info('%s %s: log file: "%s"',
                 inventory.cluster_name, playbook_basename, os.path.realpath(log_file.name))

    deployment_process = subprocess.Popen(ansible_playbook_command.split(),
                                          stdout=log_file, stderr=subprocess.STDOUT)

    return DeploymentWrapper(process=deployment_process,
                             cluster_name=inventory.cluster_name,
                             playbook_file_name=playbook_basename,
                             log_file=log_file,
                             )


def kill_deployments(deployments):
    """Kills every executed deployment"""
    for deployment in deployments:
        if (deployment is not None) and (deployment.process.poll() is None):
            # deployment_child = Popen(['ps', '-opid', '--no-headers', '--ppid',
            #                           str(deployment.process.pid)], stdout=PIPE)
            # ansible_playbook_pid = int(deployment_child.stdout.read())
            try:
                # os.kill(ansible_playbook_pid, signal.SIGTERM)
                os.kill(deployment.process.pid, signal.SIGTERM)
            except ProcessLookupError:
                logging.info('Playbook "%s" | cluster "%s" already terminated.',
                             deployment.playbook_file_name, deployment.name)
                continue
            deployment.process.terminate()
            deployment.process.wait()
            if deployment.log_file is not None:
                deployment.log_file.close()
            logging.info('Playbook "%s" | cluster "%s" terminated.',
                         deployment.playbook_file_name, deployment.cluster_name)


def check_deployments_status(deployments, exit_on_error=False):
    """Simple asynchronous checks if some deployment is finished"""
    ## TO-DO: process outputs from deployments
    while len(deployments) > 0:
        for _, deployment in enumerate(deployments):
            if deployment.process.poll() is None:
                pass
            elif deployment.process.poll() == 0:
                logging.info('%s %s: succeed.',
                             deployment.cluster_name,
                             deployment.playbook_file_name)
                deployment.log_file.close()
                deployments.remove(deployment)
            elif deployment.process.poll() != 0:
                logging.error('%s %s: failed. Please check the logs: %s',
                              deployment.cluster_name,
                              deployment.playbook_file_name,
                              os.path.realpath(deployment.log_file.name))
                deployment.log_file.close()
                deployments.remove(deployment)
                if exit_on_error is True:
                    logging.info("--any-errors-fatal flag raised, terminating other deployments...")
                    kill_deployments(deployments)
                    RT_OUTPUT_HANDLER.output_screens_cleanup()
                    sys.exit(ERROR_EXIT_CODE)
        time.sleep(1)


def exit_gracefully(signum, _):
    """Exit when signal is caught"""
    logging.info("")
    logging.info('Signal "%s" caught, killing deployments...', signum)
    kill_deployments(deployment_wrappers)
    RT_OUTPUT_HANDLER.output_screens_cleanup()
    logging.info('All deployments stopped')
    sys.exit(ERROR_EXIT_CODE)


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
    parser.add_argument("--revert-dir-layout", dest="revert_dir_layout", action="store_true",
                        help="Revert alternate dir layout and exit [to be removed in future]")
    parser.add_argument("--rt-output-tracking", dest="rt_output_tracking", action="store_true",
                        help="Creates sessions with real-time log file tracking")
    return parser.parse_args()


def main(args):
    """Run parallel network edge deployments"""
    signal.signal(signal.SIGINT, exit_gracefully)
    signal.signal(signal.SIGTERM, exit_gracefully)

    create_log_dir_if_not_exists()
    current_date_time = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    deploy_log_path = os.path.join(ANSIBLE_LOGS_PATH, f"deploy_script_{current_date_time}.log")
    logging.basicConfig(level=LOGGER_LEVEL,
                        format='%(asctime)s.%(msecs)03d %(levelname)s: %(message)s',
                        datefmt='%Y-%m-%d %H:%M:%S',
                        handlers=[
                            logging.FileHandler(deploy_log_path),
                            logging.StreamHandler()
                            ]
                        )
    if args.revert_dir_layout:
        handle_alt_dir_layout_cleanup()
        logging.info("Directory layout reverted.")
        sys.exit(0)

    RT_OUTPUT_HANDLER.enable_logs_tracking(args.rt_output_tracking)
    inventory_handler = inventory_handlers.InventoryHandler(MULTI_INVENTORY_FILE)

    for inventory in inventory_handler.get_inventories:
        if not verify_flavor(inventory.flavor, FLAVORS_PATH):
            logging.fatal('Parsing inventory failed: flavor "%s" does not exists in "%s"',
                          inventory.flavor, FLAVORS_PATH)
            sys.exit(1)

    prepare_alt_dir_layout()
    for inventory in inventory_handler.get_inventories:
        deploy_wrapper = run_deployment(inventory, args.clean)
        deployment_wrappers.append(deploy_wrapper)
        session_command = f"tail -n 50 -f {deploy_wrapper.log_file.name}"
        RT_OUTPUT_HANDLER.call_new_track_output_session(deploy_wrapper.cluster_name,
                                                        session_command)
        time.sleep(DEPLOYMENT_INTERVAL)

    RT_OUTPUT_HANDLER.log_sessions_creation()
    check_deployments_status(deployment_wrappers, args.any_errors_fatal)
    RT_OUTPUT_HANDLER.output_screens_cleanup()
    logging.info("Deployment finished")
    sys.exit(0)


if __name__ == '__main__':
    try:
        main(parse_arguments())
    except argparse.ArgumentTypeError as exception:
        logging.error(exception)
        sys.exit(ERROR_EXIT_CODE)
