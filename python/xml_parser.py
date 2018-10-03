#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# sudo easy_install pip
# sudo pip install lxml
#

import sys, pprint, re, json, os
from lxml import etree

def usage():
    usage_str = '''A simple XML Parser
If one xml file is given, outputs "property=value" output (so that can copy&paste into Ambari, ex: Capacity Scheduler)
If two xml files are given, compare and outputs the difference with JSON format.

python %s XXXX-site.xml [YYYY-site.xml] [join type (f|l|r|i)] [exclude regex for key]


To get the latest code:
    curl -O https://raw.githubusercontent.com/hajimeo/samples/master/python/xml_parser.py


Example 1: use as a command line tool on Mac (eg: ln -s %s /usr/local/bin/xmldiff)
    Setup:
      ssh -p 2222 root@sandbox.hortonworks.com "echo \"`cat ~/.ssh/id_rsa.pub`\" >> ~/.ssh/authorized_keys"
    Run:
      _f=/etc/ambari-metrics-collector/conf/ams-site.xml; %s ./${_f} <(ssh -Cp 2222 root@sandbox.hortonworks.com cat ${_f}) 'F' '.+(auth_to_local|\.hue\.).*'

Example 2: Compare all xxx-site.xml between two clusters
    Step 1: collect all configs from a cluster with below tar command
      tar czhvf ./hdp_all_conf_$(hostname).tgz /usr/hdp/current/*/conf /etc/{ams,ambari}-* /etc/ranger/*/policycache /etc/hosts /etc/krb5.conf 2>/dev/null
      
    Step 2: extract hdp_all_conf_xxxx.tgz
    
    Step 3: Compare with same or similar version of your cluster
      find . -type f -name '*-site.xml' | xargs -t -I {} bash -c '_f={};%s $_f <(ssh -Cp 2222 root@sandbox.hortonworks.com cat ${_f#.}) > ${_f}.json'
      
    Step 4: Check the result
      find . -type f -name '*-site.xml.json' -ls

Misc.: for non xml files
    _f=./client.properties; diff -w $_f <(ssh -Cp 2222 root@sandbox.hortonworks.com cat /etc/falcon/conf/$_f)
'''
    filename = os.path.basename(__file__)
    print usage_str % (filename, filename, filename, filename)

class XmlParser:
    @staticmethod
    def fatal(reason):
        sys.stderr.write("FATAL: " + reason + '\n')
        sys.exit(1)

    @staticmethod
    def err(reason, level="ERROR"):
        sys.stderr.write(level + ": " + str(reason) + '\n')
        raise ValueError(str(reason))

    @staticmethod
    def warn(reason, level="WARN"):
        sys.stderr.write(level + ": " + str(reason) + '\n')

    @staticmethod
    def xml2dict(filename, parent_element_name='property', key_element_name='name', value_element_name='value'):
        rtn = {}
        parser = etree.XMLParser(recover=True)
        try:
            r = etree.ElementTree(file=filename, parser=parser).getroot()
        except Exception, e:
            XmlParser.fatal(str(e))
            return rtn

        for p in r.findall('.//' + parent_element_name):
            try:
                name = str(p.find(".//" + key_element_name).text).strip()
                value = str(p.find(".//" + value_element_name).text).strip()
                if len(name) > 0:
                    if value == 'None': value=""
                    rtn[name] = value
            except Exception, e:
                XmlParser.warn(name+" does not have value. "+str(e))
        return rtn

    @staticmethod
    def compare_dict(l_dict, r_dict, join_type='f', ignore_regex=None):
        rtn = {}
        regex = None

        if ignore_regex is not None:
            regex = re.compile(ignore_regex)

        # create a list contains unique keys
        for k in set(l_dict.keys() + r_dict.keys()):
            if regex is not None:
                if regex.match(k):
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
    def output_as_str(dict):
        for k in dict.keys():
            print "%s=%s" % (k, str(dict[k]))



if __name__ == '__main__':
    if len(sys.argv) < 2:
        usage()
        sys.exit(0)

    f1 = XmlParser.xml2dict(sys.argv[1])

    if len(sys.argv) == 2:
        #print json.dumps(f1, indent=0, sort_keys=True, separators=('', '='))
        XmlParser.output_as_str(f1)
        sys.exit(0)

    join_type = 'f'
    if len(sys.argv) > 3:
        join_type = sys.argv[3]

    ignore_regex = None
    if len(sys.argv) == 5:
        ignore_regex = r""+sys.argv[4]  # not so sure if this works, but seems working

    f2 = XmlParser.xml2dict(sys.argv[2])
    out = XmlParser.compare_dict(f1, f2, join_type, ignore_regex)

    # For now, just outputting as JSON (from a dict)
    #pprint.pprint(out)
    print json.dumps(out, indent=4, sort_keys=True)
