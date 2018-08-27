#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os, fnmatch, gzip, re
import pandas as pd
from sqlalchemy import create_engine
import sqlite3

_LAST_FILE_LIST = []  # for debug


### Text processing functions
# As Python 2.7's glob does not have recursive option
def globr(ptn='*', src='./'):
    matches = []
    for root, dirnames, filenames in os.walk(src):
        # os walk doesn't sort and almost random
        for filename in fnmatch.filter(sorted(filenames), ptn):
            matches.append(os.path.join(root, filename))
    return matches


### File handling functions
def read(file):
    if not os.path.isfile(file):
        return None
    if file.endswith(".gz"):
        return gzip.open(file, "rt")
    else:
        return open(file, "r")


def load_jsons(src="./"):
    """
    Find json files from current path and load as pandas dataframes object
    :return: dict contains Pandas dataframes object
    """
    global _LAST_FILE_LIST
    names_dict = {}
    dfs = {}

    _LAST_FILE_LIST = globr('*.json', src)
    for f_path in _LAST_FILE_LIST:
        f_1st_c = os.path.splitext(os.path.basename(f_path))[0][0]
        new_name = f_1st_c
        for i in range(0, 9):
            if i > 0:
                new_name = f_1st_c + str(i)
            if new_name in names_dict and names_dict[new_name] == f_path:
                # print "Found "+new_name+" for "+f_path
                break
            if new_name not in names_dict:
                # print "New name "+new_name+" hasn't been used for "+f_path
                break
        names_dict[new_name] = f_path
        dfs[new_name] = pd.read_json(f_path)
    return (dfs, names_dict)


### DB processing functions
def db(dbname=':memory:', dbtype='sqlite', isolation_level=None, echo=False):
    # if dbtype == 'sqlite':
    #    return sqlite3.connect(dbname, isolation_level=isolation_level)
    return create_engine(dbtype + ':///' + dbname, isolation_level=isolation_level, echo=echo)


def connect(dbname=':memory:', dbtype='sqlite', isolation_level=None, echo=False):
    engine = db(dbname=dbname, dbtype=dbtype, isolation_level=isolation_level, echo=echo)
    if dbtype == 'sqlite':
        engine.connect().connection.connection.text_factory = str
    return engine.connect()


def file2table(db, file, tablename, num_cols, line_beginning="^\d\d\d\d-\d\d-\d\d",
               line_matching="^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) (.+?) (.+?) (\{.*?\}) (.+?) - (.*)"):
    begin_re = re.compile(line_beginning)
    line_re = re.compile(line_matching)
    prev_matches = None
    prev_message = None
    last_res = None
    f = read(file)
    # Read lines
    for l in f:
        # If current line is beginning of a new *log* line (eg: ^2018-08-\d\d...)
        if begin_re.search(l):
            # If previous matches aren't empty, save previous date into a table
            if bool(prev_matches):
                last_res = insert_taple(db=db, values=prev_matches, log_message=prev_message, tablename=tablename,
                                        num_cols=num_cols)
                prev_message = None
                prev_matches = None
            _matches = line_re.search(l)
            if _matches:
                _tmp_groups = _matches.groups()
                prev_message = _tmp_groups[-1]
                prev_matches = _tmp_groups[:(len(_tmp_groups) - 1)]
        else:
            prev_message += "" + l  # Looks like each line already has '\n'
    # insert last message
    if bool(prev_matches):
        last_res = insert_taple(db=db, values=prev_matches, log_message=prev_message, tablename=tablename,
                                num_cols=num_cols)
    return last_res


def insert_taple(db, values, log_message, tablename, num_cols):
    if bool(num_cols) and len(values) < num_cols:
        # - 1 for message
        for i in range(((num_cols - 1) - len(values))):
            values += (None,)
        values += (log_message,)
    placeholders = ','.join('?' * len(values))
    return db.execute("INSERT INTO " + tablename + " VALUES (" + placeholders + ")", values)


def files2table(db, file_glob, tablename, num_cols, create_table_if_not_ddl, line_beginning="^\d\d\d\d-\d\d-\d\d",
                line_matching="^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) (.+?) (.+?) (\{.*?\}) (.+?) - (.*)", max_file_num=10):
    files = globr(file_glob)
    if bool(files) is False: return False
    if len(files) > max_file_num:
        raise ValueError('Glob: %s returned too many files (%s)' % (file_glob, str(len(files))))
    db.execute(create_table_if_not_ddl)
    for f in files:
        file2table(db=db, file=f, tablename=tablename, num_cols=num_cols, line_beginning=line_beginning, line_matching=line_matching)
