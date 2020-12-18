# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2020 Intel Corporation

#!/bin/python3
# coding:utf-8

'''
This is a funcion to parse a yaml file
'''

import os
import sys
import yaml

if len(sys.argv) != 2:
    sys.exit()

selected = sys.argv[1]

curPath = os.path.dirname(os.path.realpath(__file__))
yamlPath = os.path.join(curPath, "../package_definition_list/pdl_flexran.yml")
f = open(yamlPath, 'r', encoding='utf-8')

cfg = f.read()
d = yaml.safe_load(cfg)

def get_charts_struct(parent, dic):
    """ Parse the PDL yaml file to output a long string
    """
    line = ''
    for fi in dic['file']:
        if isinstance(fi, dict):
            new_parent = parent + '/' + dic['dir']
            line = line + get_charts_struct(new_parent, fi)
        else:
            line = line + parent + '/' + dic['dir'] + '|' + fi + ','
    if line[-1] == ',':
        line = line[:-1]
    return line

if selected == 'rpm-packages':
    for key in d[selected]:
        print("%s,%s"%(key['name'], key['rpm']))
elif selected == 'github-repos':
    for key in d[selected]:
        print("%s,%s,%s,%s"%(key['name'], key['url'], key['flag'], key['value']))
elif selected == 'go-modules':
    for key in d[selected]:
        print("%s"%(key['name']))
elif selected == 'pip-packages':
    for key in d[selected]:
        print("%s,%s"%(key['name'], key['url']))
elif selected == 'docker-images':
    for key in d[selected]:
        print("%s,%s"%(key['name'], key['image']))
elif selected == 'build-images':
    for key in d[selected]:
        print("%s,%s"%(key['name'], key['tag']))
elif selected == 'yaml-files':
    for key in d[selected]:
        print("%s,%s"%(key['name'], key['url']))
elif selected == 'other-files':
    for key in d[selected]:
        print("%s,%s"%(key['name'], key['url']))
elif selected == 'charts-files':
    for key in d[selected]:
        print(get_charts_struct('', key))

f.close()
