#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Python Jupyter Notebook helper/utility functions
# @author: hajime
#

import sys, os, fnmatch, gzip, re
import pandas as pd
from sqlalchemy import create_engine
import sqlite3


### Text processing functions
def globr(ptn='*', src='./'):
    """
    As Python 2.7's glob does not have recursive option
    :param ptn: glob regex pattern
    :param src: source/importing directory path
    :return: list contains matched file pathes
    """
    matches = []
    for root, dirnames, filenames in os.walk(src):
        # os walk doesn't sort and almost random
        for filename in fnmatch.filter(sorted(filenames), ptn):
            matches.append(os.path.join(root, filename))
    return matches


### File handling functions
def read(file):
    """
    Read a single normal or gz file
    :param file:
    :return: file handler
    """
    if not os.path.isfile(file):
        return None
    if file.endswith(".gz"):
        return gzip.open(file, "rt")
    else:
        return open(file, "r")


def load_jsons(src="./", conn_for_table=None):
    """
    Find json files from current path and load as pandas dataframes object
    :param src: glob(r) source/importing directory path
    :param conn_for_table: If connection object is given, convert JSON to table
    :return: dict contains Pandas dataframes object
    """
    names_dict = {}
    dfs = {}

    files = globr('*.json', src)
    for f in files:
        f_name, f_ext = os.path.splitext(os.path.basename(f))
        _1st_char = f_name[0]
        new_name = _1st_char
        for i in range(0, 9):
            if i > 0:
                new_name = _1st_char + str(i)
            if new_name in names_dict and names_dict[new_name] == f:
                # print "Found "+new_name+" for "+f
                break
            if new_name not in names_dict:
                # print "New name "+new_name+" hasn't been used for "+f
                break
        names_dict[new_name] = f
        dfs[new_name] = pd.read_json(f)
        if bool(conn_for_table):
            dfs[new_name].to_sql(f_name, con=conn_for_table)
    return (dfs, names_dict)


### DB processing functions
# NOTE: without sqlalchemy is faster
def _db(dbname=':memory:', dbtype='sqlite', isolation_level=None, force_sqlalchemy=False, echo=False):
    """
    Create a DB object. For performance purpose, currently not using sqlalchemy if dbtype is sqlite
    :param dbname: Database name
    :param dbtype: DB type
    :param isolation_level: Isolation level
    :param echo: True output more if sqlalchemy is used
    :return: DB object
    """
    if force_sqlalchemy is False and dbtype == 'sqlite':
        return sqlite3.connect(dbname, isolation_level=isolation_level)
    return create_engine(dbtype + ':///' + dbname, isolation_level=isolation_level, echo=echo)


def connect(dbname=':memory:', dbtype='sqlite', isolation_level=None, force_sqlalchemy=False, echo=False):
    """
    Connect to a database
    :param dbname: Database name
    :param dbtype: DB type
    :param isolation_level: Isolation level
    :param echo: True output more if sqlalchemy is used
    :return: connection object
    """
    db = _db(dbname=dbname, dbtype=dbtype, isolation_level=isolation_level, force_sqlalchemy=force_sqlalchemy, echo=echo)
    if dbtype == 'sqlite':
        if force_sqlalchemy is False:
            db.text_factory = str
        else:
            db.connect().connection.connection.text_factory = str
        return db
    return db.connect()


def _insert2table(conn, tablename, taple, long_value="", num_cols=None):
    """
    Insert one taple to a tabale
    :param conn: Connection object created by connect()
    :param tablename: Table name
    :param taple:
    :param long_value: multi-lines log messages
    :param num_cols: Number of columns in the table to populate missing column as None/NULL
    :return: execute() method result
    """
    if bool(num_cols) and len(taple) < num_cols:
        # - 1 for message
        for i in range(((num_cols - 1) - len(taple))):
            taple += (None,)
    taple += (long_value,)
    placeholders = ','.join('?' * len(taple))
    return conn.execute("INSERT INTO " + tablename + " VALUES (" + placeholders + ")", taple)


def file2table(conn, file, tablename, num_cols, line_beginning="^\d\d\d\d-\d\d-\d\d",
               line_matching="(.+)", size_regex="", time_regex=""):
    """
    Insert one file (log) lines into one table
    :param conn: Connection object created by connect()
    :param file: (Log) file path
    :param tablename: Table name
    :param num_cols: number of columns in the table
    :param line_beginning: To detect the beginning of the log entry (normally ^\d\d\d\d-\d\d-\d\d)
    :param line_matching: A group matching regex to separate one log lines into columns
    :param size_regex: (optional) size-like regex to populate 'size' column
    :param time_regex: (optional) time/duration like regex to populate 'time' column
    :return: last result of conn.execute()
    """
    begin_re = re.compile(line_beginning)
    line_re = re.compile(line_matching)
    if bool(size_regex): size_re = re.compile(size_regex)
    if bool(time_regex): time_re = re.compile(time_regex)
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
                last_res = _insert2table(conn=conn, tablename=tablename, taple=prev_matches, long_value=prev_message,
                                         num_cols=num_cols)
                prev_message = None
                prev_matches = None

            _matches = line_re.search(l)
            if _matches:
                _tmp_groups = _matches.groups()
                prev_message = _tmp_groups[-1]
                prev_matches = _tmp_groups[:(len(_tmp_groups) - 1)]

                if bool(size_regex):
                    _size_matches = size_re.search(prev_message)
                    if _size_matches:
                        prev_matches += (_size_matches.group(1),)
                if bool(time_regex):
                    _time_matches = time_re.search(prev_message)
                    if _time_matches:
                        prev_matches += (_time_matches.group(1),)
        else:
            prev_message += "" + l  # Looks like each line already has '\n'
    # insert last message
    if bool(prev_matches):
        last_res = _insert2table(conn=conn, tablename=tablename, taple=prev_matches, long_value=prev_message,
                                 num_cols=num_cols)
    return last_res


def files2table(conn, file_glob, tablename=None,
                col_def="datetime TEXT, loglevel TEXT, thread TEXT, jsonstr TEXT, size TEXT, time TEXT, message TEXT",
                num_cols=None, line_beginning="^\d\d\d\d-\d\d-\d\d",
                line_matching="^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) (.+?) \[(.+?)\] (\{.*?\}) (.+)",
                size_regex="[sS]ize = ([0-9]+)", time_regex="time = ([0-9.,]+ ?m?s)",
                max_file_num=10):
    """
    Insert multiple files into one table
    :param conn:  Connection object
    :param file_glob: simple regex used in glob to select files.
    :param tablename: Table name
    :param col_def: Column definition (column_name1 data_type, column_name2 data_type, ...)
    :param num_cols: Number of columns in the table. Optional if col_def is given.
    :param line_beginning: To detect the beginning of the log entry (normally ^\d\d\d\d-\d\d-\d\d)
    :param line_matching: A group matching regex to separate one log lines into columns
    :param size_regex: (optional) size-like regex to populate 'size' column
    :param time_regex: (optional) time/duration like regex to populate 'time' column
    :param max_file_num: To avoid memory issue, setting max files to import
    :return: last result from file2table()
    """
    # NOTE: as python dict does not guarantee the order, col_def is using string
    if bool(num_cols) is False:
        _cols = col_def.split(",")
        num_cols = len(_cols)
    files = globr(file_glob)
    if bool(files) is False: return False
    if len(files) > max_file_num:
        raise ValueError('Glob: %s returned too many files (%s)' % (file_glob, str(len(files))))
    # If not None, create a table
    if bool(tablename) and bool(col_def):
        conn.execute("CREATE TABLE IF NOT EXISTS %s (%s)" % (tablename, col_def))
    res = None
    for f in files:
        res = file2table(conn=conn, file=f, tablename=tablename, num_cols=num_cols, line_beginning=line_beginning,
                   line_matching=line_matching, size_regex=size_regex, time_regex=time_regex)
        if bool(res) is False:
            return res
    return res


# TEST
# file_glob="debug.2018-08-23*.gz"
# tablename="engine_debug_log"
# conn = ju.connect()
# ju.files2table(conn=conn, file_glob=file_glob, tablename=tablename)
# res = conn.execute("SELECT MAX(oid) FROM "+tablename)
# res.fetchall()
