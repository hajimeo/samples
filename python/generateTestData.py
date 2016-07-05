#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys
#import fileinput
import re
import random
import string
import logging

__author__ = 'hosako'
LOG_LEVEL = logging.INFO    # or DEBUG
MAX_STRING_LEN = 64


def randomStr(length):
    return ''.join(random.choice(string.lowercase) for i in range(length))

def randomInt(length):
    return random.randint(0,length)

if __name__ == '__main__':
    logging.basicConfig()
    log = logging.getLogger()
    log.setLevel(LOG_LEVEL)

    if len(sys.argv) != 4:
        print "Argument should be three (rows, tablename, CREATE TABLE statement with one line per column definition)"
        print __file__+" 3 test_table 'CREATE TABLE aaa (...)'"
        exit(1)

    rows = int(sys.argv[1])
    log.debug("rows: "+str(rows))
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

            log.debug("starting line "+str(line))
            r = re.search('\s*`?([^\s`]+)`?\s+(.+)', line)
            if r is None:
                log.debug("No reg match, skipping for "+str(line))
                continue

            g = r.groups()

            col = string.strip(g[0])
            probably_col_def = string.strip(g[1])
            log.debug("column = "+str(col))
            r2 = re.search('([a-z0-9]+?)\s*\((\d+)', probably_col_def, re.IGNORECASE)
            if r2 is None:
                if re.search('(DATE|TIME)', probably_col_def, re.IGNORECASE):
                    rtn[col] = "CURRENT_TIMESTAMP"
                    continue
                elif re.search('(BOOLEAN)', probably_col_def, re.IGNORECASE):
                    rtn[col] = "FALSE"
                    continue
                elif re.search('(TEXT|LOB)', probably_col_def, re.IGNORECASE):
                    rtn[col] = "NULL"
                    continue
                elif re.search('(string|int)', probably_col_def, re.IGNORECASE):
                    r2 = re.search('(string|int)', probably_col_def, re.IGNORECASE)
                    log.debug("don't need to set value in here for "+line)
                else:
                    # FIXME: at this moment, skip unkonw column type
                    log.debug("couldn't identify "+str(probably_col_def)+" for "+line)
                    continue

            n = MAX_STRING_LEN
            g2 = r2.groups()
            log.debug("processing datatype = "+str(g2))
            if len(g2) > 1:
                if not g2[1].isdigit():
                    log.debug(g2[1]+" is not digit")
                    continue
                n = randomInt(int(g2[1]))

            if n > MAX_STRING_LEN:
                n = MAX_STRING_LEN

            if re.search('.*CHAR.*', g2[0], re.IGNORECASE):
                rtn[col] = "'"+randomStr(n)+"'"
            if re.search('.*string.*', g2[0], re.IGNORECASE):
                rtn[col] = "'"+randomStr(n)+"'"
            else:
                # FIXME: assuming everything else is numeric...
                rtn[col] = str(randomInt(n))
            log.debug("rtn["+col+"] = "+str(rtn[col]))

        log.debug("rtn="+str(rtn))
        cols = rtn.keys()
        vals = rtn.values()
        cols_str = '`, `'.join(cols)
        vals_str = ', '.join(vals)
        print "INSERT INTO "+tablename+" (`"+cols_str+"`)"
        print " VALUES ("+vals_str+");"
