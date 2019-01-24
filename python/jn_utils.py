#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Python Jupyter Notebook helper/utility functions
# @author: hajime
#
# curl https://raw.githubusercontent.com/hajimeo/samples/master/python/jn_utils.py -o $HOME/IdeaProjects/samples/python/jn_utils.py
#
"""
jn_utils is Jupyter Notebook Utility script, which contains functions to convert text files to Pandas DataFrame or DB (SQLite) tables.
To update this script, execute "ju.update()".
"""

import sys, os, fnmatch, gzip, re
from time import time
from datetime import datetime
import pandas as pd
from sqlalchemy import create_engine
import sqlite3

_LAST_CONN = None
_DB_SCHEMA = 'db'


def _mexec(func_obj, kwargs_list, num=None, using_process=False):
    """
    Execute multiple functions asynchronously
    :param func_obj: A function object to be executed
    :param kwargs_list: A list contains dicts of arguments
    :param num: number of pool. if None, half of CPUs (NOTE: if threads, it does not matter)
    :return: list contains results. Currently result order is random (not same as args_list)
    >>> def multi(x, y): return x * y
    ...
    >>> _mexec(multi, None)
    >>> _mexec(multi, [{'x':1, 'y':2}])[0]
    2
    >>> rs = _mexec(multi, [{'x':1, 'y':2}, {'x':2, 'y':3}])
    >>> rs[0] + rs[1]
    8
    """
    rs = []
    if bool(kwargs_list) is False or bool(func_obj) is False: return None
    if len(kwargs_list) == 1:
        rs.append(func_obj(**kwargs_list[0]))
        return rs
    from concurrent.futures import as_completed
    if using_process:
        from concurrent.futures import ProcessPoolExecutor as pe
    else:
        from concurrent.futures import ThreadPoolExecutor as pe
    if bool(num) is False:
        import multiprocessing
        num = int(multiprocessing.cpu_count() / 2)
    executor = pe(max_workers=num)
    futures = [executor.submit(func_obj, **kwargs) for kwargs in kwargs_list]
    for future in as_completed(futures):
        rs.append(future.result())
    return rs


def _dict2global(d, scope, overwrite=False):
    """
    Iterate the given dict and create global variables (key = value)
    NOTE: somehow this function can't be called from inside of a function in Jupyter
    :param d: a dict object
    :param scope: should pass 'globals()' or 'locals()'
    :param overwrite: If True, instead of throwing error, just overwrites with the new value
    :return: void
    >>> _dict2global({'a':'test', 'b':'test2'}, globals(), True)
    >>> b == 'test2'
    True
    """
    for k, v in d.items():
        if k in scope and overwrite is False:
            raise ValueError('%s is already used' % (k))
            # continue
        scope[k] = v


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


def _globr(ptn='*', src='./'):
    """
    As Python 2.7's glob does not have recursive option
    :param ptn: glob regex pattern
    :param src: source/importing directory path
    :return: list contains matched file paths
    >>> l = _globr();len(l) > 0
    True
    """
    matches = []
    for root, dirnames, filenames in os.walk(src):
        # os walk doesn't sort and almost random
        for filename in fnmatch.filter(sorted(filenames), ptn):
            matches.append(os.path.join(root, filename))
    return matches


def _read(file):
    """
    Read one text or gz file
    :param file:
    :return: file handler
    >>> f = _read(__file__);f.name == __file__
    True
    """
    if not os.path.isfile(file):
        return None
    if file.endswith(".gz"):
        return gzip.open(file, "rt")
    else:
        return open(file, "r")


def _timestamp(unixtimestamp=None, format="%Y%m%d%H%M%S"):
    """
    Format Unix Timestamp with a given format
    :param unixtimestamp: Int (or float, but number after dot will be ignored)
    :param format: Default is %Y%m%d%H%M%S
    :return: Formatted string
    >>> dt_str = _timestamp(1543189639)
    >>> dt_str.startswith('2018112')
    True
    """
    if bool(unixtimestamp) is False:
        unixtimestamp = time()
    # TODO: wanted to use timezone.utc but python 2.7 doesn't work
    return datetime.fromtimestamp(float(unixtimestamp)).strftime(format)


def _err(message):
    sys.stderr.write("%s\n" % (str(message)))


def load_jsons(src="./", db_conn=None, include_ptn='*.json', exclude_ptn='physicalPlans|partitions', chunksize=1000,
               json_cols=['connectionId', 'planJson', 'json']):
    """
    Find json files from current path and load as pandas dataframes object
    :param src: source/importing directory path
    :param db_conn: If connection object is given, convert JSON to table
    :param include_ptn: Regex string to include some file
    :param exclude_ptn: Regex string to exclude some file
    :param chunksize: Rows will be written in batches of this size at a time. By default, all rows will be written at once
    :param json_cols: to_sql() fails if column is json, so forcing those columns to string
    :return: A tuple contain key=>file relationship and Pandas dataframes objects
    #>>> (names_dict, dfs) = load_jsons(src="./engine/aggregates")
    #>>> bool(names_dict)
    #True
    >>> pass    # TODO: implement test
    """
    names_dict = {}
    dfs = {}
    ex = re.compile(exclude_ptn)

    files = _globr(include_ptn, src)
    for f in files:
        if ex.search(os.path.basename(f)):
            continue
        f_name, f_ext = os.path.splitext(os.path.basename(f))
        new_name = _pick_new_key(f_name, names_dict, using_1st_char=(bool(db_conn) is False), prefix='t_')
        _err("Creating table: %s ..." % (new_name))
        names_dict[new_name] = f
        dfs[new_name] = json2df(file_path=f, db_conn=db_conn, tablename=new_name, chunksize=chunksize,
                                json_cols=json_cols)
    return (names_dict, dfs)


def json2df(file_path, db_conn=None, tablename=None, json_cols=[], chunksize=1000):
    """
    Convert a json file into a DataFrame and if db_conn is given, import into a DB table
    :param file_path: File path
    :param db_conn:   DB connection object
    :param tablename: table name
    :param json_cols: to_sql() fails if column is json, so forcing those columns to string
    :param chunksize:
    :return: a DataFrame object
    >>> pass    # TODO: implement test
    """
    global _DB_SCHEMA
    df = pd.read_json(file_path)
    if bool(db_conn):
        if bool(tablename) is False:
            tablename, ext = os.path.splitext(os.path.basename(file_path))
        # TODO: Temp workaround "<table>: Error binding parameter <N> - probably unsupported type."
        df_tmp_mod = _avoid_unsupported(df=df, json_cols=json_cols, name=tablename)
        df_tmp_mod.to_sql(name=tablename, con=db_conn, chunksize=chunksize, if_exists='replace', schema=_DB_SCHEMA)
    return df


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


def _avoid_unsupported(df, json_cols=[], name=None):
    """
    Drop DF cols to workaround "<table>: Error binding parameter <N> - probably unsupported type."
    :param df: A *reference* of panda DataFrame
    :param json_cols: List contains column names. Ex. ['connectionId', 'planJson', 'json']
    :param name: just for logging
    :return: Modified df
    >>> _avoid_unsupported(pd.DataFrame([{"a_json":"aaa", "test":"bbbb"}]), ["test"])
    Empty DataFrame
    Columns: []
    Index: [0]
    """
    keys = df.columns.tolist()
    drop_cols = []
    for k in keys:
        if k in json_cols or k.lower().find('json') > 0:
            # df[k] = df[k].to_string()
            drop_cols.append(k)
    if len(drop_cols) > 0:
        if bool(name): _err(" - dropping columns:%s from %s." % (str(drop_cols), name))
        return df.drop(columns=drop_cols)
    return df


### Database/DataFrame processing functions
# NOTE: without sqlalchemy is faster
def _db(dbname=':memory:', dbtype='sqlite', isolation_level=None, force_sqlalchemy=False, echo=False):
    """
    Create a DB object. For performance purpose, currently not using sqlalchemy if dbtype is sqlite
    :param dbname: Database name
    :param dbtype: DB type
    :param isolation_level: Isolation level
    :param echo: True output more if sqlalchemy is used
    :return: DB object
    >>> pass    # testing in connect()
    """
    if force_sqlalchemy is False and dbtype == 'sqlite':
        return sqlite3.connect(dbname, isolation_level=isolation_level)
    return create_engine(dbtype + ':///' + dbname, isolation_level=isolation_level, echo=echo)


def connect(dbname=':memory:', dbtype='sqlite', isolation_level=None, force_sqlalchemy=False, echo=False):
    """
    Connect to a database (SQLite)
    :param dbname: Database name
    :param dbtype: DB type
    :param isolation_level: Isolation level
    :param echo: True output more if sqlalchemy is used
    :return: connection (cursor) object
    >>> import sqlite3;s = connect()
    >>> isinstance(s, sqlite3.Connection)
    True
    """
    global _LAST_CONN
    if bool(_LAST_CONN): return _LAST_CONN

    db = _db(dbname=dbname, dbtype=dbtype, isolation_level=isolation_level, force_sqlalchemy=force_sqlalchemy,
             echo=echo)
    if dbtype == 'sqlite':
        if force_sqlalchemy is False:
            db.text_factory = str
        else:
            db.connect().connection.connection.text_factory = str
        # For 'sqlite, 'db' is the connection object because of _db()
        conn = db
    else:
        conn = db.connect()
    if bool(conn): _LAST_CONN = conn
    return conn


def q(sql, conn=None, no_history=False):
    """
    Alias of query
    :param sql: SELECT statement
    :param conn: DB connection object
    :param no_history: not saving this query into a history file
    :return: a DF object
    >>> pass
    """
    return query(sql, conn, no_history)


def query(sql, conn=None, no_history=False):
    """
    Call fetchall() with given query, expecting SELECT statement
    :param sql: SELECT statement
    :param conn: DB connection object
    :param no_history: not saving this query into a history file
    :return: a DF object
    >>> query("select name from sqlite_master where type = 'table'", connect(), True)
    Empty DataFrame
    Columns: [name]
    Index: []
    """
    global _LAST_CONN
    if bool(conn) is False: conn = _LAST_CONN
    # return conn.execute(sql).fetchall()
    df = pd.read_sql(sql, conn)
    if no_history is False and df.empty is False:
        _save_query(sql)
    return df


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
    df_new = pd.DataFrame([[_timestamp(), sql]], columns=["datetime", "query"])
    df_hist = csv2df(query_history_csv, header=None)
    if df_hist is False:
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
    rs = conn.execute("select distinct name from sqlite_master where type = 'table'%s" % (sql_and))
    if bool(rs) is False:
        return
    return _get_col_vals(rs.fetchall(), 0)


def inject_auto_comp():
    """
    Some hack to use autocomplete in the SQL
    :return: Void
    """
    tables = describe().name.values
    for t in tables:
        cols = describe(t).name.values
        try:
            get_ipython().user_global_ns[t] = type(t, (), {})
            for c in cols:
                setattr(get_ipython().user_global_ns[t], c, True)
        except:
            _err("setattr(get_ipython().user_global_ns[%s], c, True) failed" % t)
            pass



def draw(df, width=16, x_col=0, x_colname=None):
    """
    Helper function for df.plot()
    As pandas.DataFrame.plot is a bit complicated, using simple options only if this method is used.
    https://pandas.pydata.org/pandas-docs/stable/generated/pandas.DataFrame.plot.html

    ju.draw(ju.q("select QueryHour, SumSqSqlWallTime, SumPostPlanTime, SumSqPostPlanTime from query_stats")).tail()

    :param df: A DataFrame object, which first column will be the 'x' if x_col is not specified
    :param width: This is Inch and default is 16 inch.
    :param x_col: Column index number used for X axis.
    :param x_colname: If column name is given, use this instead of x_col.
    :return: DF (use .tail() or .head() to limit the rows)
    """
    try:
        import matplotlib.pyplot as plt
        get_ipython().run_line_magic('matplotlib', 'inline')
    except:
        _err("get_ipython().run_line_magic('matplotlib', 'inline') failed")
        pass
    height_inch = 8
    if len(df.columns) > 2:
        height_inch = len(df.columns) * 4
    if bool(x_colname) is False:
        x_colname = df.columns[x_col]
    df.plot(figsize=(width, height_inch), x=x_colname, subplots=True, sharex=True)
    # TODO: x axis doesn't show any legend
    # if len(df) > (width * 2):
    #    interval = int(len(df) / (width * 2))
    #    labels = df[x_colname].tolist()
    #    lables = labels[::interval]
    #    plt.xticks(list(range(interval)), lables)
    return df


def hist(run=None, like=None, html=True):
    """
    Alias of qhistory (query history)
    :param run: Integer of DataFrame row index which will be run
    :param like: String used in 'like' to search 'query' column
    :param html: Whether output in HTML or not
    :return: Pandas DataFrame contains a list of queries
    """
    return qhistory(run=run, like=like, html=html)


def history(run=None, like=None, html=True):
    """
    Alias of qhistory (query history)
    :param run: Integer of DataFrame row index which will be run
    :param like: String used in 'like' to search 'query' column
    :param html: Whether output in HTML or not
    :return: Pandas DataFrame contains a list of queries
    """
    return qhistory(run=run, like=like, html=html)


def qhistory(run=None, like=None, html=True):
    """
    Return query histories as DataFrame (so that it will be display nicely in Jupyter)
    :param run: Integer of DataFrame row index which will be run
    :param like: String used in 'like' to search 'query' column
    :param html: Whether output in HTML or not
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
    if bool(run):
        sql = df.loc[run, 'query']  # .loc[row_num, column_name]
        _err(sql)
        return query(sql=sql, conn=connect())
    if bool(like):
        df = df[df['query'].str.contains(like)]
    if html is False:
        #TODO: hist(html=False).groupby(['query']).count().sort_values(['count'])
        return df
    current_max_colwitdh = pd.get_option('display.max_colwidth')
    pd.set_option('display.max_colwidth', -1)
    out = df.to_html()
    pd.set_option('display.max_colwidth', current_max_colwitdh)
    from IPython.core.display import display, HTML
    display(HTML(out))


def desc(tablename=None, colname=None, conn=None):
    """
    Alias of describe()
    :param tablename: If empty, get table list
    :param colname: String used in like, such as column name
    :param conn: DB connection (cursor) object
    :return: void with printing CREATE statement, or a DF object contains table list
    """
    return describe(tablename=tablename, colname=colname, conn=conn)


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
    sql_and = ""
    if bool(colname):
        sql_and = " and name like '%" + str(colname) + "%'"
    if bool(tablename):
        # NOTE: this query is sqlite specific. names = list(map(lambda x: x[0], cursor.description))
        return query(sql="select `name`, `type`, `notnull`, `dflt_value`, `pk` from pragma_table_info('%s') where name is not 'index' %s order by cid" % (str(tablename), sql_and), conn=conn, no_history=True)
    return show_create_table(tablenames=None, like=colname, conn=conn)


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
    global _LAST_CONN
    if bool(conn) is False: conn = _LAST_CONN
    sql_and = ""
    if bool(like):
        sql_and = " and sql like '%" + str(like) + "%'"
    if bool(tablenames):
        if isinstance(tablenames, str): tablenames = [tablenames]
        for t in tablenames:
            # Currently searching any object as long as name matches
            rs = conn.execute("select sql from sqlite_master where name = '%s'%s" % (str(t), sql_and))
            if bool(rs) is False:
                continue
            print(rs.fetchall()[0][0])
            # SQLite doesn't like - in a table name. need to escape with double quotes.
            print("Rows: %s\n" % (conn.execute("SELECT count(oid) FROM \"%s\"" % (t)).fetchall()[0][0]))
        return
    if bool(like):
        # Currently only searching table object
        rs = conn.execute("select distinct name from sqlite_master where type = 'table'%s" % (sql_and))
        if bool(rs) is False:
            return
        tablenames = _get_col_vals(rs.fetchall(), 0)
        return show_create_table(tablenames=tablenames)
    return query(sql="select distinct name, rootpage from sqlite_master where type = 'table'%s order by rootpage" % (sql_and), conn=conn, no_history=True)


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
    import jaydebeapi
    cur_dir = os.path.dirname(os.path.abspath(__file__))
    jar_dir = os.path.abspath(os.path.join(cur_dir, '..')) + "/java/hadoop"
    conn = jaydebeapi.connect("org.apache.hive.jdbc.HiveDriver",
                              conn_str, [user, pwd],
                              [jar_dir + "/hive-jdbc-1.0.0-standalone.jar",
                               jar_dir + "/hadoop-core-1.0.3.jar"]).cursor()
    return conn


def hive_q(sql, conn):
    """
    Execute a SQL query against hive connection
    :param sql: (SELECT) SQL statement
    :param conn: DB connection (cursor)
    :return: Panda DataFrame
    #>>> hc = hive_conn("jdbc:hive2://localhost:10000/default")
    #>>> df = hive_q("SELECT 1", hc)
    #>>> bool(df)
    #True
    >>> pass    # TODO: implement test
    """
    conn.execute(sql)
    result = conn.fetchall()
    if bool(result):
        return pd.DataFrame(result)
    return result


def _massage_tuple_for_save(tpl, long_value="", num_cols=None):
    """
    Massage the given tuple to convert to a DataFrame or a Table columns later
    :param tpl: Tuple which contains value of a row
    :param long_value: multi-lines log messages
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


def _insert2table(conn, tablename, tpls, chunk_size=1000):
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
    Search a line with given regex (compiled)
    :param line: String of a log line
    :param prev_matches: A tuple which contains previously matched groups
    :param prev_message: String contain log's long text which often multi-lines
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
    # If current line is beginning of a new *log* line (eg: ^2018-08-\d\d...)
    if begin_re.search(line):
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
            _tmp_groups = _matches.groups()
            prev_message = _tmp_groups[-1]
            prev_matches = _tmp_groups[:(len(_tmp_groups) - 1)]

            if bool(size_re):
                _size_matches = size_re.search(prev_message)
                if _size_matches:
                    prev_matches += (_size_matches.group(1),)
            if bool(time_re):
                _time_matches = time_re.search(prev_message)
                if _time_matches:
                    prev_matches += (_time_matches.group(1),)
    else:
        prev_message += "" + line  # Looks like each line already has '\n'
    return (tmp_tuple, prev_matches, prev_message)


def _read_file_and_search(file, line_beginning, line_matching, size_regex=None, time_regex=None, num_cols=None):
    """
    Read a file and search each line with given regex
    :param file: A file path
    :param line_beginning: Regex to find the beginning of the line (normally like ^2018-08-21)
    :param line_matching: Regex to capture column values
    :param size_regex: Regex to capture size
    :param time_regex: Regex to capture time/duration
    :param num_cols: Number of columns
    :return: A list of tuples
    >>> pass    # TODO: implement test
    """
    begin_re = re.compile(line_beginning)
    line_re = re.compile(line_matching)
    size_re = re.compile(size_regex) if bool(size_regex) else None
    time_re = re.compile(time_regex) if bool(time_regex) else None
    prev_matches = None
    prev_message = None
    tuples = []

    f = _read(file)
    # Read lines
    for l in f:
        (tmp_tuple, prev_matches, prev_message) = _find_matching(line=l, prev_matches=prev_matches,
                                                                 prev_message=prev_message, begin_re=begin_re,
                                                                 line_re=line_re, size_re=size_re, time_re=time_re,
                                                                 num_cols=num_cols)
        if bool(tmp_tuple):
            tuples += [tmp_tuple]

    # append last message
    if bool(prev_matches):
        tuples += [_massage_tuple_for_save(tpl=prev_matches, long_value=prev_message, num_cols=num_cols)]
    return tuples


def logs2table(file_glob, tablename, conn=None,
               col_defs=['datetime', 'loglevel', 'thread', 'jsonstr', 'size', 'time', 'message'],
               num_cols=None, line_beginning="^\d\d\d\d-\d\d-\d\d",
               line_matching="^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) (.+?) \[(.+?)\] (\{.*?\}) (.+)",
               size_regex="[sS]ize = ([0-9]+)", time_regex="time = ([0-9.,]+ ?m?s)",
               max_file_num=10, multiprocessing=False):
    """
    Insert multiple log files into *one* table
    :param conn:  Connection object
    :param file_glob: simple regex used in glob to select files.
    :param tablename: Table name. Required
    :param col_defs: Column definition list or dict (column_name1 data_type, column_name2 data_type, ...)
    :param num_cols: Number of columns in the table. Optional if col_def_str is given.
    :param line_beginning: To detect the beginning of the log entry (normally ^\d\d\d\d-\d\d-\d\d)
    :param line_matching: A group matching regex to separate one log lines into columns
    :param size_regex: (optional) size-like regex to populate 'size' column
    :param time_regex: (optional) time/duration like regex to populate 'time' column
    :param max_file_num: To avoid memory issue, setting max files to import
    :param multiprocessing: If True, use multiple CPUs
    :return: Void if no error, or a tuple contains multiple information for debug
    >>> pass    # TODO: implement test
    """
    global _LAST_CONN
    if bool(conn) is False: conn = _LAST_CONN

    # NOTE: as python dict does not guarantee the order, col_def_str is using string
    if bool(num_cols) is False:
        num_cols = len(col_defs)
    files = _globr(file_glob)

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
            return res

    if multiprocessing:
        kwargs_list = []
        for f in files:
            kwargs_list.append(
                {'file': f, 'line_beginning': line_beginning, 'line_matching': line_matching, 'size_regex': size_regex,
                 'time_regex': time_regex, 'num_cols': num_cols})
        rs = _mexec(_read_file_and_search, kwargs_list, using_process=True)
        for tuples in rs:
            # If inserting into one table, probably no point of multiprocessing for this.
            if len(tuples) > 0:
                res = _insert2table(conn=conn, tablename=tablename, tpls=tuples)
                if bool(res) is False:  # if fails once, stop
                    return res
        return
    for f in files:
        _err("Processing %s ..." % (str(f)))
        tuples = _read_file_and_search(file=f, line_beginning=line_beginning, line_matching=line_matching,
                                       size_regex=size_regex, time_regex=time_regex, num_cols=num_cols)
        if len(tuples) > 0:
            res = _insert2table(conn=conn, tablename=tablename, tpls=tuples)
            if bool(res) is False:  # if fails once, stop
                return res


def logs2dfs(file_glob, col_names=['datetime', 'loglevel', 'thread', 'jsonstr', 'size', 'time', 'message'],
             num_fields=None, line_beginning="^\d\d\d\d-\d\d-\d\d",
             line_matching="^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) (.+?) \[(.+?)\] (\{.*?\}) (.+)",
             size_regex="[sS]ize =? ?([0-9]+)", time_regex="time = ([0-9.,]+ ?m?s)",
             max_file_num=10, multiprocessing=False):
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
    :param multiprocessing: If True, use multiple CPUs
    :return: A concatenated DF object
    #>>> df = logs2dfs(file_glob="debug.2018-08-28.11.log.gz")
    #>>> df2 = df[df.loglevel=='DEBUG'].head(10)
    #>>> bool(df2)
    #True
    >>> pass    # TODO: implement test
    """
    # NOTE: as python dict does not guarantee the order, col_def_str is using string
    if bool(num_fields) is False:
        num_fields = len(col_names)
    files = _globr(file_glob)

    if bool(files) is False:
        return False

    if len(files) > max_file_num:
        raise ValueError('Glob: %s returned too many files (%s)' % (file_glob, str(len(files))))

    dfs = []
    if multiprocessing:
        kwargs_list = []
        for f in files:
            kwargs_list.append(
                {'file': f, 'line_beginning': line_beginning, 'line_matching': line_matching, 'size_regex': size_regex,
                 'time_regex': time_regex, 'num_cols': num_fields})
        rs = _mexec(_read_file_and_search, kwargs_list, using_process=True)
        for tuples in rs:
            if len(tuples) > 0:
                dfs += [pd.DataFrame.from_records(tuples, columns=col_names)]
    else:
        for f in files:
            _err("Processing %s ..." % (str(f)))
            tuples = _read_file_and_search(file=f, line_beginning=line_beginning, line_matching=line_matching,
                                           size_regex=size_regex, time_regex=time_regex, num_cols=num_fields)
            if len(tuples) > 0:
                dfs += [pd.DataFrame.from_records(tuples, columns=col_names)]
    return pd.concat(dfs)


def load_csvs(src="./", db_conn=None, include_ptn='*.csv', exclude_ptn='', chunksize=1000):
    """
    Convert multiple CSV files to DF and DB tables
    :param src: Source directory path
    :param db_conn: DB connection object
    :param include_ptn: Include pattern
    :param exclude_ptn: Exclude pattern
    :param chunksize: to_sql() chunk size
    :return: A tuple contain key=>file relationship and Pandas dataframes objects
    #>>> (names_dict, dfs) = load_csvs(src="./stats")
    #>>> bool(names_dict)
    #True
    >>> pass    # TODO: implement test
    """
    names_dict = {}
    dfs = {}
    ex = re.compile(exclude_ptn)

    files = _globr(include_ptn, src)
    for f in files:
        if bool(exclude_ptn) and ex.search(os.path.basename(f)): continue

        f_name, f_ext = os.path.splitext(os.path.basename(f))
        new_name = _pick_new_key(f_name, names_dict, using_1st_char=(bool(db_conn) is False), prefix='t_')
        _err("Creating table: %s ..." % (new_name))
        names_dict[new_name] = f

        dfs[new_name] = csv2df(file_path=f, db_conn=db_conn, tablename=new_name, chunksize=chunksize)
    return (names_dict, dfs)


def csv2df(file_path, db_conn=None, tablename=None, chunksize=1000, header=0):
    '''
    Load a CSV file into a DataFrame
    :param file_path: File Path
    :param db_conn: DB connection object. If not empty, also import into a sqlite table
    :return: Pandas DF object or False if file is not readable
    >>> pass    # Testing in df2csv()
    '''
    global _DB_SCHEMA
    if os.path.exists(file_path) is False:
        return False
    df = pd.read_csv(file_path, escapechar='\\', header=header)
    if bool(db_conn):
        if bool(tablename) is False:
            tablename, ext = os.path.splitext(os.path.basename(file_path))
        df.to_sql(name=tablename, con=db_conn, chunksize=chunksize, if_exists='replace', schema=_DB_SCHEMA)
    return df


def df2csv(df, file_path, mode="w", header=True):
    '''
    Save DataFrame to a CSV file
    :param df_obj: Pandas Data Frame object
    :param file_path: File Path
    :param mode: mode used with open()
    :return: void
    >>> import pandas as pd
    >>> df = pd.DataFrame([{"key":"a", "val":"value"}])
    >>> df2csv(df, '/tmp/test_df2csv.csv', 'w')
    >>> df2 = csv2df('/tmp/test_df2csv.csv')
    >>> df == df2
        key   val
    0  True  True
    '''
    df.to_csv(file_path, mode=mode, header=header, index=False, escapechar='\\')


def gen_ldapsearch(ldap_json=None):
    if bool(ldap_json) is False:
        ldap_json = _globr("directory_configurations.json")[0]
    import json
    with open(ldap_json) as f:
        a = json.load(f)
    l = a[0]
    p = "ldaps" if "use_ssl" in l else "ldap"
    r = re.search(r"^[^=]*?=?([^=]+?)[ ,@]", l["username"])
    u = r.group(1) if bool(r) else l["username"]
    return "LDAPTLS_REQCERT=never ldapsearch -H %s://%s:%s -D \"%s\" -b \"%s\" -W \"(%s=%s)\"" % (
        p, l["host_name"], l["port"], l["username"], l["base_dn"], l["user_configuration"]["unique_id_attribute"], u)


def load(jsons_dir="./engine/aggregates", csvs_dir="./stats"):
    """
    Execute loading functions (currently load_jsons and load_csvs)
    :param jsons_dir: (optional) Path to a directory which contains JSON files
    :param csvs_dir: (optional) Path to a directory which contains CSV files
    :return: void
    >>> pass    # test should be done in load_jsons and load_csvs
    """
    # TODO: shouldn't have any paths in here but should be saved into some config file.
    load_jsons(jsons_dir, connect())
    load_csvs(csvs_dir, connect())
    # TODO: below does not work so that using above names_dict workaround
    # try:
    #    import jn_utils as ju
    #    get_ipython().set_custom_completer(ju._autocomp_matcher)    # Completer.matchers.append
    # except:
    #    _err("get_ipython().set_custom_completer(ju._autocomp_matcher) failed")
    #    pass
    _err("Populating autocomps...")
    inject_auto_comp()
    _err("Completed.")


def update_check(file=None, baseurl="https://raw.githubusercontent.com/hajimeo/samples/master/python"):
    """
    (almost) Alias of update()
    Check if update is avaliable (actually checking file size only at this moment)
    :param file: File path string. If empty, checks for this file (jn_utils.py)
    :param baseurl: Default is https://raw.githubusercontent.com/hajimeo/samples/master/python
    :return: If update available, True and output message in stderr)
    >>> b = update_check()
    >>> b is not False
    True
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
    >>> pass
    """
    try:
        from urllib.request import urlopen, Request
    except ImportError:
        from urllib2 import urlopen, Request
    if bool(file) is False:
        file = __file__
    # i'm assuming i do not need to concern of .pyc...
    filename = os.path.basename(file)
    url = baseurl.rstrip('/') + "/" + filename
    remote_size = int(urlopen(url).headers["Content-Length"])
    local_size = int(os.path.getsize(file))
    if remote_size < (local_size / 2):
        _err("Couldn't check the size of %s" % (url))
        return False
    if force_update is False and int(remote_size) == int(local_size):
        # If exactly same size, not updating
        _err("No need to update %s" % (filename))
        return
    if int(remote_size) != int(local_size):
        _err("%s size is different between remote (%s KB) and local (%s KB)." % (
            filename, int(remote_size / 1024), int(local_size / 1024)))
        if check_only:
            _err("To update, use 'ju.update()'\n")
            return True
    new_file = "/tmp/" + filename + "_" + _timestamp()
    os.rename(file, new_file)
    remote_content = urlopen(url).read()
    with open(file, 'wb') as f:
        f.write(remote_content)
    _err("%s was updated and back up is %s" % (filename, new_file))
    return


def configure():
    # TODO:
    config_path = os.getenv('JN_UTILS_CONFIG', os.getenv('HOME') + os.path.sep + ".ju_config")
    if os.path.exists(config_path) is False:
        # Download the template or ask a few questions to create config file
        pass
    pass


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

    doctest.testmod(verbose=True)
