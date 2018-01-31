#!/usr/bin/env bash
#
# Bunch of grep functions to search log files
# Don't use complex one, so that each function can be easily copied and pasted
#
# TODO: tested on Mac only (eg: sed -E, ggrep)
# which ggrep || alias ggrep=grep
#

usage() {
    echo "HELP/USAGE:"
    echo "This script contains useful functions to search log files.

How to use: source and use some function
    source ${BASH_SOURCE}
    help f_someFunctionName

    Examples:
    # Check what kind of caused by is most
    f_topCausedByExceptions ./yarn_application.log | tail -n 10

    # Check what kind of ERROR is most
    f_topErrors ./yarn_application.log | tail -n 10
Or
    ${BASH_SOURCE} -f log_file_path [-s start_date] [-e end_date] [-t log_type]
    NOTE:
      For start and end date, as using grep, may not return good result if you specify minutes or seconds.
      'log_type' currently accepts only 'ya' (yarn app log)

"
    echo "Available functions:"
    list
}
### Public functions ###################################################################################################

function f_topCausedByExceptions() {
    local __doc__="List Caused By xxxxException"
    local _path="$1"
    local _is_shorter="$2"
    local _regex="Caused by.+Exception"

    if [[ "$_is_shorter" =~ (^y|^Y) ]]; then
        _regex="Caused by.+?Exception"
    fi
    egrep -wo "$_regex" "$_path" | sort | uniq -c | sort -n
}

function f_topErrors() {
    local __doc__="List top ERRORs. Eg.: f_topErrors ./hbase-ams-master-fslhd.log Y N \"\" \"^2017-05-10\""
    local _path="$1"
    local _is_including_warn="$2"
    local _not_hiding_number="$3"
    local _regex="$4"
    local _date_regex_start="$5"
    local _date_regex_end="$6"

    if [ -n "$_date_regex_start" ]; then
        _getAfterFirstMatch "$_path" "$_date_regex_start" "$_date_regex_end" > /tmp/f_topErrors_$$.tmp
        _path=/tmp/f_topErrors_$$.tmp
    fi
    if [ -z "$_regex" ]; then
        _regex="(ERROR|SEVERE|FATAL|SHUTDOWN|java\..+?Exception).+"

        if [[ "$_is_including_warn" =~ (^y|^Y) ]]; then
            _regex="(ERROR|SEVERE|FATAL|SHUTDOWN|java\..+?Exception|WARN|WARNING).+"
        fi
    fi

    if [[ "$_not_hiding_number" =~ (^y|^Y) ]]; then
        egrep -wo "$_regex" "$_path" | sort | uniq -c | sort -n
    else
        egrep -wo "$_regex" "$_path" | gsed -r "s/0x[0-9a-f][0-9a-f][0-9a-f]+/0x__________/g" | gsed -r "s/[0-9][0-9]+/____/g" | sort | uniq -c | sort -n
    fi
}

function f_topSlowLogs() {
    local __doc__="List top performance related log entries. Eg.: f_topSlwErrors ./hbase-ams-master-fslhd.log Y \"\" \"^2017-05-10\""
    local _path="$1"
    local _not_hiding_number="$2"
    local _regex="$3"
    local _date_regex_start="$4"
    local _date_regex_end="$5"

    if [ -n "$_date_regex_start" ]; then
        _getAfterFirstMatch "$_path" "$_date_regex_start" "$_date_regex_end" > /tmp/f_topErrors_$$.tmp
        _path=/tmp/f_topErrors_$$.tmp
    fi
    if [ -z "$_regex" ]; then
        _regex="(slow|performance|delay|delaying|waiting|latency|too many|not sufficient|lock held).+"
    fi

    if [[ "$_not_hiding_number" =~ (^y|^Y) ]]; then
        egrep -wio "$_regex" "$_path" | sort | uniq -c | sort -n
    else
        # ([0-9]){2,4} didn't work
        egrep -wi "$_regex" "$_path" | gsed -r "s/[0-9a-f][0-9a-f][0-9a-f][0-9a-f]+/____/g" | gsed -r "s/[0-9]/_/g" | sort | uniq -c | sort -n
    fi
}

function f_errorsAt() {
    local __doc__="List ERROR date and time"
    local _path="$1"
    local _is_showing_longer="$2"
    local _is_including_warn="$3"
    local _regex="(ERROR|SEVERE|FATAL)"

    if [[ "$_is_including_warn" =~ (^y|^Y) ]]; then
        _regex="(ERROR|SEVERE|FATAL|WARN)"
    fi

    if [[ "$_is_showing_longer" =~ (^y|^Y) ]]; then
        _regex="${_regex}.+$"
    fi

    egrep -wo "^20[12].+? $_regex" "$_path" | sort
}

function f_appLogContainersAndHosts() {
    local __doc__="List containers ID and host (from YARN app log)"
    local _path="$1"
    local _sort_by_host="$2"

    if [[ "$_sort_by_host" =~ (^y|^Y) ]]; then
        ggrep "^Container: container_" "$_path" | sort -k4 | uniq
    else
        ggrep "^Container: container_" "$_path" | sort | uniq
    fi
}

function f_appLogContainerCountPerHost() {
    local __doc__="Count container per host (from YARN app log)"
    local _path="$1"
    local _sort_by_host="$2"

    if [[ "$_sort_by_host" =~ (^y|^Y) ]]; then
        f_appLogContainersAndHosts "$1" | awk '{print $4}' | sort | uniq -c
    else
        f_appLogContainersAndHosts "$1" | awk '{print $4}' | sort | uniq -c | sort -n
    fi
}

    function f_appLogJobCounters() {
        local __doc__="List the Job Final counters (Tez only?) (from YARN app log)"
        local _path="$1"
        local _line=""
        local _regex="(Final Counters for [^ :]+)[^\[]+(\[.+$)"

        ggrep -Eo "Final Counters for .+$" "$_path" | while read -r _line ; do
            if [[ "$_line" =~ ${_regex} ]]; then
                echo "# ${BASH_REMATCH[1]}"
                # TODO: not clean enough. eg: [['File System Counters HDFS_BYTES_READ=1469456609',
                echo "${BASH_REMATCH[2]}" | gsed -r 's/\[([^"\[])/\["\1/g' | gsed -r 's/([^"])\]/\1"\]/g' | gsed -r 's/([^"]), ([^"])/\1", "\2/g' | gsed -r 's/\]\[/\], \[/g' | python -m json.tool
                echo ""
            fi
        done
    }

function f_appLogJobExports() {
    local __doc__="List exports in the job (from YARN app log)"
    local _path="$1"
    local _regex="^export "

    egrep "$_regex" "$_path" | sort | uniq -c
}

function f_appLogFindFirstSyslog() {
    local __doc__="After yarn_app_logs_splitter, find which one was started first."
    local _dir_path="${1-.}"
    local _num="${2-10}"

    ( find "${_dir_path%/}" -name "*.syslog" | xargs -I {} bash -c "ggrep -oHE '^${_DATE_FORMAT} \d\d:\d\d:\d\d' -m 1 {}" | awk -F ':' '{print $2":"$3":"$4" "$1}' ) | sort -n | head -n $_num
}

function f_appLogFindLastSyslog() {
    local __doc__="After yarn_app_logs_splitter, find which one was ended in the last. gtac is required"
    local _dir_path="${1-.}"
    local _num="${2-10}"
    local _regex="${3}"

    if [ -n "$_regex" ]; then
        ( for _f in `ggrep -l "$_regex" ${_dir_path%/}/*.syslog`; do _dt="`gtac $_f | ggrep -oE "^${_DATE_FORMAT} \d\d:\d\d:\d\d" -m 1`" && echo "$_dt $_f"; done ) | sort -nr | head -n $_num
    else
        ( for _f in `find "${_dir_path%/}" -name "*.syslog"`; do _dt="`gtac $_f | ggrep -oE "^${_DATE_FORMAT} \d\d:\d\d:\d\d" -m 1`" && echo "$_dt $_f"; done ) | sort -nr | head -n $_num
    fi
}

function f_hdfsAuditLogCountPerTime() {
    local __doc__="Count a log file (eg.: HDFS audit) per 10 minutes"
    local _path="$1"
    local _datetime_regex="$2"

    if [ -z "$_datetime_regex" ]; then
        _datetime_regex="^${_DATE_FORMAT} \d\d:\d"
    fi

    if ! which bar_chart.py &>/dev/null; then
        echo "## bar_chart.py is missing..."
        local _cmd="uniq -c"
    else
        local _cmd="bar_chart.py"
    fi

    ggrep -oE "$_datetime_regex" $_path | $_cmd
}

function f_hdfsAuditLogCountPerCommand() {
    local __doc__="Count HDFS audit per command for some period"
    local _path="$1"
    local _datetime_regex="$2"

    if ! which bar_chart.py &>/dev/null; then
        echo "## bar_chart.py is missing..."
        local _cmd="sort | uniq -c"
    else
        local _cmd="bar_chart.py"
    fi

    # TODO: not sure if sed regex is good (seems to work, Mac sed / gsed doesn't like +?)
    if [ ! -z "$_datetime_regex" ]; then
        gsed -n "s@\($_datetime_regex\).*\(cmd=[^ ]*\).*src=.*\$@\1,\2@p" $_path | $_cmd
    else
        gsed -n 's:^.*\(cmd=[^ ]*\) .*$:\1:p' $_path | $_cmd
    fi
}

function f_hdfsAuditLogCountPerUser() {
    local __doc__="Count HDFS audit per user for some period"
    local _path="$1"
    local _per_method="$2"
    local _datetime_regex="$3"

    if [ ! -z "$_datetime_regex" ]; then
        ggrep -E "$_datetime_regex" $_path > /tmp/f_hdfs_audit_count_per_user_$$.tmp
        _path="/tmp/f_hdfs_audit_count_per_user_$$.tmp"
    fi

    if ! which bar_chart.py &>/dev/null; then
        echo "## bar_chart.py is missing..."
        local _cmd="sort | uniq -c"
    else
        local _cmd="bar_chart.py"
    fi

    # TODO: not sure if sed regex is good (seems to work, Mac sed / gsed doesn't like +?)
    if [[ "$_per_method" =~ (^y|^Y) ]]; then
        gsed -n 's:^.*\(ugi=[^ ]*\) .*\(cmd=[^ ]*\).*src=.*$:\1,\2:p' $_path | $_cmd
    else
        gsed -n 's:^.*\(ugi=[^ ]*\) .*$:\1:p' $_path | $_cmd
    fi
}

function f_longGC() {
    local __doc__="List long GC (real >= 1)"
    local _path="$1"
    local _regex=", real=[1-9]"

    egrep "$_regex" "$_path"
}

function f_listPerflogEnd() {
    local __doc__="ggrep </PERFLOG ...> to see duration"
    local _path="$1"
    local _sort_by_duration="$2"

    if [[ "$_sort_by_duration" =~ (^y|^Y) ]]; then
        # expecting 5th one is duration after removing start and end time
        #egrep -wo '</PERFLOG .+>' "$_path" | sort -t'=' -k5n
        # removing start and end so that we can easily compare two PERFLOG outputs
        egrep -wo '</PERFLOG .+>' "$_path" | gsed -r "s/ (start|end)=[0-9]+//g" | sort -t'=' -k3n
    else
        # sorting with start time
        egrep -wo '</PERFLOG .+>' "$_path" | sort -t'=' -k3n
    fi
}

function f_getPerflog() {
    local __doc__="Get lines between PERFLOG method=xxxxx"
    local _path="$1"
    local _approx_datetime="$2"
    local _thread_id="$3"
    local _method="${4-compile}"

    _getAfterFirstMatch "$_path" "^${_approx_datetime}.+ Thread-${_thread_id}\]: .+<PERFLOG method=${_method} " "Thread-${_thread_id}\]: .+<\/PERFLOG method=${_method} " | ggrep -vP ": Thread-(?!${_thread_id})\]"
}

function f_findJarByClassName() {
    local __doc__="Find jar by class name (add .class in the name). If symlink needs to be followed, add -L in _search_path"
    local _class_name="$1"
    local _search_path="${2-/usr/hdp/current/*/}"

    # if search path is an integer, treat as PID
    if [[ $_search_path =~ ^-?[0-9]+$ ]]; then
        lsof -nPp $_search_path | ggrep -oE '/.+\.(jar|war)$' | sort | uniq | xargs -I {} bash -c "less {} | ggrep -qm1 -w $_class_name && echo {}"
        return
    fi
    # NOTE: some 'less' can't read jar, in that case, replace to 'jar -tvf', but may need to modify $PATH
    find $_search_path -type f -name '*.jar' -print0 | xargs -0 -n1 -I {} bash -c "less {} | ggrep -m 1 -w $_class_name > /tmp/f_findJarByClassName_$$.tmp && ( echo {}; cat /tmp/f_findJarByClassName_$$.tmp )"
    # TODO: it won't search war file...
}

# TODO: find hostname and container, splits, actual query (mr?) etc from app log

function f_extractByDates() {
    local __doc__="Grep large file with date string"
    local _log_file_path="$1"
    local _start_date="$2"
    local _end_date="$3"
    local _date_format="$4"
    local _is_utc="$6"

    local _date_regex=""
    local _date="gdate"

    # in case file path includes wildcard
    ls -1 $_log_file_path &>/dev/null
    if [ $? -ne 0 ]; then
        return 3
    fi

    if [ -z "$_start_date" ]; then
        return 4
    fi

    if [ -z "$_date_format" ]; then
        _date_format="%Y-%m-%d %H:%M:%S"
    fi

    if [[ "$_is_utc" =~ (^y|^Y) ]]; then
        _date="gdate -u"
    fi

    # if _start_date is integer, treat as from X hours ago
    if [[ $_start_date =~ ^-?[0-9]+$ ]]; then
        _start_date="`$_date +"$_date_format" -d "${_start_date} hours ago"`" || return 5
    fi

    # if _end_date is integer, treat as from X hours ago
    if [[ $_end_date =~ ^-?[0-9]+$ ]]; then
        _end_date="`$_date +"$_date_format" -d "${_start_date} ${_end_date} hours ago"`" || return 6
    fi

    eval "_getAfterFirstMatch \"$_log_file_path\" \"$_start_date\" \"$_end_date\""

    return $?
}

function f_splitApplog() {
    local __doc__="Split YARN App log with yarn_app_logs_splitter.py"
    local _app_log="$1"
    local _out_name="containers_`basename $_app_log .log`"
    # Assuming yarn_app_logs_splitter.py is in the following location
    local _script_path="`dirname $(dirname $(dirname $BASH_SOURCE))`/dev-tools/hadoop-tools/yarn/yarn_app_logs_splitter.py"
    if [ ! -s "$_script_path" ]; then
        echo "$_script_path does not exist"
        return 1
    fi
    grep -Fv "***********************************************************************" $_app_log > /tmp/${_app_log}.tmp
    python "$_script_path" --container-log-dir $_out_name --app-log /tmp/${_app_log}.tmp
}

function f_swimlane() {
    local __doc__="TODO: use swimlane (but broken?)"
    local _app_log="$1"
    local _out_name="`basename $_app_log .log`.svg"
    local _tmp_name="`basename $_app_log .log`.tmp"
    local _script_path="`dirname $(dirname $(dirname $BASH_SOURCE))`/tez/tez-tools/swimlanes/swimlane.py"
    ggrep 'HISTORY' $_app_log > ./$_tmp_name
    if [ ! -s "$_tmp_name" ]; then
        echo "$_tmp_name is empty."
        return 1
    fi
    if [ ! -s "$_script_path" ]; then
        echo "$_script_path does not exist"
        return 1
    fi
    python "$_script_path" -o $_out_name $_tmp_name
}

function f_git_search() {
    local __doc__="Grep git comments to find matching branch or tag"
    local _search="$1"
    local _git_dir="$2"
    local _is_fetching="$3"
    local _is_showing_grep_result="$4"

    if [ -d "$_git_dir" ]; then
       cd "$_git_dir"
    fi

    if [[ "$_is_fetching" =~ (^y|^Y) ]]; then
        git fetch
    fi

    local _grep_result="`git log --all --grep "$_search"`"
    if [[ "$_is_showing_grep_result" =~ (^y|^Y) ]]; then
        echo "$_grep_result"
    fi

    local _commits_only="`echo "$_grep_result" | ggrep ^commit | cut -d ' ' -f 2`"

    echo "# Searching branches ...."
    for c in $_commits_only; do git branch -r --contains $c; done | sort
    echo "# Searching tags ...."
    for c in $_commits_only; do git tag --contains $c; done | sort
}

function f_os_checklist() {
    local __doc__="Check OS kernel parameters"
    local _conf="${1-./}"

    #cat /sys/kernel/mm/transparent_hugepage/enabled
    #cat /sys/kernel/mm/transparent_hugepage/defrag

    # 1. check "sysctl -a" output
    local _props="vm.zone_reclaim_mode vm.swappiness vm.dirty_ratio vm.dirty_background_ratio kernel.shmmax vm.oom_dump_tasks net.core.somaxconn net.core.netdev_max_backlog net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.ipv4.ip_local_port_range net.ipv4.tcp_mtu_probing net.ipv4.tcp_fin_timeout net.ipv4.conf.*.forwarding"

    _search_properties "${_conf%/}" "${_props}"
}

function f_hdfs_checklist() {
    local __doc__="Store HDFS config checklist in this function"
    local _conf="${1-./}"

    # 1. check the following properties' values
    local _props="dfs.namenode.audit.log.async dfs.namenode.servicerpc-address dfs.namenode.handler.count dfs.namenode.service.handler.count dfs.namenode.lifeline.rpc-address ipc.[0-9]+.backoff.enable ipc.[0-9]+.callqueue.impl dfs.namenode.name.dir< dfs.journalnode.edits.dir dfs.namenode.accesstime.precision"

    _search_properties "${_conf%/}/*-site.xml" "${_props}" "Y"

    # 2. Check log4j config for performance
    ggrep -E '^log4j\..+\.(BlockStateChange|StateChange)' ${_conf%/}/log4j.properties
}

function f_hive_checklist() {
    local __doc__="Store Hive config checklist in this function"
    local _conf="${1-./}"   # set / set -v output or hive-site.xml
    local _others="$2"      # check HDFS, YARN, MR2 configs if 'y'

    # 1. check the following properties' values
    # ggrep -ohE '\(property\(.+$' * | cut -d '"' -f 2 | tr '\n' ' '

    echo "# Hive config check" >&2
    local _props="hive.auto.convert.join hive.merge.mapfiles hive.merge.mapredfiles hive.exec.compress.intermediate hive.exec.compress.output datanucleus.cache.level2.type hive.default.fileformat.managed hive.default.fileformat fs.hdfs.impl.disable.cache fs.file.impl.disable.cache hive.cbo.enable hive.compute.query.using.stats hive.stats.fetch.column.stats hive.stats.fetch.partition.stats hive.execution.engine datanucleus.fixedDatastore hive.exim.strict.repl.tables datanucleus.autoCreateSchema hive.exec.parallel hive.plan.serialization.format hive.server2.tez.initialize.default.sessions hive.vectorized.execution.enabled hive.vectorized.execution.reduce.enabled"
    _search_properties "${_conf%/}" "${_props}"

    echo -e "\n# Tez config check" >&2
    _props="tez.am.am-rm.heartbeat.interval-ms.max tez.runtime.transfer.data-via-events.enabled tez.session.am.dag.submit.timeout.secs tez.am.container.reuse.enabled tez.runtime.io.sort.mb tez.session.client.timeout.secs tez.runtime.shuffle.memory-to-memory.enable tez.runtime.task.input.post-merge.buffer.percent tez.am.container.session.delay-allocation-millis tez.session.am.dag.submit.timeout.secs tez.runtime.shuffle.fetch.buffer.percent tez.task.am.heartbeat.interval-ms.max tez.task.am.heartbeat.counter.interval-ms.max tez.task.get-task.sleep.interval-ms.max tez.task.scale.memory.enabled"
    _search_properties "${_conf%/}" "${_props}"

    echo -e "\n# Hive extra config check" >&2
    _props="hive.metastore.client.connect.retry.delay hive.metastore.client.connect.retry.delay hive.metastore.failure.retries hive\..*aux.jars.path hive.server2.async.exec.threads hive\.server2\..*\.threads hive.tez.java.opts hive.server2.idle.session.check.operation hive.server2.session.check.interval hive.server2.idle.session.timeout hive.server2.idle.operation.timeout tez.session.am.dag.submit.timeout.secs tez.yarn.ats.event.flush.timeout.millis hive.llap.* fs.permissions.umask-mode"
    _search_properties "${_conf%/}" "${_props}"

    # 2. Extra properties from set output
    echo -e "\n# hadoop common (mainly from core-site.xml and set -v required)" >&2
    _props="hadoop\.proxyuser\..* hadoop\.ssl\..* hadoop\.http\.authentication\..* ipc\.client\..*"
    _search_properties "${_conf%/}" "${_props}"

    if [[ "$_others" =~ (^y|^Y) ]]; then
        echo -e "\n# HDFS config check" >&2
        _props="hdfs.audit.logger dfs.block.access.token.enable dfs.blocksize dfs.namenode.checkpoint.period dfs.datanode.failed.volumes.tolerated dfs.datanode.max.transfer.threads dfs.permissions.enabled hadoop.security.group.mapping fs.defaultFS dfs.namenode.accesstime.precision dfs.ha.automatic-failover.enabled dfs.namenode.checkpoint.txns dfs.namenode.stale.datanode.interval dfs.namenode.name.dir dfs.namenode.handler.count dfs.namenode.metrics.logger.period.seconds dfs.namenode.name.dir dfs.namenode.top.enabled fs.protected.directories dfs.replication dfs.namenode.name.dir.restore dfs.namenode.safemode.threshold-pct dfs.namenode.avoid.read.stale.datanode dfs.namenode.avoid.write.stale.datanode dfs.replication dfs.client.block.write.replace-datanode-on-failure.enable dfs.client.block.write.replace-datanode-on-failure.policy dfs.client.block.write.replace-datanode-on-failure.best-effort dfs.datanode.du.reserved hadoop.security.logger dfs.client.read.shortcircuit dfs.domain.socket.path fs.trash.interval ha.zookeeper.acl ha.health-monitor.rpc-timeout.ms dfs.namenode.replication.work.multiplier.per.iteration"
        _search_properties "${_conf%/}" "${_props}"

        echo -e "\n# YARN config check" >&2
        _props="yarn.timeline-service.generic-application-history.save-non-am-container-meta-info yarn.timeline-service.enabled hadoop.security.authentication yarn.timeline-service.http-authentication.type yarn.timeline-service.store-class yarn.timeline-service.ttl-enable yarn.timeline-service.ttl-ms yarn.acl.enable yarn.log-aggregation-enable yarn.nodemanager.recovery.enabled yarn.resourcemanager.recovery.enabled yarn.resourcemanager.work-preserving-recovery.enabled yarn.nodemanager.local-dirs yarn.nodemanager.log-dirs yarn.nodemanager.resource.cpu-vcores yarn.nodemanager.vmem-pmem-ratio"
        _search_properties "${_conf%/}" "${_props}"

        echo -e "\n# MR config check" >&2
        _props="mapreduce.map.output.compress mapreduce.output.fileoutputformat.compress io.sort.factor mapreduce.task.io.sort.mb mapreduce.map.sort.spill.percent mapreduce.map.speculative mapreduce.input.fileinputformat.split.maxsize mapreduce.input.fileinputformat.split.minsize mapreduce.reduce.shuffle.parallelcopies mapreduce.reduce.speculative mapreduce.job.reduce.slowstart.completedmaps mapreduce.tasktracker.group"
        _search_properties "${_conf%/}" "${_props}"
    fi

    # 3. Extra properties from set output
    if [ -f "$_conf" ]; then
        echo -e "\n# System:java" >&2
        # |system:java\.class\.path
        ggrep -E '^(env:HOSTNAME|env:HADOOP_HEAPSIZE|env:HADOOP_CLIENT_OPTS|system:hdp\.version|system:java\.home|system:java\.vm\.*|system:java\.io\.tmpdir|system:os\.version|system:user\.timezone)=' "$_conf"
    fi
}

function _search_properties() {
    local _path="${1-./}"
    local _props="$2" # space separated regex
    local _is_name_value_xml="$3"

    for _p in ${_props}; do
        if [[ "${_is_name_value_xml}" =~ (^y|^Y) ]]; then
            local _out="`ggrep -Pzo "(?s)<name>${_p}</name>.+?</value>" ${_path}`"
            [[ "${_out}" =~ (<value>)(.*)(</value>) ]]
            echo "${_p}=${BASH_REMATCH[2]}"
        else
            # Expecting hive 'set' command output or similar style (prop=value)
            ggrep -P "${_p}" ${_path}
        fi
    done
}

function f_load_ambaridb() {
    local __doc__="Load ambari DB sql file into Mac's PostgreSQL DB"
    local _sql_file="$1"
    local _missing_tables_sql="$2"
    local _sudo_user="${3-$USER}"
    local _ambari_pwd="${4-bigdata}"

    # If a few tables are missing, need missing tables' schema
    # pg_dump -Uambari -h `hostname -f` ambari -s -t alert_history -t host_role_command -t execution_command -t stage -t request > ambari_missing_table_ddl.sql

    #psql template1 -c 'DROP DATABASE ambari;'
    sudo -u ${_sudo_user} -i psql template1 -c 'ALTER DATABASE ambari RENAME TO ambari_'$(date +"%Y%m%d%H%M%S")';'
    sudo -u ${_sudo_user} -i psql template1 -c 'CREATE DATABASE ambari;'
    sudo -u ${_sudo_user} -i psql template1 -c "CREATE USER ambari WITH LOGIN PASSWORD '${_ambari_pwd}';"
    sudo -u ${_sudo_user} -i psql template1 -c 'GRANT ALL PRIVILEGES ON DATABASE ambari TO ambari;'

    export PGPASSWORD="${_ambari_pwd}"
    psql -Uambari -h `hostname -f` ambari -c 'CREATE SCHEMA ambari;ALTER SCHEMA ambari OWNER TO ambari;';
    # It's OK to see relation error for index (TODO: upgrade table may fail)
    [ -s "$_missing_tables_sql" ] && psql -Uambari -h `hostname -f` ambari < ${_missing_tables_sql}
    psql -Uambari -h `hostname -f` ambari < ${_sql_file}
    [ -s "$_missing_tables_sql" ] && psql -Uambari -h `hostname -f` ambari < ${_missing_tables_sql}
    psql -Uambari -h `hostname -f` -c "UPDATE users SET user_password='538916f8943ec225d97a9a86a2c6ec0818c1cd400e09e03b660fdaaec4af29ddbb6f2b1033b81b00' WHERE user_name='admin' and user_type='LOCAL';"
    psql -Uambari -h `hostname -f` -c "select * from metainfo where metainfo_key = 'version';"
    psql -Uambari -h `hostname -f` -c "SELECT * FROM clusters WHERE security_type = 'KERBEROS';"
    #UPDATE clusters SET security_type = 'NONE' WHERE provisioning_state = 'INSTALLED';
    #curl -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X DELETE "${_api_uri}/services/KERBEROS" &>/dev/null
    #curl -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X DELETE "${_api_uri}/artifacts/kerberos_descriptor" &>/dev/null
    unset PGPASSWORD
}

### Private functions ##################################################################################################

function _split() {
    local _rtn_var_name="$1"
    local _string="$2"
    local _delimiter="${3-,}"
    local _original_IFS="$IFS"
    eval "IFS=\"$_delimiter\" read -a $_rtn_var_name <<< \"$_string\""
    IFS="$_original_IFS"
}

function _getAfterFirstMatch() {
    local _file_path="$1"
    local _start_regex="$2"
    local _end_regex="$3"

    local _start_line_num=`ggrep -m1 -nP "$_start_regex" "$_file_path" | cut -d ":" -f 1`
    if [ -n "$_start_line_num" ]; then
        local _end_line_num=""
        if [ -n "$_end_regex" ]; then
            #gsed -n "${_start_line_num},\$s/${_end_regex}/&/p" "$_file_path"
            _end_line_num=`tail -n +${_start_line_num} "$_file_path" | ggrep -m1 -nP "$_end_regex" | cut -d ":" -f 1`
            _end_line_num=$(( $_end_line_num + $_start_line_num - 1 ))
        fi
        if [ -n "$_end_line_num" ]; then
            gsed -n "${_start_line_num},${_end_line_num}p" "${_file_path}"
        else
            gsed -n "${_start_line_num},\$p" "${_file_path}"
        fi
    fi
}

### Help ###############################################################################################################

list() {
    local _name="$1"
    #local _width=$(( $(tput cols) - 2 ))
    local _tmp_txt=""
    # TODO: restore to original posix value
    set -o posix

    if [[ -z "$_name" ]]; then
        (for _f in `typeset -F | ggrep -E '^declare -f [fp]_' | cut -d' ' -f3`; do
            #eval "echo \"--[ $_f ]\" | gsed -e :a -e 's/^.\{1,${_width}\}$/&-/;ta'"
            _tmp_txt="`help "$_f" "Y"`"
            printf "%-28s%s\n" "$_f" "$_tmp_txt"
        done)
    elif [[ "$_name" =~ ^func ]]; then
        typeset -F | ggrep '^declare -f [fp]_' | cut -d' ' -f3
    elif [[ "$_name" =~ ^glob ]]; then
        set | ggrep ^[g]_
    elif [[ "$_name" =~ ^resp ]]; then
        set | ggrep ^[r]_
    fi
}
help() {
    local _function_name="$1"
    local _doc_only="$2"

    if [ -z "$_function_name" ]; then
        echo "help <function name>"
        echo ""
        list "func"
        echo ""
        return
    fi

    if [[ "$_function_name" =~ ^[fp]_ ]]; then
        local _code="$(type $_function_name 2>/dev/null | ggrep -v "^${_function_name} is a function")"
        if [ -z "$_code" ]; then
            echo "Function name '$_function_name' does not exist."
            return 1
        fi

        local _eval="$(echo -e "${_code}" | awk '/__doc__=/,/;/')"
        eval "$_eval"

        if [ -z "$__doc__" ]; then
            echo "No help information in function name '$_function_name'."
        else
            echo -e "$__doc__"
            [[ "$_doc_only" =~ (^y|^Y) ]] && return
        fi

        local _params="$(type $_function_name 2>/dev/null | ggrep -iP '^\s*local _[^_].*?=.*?\$\{?[1-9]' | ggrep -v awk)"
        if [ -n "$_params" ]; then
            echo "Parameters:"
            echo -e "$_params
            "
            echo ""
        fi
    else
        echo "Unsupported Function name '$_function_name'."
        return 1
    fi
}

### Global variables ###################################################################################################
# TODO: Not using at this moment
_IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
_IP_RANGE_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(/[0-3]?[0-9])?$'
_HOSTNAME_REGEX='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
_URL_REGEX='(https?|ftp|file|svn)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'
_TEST_REGEX='^\[.+\]$'
[ -z "$_DATE_FORMAT" ] && _DATE_FORMAT="\d\d\d\d-\d\d-\d\d"

### Main ###############################################################################################################

if [ "$0" = "$BASH_SOURCE" ]; then
    # parsing command options
    while getopts "f:s:e:t:h" opts; do
        case $opts in
            f)
                _FILE_PATH="$OPTARG"
                ;;
            s)
                _START_DATE="$OPTARG"
                ;;
            e)
                _END_DATE="$OPTARG"
                ;;
            t)
                _LOG_TYPE="$OPTARG"
                ;;
            h)
                usage | less
                exit 0
        esac
    done

    if [ -z "$_FILE_PATH" ]; then
        usage
        exit
    fi

    if [ ! -s "$_FILE_PATH" ]; then
        echo "$_FILE_PATH is not a right file. (-h for help)"
        exit 1
    fi

    _file_path="$_FILE_PATH"
    if [ -n "$_START_DATE" ]; then
        echo "# Extracting $_START_DATE $_END_DATE into a temp file ..." >&2
        f_extractByDates "$_FILE_PATH" "$_START_DATE" "$_END_DATE" > /tmp/_f_extractByDates_$$.out
        _file_path="/tmp/_f_extractByDates_$$.out"
    fi
    echo "# Running f_topErrors $_file_path ..." >&2
    f_topErrors "$_file_path" "Y" > /tmp/_f_topErrors_$$.out &
    echo "# Running f_topCausedByExceptions $_file_path ..." >&2
    f_topCausedByExceptions "$_file_path" > /tmp/_f_topCausedByExceptions_$$.out &
    echo "# Running f_topSlowLogs $_file_path ..." >&2
    f_topSlowLogs "$_file_path" > /tmp/_f_topSlowLogs_$$.out &
    if [ "$_LOG_TYPE" != "ya" ]; then
        echo "# Running f_hdfsAuditLogCountPerTime $_file_path ..." >&2
        f_hdfsAuditLogCountPerTime "$_file_path" > /tmp/_f_hdfsAuditLogCountPerTime_$$.out &
    fi
    wait

    echo "" >&2
    echo "============================================================================" >&2
    echo "# f_topErrors (top 40)"
    cat /tmp/_f_topErrors_$$.out | tail -n 40
    echo ""
    echo "# f_topCausedByExceptions (top 40)"
    cat /tmp/_f_topCausedByExceptions_$$.out | tail -n 40
    echo ""
    echo "# f_topSlowLogs (top 40)"
    cat /tmp/_f_topSlowLogs_$$.out | tail -n 40
    echo ""
    if [ "$_LOG_TYPE" != "ya" ]; then
        echo "# f_hdfsAuditLogCountPerTime (last 48 lines)"
        cat /tmp/_f_hdfsAuditLogCountPerTime_$$.out | tail -n 48
        echo ""
    fi

    # if app log, run f_appLogxxxxx
    if [ "$_LOG_TYPE" = "ya" ]; then
        echo "# f_appLogContainersAndHosts"
        f_appLogContainersAndHosts "$_file_path" "Y"
        echo ""
        echo "# f_appLogJobCounters"
        f_appLogJobCounters "$_file_path"
        echo ""
    fi
fi