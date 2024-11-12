import jn_utils as ju
import get_json as gj
import linecache, re, os, json

isHeaderContentLength = False


def _gen_regex_for_request_logs(filepath="request.log"):
    """
    Return a list which contains column names, and regex pattern for request.log
    Based on bash/log_search.sh f_request2csv
    :param filepath: A file path or *simple* regex used in glob to select files.
    :return: (col_list, pattern_str)
    """
    if os.path.isfile(filepath) is False:
        files = ju._globr(filepath)
        if bool(files) is False:
            return ([], "")
        filepath = files[0]
    checking_line = linecache.getline(filepath, 2)  # first line can be a junk: "** TRUNCATED ** linux x64"
    # @see: samples/bash/log_search.sh:f_request2csv()
    columns = ["clientHost", "l", "user", "date", "requestURL", "statusCode", "headerContentLength", "bytesSent",
               "elapsedTime", "headerUserAgent", "thread"]
    partern_str = '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) "([^"]+)" \[([^\]]+)\]'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    columns = ["clientHost", "l", "user", "date", "requestURL", "statusCode", "headerContentLength", "bytesSent",
               "elapsedTime", "headerUserAgent", "thread", "misc"]
    partern_str = '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) "([^"]+)" \[([^\]]+)\] (.+)'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    columns = ["clientHost", "l", "user", "date", "requestURL", "statusCode", "bytesSent", "elapsedTime",
               "headerUserAgent", "thread"]
    partern_str = '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) "([^"]+)" \[([^\]]+)\]'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    columns = ["clientHost", "l", "user", "date", "requestURL", "statusCode", "headerContentLength", "bytesSent",
               "elapsedTime", "headerUserAgent"]
    partern_str = '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) "([^"]+)"'
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
    columns = ["clientHost", "l", "date", "requestURL", "statusCode", "bytesSent", "elapsedTime", "user", "misc"]
    partern_str = '^([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" http_status=([^ ]+) http_content_length=([^ ]+) latency=([^ ]+) user=([^ ]+) (.+)'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    ju._info("Can not determine the log format for %s . Using default one." % (str(filepath)))
    return (columns, partern_str)


def _gen_regex_for_app_logs(filepath=""):
    """
    Return a list which contains column names, and regex pattern for nexus.log, clm-server.log, server.log
    :param filepath: A file path or a file name or *simple* pattern used in glob to select files.
    :param checking_line: Based on this line, columns and regex will be decided
    :return: (col_list, pattern_str)
    NOTE: TODO: gz file such as request-2021-03-02.log.gz won't be recognised.
    """
    # If filepath is not empty but not exist, assuming it as a glob pattern
    if os.path.isfile(filepath) is False:
        files = ju._globr(filepath)
        if bool(files) is False:
            return ([], "")
        filepath = files[0]

    # Default and in case can't be identified
    columns = ['date_time', 'loglevel', 'message']
    partern_str = '^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[.,0-9]*)[^ ]* +([^ ]+) +(.+)'

    checking_line = None
    for i in range(1, 100):  # 10 was not enough
        checking_line = linecache.getline(filepath, i)
        if re.search('^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d)', checking_line):
            break
    if bool(checking_line) is False:
        ju._info("Could not determine columns and pattern_str. Using default.")
        return (columns, partern_str)
    ju._debug(checking_line)

    columns = ['date_time', 'loglevel', 'thread', 'node', 'user', 'class', 'message']
    partern_str = '^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[.,0-9]*)[^ ]* +([^ ]+) +\[([^]]+)\][^ ]* ([^ ]*) ([^ ]*) ([^ ]+) - (.*)'
    if re.search(partern_str, checking_line):
        return (columns, partern_str)
    columns = ['date_time', 'loglevel', 'thread', 'user', 'class', 'message']
    partern_str = '^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[.,0-9]*)[^ ]* +([^ ]+) +\[([^]]+)\][^ ]* ([^ ]*) ([^ ]+) - (.*)'
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
    columns = ["duration", "total_time", "mem_before", "mem_after", "memory"]
    cols_tmp = re.findall(r'([^ ,]+)=', sample)
    # columns += list(map(lambda x: x.replace('.', '_'), cols_tmp))
    columns += cols_tmp
    partern_str = ' total \[([^]]+)\]/\[([^]]+)\], memory \[([^]]+)\]->\[([^]]+)\]/\[([^]]+)\]'
    for c in cols_tmp:
        partern_str += " %s=([^, ]+)," % (c)
    partern_str += "?"
    return (columns, partern_str)


def _create_t_log_elastic_monitor_jvm(tablename='t_log_elastic_monitor_jvm'):
    df_em = ju.q("""select date_time, message from t_nxrm_logs where class = 'org.elasticsearch.monitor.jvm'""")
    if len(df_em) == 0:
        return False
    (col_names, line_matching) = _gen_regex_for_elastic_jvm(df_em['message'][1])
    msg_ext = df_em['message'].str.extract(line_matching)
    msg_ext.columns = col_names
    # Delete unnecessary column(s), then left join the extracted dataframe, then load into SQLite
    df_em.drop(columns=['message']).join(msg_ext).to_sql(name=tablename, con=ju.connect(),
                                                         chunksize=1000, if_exists='replace',
                                                         schema=ju._DB_SCHEMA)
    ju._autocomp_inject(tablename=tablename)


def _save_json(file_regex, save_path="", search_props=None, key_name=None, rtn_attrs=None, find_all=False):
    file_paths = ju._globr(file_regex, useRegex=True)
    if bool(file_paths) is False:
        ju._debug("No file found by using regex:%s" % file_regex)
        return False
    js_obj = gj.get_json(file_paths[0], search_props=search_props, key_name=key_name, rtn_attrs=rtn_attrs,
                         find_all=find_all)
    if bool(js_obj) is False:
        ju._info("No JSON returned by searching with %s and %s" % (str(search_props), file_regex))
        return False
    if bool(save_path) is False:
        return js_obj
    with open(save_path, 'w') as f:
        f.write(json.dumps(js_obj))


def update():
    ju.update(file=__file__)


def request2table(filepath, tablename="t_request", max_file_size=(1024 * 1024 * 100), time_from_regex=None,
                  time_until_regex=None):
    """
    Convert request.log file to DB table
    :param filepath: File path or glob pattern
    :param tablename: DB table name
    :param max_file_size: larger than this file will be skipped
    :param time_from_regex: Regex string to detect the start time from the log
    :param time_until_regex: Regex string to detect the end time from the log
    :return: True if no error, or DataFrame list
    """
    log_path = ju._get_file(filepath)
    if bool(log_path) is False:
        return False
    line_from = line_until = 0
    if bool(time_from_regex):
        line_from = ju._linenumber(log_path, "\d\d/.../\d\d\d\d:" + time_from_regex)
    if bool(time_until_regex):
        line_until = ju._linenumber(log_path, "\d\d/.../\d\d\d\d:" + time_until_regex)
    (col_names, line_matching) = _gen_regex_for_request_logs(log_path)
    rtn = ju.logs2table(log_path, tablename=tablename, line_beginning="^.",
                        col_names=col_names, line_matching=line_matching,
                        max_file_size=max_file_size,
                        line_from=line_from, line_until=line_until)
    if ju.exists(tablename):
        ju._info("%s has been created (may want to run 'al.req2table_post()')" % tablename)
        return True
    return False


def req2table_post(tablename="t_request", add_startTime=True, datetime_col="date", elapsed_col="elapsedTime"):
    """
    Post actions after converting request log to table
    :param tablename: request table
    :param add_startTime: This one is slower and if True, add a new column for start time
    :param datetime_col: Name of the column which stores datetime information
    :param elapsed_col: Name of the column which stores elapsed time information
    :return: void
    """
    if ju.exists("t_request", "headerContentLength"):
        try:
            ju._info("Changing '-' in headerContentLength to 0 ...")
            _ = ju.execute(sql=f"UPDATE {tablename} SET headerContentLength = 0 WHERE headerContentLength = '-'")
        except:
            pass
    if add_startTime:
        try:
            _ = ju.execute(sql=f"ALTER TABLE {tablename} ADD COLUMN startTime timestamp DEFAULT NULL")
        except Exception as e:
            ju._err(str(e))
        try:
            _ = ju.execute(sql=f"ALTER TABLE {tablename} ADD COLUMN endTime timestamp DEFAULT NULL")
        except Exception as e:
            ju._err(str(e))
        try:
            ju._info(f"Populating endTime from '{datetime_col}' column ...")
            _ = ju.execute(sql=f"UPDATE {tablename} SET endTime = UDF_STRFTIME('%Y-%m-%d %H:%M:%S', `{datetime_col}`)")
        except Exception as e:
            ju._err(str(e))
        try:
            ju._info(f"Populating startTime from '{datetime_col}' and '{elapsed_col}' columns (this one is slow) ...")
            _ = ju.execute(sql=f"UPDATE {tablename} SET startTime = UDF_STARTED_TIME(`{datetime_col}`, {elapsed_col})")
        except Exception as e:
            ju._err(str(e))


def applog2table(filepath, tablename="t_applog", max_file_size=(1024 * 1024 * 100), time_from_regex=None,
                 time_until_regex=None):
    """
    Convert application log file to DB table
    applog2table(filepath="clm-server.log", tablename="t_iq_logs", max_file_size=1294748262)
    :param filepath: a path or a glob pattern
    :param tablename: DB table name
    :param max_file_size:
    :param time_from_regex:
    :param time_until_regex:
    :return:
    """
    log_path = ju._get_file(filepath)
    if bool(log_path) is False:
        return False
    line_from = line_until = 0
    if bool(time_from_regex):
        line_from = ju._linenumber(log_path, "^\d\d\d\d-\d\d-\d\d " + time_from_regex)
    if bool(time_until_regex):
        line_until = ju._linenumber(log_path, "^\d\d\d\d-\d\d-\d\d " + time_until_regex)
    (col_names, line_matching) = _gen_regex_for_app_logs(log_path)
    return ju.logs2table(log_path, tablename=tablename, col_names=col_names,
                         line_matching=line_matching, max_file_size=max_file_size,
                         line_from=line_from, line_until=line_until)


def etl_request(log_suffix=".log", max_file_size=(1024 * 1024 * 100), add_startTime=True, tablename="t_request"):
    if ju.exists(tablename) is False:
        # If request.*csv* exists, use that. if not, logs2table, which is slower.
        _ = ju.load_csvs(src="./_filtered/", include_ptn="request.csv", max_file_size=(max_file_size * 5),
                         conn=ju.connect())
    # If no csv file, then try to load request.log
    if ju.exists(tablename) is False:
        _ = request2table("request" + log_suffix)
    if ju.exists(tablename):
        ju._info("Executing req2table_post for %s with add_startTime %s" % (tablename, add_startTime))
        req2table_post(tablename=tablename, add_startTime=add_startTime)
        global isHeaderContentLength
        # non NXRM3 request.log wouldn't have headerContentLength
        isHeaderContentLength = ju.exists(tablename, "headerContentLength")
        return True
    return False


def etl(path="", log_suffix=".log", dist="./_filtered", max_file_size=(1024 * 1024 * 100), time_from_regex=None,
        time_until_regex=None, add_startTime=True):
    """
    Extract data, transform and load (to DB)
    :param path: To specify a zip file
    :param log_suffix: To specify the YYYY-MM-DD.log.gz
    :param dist: Directory path to save the extracted data (default ./_filtered)
    :param max_file_size: Larger than this size will be skipped (default 100MB)
    :param time_from_regex: Regex for 'time' for logs2table's line_from (eg "(0[5-9]|1[0-3]]):\d\d:\d\d")
    :param time_until_regex: Regex for 'time' for logs2table's line_until
    :param add_startTime: In the table, add 'startedTime' from 'date_time' and 'elapsedTime'. Requires col_names
    :return: void
    """
    global isHeaderContentLength
    if bool(path) is False:
        maybe_zips = ju._globr("*support*.zip", depth=1)
        if len(maybe_zips) > 0:
            path = maybe_zips[-1:][0]
            ju._info("'path' is not specified and found zip file: %s . Using this one..." % path)

    cur_dir = os.getcwd()  # chdir to the original path later
    dist = os.path.realpath(dist)
    tmpObj = None
    extracted_dir = None
    if os.path.isfile(path) and path.endswith(".zip"):
        tmpObj = ju._extract_zip(path)
        extracted_dir = tmpObj.name
        os.chdir(extracted_dir)
    elif os.path.isdir(path):
        os.chdir(path)

    try:
        ### Extract ############################################################
        # Somehow Jupyter started as service uses 'sh', so forcing 'bash'
        ju._system(
            ju._SH_EXECUTABLE + " -c '[ ! -s /tmp/log_search.sh ] && curl -s --compressed https://raw.githubusercontent.com/hajimeo/samples/master/bash/log_search.sh -o /tmp/log_search.sh; [ ! -d \"%s\" ] && mkdir \"%s\"'" % (
                dist, dist))
        ju._system(
            ju._SH_EXECUTABLE + " -c '%s[ -d \"%s\" ] && . /tmp/log_search.sh && f_request2csv \"\" \"%s\" 2>/dev/null && f_audit2json \"\" \"%s\"'" % (
                "cd %s;" % extracted_dir if extracted_dir else "", dist, dist, dist))
        # system-filestores from sysinfo.json
        _save_json("sysinfo\.json", "%s/system-filestores.json" % dist, "system-filestores")
        # extracting from DB export.json files
        _save_json("config/export\.json", "%s/http_client.json" % dist, "records,@class=http_client", "@class",
                   "connection,proxy")
        _save_json("config/export\.json", "%s/db_repos.json" % dist, "records,@class=repository", "@class",
                   "recipe_name,repository_name,online,attributes", True)
        saml_config = _save_json("config/export\.json", "", "records,@class:saml", "@class",
                                 "entityId,idpMetadata,mapping,keyStoreBytes,keyStorePassword", True)
        if bool(saml_config):
            db_saml_idp_metadata = ""
            from lxml import etree as ET
            if 'idpMetadata' in saml_config:
                t = ET.fromstring(saml_config['idpMetadata'].encode('utf-8'))
                db_saml_idp_metadata += ET.tostring(t, pretty_print=True, encoding='unicode') + "\n"
            if 'mapping' in saml_config:
                db_saml_idp_metadata += "<!-- mapping \n" + str(saml_config['mapping']) + "\n-->"
            if len(db_saml_idp_metadata) > 0:
                with open("%s/db_saml_idp_metadata.xml" % dist, 'w') as f:
                    f.write(db_saml_idp_metadata)
        _save_json("security/export\.json", "%s/db_saml_user.json" % dist, "records,@class=saml_user", "@class",
                   "id,status,roles", True)
        # TODO: add more

        ### Transform & Load ###################################################
        # Loading db_xxxxx.json
        _ = ju.load_jsons(src=dist, include_ptn="db_*.json", flatten=True, max_file_size=(max_file_size * 2),
                          conn=ju.connect())
        # If audit.json file exists and no time_xxxx_regex
        if os.path.isfile(
                dist + "/audit.json"):  # and bool(time_from_regex) is False and bool(time_until_regex) is False
            _ = ju.json2df(dist + "/audit.json", tablename="t_audit_logs", flatten=True, max_file_size=max_file_size)
        else:
            # TODO: currently below is too slow, so not using "max_file_size=max_file_size,"
            log_path = ju._get_file("audit" + log_suffix)
            if bool(log_path):
                line_from = line_until = 0
                if bool(time_from_regex):
                    line_from = ju._linenumber(log_path, "^\{\"timestamp\":\"\d\d\d\d-\d\d-\d\d " + time_from_regex)
                if bool(time_until_regex):
                    line_until = ju._linenumber(log_path, "^\{\"timestamp\":\"\d\d\d\d-\d\d-\d\d " + time_until_regex)
                _ = ju.json2df(log_path, tablename="t_audit_logs",
                               line_by_line=True, line_from=line_from, line_until=line_until)

        # ./work/db/xxxxx.json (new DB)
        _ = ju.load_jsons(".", include_ptn=".+/db/.+\.json", exclude_ptn='(samlConfigurationExport\.json|export\.json)',
                          useRegex=True, conn=ju.connect())

        # xxxxx.csv. If CSV, probably 3 times higher should be OK
        _ = ju.load_csvs(src="./_filtered/", include_ptn="*.csv", max_file_size=(max_file_size * 5), conn=ju.connect())

        etl_request(log_suffix=log_suffix, max_file_size=max_file_size, add_startTime=add_startTime)

        # Loading application log file(s) into database.
        nxrm_logs = applog2table("nexus" + log_suffix, "t_nxrm_logs")
        _ = applog2table("clm-server" + log_suffix, "t_iq_logs")

        # Hazelcast health monitor
        if ju.exists("t_log_hazelcast_monitor") is False and bool(nxrm_logs):
            df_hm = ju.q(
                """select date_time, message from t_nxrm_logs where class = 'com.hazelcast.internal.diagnostics.HealthMonitor'""")
            if len(df_hm) > 0:
                (col_names, line_matching) = _gen_regex_for_hazel_health(df_hm['message'][1])
                msg_ext = df_hm['message'].str.extract(line_matching)
                msg_ext.columns = col_names
                # Delete unnecessary column(s), then left join the extracted dataframe, then load into SQLite
                df_hm.drop(columns=['message']).join(msg_ext).to_sql(name="t_log_hazelcast_monitor", con=ju.connect(),
                                                                     chunksize=1000, if_exists='replace',
                                                                     schema=ju._DB_SCHEMA)
                ju._autocomp_inject(tablename='t_log_hazelcast_monitor')

        # org.elasticsearch.monitor.jvm
        if ju.exists("t_log_elastic_monitor_jvm") is False and bool(nxrm_logs):
            _create_t_log_elastic_monitor_jvm('t_log_elastic_monitor_jvm')

        # Thread dump
        _ = ju.logs2table(filename="threads.txt", tablename="t_threads", conn=ju.connect(),
                          col_names=['thread_name', 'id', 'state', 'stacktrace'],
                          line_beginning="^[^ ]",
                          line_matching='^"?([^"]+)"? id=([^ ]+) state=(\w+)(.*)',
                          size_regex=None, time_regex=None)
    except:
        raise
    finally:
        ju.autocomplete()
        os.chdir(cur_dir)
        if tmpObj is not None:
            tmpObj.cleanup()

    ju.display(ju.desc(), name="Available_Tables")


def analyze_log_table(log_table_name, where_sql="", tail_num=10000):
    # analyse t_logs table (eg: count ERROR|WARN)
    display_name = "WarnsErrors_Hourly"
    # UDF_REGEX('(\d\d\d\d-\d\d-\d\d.\d\d)', date_time, 1)
    query = """SELECT substr(`date_time`, 1, 13) as date_hour, loglevel, count(*) as num 
    FROM %s
    %s
      AND loglevel NOT IN ('TRACE', 'DEBUG', 'INFO')
    GROUP BY 1, 2""" % (log_table_name, where_sql)
    ju.draw(ju.q(query).tail(tail_num), name=display_name, desc=query, is_x_col_datetime=False)

    # count unique threads per hour
    display_name = "Unique_Threads_Hourly"
    # TODO: should use UDF_REGEX("^([^-@]+)", thread, 1) as thread ?
    query = """SELECT date_hour, count(*) as num 
    FROM (SELECT distinct substr(`date_time`, 1, 13) as date_hour, thread 
        FROM %s
        %s
    ) tt
    GROUP BY 1""" % (log_table_name, where_sql)
    ju.draw(ju.q(query).tail(tail_num), name=display_name, desc=query, is_x_col_datetime=False)


def analyse_request_logs(tablename="t_request", tail_num=10000, use_headerContentLength=False):
    """
    Analyse request log. Expecting afeter etl_request() so taht `t_request` already exists.
    :param tablename: Request table name
    :param tail_num: How many rows/records to display. Default is 10K
    :param use_headerContentLength: In the report, Add a few aggregate collumns which use headerContentLength column
    :return: void
    >>> pass    # test should be done in each function
    """
    global isHeaderContentLength
    if use_headerContentLength:
        isHeaderContentLength = use_headerContentLength

    where_sql = "WHERE 1=1"
    headerContentLengthAgg = ""
    avgMsPerByteAgg = "CAST(SUM(CAST(elapsedTime AS INT)) / SUM(CAST(bytesSent AS INT)) AS INT)  AS avgMsPerByte,"
    avgBytesPerMsAgg = "CAST(SUM(CAST(bytesSent AS INT)) / SUM(CAST(elapsedTime AS INT)) AS INT)  AS avgBytesPerMs,"

    if isHeaderContentLength:
        # where_sql = "WHERE (CAST(bytesSent AS INT) + CAST(headerContentLength AS INT) > 0)" # TODO: POST has 0 and 0
        # NOTE: Don't forget to append a comma in the end of line.
        headerContentLengthAgg = "AVG(CAST(headerContentLength AS INTEGER)) AS bytesReceived,"
        avgMsPerByteAgg = "CAST(SUM(CAST(elapsedTime AS INTEGER)) / SUM(CAST(bytesSent AS INT) + CAST(headerContentLength AS INT)) AS INT) AS avgMsPerByte,"
        avgBytesPerMsAgg = "CAST(SUM(CAST(bytesSent AS INT) + CAST(headerContentLength AS INT)) / SUM(CAST(elapsedTime AS INTEGER)) AS INT) AS avgBytesPerMs,"

    if ju.exists(tablename):
        display_name = "RequestLog_StatusCode_Hourly_aggs_2xx_5xx"
        # Join db_repos.json and request.log
        #   AND UDF_REGEX('.+ /nexus/content/repositories/([^/]+)', {tablename}.requestURL, 1) IN (SELECT repository_name FROM t_db_repo where t_db_repo.`attributes.storage.blobStoreName` = 'nexus3')
        query = f"""SELECT substr(`date`, 1, 14)||':00:00' AS date_hour, substr(statusCode, 1, 1) || 'xx' as status_code,
    CAST(MAX(CAST(elapsedTime AS INT)) AS INT) AS max_elaps, 
    CAST(AVG(CAST(elapsedTime AS INT)) AS INT) AS avg_elaps, 
    CAST(AVG(CAST(bytesSent AS INT)) AS INT) AS avg_bytes, 
    {avgBytesPerMsAgg} 
    count(*) AS requests
FROM {tablename}
{where_sql}
  AND (statusCode like '2%' OR statusCode like '5%')
GROUP BY 1, 2"""
        df = ju.q(query)
        ju.display(df, name=display_name, desc=query)
        #ju.draw(df.tail(tail_num), name=display_name, desc=query)

        display_name = "RequestLog_Status_ByteSent_Elapsed"
        query = f"""SELECT TIME(substr(date, 13, 8)) as hhmmss,
    {avgBytesPerMsAgg} {avgMsPerByteAgg}
    SUM(CAST(bytesSent AS INTEGER)) AS bytesSent, {headerContentLengthAgg} 
    SUM(CAST(elapsedTime AS INTEGER)) AS elapsedTime,
    count(*) AS requests
FROM {tablename}
{where_sql}
GROUP BY hhmmss"""
        ju.draw(ju.q(query).tail(tail_num), name=display_name, desc=query, is_x_col_datetime=False)


# TODO: time_from_regex and time_until_regex are probably not working
def analyse_logs(path="", log_suffix=".log", tail_num=10000, max_file_size=(1024 * 1024 * 100), skip_etl=False,
                 add_startTime=True, use_headerContentLength=False, time_from_regex=None, time_until_regex=None):
    """
    A prototype / demonstration function for extracting then analyse log files
    :param path: File (including zip) path
    :param log_suffix: To specify the YYYY-MM-DD.log.gz
    :param tail_num: How many rows/records to display. Default is 10K
    :param max_file_size: File smaller than this size will be skipped.
    :param skip_etl: Skip etl() function
    :param add_startTime: In the table, add 'startedTime' from 'date' and 'elapsedTime' (for request.log, not request.csv)
    :param use_headerContentLength: In the report, Add a few aggregate collumns which use headerContentLength column
    :param time_from_regex: Regex to extract the start time from the log file
    :param time_until_regex: Regex to extract the end time from the log file
    :return: void
    >>> pass    # test should be done in each function
    """
    global isHeaderContentLength
    if use_headerContentLength:
        isHeaderContentLength = use_headerContentLength
    if bool(skip_etl) is False:
        etl(path=path, log_suffix=log_suffix, max_file_size=max_file_size, add_startTime=add_startTime,
            time_from_regex=time_from_regex, time_until_regex=time_until_regex)

    analyse_request_logs(tablename="t_request", tail_num=tail_num, use_headerContentLength=use_headerContentLength)

    where_sql = "WHERE 1=1"
    if ju.exists("t_log_hazelcast_monitor"):
        display_name = "NexusLog_Health_Monitor"
        query = """SELECT date_time
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
FROM t_log_hazelcast_monitor
%s""" % (where_sql)
        ju.draw(ju.q(query).tail(tail_num), name=display_name, desc=query)

    if ju.exists("t_log_elastic_monitor_jvm"):
        display_name = "NexusLog_ElasticJvm_Monitor"
        query = """SELECT date_time
    , UDF_STR_TO_INT(duration) as duration_ms
    , UDF_STR_TO_INT(total_time) as total_time_ms
    , UDF_STR_TO_INT(mem_before) as mem_before_bytes
    , UDF_STR_TO_INT(mem_after) as mem_after_bytes
FROM t_log_elastic_monitor_jvm
%s""" % (where_sql)
        ju.draw(ju.q(query).tail(tail_num), name=display_name, desc=query)

    if ju.exists("t_iq_logs"):
        display_name = "NxiqLog_Policy_Scan_durations"
        # Window function / partition doesn't work with sqlite installed by pip somehow
        query = """SELECT t_scan_start.thread, start_dt, end_dt,
  (STRFTIME('%s', end_dt) - STRFTIME('%s', start_dt)) as duration, duration_ms_str
  FROM (SELECT thread, date_time as start_dt FROM t_iq_logs 
    WHERE thread like 'PolicyEvaluateService-%%' AND message like '%%Received %% scan for application%%'
      AND date_time >= (SELECT date_time FROM t_iq_logs WHERE thread = 'PolicyEvaluateService-0' ORDER BY date_time DESC LIMIT 1)) t_scan_start
LEFT JOIN (SELECT thread, date_time as end_dt, UDF_REGEX('(\d+) ms\.', message, 1) as duration_ms_str 
    FROM t_iq_logs 
    WHERE thread like 'PolicyEvaluateService-%%' AND message like '%%Evaluated policy for app public id%%') t_scan_end
  ON t_scan_start.thread = t_scan_end.thread and t_scan_start.start_dt < t_scan_end.end_dt
ORDER BY start_dt"""
        # TODO: not accurate
        # ju.display(ju.q(query).tail(tail_num), name=display_name, desc=query)

        display_name = "NxiqLog_HDS_Client_Requests"
        query = """SELECT date_time, 
  UDF_REGEX('ms. (\d+)$', message, 1) as status,
  CAST(UDF_REGEX(' in (\d+) ms', message, 1) AS INT) as ms
FROM t_iq_logs
%s
  AND class in ('com.sonatype.insight.brain.hds.HdsClient', 'com.sonatype.insight.brain.hds.DefaultHdsClient')
  AND message LIKE 'Completed request%%'""" % (where_sql)
        ju.draw(ju.q(query).tail(tail_num), name=display_name, desc=query)

        display_name = "NxiqLog_Scans_Evaluations"
        query = """SELECT date_time, thread,
    UDF_REGEX(' scan id ([^ ]+),', message, 1) as scan_id,
    CAST(UDF_REGEX(' in (\d+) ms', message, 1) as INT) as ms 
FROM t_iq_logs
%s
  AND message like 'Evaluated policy for%%'""" % (where_sql)
        ju.draw(ju.q(query).tail(tail_num), name=display_name, desc=query)

    log_table_name = None
    if ju.exists("t_nxrm_logs"):
        log_table_name = "t_nxrm_logs"
    elif ju.exists("t_iq_logs"):
        log_table_name = "t_iq_logs"
    if bool(log_table_name):
        analyze_log_table(log_table_name, where_sql, tail_num)

    if ju.exists("t_nxrm_logs"):
        display_name = "Join_Requests_And_AppLog_For_TimeoutException"
        # UDF_REGEX('(\d\d\d\d-\d\d-\d\d.\d\d)', date_time, 1)
        query = """SELECT n.date_time, n.loglevel, n.thread, n.user
    , r.clientHost, r.user, r.requestURL, r.statusCode, r.bytesSent, r.elapsedTime
    FROM %s n
    LEFT JOIN t_request r ON CAST(r.elapsedTime AS INT) >= 30000 AND n.thread = r.thread
        AND UDF_STRFTIME('%%d/%%b/%%Y:%%H:%%M:%%S', DATETIME(n.date_time))||' +0000' = r.`date` 
    WHERE n.message like '%%Idle timeout expired: 30000/30000 ms%%'""" % (log_table_name)
        try:
            ju.display(ju.q(query).tail(tail_num), name=display_name, desc=query)
        except:
            # non NXRM3 request.log wouldn't have r.thread
            pass
        if ju.exists("t_log_task_status"):
            display_name = "Potentially_long_running_tasks"
            query = """SELECT thread_id, task_name, user, count(*)/2 as occurence, min(date_time), max(date_time), ((STRFTIME('%s', max(date_time)) - STRFTIME('%s', min(date_time))) / (count(*) / 2)) as avg_duration FROM t_log_task_status
    GROUP BY 1,2,3
    HAVING avg_duration > 1800
    ORDER BY min(date_time)"""
            try:
                ju.display(ju.q(query).tail(tail_num), name=display_name, desc=query)
            except:
                pass

    if ju.exists("t_threads"):
        display_name = "Blocked_Threads"
        query = """SELECT * FROM t_threads
WHERE thread_name not like '%InstrumentedSelectChannelConnector%'
  AND (thread_name NOT like '%-ServerConnector%')
  AND (state like 'BLOCK%' or state like 'block%')"""
        ju.display(ju.q(query).tail(tail_num), name=display_name, desc=query)

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

    # Join request.log and nexus.log
    # _date="24/Feb/2022"
    # _tz="-0500"
    # _sql="SELECT * FROM t_request JOIN (SELECT '%s:'||substr(date_time, 12, 8)||' %s' as req_datetime, thread FROM t_nxrm_logs) t ON t_request.date = t.req_datetime and t_request.thread = t.thread" % (_date, _tz)
    # ju.q(_sql)
