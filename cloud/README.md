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

The OpenNESS installation log and the Ansible inventory file will be available on the Controller Node in `~/openness-install.log` and `~/inventory.ini` within the user specified non-root user account (e.g. `ceekuser`).

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
