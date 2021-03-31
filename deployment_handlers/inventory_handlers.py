#!/usr/bin/env python3

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2021 Intel Corporation

"""
Handlers for inventory.yml file
"""

import os
import yaml

class Inventory: # pylint: disable=too-many-instance-attributes
    """Single inventory for deployment"""
    def __init__(self, inventory_doc):
        self.__inventory_doc = inventory_doc
        self.__parse_yaml_doc(inventory_doc)

    @property
    def flavor(self):
        """Returns deployment flavor"""
        return self.__flavor

    @property
    def is_single_node(self):
        """Returns true if single node deployment is set"""
        return self.__is_single_node

    @property
    def limit(self):
        """Returns group limitation for deployment"""
        return self.__limit

    @property
    def inventory_filename(self):
        """Returns actual inventory filename"""
        return self.__inventory_filename

    @property
    def cluster_name(self):
        """Returns cluster name"""
        return self.__cluster_name

    @property
    def controller_ansible_host(self):
        """Returns controller ansible_host for controller"""
        return self.__controller_ansible_host

    @property
    def controller_ansible_user(self):
        """Returns controller ansible_user for controller"""
        return self.__controller_ansible_user

    @property
    def inventory(self):
        """Returns inventory contents"""
        return yaml.dump(self.__inventory_doc)

    def dump_to_yaml(self, path=""):
        """Dump inventory to yaml file, returns location"""
        inventory_path = os.path.join(path, self.__inventory_filename)
        if not os.path.exists(path):
            os.mkdir(path)
        with open(inventory_path, 'w') as inventory_file:
            yaml.dump(self.__inventory_doc, inventory_file)
        return inventory_path

    def __parse_yaml_doc(self, inventory_doc):
        self.__flavor = inventory_doc["all"]["vars"]["flavor"]
        if self.__flavor is None:
            raise ValueError("Flavor must be defined in all docs in inventory.yml file!")
        self.__cluster_name = inventory_doc["all"]["vars"]["cluster_name"]
        if self.__cluster_name is None:
            raise ValueError("Cluster name must be defined in all docs in inventory.yml file")
        self.__is_single_node = inventory_doc["all"]["vars"]["single_node_deployment"]
        self.__limit = inventory_doc["all"]["vars"]["limit"]
        self.__inventory_filename = f"inventory_{self.__cluster_name}.yml"
        self.__controller_ansible_host = \
            next(iter(inventory_doc["controller_group"]["hosts"].values()))["ansible_host"]
        self.__controller_ansible_user = \
            next(iter(inventory_doc["controller_group"]["hosts"].values()))["ansible_user"]

class InventoryHandler:
    """Simple inventory.yml handler"""

    def __init__(self, inventory_path):
        self.__load_inventory(inventory_path)
        self.__verify_cluster_names()

    @property
    def get_inventories(self):
        """Returns list with loaded Inventories"""
        return self.__inventories

    def get_inventories_amount(self):
        """Returns amount of loaded inventories"""
        return len(self.__inventories)

    def __load_inventory(self, inventory_path):
        with open(inventory_path, 'r') as inventory_stream:
            doc_iterator = yaml.load_all(inventory_stream, Loader=yaml.SafeLoader)
            self.__inventories = []
            for doc in doc_iterator:
                self.__inventories.append(Inventory(doc))

    def __verify_cluster_names(self):
        cluster_names = []
        for i in range(len(self.__inventories)):
            cluster_name = self.__inventories[i].cluster_name
            if cluster_name in cluster_names:
                raise ValueError("Cluster names must be different")
            cluster_names.append(cluster_name)
