#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# NOTE: https://pypi.python.org/pypi/json-delta/ may do better job
#

def usage():
    print '''A simple JSON Parser/Sorter
If one json file is given, outputs "property=value" output (so that can copy&paste into Ambari, ex: Capacity Scheduler)
If two json files are given, compare and outputs the difference with JSON format.

python ./json_parser.py some.json [another.json] [join type (f|l|r|i)] [exclude regex for key]

To get the latest code:
    curl -O https://raw.githubusercontent.com/hajimeo/samples/master/python/json_parser.py
'''

import sys, pprint, re, json
from lxml import etree

class JsonParser:
    @staticmethod
    def fatal(reason):
        sys.stderr.write("FATAL: " + reason + '\n')
        sys.exit(1)

    @staticmethod
    def err(reason, level="ERROR"):
        sys.stderr.write(level + ": " + str(reason) + '\n')
        raise

    @staticmethod
    def warn(reason, level="WARN"):
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
    def compare_dict(l_dict, r_dict, join_type='f', ignore_regex=None):
        rtn = {}
        regex = None

        if ignore_regex is not None:
            regex = re.compile(ignore_regex)

        # create a list contains unique keys
        for k in list(set(l_dict.keys() + r_dict.keys())):
            if regex is not None:
                if regex.match(k):
                    continue
            if isinstance(l_dict[k], dict) and isinstance(r_dict[k], dict):
                tmp_rtn = JsonParser.compare_dict(l_dict[k], r_dict[k], join_type, ignore_regex)
                if len(tmp_rtn) > 0:
                    rtn[k] = tmp_rtn
                continue
            if not k in l_dict or not k in r_dict or l_dict[k] != r_dict[k]:
                if join_type.lower() in ['l', 'i'] and not k in l_dict:
                    continue
                if join_type.lower() in ['r', 'i'] and not k in r_dict:
                    continue

                if not k in l_dict:
                    rtn[k] = [None, r_dict[k]]
                elif not k in r_dict:
                    rtn[k] = [l_dict[k], None]
                else:
                    rtn[k] = [l_dict[k], r_dict[k]]
        return rtn

    @staticmethod
    def output_as_str(obj):
        # TODO: need better output format
        pprint.pprint(obj)

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
    if len(sys.argv) < 2:
        usage()
        sys.exit(0)

    f1 = JsonParser.json2dict(sys.argv[1])

    if len(sys.argv) == 2:
        #print json.dumps(f1, indent=0, sort_keys=True, separators=('', '='))
        JsonParser.output_as_str(f1)
        sys.exit(0)

    join_type = 'f'
    if len(sys.argv) > 3:
        join_type = sys.argv[3]

    ignore_regex = None
    if len(sys.argv) == 5:
        ignore_regex = r""+sys.argv[4]  # not so sure if this works, but seems working

    f2 = JsonParser.json2dict(sys.argv[2])
    out = JsonParser.compare_dict(f1, f2, join_type, ignore_regex)

    # For now, just outputting as JSON (from a dict)
    print json.dumps(out, indent=4, sort_keys=True)
