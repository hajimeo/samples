#!/usr/bin/env bash
#
# Bunch of grep functions to search log files
# Don't use complex one, so that each function can be easily copied and pasted
#
# DOWNLOAD:
#   curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/log_search.sh
#
# TODO: tested on Mac only (eg: sed -E, ggrep)
# brew install grep     # 'grep' will install ggrep
# brew install gnu-sed  # for gsed
# brew install dateutils # for dateconv
# brew install coreutils # for gtac gdate
# curl https://raw.githubusercontent.com/hajimeo/samples/master/python/line_parser.py -o /usr/local/bin/line_parser.py
#

[ -n "$_DEBUG" ] && (set -x; set -e)

usage() {
    echo "HELP/USAGE:"
    echo "This script contains useful functions to search log files.

How to use: source, then use some function
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
    _list
}
### Public functions ###################################################################################################

function p_support() {
    local __doc__="Scan a support bundle"

    echo "#[$(date +"%H:%M:%S")] Version information"
    echo "## version files (versions.*.yml or build.yaml)"
    find . -type f -name 'versions.*.yml' -print | sort | tee /tmp/versions_$$.out
    local _versions_yaml="`cat /tmp/versions_$$.out | sort -n | tail -n1`"
    if [ -s "${_versions_yaml}" ]; then
        echo " "
        echo "## ${_versions_yaml}"
        cat "${_versions_yaml}"
        echo " "
    else
        _find_and_cat "build.yaml"
    fi
    echo " "

    echo "#[$(date +"%H:%M:%S")] config-custom.yaml (may not exist in older version)"
    _find_and_cat "config-custom.yaml" | sort | uniq
    echo " "
    echo " "

    echo "#[$(date +"%H:%M:%S")] config.yaml (filtered)"
    _find_and_cat "config.yaml" | grep -E '(^AS_LOG_DIR|^HOSTNAME|^JAVA_HOME|^user.timezone|^estimator.enabled|^query.result.max_rows|^thrifty.client.protocol|^aggregates.create.invalidateMetadataOnAllSubgroups|^aggregates\..+\.buildFromExisting|^jobs.aggregates.maintainer|^authorization.impersonation.jdbc.enabled)' | sort | uniq
    echo " "
    f_genKinit
    echo " "

    echo "#[$(date +"%H:%M:%S")] runtime.yaml (usedMem = totalMemory() - freeMemory())"
    _find_and_cat "runtime.yaml"
    echo " "
    echo " "

    echo "#[$(date +"%H:%M:%S")] settings.json last 3 settings changes"
    _find_and_cat "settings.json" | python -c "import sys,json;a=json.loads(sys.stdin.read());print json.dumps(a[-3:], indent=4)"
    echo " "
    echo " "

    echo "#[$(date +"%H:%M:%S")] engine/aggregates/config.json last 3 settings changes"
    _find_and_cat "config.json" | python -c "import sys,json;a=json.loads(sys.stdin.read());print json.dumps(a[-3:], indent=4)"
    echo " "
    echo " "

    #echo "#[$(date +"%H:%M:%S")] config.yaml | grep -iE '(max|size|pool).+000$' | grep -vi 'time'"
    # Exact config parameter(s) which might cause issue
    # TODO: Aggregate Batch <UUID> failed creating a build order for rebuilding aggregates.
    # TODO: aggregates.maxExternalRequestDuration.timeout|aggregates.batch.buildFromExisting'
    # Try finding parameters which value might be too big
    #_find_and_cat "config.yaml" | grep -iE '(max|size|pool).+(000|mins|hours)$' | grep -vi "time"
    #echo " "
    #echo " "

    echo "#[$(date +"%H:%M:%S")] Connection group (warehouse -> sql engine)"
    _find_and_cat "connection_groups.json" | python -m json.tool
    echo "#[$(date +"%H:%M:%S")] Connection pool (sql engine)"
    _find_and_cat "pool.json"   # check maxConnections, consecutiveFailures
    echo " "
    echo " "

    echo "#[$(date +"%H:%M:%S")] akka_cluster_state.json and zkState.json To check HA"
    _find_and_cat "akka_cluster_state.json"
    _find_and_cat "zkState.json"
    echo " "
    echo " "

    # TODO: ./engine/cron-scheduler/jobHistories.json, ./account/account_audit_stream.json

    #echo "#[$(date +"%H:%M:%S")] current-status.json Cache status"
    #_find_and_cat "current-status.json"
    #echo " "
    #echo " "

    #echo "#[$(date +"%H:%M:%S")] properties.json Engine properties for last 20 lines"
    #_find_and_cat "properties.json" | tail -n 20
    #echo " "
    #echo " "

    echo "#[$(date +"%H:%M:%S")] directory_configurations.json"
    _find_and_cat "directory_configurations.json"
    echo " "
    echo " "
    f_genLdapsearch
    echo " "
    echo " "

    echo "#[$(date +"%H:%M:%S")] tableSizes.tsv 10 large tables (by num rows)"
    _find_and_cat "tableSizes.tsv" | sort -n -k2 | tail -n 10
    echo "* Number of tables: "$(_find_and_cat "tableSizes.tsv" | wc -l | tr -d '[:space:]')
    echo "* Number of 0 tbls: "$(_find_and_cat "tableSizes.tsv" | grep -w 0 -c)
    echo " "

    echo "#[$(date +"%H:%M:%S")] Engine start/restart"
    rg -z -N --no-filename -g 'engine.*log*' '(AtScale Engine, shutting down|Shutting down akka system|actor system shut down|[0-9.]+ startup complete)' | sort | uniq | tail
    echo " "
    echo "#[$(date +"%H:%M:%S")] supervisord 'engine entered RUNNING state' (NOTE: time is probably not UTC)"
    rg -z -N --no-filename -g 'atscale_service.log' 'engine entered RUNNING state' | tail -n 10
    echo " "
    echo "#[$(date +"%H:%M:%S")] supervisord 'not expected' (NOTE: time is probably not UTC)"
    rg -z -N --no-filename -g 'atscale_service.log' 'not expected' | tail -n 10

    echo " "
    echo "#[$(date +"%H:%M:%S")] OutOfMemoryError count in all logs"
    rg -z -c 'OutOfMemoryError'
    echo " "
    echo "#[$(date +"%H:%M:%S")] Last 10 OutOfMemoryError in engine logs"
    rg -z -N --no-filename 'OutOfMemoryError' -g 'engine.*log*' -B 1 | rg "^$_DATE_FORMAT" | sort | uniq | tail -n 10

    echo " "
    echo "#[$(date +"%H:%M:%S")] Last 10 'Thread starvation or clock leap detected' engine logs"
    rg -z -N --no-filename "^${_DATE_FORMAT}.+(Thread starvation or clock leap detected|Scheduled sending of heartbeat was delayed)" -g 'engine.*log*' | sort | uniq | tail -n 10
    echo " "
    echo "#[$(date +"%H:%M:%S")] Last 10 'Marshalled xxxxxxxxx characters of SOAP data in yyy s'"
    rg -z -N --no-filename "^${_DATE_FORMAT}.+ Marshalled \d\d\d\d\d\d\d\d+ characters of SOAP data" -g 'engine.*log*' | sort | uniq | tail -n 10
    echo " "
    echo "#[$(date +"%H:%M:%S")] Last 10 'WARN fsync-ing the write ahead log'"
    rg -z -N --no-filename "^${_DATE_FORMAT}.+ WARN.+fsync-ing the write ahead log" -g 'coordinator.*stdout*' | sort | uniq | tail -n 10

    echo " "
    echo "#[$(date +"%H:%M:%S")] Count thread types from periodic.log"
    rg -g 'periodic.log' '^"' -A 1 --no-filename | rg '^  ' | sort | uniq -c

    echo " "
    echo "#[$(date +"%H:%M:%S")] WARNs (and above) in warn.log (top 40)"
    f_listWarns "warn.log"

    echo " "
    echo "#[$(date +"%H:%M:%S")] debug.*log* start and end (start time, end time, difference(sec), filesize)"
    f_list_start_end "debug.*log*"
}

function p_performance() {
    local _glob="${1-"engine.*log*"}"   # eg: "engine.2018-11-27*log*". Empty means using default of each function.
    local _YYYY_MM_DD_hh_m_regex="${2}" # eg: "2018-11-26 1[01]:\d". Can't use () as it will change the order of rg -o -r
    local _num_cpu="${3}"               # if empty, use half of CPUs
    local _n="${4:-20}"

    if [ -n "${_glob}" ]; then
        # for f_checkMaterializeWorkers
        local _tmp_glog="`echo ${_glob} | _sed 's/engine/debug/'`"  # TODO: not best way as 'warn' doesn't work
    fi

    if [ -z "${_num_cpu}" ]; then
        local _divider=2
        #[[ "${_exclude_slow_funcs}" =~ ^(y|Y) ]] && _divider=3
        if [ -e /proc/cpuinfo ]; then
            _num_cpu=$(( `grep -c ^processor /proc/cpuinfo` / ${_divider} ))
        else
            _num_cpu=$(( `sysctl -n hw.ncpu` / ${_divider} ))
        fi
        [ 2 -gt ${_num_cpu:-0} ] && _num_cpu=2
    fi

    # Prepare command list for _mexec (but as rg is already multi-threading, not much diff)
    > /tmp/perform_cmds.tmp || return $?
    cat << EOF > /tmp/perform_cmds.tmp
f_topSlowLogs "^${_YYYY_MM_DD_hh_m_regex}" "${_glob}" "" "" "${_n}"                           > /tmp/perform_f_topSlowLogs_$$.out
f_topErrors "${_glob}" "${_YYYY_MM_DD_hh_m_regex}" "" "" "${_n}"                              > /tmp/perform_f_topErrors_$$.out
f_checkResultSize "${_YYYY_MM_DD_hh_m_regex}" "${_glob}" "${_n}"                              > /tmp/perform_f_checkResultSize_$$.out
f_checkMaterializeWorkers "${_YYYY_MM_DD_hh_m_regex}" "${_tmp_glog}" "${_n}"                              > /tmp/perform_f_checkMaterializeWorkers_$$.out
f_failedQueries "${_YYYY_MM_DD_hh_m_regex}" "${_glob}" "${_n}"                                > /tmp/perform_f_failedQueries_$$.out
f_preCheckoutDuration "${_YYYY_MM_DD_hh_m_regex}" "${_glob}" ${_n}                            > /tmp/perform_f_preCheckoutDuration_$$.out
f_aggBatchKickoffSize "${_YYYY_MM_DD_hh_m_regex}" "${_glob}" ${_n}                            > /tmp/perform_f_aggBatchKickoffSize_$$.out
EOF
    if [ -z "${_YYYY_MM_DD_hh_m_regex}" ]; then
        cat << EOF >> /tmp/perform_cmds.tmp
f_count_lines                                                                      > /tmp/perform_f_count_lines_$$.out
f_count_threads "" "${_n}"                                                         > /tmp/perform_f_count_threads_$$.out
f_count_threads_per_dump                                                           > /tmp/perform_f_count_threads_per_dump_$$.out
EOF
    fi
    _mexec /tmp/perform_cmds.tmp "source $BASH_SOURCE;" "" "${_num_cpu}"

    echo "# f_checkResultSize success query size from the engine log (datetime, queryId, size, time)"
    cat /tmp/perform_f_checkResultSize_$$.out
    echo " "

    echo "# f_failedQueries failed queries from the engine log (datetime, queryId, time) and top ${_n}"
    cat /tmp/perform_f_failedQueries_$$.out
    echo " "

    echo "# f_checkMaterializeWorkers Materialization queue size from the engine debug log"
    cat /tmp/perform_f_checkMaterializeWorkers_$$.out
    echo " "

    echo "# f_preCheckoutDuration from the engine debug log (datetime, statement duration, test duration) and top ${_n}"
    cat /tmp/perform_f_preCheckoutDuration_$$.out
    echo " "

    echo "# f_aggBatchKickoffSize from the engine debug log (datetime, batchId, how many, isFullBuild) and top ${_n}"
    cat /tmp/perform_f_aggBatchKickoffSize_$$.out
    echo " "

    echo "# f_count_lines"
    cat /tmp/perform_f_count_lines_$$.out
    echo "# f_count_threads against the last periodic.log for top ${_n}"
    cat /tmp/perform_f_count_threads_$$.out
    echo "# Also, executed 'f_count_threads_per_dump > /tmp/perform_f_count_threads_per_dump_$$.out'"
    echo " "

    local _tmp_date_regex="${_DATE_FORMAT}.${_TIME_FMT4CHART}?"
    [ -n "${_YYYY_MM_DD_hh_m_regex}" ] && _tmp_date_regex="${_YYYY_MM_DD_hh_m_regex}"

    # TODO: 2019-01-16 19:36:12,701 DEBUG [atscale-akka.actor.connection-pool-154790] {...} com.atscale.engine.connection.pool.ConnectionManagerActor - Current state:
    echo "# Connection pool failures per hour"
    # Didn't find a request to serve
    rg -N --no-filename -z -g "${_glob}" -i "^(${_tmp_date_regex}).+(Likely the pool is at capacity|failed to find free connection|Could not establish a JDBC|Cannot connect to subgroup|Could not create ConnectionManagerActor|No connections available|No free connections|Could not satisfy request|Connection warming failure for|Connection test failure|had failures. Will process queue again in)" -o -r '$1 $2' | sort | uniq -c | tail -n ${_n}
    echo " "

    rg -N --no-filename -z -g "${_glob}" "^${_tmp_date_regex}.+took \[[0-9.]+ [^]]+\] to begin execution" | sort | uniq > /tmp/took_X_to_begin_$$.out
    echo "# Took [X *ks*] to begin execution"
    rg -N "^${_tmp_date_regex}.+took \[[1-9][0-9.]+ ks\] to begin execution" /tmp/took_X_to_begin_$$.out
    echo " "

    echo "# 'Took [X s] to begin execution' milliseconds"
    rg -N "^(${_tmp_date_regex}).+took \[([1-9][0-9.]+) (s|ks)\] to begin execution" -o -r '$1 $2' /tmp/took_X_to_begin_$$.out | awk '{print $1"T"$2" "($3*1000)}' | bar_chart.py -A
    echo " "

    echo "# 'Ending QueryActor'"
    rg -N --no-filename -z -g "${_glob}" "^${_tmp_date_regex}.+Ending QueryActor" | sort | uniq
    echo " "

    echo "# count 'Took [X s] to begin execution' occurrence"
    rg -N "^${_tmp_date_regex}" -o /tmp/took_X_to_begin_$$.out | sort | uniq -c | sort | tail -n ${_n}
    echo " "

    echo "# Counting 'Getting LDAP user completed after X s' (seconds and higher only)"
    rg -N --no-filename -z -g "${_glob}" "^(${_tmp_date_regex}).+ Getting LDAP user completed after ([0-9.]+) (s|ks)" -o -r '$1' | awk '{print $1"T"$2" 1"}' | bar_chart.py -A
    echo " "
    rg -N --no-filename -z -g "${_glob}" "^(${_tmp_date_regex}).+ Getting LDAP user completed after ([0-9.]+) (s|ks)" -o -r '$1 $2 $3' | awk '{if ($4=="ks") s=$3*1000; else s=$3; print $1" "$2" "$3" s"}' | sort -nk2 | tail -n${_n}
    echo " "

    echo "# f_topSlowLogs from engine *debug* log if no _glob, and top ${_n}"
    cat /tmp/perform_f_topSlowLogs_$$.out
    echo " "

    echo "# f_topErrors from engine log and top ${_n}"
    cat /tmp/perform_f_topErrors_$$.out
    echo " "
    # TODO: hiveserver2.log Total time spent in this metastore function was greater than
}

function f_checkResultSize() {
    local __doc__="Get result sizes from the engine debug log (datetime, queryId, size, time)"
    local _date_regex="${1}"    # No need ^
    local _glob="${2:-engine.*log*}"
    local _n="${3:-20}"
    [ -z "${_date_regex}" ] && _date_regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d,\d+"

    rg -z -N --no-filename -g "${_glob}" -i -o "^(${_date_regex}).+ queryId=(........-....-....-....-............).+QuerySucceededEvent.+, size = ([^,]+), time = ([^,]+)," -r '${1}|${2}|${3}|${4}' | sort -n | uniq > /tmp/f_checkResultSize_$$.out
    echo "### histogram (time vs query result size) #################################################"
    rg -z -N --no-filename "^(${_DATE_FORMAT}).(${_TIME_FMT4CHART}?).*\|([^|]+)\|([^|]+)\|([^|]+)" -r '${1}T${2} ${4}' /tmp/f_checkResultSize_$$.out | bar_chart.py -A
    echo ' '
    echo "### histogram (time vs query requests) ####################################################"
    rg -z -N --no-filename "^(${_DATE_FORMAT}).(${_TIME_FMT4CHART}?).*\|([^|]+)\|([^|]+)\|([^|]+)" -r '${1}T${2}' /tmp/f_checkResultSize_$$.out | bar_chart.py
    echo ' '
    echo "### Large size (datetime|queryId|size|time) ###############################################"
    cat /tmp/f_checkResultSize_$$.out | sort -t '|' -nk3 | tail -n${_n} | tr '|' '\t'
    echo ' '
    echo "### Slow query (datetime|queryId|size|time) ###############################################"
    (cat /tmp/f_checkResultSize_$$.out | grep ' s$' | sort -t '|' -nk4; cat /tmp/f_checkResultSize_$$.out | grep ' ks$' | sort -t '|' -nk4) | tail -n${_n} | tr '|' '\t'
    echo " "
    ls -lh /tmp/f_checkResultSize_$$.out
}

function f_checkMaterializeWorkers() {
    local __doc__="Check Materialization worker size (datetime, size)"
    local _date_regex="${1}"    # No need ^
    local _glob="${2:-debug*.log*}" # As TRACE log, needs debug log
    local _n="${3:-20}"
    [ -z "${_date_regex}" ] && _date_regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d,\d+"
    # aggregates.configuration.maximum_concurrent_materializations.default = 1 or atscale.atscale.aggregate_configurations table
    local _waiting="$(rg -z -N --no-filename -g "${_glob}" -i -o "^(${_date_regex}).+TRACE .+ No workers available for request, adding to queue of size (\d+)" -r '${1}|${2}')"
    local _working="$(rg -z -N --no-filename -g "${_glob}" -i -o "^(${_date_regex}).+TRACE .+ Worker .+ is available to handle request" -r '${1}|-1')"
    ( echo  "${_waiting}"; echo "${_working}" ) | awk -F"|" '{print $1"|"$2+1}' | sort -n > /tmp/f_checkMaterializeWorkers_$$.out
    # Shouldn't accumulate queue size (need windowing...)
    echo "### histogram (time vs worker queue (waiting) size) #######################################"
    rg -z -N --no-filename "^(${_DATE_FORMAT}).(${_TIME_FMT4CHART}?).*\|([^|]+)" -r '${1}T${2} ${3}' /tmp/f_checkMaterializeWorkers_$$.out | sort -n | uniq  | sort -k1,1r -k2,2nr > /tmp/f_checkMaterializeWorkers_filtered_$$.out
    for _dt in `cat /tmp/f_checkMaterializeWorkers_filtered_$$.out | cut -d" " -f1 | sort -n | uniq`; do
        grep -m 1 "^${_dt}" /tmp/f_checkMaterializeWorkers_filtered_$$.out
    done | bar_chart.py -A
    echo ' '
    echo "### histogram (time vs materialize request count) #########################################"
    rg -z -N --no-filename "^(${_DATE_FORMAT}).(${_TIME_FMT4CHART}?).*\|([^|]+)" -r '${1}T${2}' /tmp/f_checkMaterializeWorkers_$$.out | bar_chart.py
    echo ' '
    echo "### Large materialize queue size (datetime|size) ##########################################"
    cat /tmp/f_checkMaterializeWorkers_$$.out | grep -v '|0$' | sort -t '|' -nk2 | tail -n${_n} | tr '|' '\t'
    echo " "
    ls -lh /tmp/f_checkMaterializeWorkers_$$.out
    # NOTE: to get the queryId: AggregateInstanceMaterializerWorker - Submitted aggregate creation query with ID: [UUID]
}

function f_failedQueries() {
    local __doc__="Get 'Logging query failures' (datetime, queryId, time)"
    local _date_regex="${1}"    # No need ^
    local _glob="${2:-engine.*log*}"
    local _n="${3:-20}"
    [ -z "${_date_regex}" ] && _date_regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d,\d+"

    rg -z -N --no-filename -g "${_glob}" -i -o "^(${_date_regex}).+ queryId=(........-....-....-....-............).+ QueryFailedEvent.+ time = ([^,]+)," -r '${1}|${2}|${3}' | sort -n | uniq > /tmp/f_failedQueries_$$.out
    echo "### histogram (time vs failed query count) ################################################"
    rg -z -N --no-filename "^(${_DATE_FORMAT}).(${_TIME_FMT4CHART}?).*\|([^|]+)\|([^|]+)" -r '${1}T${2}' /tmp/f_failedQueries_$$.out | bar_chart.py
    echo ' '
    echo "### Slow failed query (datetime|queryId|time) #############################################"
    (cat /tmp/f_failedQueries_$$.out | grep ' s$' | sort -t '|' -nk3; cat /tmp/f_failedQueries_$$.out | grep ' ks$' | sort -t '|' -nk3) | tail -n${_n} | tr '|' '\t'
    echo " "
    ls -lh /tmp/f_failedQueries_$$.out
}

function f_preCheckoutDuration() {
    local __doc__="Get 'preCheckout timing report' from the engine debug log (datetime, statement duration, test duration)"
    # f_preCheckoutDuration | sort -t'|' -nk3 | tail -n 10
    local _date_regex="${1}"    # No need ^
    local _glob="${2:-engine.*log*}"
    local _n="${3:-20}"
    [ -z "${_date_regex}" ] && _date_regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d,\d+"

    # NOTE: queryId sometime is not included
    rg -z -N --no-filename -g "${_glob}" -o "^(${_date_regex}).+preCheckout timing report:.+statementDurations=[^=]+=([0-9,.]+) (.+)\].+testDuration=[^=]+=([0-9,.]+) (.+)\]" -r '${1}|${2}${3}|${4}${5}' | _sed -r 's/([0-9]+)\.([0-9]{2})s/\1\20ms/g' > /tmp/f_preCheckoutDuration_$$.out

    cat /tmp/f_preCheckoutDuration_$$.out | sort -t'|' -nk3 | tail -n ${_n}
    echo " "
    ls -lh /tmp/f_preCheckoutDuration_$$.out
}

function f_aggBatchKickoffSize() {
    local __doc__="Check Agg Batch Kick off count from the engine debug log (datetime, batchId, how many, isFullBuild)"
    # f_aggBatchKickoffSize | sort -t'|' -nk3 | tail -n 10
    local _date_regex="${1}"    # No need ^
    local _glob="${2:-engine.*log*}"
    local _n="${3:-20}"
    [ -z "${_date_regex}" ] && _date_regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d,\d+"

    rg -z -N --no-filename -g "${_glob}" -o "^(${_date_regex}).+ Kickoff batch (........-....-....-....-............) with ([0-9,]+) aggregate\(s\) and isFullBuild (.+)" -r '${1}|${2}|${3}|${4}' | sort > /tmp/f_aggBatchKickoffSize_$$.out

    rg -z -N --no-filename -g "${_glob}" -o "^(${_date_regex}).+WARN.+ Aggregate Batch.+(........-....-....-....-............).+failed with error message" -r '${1}|${2}' | sort > /tmp/f_aggBatchKickoffSize_failed_$$.out

    echo "### histogram (time vs batch aggregate size) ##############################################"
    rg -N --no-filename "^(${_DATE_FORMAT}).(${_TIME_FMT4CHART}?).*\|([^|]+)\|([^|]+)\|([^|]+)" -r '${1}T${2} ${4}' /tmp/f_aggBatchKickoffSize_$$.out | bar_chart.py -A
    echo ' '
    echo "### histogram (time vs batch count) #######################################################"
    rg -N --no-filename "^(${_DATE_FORMAT}).(${_TIME_FMT4CHART}?).*\|([^|]+)\|([^|]+)\|([^|]+)" -r '${1}T${2}' /tmp/f_aggBatchKickoffSize_$$.out | bar_chart.py
    echo ' '
    echo "### histogram (time vs failed batch count) ################################################"
    rg -N --no-filename "^(${_DATE_FORMAT}).(${_TIME_FMT4CHART}?).*\|([^|]+)" -r '${1}T${2}' /tmp/f_aggBatchKickoffSize_failed_$$.out | bar_chart.py
    echo ' '
    echo "### Large size (datetime|batchId|size|full) ###############################################"
    cat /tmp/f_aggBatchKickoffSize_$$.out | sort -t '|' -nk3 | tail -n${_n} | tr '|' '\t'
    echo ' '
}

function f_list_queries() {
    local _date_regex="$1"
    local _glob="${2:-"engine.*log*"}"
    rg -z -N --no-filename "^${_date_regex}.* INFO .+queryId=.+ Received (SQL|Analysis) [Qq]uery" -g "${_glob}" | sort
}

function f_query_plan() {
    local _queryId="$1"
    local _glob="${2:-"debug.*log*"}"
    rg -z -N --no-filename "queryId=${_queryId}.+ Final physical plan.+SqlPlan\((.+)\)" -g "${_glob}" -m 1 -o -r '$1' | pjson 100000000
    # TODO: Query part core physical plan
}

function f_grep_multilines() {
    local __doc__="Multiline search with 'rg'. TODO: dot and brace can't be used in _str_in_1st_line"
    local _str_in_1st_line="$1"         # TODO: At this moment, grep-ing lines which *first* line contain this string
    local _glob="${2:-"debug.*log*"}"
    local _rg_extra_opt="${3-"-A 1 -m 2000"}"   # Accept *empty string*
    local _boundary_str="${4:-"^2\\d\\d\\d-\\d\\d-\\d\\d.\\d\\d:\\d\\d:\\d\\d"}"

    # TODO: if next line also contains the queryId, it won't be included in the output, so using -A 1 at this moment. ("(?!^2\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d)" didn't work)
    local _regex="${_boundary_str}[^\n]+?${_str_in_1st_line}.+?(${_boundary_str}|\z)"
    echo "# regex:${_regex} -g '${_glob}' ${_rg_extra_opt}" >&2
    rg "${_regex}" \
        --multiline --multiline-dotall --no-line-number --no-filename -z \
        -g "${_glob}" ${_rg_extra_opt} --sort=path
    # not sure if rg sorts properly with --sort, so best effort (can not use ' | sort' as multi-lines)
}

function f_genKinit() {
    local __doc__="Generate Kinit command from a config.yaml file"

    _find_and_cat "config.yaml" 2>/dev/null | grep -E '(^user\.name|^kerberos)' | sort | uniq > /tmp/f_genKinit_$$.out
    _load_yaml /tmp/f_genKinit_$$.out "_k_"
    if [ -n "${_k_kerberos_service}" ]; then
        echo "su - ${_k_user_name}"
        if [ -n "${_k_kerberos_host}" ]; then
            echo "kinit -kt ${_k_kerberos_keytab} ${_k_kerberos_service}/${_k_kerberos_host}@${_k_kerberos_domain}"
        else
            echo "kinit -kt ${_k_kerberos_keytab} ${_k_kerberos_service}@${_k_kerberos_domain}"
        fi
    fi
}

function f_genLdapsearch() {
    local __doc__="Generate ldapsearch command from a json file"
    local _json_str="`_find_and_cat "directory_configurations.json" 2>/dev/null`"
    [ -z "${_json_str}" ] && return
    [ "${_json_str}" = "[ ]" ] && return
    echo "${_json_str}" | python -c 'import sys,re,json
a=json.loads(sys.stdin.read());l=a[0]
p="ldaps" if "use_ssl" in l and l["use_ssl"] else "ldap"
r=re.search(r"^[^=]*?=?([^=]+?)[ ,@]", l["username"])
u=r.group(1) if bool(r) else l["username"]
print("LDAPTLS_REQCERT=never ldapsearch -H %s://%s:%s -D \"%s\" -b \"%s\" -W \"(%s=%s)\"" % (p, l["host_name"], l["port"], l["username"], l["base_dn"], l["user_configuration"]["unique_id_attribute"], u))'
}

function f_topCausedByExceptions() {
    local __doc__="List Caused By xxxxException (Requires rg)"
    local _path="$1"
    local _is_shorter="$2"
    local _regex="Caused by.+Exception"

    if [[ "$_is_shorter" =~ (^y|^Y) ]]; then
        _regex="Caused by.+?Exception"
    fi
    rg -z -N -o "$_regex" "$_path" | sort | uniq -c | sort -n
}

function f_topErrors() {
    local __doc__="List top ERRORs. NOTE: with _date_from and without may produce different result (ex: Caused by)"
    local _glob="${1:-"engine.*log*"}"   # file path which rg accepts and NEEDS double-quotes
    local _date_regex="$2"   # ISO format datetime, but no seconds (eg: 2018-11-05 21:00)
    local _regex="$3"       # to overwrite default regex to detect ERRORs
    local _top_N="${4:-10}" # how many result to show

    if ! which rg &>/dev/null; then
        echo "'rg' is required (eg: brew install rg)" >&2
        return 101
    fi

    if [ -z "$_regex" ]; then
        _regex="\b(WARN|ERROR|SEVERE|FATAL|SHUTDOWN|Caused by|.+?Exception|[Ff]ailed)\b.+"
    fi

    if [ -n "${_date_regex}" ]; then
        _regex="^(${_date_regex}).+${_regex}"
    fi

    echo "# Regex = '${_regex}'"
    #rg -z -c -g "${_glob}" "${_regex}"
    rg -z -N --no-filename -g "${_glob}" -o "${_regex}" > /tmp/f_topErrors.$$.tmp

    # just for fun, drawing bar chart
    if [ -n "${_date_regex}" ] && which bar_chart.py &>/dev/null; then
        local _date_regex2="^[0-9-/]+ \d\d:\d"
        [ "`wc -l /tmp/f_topErrors.$$.tmp | awk '{print $1}'`" -lt 400 ] && _date_regex2="^[0-9-/]+ \d\d:\d\d"
        echo ' '
        rg -z --no-line-number --no-filename -o "${_date_regex2}" /tmp/f_topErrors.$$.tmp | sed 's/T/ /' | bar_chart.py
        echo " "
    fi

    cat "/tmp/f_topErrors.$$.tmp" | _replace_number | sort | uniq -c | sort -n | tail -n ${_top_N}
}

function f_listWarns() {
    local __doc__="List the counts of frequent warns and also errors"
    local _glob="${1:-"warn*.log*"}"
    local _date_4_bar="${2:-"\\d\\d\\d\\d-\\d\\d-\\d\\d \\d\\d"}"
    local _top_N="${3:-40}"

    #rg -z -c -g "${_glob}" "${_regex}"
    rg -z --no-line-number --no-filename -g "${_glob}" "^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d (ERROR|FATAL|SEVERE|WARN)" > /tmp/f_listWarns.$$.tmp

    # count by class name and ignoring only once or twice warns
    rg "(ERROR|FATAL|SEVERE|WARN) +\[[^]]+\] \{[^}]*\} ([^ ]+)" -o -r '$1 $2' /tmp/f_listWarns.$$.tmp | _replace_number | sort | uniq -c | sort -n | grep -vE ' +[12] WARN' | tail -n ${_top_N}
    echo " "
    rg -o "^${_date_4_bar}" /tmp/f_listWarns.$$.tmp | bar_chart.py
}

function f_topSlowLogs() {
    local __doc__="List top performance related log entries."
    local _date_regex="$1"
    local _glob="${2:-debug.*log*}"
    local _regex="$3"
    local _not_hiding_number="$4"
    local _top_N="${5:-10}" # how many result to show

    if [ -z "$_regex" ]; then
        _regex="\b(slow|delay|delaying|latency|too many|not sufficient|lock held|took [1-9][0-9]+ ?ms|timeout|timed out|going into queue, is \[...+\] in line|request rejected|Likely the pool is at capacity|failed to find free connection)\b.+"
    fi
    if [ -n "${_date_regex}" ]; then
        _regex="^${_date_regex}.+${_regex}"
    fi

    echo "# Regex = '${_regex}'"
    #rg -z -c -g "${_glob}" -wio "${_regex}"
    if [[ "$_not_hiding_number" =~ (^y|^Y) ]]; then
        rg -z -N --no-filename -g "${_glob}" -io "$_regex" | sort | uniq -c | sort -n
    else
        # ([0-9]){2,4} didn't work also (my note) sed doesn't support \d
        rg -z -N --no-filename -g "${_glob}" -io "$_regex" | _replace_number | sort | uniq -c | sort -n | tail -n ${_top_N}
    fi
}

function f_appLogFindAppMaster() {
    local __doc__="After yarn_app_logs_splitter, find which node was AppMaster. TODO: currently only MR and not showing host"
    local _splitted_dir="${1:-.}"
    rg -l 'Created MRAppMaster' "${_splitted_dir%/}/*.syslog"
}

function f_appLogContainersAndHosts() {
    local __doc__="List containers ID and host (from YARN app log)"
    local _path="$1"
    local _sort_by_host="$2"

    if [[ "$_sort_by_host" =~ (^y|^Y) ]]; then
        _grep "^Container: container_" "$_path" | sort -k4 | uniq
    else
        _grep "^Container: container_" "$_path" | sort | uniq
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

    rg --no-line-number --no-filename -z -o "Final Counters for .+$" "$_path" | while read -r _line ; do
        if [[ "$_line" =~ ${_regex} ]]; then
            echo "# ${BASH_REMATCH[1]}"
            # TODO: not clean enough. eg: [['File System Counters HDFS_BYTES_READ=1469456609',
            echo "${BASH_REMATCH[2]}" | _sed -r 's/\[([^"\[])/\["\1/g' | _sed -r 's/([^"])\]/\1"\]/g' | _sed -r 's/([^"]), ([^"])/\1", "\2/g' | _sed -r 's/\]\[/\], \[/g' | python -m json.tool
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

    ( find "${_dir_path%/}" -name "*.syslog" | xargs -I {} bash -c "_grep -oHP '^${_DATE_FORMAT} \d\d:\d\d:\d\d' -m 1 {}" | awk -F ':' '{print $2":"$3":"$4" "$1}' ) | sort -n | head -n $_num
}

function f_appLogFindLastSyslog() {
    local __doc__="After yarn_app_logs_splitter, find which one was ended in the last. gtac/tac is required"
    local _dir_path="${1-.}"
    local _num="${2-10}"
    local _regex="${3}"

    if [ -n "$_regex" ]; then
        ( for _f in `_grep -l "$_regex" ${_dir_path%/}/*.syslog`; do _dt="`_tac $_f | _grep -oP "^${_DATE_FORMAT} \d\d:\d\d:\d\d" -m 1`" && echo "$_dt $_f"; done ) | sort -nr | head -n $_num
    else
        ( for _f in `find "${_dir_path%/}" -name "*.syslog"`; do _dt="`_tac $_f | _grep -oP "^${_DATE_FORMAT} \d\d:\d\d:\d\d" -m 1`" && echo "$_dt $_f"; done ) | sort -nr | head -n $_num
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
        echo "### bar_chart.py is missing..."
        echo "# sudo -H python -mpip install matplotlib"
        echo "# sudo -H pip install data_hacks"
        local _cmd="uniq -c"
    else
        local _cmd="bar_chart.py"
    fi

    _grep -oP "$_datetime_regex" $_path | $_cmd
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

    # TODO: not sure if sed regex is good (seems to work, Mac sed / gsed doesn't like +?)、Also sed doen't support ¥d
    if [ ! -z "$_datetime_regex" ]; then
        _sed -n "s@\($_datetime_regex\).*\(cmd=[^ ]*\).*src=.*\$@\1,\2@p" $_path | $_cmd
    else
        _sed -n 's:^.*\(cmd=[^ ]*\) .*$:\1:p' $_path | $_cmd
    fi
}

function f_hdfsAuditLogCountPerUser() {
    local __doc__="Count HDFS audit per user for some period"
    local _path="$1"
    local _per_method="$2"
    local _datetime_regex="$3"

    if [ ! -z "$_datetime_regex" ]; then
        _grep -P "$_datetime_regex" $_path > /tmp/f_hdfs_audit_count_per_user_$$.tmp
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
        _sed -n 's:^.*\(ugi=[^ ]*\) .*\(cmd=[^ ]*\).*src=.*$:\1,\2:p' $_path | $_cmd
    else
        _sed -n 's:^.*\(ugi=[^ ]*\) .*$:\1:p' $_path | $_cmd
    fi
}

function f_listPerflogEnd() {
    local __doc__="_grep </PERFLOG ...> to see duration"
    local _path="$1"
    local _sort_by_duration="$2"

    if [[ "$_sort_by_duration" =~ (^y|^Y) ]]; then
        # expecting 5th one is duration after removing start and end time
        #egrep -wo '</PERFLOG .+>' "$_path" | sort -t'=' -k5n
        # removing start and end so that we can easily compare two PERFLOG outputs
        rg -z -wo '</PERFLOG .+>' $_path | _sed -r "s/ (start|end)=[0-9]+//g" | sort -t'=' -k3n
    else
        # sorting with start time
        rg -z -wo '</PERFLOG .+>' $_path | sort -t'=' -k3n
    fi
}

function f_getPerflog() {
    local __doc__="Get lines between PERFLOG method=xxxxx"
    local _path="$1"
    local _approx_datetime="$2"
    local _thread_id="$3"
    local _method="${4-compile}"

    _getAfterFirstMatch "$_path" "^${_approx_datetime}.+ Thread-${_thread_id}\]: .+<PERFLOG method=${_method} " "Thread-${_thread_id}\]: .+<\/PERFLOG method=${_method} " | _grep -vP ": Thread-(?!${_thread_id})\]"
}

function f_findJarByClassName() {
    local __doc__="Find jar by class name (add .class in the name). If symlink needs to be followed, add -L in _search_path"
    local _class_name="$1"
    local _search_path="${2-/usr/hdp/current/*/}" # can be PID too

    # if search path is an integer, treat as PID
    if [[ $_search_path =~ ^-?[0-9]+$ ]]; then
        lsof -nPp $_search_path | _grep -oE '/.+\.(jar|war)$' | sort | uniq | xargs -I {} bash -c "less {} | _grep -qm1 -w $_class_name && echo {}"
        return
    fi
    # NOTE: some 'less' can't read jar, in that case, replace to 'jar -tvf', but may need to modify $PATH
    find $_search_path -type f -name '*.jar' -print0 | xargs -0 -n1 -I {} bash -c "less {} | _grep -m 1 -w $_class_name > /tmp/f_findJarByClassName_$$.tmp && ( echo {}; cat /tmp/f_findJarByClassName_$$.tmp )"
    # TODO: it won't search war file...
}

function f_searchClass() {
    local __doc__="Find jar by *full* class name (without .class) by using PID, which means that component needs to be running, and then export CLASSPATH, and compiles if class_name.java exists"
    local _class_name="$1"  # should be full class name but without .class
    local _pid="$2"         # PID or directory

    local _class_file_path="$( echo "${_class_name}" | sed 's/\./\//g' )"
    local _basename="$(basename ${_class_file_path})"

    if [ -d "${_pid}" ]; then
        _grep -l -Rs "${_class_file_path}" "${_pid}"
        return $?
    fi

    local _cmd_dir="$(dirname `readlink /proc/${_pid}/exe`)" || return $?
    which ${_cmd_dir}/jar &>/dev/null || return 1

    if [ ! -s /tmp/f_searchClass_${_basename}_jars.out ]; then
        ls -l /proc/${_pid}/fd | _grep -oE '/.+\.(jar|war)$' > /tmp/f_searchClass_${_pid}.out
        cat /tmp/f_searchClass_${_pid}.out | sort | uniq | xargs -I {} bash -c ${_cmd_dir}'/jar -tvf {} | _grep -E "'${_class_file_path}'.class" > /tmp/f_searchClass_'${_basename}'_tmp.out && echo {} && cat /tmp/f_searchClass_'${_basename}'_tmp.out >&2' | tee /tmp/f_searchClass_${_basename}_jars.out
    else
        cat /tmp/f_searchClass_${_basename}_jars.out
    fi
}

function f_classpath() {
    local __doc__="Ooutput classpath of the given PID"
    local _pid="$1"
    local _user="`stat -c '%U' /proc/${_pid}`" || return $?
    local _cmd_dir="$(dirname `readlink /proc/${_pid}/exe`)" || return $?
    sudo -u ${_user} ${_cmd_dir}/jcmd ${_pid} VM.system_properties | _grep '^java.class.path=' | sed 's/\\:/:/g' | cut -d"=" -f 2
}

function f_patchJar() {
    local __doc__="Find jar by *full* class name (without .class) by using PID, which means that component needs to be running, and then export CLASSPATH, and compiles if class_name.java exists"
    local _class_name="$1" # should be full class name but without .class
    local _pid="$2"

    local _class_file_path="$( echo "${_class_name}" | sed 's/\./\//g' )"
    local _basename="$(basename ${_class_file_path})"
    local _dirname="$(dirname ${_class_file_path})"
    local _cmd_dir="$(dirname `readlink /proc/${_pid}/exe`)" || return $?
    which ${_cmd_dir}/jar &>/dev/null || return 1
    ls -l /proc/${_pid}/fd | _grep -oE '/.+\.(jar|war)$' > /tmp/f_patchJar_${_pid}.out

    # If needs to compile but _jars.out exist, don't try searching as it takes long time
    if [ ! -s /tmp/f_patchJar_${_basename}_jars.out ]; then
        cat /tmp/f_patchJar_${_pid}.out | sort | uniq | xargs -I {} bash -c ${_cmd_dir}'/jar -tvf {} | _grep -E "'${_class_file_path}'.class" > /tmp/f_patchJar_'${_basename}'_tmp.out && echo {} && cat /tmp/f_patchJar_'${_basename}'_tmp.out >&2' | tee /tmp/f_patchJar_${_basename}_jars.out
    else
        echo "/tmp/f_patchJar_${_basename}_jars.out exists. Reusing..."
    fi

    if [ -e "${_cmd_dir}/jcmd" ]; then
        local _cp="`f_classpath ${_pid}`"
    else
        # if wokring classpath exist, use it
        if [ -s /tmp/f_patchJar_${_basename}_${_pid}_cp.out ]; then
            local _cp="$(cat /tmp/f_patchJar_${_basename}_${_pid}_cp.out)"
        else
            local _cp=$(cat /tmp/f_patchJar_${_pid}.out | tr '\n' ':')
        fi
    fi

    if [ -r "${_basename}.java" ]; then
        [ -z "${_cp}" ] && return 1

        if [ -z "$_CLASSPATH" ]; then
            export CLASSPATH="${_cp%:}"
        else
            export CLASSPATH="${_cp%:}:$_CLASSPATH"
        fi

        # Compile
        ${_cmd_dir}/javac "${_basename}.java" || return $?
        # Saving workign classpath if able to compile
        echo $CLASSPATH > /tmp/f_patchJar_${_basename}_${_pid}_cp.out
        [ -d "${_dirname}" ] || mkdir -p ${_dirname}
        mv -f ${_basename}*class "${_dirname%/}/" || return $?

        for _j in `cat /tmp/f_patchJar_${_basename}_jars.out`; do
            local _j_basename="$(basename ${_j})"
            # If jar file hasn't been backed up, taking one, and if backup fails, skip this jar.
            if [ ! -s ${_j_basename} ]; then
                cp -p ${_j} ./${_j_basename} || continue
            fi
            eval "${_cmd_dir}/jar -uf ${_j} ${_dirname%/}/${_basename}*class"
            ls -l ${_j}
            ${_cmd_dir}/jar -tvf ${_j} | _grep -F "${_dirname%/}/${_basename}"
        done
    else
        echo "${_basename}.java is not readable."
    fi
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
    local _date="_date"

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
        _date="_date -u"
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

function f_appLogSprit() {
    local __doc__="(deprecated: no longer works with Ambari 2.7.x / HDP 2.6.x) Split YARN App log with yarn_app_logs_splitter.py"
    local _app_log="$1"

    local _out_dir="containers_`basename $_app_log .log`"
    # Assuming yarn_app_logs_splitter.py is in the following location
    local _script_path="$(dirname "$_SCRIPT_DIR")/misc/yarn_app_logs_splitter.py"
    if [ ! -s "$_script_path" ]; then
        echo "$_script_path does not exist. Downloading..."
        if [ ! -d "$(dirname "${_script_path}")" ]; then
            mkdir -p "$(dirname "${_script_path}")" || return $?
        fi
        curl -so "${_script_path}" https://raw.githubusercontent.com/hajimeo/samples/master/misc/yarn_app_logs_splitter.py || return $?
    fi
    if [ ! -r "$_app_log" ]; then
        echo "$_app_log is not readable"
        return 1
    fi
    #_grep -Fv "***********************************************************************" $_app_log > /tmp/${_app_log}.tmp
    python "$_script_path" --container-log-dir $_out_dir --app-log "$_app_log"
}

function f_appLogCSprit() {
    local __doc__="Split YARN App log with csplit/gcsplit"
    local _app_log="$1"

    local _out_dir="`basename $_app_log .log`_containers"
    if [ ! -r "$_app_log" ]; then
        echo "$_app_log is not readable"
        return 1
    fi

    if [ ! -d $_out_dir ]; then
        mkdir -p $_out_dir || return $?
    fi

    _csplit -z -f $_out_dir/lineNo_ $_app_log "/^Container: container_/" '{*}' || return $?
    local _new_filename=""
    local _type=""
    # -bash: /bin/ls: Argument list too long, also i think xargs can't use eval, also there is command length limit!
    #find $_out_dir -type f -name 'lineNo_*' -print0 | xargs -P 3 -0 -n1 -I {} bash -c "cd $PWD; _f={};_new_filepath=\"\`head -n 1 \${_f} | grep -oE \"container_.+\" | tr ' ' '_'\`\" && mv \${_f} \"${_out_dir%/}/\${_new_filepath}.out\""
    for _i in {0..9}; do
        for _f in `ls -1 ${_out_dir%/}/lineNo_${_i}* 2>/dev/null`; do
            _new_filename="`head -n 1 ${_f} | grep -oE "container_[a-z0-9_]+"`"
            _type="`grep -m 1 '^LogType:' ${_f} | cut -d ':' -f2`"
            if [ -n "${_new_filename}" ]; then
                if [[ "${_type}" =~ ^.+\.dot$ ]]; then
                    rg '^digraph.+\}' --multiline --multiline-dotall --no-filename --no-line-number ${_f} > "${_out_dir%/}/${_new_filename}.${_type}" && rm -f "${_f}"
                else
                    mv -v -i ${_f} "${_out_dir%/}/${_new_filename}.${_type}"
                fi
            fi
        done
    done
}

function f_appLogSwimlane() {
    local __doc__="TODO: use swimlane (but broken?)"
    local _app_log="$1"

    local _out_name="`basename $_app_log .log`.svg"
    local _tmp_name="`basename $_app_log .log`.tmp"
    local _script_path="$(dirname "$_SCRIPT_DIR")/misc/swimlane.py"
    _grep 'HISTORY' $_app_log > ./$_tmp_name
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

function f_appLogHISTORY() {
    local __doc__="grep keyword from [HISTORY] line"
    local _app_log="$1"
    local _keyword="${2-"timeTaken"}"   # maxTaskDuration

    local _hist_file="/tmp/`basename $_app_log .log`.hist"
    [ ! -s "${_hist_file}" ] && rg -z --no-line-number --no-filename -o '\[HISTORY\].+' $_app_log > $_hist_file || return $?
    [ -n "${_keyword}" ] && rg --no-filename --no-line-number -o "vertexName=([^,]+).+vertexId=([^,]+).+${_keyword}=([^,]+)" -r $'${2}\t${1}\t${3}' $_hist_file | sort -t$'\t' -n -k3

    # TODO: rg '</PERFLOG.+duration=\d{7}+' --no-filename | sort
}

function f_appLogTransition() {
    local __doc__="grep transitioned"
    # f_appLogTransition "*" "" | bar
    # f_appLogTransition "*" "RUNNING" | sort -t $'\t' -k2  # sort by vertexName
    # rg 'VertexName: Reducer 20'
    local _app_log="$1"
    local _keyword="${2-"RUNNING"}"
    # vertex_[0-9_]+
    rg --no-filename --no-line-number -o "^(${_DATE_FORMAT}.\d\d:\d\d:\d\d).+(\[[^]]+\]) (transitioned from.+${_keyword}.+)" -r $'${1}\t${2}\t${3}' | sort | uniq
}

function f_list_start_end(){
    local __doc__="Output start time, end time, difference(sec), (filesize) from *multiple* log files"
    local _glob="${1}"
    local _date_regex="${2:-${_DATE_FORMAT}.\d\d:\d\d:\d\d}"
    local _sort="${3:-2}"
    # If no file(s) given, check current working directory
    if [ -n "${_glob}" ]; then
        _files="`find . -type f -name "${_glob}" -print`"
    else
        local _files="`ls -1`"
    fi
    for _f in `echo ${_files}`; do f_start_end_time_with_diff $_f "^${_date_regex}"; done | sort -t$'\t' -k${_sort}
}

function f_start_end_time_with_diff(){
    local __doc__="Output start time, end time, difference(sec), (filesize) from a log file (eg: for _f in \`ls\`; do f_start_end_time_with_diff \$_f \"^${_DATE_FORMAT}.\d\d:\d\d:\d\d,\d\d\d\"; done | sort -t$'\\t' -k2)"
    local _log="$1"
    local _date_regex="${2}"
    [ -z "$_date_regex" ] && _date_regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d"

    local _start_date=`rg -z -N -om1 "^$_date_regex" ${_log} | sed 's/T/ /'` || return $?
    local _extension="${_log##*.}"
    if [ "${_extension}" = 'gz' ]; then
        local _end_date=`gunzip -c ${_log} | _tac | rg -N -om1 "^$_date_regex" | sed 's/T/ /'` || return $?
    else
        local _end_date=`_tac ${_log} | rg -z -N -om1 "^$_date_regex" | sed 's/T/ /'` || return $?
    fi
    local _start_int=`_date2int "${_start_date}"`
    local _end_int=`_date2int "${_end_date}"`
    local _diff=$(( $_end_int - $_start_int ))
    # Filename, start datetime, enddatetime, difference, (filesize)
    echo -e "`basename ${_log}`\t${_start_date}\t${_end_date}\t${_diff} s\t$((`wc -c <${_log}` / 1024)) KB"
}

function f_split_strace() {
    local __doc__="Split a strace output, which didn't use -ff, per PID. As this function may take time, it should be safe to cancel at any time, and re-run later"
    local _strace_file="$1"
    local _save_dir="${2-./}"
    local _reverse="$3"

    local _cat="cat"
    if [[ "${_reverse}" =~ (^y|^Y) ]]; then
        which tac &>/dev/null && _cat="tac"
        which gtac &>/dev/null && _cat="gtac"
    fi

    [ ! -d "${_save_dir%/}" ] && ( mkdir -p "${_save_dir%/}" || return $? )
    if [ ! -s "${_save_dir%/}/_pid_list.tmp" ]; then
        awk '{print $1}' "${_strace_file}" | sort -n | uniq > "${_save_dir%/}/_pid_list.tmp"
    else
        echo "${_save_dir%/}/_pid_list.tmp exists. Reusing..." 1>&2
    fi

    for _p in `${_cat} "${_save_dir%/}/_pid_list.tmp"`
    do
        if [ -s "${_save_dir%/}/${_p}.out" ]; then
            if [[ "${_reverse}" =~ (^y|^Y) ]]; then
                echo "${_save_dir%/}/${_p}.out exists. As reverse mode, exiting..." 1>&2
                return
            fi
            echo "${_save_dir%/}/${_p}.out exists. skipping..." 1>&2
            continue
        fi
        _grep "^${_p} " "${_strace_file}" > "${_save_dir%/}/.${_p}.out" && mv -f "${_save_dir%/}/.${_p}.out" "${_save_dir%/}/${_p}.out"
    done
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

    local _commits_only="`echo "$_grep_result" | _grep ^commit | cut -d ' ' -f 2`"

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
    _grep -P '^log4j\..+\.(BlockStateChange|StateChange)' ${_conf%/}/log4j.properties
}

function f_hive_checklist() {
    local __doc__="Store Hive config checklist in this function"
    local _conf="${1-./}"   # set / set -v output or hive-site.xml
    local _others="$2"      # check HDFS, YARN, MR2 configs if 'y'

    # 1. check the following properties' values
    # _grep -ohP '\(property\(.+$' * | cut -d '"' -f 2 | tr '\n' ' '

    echo "# Hive config check" >&2
    local _props="hive.auto.convert.join hive.merge.mapfiles hive.merge.mapredfiles hive.exec.compress.intermediate hive.exec.compress.output datanucleus.cache.level2.type hive.default.fileformat.managed hive.default.fileformat fs.hdfs.impl.disable.cache fs.file.impl.disable.cache hive.cbo.enable hive.compute.query.using.stats hive.stats.fetch.column.stats hive.stats.fetch.partition.stats hive.execution.engine datanucleus.fixedDatastore hive.exim.strict.repl.tables datanucleus.autoCreateSchema hive.exec.parallel hive.plan.serialization.format hive.server2.tez.initialize.default.sessions hive.vectorized.execution.enabled hive.vectorized.execution.reduce.enabled"
    _search_properties "${_conf%/}" "${_props}"

    echo -e "\n# Tez config check" >&2
    _props="tez.am.am-rm.heartbeat.interval-ms.max tez.runtime.transfer.data-via-events.enabled tez.session.am.dag.submit.timeout.secs tez.am.container.reuse.enabled tez.runtime.io.sort.mb tez.session.client.timeout.secs tez.runtime.shuffle.memory-to-memory.enable tez.runtime.task.input.post-merge.buffer.percent tez.am.container.session.delay-allocation-millis tez.session.am.dag.submit.timeout.secs tez.runtime.shuffle.fetch.buffer.percent tez.task.am.heartbeat.interval-ms.max tez.task.am.heartbeat.counter.interval-ms.max tez.task.get-task.sleep.interval-ms.max tez.task.scale.memory.enabled"
    _search_properties "${_conf%/}" "${_props}"

    echo -e "\n# Hive extra config check" >&2
    _props="hive.metastore.client.connect.retry.delay hive.metastore.client.connect.retry.delay hive.metastore.failure.retries hive\..*aux.jars.path hive.server2.async.exec.threads hive\.server2\..*\.threads hive.tez.java.opts hive.server2.idle.session.check.operation hive.server2.session.check.interval hive.server2.idle.session.timeout hive.server2.idle.operation.timeout tez.session.am.dag.submit.timeout.secs tez.yarn.ats.event.flush.timeout.millis hive.llap.* fs.permissions.umask-mode hive.optimize.reducededuplication"
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
        _grep -P '^(env:HOSTNAME|env:HADOOP_HEAPSIZE|env:HADOOP_CLIENT_OPTS|system:hdp\.version|system:java\.home|system:java\.vm\.*|system:java\.io\.tmpdir|system:os\.version|system:user\.timezone)=' "$_conf"
    fi
}

_COMMON_QUERIE_UPDATES="UPDATE users SET user_password='538916f8943ec225d97a9a86a2c6ec0818c1cd400e09e03b660fdaaec4af29ddbb6f2b1033b81b00' WHERE user_name='admin' and user_type='LOCAL';"
_COMMON_QUERIE_SELECTS="select * from metainfo where metainfo_key = 'version';select repo_version_id, stack_id, display_name, repo_type, substring(repositories, 1, 500) from repo_version order by repo_version_id desc limit 5;SELECT * FROM clusters WHERE security_type = 'KERBEROS';"
function f_load_ambaridb_to_postgres() {
    local __doc__="Load ambari DB sql file into Mac's (locals) PostgreSQL DB"
    local _sql_file="$1"
    local _missing_tables_sql="$2"
    local _sudo_user="${3-$USER}"
    local _ambari_pwd="${4-bigdata}"

    # If a few tables are missing, need missing tables' schema
    # pg_dump -Uambari -h `hostname -f` ambari -s -t alert_history -t host_role_command -t execution_command -t request > ambari_missing_table_ddl.sql

    if ! sudo -u ${_sudo_user} -i psql template1 -c '\l+'; then
        echo "Connecting to local postgresql failed. Is PostgreSQL running?"
        echo "pg_ctl -D /usr/local/var/postgres -l ~/postgresql.log restart"
        return 1
    fi
    sleep 3q

    #echo "sudo -iu ${_sudo_user} psql template1 -c 'DROP DATABASE ambari;'"
    if ! sudo -iu ${_sudo_user} psql template1 -c 'ALTER DATABASE ambari RENAME TO ambari_'$(date +"%Y%m%d%H%M%S") ; then
        sudo -iu ${_sudo_user} psql template1 -c "select pid, usename, application_name, client_addr, client_port, waiting, state, query_start, query, xact_start from pg_stat_activity where datname='ambari'"
        return 1
    fi
    sudo -iu ${_sudo_user} psql template1 -c 'CREATE DATABASE ambari;'
    sudo -iu ${_sudo_user} psql template1 -c "CREATE USER ambari WITH LOGIN PASSWORD '${_ambari_pwd}';"
    sudo -iu ${_sudo_user} psql template1 -c 'GRANT ALL PRIVILEGES ON DATABASE ambari TO ambari;'

    export PGPASSWORD="${_ambari_pwd}"
    psql -Uambari -h `hostname -f` ambari -c 'CREATE SCHEMA ambari;ALTER SCHEMA ambari OWNER TO ambari;'

    # TODO: may need to replace the schema if not 'ambari'
    #_sed -i'.bak' -r 's/\b(custom_schema|custom_owner)\b/ambari/g' ambari.sql

    # It's OK to see relation error for index (TODO: upgrade table may fail)
    [ -s "$_missing_tables_sql" ] && psql -Uambari -h `hostname -f` ambari < ${_missing_tables_sql}
    psql -Uambari -h `hostname -f` ambari < ${_sql_file}
    [ -s "$_missing_tables_sql" ] && psql -Uambari -h `hostname -f` ambari < ${_missing_tables_sql}
    psql -Uambari -h `hostname -f` -c "${_COMMON_QUERIE_UPDATES}"
    psql -Uambari -h `hostname -f` -c "${_COMMON_QUERIE_SELECTS}"

    echo "psql -Uambari -h `hostname -f` -xc \"UPDATE clusters SET security_type = 'NONE' WHERE provisioning_state = 'INSTALLED' and security_type = 'KERBEROS';\""
    #curl -i -H "X-Requested-By:ambari" -u admin:admin -X DELETE "http://$AMBARI_SERVER:8080/api/v1/clusters/$CLUSTER/services/KERBEROS"
    #curl -i -H "X-Requested-By:ambari" -u admin:admin -X DELETE "http://$AMBARI_SERVER:8080/api/v1/clusters/$CLUSTER/artifacts/kerberos_descriptor"
    unset PGPASSWORD
}

function f_load_ambaridb_to_mysql() {
    local __doc__="Load ambari DB sql file into Mac's (locals) MySQL DB"
    local _sql_file="$1"
    local _missing_tables_sql="$2"
    local _sudo_user="${3-$USER}"
    local _ambari_pwd="${4-bigdata}"

    # If a few tables are missing, need missing tables' schema
    # pg_dump -Uambari -h `hostname -f` ambari -s -t alert_history -t host_role_command -t execution_command -t request > ambari_missing_table_ddl.sql

    if ! mysql -u root -e 'show databases'; then
        echo "Connecting to local MySQL failed. Is MySQL running?"
        echo "brew services start mysql"
        return 1
    fi

    mysql -u root -e "CREATE USER 'ambari'@'%' IDENTIFIED BY '${_ambari_pwd}';
GRANT ALL PRIVILEGES ON *.* TO 'ambari'@'%';
CREATE USER 'ambari'@'localhost' IDENTIFIED BY '${_ambari_pwd}';
GRANT ALL PRIVILEGES ON *.* TO 'ambari'@'localhost';
CREATE USER 'ambari'@'`hostname -f`' IDENTIFIED BY '${_ambari_pwd}';
GRANT ALL PRIVILEGES ON *.* TO 'ambari'@'`hostname -f`';
FLUSH PRIVILEGES;"

    if ! mysql -uambari -p${_ambari_pwd} -h `hostname -f` -e 'create database ambari'; then
        echo "Please drop the database first as renaming DB on MySQL is hard"
        echo "mysql -uambari -p${_ambari_pwd} -h `hostname -f` -e 'DROP DATABASE ambari;'"
        return
    fi

    mysql -u ambari -p${_ambari_pwd} -h `hostname -f` ambari < "${_sql_file}"

    # TODO: _missing_tables_sql
    mysql -u ambari -p${_ambari_pwd} -h `hostname -f` ambari -e "${_COMMON_QUERIE_UPDATES}"
    mysql -u ambari -p${_ambari_pwd} -h `hostname -f` ambari -e "${_COMMON_QUERIE_SELECTS}"

    echo "mysql -u ambari -p${_ambari_pwd} -h `hostname -f` ambari -e \"UPDATE clusters SET security_type = 'NONE' WHERE provisioning_state = 'INSTALLED' and security_type = 'KERBEROS';\""
    #curl -i -H "X-Requested-By:ambari" -u admin:admin -X DELETE "http://$AMBARI_SERVER:8080/api/v1/clusters/$CLUSTER/services/KERBEROS"
    #curl -i -H "X-Requested-By:ambari" -u admin:admin -X DELETE "http://$AMBARI_SERVER:8080/api/v1/clusters/$CLUSTER/artifacts/kerberos_descriptor"
}

function f_gc_before_after_check() {
    local __doc__="TODO: add PrintClassHistogramBeforeFullGC, and parse log to find which objects are increasing"
    return
    # TODO: _grep -F '#instances' -A 20 solr_gc.log | _grep -E -- '----------------|org.apache'
    export JAVA_GC_LOG_DIR="/some/location"
    export JAVA_GC_OPTS="-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=${JAVA_GC_LOG_DIR%/}/ \
    -XX:+PrintClassHistogramBeforeFullGC -XX:+PrintClassHistogramAfterFullGC \
    -XX:+TraceClassLoading -XX:+TraceClassUnloading \
    -verbose:gc -XX:+PrintGC -XX:+PrintGCDetails -XX:+PrintGCDateStamps \
    -Xloggc:${JAVA_GC_LOG_DIR}/gc.log -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=1024k"
}

function f_validate_siro_ini() {
    local __doc__="TODO: Read shiro config file and, at least, generate ldapsarch command"
    return
}

function f_count_lines() {
    local __doc__="Count lines between _search_regex of periodic.log"
    local _file="$1"
    local _search_regex="${2:-"^20\\d\\d-\\d\\d-\\d\\d .+Periodic stack trace"}"

    [ -z "${_file}" ] && _file="`find . -name periodic.log -print | head -n1`" && ls -lh ${_file}
    [ ! -s "${_file}" ] && return

    local _ext="${_file##*.}"
    if [[ "${_ext}" =~ gz ]]; then
        local _line_num=`gunzip -c ${_file} | wc -l | tr -d '[:space:]'`
        rg -n --no-filename -z "${_search_regex}" ${_file} | rg -o '^(\d+):(2\d\d\d-\d\d-\d\d) (\d\d:\d\d:\d\d,\d\d\d)' -r '${2}T${3} ${1}' | line_parser.py thread_num ${_line_num} | bar_chart.py -A
    else
        local _line_num=`wc -l <${_file} | tr -d '[:space:]'`
        rg -n --no-filename -z "${_search_regex}" ${_file} | rg -o '^(\d+):(2\d\d\d-\d\d-\d\d) (\d\d:\d\d:\d\d,\d\d\d)' -r '${2}T${3} ${1}' | line_parser.py thread_num ${_line_num} | bar_chart.py -A
    fi
}

function f_count_threads() {
    local __doc__="Grep periodic log and count threads of periodic.log"
    local _file="$1"
    local _tail_n="${2-10}"
    [ -z "${_file}" ] &&  _file="`find . -name periodic.log -print | head -n1`" && ls -lh ${_file}
    [ ! -s "${_file}" ] && return

    if [ -n "${_tail_n}" ]; then
        rg -z -N -o '^"([^"]+)"' -r '$1' "${_file}" | _sed -r 's/-[0-9]+$//g' | sort | uniq -c | sort -n | tail -n ${_tail_n}
    else
        rg -z -N -o '^"([^"]+)"' -r '$1' "${_file}" | sort | uniq
    fi
}

function f_count_threads_per_dump() {
    local __doc__="Split periodic (thread dump) log and count threads per dump"
    local _file="$1"
    local _search="${2:-"- Periodic stack trace .:"}"

    [ -z "${_file}" ] &&  _file="`find . -name periodic.log -print | head -n1`" && ls -lh ${_file}
    local _tmp_dir="/tmp/tdumps"
    local _prefix="periodic_"
    _file="$(realpath "${_file}")"

    mkdir ${_tmp_dir} &>/dev/null
    cd ${_tmp_dir} || return $?

    local _ext="${_file##*.}"
    if [[ "${_ext}" =~ gz ]]; then
        _csplit -f "${_prefix}" <(gunzip -c ${_file}) "/${_search}/" '{*}'
    else
        _csplit -f "${_prefix}" ${_file} "/${_search}/" '{*}'
    fi

    if [ $? -ne 0 ]; then
        cd -
        return 1
    fi

    for _f in `ls -1 ${_prefix}*`; do
        head -n 1 $_f
        # NOTE: currently excluding thread which occurrence is only 1.
        rg '^"([^"]+)"' -o -r '$1' $_f | _sed 's/[0-9]\+/_/g' | sort | uniq -c | grep -vE '^ +1 '
        echo '--'
    done
    cd -
}


### Private functions ##################################################################################################

function _mexec() {
    local __doc__="Execute multple commands concurrently. NOTE: seems Mac's xargs has command length limit and no -r to ignore empty line"
    local _cmds_list="$1"
    local _prefix_cmd="$2"  # NOTE: no ";"
    local _suffix_cmd="$3"  # NOTE: no ";"
    local _num_process="${4:-3}"
    if [ -f "${_cmds_list}" ]; then
        cat "${_cmds_list}"
    else
        echo ${_cmds_list}
    fi | tr '\n' '\0' | xargs -0 -n1 -P${_num_process} -I @@ bash -c "${_prefix_cmd}@@${_suffix_cmd}"
}

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
    local _exclude_first_line="$4"
    local _extension="${_file_path##*.}"

    local _start_line_num=`rg -z -n -m1 "$_start_regex" "$_file_path" | cut -d ":" -f 1`
    if [ -n "$_start_line_num" ]; then
        local _end_line_num="\$"
        if [ -n "$_end_regex" ]; then
            #_sed -n "${_start_line_num},\$s/${_end_regex}/&/p" "$_file_path"
            local _tmp_start_line_num=$_start_line_num
            [[ "$_exclude_first_line" =~ ^(y|Y) ]] && _tmp_start_line_num=$(($_start_line_num + 1))
            if [ "${_extension}" = 'gz' ]; then
                _end_line_num=`gunzip -c "$_file_path" | tail -n +${_tmp_start_line_num} | _grep -m1 -nP "$_end_regex" | cut -d ":" -f 1`
            else
                _end_line_num=`tail -n +${_tmp_start_line_num} "$_file_path" | _grep -m1 -nP "$_end_regex" | cut -d ":" -f 1`
            fi
            _end_line_num=$(( $_end_line_num + $_start_line_num - 1 ))
        fi
        if [ "${_extension}" = 'gz' ]; then
            gunzip -c "${_file_path}" | _sed -n "${_start_line_num},${_end_line_num}p"
        else
            _sed -n "${_start_line_num},${_end_line_num}p" "${_file_path}"
        fi
    fi
}

function _date2int() {
    local _date_str="$1"
    [[ "${_date_str}" =~ ^[0-9][0-9]\/[0-9][0-9]\/[0-9][0-9].[0-9][0-9]:[0-9][0-9]:[0-9][0-9] ]] && _date_str="`dateconv "${_date_str}" -i "%y/%m/%d %H:%M:%S" -f "%Y-%m-%d %H:%M:%S"`"
    _date -d "${_date_str}" +"%s"
}

function _find_and_cat() {
    for _f in `find . -name "$1" -print`; do
        echo "## ${_f}" >&2
        if [ -n "${_f}" ]; then
            cat "${_f}"
        fi
    done
}

function _replace_number() {
    _sed -r "s/[0-9a-fA-F]+-[0-9a-fA-F]+-[0-9a-fA-F]+-[0-9a-fA-F]+-[0-9a-fA-F]+/__UUID__/g" \
     | _sed -r "s/0x[0-9a-f][0-9a-f]+/0x_HEX_/g" \
     | _sed -r "s/[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]/_HEX_/g" \
     | _sed -r "s/20[0-9][0-9][-/][0-9][0-9][-/][0-9][0-9][ T]/_DATE_ /g" \
     | _sed -r "s/[0-2][0-9]:[0-6][0-9]:[0-6][0-9][.,0-9]*/_TIME_/g" \
     | _sed -r "s/-[0-9]+\]\s+\{/-N] {/g" \
     | _sed -r "s/[0-9][0-9][0-9][0-9][0-9]+/_NUM_/g"
}

function _load_yaml() {
    local _yaml_file="${1}"
    local _name_space="${2}"
    [ -s "${_yaml_file}" ] || return 1
    # TODO: probably this can be done only with awk
    #awk -F "=" '{out=$2;gsub(/[^0-9a-zA-Z_]/,"_",$1);for(i=3;i<=NF;i++){out=out"="$i};print $1"=\""$out"\""}' ${_yaml_file} > /tmp/_load_yaml.out || return $?
    _sed -n -r 's/^([^=]+)[[:space:]]+=[[:space:]]+(.+)/'${_name_space}'\1\t"\2"/p' ${_yaml_file} | awk -F "\t" '{gsub(/[^0-9a-zA-Z_]/,"_",$1); print $1"="$2}' > /tmp/_load_yaml.out || return $?
    source /tmp/_load_yaml.out
}

function _search_properties() {
    local _path="${1-./}"
    local _props="$2" # space separated regex
    local _is_name_value_xml="$3"

    for _p in ${_props}; do
        if [[ "${_is_name_value_xml}" =~ (^y|^Y) ]]; then
            local _out="`_grep -Pzo "(?s)<name>${_p}</name>.+?</value>" ${_path}`"
            [[ "${_out}" =~ (<value>)(.*)(</value>) ]]
            echo "${_p}=${BASH_REMATCH[2]}"
        else
            # Expecting hive 'set' command output or similar style (prop=value)
            _grep -P "${_p}" ${_path}
        fi
    done
}

function _sed() {
    local _cmd="sed"; which gsed &>/dev/null && _cmd="gsed"
    ${_cmd} "$@"
}
function _csplit() {
    local _cmd="csplit"; which gcsplit &>/dev/null && _cmd="gcsplit"
    ${_cmd} "$@"
}
function _grep() {
    local _cmd="grep"; which grep &>/dev/null && _cmd="ggrep"
    ${_cmd} "$@"
}
function _date() {
    local _cmd="date"; which gdate &>/dev/null && _cmd="gdate"
    ${_cmd} "$@"
}
function _tac() {
    local _cmd="tac"; which gtac &>/dev/null && _cmd="gtac"
    ${_cmd} "$@"
}



### Help ###############################################################################################################

help() {
    local _function_name="$1"
    local _show_code="$2"
    local _doc_only="$3"

    if [ -z "$_function_name" ]; then
        echo "help <function name> [Y]"
        echo ""
        _list "func"
        echo ""
        return
    fi

    local _output=""
    if [[ "$_function_name" =~ ^[fp]_ ]]; then
        local _code="$(type $_function_name 2>/dev/null | _grep -v "^${_function_name} is a function")"
        if [ -z "$_code" ]; then
            echo "Function name '$_function_name' does not exist."
            return 1
        fi

        eval "$(echo -e "${_code}" | awk '/__doc__=/,/;/')"
        if [ -z "$__doc__" ]; then
            _output="No help information in function name '$_function_name'.\n"
        else
            _output="$__doc__"
            if [[ "${_doc_only}" =~ (^y|^Y) ]]; then
                echo -e "${_output}"; return
            fi
        fi

        local _params="$(type $_function_name 2>/dev/null | _grep -iP '^\s*local _[^_].*?=.*?\$\{?[1-9]' | _grep -v awk)"
        if [ -n "$_params" ]; then
            _output="${_output}Parameters:\n"
            _output="${_output}${_params}\n"
        fi
        if [[ "${_show_code}" =~ (^y|^Y) ]] ; then
            _output="${_output}\n${_code}\n"
            echo -e "${_output}" | less
        elif [ -n "$_output" ]; then
            echo -e "${_output}"
            echo "(\"help $_function_name y\" to show code)"
        fi
    else
        echo "Unsupported Function name '$_function_name'."
        return 1
    fi
}
_list() {
    local _name="$1"
    #local _width=$(( $(tput cols) - 2 ))
    local _tmp_txt=""
    # TODO: restore to original posix value
    set -o posix

    if [[ -z "$_name" ]]; then
        (for _f in `typeset -F | _grep -P '^declare -f [fp]_' | cut -d' ' -f3`; do
            #eval "echo \"--[ $_f ]\" | _sed -e :a -e 's/^.\{1,${_width}\}$/&-/;ta'"
            _tmp_txt="`help "$_f" "" "Y"`"
            printf "%-28s%s\n" "$_f" "$_tmp_txt"
        done)
    elif [[ "$_name" =~ ^func ]]; then
        typeset -F | _grep '^declare -f [fp]_' | cut -d' ' -f3
    elif [[ "$_name" =~ ^glob ]]; then
        set | _grep ^[g]_
    elif [[ "$_name" =~ ^resp ]]; then
        set | _grep ^[r]_
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
[ -z "$_TIME_FMT4CHART" ] && _TIME_FMT4CHART="\d\d:"
_SCRIPT_DIR="$(dirname $(realpath "$BASH_SOURCE"))"


### Main ###############################################################################################################
if [ "$0" = "$BASH_SOURCE" ]; then
    usage | less
fi