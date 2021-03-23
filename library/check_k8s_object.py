#!/usr/bin/python

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2021 Intel Corporation

''' This is a module for ansible to check working state of some kubernetes
objects. Please read inline YAML documentation'''

import subprocess
import json

from ansible.module_utils.basic import AnsibleModule

ANSIBLE_METADATA = {
    'metadata_version': '1.1',
    'status': ['preview'],
    'supported_by': 'community'
}

DOCUMENTATION = '''
---
module: check_k8s_object

short_description: checks k8s objects status

version_added: "1.0"

description:
    - this module checks status of some k8s objects and returns its status

options:
    kind:
        description:
            - > kind of object to check, can be daemonset, statefulset
                or deployment
        required: true
    namespace:
        description:
            - k8s namespace name
        required: true
    name:
        description:
            - k8s object name
        required: true
'''

EXAMPLES = '''
# Pass in a message
- name: test new module
  check_k8s_object:
    kind: sts
    name: harbor-app-harbor-database
    namespace: harbor
'''

RETURN = '''
original_message:
    description: ignored
    type: str
    returned: always
message:
    description: > The output message that the test module generates, can be
                   error description or a string describing replicas status
                   like: Replicas status: 1/1
    type: str
    returned: always
'''


def call_kubectl(kind, name, namespace, result):
    '''Calls kubectl, check the status preventing exceptions from propagation.
    Modifies results parameter in case of error.
    Returns a tuple of bool status and output'''

    output = None
    try:
        parameters = ['kubectl', 'get', '--output', 'json',
                      str(kind),
                      '-n', str(namespace),
                      str(name)]

        output = subprocess.check_output(parameters, stderr=subprocess.STDOUT)
        output = json.loads(output)

        result['cmd'] = " ".join(parameters)

        result['failed'] = False

        return (True, output)
    except ValueError as ex:
        result['failed'] = True
        result['message'] = "ValueError: " + str(ex)
    except OSError as ex:
        result['rc'] = ex.errno
        result['failed'] = True
        result['message'] = "OSError: " + ex.strerror
    except subprocess.CalledProcessError as ex:
        result['stdout'] = ex.output
        result['rc'] = ex.returncode
        result['failed'] = True
        result['message'] = "CalledProcessError: " + str(ex)

    return (False, output)


def check_daemonset(output):
    '''check if daemonset is running correctly'''

    result = False
    message = None

    try:
        available = output['status']['numberAvailable']
        desired = output['status']['desiredNumberScheduled']

        if available >= desired:
            result = True
            message = "Daemonset seems to be running normally"
        else:
            message = "Not enough available replicas {}/{}".format(
                available, desired
            )
    except KeyError as err:
        message = "Could not find the {} field in status - most probably the amount is 0".\
            format(",".join(err.args))

    return (result, message)


def check_statefulset(output):
    '''check if statefulset is running correctly'''

    result = False
    message = None

    try:
        replicas = output['status']['replicas']
        ready_replicas = output['status']['readyReplicas']

        if ready_replicas >= replicas:
            result = True
            message = "Statefulset seems to be running normally"
        else:
            message = "Not enough ready replicas {}/{}".format(
                ready_replicas, replicas
            )
    except KeyError as err:
        message = "Could not find the {} field in status - most probably the amount is 0".\
            format(",".join(err.args))

    return (result, message)


def check_deployment(output):
    '''check if deployment is running correctly'''

    result = False
    message = None

    try:
        available = output['status']['availableReplicas']
        replicas = output['status']['replicas']

        if available >= replicas:
            result = True
            message = "Deployment seems to be running normally"
        else:
            message = "Not enough available replicas {}/{}".format(
                available, replicas
            )
    except KeyError as err:
        message = "Could not find the {} field in status - most probably the amount is 0".\
            format(",".join(err.args))

    return (result, message)


def analyze_kubectl_output(output):
    '''analyze output from kubectl, check if replicas == readyReplicas
       return True if replicas == readyReplicas, False otherwise'''

    # uncomment this if debug output is needed
    # result['original_message'] = json.dumps(output["status"])

    if 'kind' not in output:
        return (False, "Error: no kind field in output json")

    kind = output['kind']

    mapping = {'DaemonSet': check_daemonset,
               'StatefulSet': check_statefulset,
               'Deployment': check_deployment}

    return mapping[kind](output)


def run_module():
    '''Module run function'''

    arguments = dict(
        kind=dict(type='str', required=True),
        name=dict(type='str', required=True),
        namespace=dict(type='str', required=True),
    )

    result = dict(
        changed=False,
        message=''
    )

    module = AnsibleModule(
        argument_spec=arguments,
        supports_check_mode=True
    )

    result['kind'] = kind = module.params['kind']
    result['name'] = name = module.params['name']
    result['namespace'] = namespace = module.params['namespace']

    kinds = ['deployment', 'deploy', 'daemonset', 'ds', 'statefulset', 'sts']

    if kind not in kinds:
        message = "Error: bad kind {}, it should be one of: {}"
        message = message.format(kind, ", ".join(kinds))

        module.fail_json(msg=message, **result)

    (call_status, kubectl_output) = call_kubectl(kind, name, namespace, result)

    if call_status:
        (analyze_status, message) = analyze_kubectl_output(kubectl_output)

        result['message'] = message

        if analyze_status:
            module.exit_json(**result)
        else:
            result['failed'] = True
            module.fail_json(msg=message, **result)
    else:
        result['failed'] = True
        module.fail_json(msg=result['message'], **result)


def main():
    '''Main module function'''
    run_module()


if __name__ == '__main__':
    main()
