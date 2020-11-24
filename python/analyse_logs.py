import jn_utils as ju
import linecache, re, os


def _gen_regex_for_request_logs(filename="request.log"):
    """
    Return a list which contains column names, and regex pattern for request.log
    :param filename: A file name or *simple* regex used in glob to select files.
    :return: (col_list, pattern_str)
    """
    files = ju._globr(filename)
    if bool(files) is False:
        return ([], "")
    checking_line = linecache.getline(files[0], 2)  # first line can be a junk: "** TRUNCATED ** linux x64"
    # @see: samples/bash/log_search.sh:f_request2csv()
    columns = ["clientHost", "l", "user", "date", "requestURL", "statusCode", "headerContentLength", "bytesSent",
               "elapsedTime", "headerUserAgent", "thread"]
    partern_str = '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) "([^"]+)" \[([^\]]+)\]'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    columns = ["clientHost", "l", "user", "date", "requestURL", "statusCode", "bytesSent", "elapsedTime",
               "headerUserAgent", "thread"]
    partern_str = '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) "([^"]+)" \[([^\]]+)\]'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    columns = ["clientHost", "l", "user", "date", "requestURL", "statusCode", "bytesSent", "elapsedTime",
               "headerUserAgent"]
    partern_str = '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) "([^"]+)'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    columns = ["clientHost", "l", "user", "date", "requestURL", "statusCode", "bytesSent", "elapsedTime"]
    partern_str = '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([0-9]+)'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)

    columns = ["clientHost", "l", "user", "date", "requestURL", "statusCode", "bytesSent", "elapsedTime", "misc"]
    partern_str = '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+)'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    else:
        ju._info("Can not determine the log format for %s . Using last one." % (str(files[0])))
        return (columns, partern_str)


def _gen_regex_for_app_logs(filepath=""):
    """
    Return a list which contains column names, and regex pattern for nexus.log, clm-server.log, server.log
    :param filepath: A file path or a file name or *simple* pattern used in glob to select files.
    :param checking_line: Based on this line, columns and regex will be decided
    :return: (col_list, pattern_str)
    2020-01-03 00:00:38,357-0600 WARN  [qtp1359575796-407871] anonymous org.sonatype.nexus.proxy.maven.maven2.M2GroupRepository - IOException during parse of metadata UID="oracle:/junit/junit-dep/maven-metadata.xml", will be skipped from aggregation!
    """
    # If filepath is not empty but not exist, assuming it as a glob pattern
    if bool(filepath) and os.path.isfile(filepath) is False:
        files = ju._globr(filepath)
        if bool(files) is False:
            return ([], "")
        filepath = files[0]

    # Default and in case can't be identified
    columns = ['date_time', 'loglevel', 'message']
    partern_str = '^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[^ ]*) +([^ ]+) +(.+)'

    checking_line = None
    for i in range(1, 10):
        checking_line = linecache.getline(filepath, i)
        if re.search('^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[^ ]*)', checking_line):
            break
    if bool(checking_line) is False:
        ju._info("Could not determine columns and pattern_str. Using default.")
        return (columns, partern_str)
    ju._debug(checking_line)

    columns = ['date_time', 'loglevel', 'thread', 'node', 'user', 'class', 'message']
    partern_str = '^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[^ ]*) +([^ ]+) +\[([^]]+)\] ([^ ]*) ([^ ]*) ([^ ]+) - (.*)'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    columns = ['date_time', 'loglevel', 'thread', 'user', 'class', 'message']
    partern_str = '^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[^ ]*) +([^ ]+) +\[([^]]+)\] ([^ ]*) ([^ ]+) - (.*)'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    return (columns, partern_str)


# TODO: should create one function does all
def _gen_regex_for_hazel_health(sample):
    """
    Return a list which contains column names, and regex pattern for nexus.log, clm-server.log, server.log
    :param sample: A sample line
    :return: (col_list, pattern_str)
    """
    # no need to add 'date_time'
    columns = ['ip', 'port', 'user', 'cluster_ver']
    cols_tmp = re.findall(r'([^ ,]+)=', sample)
    # columns += list(map(lambda x: x.replace('.', '_'), cols_tmp))
    columns += cols_tmp
    partern_str = '^\[([^\]]+)]:([^ ]+) \[([^\]]+)\] \[([^\]]+)\]'
    for c in cols_tmp:
        partern_str += " %s=([^, ]+)," % (c)
    partern_str += "?"
    return (columns, partern_str)


def _gen_regex_for_elastic_jvm(sample):
    """
    Return a list which contains column names, and regex pattern for nexus.log, clm-server.log, server.log
    :param sample: A sample line
    :return: (col_list, pattern_str)
    """
    # no need to add 'date_time'
    columns = ["duration","total_time","mem_before","mem_after","memory"]
    cols_tmp = re.findall(r'([^ ,]+)=', sample)
    # columns += list(map(lambda x: x.replace('.', '_'), cols_tmp))
    columns += cols_tmp
    partern_str = ' total \[([^]]+)\]/\[([^]]+)\], memory \[([^]]+)\]->\[([^]]+)\]/\[([^]]+)\]'
    for c in cols_tmp:
        partern_str += " %s=([^, ]+)," % (c)
    partern_str += "?"
    return (columns, partern_str)


def threads2table(filename="threads.txt", tablename=None, conn=None,
                  line_beginning="^\"", line_matching='^"?([^"]+)"? id=([^ ]+) state=(\w+)(.*)'):
    """
    Load the threads.txt file to table
    :param filename: String for a filename for glob or a file path.
    :param tablename: String for the table name
    :param conn: Optional DB connection object. If None, a new connetion will be created.
    :param line_beginning: Regex string for finding the beginning of a record
    :param line_matching: Regex string for finding columns
    :return: logs2table result
    """
    #
    return ju.logs2table(filename=filename, tablename=tablename, conn=conn,
                      col_names=['thread_name', 'id', 'state', 'stacktrace'],
                      line_beginning=line_beginning,
                      line_matching=line_matching,
                      size_regex=None, time_regex=None)


def etl(max_file_size=(1024 * 1024 * 100)):
    """
    Extract data and transform and load
    :param max_file_size:
    :return:
    """
    # At this moment, using system commands only when ./_filtered does not exist
    ju._system('[ ! -d ./_filtered ] && [ ! -s /tmp/log_search.sh ] && curl -s --compressed https://raw.githubusercontent.com/hajimeo/samples/master/bash/log_search.sh -o /tmp/log_search.sh')
    ju._system('[ ! -d ./_filtered ] && mkdir ./_filtered && source /tmp/log_search.sh && f_request2csv "" _filtered && f_audit2json "" _filtered')

    # Audit json if audit.json file exists
    _ = ju.json2df('audit.json', tablename="t_audit_logs", json_cols=['attributes', 'data'], conn=ju.connect())

    # If request.*csv* exists, use that (because it's faster), if not, logs2table, which is slower.
    request_logs = ju.csv2df('request.csv', tablename="t_request_logs", conn=ju.connect(), if_exists="replace")
    if bool(request_logs) is False:
        (col_names, line_matching) = _gen_regex_for_request_logs('request.log')
        request_logs = ju.logs2table('request.log', tablename="t_request_logs", col_names=col_names, line_beginning="^.",
                                     line_matching=line_matching, max_file_size=max_file_size)

    # Loading application log file(s) into database.
    (col_names, line_matching) = _gen_regex_for_app_logs('nexus.log')
    nxrm_logs = ju.logs2table('nexus.log', tablename="t_logs", col_names=col_names, line_matching=line_matching, max_file_size=max_file_size)
    (col_names, line_matching) = _gen_regex_for_app_logs('clm-server.log')
    nxiq_logs = ju.logs2table('clm-server.log', tablename="t_logs", col_names=col_names, line_matching=line_matching, max_file_size=max_file_size)

    # Hazelcast health monitor
    health_monitor = ju.csv2df('log_hazelcast_monitor.csv', tablename="t_health_monitor", conn=ju.connect(), if_exists="replace")
    if bool(health_monitor) is False and bool(nxrm_logs):
        df_hm = ju.q("""select date_time, message from t_logs where class = 'com.hazelcast.internal.diagnostics.HealthMonitor'""")
        if len(df_hm) > 0:
            (col_names, line_matching) = _gen_regex_for_hazel_health(df_hm['message'][1])
            msg_ext = df_hm['message'].str.extract(line_matching)
            msg_ext.columns = col_names
            # Delete unnecessary column(s), then left join the extracted dataframe, then load into SQLite
            df_hm.drop(columns=['message']).join(msg_ext).to_sql(name="t_health_monitor", con=ju.connect(), chunksize=1000, if_exists='replace', schema=ju._DB_SCHEMA)
            health_monitor = True
            ju._autocomp_inject(tablename='t_health_monitor')

    # Elastic JVM monitor
    elastic_monitor = ju.csv2df('log_elastic_jvm_monitor.csv', tablename="t_elastic_jvm_monitor", conn=ju.connect(), if_exists="replace")
    if bool(elastic_monitor) is False and bool(nxrm_logs):
        df_em = ju.q("""select date_time, message from t_logs where class = 'org.elasticsearch.monitor.jvm'""")
        if len(df_em) > 0:
            (col_names, line_matching) = _gen_regex_for_elastic_jvm(df_em['message'][1])
            msg_ext = df_em['message'].str.extract(line_matching)
            msg_ext.columns = col_names
            # Delete unnecessary column(s), then left join the extracted dataframe, then load into SQLite
            df_em.drop(columns=['message']).join(msg_ext).to_sql(name="t_elastic_jvm_monitor", con=ju.connect(), chunksize=1000, if_exists='replace', schema=ju._DB_SCHEMA)
            health_monitor = True
            ju._autocomp_inject(tablename='t_elastic_jvm_monitor')

    ju.display(ju.desc(), name="Available_Tables")


def analyse_logs(start_isotime=None, end_isotime=None, tail_num=10000, max_file_size=(1024 * 1024 * 100)):
    """
    A prototype / demonstration function for extracting then analyse log files
    :param start_isotime: YYYY-MM-DD hh:mm:ss,sss
    :param end_isotime: YYYY-MM-DD hh:mm:ss,sss
    :param tail_num: How many rows/records to display. Default is 10K
    :param max_file_size: File smaller than this size will be skipped.
    :return: void
    >>> pass    # test should be done in each function
    """
    etl(max_file_size=max_file_size)

    where_sql = "WHERE 1=1"
    if bool(start_isotime) is True:
        where_sql += " AND date_time >= '" + start_isotime + "'"
    if bool(end_isotime) is True:
        where_sql += " AND date_time <= '" + end_isotime + "'"

    if bool(request_logs):
        display_name = "RequestLog_StatusCode_Hourly_aggs"
        # Can't use above where_sql for this query
        where_sql2 = "WHERE 1=1"
        if bool(start_isotime) is True:
            where_sql2 += " AND UDF_STR2SQLDT(`date`, '%d/%b/%Y:%H:%M:%S %z') >= UDF_STR2SQLDT('" + start_isotime + " +0000','%Y-%m-%d %H:%M:%S %z')"
        if bool(end_isotime) is True:
            where_sql2 += " AND UDF_STR2SQLDT(`date`, '%d/%b/%Y:%H:%M:%S %z') <= UDF_STR2SQLDT('" + end_isotime + " +0000','%Y-%m-%d %H:%M:%S %z')"
        query = """SELECT UDF_REGEX('(\d\d/[a-zA-Z]{3}/20\d\d:\d\d)', `date`, 1) AS date_hour, statusCode,
    CAST(MAX(CAST(elapsedTime AS INT)) AS INT) AS max_elaps, 
    CAST(MIN(CAST(elapsedTime AS INT)) AS INT) AS min_elaps, 
    CAST(AVG(CAST(elapsedTime AS INT)) AS INT) AS avg_elaps, 
    CAST(AVG(CAST(bytesSent AS INT)) AS INT) AS avg_bytes, 
    count(*) AS occurrence
FROM t_request_logs
%s
GROUP BY 1, 2""" % (where_sql2)
        ju.display(ju.q(query), name=display_name, desc=query)

        display_name = "RequestLog_Status_ByteSent_Elapsed"
        query = """SELECT UDF_STR2SQLDT(`date`, '%%d/%%b/%%Y:%%H:%%M:%%S %%z') AS date_time, 
    CAST(statusCode AS INTEGER) AS statusCode, 
    CAST(bytesSent AS INTEGER) AS bytesSent, 
    CAST(elapsedTime AS INTEGER) AS elapsedTime 
FROM t_request_logs %s""" % (where_sql2)
        ju.draw(ju.q(query).tail(tail_num), name=display_name, desc=query)

    if bool(health_monitor):
        display_name = "NexusLog_Health_Monitor"
        query = """select date_time
    , UDF_STR_TO_INT(`physical.memory.free`) as sys_mem_free_bytes
    --, UDF_STR_TO_INT(`swap.space.free`) as swap_free_bytes
    , CAST(`swap.space.free` AS INTEGER) as swap_free_bytes
    , UDF_STR_TO_INT(`heap.memory.used/max`) as heap_used_percent
    , CAST(`major.gc.count` AS INTEGER) as majour_gc_count
    , UDF_STR_TO_INT(`major.gc.time`) as majour_gc_msec
    , CAST(`load.process` AS REAL) as load_proc_percent
    , CAST(`load.system` AS REAL) as load_sys_percent
    , CAST(`load.systemAverage` AS REAL) as load_system_avg
    , CAST(`thread.count` AS INTEGER) as thread_count
    , CAST(`connection.active.count` AS INTEGER) as node_conn_count
FROM t_health_monitor
%s""" % (where_sql)
        ju.draw(ju.q(query).tail(tail_num), name=display_name, desc=query)

    if bool(elastic_monitor):
        display_name = "NexusLog_ElasticJvm_Monitor"
        query = """select date_time
    , UDF_STR_TO_INT(duration) as duration_ms
    , UDF_STR_TO_INT(total_time) as total_time_ms
    , UDF_STR_TO_INT(mem_before) as mem_before_bytes
    , UDF_STR_TO_INT(mem_after) as mem_after_bytes
FROM t_elastic_jvm_monitor
%s""" % (where_sql)
        ju.draw(ju.q(query).tail(tail_num), name=display_name, desc=query)

    if bool(nxiq_logs):
        display_name = "NxiqLog_Policy_Scan_aggs"
        query = """SELECT thread, min(date_time), max(date_time), 
    STRFTIME('%s', UDF_REGEX('(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d+)', max(date_time), 1))
  - STRFTIME('%s', UDF_REGEX('(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d.\d+)', min(date_time), 1)) as diff,
    count(*)
FROM t_logs
WHERE thread LIKE 'PolicyEvaluateService%'
GROUP BY 1
ORDER BY diff, thread"""
        ju.display(ju.q(query).tail(tail_num), name=display_name, desc=query)

        display_name = "NxiqLog_HDS_Client_Requests"
        query = """SELECT date_time, 
  UDF_REGEX(' in (\d+) ms', message, 1) as ms,
  UDF_REGEX('ms. (\d+)$', message, 1) as status
FROM t_logs
WHERE t_logs.class = 'com.sonatype.insight.brain.hds.HdsClient'
  AND t_logs.message LIKE 'Completed request%'"""
        ju.display(ju.q(query).tail(tail_num), name=display_name, desc=query)

        display_name = "NxiqLog_Top10_Slow_Scans"
        query = """SELECT date_time, thread,
    UDF_REGEX(' scan id ([^ ]+),', message, 1) as scan_id,
    CAST(UDF_REGEX(' in (\d+) ms', message, 1) as INT) as ms 
FROM t_logs
WHERE t_logs.message like 'Evaluated policy for%'
ORDER BY ms DESC
LIMIT 10"""
        ju.display(ju.q(query).tail(tail_num), name=display_name, desc=query)

    if bool(nxrm_logs) or bool(nxiq_logs):
        # analyse t_logs table (eg: count ERROR|WARN)
        display_name = "WarnsErrors_Hourly"
        query = """SELECT UDF_REGEX('(\d\d\d\d-\d\d-\d\d.\d\d)', date_time, 1) as date_hour, loglevel, count(*) as num 
    FROM t_logs
    %s
      AND loglevel NOT IN ('TRACE', 'DEBUG', 'INFO')
    GROUP BY 1, 2""" % (where_sql)
        ju.draw(ju.q(query).tail(tail_num), name=display_name, desc=query)
        # count unique threads per hour
        display_name = "Unique_Threads_Hourly"
        query = """SELECT date_hour, count(*) as num 
    FROM (SELECT distinct UDF_REGEX('(\d\d\d\d-\d\d-\d\d.\d\d)', date_time, 1) as date_hour, thread 
        FROM t_logs
        %s
    ) tt
    GROUP BY 1""" % (where_sql)
        ju.draw(ju.q(query).tail(tail_num), name=display_name, desc=query)
    # TODO: analyse db job triggers
    # q("""SELECT description, fireInstanceId
    # , nextFireTime
    # , DATETIME(ROUND(nextFireTime / 1000), 'unixepoch') as NextAt
    # , DATETIME(ROUND(previousFireTime / 1000), 'unixepoch') as PrevAt
    # , DATETIME(ROUND(startTime / 1000), 'unixepoch') as startAt
    # , jobDataMap, cronEx
    # FROM t_db_job_triggers_json
    # WHERE nextFireTime is NOT NULL
    #  AND nextFireTime > 1578290830000
    # ORDER BY nextFireTime
    # """)
