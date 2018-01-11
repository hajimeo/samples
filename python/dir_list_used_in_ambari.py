#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# Search ambari's current service config (json file) and find the property values which property name looks like directory or path
#
# NOTE: need to get the currnet config from ambari like below (do not forget to change the Cluster name):
#   curl -u admin:admin "http://sandbox.hortonworks.com:8080/api/v1/clusters/Sandbox/configurations/service_config_versions?is_current=true" -o ./current_config.json
#
# How to run:
#   python ./dir_list_used_in_ambari.py ~/Desktop/current_config.json
#
# To compare/test:
#   python ./dir_list_used_in_ambari.py ~/Desktop/current_config.json | sort | uniq | tr '\n' '|'
#   find / -type d -group hadoop 2>/dev/null > hadoop_dirs.out
#   cat hadoop_dirs.out | grep -vE '/etc/|/home/|/proc/|/var/run/' | grep -vE '(output of python)'
#

import sys, re, json

class JsonParser:
    @staticmethod
    def err(reason, level="ERROR"):
        sys.stderr.write(level + ": " + str(reason) + '\n')

    @staticmethod
    def json2dict(filename, parent_element_name='configurations', key_element_name='type', value_element_name='properties'):
        rtn={}
        with open(filename) as f:
            jl = json.load(f)
        if len(parent_element_name) > 0:
            # let's return False if parent_element_name is specified but doesn't exist
            config=JsonParser.find_key_from_dict(jl, parent_element_name)
            if len(key_element_name) > 0:
                rtn = JsonParser.find_key_from_dict(config, key_element_name, value_element_name)
        return rtn

    @staticmethod
    def find_key_from_dict(obj, key, val_key=""):
        rtn={}
        tmp_item=[]
        if key in obj:
            if len(val_key) > 0:
                if val_key in obj:
                    rtn[obj[key]]=obj[val_key]
                else:
                    rtn[obj[key]]=None
                return rtn
            return obj[key]
        if isinstance(obj, list):
            for v in obj:
                tmp_item.append(JsonParser.find_key_from_dict(v, key, val_key))
            if len(tmp_item) == 1:
                return tmp_item[0]
            if len(tmp_item) > 0:
                if len(val_key) > 0:
                    rtn2={}
                    for obj2 in tmp_item:
                        for k2, v2 in obj2.items():
                            rtn2[k2]=v2
                    return rtn2
                return tmp_item
        elif isinstance(obj, dict):
            for k, v in obj.items():
                item = JsonParser.find_key_from_dict(v, key, val_key)
                if item is not None:
                    return item
        return False


if __name__ == '__main__':
    # TODO: These need to be adjusted by each environment
    pattern=re.compile(r"([_\-\.]dir|[_\-\.]path|dataDir)")
    value_ecludes=re.compile(r"^/var/run/|^/tmp|^/var/log/|^/etc|^/apps/|^/user|^/app-logs|^/ats/|,|:")

    if len(sys.argv) < 2:
        JsonParser.err("Need a json file")
        sys.exit(0)

    dict = JsonParser.json2dict(sys.argv[1])
    # For debugging purpose
    #print json.dumps(dict, indent=4, sort_keys=True)
    for config_type, properties in dict.items():
        #print config_type
        props = properties.keys()
        for k in props:
            if pattern.search(k) and re.match("/", properties[k]) and properties[k] != "/" and not value_ecludes.search(properties[k]):
                #sys.stderr.write('# '+k+'\n')
                print properties[k]

    sys.stderr.write('# Dirs not in config but maybe used by HDP/Ambari\n')
    print "/usr/hdp/"
    print "/usr/lib/ambari-*"
    print "/var/lib/ambari-*"
    print "/opt/ambari_"
    print "/usr/lib/python2.6/site-packages/resource_monitoring"
    print "/var/lib/hadoop*"
    print "/var/lib/knox"
    sys.stderr.write('# Below may need to change\n')
    #print "/home/xxxxx"
    print "/var/log/"
    print "/tmp/"
