import jn_utils as ju

def analyse_logs(start_isotime=None, end_isotime=None, elapsed_time=0, tail_num=10000, max_file_size=(1024 * 1024 * 100), load_only=False):
    """
    A prototype / demonstration function to analyse log files
    :param start_isotime:
    :param end_isotime:
    :param elapsed_time:
    :param tail_num:
    :return: void
    >>> pass    # test should be done in each function
    """
    # Audit json if audit.json file exists
    _ = ju.json2df('audit.json', tablename="t_audit_logs", json_cols=['attributes', 'data'], conn=ju.connect())

    # If request.*csv* exists, use that (because it's faster), if not, logs2table, which is slower.
    request_logs = ju.csv2df('request.csv', tablename="t_request_logs", conn=ju.connect(), if_exists="replace")
    if bool(request_logs) is False:
        (col_names, line_matching) = ju._gen_regex_for_request_logs('request.log')
        request_logs = ju.logs2table('request.log', tablename="t_request_logs", col_names=col_names, line_beginning="^.",
                                     line_matching=line_matching, max_file_size=max_file_size)

    # Loading application log file(s) into database.
    (col_names, line_matching) = ju._gen_regex_for_app_logs('nexus.log')
    nxrm_logs = ju.logs2table('nexus.log', tablename="t_logs", col_names=col_names, line_matching=line_matching, max_file_size=max_file_size)
    (col_names, line_matching) = ju._gen_regex_for_app_logs('clm-server.log')
    nxiq_logs = ju.logs2table('clm-server.log', tablename="t_logs", col_names=col_names, line_matching=line_matching, max_file_size=max_file_size)

    # Hazelcast health monitor
    health_monitor = ju.csv2df('log_hazelcast_monitor.csv', tablename="t_health_monitor", conn=ju.connect(), if_exists="replace")
    if bool(health_monitor) is False and bool(nxrm_logs):
        df_hm = ju.q("""select date_time, message from t_logs where class = 'com.hazelcast.internal.diagnostics.HealthMonitor'""")
        if len(df_hm) > 0:
            (col_names, line_matching) = ju._gen_regex_for_hazel_health(df_hm['message'][1])
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
            (col_names, line_matching) = ju._gen_regex_for_elastic_jvm(df_em['message'][1])
            msg_ext = df_em['message'].str.extract(line_matching)
            msg_ext.columns = col_names
            # Delete unnecessary column(s), then left join the extracted dataframe, then load into SQLite
            df_em.drop(columns=['message']).join(msg_ext).to_sql(name="t_elastic_jvm_monitor", con=ju.connect(), chunksize=1000, if_exists='replace', schema=ju._DB_SCHEMA)
            health_monitor = True
            ju._autocomp_inject(tablename='t_elastic_jvm_monitor')

    ju.display(ju.desc(), name="Available_Tables")
    if load_only:
        return

    where_sql = "WHERE 1=1"
    if bool(start_isotime) is True:
        where_sql += " AND date_time >= '" + start_isotime + "'"
    if bool(end_isotime) is True:
        where_sql += " AND date_time <= '" + end_isotime + "'"

    if bool(request_logs):
        display_name = "RequestLog_StatusCode_Hourly_aggs"
        # Can't use above where_sql for this query
        where_sql2 = "WHERE 1=1"
        if bool(elapsed_time) is True:
            where_sql2 += " AND elapsedTime >= %d" % (elapsed_time)
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
        ju._info("# Query (%s): \n%s" % (display_name, query))
        ju.display(ju.q(query), name=display_name)

        display_name = "RequestLog_Status_ByteSent_Elapsed"
        query = """SELECT UDF_STR2SQLDT(`date`, '%%d/%%b/%%Y:%%H:%%M:%%S %%z') AS date_time, 
    CAST(statusCode AS INTEGER) AS statusCode, 
    CAST(bytesSent AS INTEGER) AS bytesSent, 
    CAST(elapsedTime AS INTEGER) AS elapsedTime 
FROM t_request_logs %s""" % (where_sql)
        ju._info("# Query (%s): \n%s" % (display_name, query))
        ju.draw(ju.q(query).tail(tail_num), name=display_name)

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
        ju._info("# Query (%s): \n%s" % (display_name, query))
        ju.draw(ju.q(query), name=display_name)

    if bool(elastic_monitor):
        display_name = "NexusLog_ElasticJvm_Monitor"
        query = """select date_time
    , UDF_STR_TO_INT(duration) as duration_ms
    , UDF_STR_TO_INT(total_time) as total_time_ms
    , UDF_STR_TO_INT(mem_before) as mem_before_bytes
    , UDF_STR_TO_INT(mem_after) as mem_after_bytes
FROM t_elastic_jvm_monitor
%s""" % (where_sql)
        ju._info("# Query (%s): \n%s" % (display_name, query))
        ju.draw(ju.q(query), name=display_name)

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
        ju._info("# Query (%s): \n%s" % (display_name, query))
        ju.display(ju.q(query), name=display_name)

        display_name = "NxiqLog_HDS_Client_Requests"
        query = """SELECT date_time, 
  UDF_REGEX(' in (\d+) ms', message, 1) as ms,
  UDF_REGEX('ms. (\d+)$', message, 1) as status
FROM t_logs
WHERE t_logs.class = 'com.sonatype.insight.brain.hds.HdsClient'
  AND t_logs.message LIKE 'Completed request%'"""
        ju._info("# Query (%s): \n%s" % (display_name, query))
        ju.display(ju.q(query), name=display_name)

        display_name = "NxiqLog_Top10_Slow_Scans"
        query = """SELECT date_time, thread,
    UDF_REGEX(' scan id ([^ ]+),', message, 1) as scan_id,
    CAST(UDF_REGEX(' in (\d+) ms', message, 1) as INT) as ms 
FROM t_logs
WHERE t_logs.message like 'Evaluated policy for%'
ORDER BY ms DESC
LIMIT 10"""
        ju._info("\n: \n%s" % (display_name, query))
        ju.display(ju.q(query), name=display_name)

    if bool(nxrm_logs) or bool(nxiq_logs):
        # analyse t_logs table (eg: count ERROR|WARN)
        display_name = "WarnsErros_Hourly"
        query = """SELECT UDF_REGEX('(\d\d\d\d-\d\d-\d\d.\d\d)', date_time, 1) as date_hour, loglevel, count(1) 
    FROM t_logs
    %s
      AND loglevel NOT IN ('TRACE', 'DEBUG', 'INFO')
    GROUP BY 1, 2""" % (where_sql)
        ju._info("# Query (%s): \n%s" % (display_name, query))
        ju.draw(ju.q(query), name=display_name)

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