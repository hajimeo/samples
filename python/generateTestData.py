#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys
import os
#import fileinput
import re
import random
import string
import logging
import csv

__author__ = 'hosako'
LOG_LEVEL = logging.INFO    # or DEBUG
MAX_STRING_LEN = 64

def help():
    print """Generate INSERT statements or CREATE TABLE statement

How to generate INSERT statements:
    %s INSERT 3 some_tablename 'CREATE TABLE aaa (...)'
 
    Arguments are how_many_rows, table name, and CREATE TABLE statement with one line per column definition

How to generate CREATE TABLE statement:
    %s CREATE ./some_csv_file.csv [some_tablename] [TEXTFILE|ORC]
 
    Arguments are a file path to CSV file, a table name (optional), stored as (optional)
""" % (__file__, __file__)

def randomStr(length):
    return ''.join(random.choice(string.lowercase) for i in range(length))

def randomInt(length):
    return random.randint(0,length)

def printInserts(how_many_rows=0, tablename="", lines_of_create_statement=[]):
    # repeat 'how_many_rows' times
    for i in range(0, how_many_rows):
        tmp = {}
        for line in lines_of_create_statement:
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
                    tmp[col] = "CURRENT_TIMESTAMP"
                    continue
                elif re.search('(BOOLEAN)', probably_col_def, re.IGNORECASE):
                    tmp[col] = "FALSE"
                    continue
                elif re.search('(TEXT|LOB)', probably_col_def, re.IGNORECASE):
                    tmp[col] = "NULL"
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
                tmp[col] = "'"+randomStr(n)+"'"
            if re.search('.*string.*', g2[0], re.IGNORECASE):
                tmp[col] = "'"+randomStr(n)+"'"
            else:
                # FIXME: assuming everything else is numeric...
                tmp[col] = str(randomInt(n))
            log.debug("tmp["+col+"] = "+str(tmp[col]))

        log.debug("tmp="+str(tmp))
        cols = tmp.keys()
        vals = tmp.values()
        cols_str = '`, `'.join(cols)
        vals_str = ', '.join(vals)
        print "INSERT INTO "+tablename+" (`"+cols_str+"`)"
        print " VALUES ("+vals_str+");"
        return True

def printCreateStatementFromCsvFile(csv_file_path, tablename="", stored_as='TEXTFILE', dialect='excel'):
    if len(tablename) == 0:
        tablename=os.path.basename(os.path.splitext(csv_file_path)[0])
    f=open(csv_file_path, 'rb')
    r = csv.reader(f, dialect=dialect)
    column_header=r.next()
    f.close()
    if len(tablename) == 0:
        return False
    print "CREATE TABLE %s (" % (tablename)
    for i in range(0, len(column_header)):
        if (i+1) == len(column_header):
            print "  `%s` string)" % (column_header[i])
        else:
            print "  `%s` string," % (column_header[i])
    print "STORED AS %s;" % (stored_as)
    return True

def prepareCsvFileForImport(csv_file_path, dialect='excel'):
    new_filepath=os.path.splitext(csv_file_path)[0]+".mod.csv"
    if os.path.isfile(new_filepath) and os.path.getsize(new_filepath) > 0:
        log.error("%s already exists" % (new_filepath))
        return False
    f=open(csv_file_path, 'rb')
    r = csv.reader(f, dialect=dialect)
    f2=open(new_filepath, 'wb')
    w = csv.writer(f2, dialect=dialect)
    for row in r:
        new_row=[]
        for v in row:
            # transfer data for Hive (TODO)
            if v.lower() == 'null':
                new_value="\N"
            else:
                new_value="\\n".join(v.split("\n"))
            new_row.append(new_value)
        w.writerow(new_row)
    f.close()
    f2.close()
    return True

def tmpCaseDocumentationQualityCheck(csv_file_path, case_owner_column='Case Owner', how_many=4, dialect='excel'):
    new_filepath=os.path.splitext(csv_file_path)[0]+".random.csv"
    if os.path.isfile(new_filepath) and os.path.getsize(new_filepath) > 0:
        log.error("%s already exists" % (new_filepath))
        return False
    f=open(csv_file_path, 'rb')
    r = csv.reader(f, dialect=dialect)
    case_owner_index=None
    data_per_owner={}
    for row in r:
        if case_owner_index is None:
            case_owner_index=row.index(case_owner_column)
        data_per_owner.setdefault(row[case_owner_index],[]).append(row)
    f.close()
    f2=open(new_filepath, 'wb')
    w = csv.writer(f2, dialect=dialect)
    for case_owner, rows in data_per_owner.iteritems():
        if len(rows) <= how_many:
            new_rows=rows
        else:
            new_rows=random.sample(rows, how_many)
        for new_row in new_rows:
            w.writerow(new_row)
    f2.close()
    return True


if __name__ == '__main__':
    logging.basicConfig()
    log = logging.getLogger()
    log.setLevel(LOG_LEVEL)

    if len(sys.argv) < 3:
        help()
        exit(1)

    if sys.argv[1] == 'CREATE':
        if not os.path.isfile(sys.argv[2]):
            log.error("%s is not a file" % (sys.argv[2]))
            exit(1)

        tablename=""
        stored_as="TEXTFILE"
        if len(sys.argv) > 3:
            tablename = sys.argv[3]
        if len(sys.argv) > 4:
            stored_as = sys.argv[4]
        printCreateStatementFromCsvFile(sys.argv[2], tablename, stored_as)
    elif sys.argv[1] == 'INSERT':
        if len(sys.argv) != 5:
            help()
            exit(1)

        how_many_rows = int(sys.argv[1])
        log.debug("how_many_rows: "+str(how_many_rows))
        tablename = sys.argv[2]
        lines_of_create_statement = sys.argv[3].split('\n')
        #lines_of_create_statement = []
        #for l in fileinput.input():
        #    lines_of_create_statement.append(l)
        printInserts(how_many_rows, tablename, lines_of_create_statement)
    elif sys.argv[1] == 'PREPARE':
        printCreateStatementFromCsvFile(sys.argv[1])
    else:
        help()
        exit(0)

