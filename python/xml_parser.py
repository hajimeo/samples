#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# XML Parser, and also can compare two XML files, like:
# python ./xml_parser.py hive-site.xml hive-site.xml.backup
#
# Example: use a command line tool
#   ln -s ./xml_parser.py /usr/local/bin/xmldiff
#   ssh -p 2222 root@sandbox.hortonworks.com "echo \"`cat ~/.ssh/id_rsa.pub`\" >> ~/.ssh/authorized_keys"
#   xmldiff ./ams-site.xml <(ssh -Cp 2222 root@sandbox.hortonworks.com cat /etc/ambari-metrics-collector/conf/ams-site.xml)
#

import sys, pprint
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


if __name__ == '__main__':
    if len(sys.argv) < 2:
        XmlParser.fatal('Usage: ' + sys.argv[0] + ' file1.xml [file2.xml]')

    f1 = XmlParser.xml2dict(sys.argv[1])

    if len(sys.argv) == 2:
        pprint.pprint(f1)
        sys.exit(0)

    f2 = XmlParser.xml2dict(sys.argv[2])
    # create a list contains unique keys
    f1k_and_f2k_u = list(set(f1.keys() + f2.keys()))

    out = {}
    for k in f1k_and_f2k_u:
        if not k in f1 or not k in f2 or f1[k] != f2[k]:
            if not k in f1:
                out[k] = [None, f2[k]]
            elif not k in f2:
                out[k] = [f1[k], None]
            else:
                out[k] = [f1[k], f2[k]]

    # TODO: too lazy to format the output
    pprint.pprint(out, width=1)
