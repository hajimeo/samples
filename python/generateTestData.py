#!/usr/bin/env python
# -*- coding: utf-8 -*-
__author__ = 'hosako'
import fileinput
import re
import random
import string
import sys

def randomStr(length):
    return ''.join(random.choice(string.lowercase) for i in range(length))

def randomInt(length):
    return random.randint(0,length)

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print "Argument should be three (rows, tablename, DDL)"
        exit(1)

    max_char_len = 20

    rows = int(sys.argv[1])
    #print  "rows: "+str(rows)
    tablename = sys.argv[2]
    lines = sys.argv[3].split('\n')

    #lines = []
    #for l in fileinput.input():
    #    lines.append(l)

    for i in range(0, rows):
        rtn = {}
        for line in lines:
            if len(line) == 0:
                continue

            #print  "starting line "+str(line)
            r = re.search('\s*([^\s]+)\s+(.+)', line)
            if r is None:
                #print  "No reg match, skipping for "+str(line)
                continue

            g = r.groups()

            col = string.strip(g[0])
            #print  "processing column:"+str(col)
            r2 = re.search('\s*([a-z0-9]+?)\s*\((\d+)', g[1], re.IGNORECASE)
            if r2 is None:
                if re.search('(DATE|TIME)', g[1], re.IGNORECASE):
                    rtn[col] = "CURRENT_TIMESTAMP"
                elif re.search('(BOOLEAN)', g[1], re.IGNORECASE):
                    rtn[col] = "FALSE"
                elif re.search('(TEXT|LOB)', g[1], re.IGNORECASE):
                    rtn[col] = "NULL"
                #else:
                    # FIXME: at this moment, skip unkonw column type
                    #print "couldn't identify "+str(g[1])+" for "+line
                continue

            g2 = r2.groups()
            #print  "processing datatype:"+str(g2)
            if not g2[1].isdigit():
                print  g2[1]+" is not digit"
                continue

            n = randomInt(int(g2[1]))
            if n > max_char_len:
                n= max_char_len

            if re.search('.*CHAR.*', g2[0], re.IGNORECASE):
                rtn[col] = "'"+randomStr(n)+"'"
            else:
                # FIXME: assuming everything else is numeric...
                rtn[col] = str(randomInt(n))

        #print rtn
        cols = rtn.keys()
        vals = rtn.values()
        cols_str = ', '.join(cols)
        vals_str = ', '.join(vals)
        #print "=========================================================="
        print "  "
        print "INSERT INTO "+tablename+" ("+cols_str+")"
        print " VALUES ("+vals_str+");"
        #print "=========================================================="
