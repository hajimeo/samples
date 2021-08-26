#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# gen_delete.py results.json deletes.sql
#
# Expecting below query:
# SELECT dupe_rids, keep_rid FROM (SELECT list(@rid) as dupe_rids, max(@rid) as keep_rid, COUNT(*) as c FROM component GROUP BY bucket, group, name, version) WHERE c > 1 LIMIT 100000;

import sys, json
with open(sys.argv[1]) as f:
    jsList = json.load(f)

with open(sys.argv[2], 'w') as w:
    for js in jsList:
        for dup in js['dupe_rids']:
            if dup != js['keep_rid']:
                w.write("TRUNCATE RECORD %s;\n" % dup)
sys.exit(0)

# Example: converting list JSON to Dict (Map) for Groovy
rtn = {}
for js in jsList:
    if js['repo_name'] not in rtn:
        rtn[js['repo_name']] = [js['name']]
    else:
        rtn[js['repo_name']].append(js['name'])

with open(sys.argv[2], 'w') as f:
    json.dump(rtn, f)