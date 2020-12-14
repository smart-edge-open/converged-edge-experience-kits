```text
SPDX-License-Identifier: Apache-2.0
Copyright (c) 2020 Intel Corporation
```

![OpenNESS](https://www.openness.org/images/openness-logo.png)

# OpenNESS Devkit for Azure

This is an Azure Resource Manager template to deploy OpenNESS within Azure. 

## Requirements

The following are requirements in order to deploy this template:

* An active Azure subscription
* Your account needs the [Managed Identity Contributor](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#managed-identity-contributor) role  in order to create a user assigned managed identity
* Adequate quota within selected region to deploy the number of virtual machines of the selected size



The following fields **must** be populated within the Azure portal:

* Resource Group (recommended to always create new)

* SSH Identity:  Your personal SSH pulic key is required in RSA format similar to:

    `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCmtbcd0Zo27fRIz5dTWG0Vnh .... lw== user@system`

* VM Username:  This is the non-priveleged user that will be created

* VMSS Name:  This is required in order to create the VMSS

> WARNING:  There is no content validation on the parameters, any invalid entry may result in a silent failure on deployment

> NOTE:  Please document your selected Resource Group and VMSS Name, as these can be utilized to query for the node IP addresses in the future

> NOTE: The Deploy to Azure button may only work when clicked within Github web interface

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fopen-ness%2Fopenness-experience-kits%2Fmaster%2Fcloud%2Fazuredeploy.json)

## Post Deployment

> NOTE:  Deployment may take up to 2 hours to complete due to variability within Azure, typical deployment is <45 minutes

After deployment completes, the Azure Deployment resource will have Outputs with access details.  The Deployment resource itself will only be retained for 26-hours, this is a limitation of the Azure service.

The "result" field will include access instructions for the deployed cluster, as well as the Ansible _Play Recap_.

>  NOTE: If the recap includes a failure count other than `failed=0` then the OpenNESS installation failed.

The OpenNESS installation log and the Ansible inventory file will be available on the Controller Node in `~/openness-install.log` and `~/inventory.ini` within the user specified non-root user account (e.g. `oekuser`).

The public IP addresses for the nodes can be queried with this script, your local `bash` shell with the presence of [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) or an [Azure Cloud Shell](https://docs.microsoft.com/en-us/azure/cloud-shell/overview).  You will need to manually confirm you have an active Azure token, the easist method is by manually running `az login` prior to execution:

```shell
echo "Enter the ResourceGroup:" &&
read resourceGroupName &&
echo "Enter the VMSSname:" &&
read vmssName &&
echo "The public IP addresses are below, the first IP address should be the Controller Node" &&
az vmss list-instance-public-ips  -n "$vmssName" -g "$resourceGroupName" --query  [].ipAddress
```

## Next Steps

You can now proceed to onboarding applications to your Devkit environment. 

If you are looking to integrate your own application with OpenNESS please start at our [Network Edge Applications Onboarding](https://www.openness.org/docs/doc/applications-onboard/network-edge-applications-onboarding) guide.

You can find OpenNESS existing integrated apps within our [edgeapps repo](https://github.com/open-ness/edgeapps) and our [Commercial Edge Applications portal](https://networkbuilders.intel.com/commercial-applications), or you can [participate and have your apps featured](https://networkbuilders.intel.com/commercial-applications/participate).


# OpenNESS can also be installed on a VM located in the Azure cloud using Porter. This section provides steps for installing an example environment for both single node and multi node cluster

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
