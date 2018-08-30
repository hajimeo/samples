#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Python Jupyter Notebook helper/utility functions
# @author: hajime
#

import sys, os, fnmatch, gzip, re
from multiprocessing import Process
import pandas as pd
from sqlalchemy import create_engine
import sqlite3


### Utility's utility functions


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


def load_jsons(src="./", db_conn=None, string_cols=['connectionId', 'planJson', 'json'], chunksize=None):
    """
    Find json files from current path and load as pandas dataframes object
    :param src: glob(r) source/importing directory path
    :param db_conn: If connection object is given, convert JSON to table
    :param string_cols: As of today, to_sql fails if column is json, so forcing those columns to string
    :return: dict contains Pandas dataframes object
    """
    names_dict = {}
    dfs = {}

    files = globr('*.json', src)
    for f in files:
        new_name = _pick_new_key(f, names_dict, True)
        names_dict[new_name] = f
        dfs[new_name] = pd.read_json(f)
        if bool(db_conn):
            f_name, f_ext = os.path.splitext(os.path.basename(f))
            try:
                # TODO: Temp workaround "<table>: Error binding parameter <N> - probably unsupported type."
                _force_string(df=dfs[new_name], string_cols=string_cols)
                dfs[new_name].to_sql(name=f_name, con=db_conn, chunksize=chunksize)
            # Get error message from Exception
            except Exception as e:
                sys.stderr.write("%s: %s\n" % (str(f_name), str(e)))
                raise
    return (dfs, names_dict)


def _pick_new_key(file, names_dict, using_1st_char=False):
    f_name = os.path.basename(file)
    if using_1st_char:
        new_key = f_name[0]
    else:
        new_key = f_name

    for i in range(0, 9):
        if i > 0:
            new_key = new_key + str(i)
        if new_key in names_dict and names_dict[new_key] == file:
            break
        if new_key not in names_dict:
            break
    return new_key


def _force_string(df, string_cols):
    keys = df.columns.tolist()
    for k in keys:
        if k in string_cols or k.lower().find('json') > 0:
            df[k] = df[k].to_string()


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
    db = _db(dbname=dbname, dbtype=dbtype, isolation_level=isolation_level, force_sqlalchemy=force_sqlalchemy,
             echo=echo)
    if dbtype == 'sqlite':
        if force_sqlalchemy is False:
            db.text_factory = str
        else:
            db.connect().connection.connection.text_factory = str
        return db
    return db.connect()


def _insert2table(conn, tablename, tuple, long_value="", num_cols=None):
    """
    Insert one tuple to a tabale
    :param conn: Connection object created by connect()
    :param tablename: Table name
    :param tuple:
    :param long_value: multi-lines log messages
    :param num_cols: Number of columns in the table to populate missing column as None/NULL
    :return: execute() method result
    """
    if bool(num_cols) and len(tuple) < num_cols:
        # - 1 for message
        for i in range(((num_cols - 1) - len(tuple))):
            tuple += (None,)
    tuple += (long_value,)
    placeholders = ','.join('?' * len(tuple))
    return conn.execute("INSERT INTO " + tablename + " VALUES (" + placeholders + ")", tuple)


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
    :return: A tuple contains last result of conn.execute()
    """
    begin_re = re.compile(line_beginning)
    line_re = re.compile(line_matching)
    if bool(size_regex): size_re = re.compile(size_regex)
    if bool(time_regex): time_re = re.compile(time_regex)
    prev_matches = None
    prev_message = None
    f = read(file)
    # Read lines
    for l in f:
        # If current line is beginning of a new *log* line (eg: ^2018-08-\d\d...)
        if begin_re.search(l):
            # If previous matches aren't empty, save previous date into a table
            if bool(prev_matches):
                # TODO: should insert multiple tuples
                res = _insert2table(conn=conn, tablename=tablename, tuple=prev_matches, long_value=prev_message,
                                    num_cols=num_cols)
                if bool(res) is False:
                    return (res, prev_matches, prev_message, num_cols)
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
        res = _insert2table(conn=conn, tablename=tablename, tuple=prev_matches, long_value=prev_message,
                            num_cols=num_cols)
        if bool(res) is False:
            return (res, prev_matches, prev_message, num_cols)
    return True


def files2table(conn, file_glob, tablename=None,
                col_defs=['datetime', 'loglevel', 'thread', 'jsonstr', 'size', 'time', 'message'],
                num_cols=None, line_beginning="^\d\d\d\d-\d\d-\d\d",
                line_matching="^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) (.+?) \[(.+?)\] (\{.*?\}) (.+)",
                size_regex="[sS]ize = ([0-9]+)", time_regex="time = ([0-9.,]+ ?m?s)",
                max_file_num=10):
    """
    Insert multiple files into one table
    :param conn:  Connection object
    :param file_glob: simple regex used in glob to select files.
    :param tablename: Table name
    :param col_defs: Column definition list or dict (column_name1 data_type, column_name2 data_type, ...)
    :param num_cols: Number of columns in the table. Optional if col_def_str is given.
    :param line_beginning: To detect the beginning of the log entry (normally ^\d\d\d\d-\d\d-\d\d)
    :param line_matching: A group matching regex to separate one log lines into columns
    :param size_regex: (optional) size-like regex to populate 'size' column
    :param time_regex: (optional) time/duration like regex to populate 'time' column
    :param max_file_num: To avoid memory issue, setting max files to import
    :return: A tuple contains multiple information for debug
    """
    # NOTE: as python dict does not guarantee the order, col_def_str is using string
    if bool(num_cols) is False:
        num_cols = len(col_defs)
    files = globr(file_glob)

    if bool(files) is False:
        return False

    if len(files) > max_file_num:
        raise ValueError('Glob: %s returned too many files (%s)' % (file_glob, str(len(files))))

    col_def_str = ""
    if isinstance(col_defs, dict):
        for k, v in col_defs.iteritems():
            if col_def_str != "":
                col_def_str += ", "
            col_def_str += "%s %s" % (k, v)
    else:
        for v in col_defs:
            if col_def_str != "":
                col_def_str += ", "
            col_def_str += "%s TEXT" % (v)

    # If not None, create a table
    if bool(tablename) and bool(col_def_str):
        res = conn.execute("CREATE TABLE IF NOT EXISTS %s (%s)" % (tablename, col_def_str))
        if bool(res) is False:
            return (res, tablename, col_def_str)

    for f in files:
        # TODO: Should use Process or Pool class
        res = file2table(conn=conn, file=f, tablename=tablename, num_cols=num_cols, line_beginning=line_beginning,
                         line_matching=line_matching, size_regex=size_regex, time_regex=time_regex)
        if bool(res) is False:
            return (res, f, tablename)
    return True


def _prepare4df(tuple, long_value="", num_fields=None):
    """
    Insert one tuple to a tabale
    :param tuple:
    :param long_value: multi-lines log messages
    :param num_fields: Number of columns in the table to populate missing column as None/NULL
    :return: modified tuple
    """
    if bool(num_fields) and len(tuple) < num_fields:
        # - 1 for message
        for i in range(((num_fields - 1) - len(tuple))):
            tuple += (None,)
    tuple += (long_value,)
    return tuple


def file2df(file, col_names=None, num_fields=None,
            line_beginning="^\d\d\d\d-\d\d-\d\d",
            line_matching="(.+)", size_regex="", time_regex=""):
    """
    Convert one (log) file to a DataFrame object
    :param file: (Log) file path
    :param col_names: Column name *list*
    :param num_fields: number of columns in the table
    :param line_beginning: To detect the beginning of the log entry (normally ^\d\d\d\d-\d\d-\d\d)
    :param line_matching: A group matching regex to separate one log lines into columns
    :param size_regex: (optional) size-like regex to populate 'size' column
    :param time_regex: (optional) time/duration like regex to populate 'time' column
    :return: A dataframe object
    """
    if bool(num_fields) is False:
        num_fields = len(col_names)
    begin_re = re.compile(line_beginning)
    line_re = re.compile(line_matching)
    if bool(size_regex): size_re = re.compile(size_regex)
    if bool(time_regex): time_re = re.compile(time_regex)
    prev_matches = None
    prev_message = None
    f = read(file)
    tuples = []
    # Read lines
    for l in f:
        # If current line is beginning of a new *log* line (eg: ^2018-08-\d\d...)
        if begin_re.search(l):
            # If previous matches aren't empty, save previous date into a table
            if bool(prev_matches):
                tmp_tuple = _prepare4df(tuple=prev_matches, long_value=prev_message, num_fields=num_fields)
                if bool(tmp_tuple) is False:
                    return (prev_matches, prev_message, num_fields)
                tuples += [tmp_tuple]
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
    # append last message
    if bool(prev_matches):
        tuples += [_prepare4df(tuple=prev_matches, long_value=prev_message, num_fields=num_fields)]
    return pd.DataFrame.from_records(tuples, columns=col_names)


def files2dfs(file_glob, col_names=['datetime', 'loglevel', 'thread', 'jsonstr', 'size', 'time', 'message'],
              num_fields=None, line_beginning="^\d\d\d\d-\d\d-\d\d",
              line_matching="^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) (.+?) \[(.+?)\] (\{.*?\}) (.+)",
              size_regex="[sS]ize = ([0-9]+)", time_regex="time = ([0-9.,]+ ?m?s)",
              max_file_num=10):
    """
    Convert multiple files to multiple DataFrame objects
    :param file_glob: simple regex used in glob to select files.
    :param col_names: Column definition list or dict (column_name1 data_type, column_name2 data_type, ...)
    :param num_fields: Number of columns in the table. Optional if col_def_str is given.
    :param line_beginning: To detect the beginning of the log entry (normally ^\d\d\d\d-\d\d-\d\d)
    :param line_matching: A group matching regex to separate one log lines into columns
    :param size_regex: (optional) size-like regex to populate 'size' column
    :param time_regex: (optional) time/duration like regex to populate 'time' column
    :param max_file_num: To avoid memory issue, setting max files to import
    :return: A concatenated DF object
    """
    # NOTE: as python dict does not guarantee the order, col_def_str is using string
    if bool(num_fields) is False:
        num_fields = len(col_names)
    files = globr(file_glob)

    if bool(files) is False:
        return False

    if len(files) > max_file_num:
        raise ValueError('Glob: %s returned too many files (%s)' % (file_glob, str(len(files))))

    dfs = []
    for f in files:
        # TODO: Should use Process or Pool class
        dfs += [file2df(file=f, col_names=col_names, num_fields=num_fields, line_beginning=line_beginning,
                        line_matching=line_matching, size_regex=size_regex, time_regex=time_regex)]
    return pd.concat(dfs)


# TEST commands
'''
file_glob="debug.2018-08-23*.gz"
tablename="engine_debug_log"
conn = ju.connect()   # Using dbname will be super slow
res = ju.files2table(conn=conn, file_glob=file_glob, tablename=tablename)
print res
conn.execute("select name from sqlite_master where type = 'table'").fetchall()
conn.execute("select sql from sqlite_master where name='%s'" % (tablename)).fetchall()
conn.execute("SELECT MAX(oid) FROM %s" % (tablename)).fetchall()
'''
