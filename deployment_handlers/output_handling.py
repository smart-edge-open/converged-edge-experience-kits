#!/usr/bin/env python3

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2021 Intel Corporation

"""
Ansible Playbook output handlers
"""

from subprocess import Popen, DEVNULL, STDOUT
import shutil
import sys

# Session management commands
SESSION_APP = "screen"
CREATE_NEW_NAMED_SESSION = f"{SESSION_APP} -dmS"
LIST_SESSIONS = f"{SESSION_APP} -ls"
ATTACH_SESSION = f"{SESSION_APP} -r"
KILL_SESSION = f"{SESSION_APP} -XS"
KILL_SESSION_ARG = "quit"

class RtOutputHandler:
    """Simple real time output handler"""

    def __init__(self, logging, enabled=False):
        self.__logging = logging
        self.enable_logs_tracking(enabled)
        self.__sessions_names = []


    def __session_app_pre_check(self):
        """Checks if session app is installed, exits if is not"""
        if shutil.which(SESSION_APP) is None:
            self.__logging.error(f"\'{SESSION_APP}\' not installed, exiting...")
            sys.exit(2)
        else:
            self.__logging.info(f"\'{SESSION_APP}\' installed, continuing...")


    def enable_logs_tracking(self, enabled):
        """Set real time logs tracking"""
        self.__enabled = enabled
        if self.__enabled:
            self.__logging.info("--rt-output-tracking flag raised, checking pre-conditions...")
            self.__session_app_pre_check()
        else:
            self.__logging.info("Real-time logs tracking not enabled")


    def log_sessions_creation(self):
        """Show created sessions"""
        if self.__enabled:
            self.__logging.info("Created screen session\\s for real-time output tracking:")
            self.__logging.info("Type \'%s <CLUSTER_NAME>\' to track specific cluster",
                                ATTACH_SESSION)
            Popen(LIST_SESSIONS.split())


    def call_new_track_output_session(self, session_name, session_command):
        """Create new named session with given command"""
        if self.__enabled:
            Popen(f"{CREATE_NEW_NAMED_SESSION} {session_name} {session_command}".split(),
                  stdout=DEVNULL, stderr=STDOUT)
            self.__sessions_names.append(session_name)


    def output_screens_cleanup(self):
        """Kills every created session"""
        if self.__enabled:
            for session_name in self.__sessions_names:
                Popen(f"{KILL_SESSION} {session_name} {KILL_SESSION_ARG}".split())
