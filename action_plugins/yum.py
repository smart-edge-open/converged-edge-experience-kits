#!/usr/bin/python

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

"""This plugin will call yum module and retry installation task if installation fail."""
# All parameters of yum module can be used. Two additional parameters can also be provided:
# - retries: number of retries (default: 10)
# - delay: time (in seconds) that plugin will wait between retries (default: 5)
# Number of retries and delay can be also configured by global variables
# number_of_retries and retry_delay provided in group_vars.

from __future__ import (absolute_import, division, print_function)
import time
import ansible.plugins.action
MetaClass = type

DEFAULT_VALUES = {
    'retries': {'value': 10, 'ansible_var': 'number_of_retries'},
    'delay': {'value': 5, 'ansible_var': 'retry_delay'}
}

class ActionModule(ansible.plugins.action.ActionBase):
    """Ansible plugin wrapping the ansible yum module to make package
       installation more network error resistant"""
    def get_variable(self, arg):
        """get_variable will find value for provided argument arg may be 'retries' or 'delay'"""
        def_val = DEFAULT_VALUES.get(arg)
        if def_val is None:
            return -1

        task_var = def_val.get('ansible_var')
        if task_var is None:
            return -2

        # check if module's argument was provided (retries or delay)
        if self.module_args.get(arg) is not None:
            result = self.module_args.get(arg)
            # delete argument to avoid passing it to original yum module
            del self.module_args[arg]
            return result
        # else check if ansible variable was set (number_of_retries or retry_delay in group_vars)
        if self.task_vars.get(task_var) is not None:
            return self.task_vars.get(task_var)
        # use default value if argument and ansible variable were not set
        return def_val.get('value')

    def run(self, tmp=None, task_vars=None):
        super(ActionModule, self).run(tmp, task_vars)
        self.module_args = self._task.args.copy()
        self.task_vars = task_vars

        state = str(self.module_args.get('state')).lower()
        autoremove = str(self.module_args.get('autoremove')).lower()

        # If this is non-installation task run it with original yum module.
        # Remove unused variables form module_args dict if necessary.
        if (state not in ('present', 'installed')) or autoremove == 'yes':
            if (self.module_args.get('retries') is not None
                    or self.module_args.get('delay') is not None):
                self._display.vvv('This is not an installation task. Retries will be omitted.')
                if self.module_args.get('retries') is not None:
                    del self.module_args['retries']
                if self.module_args.get('delay') is not None:
                    del self.module_args['delay']
            return self._execute_module(module_name='yum', module_args=self.module_args,
                                        task_vars=self.task_vars, tmp=tmp)

        # Find actual values of retries and delay.
        number_of_retries = self.get_variable('retries')
        retry_delay = self.get_variable('delay')

        # Run task for number_of_retries, break if it succeeded.
        attempt = 0
        for attempt in range(number_of_retries):
            result = self._execute_module(module_name='yum', module_args=self.module_args,
                                          task_vars=self.task_vars, tmp=tmp)

            return_code = result.get('rc')
            if return_code == 0:
                break

            if attempt < (number_of_retries - 1):
                self._display.display("Error occurred. Will retry after %s seconds."
                                      " You can find details below:" % str(retry_delay))
                if (result.get('msg') is not None and result.get('msg') != ''):
                    self._display.display("%s" % str(result['msg']))
                else:
                    self._display.display("%s" % str(result))
                time.sleep(retry_delay)
                self._display.display("\nRetrying task - attempt %s of %s"
                                      % (str(attempt + 2), str(number_of_retries)))

        result['attempts'] = attempt + 1
        return result
