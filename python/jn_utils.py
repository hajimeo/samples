#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Python Jupyter Notebook helper/utility functions
# @author: hajime
#
# curl https://raw.githubusercontent.com/hajimeo/samples/master/python/jn_utils.py -o $HOME/IdeaProjects/samples/python/jn_utils.py
#
"""
jn_utils is Jupyter Notebook Utility script, which contains functions to convert text files to Pandas DataFrame or DB (SQLite) tables.
To update this script, execute "ju.update()".

== Pandas tips (which I often forget) ==================================
To show more strings in the truncated rows:
    pd.options.display.max_rows = 1000      (default is 60)
To show more strings in a column:
    pd.options.display.max_colwidth = 1000  (default is 50. -1 to disable = show everything)
To show the first 3 rows and the last 3 rows:
    df.iloc[[0,1,2,-3,-2,-1]]
Convert one row to dict:
    row = df[:1].to_dict(orient='records')[0]
Styling:
    https://pandas.pydata.org/pandas-docs/stable/user_guide/style.html

== Sqlite tips (which I often forget) ==================================
Convert Unix timestamp with milliseconds to datetime
    DATETIME(ROUND(dateColumn / 1000), 'unixepoch')
Get date_hour
    UDF_REGEX('(\d\d\d\d-\d\d-\d\d.\d\d)', date_time, 1)
or faster way to get 10mis from the request.log:
    substr(date, 1, 16)
Format datetime to request.log like one: https://www.sqlite.org/lang_datefunc.html (No month abbreviation)
    UDF_STRFTIME('%d/%b/%Y:%H:%M:%S', DATETIME(date_time, '-30 seconds'))||' +0000' as req_date_time
Convert current time or string date to Unix timestamp
    STRFTIME('%s', 'NOW')
    STRFTIME('%s', UDF_REGEX('(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d+)', max(date_time), 1))
or
    UDF_TIMESTAMP('some date like string')
or
    $ q "select (julianday('2020-05-01 00:10:00') - 2440587.5)*86400.0"
    1588291800.0000045
    $ q "select CAST((julianday('2020-05-01 00:10:00') - julianday('2020-05-01 00:00:00')) * 8640000 AS INT)" <<< milliseconds
    600.0000044703484
Get the started time by concatenating today and the time string from 'date' column, then convert to Unix-timestamp
    TIME(CAST((julianday(DATE('now')||' '||substr(date,13,8))  - 2440587.5) * 86400.0 - elapsedTime/1000 AS INT), 'unixepoch') as started_time
or  (4*60*60) is for the timezone offst -0400
    TIME(UDF_TIMESTAMP(date) - CAST(elapsedTime/1000 AS INT) - (4*60*60), 'unixepoch') as started_time
"""

# TODO: When you add a new pip package, don't forget to update setup_work_env.sh
import sys, os, io, fnmatch, gzip, re, json, sqlite3, ast
from time import time
from datetime import datetime
from dateutil import parser

import pandas as pd
from sqlalchemy import create_engine
import matplotlib.pyplot as plt

from sqlite3.dbapi2 import InterfaceError
from json.decoder import JSONDecodeError

try:
    from lxml import etree
    import multiprocessing as mp
    import jaydebeapi
    import IPython
except ImportError:
    # Above modules are not mandatory
    pass

try:
    from urllib.request import urlopen, Request
except ImportError:
    from urllib2 import urlopen, Request

_DEBUG = False
_LOAD_UDFS = True

_LAST_CONN = None
_DB_TYPE = 'sqlite'
_DB_SCHEMA = 'public'
_SIZE_REGEX = r"[sS]ize ?= ?([0-9]+)"
_TIME_REGEX = r"\b([0-9.,]+) ([km]?s)\b"
_SH_EXECUTABLE = "/bin/bash"

# If the HTML string contains '$', Jupyter renders as Italic.
pd.options.display.html.use_mathjax = False


def _mexec(func_obj, args_list, num=None):
    """
    Execute multiple functions asynchronously
    :param func_obj: A function object to be executed
    :param args_list: A list contains tuples of arguments
    :param num: number of pool. if None, half of CPUs (NOTE: if threads, it does not matter)
    :return: list contains results. Currently result order is random (not same as args_list)
    #NOTE: somehow using two items in args_list fails in the unit test (manually running is OK)
    >>> _mexec((lambda x, y: x * y), [(1, 2)])[0]
    2
    """
    rs = []
    if bool(args_list) is False or bool(func_obj) is False:
        return None
    # If only one args list, no point of doing multiprocessing
    if len(args_list) == 1:
        rs.append(func_obj(*args_list[0]))
        return rs
    if bool(num) is False:
        num = int(mp.cpu_count() / 2)
    executor = mp.Pool(processes=num)
    rs = executor.starmap_async(func_obj, args_list)
    return rs.get()


def _chunks(l, n):
    """
    Split/Slice a list by the size 'n'
    From https://stackoverflow.com/questions/312443/how-do-you-split-a-list-into-evenly-sized-chunks
    :param l: A list object
    :param n: Chunk size
    :return: New list
    >>> _chunks([1,2,3,4,5], 2)
    [[1, 2], [3, 4], [5]]
    """
    return [l[i:i + n] for i in range(0, len(l), n)]  # xrange is replaced


def _globr(ptn='*', src='./', loop=0, depth=5, min_size=0, max_size=0, useRegex=False,
           ignoreHidden=True):
    """
    As Python 2.7's glob does not have recursive option
    :param ptn: glob *regex* pattern (usually glob pattern is not regex)
    :param src: source/importing directory path
    :param loop: loop=1 returns only the first match
    :param depth: depth=1 checks only the directories under src
    :param min_size:
    :param useRegex:
    :return: list contains matched file paths
    >>> l = _globr()
    >>> len(l) > 0
    True
    """
    matches = []
    ex = None
    if useRegex and bool(ptn):
        ex = re.compile(ptn)
    n = 0
    start_depth = src.count(os.sep)
    for root, dirnames, filenames in os.walk(src):
        if ignoreHidden and '/.' in root:
            continue
        current_depth = root.count(os.sep) - start_depth + 1
        if root != src and depth > 0 and current_depth >= depth:
            # TODO: os.walk still checks children directories
            continue
        if useRegex:
            for filename in filenames:
                file_path = os.path.join(root, filename)
                if ex is not None and ex.search(file_path):
                    matches.append(file_path)
                    n = n + 1
                    if 0 < loop <= n:
                        break
        else:
            for filename in fnmatch.filter(filenames, ptn):
                matches.append(os.path.join(root, filename))
                n = n + 1
                if 0 < loop <= n:
                    break
    if min_size > 0 or max_size > 0:
        # Tricky! You can't use list.remove() while looping this list (also .copy() is needed)
        _matches = matches.copy()
        for filepath in _matches:
            file_size = int(_get_filesize(filepath))
            if min_size > 0 and file_size < min_size:
                matches.remove(filepath)
            elif max_size > 0 and file_size > max_size:
                matches.remove(filepath)
    # os.walk doesn't sort and looks like random order
    return sorted(matches)


def _get_file(filename):
    if os.path.isfile(filename):
        return filename
    files = _globr(filename)
    if bool(files) is False:
        return None
    return files[0]


def _is_numeric(some_num):
    """
    Python's isnumeric return False for float!!!
    :param some_num:
    :return: boolean
    >>> _is_numeric(1.234)
    True
    """
    try:
        float(some_num)
        return True
    except:
        return False


def _get_filesize(file_path):
    """
    os.stat(xxx).st_size and os.path.getsize(xxx) both fails if file path is wrong
    :param file_path: string of the file path
    :return: boolean or file size
    >>> _get_filesize("jn_utils.py") > 0
    True
    """
    try:
        if os.path.isfile(file_path):
            return os.path.getsize(file_path)
        return False
    except:
        return False


def _is_jupyter():
    is_jupyter = True
    try:
        get_ipython()
    except:
        is_jupyter = False
    return is_jupyter


def _open_file(file, mode="r"):
    """
    Open one text or gz file
    :param file:
    :return: file handler
    >>> f = _open_file(__file__);f.name == __file__
    True
    """
    if not os.path.isfile(file):
        return None
    if file.endswith(".gz"):
        _debug("opening %s" % (file))
        return gzip.open(file, "%st" % (mode))
    else:
        return open(file, mode)


def _extract_zip(zipfile, dest=None):
    """
    Extract a zip file into the destination or a temp directory
    :param zipfile: String for the zip file path
    :param dest:    String for the destination path
    :return: None or TemporaryDirectory object
    """
    tempObj = None
    if bool(dest) is False:
        import tempfile
        tempObj = tempfile.TemporaryDirectory()
        dest = tempObj.name
    from zipfile import ZipFile
    with ZipFile(zipfile, 'r') as zf:
        zf.extractall(dest)
    return tempObj


def _generator(obj):
    """
    Return generator so that don't need to worry about List or Dict for looping
    :param obj: dict or list
    :return: Generator object
    """
    return obj if isinstance(obj, dict) else (i for i, v in enumerate(obj))


def _timestamp(unixtimestamp=None, format=None):
    """
    Format Unix Timestamp with a given format
    NOTE: '%f' is used as miliseconds
    :param unixtimestamp: Int (or float, but number after dot will be ignored)
    :param format: Default is %Y-%m-%d %H:%M:%S.%f[:-3]
    :return: Formatted string
    >>> dt_str = _timestamp(1543189639)
    >>> dt_str.startswith('2018')
    True
    """
    if bool(unixtimestamp) is False:
        unixtimestamp = time()
    dt = datetime.fromtimestamp(float(unixtimestamp))
    if format is None:
        return dt.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
    if format.endswith('%f'):
        return dt.strftime(format)[:-3]
    return dt.strftime(format)


def _log(level, message, format="%H:%M:%S.%f"):
    sys.stderr.write("[%s] %-5s %s\n" % (_timestamp(format=format), level, str(message)))


def _info(message):
    _log("INFO", message)


def _err(message):
    _log("ERROR", message)


def _debug(message, dbg=False):
    global _DEBUG
    if _DEBUG or dbg:
        _log("DEBUG", message)


def load_jsons(src="./", conn=None, include_ptn='*.json', exclude_ptn='', chunksize=1000,
               json_cols=[], flatten=None, useRegex=False, max_file_size=0):
    """
    Find json files from current path and load as pandas dataframes object
    :param src: source/importing directory path
    :param conn: If connection object is given, convert JSON to table
    :param include_ptn: Regex string to include some file
    :param exclude_ptn: Regex string to exclude some file
    :param chunksize: Rows will be written in batches of this size at a time. By default, all rows will be written at once
    :param json_cols: to_sql() fails if column is json, so do some workaround against those columns
    :param flatten: If true, use json_normalize()
    :param useRegex: whether use regex or not to find json files
    :return: A tuple contain key=>file relationship and Pandas dataframes objects
    #>>> (names_dict, dfs) = load_jsons(src="./engine/aggregates")
    #>>> bool(names_dict)
    #True
    >>> pass    # TODO: implement test
    """
    names_dict = {}
    dfs = {}
    ex = None
    if bool(exclude_ptn):
        ex = re.compile(exclude_ptn)

    files = _globr(ptn=include_ptn, src=src, useRegex=useRegex, max_size=max_file_size)
    for f in files:
        f_name, f_ext = os.path.splitext(os.path.basename(f))
        if ex is not None and ex.search(f_name):
            _info("Excluding %s as per exclude_ptn (%d KB)..." % (f_name, _get_filesize(f) / 1024))
            continue
        new_name = _pick_new_key(f_name, names_dict, prefix='t_')
        names_dict[new_name] = f
        dfs[new_name] = json2df(filename=f, conn=conn, tablename=new_name, chunksize=chunksize, json_cols=json_cols,
                                flatten=flatten)
    if bool(conn):
        del (names_dict)
        del (dfs)
        return None
    return (names_dict, dfs)


def json2df(filename, tablename=None, conn=None, chunksize=1000, if_exists='replace', jq_query="",
            max_file_size=(1024 * 1024 * 100),
            flatten=None, json_cols=[], line_by_line=False, line_from=0, line_until=0):
    """
    Convert a json file, which contains list into a DataFrame
    If conn is given, import into a DB table
    :param filename: File path or file name or glob pattern
    :param tablename: If empty, table name will be the filename without extension
    :param conn:   DB connection object
    :param chunksize: to split the data (used in pandas to_sql)
    :param if_exists: 'fail', 'replace', or 'append'
    :param jq_query: String used with ju.jq(), to filter json record
    :param flatten: If true, use json_normalize()
    :param json_cols: to_sql() fails if column is json, so forcing those columns to string
    :param line_by_line: Another way to workaround 'Error binding parameter'
    :param line_from: To exclude unnecessary lines. line_by_line = true requreid
    :param line_until: To exclude unnecessary lines. line_by_line = true requreid
    :return: a DataFrame object
    #>>> json2df('./export.json', '.records | map(select(.["@class"] == "quartz_job_detail" and .value_data.jobDataMap != null))[] | .value_data.jobDataMap', ju.connect(), 't_quartz_job_detail')
    #>>> json2df('audit.json', '..|select(.attributes? and .attributes.".typeId" == "db.backup")|.attributes', ju.connect(), "t_audit_attr_dbbackup_logs")
    #>>> ju.json2df(filename="./audit.json", json_cols=['data', 'data.roleMembers', 'data.policyConstraints', 'data.applicationCategories', 'data.licenseNames'], conn=ju.connect())
    >>> pass    # TODO: implement test
    """
    # If flatten is not specified but going to import into Sqlite, changing flatten to true so that less error in DB
    if flatten is None and (tablename is not None or conn is not None):
        flatten = True
    # If table name is specified but no conn object, create it
    if bool(tablename) and conn is None:
        conn = connect()

    if os.path.exists(filename):
        files = [filename]
    else:
        files = _globr(filename)
        if bool(files) is False:
            _debug("No %s. Skipping ..." % (str(filename)))
            return None

    dfs = []
    for file_path in files:
        fs = _get_filesize(file_path)
        if fs >= max_file_size:
            _info("WARN: File %s (%d MB) is too large (max_file_size=%d)." % (
                file_path, int(fs / 1024 / 1024), max_file_size))
            continue
        if fs < 32:
            _info("%s is too small (%d) as JSON. Skipping ..." % (str(file_path), fs))
            continue
        _info("Loading %s ..." % (str(file_path)))
        if bool(jq_query):
            obj = jq(file_path, jq_query)
            dfs.append(pd.DataFrame(obj))
        else:
            # TODO: currently too slow to use.
            if line_by_line:
                _dfs = []
                _ln = 0
                for line in _open_file(file_path):
                    _ln += 1
                    if bool(line_from) and _ln < line_from:
                        continue
                    if bool(line_until) and _ln > line_until:
                        continue
                    try:
                        j_obj = json.loads(line.rstrip(','))
                    except:
                        # Ignore any non json strings
                        continue
                    #__df = pd.DataFrame.from_dict(_js, orient="columns")
                    __df = pd.json_normalize(j_obj).fillna("")
                    if len(__df) > 0:
                        _dfs.append(__df)
                if len(_dfs) > 0:
                    _df = pd.concat(_dfs, sort=False)
            elif flatten is True:
                try:
                    with open(file_path) as f:
                        j_obj = json.load(f)
                    # 'fillna' is for workaround-ing "probably unsupported type." (because of N/a)
                    _df = pd.json_normalize(j_obj).fillna("")
                except JSONDecodeError as e:
                    _err("%s for %s" % (str(e), file_path))
                    continue
            else:
                try:
                    _df = pd.read_json(file_path)
                except UnicodeDecodeError:
                    _df = pd.read_json(file_path, encoding="iso-8859-1")
            dfs.append(_df)  # , dtype=False (didn't help)

    if bool(dfs) is False:
        return False

    df = pd.concat(dfs, sort=False)
    if bool(conn):
        if bool(json_cols) is False:
            # TODO: if non first raw contains dict or list?
            first_row = df[:1].to_dict(orient='records')[0]  # 'records' is for list like data
            for k in first_row:
                if type(first_row[k]) is dict or type(first_row[k]) is list:
                    json_cols.append(k)
        if bool(tablename) is False:
            tablename = _pick_new_key(os.path.basename(files[0]), {}, using_1st_char=False, prefix='t_')
        # Temp workaround: "<table>: Error binding parameter <N> - probably unsupported type."
        # Temp workadound2: if flatten is true, converting to str for all columns...
        _debug("json_cols: %s" % (str(json_cols)))
        df_tmp_mod = _avoid_unsupported(df=df, json_cols=json_cols, all_str=flatten, name=tablename, max_row_size=int(max_file_size/100))
        if df2table(df=df_tmp_mod, tablename=tablename, conn=conn, chunksize=chunksize, if_exists=if_exists) is True:
            _info("Created table: %s " % (tablename))
            _autocomp_inject(tablename=tablename)
    return df


def _json2table(filename, tablename=None, conn=None, col_name='json_text', appending=False):
    """
    NOT WORKING
    """
    pass
    if conn is None:
        conn = connect()
    with open(filename) as f:
        j_obj = json.load(f)
    if not j_obj:
        return False
    j_str = json.dumps(j_obj)

    if bool(tablename) is False:
        tablename = _pick_new_key(filename, {}, using_1st_char=False, prefix='t_')

    if appending is False:
        res = execute("DROP TABLE IF EXISTS %s" % (tablename))
        if bool(res) is False:
            return res
        _debug("DROP-ed TABLE IF EXISTS %s" % (tablename))
    res = execute("CREATE TABLE IF NOT EXISTS %s (%s TEXT)" % (tablename, col_name))  # JSON type not supported?
    if bool(res) is False:
        return res
    rtn = conn.executemany("INSERT INTO " + tablename + " VALUES (?)", str(j_str))
    if bool(rtn):
        _info("Created table: %s" % (tablename))
    return rtn


def jq(file_path, query='.', as_string=False):
    """
    Read a json file and query with 'jq' syntax
    NOTE: Requires 'pyjq' package.
    @see https://stedolan.github.io/jq/tutorial/ for query syntax
    :param file_path: Json File path
    :param query: 'jq' query string (looks like dict)
    :param as_string: if true, convert result to string
    :return: whatever pyjq returns
    #>>> pd.DataFrame(ju.jq('./export.json', '.records | map(select(.value_data != null))[] | .value_data'))
    >>> pass    # TODO: implement test
    """
    try:
        import pyjq
    except ImportError:
        _err("importing pyjq failed")
        return
    jd = json2dict(file_path)
    result = pyjq.all(query, jd)
    if len(result) == 1:
        result = result[0]
    if as_string:
        result = str(result)
    return result


def json2dict(file_path, sort=True):
    """
    Read a json file and return as dict
    :param file_path: Json File path
    :param sort:
    :return: Python dict
    >>> pass    # TODO: implement test
    """
    with open(file_path) as f:
        rtn = json.load(f)
    if not rtn:
        return {}
    if sort:
        rtn = json.loads(json.dumps(rtn, sort_keys=sort))
    return rtn


def xml2df(file_path, row_element_name, tbl_element_name=None, conn=None, tablename=None, chunksize=1000,
           if_exists='replace'):
    """
    Convert a XML file into a DataFrame
    If conn is given, import into a DB table
    :param file_path: File path
    :param row_element_name: Name of XML element which is used to find table rows
    :param tbl_element_name: Name of XML element which is used to find tables (Optional)
    :param conn:   DB connection object
    :param tablename: If empty, table name will be the filename without extension
    :param chunksize: to split the data
    :param if_exists: 'fail', 'replace', or 'append'
    :return: a DataFrame object
    #>>> xml2df('./nexus.xml', 'repository', conn=ju.connect())
    >>> pass    # TODO: implement test
    """
    data = xml2dict(file_path, row_element_name, tbl_element_name)
    df = pd.DataFrame(data)
    if bool(conn):
        if bool(tablename) is False:
            tablename, ext = os.path.splitext(os.path.basename(file_path))
        if df2table(df=df, tablename=tablename, conn=conn, chunksize=chunksize, if_exists=if_exists) is True:
            _info("Created table: %s" % (tablename))
            _autocomp_inject(tablename=tablename)
    return df


def xml2dict(file_path, row_element_name, tbl_element_name=None, tbl_num=0):
    rtn = []
    parser = etree.XMLParser(recover=True)
    try:
        r = etree.ElementTree(file=file_path, parser=parser).getroot()
        if bool(tbl_element_name) is True:
            tbls = r.findall('.//' + tbl_element_name)
            if len(tbls) > 1:
                _info("%s returned more than 1. Using tbl_num=%s" % (tbl_element_name, str(tbl_num)))
            rows = tbls[tbl_num].findall(".//" + row_element_name)
        else:
            rows = r.findall(".//" + row_element_name)
        _debug("rows num: %d" % (len(rows)))
        for row in rows:
            _row = {}
            for col in list(row):
                _row[col.tag] = ''.join(col.itertext()).strip()
            rtn.append(_row)
    except Exception as e:
        _err(str(e))
    return rtn


def _pick_new_key(name, names_dict, using_1st_char=False, check_global=False, prefix=None):
    """
    Find a non-conflicting a dict key for given name (normally a file name/path)
    :param name: name to be saved or used as a dict key
    :param names_dict: list of names which already exist
    :param using_1st_char: if new name
    :param check_global: Check if new name is used as a global variable
    :param prefix: Appending some string (eg: 'tbl_') at the beginning of the name
    :return: a string of a new dict key which hasn't been used
    >>> _pick_new_key('test', {'test':'aaa'}, False)
    'test1'
    >>> _pick_new_key('test', {'test':'aaa', 't':'bbb'}, True)
    't1'
    """
    name = re.sub(r'\W+', '_', name)
    if using_1st_char:
        name = name[0]
    if bool(prefix):
        new_key = prefix + name
    else:
        new_key = name

    for i in range(0, 9):
        if i > 0:
            new_key = name + str(i)
        if new_key in names_dict and names_dict[new_key] == name:
            break
        if new_key not in names_dict and check_global is False:
            break
        if new_key not in names_dict and check_global is True and new_key not in globals():
            break
    return new_key


def _avoid_unsupported(df, json_cols=[], all_str=False, name=None, max_row_size=1000000):
    """
    Convert DF cols for workarounding "<table>: Error binding parameter <N> - probably unsupported type."
    :param df: A *reference* of panda DataFrame
    :param json_cols: List contains column names. Ex. ['connectionId', 'planJson', 'json']
    :param all_str: If True and df is not too large, convert all columns to string
    :param name: just for extra loggings
    :return: Modified df
    >>> import pandas as pd
    >>> _avoid_unsupported(pd.DataFrame([{"a_json":{"a":"a-val","b":"b-val"}, "test":12345}]), ["test"]).values
    array([["{'a': 'a-val', 'b': 'b-val'}", '12345']], dtype=object)
    """
    if bool(json_cols) is False and all_str is False:
        return df
    if len(df) > max_row_size:  # don't want to convert huge df
        _err("_avoid_unsupported does not convert this large df (%d) (max_row_size = %d)" % (len(df), max_row_size))
        return df
    keys = df.columns.tolist()
    cols = {}
    for k in keys:
        k_str = str(k)
        if k_str in json_cols or k_str.lower().find('json') > 0:
            _debug("_avoid_unsupported: k_str = %s" % (k_str))
            # df[k_str] = df[k_str].to_string()
            cols[k_str] = 'str'
        elif all_str:
            cols[k_str] = 'str'
    if len(cols) > 0:
        if bool(name):
            _debug(" - converting columns:%s." % (str(cols)))
        return df.astype(cols)
    return df


### Database/DataFrame processing functions
# NOTE: without sqlalchemy is faster
def _db(conn_str=':memory:', dbtype='sqlite', isolation_level=None, use_sqlalchemy=False, echo=False):
    """
    Create a DB object. For performance purpose, currently not using sqlalchemy if dbtype is sqlite
    :param conn_str: Database connection string after "//"
                    For example, "<hostname>:<port>/<database>?<arg1>=<val1>"
    :param dbtype: DB type
    :param isolation_level: Isolation level
    :param use_sqlalchemy: Use sqlalchemy
    :param echo: True output more if sqlalchemy is used
    :return: DB object
    >>> pass    # testing in connect()
    """
    global _DB_TYPE
    _DB_TYPE = dbtype
    if use_sqlalchemy is False and dbtype == 'sqlite':
        return sqlite3.connect(conn_str, isolation_level=isolation_level)
    if dbtype == 'sqlite':
        conn_str = dbtype + ':///' + conn_str
    elif dbtype == 'hive':
        return hive_conn("jdbc:hive2://" + conn_str)
    else:
        conn_str = dbtype + '://' + conn_str
    return create_engine(conn_str, isolation_level=isolation_level, echo=echo)


# Seems sqlite doesn't have regex (need to import pcre.so)
def udf_regex(regex, item, rtn_idx=0):
    """
    Regex UDF for SQLite
    eg: SELECT UDF_REGEX('queryId=([0-9a-f-]+)', ids, 1) as query_id, ...
    :param regex:   String - Regular expression
    :param item:    String - Column name
    :param rtn_idx: Integer - Grouping result index start from 1
    :return:        Mixed   - Group(idx) result
    >>> udf_regex('(\d\d\d\d-\d\d-\d\d.\d\d)', "2019-10-14 00:00:05", 1)
    '2019-10-14 00'
    """
    matches = re.search(regex, item)
    # If 0, return true or false (expecting to use in WHERE clause)
    if rtn_idx == 0:
        return bool(matches)
    if bool(matches) is False:
        return None
    return matches.group(rtn_idx)


def udf_str2sqldt(date_time):
    """
    Convert date_time string to SQLite friendly ISO date_time string with "." milliseconds, instead of ","
    eg: SELECT UDF_STR2SQLDT('14/Oct/2019:00:00:05 +0800') as SQLite_DateTime, ...
    "2019-10-14 00:00:05.000000+0800"
    :param date_time:   String - Date and Time string
    :return:            String - SQLite accepting date time string
    >>> udf_str2sqldt("14/Oct/2019:00:00:05 +0800")
    '2019-10-14 00:00:05.000000+0800'
    """
    # 14/Oct/2019:00:00:05 +0800 => 2013-10-07 04:23:19.120-04:00
    # https://docs.python.org/3/library/datetime.html#strftime-and-strptime-behavior
    if date_time.count(":") >= 3:
        # assuming the format is "%d/%b/%Y:%H:%M:%S %z"
        date_str, time_str = date_time.split(":", 1)
        date_time = date_str + " " + time_str
    return parser.parse(date_time).strftime("%Y-%m-%d %H:%M:%S.%f%z")


def udf_strftime(format, date_time):
    """
    Sqlite STRFTIME does not have Month abbribiation (almost same as udf_str2sqldt but 2 arguments)
    eg: SELECT UDF_STRFTIME('14/Oct/2019:00:00:05 +0800', '%d/%b/%Y:%H:%M:%S %z') as request_datetime, ...
    :param format:      String - Date and Time format supported by python's strftime
    :param date_time:   String - Date and Time string
    :return:            String - Formatted date time string
    >>> udf_strftime("%d/%b/%Y:%H:%M:%S", "2021-07-30 05:59:16.999+0000")
    '30/Jul/2021:05:59:16'
    """
    return parser.parse(date_time).strftime(format)


def udf_timestamp(date_time):
    """
    Sqlite UDF for converting date_time string to Unix timestamp
    eg: SELECT UDF_TIMESTAMP(some_datetime) as unix_timestamp, ...

    NOTE: SQLite's STRFTIME('%s', 'YYYY-MM-DD hh:mm:ss') also return same.
          or CAST((julianday(some_datetime) - 2440587.5)*86400.0 as INT)
    :param date_time: ISO date string (or Date/Time column but SQLite doesn't have date/time columns)
    :return:          Integer of Unix Timestamp
    >>> udf_timestamp("14/Apr/2021:06:39:42 +0000")
    1618382382
    >>> udf_timestamp("14/Apr/2021:06:39:42 -0400")
    1618396782
    >>> udf_timestamp("2021-04-14 06:39:42+0000")
    1618382382
    """
    if date_time.count(":") >= 3:
        # assuming the date_time uses "%d/%b/%Y:%H:%M:%S %z". This format doesn't work with parse, so changing.
        date_str, time_str = date_time.split(":", 1)
        date_time = date_str + " " + time_str
    # Seems mktime calculates offset string unnecessarily, so don't use mktime
    return int(parser.parse(date_time).timestamp())


def udf_str_to_int(some_str):
    """
    Convert \d\d\d\d(MB|M|GB\G) to bytes etc.
    eg: SELECT UDF_STR_TO_INT(some_string) as xxxx, ...
    :param some_str: 350M, 350MB, 350GB, 350G, 60s, 60m, 60ms, 60%
    :return:         Integer
    """
    if some_str is None:
        return None
    matches = re.search('([\d.\-]+) ?([a-zA-z%]*)', some_str)
    if bool(matches) is False:
        return None
    num = float(matches.group(1))
    if len(matches.groups()) > 1:
        unit = matches.group(2).upper()
    else:
        return num
    if unit in ['B', 'MS', '%']:
        return num
    if unit in ['G', 'GB']:
        return int(num * 1024 * 1024 * 1024)
    if unit in ['M', 'MB']:
        return int(num * 1024 * 1024)
    if unit in ['K', 'KB']:
        return int(num * 1024)
    if unit in ['S', 'SEC']:
        return int(num * 1000)
    if unit in ['M', 'MIN']:
        return int(num * 1000 * 60)
    if unit in ['H', 'HOUR']:
        return int(num * 1000 * 60 * 60)
    return num


def udf_num_human_readable(some_numeric, base_unit):
    """
    TODO: Convert integer|float|decimal to human readable string.
    eg: SELECT UDF_NUM_HUMAN_READABLE(some_numeric, 'byte') as xxxx, ...
    :param some_numeric: 100, 123.45
    :param base_unit: 'byte' or 'bytes' or 'sec' or 'seconds'
    :return: string
    """
    if _is_numeric(some_numeric):
        return _human_readable_num(some_numeric, base_unit)
    else:
        return some_numeric


def _human_readable_num(some_numeric, base_unit="byte", r=2):
    """
    Convert integer|float|decimal to human readable string.
    eg: SELECT UDF_NUM_HUMAN_READABLE(some_numeric, 'byte') as xxxx, ...
    :param some_numeric: 100, 123.45
    :param base_unit: 'byte' or 'bytes' or 'msec' or 'milliseconds'
    :param r: used in round function
    :return: string|object
    >>> _human_readable_num("1234567890123.756")
    '1.23 TB'
    >>> _human_readable_num("1234567890.756", "msec")
    '14.29 h'
    """
    # If some_numeric is not string or not number, loop object and return the object
    if type(some_numeric) in [dict, list]:
        for k in _generator(some_numeric):
            some_numeric[k] = _human_readable_num(some_numeric[k], base_unit)
        return some_numeric
    elif _is_numeric(some_numeric):
        n = float(some_numeric)
        if base_unit in ['byte', 'bytes']:
            units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
            u_idx = int((len(str(int(abs(n)))) - 1) / 3)
            if u_idx == 0:
                return str(round(n, r)) + " " + units[u_idx]
            return str(round(n / (1000 ** u_idx), r)) + " " + units[u_idx]
        elif base_unit in ['msec', 'milliseconds']:
            # base = list(reversed([1000, 60000, 3600000, 86400000]))
            base = [86400000, 3600000, 60000, 1000]
            units = ['d', 'h', 'm', 's', 'ms']
            # Need to be reverse order for time
            for i in _generator(base):
                if abs(n) > base[i]:
                    return str(round(n / base[i], r)) + " " + units[1]
    # Not numeric and not iterable, so no idea
    return some_numeric


def _register_udfs(conn):
    """
    Register all UDFs (NOTE: do not forget to udpate this function when a new one is created)
    How to check: SELECT * FROM pragma_function_list WHERE name like 'UDF_%';
    :param conn:
    :return:
    """
    global _LOAD_UDFS
    if _LOAD_UDFS:
        # UDF_REGEX(regex, column, integer)
        conn.create_function("UDF_REGEX", 3, udf_regex)
        conn.create_function("UDF_STR2SQLDT", 1, udf_str2sqldt)
        conn.create_function("UDF_STRFTIME", 2, udf_strftime)
        conn.create_function("UDF_TIMESTAMP", 1, udf_timestamp)
        conn.create_function("UDF_STR_TO_INT", 1, udf_str_to_int)
        conn.create_function("UDF_NUM_HUMAN_READABLE", 1, udf_num_human_readable)
    return conn


def connect(conn_str=':memory:', dbtype='sqlite', isolation_level=None, use_sqlalchemy=False, echo=False):
    """
    Connect to a database (SQLite)
    :param conn_str: Database name
    :param dbtype: DB type sqlite or postgres
    :param isolation_level: Isolation level
    :param use_sqlalchemy: Use sqlalchemy
    :param echo: True outputs more if sqlalchemy is used
    :return: connection (cursor) object
    >>> import sqlite3;s = connect()
    >>> isinstance(s, sqlite3.Connection)
    True
    """
    global _LAST_CONN
    if bool(_LAST_CONN): return _LAST_CONN

    db = _db(conn_str=conn_str, dbtype=dbtype, isolation_level=isolation_level, use_sqlalchemy=use_sqlalchemy,
             echo=echo)
    if dbtype == 'sqlite':
        if use_sqlalchemy is False:
            db.text_factory = str
        else:
            db.connect().connection.connection.text_factory = str
        # For 'sqlite, 'db' is the connection object because of _db()
        conn = _register_udfs(db)
    # elif dbtype == 'postgres':
    #    _debug("TODO: do something")
    #    conn = db.connect()
    else:
        conn = db.connect()
    if bool(conn): _LAST_CONN = conn
    return conn


def execute(sql, conn=None, no_history=False):
    """
    Execute a SQL statement (updte|insert into|delete
    :param sql: SQL statement
    :param conn: DB connection object
    :param no_history: not saving this query into a history file
    :return: result or void
    >>> r = execute("UPDATE sqlite_master SET name = name where type = 'testtesttesttest'", connect(), True)
    >>> bool(r)
    True
    """
    if conn is None:
        conn = connect()
    result = conn.execute(sql)
    if no_history is False and bool(result):
        _save_query(sql)
    return result


def query(sql, conn=None, no_history=False, show=False):
    """
    Call pd.read_sql() with given query, expecting SELECT statement
    :param sql: SELECT statement
    :param conn: DB connection object
    :param no_history: not saving this query into a history file
    :param show: True/False or integer to draw HTML (NOTE: False is faster)
    :return: a DF object or void
    >>> query("select name from sqlite_master where type = 'table'", connect(), True)
    Empty DataFrame
    Columns: [name]
    Index: []
    """
    if conn is None:
        conn = connect()
    # return conn.execute(sql).fetchall()
    # TODO: pd.options.display.max_colwidth = col_width does not work
    df = pd.read_sql(sql, conn)
    # TODO: Trying to set td tags alignment to left but not working
    # dfStyler = df.style.set_properties(**{'text-align': 'left'})
    # dfStyler.set_table_styles([dict(selector='td', props=[('text-align', 'left')])])
    if no_history is False and df.empty is False:
        _save_query(sql)
    if bool(show):
        show_num = 1000
        try:
            if show is not True:
                show_num = int(show)
        except ValueError:
            pass
        display(df, tail=show_num)
        return
    return df


q = query


def query_execute(sql, conn):
    """
    Call conn.execute() then conn.fetchall() with given query, expecting SELECT statement
    Comparing to query(), this should support more databases, such as Hive, but NOT SQLite...
    :param sql: (SELECT) SQL statement
    :param conn: DB connection (cursor)
    :return: Panda DataFrame
    #>>> hc = hive_conn("jdbc:hive2://localhost:10000/default")
    #>>> df = query_execute("SELECT 1", hc)
    #>>> bool(df)
    #True
    >>> pass    # TODO: implement test
    """
    conn.execute(sql)
    result = conn.fetchall()
    if bool(result):
        return pd.DataFrame(result)
    return result


def _save_query(sql, limit=1000):
    """
    Save a sql into a history file
    :param sql: query string
    :param limit: How many queies stores into a history file. Default is 1000
    :return: void
    >>> pass    # Testing in qhistory()
    """
    query_history_csv = os.getenv('JN_UTILS_QUERY_HISTORY', os.getenv('HOME') + os.path.sep + ".ju_qhistory")
    # removing spaces and last ';'
    sql = sql.strip().rstrip(';')
    df_new = pd.DataFrame([[_timestamp(format="%Y%m%d%H%M%S"), sql]], columns=["datetime", "query"])
    df_hist = csv2df(query_history_csv, header=None)
    if df_hist is False or df_hist is None:
        df = df_new
    else:
        # If not empty (= same query exists), drop/remove old dupe row(s), so that time will be new.
        df_hist.columns = ["datetime", "query"]
        df_hist_new = df_hist[df_hist['query'].str.lower().isin([sql.lower()]) == False]
        df = df_hist_new.append(df_new, ignore_index=True, sort=False)
    # Currently not appending but overwriting whole file.
    df2csv(df.tail(limit), query_history_csv, mode="w", header=False)


def _autocomp_matcher(text):
    """
    This function is supposed to be a custom matcher for IPython Completer
    TODO: doesn't work (can't register/append in matchers from 'ju' name space)
    :param text:
    :return:
    """
    global _LAST_CONN
    conn = _LAST_CONN
    # Currently only searching table object
    sql_and = " and tbl_name like '" + str(text) + "%'"
    # TODO: does not work with PostgreSQL
    rs = execute("select distinct name from sqlite_master where type = 'table'%s" % (sql_and))
    if bool(rs) is False:
        return
    return _get_col_vals(rs.fetchall(), 0)


def _autocomp_inject(tablename=None):
    """
    Some hack to use autocomplete in the SQL
    NOTE: Only works with python 3.7 and older ipython
    :param tablename: Optional
    :return: Void
    """
    if bool(tablename):
        tables = [tablename]
    else:
        tables = describe().name.to_list()

    for t in tables:
        cols = describe(t).name.to_list()
        tbl_cls = _gen_class(t, cols)
        try:
            get_ipython().user_global_ns[t] = tbl_cls
            # globals()[t] = tbl_cls
            # locals()[t] = tbl_cls
            # _info("added %s with %s" % (t, str(globals()[t])))
        except:
            _debug("get_ipython().user_global_ns failed")
            pass


def _gen_class(name, attrs=None, def_value=True):
    if type(attrs) == dict:
        c = type(name, (), attrs)
    else:
        c = type(name, (), {})
        if type(attrs) == list:
            for a in attrs:
                setattr(c, a, def_value)
    return c


def _system(command, direct=False, direct_executable=_SH_EXECUTABLE):
    if direct is False and _is_jupyter:
        get_ipython().system(command)
    else:
        import subprocess
        if os.access(direct_executable, os.X_OK) is False:
            direct_executable = None
        # TODO: don't need to escape?
        p = subprocess.Popen(command, shell=True, executable=direct_executable,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, err = p.communicate()
        # Above returns byte objects which are encoded with utf-8. Without decoding, it outputs "b" and "\n".
        if len(err) > 0:
            sys.stderr.write(err.decode() + "\n")
        if len(out) > 0:
            sys.stdout.write(out.decode() + "\n")


def display(df, name="", desc="", tail=1000):
    """
    Wrapper of IPython.display.display for *DataFrame* object
    This function also change the table cel (th, td) alignments.
    :param df: A DataFrame object
    :param name: Caption and also used when saving into file
    :param desc: Optional description (eg: SQL statement)
    :param tail: How many rows from the last to display (not for df2csv)
    :return Void
    >>> pass
    """
    name_html = ""
    if bool(name) is False:
        name = _timestamp(format="%Y%m%d%H%M%S%f")
    else:
        # df.style.set_caption(name)
        name_html += "<h4>" + name + "</h4>"
        if bool(desc):
            name_html += "<pre>" + desc + "</pre>"
    if _is_jupyter():
        if df.empty is False and df.index.empty is False and len(df.index) > tail:
            orig_length = len(df.index)
            df = df.tail(tail)
            name_html += "<pre>Displaying last " + str(tail) + " records (total: " + str(orig_length) + "</pre>"
        try:
            df_styler = df.style.set_properties(**{'text-align': 'left'})
            df_styler = df_styler.set_table_styles([
                dict(selector='th', props=[('text-align', 'left'), ('vertical-align', 'top')]),
                dict(selector='td', props=[('white-space', 'pre-wrap'), ('vertical-align', 'top')])
            ])
            # pd.options.display.html.use_mathjax = False    # Now this is set in global
            _display(name_html + '\n' + df_styler.render())
        except Exception as e:
            _display(name_html + '\n' + df.to_html())
            _err(e)
    else:
        df2csv(df=df, file_path="%s.csv" % (str(name)))


show = s = d = display


def _display(html):
    import IPython
    IPython.display.display(IPython.display.HTML(html))


def pivot(df, output_prefix="pivottable", output_dir="./", rows=None, cols=None, chunk_size=100000):
    """
    Helper function for pivottablejs https://pypi.org/project/pivottablejs/
    https://github.com/nicolaskruchten/pivottable/wiki/Parameters#options-object-for-pivotui
    :param df: A DataFrame object
    :param rows: row list
    :param cols: column list
    :return: void
    >>> pass    # TODO: implement test
    """
    if rows is None:
        rows = []
    if cols is None:
        cols = []
    dfs = _chunks(df, chunk_size)
    for i, _df in enumerate(dfs):
        outfile_path = output_dir.rstrip("/") + "/" + output_prefix + str(i + 1) + ".html"
        _pivot_ui(_df, outfile_path=outfile_path, rows=rows, cols=cols)


def _pivot_ui(df, outfile_path="pivottablejs.html", **kwargs):
    try:
        from pivottablejs import TEMPLATE
        from pivottablejs import pivot_ui
    except ImportError:
        _err("importing pivottablejs failed")
        return
    with io.open(outfile_path, 'wt', encoding='utf8') as outfile:
        csv = df.to_csv(encoding='utf8')
        if hasattr(csv, 'decode'):
            csv = csv.decode('utf8')
        html = TEMPLATE % dict(csv=csv, kwargs=json.dumps(kwargs))
        outfile.write(html)
    # TODO: pivottablejs.IFrame and ju._display() do not work from another function
    _info("%s is created." % outfile_path)


def draw(df, width=16, x_col=0, x_colname=None, name=None, desc="", tail=10, is_x_col_datetime=True):
    """
    Helper function for df.plot()
    As pandas.DataFrame.plot is a bit complicated, using simple options only if this method is used.
    https://pandas.pydata.org/pandas-docs/stable/generated/pandas.DataFrame.plot.html

    :param df: A DataFrame object, which first column will be the 'x' if x_col is not specified
    :param width: This is Inch and default is 16 inch.
    :param x_col: Column index number used for X axis.
    :param x_colname: If column name is given, use this instead of x_col.
    :param name: When saving to file.
    :param desc: TODO: Optional description (eg: SQL statement)
    :param tail: To return some sample rows.
    :param is_x_col_datetime: If True and if x_col column type is not date, cast to date
    :return: DF (use .tail() or .head() to limit the rows)
    #>>> draw(ju.q("SELECT date, statuscode, bytesSent, elapsedTime from t_request_csv")).tail()
    #>>> draw(ju.q("select QueryHour, SumSqSqlWallTime, SumPostPlanTime, SumSqPostPlanTime from query_stats")).tail()
    >>> pass    # TODO: implement test
    """
    height_inch = 8
    if len(df) == 0:
        _debug("No rows to draw.")
        return
    if len(df.columns) > 2:
        height_inch = len(df.columns) * 4
    if bool(x_colname) is False:
        x_colname = df.columns[x_col]
    # check if column is already date
    if is_x_col_datetime and pd.api.types.is_datetime64_any_dtype(df[x_colname]) is False:
        df[x_colname] = pd.to_datetime(df[x_colname])
    df.plot(figsize=(width, height_inch), x=x_colname, subplots=True, sharex=True)  # , title=name
    if bool(name) is False:
        name = _timestamp(format="%Y%m%d%H%M%S%f")
    plt.savefig("%s.png" % (str(name)))
    if _is_jupyter():
        _html = ""
        if bool(name):
            _html += "<h4>" + name + "</h4>"
        if bool(desc):
            _html += "<pre>" + desc + "</pre>"
        if len(_html) > 0:
            _display(_html)
        # Force displaying, otherwise, name (titile) and desc won't show in expected order
        plt.show()
    # TODO: x axis doesn't show any legend
    # if len(df) > (width * 2):
    #    interval = int(len(df) / (width * 2))
    #    labels = df[x_colname].tolist()
    #    lables = labels[::interval]
    #    plt.xticks(list(range(interval)), lables)
    return df.tail(tail)


def gantt(df, index_col="", start_col="min_dt", end_col="max_dt", width=8, name="", tail=10):
    """
    Helper function for plt.hlines()
    based on https://stackoverflow.com/questions/31820578/how-to-plot-stacked-event-duration-gantt-charts-using-python-pandas

    :param df: A DataFrame object, which first column will be the 'x' if x_col is not specified
    :param index_col: index column name. default: df.index
    :param start_col: start column name. default: 'min_dt'
    :param end_col: end column name. default: 'max_dt'
    :param width: This is Inch and default is 16 inch.
    :param name: When saving to file.
    :param tail: To return some sample rows.
    :return: DF (use .tail() or .head() to limit the rows)
    #>>> # Gantt chart for threads (not useful but just an example)
    #>>> df = q("SELECT thread, UDF_STR2SQLDT(MIN(date)) as min_dt, UDF_STR2SQLDT(MAX(date)) as max_dt FROM t_request_logs GROUP BY date_hour, thread")
    #>>> gantt(df, index_col="thread")
    >>> pass    # TODO: implement test
    """
    if bool(name) is False:
        name = _timestamp(format="%Y%m%d%H%M%S%f")
    if len(df) == 0:
        _debug("No rows to draw.")
        return
    df[start_col] = pd.to_datetime(df[start_col])
    df[end_col] = pd.to_datetime(df[end_col])
    fig = plt.figure(figsize=(width, int(len(df) / 3)))
    # TODO: don't know how to change this https://matplotlib.org/3.1.0/api/_as_gen/matplotlib.figure.Figure.html#matplotlib.figure.Figure.add_subplot
    ax = fig.add_subplot(111)
    ax = ax.xaxis_date()
    if bool(index_col) is False:
        y = df.index
    else:
        y = df[index_col]
    try:
        import matplotlib.dates as mdt
    except ImportError:
        _err("importing matplotlib failed")
        return
    ax = plt.hlines(y=y, xmin=mdt.date2num(df[start_col]), xmax=mdt.date2num(df[end_col]))
    if len(name) > 0:
        plt.savefig("%s.png" % (str(name)))
    if _is_jupyter():
        plt.show()
    return df.tail(tail)


def treeFromDf(df, name_ids, member_id, current="", level=0, indent=4, pad=" ", prefix="* ", mini=False):
    """
    Output tree like strings to stdout
    :param df: expecting DataFrame object, TODO: but list / dict should work too
    :param name_ids: column name(s), which is used to display the object name
    :param member_id: column name, which value contains members in python list like *strings*
    :param current: checking *from* particular name_id value
    :param level: To avoid performance issue. 0 is unlimitted.
    :param indent: for displaying
    :param pad: character used for indent
    :param prefix: strings used before line
    :param mini: Do not output first level lines which do not have any members
    :return: void
    #>>> df = ju.q("select recipe_name, repository_name, `attributes.group.memberNames` from t_db_repo")
    #>>> ju.treeFromDf(df, name_ids="repository_name,recipe_name", member_id="attributes.group.memberNames", pad=" ", prefix="|-> ")
    >>> d = [{"recipe_name":"nuget-group", "repository_name":"nuget-group", "attributes.group.memberNames":"['nuget-hosted']"}, {"recipe_name":"nuget-hosted", "repository_name":"nuget-hosted"}]
    >>> df = pd.DataFrame(data=d)
    >>> treeFromDf(df, "repository_name", "attributes.group.memberNames", pad="_", prefix="")
    nuget-group (member:1)
    ____nuget-hosted
    nuget-hosted
    """
    if level > 10:
        _err("Too many levels (max:10)")
        return
    name_ids_list = name_ids.split(",")
    name_id = name_ids_list[0]
    if bool(current):
        df_copy = df.loc[df[name_id] == current]
    else:
        df_copy = df
    for index, row in df_copy.iterrows():
        if name_id not in row:
            continue
        members = []
        opt_info = ""
        if len(name_ids_list) > 1:
            opt_info += " ["
            for i in range(len(name_ids_list)):
                if i == 0:
                    continue
                if name_ids_list[i] in row:
                    opt_info += row[name_ids_list[i]]
            opt_info += "]"
        if member_id in row and len(str(row[member_id])) > 0 and str(row[member_id]) != "nan":
            # members = json.loads(row[member_id])   # does not work with single-quotes
            members = ast.literal_eval(row[member_id])
            if len(members) > 0:
                opt_info += " (member:" + str(len(members)) + ")"
        elif mini and level == 0:
            continue
        print(pad * level * indent + prefix + row[name_id] + opt_info)  # + " (" + row[member_id] + ")"
        for member in members:
            treeFromDf(df=df, name_ids=name_ids, member_id=member_id, current=member, level=level + 1, indent=indent,
                       pad=pad, prefix=prefix, mini=mini)


def qhistory(run=None, like=None, html=True, tail=20):
    """
    Return query histories as DataFrame (so that it will be display nicely in Jupyter)
    :param run: Integer of DataFrame row index which will be run
    :param like: String used in 'like' to search 'query' column
    :param html: Whether output in HTML (default) or returning dataframe object
    :param tail: How many last record it displays (default 20)
    :return: Pandas DataFrame contains a list of queries
    >>> import os; os.environ["JN_UTILS_QUERY_HISTORY"] = "/tmp/text_qhistory.csv"
    >>> _save_query("select 1")
    >>> df = qhistory(html=False)
    >>> len(df[df['query'] == 'select 1'])
    1
    >>> _save_query("SELECT 1")
    >>> df = qhistory(html=False)
    >>> len(df)
    1
    >>> os.remove("/tmp/text_qhistory.csv")
    """
    query_history_csv = os.getenv('JN_UTILS_QUERY_HISTORY', os.getenv('HOME') + os.path.sep + ".ju_qhistory")
    df = csv2df(query_history_csv, header=None)
    if df is False or df.empty:
        return
    df.columns = ["datetime", "query"]
    if type(run) == int:
        sql = df.loc[run, 'query']  # .loc[row_num, column_name]
        _info(sql)
        return query(sql=sql, conn=connect())
    if bool(like):
        df = df[df['query'].str.contains(like)]
    if bool(tail):
        df = df.tail(tail)
    if html is False:
        # TODO: hist(html=False).groupby(['query']).count().sort_values(['count'])
        return df
    current_max_colwitdh = pd.get_option('display.max_colwidth')
    pd.set_option('display.max_colwidth', None)
    display(df)
    pd.set_option('display.max_colwidth', current_max_colwitdh)


history = qhistory


def describe(tablename=None, colname=None, conn=None):
    """
    Describe a table
    :param tablename: Exact table name. If empty, get table list
    :param colname: String used in like for column name
    :param conn: DB connection (cursor) object
    :return: a DF object contains a table information or table list
    >>> describe(conn=connect())
    Empty DataFrame
    Columns: [name, rootpage]
    Index: []
    """
    global _DB_TYPE
    if _DB_TYPE != 'sqlite':
        # If not sqlite, expecting information_schema is available
        extra_where = ""
        if bool(colname):
            extra_where = " AND column_name like '" + colname + "%'"
        if bool(tablename) is False:
            sql = "SELECT distinct table_name, count(*) as col_num FROM information_schema.columns WHERE 1=1 %s GROUP BY table_name" % (
                extra_where)
        else:
            sql = "SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_name = '%s' %s " % (
                tablename, extra_where)
        return query(sql=sql, conn=conn, no_history=True)

    if bool(tablename) is False:
        return show_create_table(tablenames=None, like=colname, conn=conn)
    # NOTE: this query is sqlite specific. names = list(map(lambda x: x[0], cursor.description))
    # NOTE2: below query does not work with SQLite older than 3.16
    # select `name`, `type`, `notnull`, `dflt_value`, `pk` from pragma_table_info('%s') where name is not 'index' %s order by cid
    df = query(sql="PRAGMA table_info('%s')" % (tablename), conn=conn, no_history=True)
    if bool(colname) is False:
        return df
    return df.query("name.str.startswith('%s')" % (colname))


desc = describe


def exists(tablename, conn=None):
    return len(describe(tablename=tablename, conn=conn)) > 0


def show_create_table(tablenames=None, like=None, conn=None):
    """
    SHOW CREATE TABLE or SHOW TABLES
    :param tablenames: If empty, get table list
    :param like: String used in like, such as column name
    :param conn: DB connection (cursor) object
    :return: void with printing CREATE statement, or a DF object contains table list
    >>> show_create_table(conn=connect())
    Empty DataFrame
    Columns: [name, rootpage]
    Index: []
    """
    # TODO: Only for sqlite, does not work with PostgreSQL
    global _DB_TYPE
    if _DB_TYPE != 'sqlite':
        _err("Unsupported DB type: %s" % str(_DB_TYPE))
        return
    if conn is None:
        conn = connect()
    sql_and = ""
    if bool(like):
        sql_and = " and sql like '%" + str(like) + "%'"
    if bool(tablenames):
        if isinstance(tablenames, str): tablenames = [tablenames]
        for t in tablenames:
            # Currently searching any object as long as name matches
            rs = execute("select sql from sqlite_master where name = '%s'%s" % (str(t), sql_and))
            if bool(rs) is False:
                continue
            print(rs.fetchall()[0][0])
            # SQLite doesn't like - in a table name. need to escape with double quotes.
            print("Rows: %s\n" % (execute("SELECT count(oid) FROM \"%s\"" % (t)).fetchall()[0][0]))
        return
    if bool(like):
        # Currently only searching table object
        rs = execute("select distinct name from sqlite_master where type = 'table'%s" % (sql_and))
        if bool(rs) is False:
            return
        tablenames = _get_col_vals(rs.fetchall(), 0)
        return show_create_table(tablenames=tablenames)
    return query(
        sql="select distinct name, rootpage from sqlite_master where type = 'table'%s order by rootpage" % (sql_and),
        conn=conn, no_history=True)


def _get_col_vals(matrix, i):
    """
    Get values from the specified column (not table's column, but matrix's column)
    :param matrix: eg: SQL result set
    :param i: column index number, starting from 0
    :return: list contains column values
    >>> _get_col_vals([[1, 2], [2, 3]], 1)
    [2, 3]
    """
    return [row[i] for row in matrix]


def hive_conn(conn_str="jdbc:hive2://localhost:10000/default", user="admin", pwd="admin"):
    """
    Demonstrating Hive connection capability (eventually will merge into connect())
    NOTE: This requires Java 8 (didn't work with Java 9)
    :param conn_str: jdbc:hive2://localhost:10000/default
    :param user: admin
    :param pwd:  admin
    :return: connection (cursor) object
    #>>> hc = hive_conn("jdbc:hive2://localhost:10000/default")
    #>>> hc.execute("SELECT 1")
    #>>> hc.fetchall()
    #[(1,)]
    >>> pass    # TODO: implement test
    """
    cur_dir = os.path.dirname(os.path.abspath(__file__))
    jar_dir = os.path.abspath(os.path.join(cur_dir, '..')) + "/java/hadoop"
    jars = []
    # currently using 1.x versions
    jars += _globr(ptn="hive-jdbc-client-1.*.jar", src=jar_dir, loop=1)
    if len(jars) == 0:
        jars += _globr(ptn="hive-jdbc-1.*-standalone.jar", src=jar_dir, loop=1)
        jars += _globr(ptn="hadoop-core-1.*.jar", src=jar_dir, loop=1)
    _debug("Loading jars: %s ..." % (str(jars)))
    conn = jaydebeapi.connect("org.apache.hive.jdbc.HiveDriver",
                              conn_str, [user, pwd], jars).cursor()
    return conn


def run_hive_queries(query_series, conn, output=True):
    """
    Execute multiple queries in a Pandas Series against Hive
    :param query_series: Panda Series object which contains query strings
    :param conn:        Hive connection object (if connection string, every time new connections will be created
    :param output:      Boolean if outputs something or not
    :return:            List of failures
    #>>> df = ju.csv2df(file_path='queries_log_received_distinct.csv', conn=ju.connect())
    #>>> #dfs = ju._chunks(df, 2500)   # May want to split if 'df' is very large, then use _mexec()
    #>>> fails = ju.run_hive_queries(df['extra_lines'], ju.hive_conn("jdbc:hive2://hostname:port/"))
    >>> pass
    """
    failures = []
    for (i, query) in query_series.iteritems():
        error = hive_query_execute(query, conn, i, output)
        if error is not None:
            failures += [{'row': i, 'exception': error, 'query': query}]
    return failures


def hive_query_execute(query, conn, row_num=None, output=False):
    """
    Run one query against Hive
    :param query:   SQL SELECT statement
    :param conn: Hive connection string or object
    :param row_num: Integer, used like ID
    :param output:  Boolean, if True, output results and error
    :return: String: Error message
    #>>> error = ju.hive_query_execute("SELECT 1", ju.hive_conn("jdbc:hive2://hostname:port/"))
    >>> pass
    """
    _time = _timestamp()
    _r = None
    _error = None
    if bool(query) and str(query).lower() != "nan":
        # TODO: should pool the connection, and not sure if it's closing in Jupyter
        try:
            if type(conn) == str:
                conn = hive_conn(conn)
            _r = query_execute(query, conn)
        except Exception as e:
            _error = e
    if output:
        print("### %s at %s ################" % (str(row_num), _time))
        if bool(_error):
            print("\n# Exception happened on No.%s" % (str(row_num)))
            print(query)
            print(_error)
        else:
            print(_r)
    else:
        if str(row_num).isdigit() and (row_num % 100 == 0): sys.stderr.write("\n")
        if bool(_error):
            sys.stderr.write("x")
        else:
            sys.stderr.write(".")
    return _error


def run_hive_queries_multi(query_series, conn_str, num_pool=None, output=False):
    """
    Execute multiple queries in a Pandas Series against Hive
    :param query_series: Panda Series object which contains query strings
    :param conn_str:    As each pool creates own connection, need String
    :param num_pool:    Concurrency number
    :param output:      Boolean if outputs something or not
    :return:            List of failures
    #>>> df = ju.csv2df(file_path='queries_log_received_distinct.csv', conn=ju.connect())
    #>>> #dfs = ju._chunks(df, 2500)   # May want to split if 'df' is very large, then use _mexec()
    #>>> fails = ju.run_hive_queries_multi(df['extra_lines'], "jdbc:hive2://hostname:port/")
    """
    failures = []
    args_list = []
    for (i, query) in query_series.iteritems():
        # from concurrent.futures import ProcessPoolExecutor hangs in Jupyter, so can't use kwargs
        args_list.append((query, conn_str, i, output))
    return _mexec(hive_query_execute, args_list, num=num_pool)


def _massage_tuple_for_save(tpl, long_value="", num_cols=None):
    """
    Transform the given tuple to a DataFrame (or Table columns)
    :param tpl: Tuple which contains values of one row
    :param long_value: multi-lines log messages, like SQL, java stacktrace etc.
    :param num_cols: Number of columns in the table to populate missing column as None/NULL
    :return: modified tuple
    >>> _massage_tuple_for_save(('a','b'), "aaaa", 4)
    ('a', 'b', None, 'aaaa')
    """
    if bool(num_cols) and len(tpl) < num_cols:
        # - 1 for message
        for i in range(((num_cols - 1) - len(tpl))):
            tpl += (None,)
    tpl += (long_value,)
    return tpl


def _insert2table(conn, tablename, tpls, chunk_size=4000):
    """
    Insert one tuple or tuples to a table
    :param conn: Connection object created by connect()
    :param tablename: Table name
    :param tpls: a Tuple or a list of Tuples, which each Tuple contains values for a row
    :return: execute() method result
    #>>> _insert2table(connect(), "test", [('a', 'b', None, 'aaaa')])
    >>> pass    # TODO: implement test
    """
    if isinstance(tpls, list):
        first_obj = tpls[0]
    else:
        first_obj = tpls
        tpls = [tpls]
    chunked_list = _chunks(tpls, chunk_size)
    placeholders = ','.join('?' * len(first_obj))
    for l in chunked_list:
        res = conn.executemany("INSERT INTO " + tablename + " VALUES (" + placeholders + ")", l)
        if bool(res) is False:
            return res
    return res


def _find_matching(line, prev_matches, prev_message, begin_re, line_re, size_re=None, time_re=None, num_cols=None):
    """
    Search one line with given regex (compiled)
    :param line: String of a log line
    :param prev_matches: A tuple which contains previously matched groups
    :param prev_message: String contain log's long text which often multi-lines (eg: SQL, java stacktrace)
    :param begin_re: Compiled regex to find the beginning of the log line
    :param line_re: Compiled regex for group match to get the (column) values
    :param size_re: An optional compiled regex to find size related value
    :param time_re: An optional compiled regex to find time related value
    :param num_cols: Number of columns used in _massage_tuple_for_save() to populate empty columns with Null
    :return: (tuple, prev_matches, prev_message)
    >>> import re;line = "2018-09-04 12:23:45 test";begin_re=re.compile("^\d\d\d\d-\d\d-\d\d");line_re=re.compile("(^\d\d\d\d-\d\d-\d\d).+(test)")
    >>> _find_matching(line, None, None, begin_re, line_re)
    (None, ('2018-09-04',), 'test')
    """
    tmp_tuple = None
    _debug(" - line: %s" % (str(line)))
    # If current line is beginning of a new *log* line (eg: ^2018-08-\d\d...)
    if begin_re.search(line):
        _debug("   matched.")
        # and if previous matches aren't empty, prev_matches is going to be saved
        if bool(prev_matches):
            tmp_tuple = _massage_tuple_for_save(tpl=prev_matches, long_value=prev_message, num_cols=num_cols)
            if bool(tmp_tuple) is False:
                # If some error happened, returning without modifying prev_xxxx
                return (tmp_tuple, prev_matches, prev_message)
            prev_message = None
            prev_matches = None

        _matches = line_re.search(line)
        if _matches:
            # _debug("_matches: %s" % (str(_matches.groups())))
            _tmp_groups = _matches.groups()
            prev_message = _tmp_groups[-1]
            prev_matches = _tmp_groups[:(len(_tmp_groups) - 1)]

            if bool(size_re):
                _size_matches = size_re.search(prev_message)
                if _size_matches:
                    prev_matches += (_size_matches.group(1),)
                else:
                    prev_matches += (None,)
            if bool(time_re):
                _time_matches = time_re.search(prev_message)
                if _time_matches:
                    # _debug(_time_matches.groups())
                    prev_matches += (_ms(_time_matches, time_re),)
                else:
                    prev_matches += (None,)
    else:
        if prev_message is None:
            prev_message = str(line)  # Looks like each line already has '\n'
        else:
            prev_message = str(prev_message) + str(line)  # Looks like each line already has '\n'
    return (tmp_tuple, prev_matches, prev_message)


def _ms(time_matches, time_re_compiled):
    """
    Convert regex match which used _TIME_REGEX to Milliseconds
    :param _time_matches:
    :param time_regex:
    :return: integer
    >>> import re
    >>> time_re = re.compile(_TIME_REGEX)
    >>> prev_message = 'withBundle request for subgroup [subgroup:some_uuid] took [1.03 s] to begin execution'
    >>> _time_matches = time_re.search(prev_message)
    >>> _ms(_time_matches, time_re)
    1030.0
    """
    global _TIME_REGEX
    if time_re_compiled.pattern != _TIME_REGEX:
        # If not using default regex, return as string
        return str(time_matches.group(1))
    # Currently not considering micro seconds
    if time_matches.group(2) == "ms":
        return float(time_matches.group(1))
    if time_matches.group(2) == "s":
        return float(time_matches.group(1)) * 1000
    if time_matches.group(2) == "ks":
        return float(time_matches.group(1)) * 1000 * 1000


def _linecount_wc(filepath):
    if bool(filepath) is False or os.path.isfile(filepath) is False:
        return False
    if filepath.endswith(".gz"):
        return int(os.popen('gunzip -c %s | wc -l' % (filepath)).read().strip())
    return int(os.popen('wc -l %s' % (filepath)).read().split()[0])


def _linenumber(filepath, search_regex, with_rg=False):
    if bool(filepath) is False or os.path.isfile(filepath) is False:
        return False
    if bool(search_regex) is False:
        return 0
    if with_rg:
        return int(os.popen('rg -n -m1 "%s" "%s" | cut -d":" -f1' % (search_regex, filepath)).read().strip())
    # NOTE: grep was not faster than python
    # if with_grep:
    #    return int(os.popen('grep -n -m1 "%s" "%s" | cut -d":" -f1' % (search_regex, filepath)).read().strip())
    ex = re.compile(search_regex)
    cnt = 1
    for line in _open_file(filepath):
        if ex.search(line):
            return cnt
        cnt += 1
    return 0


def _read_file_and_search(file_path, line_beginning, line_matching, size_regex=None, time_regex=None, num_cols=None,
                          replace_comma=False, line_from=0, line_until=0):
    """
    Read a file and search each line with given regex
    :param file_path: A file path
    :param line_beginning: Regex to find the beginning of the line (normally like ^2018-08-21)
    :param line_matching: Regex to capture column values
    :param size_regex: Regex to capture size
    :param time_regex: Regex to capture time/duration
    :param num_cols: Number of columns
    :param replace_comma: Sqlite does not like comma in datetime with milliseconds
    :param line_from: Read line from
    :param line_until: Read line until
    :return: A list of tuples
    >>> pass    # TODO: implement test
    """
    _debug("line_beginning: " + line_beginning)
    begin_re = re.compile(line_beginning)
    line_re = re.compile(line_matching)
    size_re = re.compile(size_regex) if bool(size_regex) else None
    time_re = re.compile(time_regex) if bool(time_regex) else None
    prev_matches = None
    prev_message = None
    tuples = []
    time_with_ms = re.compile('\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d,\d+')

    ttl_line = _linecount_wc(file_path)
    tmp_counter = int(float(ttl_line) / 10)
    connter = 10000 if tmp_counter < 10000 else tmp_counter
    filename = os.path.basename(file_path)
    f = _open_file(file_path)
    # Read lines
    _ln = 0
    _empty = 0
    for l in f:
        _ln += 1
        if bool(line_from) and _ln < line_from:
            _empty += 1
            _debug("  _ln=%s, line_from=%s" % (str(_ln), str(line_from)))
            continue
        if bool(line_until) and _ln > line_until:
            _empty += 1
            _debug("  _ln=%s, line_until=%s" % (str(_ln), str(line_until)))
            continue
        if (_ln % connter) == 0:
            _info("  Processed %s/%s (skip:%s) lines for %s (%s) ..." % (
                str(_ln), ttl_line, str(_empty), filename, _timestamp(format="%H:%M:%S")))
        if bool(l) is False:
            break  # most likely the end of the file?
        (tmp_tuple, prev_matches, prev_message) = _find_matching(line=l, prev_matches=prev_matches,
                                                                 prev_message=prev_message, begin_re=begin_re,
                                                                 line_re=line_re, size_re=size_re, time_re=time_re,
                                                                 num_cols=num_cols)
        # TODO: am i casting all values to string?
        if bool(tmp_tuple):
            if replace_comma and time_with_ms.search(tmp_tuple[0]):
                tmp_l = list(tmp_tuple)
                tmp_l[0] = tmp_tuple[0].replace(",", ".")
                tmp_tuple = tuple(tmp_l)
            tuples += [tmp_tuple]
        else:
            _debug("  _ln=%s, l=%s" % (str(_ln), str(l)[0:100]))
    f.close()

    # append last message (last line)
    if bool(prev_matches):
        tuples += [_massage_tuple_for_save(tpl=prev_matches, long_value=prev_message, num_cols=num_cols)]
    return tuples


def logs2table(filename, tablename=None, conn=None,
               col_names=['date_time', 'loglevel', 'thread', 'node', 'user', 'class', 'message'],
               num_cols=None, line_beginning="^\d\d\d\d-\d\d-\d\d",
               line_matching="^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[^ ]*) +([^ ]+) +\[([^]]+)\] ([^ ]*) ([^ ]*) ([^ ]+) - (.*)",
               size_regex=None, time_regex=None,
               line_from=0, line_until=0,
               max_file_num=10, max_file_size=(1024 * 1024 * 100),
               appending=False, multiprocessing=False):
    """
    Insert multiple log files into *one* table
    :param filename: a file name (or path) or *simple* glob regex
    :param tablename: Table name. If empty, generated from filename
    :param conn:  Connection object (ju.connect())
    :param col_names: Column definition list or dict (column_name1 data_type, column_name2 data_type, ...)
    :param num_cols: Number of columns in the table. Optional if col_def_str is given.
    :param line_beginning: To detect the beginning of the log entry (normally ^\d\d\d\d-\d\d-\d\d)
    :param line_matching: A group matching regex to separate one log lines into columns
    :param size_regex: (optional) size-like regex to populate 'size' column
    :param time_regex: (optional) time/duration like regex to populate 'time' column
    :param line_from: Read line from
    :param line_until: Read line until
    :param max_file_num: To avoid memory issue, setting max files to import
    :param max_file_size: To avoid memory issue, setting max file size per file
    :param appending: default is False. If False, use 'DROP TABLE IF EXISTS'
    :param multiprocessing: (Experimental) default is False. If True, use multiple CPUs
    :return: True if no error, or a tuple contains multiple information for debug
    #>>> (col_names, line_matching) = al._gen_regex_for_request_logs('request.log')
         ju.logs2table('request.log', tablename="t_request", line_beginning="^.", col_names=col_names, line_matching=line_matching)
    #>>> logs2table(filename='nexus.log*', tablename='t_nexus_log',
         col_names=['date_time', 'loglevel', 'thread', 'node', 'user', 'class', 'message'],
            line_matching='^(\\d\\d\\d\\d-\\d\\d-\\d\\d.\\d\\d:\\d\\d:\\d\\d[^ ]*) +([^ ]+) +\\[([^]]+)\\] ([^ ]*) ([^ ]*) ([^ ]+) - (.*)',
            size_regex=None, time_regex=None)
    #>>> logs2table('clm-server_*.log*', tablename="t_clm_server_log", multiprocessing=True, max_file_num=20
            col_names=['date_time', 'loglevel', 'thread', 'user', 'class', 'message'],
            line_matching='^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[^ ]*) +([^ ]+) +\[([^]]+)\] ([^ ]*) ([^ ]+) - (.*)',
            size_regex=None, time_regex=None)
    >>> pass    # TODO: implement test
    """
    global _SIZE_REGEX
    global _TIME_REGEX
    if conn is None:
        conn = connect()
    # NOTE: as python dict does not guarantee the order, col_def_str is using string
    if bool(num_cols) is False:
        num_cols = len(col_names)
    if os.path.exists(filename):
        files = [filename]
    else:
        files = _globr(filename)
    if bool(files) is False:
        _debug("No %s. Skipping ..." % (str(filename)))
        return None

    if len(files) > max_file_num:
        raise ValueError('Glob: %s returned too many files (%s)' % (filename, str(len(files))))
    col_def_str = ""
    if isinstance(col_names, dict):
        for k, v in col_names.iteritems():
            if col_def_str != "":
                col_def_str += ", "
            col_def_str += "%s %s" % (k, v)
    else:
        for v in col_names:
            if col_def_str != "":
                col_def_str += ", "
            # the column name 'jsonstr' is currently not in use.
            if v == 'jsonstr':
                col_def_str += "%s json" % (v)
            elif v == 'size' and size_regex == _SIZE_REGEX:
                col_def_str += "%s INTEGER" % (v)
            elif v == 'time' and time_regex == _TIME_REGEX:
                col_def_str += "%s REAL" % (v)
            else:
                col_def_str += "%s TEXT" % (v)

    if bool(tablename) is False:
        first_filename = os.path.basename(files[0])
        tablename = _pick_new_key(first_filename, {}, using_1st_char=False, prefix='t_')

    # If not None, create a table
    if bool(col_def_str):
        if appending is False:
            res = execute("DROP TABLE IF EXISTS %s" % (tablename))
            if bool(res) is False:
                return res
            _info("DROP-ed TABLE IF EXISTS: %s" % (tablename))
        res = execute("CREATE TABLE IF NOT EXISTS %s (%s)" % (tablename, col_def_str))
        if bool(res) is False:
            return res

    _has_table_created = False
    if multiprocessing:
        args_list = []
        for f in files:
            if os.stat(f).st_size >= max_file_size:
                _info("WARN: File %s (%d MB) is too large (max_file_size=%d), so not appending into the args_list." % (
                    str(f), int(os.stat(f).st_size / 1024 / 1024), max_file_size))
                continue
            # concurrent.futures.ProcessPoolExecutor hangs in Jupyter, so can't use kwargs
            args_list.append(
                (f, line_beginning, line_matching, size_regex, time_regex, num_cols, True, line_from, line_until))
        # file_path, line_beginning, line_matching, size_regex=None, time_regex=None, num_cols=None, replace_comma=False
        rs = _mexec(_read_file_and_search, args_list)
        for tuples in rs:
            if bool(tuples) is False or len(tuples) == 0:
                _info("WARN: _mexec returned empty tuple ...")
                continue
            res = _insert2table(conn=conn, tablename=tablename, tpls=tuples)
            if bool(res) is False:  # if fails once, stop
                _err("_insert2table failed to insert %d ..." % (len(tuples)))
                return res
            _has_table_created = True
    else:
        for f in files:
            if os.stat(f).st_size >= max_file_size:
                _info("WARN: File %s (%d MB) is too large (max_file_size=%d)" % (
                    str(f), int(os.stat(f).st_size / 1024 / 1024), max_file_size))
                continue
            tuples = _read_file_and_search(file_path=f, line_beginning=line_beginning, line_matching=line_matching,
                                           size_regex=size_regex, time_regex=time_regex, num_cols=num_cols,
                                           replace_comma=True, line_from=line_from, line_until=line_until)
            if bool(tuples):
                _debug(("tuples len:%d" % len(tuples)))
            if len(tuples) > 0:
                res = _insert2table(conn=conn, tablename=tablename, tpls=tuples)
                if bool(res) is False:  # if fails once, stop
                    return res
                _has_table_created = True
    if _has_table_created:
        _info("Created table: %s" % (tablename))
        _autocomp_inject(tablename=tablename)
    return _has_table_created


def logs2dfs(filename, col_names=['datetime', 'loglevel', 'thread', 'ids', 'size', 'time', 'message'],
             num_fields=None, line_beginning="^\d\d\d\d-\d\d-\d\d",
             line_matching="^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[0-9.,]*) (.+?) \[(.+?)\] (\{.*?\}) (.+)",
             size_regex=_SIZE_REGEX, time_regex=_TIME_REGEX,
             max_file_num=10, multiprocessing=False):
    """
    Convert multiple files to *multiple* DataFrame objects
    :param filename: A file name or *simple* regex used in glob to select files.
    :param col_names: Column definition list or dict (column_name1 data_type, column_name2 data_type, ...)
    :param num_fields: Number of columns in the table. Optional if col_def_str is given.
    :param line_beginning: To detect the beginning of the log entry (normally ^\d\d\d\d-\d\d-\d\d)
    :param line_matching: A group matching regex to separate one log lines into columns
    :param size_regex: (optional) size-like regex to populate 'size' column
    :param time_regex: (optional) time/duration like regex to populate 'time' column
    :param max_file_num: To avoid memory issue, setting max files to import
    :param multiprocessing: (Experimental) If True, use multiple CPUs
    :return: A concatenated DF object
    #>>> df = logs2dfs(filename="debug.2018-08-28.11.log.gz")
    #>>> df2 = df[df.loglevel=='DEBUG'].head(10)
    #>>> bool(df2)
    #True
    >>> pass    # TODO: implement test
    """
    # NOTE: as python dict does not guarantee the order, col_def_str is using string
    if bool(num_fields) is False:
        num_fields = len(col_names)
    files = _globr(filename)

    if bool(files) is False:
        return False

    if len(files) > max_file_num:
        raise ValueError('Glob: %s returned too many files (%s)' % (filename, str(len(files))))

    dfs = []
    if multiprocessing:
        args_list = []
        for f in files:
            args_list.append((f, line_beginning, line_matching, size_regex, time_regex, num_fields, True))
        # from concurrent.futures import ProcessPoolExecutor hangs in Jupyter, so can't use kwargs
        rs = _mexec(_read_file_and_search, args_list)
        for tuples in rs:
            if len(tuples) > 0:
                dfs += [pd.DataFrame.from_records(tuples, columns=col_names)]
    else:
        for f in files:
            _info("Processing %s (%d KB) ..." % (str(f), os.stat(f).st_size / 1024))
            tuples = _read_file_and_search(file_path=f, line_beginning=line_beginning, line_matching=line_matching,
                                           size_regex=size_regex, time_regex=time_regex, num_cols=num_fields,
                                           replace_comma=True)
            if len(tuples) > 0:
                dfs += [pd.DataFrame.from_records(tuples, columns=col_names)]
    _info("Completed.")
    if bool(dfs) is False:
        return None
    return pd.concat(dfs, sort=False)


def load_csvs(src="./", conn=None, include_ptn='*.csv', exclude_ptn='', chunksize=1000, if_exists='replace',
              useRegex=False, max_file_size=0):
    """
    Convert multiple CSV files to DF *or* DB tables
    Example: _=ju.load_csvs("./", ju.connect(), "tables_*.csv")
    :param src: Source directory path
    :param conn: DB connection object. If None, use Pandas DF otherwise, DB tables
    :param include_ptn: Include pattern
    :param exclude_ptn: Exclude pattern
    :param chunksize: to_sql() chunk size
    :param if_exists: {‘fail’, ‘replace’, ‘append’}
    :param useRegex: whether use regex or not to find json files
    :return: A tuple contain key=>file relationship and Pandas dataframes objects
    #>>> (names_dict, dfs) = load_csvs(src="./stats")
    #>>> bool(names_dict)
    #True
    >>> pass    # TODO: implement test
    """
    names_dict = {}
    dfs = {}
    ex = re.compile(exclude_ptn)
    files = _globr(ptn=include_ptn, src=src, useRegex=useRegex, max_size=max_file_size)
    for f in files:
        if bool(exclude_ptn) and ex.search(os.path.basename(f)):
            continue
        _debug("Processing %s" % (f))
        if os.stat(f).st_size == 0:
            continue
        f_name, f_ext = os.path.splitext(os.path.basename(f))
        tablename = _pick_new_key(f_name, names_dict, prefix='t_')
        names_dict[tablename] = f
        dfs[tablename] = csv2df(filename=f, conn=conn, tablename=tablename, chunksize=chunksize, if_exists=if_exists)
    if bool(conn):
        del (names_dict)
        del (dfs)
        return None
    return (names_dict, dfs)


def csv2df(filename, conn=None, tablename=None, chunksize=1000, header=0, if_exists='replace'):
    '''
    Load a CSV file into a DataFrame *or* database table if conn is given
    If conn is given, import into a DB table
    :param filename: file path or file name or glob string
    :param conn: DB connection object. If not empty, import into a sqlite table
    :param tablename: If empty, table name will be the filename without extension
    :param chunksize: Rows will be written in batches of this size at a time
    :param header: interger or list
                   Row number(s) to use as the column names
                   Or a list of column names
    :param if_exists: {‘fail’, ‘replace’, ‘append’}
    :return: Pandas DF object or False if file is not readable
    #>>> df = ju.csv2df(file_path='./slow_queries.csv', conn=ju.connect())
    >>> pass    # Testing in df2csv()
    '''
    if bool(tablename) and conn is None:
        conn = connect()
    if os.path.exists(filename):
        file_path = filename
    else:
        files = _globr(filename)
        if bool(files) is False:
            _debug("No %s. Skipping ..." % (str(filename)))
            return None
        file_path = files[0]
    # special logic for 'csv': if no header, most likely 'append' is better
    if if_exists is None:
        if header is None:
            if_exists = 'append'
        else:
            if_exists = 'fail'
    names = None
    if type(header) == list:
        names = header
        header = None
    try:
        # read_csv file fails if file is empty
        df = pd.read_csv(file_path, escapechar='\\', header=header, names=names, index_col=False)
    except pd.errors.EmptyDataError:
        _info("File %s is empty" % (str(filename)))
        return False
    if bool(conn):
        if bool(tablename) is False:
            tablename = _pick_new_key(os.path.basename(file_path), {}, using_1st_char=False, prefix='t_')
        if df2table(df=df, tablename=tablename, conn=conn, chunksize=chunksize, if_exists=if_exists) is True:
            _info("Created table: %s" % (tablename))
            _autocomp_inject(tablename=tablename)
        return len(df) > 0
    return df


def obj2csv(obj, file_path, mode="w", header=True):
    '''
    Save a python object to a CSV file
    :param obj: Pandas Data Frame object or list or dict
    :param file_path: File Path
    :param mode: mode used with open(). Default 'w'
    :return: unknown (what to_csv returns)
    >>> pass
    '''
    # [{"col1":1, "col2":2}, {"col1":3, "col2":4}]
    if type(obj) == type([]):
        df = pd.DataFrame(obj)
    elif type(obj) == type({}):
        df = pd.DataFrame.from_dict(obj)
    elif type(obj) == pd.core.frame.DataFrame:
        df = obj
    else:
        _err("Unsupported type: %s" % str(type(obj)))
        return
    return df2csv(df, file_path, mode=mode, header=header)


def df2table(df, tablename, conn=None, chunksize=1000, if_exists='replace', schema=None):
    """
    Convert df to a DB table
    :param df: A dataframe object
    :param tablename: table name
    :param conn: database connection object
    :param chunksize: to split the data
    :param if_exists: 'fail', 'replace', or 'append'
    :param schema: Database schema
    :return: True, or False or error column number if error.
    """
    if conn is None:
        conn = connect()
    try:
        if bool(schema) is False:
            global _DB_SCHEMA
            schema = _DB_SCHEMA
        df.to_sql(name=tablename, con=conn, chunksize=chunksize, if_exists=if_exists, schema=schema, index=False)
    except InterfaceError as e:
        res = re.search('Error binding parameter ([0-9]+) - probably unsupported type', str(e))
        _err(e)
        if res:
            _cnum = int(res.group(1))
            _err(df.columns[_cnum])
        return False
    return True


def df2csv(df, file_path, mode="w", header=True):
    '''
    Save DataFrame to a CSV file
    :param df: Pandas Data Frame object
    :param file_path: File Path
    :param mode: mode used with open(). Default 'w'
    :return: unknown (what to_csv returns)
    >>> import pandas as pd
    >>> df = pd.DataFrame([{"key":"a", "val":"value"}])
    >>> df2csv(df, '/tmp/test_df2csv.csv', 'w')
    >>> df2 = csv2df('/tmp/test_df2csv.csv')
    >>> df == df2
        key   val
    0  True  True
    '''
    import csv
    return df.to_csv(file_path, mode=mode, header=header, index=False, escapechar='\\', quoting=csv.QUOTE_NONNUMERIC)


def df2files(df, filepath_prefix, extension="", columns=None, overwriting=False, sep="="):
    """
    Write each line/row of a DataFrame into individual file
    :param df: Panda DataFrame
    :param filepath_prefix: filename will be this one + index + extension (if not empty)
    :param extension: file extension (eg: ".txt" or just "txt")
    :param columns: list of column names or string
    :param overwriting: if True, the destination file will be overwritten
    :param sep: Separator character which is used when multiple columns exist in the Series
    :return: None/Void
    #>>> df2files(queries_df, "test_", ".sql", ['extra_lines']) # generate a="xxxxx"
    #>>> df2files(queries_df, "test_", ".sql", "extra_lines")   # generate xxxxx
    >>> pass
    """
    if len(df) < 1:
        return False
    if type(columns) == type([]) and len(columns) > 0:
        _df = df[columns]
    else:
        _df = df
    for i, row in _df.iterrows():
        if len(extension) > 0:
            full_filepath = filepath_prefix + str(i) + "." + extension.lstrip(".")
        else:
            full_filepath = filepath_prefix + str(i)
        if overwriting is False and os.path.exists(full_filepath):
            _info("%s exists. Skipping ..." % (full_filepath))
            continue
        _info("Writing index=%s into %s ..." % (str(i), full_filepath))
        with open(full_filepath, 'w') as f2:
            if type(columns) == type('a'):
                f2.write(row[columns])
            else:
                f2.write(row.to_csv(sep=sep))


def update_check(file=None, baseurl="https://raw.githubusercontent.com/hajimeo/samples/master/python"):
    """
    (almost) Alias of update()
    Check if update is avaliable (actually checking file size only at this moment)
    :param file: File path string. If empty, checks for this file (jn_utils.py)
    :param baseurl: Default is https://raw.githubusercontent.com/hajimeo/samples/master/python
    :return: If update available, True and output message in stderr
    >>> pass
    """
    return update(file, baseurl, check_only=True)


def update(file=None, baseurl="https://raw.githubusercontent.com/hajimeo/samples/master/python", check_only=False,
           force_update=False):
    """
    Update the specified file from internet
    :param file: File path string. If empty, updates for this file (jn_utils.py)
    :param baseurl: Default is https://raw.githubusercontent.com/hajimeo/samples/master/python
    :param check_only: If True, do not update but check only
    :param force_update: Even if same size, replace the file
    :return: None if successfully replaced or don't need to update
    >>> b = update(check_only=True)
    >>> b is not False
    True
    """
    if bool(file) is False:
        file = __file__
    # i'm assuming i do not need to concern of .pyc...
    filename = os.path.basename(file)
    url = baseurl.rstrip('/') + "/" + filename
    remote_size = int(urlopen(url).headers["Content-Length"])
    local_size = int(_get_filesize(file))
    if remote_size < (local_size / 2):
        _err("Couldn't check the size of %s" % (url))
        return False
    if force_update is False and int(remote_size) == int(local_size):
        # If exactly same size, not updating
        _info("No need to update %s" % (filename))
        return
    if int(remote_size) != int(local_size):
        _info("%s size is different between remote (%s KB) and local (%s KB)." % (
            filename, int(remote_size / 1024), int(local_size / 1024)))
        if check_only:
            _info("To update, use 'ju.update()'\n")
            return True
    new_file = "/tmp/" + filename + "_" + _timestamp(format="%Y%m%d%H%M%S")
    try:
        os.rename(file, new_file)
    except:
        if force_update is False:
            _info("Taking backup to /tmp/ failed. Retry with force_update=True.")
            return False
    remote_content = urlopen(url).read()
    with open(file, 'wb') as f:
        f.write(remote_content)
    _info("%s was updated (reload/restart required) with backup: %s" % (filename, new_file))
    return


def help(func_name=None):
    """
    Output help information
    :param func_name: (optional) A function name written in this script
    :return: void
    >>> pass
    """
    import jn_utils as ju
    if bool(func_name):
        m = getattr(ju, func_name, None)
        if callable(m) and hasattr(m, '__doc__') and len(str(m.__doc__)) > 0:
            print(func_name + ":")
            print(m.__doc__)
        return
    print(ju.__doc__)
    print("Available functions:")
    for attr_str in dir(ju):
        if attr_str.startswith("_"): continue
        # TODO: no idea why those functions matches if condition.
        if attr_str in ['create_engine', 'datetime', 'help']: continue
        m = getattr(ju, attr_str, None)
        if callable(m) and hasattr(m, '__doc__') and bool(m.__doc__):
            print("    " + attr_str)
    print("For a function help, use 'ju.help(\"function_name\")'.")


if __name__ == '__main__':
    import doctest

    print("Running tests ...")
    doctest.testmod(verbose=True)
