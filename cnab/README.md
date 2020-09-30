```text
SPDX-License-Identifier: Apache-2.0
Copyright (c) 2020 Intel Corporation
```

# OpenNESS can be installed on a VM located in the azure cloud. This document provides steps for installing an example environment for both single node and multi node cluster

> It is not possible to use the RT kernel that is enabled by default in OpenNESS setup scripts. The default RT kernel used by OpenNESS lacks HyperV drivers required by azure VMs

## Prerequisites

* Azure application configured according to [Azure application and service principal](https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal)
* Docker installed on porter host

## Setup

1. Install porter(v0.26.3-beta.1) according to <https://porter.sh/install>
2. Enter `openness-experience-kits/cnab` directory
3. Extract `tenant id`, `application id` and `application token` from the created azure application
4. Run `porter credentials generate` and fill with the appropriate values from the previous step
5. Build the CNAB bundle with `porter build`
   > To enable a proxy server manually edit `openness-experience-kits/cnab/Dockerfile.tmpl`
6. Create `params.ini` and provide the SSH public key(`~/.ssh/id_rsa.pub`) that will be used to login to the created VMs:

   ```ini
   ssh_identity=...
   az_vm_count=2
   ```

   > To see all possible variables and their default values run `porter explain`
7. Run `porter install -c OpenNESS --param-file params.ini` to setup the azure VMs and install OpenNESS  
   Example output:

   ```text
   PLAY RECAP *********************************************************************
   ctrl                       : ok=352  changed=236  unreachable=0    failed=0    skipped=156  rescued=0    ignored=14
   node-0                     : ok=251  changed=129  unreachable=0    failed=0    skipped=131  rescued=0    ignored=5

   OpenNESS Setup: [INFO] oek_setup(148): Ansible finished successfully on following hosts(First IP is of controller)
   OpenNESS Setup: [INFO] oek_setup(149): 13.94.134.225,13.94.133.74
   execution completed successfully!
   ```

8. Use the first listed ip from the previous step to verify that the setup was successful:

   ```shell
   ssh oekuser@13.94.134.225 sudo kubectl get po -A
   ```

## Uninstall

1. After a successful setup run `porter uninstall -c OpenNESS`
