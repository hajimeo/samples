#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# XML Parser, and also can compare two XML files, like:
# python ./xml_parser.py XXXX-site.xml [YYYY-site.xml] [exclude regex]
#
# Example: use a command line tool
#   ln -s ./xml_parser.py /usr/local/bin/xmldiff
#   ssh -p 2222 root@sandbox.hortonworks.com "echo \"`cat ~/.ssh/id_rsa.pub`\" >> ~/.ssh/authorized_keys"
#   xmldiff ./ams-site.xml <(ssh -Cp 2222 root@sandbox.hortonworks.com cat /etc/ambari-metrics-collector/conf/ams-site.xml) '.+(auth_to_local|\.hue\.).*'
#

import sys, pprint, re
import xml.etree.ElementTree


class XmlParser:
    @staticmethod
    def fatal(reason):
        sys.stderr.write("FATAL " + reason + '\n')
        sys.exit(1)

    @staticmethod
    def err(reason, level="ERROR"):
        sys.stderr.write(level + " " + reason + '\n')
        raise

    @staticmethod
    def xml2dict(filename, parent_element_name='property', key_element_name='name', value_element_name='value'):
        rtn = {}
        r = xml.etree.ElementTree.parse(filename).getroot()
        for p in r.findall('.//' + parent_element_name):
            try:
                name = str(p.find(".//" + key_element_name).text).strip()
                value = str(p.find(".//" + value_element_name).text).strip()
                if len(name) > 0:
                    rtn[name] = value
            except:
                XmlParser.err(name+" does not have value")
        return rtn

    @staticmethod
    def compare_dict(dict1, dict2, ignore_regex=None):
        rtn = {}
        regex = None

        if ignore_regex is not None:
            regex = re.compile(ignore_regex)

        # create a list contains unique keys
        for k in list(set(dict1.keys() + dict2.keys())):
            if regex is not None:
                if regex.match(k):
                    continue;
            if not k in dict1 or not k in dict2 or dict1[k] != dict2[k]:
                if not k in dict1:
                    rtn[k] = [None, dict2[k]]
                elif not k in dict2:
                    rtn[k] = [dict1[k], None]
                else:
                    rtn[k] = [dict1[k], dict2[k]]
        return rtn


if __name__ == '__main__':
    if len(sys.argv) < 2:
        XmlParser.fatal('Usage: ' + sys.argv[0] + ' file1.xml [file2.xml]')

    f1 = XmlParser.xml2dict(sys.argv[1])

    if len(sys.argv) == 2:
        pprint.pprint(f1)
        sys.exit(0)

    ignore_regex = None
    if len(sys.argv) == 4:
        ignore_regex = r""+sys.argv[3]  # not so sure if this works, but seems working

    f2 = XmlParser.xml2dict(sys.argv[2])
    out = XmlParser.compare_dict(f1, f2, ignore_regex)

    # TODO: too lazy to format the output
    pprint.pprint(out, width=1)
