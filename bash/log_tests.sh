#!/usr/bin/env bash
_usage() {
    cat << EOF
Providing some framework for building log check/test cases (like programing language's Unit tests) with bash.

All functions start with "e_" are for extracting data, so that tests do not need to check large log files repeatedly.
All functions start with "t_" are actual testing / checking. those should behave similar to unit tests.
All functions start with "r_" are for reporting, just displaying some useful, good-to-know information with Markdown.

PREREQUISITE:
    bash, not tested with zsh.
    Please install below: (eg: 'brew install coreutils findutils ripgrep jq q')
        coreutils (eg: realpath)
        findutils (eg: gfind)
        rg  https://github.com/BurntSushi/ripgrep
        jq  https://stedolan.github.io/jq/download/
        q   https://github.com/harelba/q
        python3 with pandas
    Also, please put below in the PATH:
        https://github.com/bitly/data_hacks/blob/master/data_hacks/bar_chart.py (TODO: this project is no longer updated)

TARGET OS:
    macOS Mojave

GLOBAL VARIABLES (not all):
    _APP_VER_OVERWRITE                  To specify application version
    _WORKING_DIR_OVERWRITE              To specify the sonatype work directory (but not used)
    _NXRM_LOG _NXIQ_LOG _REQUEST_LOG    To specify the log filename (used for rg -g)
    _LOG_DATE                           To specify above log files
    _LOG_THRESHOLD_BYTES                Some time consuming functions are skipped if file is larger than 256MB
    _SKIP_EXTRACT                       Do not run functions start with e_
EOF
}
_prerequisites() {
    if ! type q >/dev/null || ! type rg >/dev/null || ! type jq >/dev/null || ! type realpath >/dev/null; then
        _LOG "ERROR" "Required command is missing."
        _usage
        return 1
    fi
}

# Importing external libraries
_import() { . $HOME/IdeaProjects/samples/bash/${1} &>/dev/null && return; [ ! -s /tmp/${1} ] && curl -sf --compressed "https://raw.githubusercontent.com/hajimeo/samples/master/bash/${1}" -o /tmp/${1}; . /tmp/${1}; }
# Requires https://raw.githubusercontent.com/hajimeo/samples/master/bash/log_search.sh
_import "log_search.sh"

# Global variables
if [ -n "${_LOG_DATE}" ]; then
    _NXRM_LOG="nexus-${_LOG_DATE}.log.gz"
    _NXIQ_LOG="clm-server-${_LOG_DATE}.log.gz"
    _REQUEST_LOG="request-${_LOG_DATE}.log.gz"
    _AUDIT_LOG="audit-${_LOG_DATE}.log.gz"
else
    _NXRM_LOG="${_NXRM_LOG:-"nexus.log"}"
    _NXIQ_LOG="${_NXIQ_LOG:-"clm-server.log"}"
    _REQUEST_LOG="${_REQUEST_LOG:-"request.log"}"
    _AUDIT_LOG="${_AUDIT_LOG:-"audit.log"}"
fi
: ${_LOG_THRESHOLD_BYTES:=134217728}    # 128MB, usually takes 7s
: ${_LOG_THRESHOLD_LINES:=20000}        # Currently used to decide if it generates iostat csv file
: ${_FILTERED_DATA_DIR:="./_filtered"}
: ${_LOG_GLOB:="*.log"}
: ${_SKIP_EXTRACT:=""}
: ${_BG_JOB_NUM:="6"}

_WORKING_DIR="${_WORKING_DIR_OVERWRITE:-"<null>"}"  # value for either workingDirectory or sonatypeWork
_APP_VER="${_APP_VER_OVERWRITE:-"<null>"}"          # 3.36.0-01


# Aliases (can't use alias in shell script, so functions)
_rg() {
    local _max_filesize="${_RG_MAX_FILESIZE-"8G"}"
    if [ -n "${_max_filesize}" ]; then
        rg --max-filesize "${_max_filesize}" -z "$@"
    else
        rg -z "$@"
    fi 2>/tmp/._rg_last.err
    local _rc=$?
    if [ ${_rc:-0} -ne 0 ] && [ -s /tmp/._rg_last.err ]; then
         echo "[$(date +'%Y-%m-%d %H:%M:%S')] rg (${_max_filesize}) $*" >> /tmp/_rg.log
         cat /tmp/._rg_last.err >> /tmp/_rg.log
    fi
    return ${_rc}
}
_bar() {
    bar_chart.py "$@" | grep -v 'Error: no data'
}
_q() {
    q -O -d"," -T --disable-double-double-quoting "$@" 2>/tmp/_q_last.err
}

_log_duration() {
    local _started="$1"
    local _ended="$2"
    local _threshold="${3:-"0"}"
    local _log_msg="${4:-"Completed ${FUNCNAME[1]}"}"
    [ -z "${_started}" ] && return
    [ -z "${_ended}" ] && _ended="$(date +%s)"
    local _diff=$((${_ended} - ${_started}))
    local _log_level="DEBUG"
    if [ ${_diff} -ge ${_threshold} ]; then
        _log_level="INFO"
    fi
    _LOG "${_log_level}" "${_log_msg} in ${_diff}s"
}

_runner() {
    local _pfx="$1"
    local _n="${2:-"${_BG_JOB_NUM:-"3"}"}"
    local _sec="${3:-"3"}"
    local _tmp="$(mktemp -d)"
    _LOG "INFO" "Executing ${FUNCNAME[1]}->${FUNCNAME[0]} $(typeset -F | grep "^declare -f ${_pfx}" | wc -l  | tr -d "[:space:]") functions."
    for _t in $(typeset -F | grep "^declare -f ${_pfx}" | cut -d' ' -f3); do
        if ! _wait_jobs "${_n}"; then
            _LOG "ERROR" "${FUNCNAME[0]} failed."
            return 11
        fi
        _LOG "DEBUG" "Started ${_t}"    # TODO: couldn't display actual command in jogs -l command
        local _started="$(date +%s)"
        eval "${_t} > ${_tmp}/${_t}.out;_log_duration \"${_started}\" \"\" \"${_sec}\" \"Completed ${_t}\"" &
    done
    _wait_jobs 0
    cat ${_tmp}/${_pfx}*.out
    _LOG "INFO" "Completed ${FUNCNAME[1]}->${FUNCNAME[0]}."
}

function f_run_extract() {
    [ -d "${_FILTERED_DATA_DIR%/}" ] || mkdir -v -p "${_FILTERED_DATA_DIR%/}" || return $?
    #if [ "$(ls -1 "${_FILTERED_DATA_DIR%/}")" ]; then
    #    _LOG "INFO" "${_FILTERED_DATA_DIR%/} is not empty so not extracting."
    #    return
    #fi
    if [[ "${_SKIP_EXTRACT}" =~ (y|Y) ]]; then
        _LOG "INFO" "_SKIP_EXTRACT is set, so not extracting."
        return
    fi
    _runner "e_"
}

function f_run_report() {
    echo "# ${FUNCNAME[0]} results"
    echo ""
    if [ ! -s ${_FILTERED_DATA_DIR%/}/extracted_configs.md ]; then
        _head "INFO" "No ${_FILTERED_DATA_DIR%/}/extracted_configs.md"
    else
        cat ${_FILTERED_DATA_DIR%/}/extracted_configs*.md
    fi
    _runner "r_"
}

function f_run_tests() {
    echo "# ${FUNCNAME[0]} results"
    echo ""
    _runner "t_"
    # TODO: currently can't count failed test.
}

function _extract_configs() {
    _head "CONFIG" "system-environment"
    echo '```'
    _search_json "sysinfo.json" "system-environment,HOSTNAME"
    _search_json "sysinfo.json" "system-environment,USER"
    _search_json "sysinfo.json" "system-environment,TZ"
    _search_json "sysinfo.json" "system-environment,PWD"
    _search_json "sysinfo.json" "system-environment,HOME" # for -Djava.util.prefs.userRoot=/home/nexus/.java
    rg '\.encoding"' -g sysinfo.json | sort | uniq
    _search_json "jmx.json" "java.lang:type=Runtime,Name" # to find PID and hostname (in case no HOSTNAME env set)
    _search_json "jmx.json" "java.lang:type=Runtime,SystemProperties" "" "Y" | rg '"(java.util.prefs.userRoot|java.home)'
    echo '```'

    _head "CONFIG" "OS/server information from jmx.json"
    echo '```'
    #_search_json "sysinfo.json" "system-runtime"   # This one does not show physical memory size
    _search_json "jmx.json" "java.lang:type=OperatingSystem,AvailableProcessors"
    _search_json "jmx.json" "java.lang:type=OperatingSystem,TotalPhysicalMemorySize" "Y"
    _search_json "jmx.json" "java.lang:type=OperatingSystem,FreePhysicalMemorySize" "Y"
    _search_json "jmx.json" "java.lang:type=OperatingSystem,CommittedVirtualMemorySize" "Y"
    _search_json "jmx.json" "java.lang:type=OperatingSystem,TotalSwapSpaceSize" "Y"
    _search_json "jmx.json" "java.lang:type=OperatingSystem,FreeSwapSpaceSize" "Y"
    _search_json "jmx.json" "java.lang:type=OperatingSystem,SystemCpuLoad"
    _search_json "jmx.json" "java.lang:type=OperatingSystem,ProcessCpuLoad"
    _search_json "jmx.json" "java.lang:type=OperatingSystem,SystemLoadAverage"
    _search_json "jmx.json" "java.lang:type=OperatingSystem,MaxFileDescriptorCount"
    _search_json "jmx.json" "java.lang:type=OperatingSystem,OpenFileDescriptorCount"
    echo '```'

    _head "CONFIG" "system-runtime"
    echo '```'
    _search_json "sysinfo.json" "system-runtime,totalMemory" "Y"
    _search_json "sysinfo.json" "system-runtime,freeMemory" "Y"
    _search_json "sysinfo.json" "system-runtime,maxMemory" "Y"
    _search_json "sysinfo.json" "system-runtime,threads"
    _search_json "jmx.json" "java.lang:type=Runtime,InputArguments" | uniq
    echo '```'

    _head "CONFIG" "network related"
    echo '```json'
    _search_json "sysinfo.json" "system-network"
    echo '```'

    _head "CONFIG" "database related"
    echo '```'
    _find_and_cat "config_ds_info.properties" 2>/dev/null
    _find_and_cat "db_info.properties" 2>/dev/null
    _find_and_cat "dbFileInfo.txt" | head -n10 2>/dev/null
    echo '```'

    # TODO: add installDirectory and IQ sonatype-work
    _head "CONFIG" "application related"
    echo '```'
    echo "sonatypeWork: \"$(_working_dir)\""
    echo "app version: \"$(_app_ver)\""
    echo '```'
}
function _working_dir() {
    [ -n "${_WORKING_DIR}" ] && [ "${_WORKING_DIR}" != "<null>" ] && echo "${_WORKING_DIR}" && return
    local _working_dir_line="$(_search_json "sysinfo.json" "nexus-configuration,workingDirectory" || _search_json "sysinfo.json" "install-info,sonatypeWork")"
    local _result="$(echo "${_working_dir_line}" | _rg ': "([^"]+)' -o -r '$1')"
    [ -n "${_result}" ] && [ "${_result}" != "<null>" ] && export _WORKING_DIR="$(echo "${_result}")" && echo "${_WORKING_DIR}"
}
function _is_mount() {
    local _path="${1:-"${_WORKING_DIR}"}"
    local _filestores="${2:-"${_FILTERED_DATA_DIR%/}/system-filestores.json"}"
    local _type_rx="${3:-"(nfs|cifs)"}"
    local _crt="${_path%/}"
    [ -z "${_path}" ] && return 2
    [ "${_path}" == "<null>" ] && return 3
    for i in {1..7}; do # checking 7 depth would be enough
        # should be more strict regex?
        if rg -m1 -A5 "\"description\"\s*:\s*\"${_crt%/}[ \"]" ${_filestores} | rg -q '"type"\s*:\s*"'${_type_rx}; then
            rg -m1 -A6 -B1 "\"description\"\s*:\s*\"${_crt%/}[ \"]" ${_filestores}
            return 0
        fi
        _crt="$(dirname "${_crt}")"
        [ -z "${_crt%/}" ] && break
    done
    return 1
}
function _app_ver() {
    [ -n "${_APP_VER}" ] && [ "${_APP_VER}" != "<null>" ] && echo "${_APP_VER}" && return
    local _app_ver_line="$(_search_json "sysinfo.json" "nexus-status,version" || _search_json "product-version.json" "product-version,version")"
    local _result="$(echo "${_app_ver_line}" | _rg ': "([^"]+)' -o -r '$1')"
    [ -n "${_result}" ] && [ "${_result}" != "<null>" ] && export _APP_VER="$(echo "${_result}")" && echo "${_APP_VER}"
}
function _extract_log_last_start() {
    local _log_path="$1"
    _head "LOGS" "Instance start time from jmx.json"
    local _tz="$(_find_and_cat "jmx.json" 2>/dev/null | _get_json "java.lang:type=Runtime,SystemProperties,key=user.timezone,value")"
    [ -z "${_tz}" ] && _tz="$(_find_and_cat "sysinfo.json" 2>/dev/null | _get_json "nexus-properties,user.timezone" | _rg '"([^"]+)' -o -r '$1')"
    local _st_ms="$(_find_and_cat jmx.json 2>/dev/null | _get_json "java.lang:type=Runtime,StartTime")"
    local _up_ms="$(_find_and_cat jmx.json 2>/dev/null | _get_json "java.lang:type=Runtime,Uptime")"
    local _st=""
    local _zip_taken_at=""
    if [ -n "${_st_ms}" ]; then
        _st="$(python3 -c "import sys,datetime;print(datetime.datetime.utcfromtimestamp(float(${_st_ms})/1000).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]+\" UTC\")")"
        _zip_taken_at="$(python3 -c "import sys,datetime;print(datetime.datetime.utcfromtimestamp(float($((${_st_ms} + ${_up_ms})))/1000).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]+\" UTC\")")"
    fi
    echo '```'
    echo "Last start time: ${_st}"
    echo "Zip taken time : ${_zip_taken_at}"
    echo "Server Timezone: ${_tz}"
    echo '```'
    _head "LOGS" "Instance start time from ${_log_path}"
    echo '```'
    _check_log_stop_start "${_log_path}"
    echo "# NOTE: slow/hang startup can be caused by org.apache.lucene.util.IOUtils.getFileStore as it checks all mount points of the OS (even app is not using)"
    echo '```'
}
function _check_log_stop_start() {
    local _log_path="$1"
    [ -z "${_log_path}" ] && _log_path="$(find . -maxdepth 3 -type f -print | grep -m1 -E "/(${_NXRM_LOG}|${_NXIQ_LOG}|server.log)$")"
    [ -z "${_log_path}" ] && return 1
    [ ! -s "${_log_path}" ] && _log_path="-g \"${_log_path}\""
    # NXRM2 stopping/starting, NXRM3 stopping/starting, IQ stopping/starting (IQ doesn't clearly say stopped so that checking 'Stopping')
    # NXRM2: org.sonatype.nexus.bootstrap.jetty.JettyServer - Stopped
    _rg --no-filename '(org.sonatype.nexus.bootstrap.jsw.JswLauncher - Stopping with code:|org.eclipse.jetty.server.AbstractConnector - Stopped ServerConnector|org.sonatype.nexus.events.EventSubscriberHost - Initialized|org.sonatype.nexus.webapp.WebappBootstrap - Initialized|org.eclipse.jetty.server.Server - Started|Started InstrumentedSelectChannelConnector|Received signal: SIGTERM|org.sonatype.nexus.extender.NexusContextListener - Uptime:|org.sonatype.nexus.extender.NexusLifecycleManager - Shutting down|org.sonatype.nexus.extender.NexusLifecycleManager - Stop KERNEL|org.sonatype.nexus.bootstrap.jetty.JettyServer - Stopped|org.sonatype.nexus.pax.logging.NexusLogActivator - start|com.sonatype.insight.brain.service.InsightBrainService - Stopping Nexus IQ Server|Disabled session validation scheduler|Initializing Nexus IQ Server)' ${_log_path} | sort | uniq | tail -n10
}
function _head() {
    local _X="###"
    if [ "$1" == "WARN" ]; then
        _X="##"
    elif [ "$1" == "INFO" ]; then
        _X="###"
    elif [ "$1" == "NOTE" ]; then
        _X="####"
    fi
    echo "  "
    echo "${_X} $*" #| sed -E 's/([(){}_])/\\\1/g'
    echo "  "
}
function _code() {
    local _text="$1"
    local _style="$2"
    local _last_echo_en="${3-"\\n"}"
    echo '```'${_style}
    echo "${_text}"
    echo '```'
    echo -en "${_last_echo_n}"
}
function _jira() {
    local _id="$1"
    local _sfx="${2:-"\\n"}"
    echo -e -n "[${_id}](https://sonatype.atlassian.net/browse/${_id})${_sfx}"
}
function _basic_check() {
    local _required_app_ver_regex="${1}"    # Can't include " " "\d" etc.
    local _required_file="${2}"
    local _level="${3:-"INFO"}"
    local _message="${4}"
    if [ -n "${_required_app_ver_regex}" ]; then
        local _ver="$(_app_ver)"
        [ -z "${_ver}" ] && _head "INFO" "Can not run ${FUNCNAME[1]} as no _APP_VER / _APP_VER_OVERWRITE detected" && return 8
        # NOTE: No message if version doesn't match but just skip.
        [ -n "${_ver}" ] && [[ ! "${_ver}" =~ ${_required_app_ver_regex} ]] && return 9
    fi
    if [ -n "${_required_file}" ] && [ ! -s "${_required_file}" ]; then
        # ${FUNCNAME[1]} is to get the caller function name
        [ -z "${_message}" ] && _message="Can not run ${FUNCNAME[1]} as no ${_required_file}"
        _head "${_level}" "${_message}"
        return 1
    fi
    return 0
}
# NOTE: this function is not so fast
function _size_check() {
    local _file_path="$1"
    local _log_threshold_bytes="${2:-"${_LOG_THRESHOLD_BYTES:-0}"}"
    local _file_size="$(_actual_file_size "${_file_path}")"
    [ -n "${_file_size}" ] && [ ${_file_size} -gt 0 ] && [ ${_file_size} -le ${_log_threshold_bytes} ] && return 0
    return 1
}
function _test_template() {
    local _bad_result="$1"
    local _level="$2"
    local _message="$3"
    local _note="$4"
    local _style="$5"
    [ -z "${_bad_result}" ] && return 0
    [ "${_bad_result}" == "0" ] && return 0
    _head "${_level}" "${_message}"
    echo '```'${_style}
    echo "${_bad_result}"
    [ -n "${_note}" ] && echo -e "# ${_note}"
    echo '```'
    return 1
}
function _test_tmpl_auto() {
    local _bad_result="$1"
    local _warn_if_gt="$2"
    local _err_if_gt="$3"
    local _message="$4"
    local _note="$5"
    local _style="$6"
    [ -z "${_bad_result}" ] && return 0
    local _level="INFO"
    local _wc="$(echo "${_bad_result}" | wc -l | tr -d '[:space:]')"
    if [ ${_wc:-0} -gt ${_err_if_gt:-0} ]; then
        _level="ERROR"
    elif [ ${_wc:-0} -gt ${_warn_if_gt:-0} ]; then
        _level="WARN"
    fi
    _test_template "${_bad_result}" "${_level}" "${_message}" "${_note}" "${_style}"
    return $?
}


### Extracts ###################################################################
function _split_log() {
    local _log_path="$1"
    local _start_log_line=""
    [ -z "${_log_path}" ] && return 1
    if [[ "${_log_path}" =~ (nexus)[^*]*log[^*]* ]]; then
        #_start_log_line=".*org.sonatype.nexus.(webapp.WebappBootstrap|events.EventSubscriberHost) - Initialized"  # NXRM2 (if no DEBUG)
        _start_log_line="(.*org.sonatype.nexus.pax.logging.NexusLogActivator - start|.*org.sonatype.nexus.events.EventSubscriberHost - Initialized)" # NXRM3|NXRM2
    elif [[ "${_log_path}" =~ (clm-server)[^*]*log[^*]* ]]; then
        _start_log_line=".* Initializing Nexus IQ Server .*"   # IQ
    fi
    if [ -n "${_start_log_line}" ]; then
        if _size_check "${_log_path}" "$((${_LOG_THRESHOLD_BYTES} * 100))"; then
            f_splitByRegex "${_log_path}" "${_start_log_line}" "_split_logs"
        else
            _LOG "WARN" "Not doing f_splitByRegex for '${_log_path}' as the size is larger than _LOG_THRESHOLD_BYTES:${_LOG_THRESHOLD_BYTES} * 100"
        fi
    fi
}
function e_app_log() {
    local _log_path="$1"
    if [ -z "${_log_path}" ]; then
        _log_path="$(find . -maxdepth 3 -type f -print | grep -m1 -E "/(${_NXRM_LOG}|${_NXIQ_LOG}|server.log)$")"
    fi
    [ ! -s "${_log_path}" ] && return 1

    _split_log "${_log_path}"
    local _since_last_restart="$(ls -1r _split_logs/* 2>/dev/null | head -n1)"
    local _excludes="(WARN .+ high disk watermark|This is NOT an error|Attempt to access soft-deleted blob .+nexus-repository-docker|CacheInfo missing for)"
    if [ -n "${_since_last_restart}" ]; then
        f_topErrors "${_since_last_restart}" "" "" "${_excludes}" >${_FILTERED_DATA_DIR%/}/f_topErrors.out
    elif _size_check "${_log_path}"; then
        # TODO: this one is slow
        _TOP_ERROR_MAX_N=10000 f_topErrors "${_log_path}" "" "" "${_excludes}" >${_FILTERED_DATA_DIR%/}/f_topErrors.out
    else
        _LOG "WARN" "Not doing f_topErrors for '${_log_path}' as the size is larger than _LOG_THRESHOLD_BYTES:${_LOG_THRESHOLD_BYTES}"
    fi
}
function e_requests() {
    local _req_log_path="$(find . -maxdepth 3 -name "${_REQUEST_LOG:-"request.log"}" | sort -r | head -n1 2>/dev/null)"
    if _size_check "${_req_log_path}" "$((${_LOG_THRESHOLD_BYTES} * 10))"; then
        # Running in background as this can take long time
        f_request2csv "${_req_log_path}" ${_FILTERED_DATA_DIR%/}/request.csv 2>/dev/null &
        _rg "${_DATE_FMT_REQ}:(\d\d).+(/rest/|/api/)([^/ =?]+/?[^/ =?]+/?[^/ =?]+/?[^/ =?]+/?[^/ =?]+/?)" --no-filename -g ${_REQUEST_LOG} -o -r '"$1:" "$2$3"' | _replace_number | sort -k1,2 | uniq -c > ${_FILTERED_DATA_DIR%/}/agg_requests_count_hour_api.ssv
    else
        _LOG "WARN" "Not converting '${_req_log_path:-"empty"}' to CSV (and agg_requests_count_hour_api) because no ${_REQUEST_LOG:-"request.log"} or larger than _LOG_THRESHOLD_BYTES:${_LOG_THRESHOLD_BYTES} * 10"
    fi
}
function e_threads() {
    f_threads "info/threads.txt" "" "" "_threads" "Y" &>${_FILTERED_DATA_DIR%/}/f_threads.out
}
function e_configs() {
    _extract_configs >${_FILTERED_DATA_DIR%/}/extracted_configs.md
    _extract_log_last_start >${_FILTERED_DATA_DIR%/}/extracted_log_last_start.md
    _search_json "sysinfo.json" "system-filestores" > ${_FILTERED_DATA_DIR%/}/system-filestores.json
}

### Reports ###################################################################
function r_configs() {
    if [ -s "${_FILTERED_DATA_DIR%/}/extracted_log_last_start.md" ]; then
        cat ${_FILTERED_DATA_DIR%/}/extracted_log_last_start.md
    fi
}
function r_audits() {
    _head "AUDIT" "Top 20 'domain','type' from ${_AUDIT_LOG}"
    echo '```'
    _rg --no-filename '"domain":"([^"]+)", *"type":"([^"]+)"' -o -r '$1,$2' -g "${_AUDIT_LOG}" | sort | uniq -c | sort -nr | head -n20
    echo "NOTE: taskblockedevent would mean another task is running (dupe tasks?)."
    echo "      repositorymetadataupdatedevent (NXRM) and governance.repository.quarantine (IQ) could be quarantine."
    echo '```'
}
function r_threads() {
    _basic_check "" "${_FILTERED_DATA_DIR%/}/f_threads.out" || return
    _head "THREADS" "Result of f_threads from ${_FILTERED_DATA_DIR%/}/f_threads.out"
    _code "$(cat ${_FILTERED_DATA_DIR%/}/f_threads.out)" "" ""
}
function r_requests() {
    local _hour="$1"
    local _where=""
    # Probably don't want to spend too much time for this function
    _size_check "${_FILTERED_DATA_DIR%/}/request.csv" "$((${_LOG_THRESHOLD_BYTES} * 2))" || return 11
    [ -n "${_hour}" ] && _where="WHERE date like '%2023:${_hour}%'"
    # TODO: RM 3.61 may have some new metrics for unique users 'nexus.analytics.unique_user_authentications_count'
    _head "REQUESTS" "Counting host_ip + user per hour for last 10 ('-' in user is counted as 1)"
    _code "$(_q -H "SELECT substr(date,1,14) as hour, count(*), count(distinct clientHost), count(distinct user), count(distinct clientHost||user) from ${_FILTERED_DATA_DIR%/}/request.csv ${_where} group by 1 order by hour desc LIMIT 10")" "" ""
    _head "REQUESTS" "Request counts per hour from ${_REQUEST_LOG}"
    _code "$(_rg "${_DATE_FMT_REQ}:${_hour:-"\\d\\d"}" -o --no-filename -g ${_REQUEST_LOG} | _bar)"
    [ -s "${_FILTERED_DATA_DIR%/}/request.csv" ] || return
    # first and end time per user
    #_q -H "select clientHost, user, count(*), min(date), max(date) from ${_FILTERED_DATA_DIR%/}/request.csv group by 1,2"
    _head "REQUESTS" "Counting repository, method, status code for last 1000 requests and top 20 (NOTE: 200 status does not mean the request completed (especially small bytesSent or headerContentLength)"
    _code "$(_rg "\[\d\d/[^/]+/20\d\d:(${_hour:-"\\d\\d"}).+ \"(\S+) .*/(repository|rest/integration/repositories/[^/]+)/([^/]+)/\S* HTTP/...\" (\d)" -o -r '${1} ${4} ${2} ${5}xx' -g ${_REQUEST_LOG} --no-filename | tail -n1000 | sort | uniq -c | sort -nr | head -n20)"
}
function r_list_logs() {
    _head "APP LOG" "max 100 *.log files' start and end (start time, end time, difference(sec), filesize)"
    _code "$(f_list_start_end "*.log")"

    _head "NOTE" "To split logs by hour:"
    echo '```'
    echo "_SPLIT_BY_REGEX_SORT=\"Y\" f_splitByRegex \"./log/${_NXRM_LOG}\" \"^${_DATE_FORMAT}.\d\d\" \"_hourly_logs\""
    echo "f_extractFromLog \"./log/${_NXRM_LOG}\" \"^${_DATE_FORMAT}.XX\" \"^${_DATE_FORMAT}.YY\" > extracted_XX_YY.out"
    echo "_SPLIT_BY_REGEX_SORT=\"Y\" f_splitByRegex \"./log/${_REQUEST_LOG}\" \"${_DATE_FMT_REQ}:\d\d\" \"_hourly_logs_req\""
    echo "f_extractFromLog \"./log/${_REQUEST_LOG}\" \"${_DATE_FMT_REQ}.XX\" \"${_DATE_FMT_REQ}.YY\" > extracted_req_XX_YY.out"
    echo '```'
}

### Tests ###################################################################
function t_basic() {
    if ! _test_template "$(find . -maxdepth 3 -type f -name truncated | grep 'truncated')" "WARN" "'truncated' found under $(realpath .) with maxdepth 3"; then
        echo '```'
        _rg -l "TRUNCATE" -g '*.log' -g '*.json'
        echo '```'
    fi
    if ! find . -maxdepth 5 -type f -name sysinfo.json | grep -q 'sysinfo.json'; then
        _head "ERROR" "No 'sysinfo.json' under $(realpath .) with maxdepth 5"
    fi
    if ! find . -maxdepth 5 -type f -name jmx.json | grep -q 'jmx.json'; then
        _head "ERROR" "No 'jmx.json' under $(realpath .) with maxdepth 5 (NEXUS-44017)"
    fi
}
function t_system() {
    _basic_check "" "${_FILTERED_DATA_DIR%/}/extracted_configs.md" || return
    _test_template "$(_rg 'AvailableProcessors.?: *[1-3]\b' ${_FILTERED_DATA_DIR%/}/extracted_configs.md)" "WARN" "AvailableProcessors (CPU) might be too low (-XX:ActiveProcessorCount=N ?)" "https://bugs.java.com/bugdatabase/view_bug?bug_id=8140793"
    _test_template "$(_rg 'TotalPhysicalMemorySize.?: *(.+ MB|[1-7]\.\d+ GB)' ${_FILTERED_DATA_DIR%/}/extracted_configs.md)" "WARN" "TotalPhysicalMemorySize (RAM) might be too low"
    # TODO: compare TotalPhysicalMemorySize and CommittedVirtualMemorySize
    _test_template "$(rg 'MaxFileDescriptorCount.?: *\d{4}\b' ${_FILTERED_DATA_DIR%/}/extracted_configs.md)" "WARN" "MaxFileDescriptorCount might be too low"
    _test_template "$(rg 'SystemLoadAverage.?: *([4-9]\.|\d\d+)' ${_FILTERED_DATA_DIR%/}/extracted_configs.md)" "WARN" "SystemLoadAverage might be too high (check number of CPUs)"
    local _xms="$(rg -i '\-Xms([a-zA-Z0-9]+)' -o -r '$1' -g jmx.json --no-filename | tail -n1)"
    local _xmx="$(rg -i '\-Xmx([a-zA-Z0-9]+)' -o -r '$1' -g jmx.json --no-filename | tail -n1)"
    if [ -z "${_xmx}" ]; then
        _head "WARN" "Xmx might not be set in jmx.json SystemProperties"
    fi
    if [ "${_xms}" != "${_xmx}" ]; then
        _test_template "$(rg -i '\-Xm[sx]' -g jmx.json)" "WARN" "Xms (${_xms}) value might not be same as Xmx (${_xmx})"
    fi
    local _maxMemory="$(rg '"maxMemory"\s*:\s*(\d+)' -g sysinfo.json --no-filename -o -r '$1' | sort | tail -n1)"
    if [ ${_maxMemory:-0} -lt 3221225472 ]; then
        _head "WARN" "maxMemory (heap|Xmx) might be too low (if docker/pod: NEXUS-35218)"
    elif [ ${_maxMemory:-0} -gt 34359738368 ]; then
        _head "WARN" "maxMemory (heap|Xmx) might be too large https://confluence.atlassian.com/jirakb/do-not-use-heap-sizes-between-32-gb-and-47-gb-in-jira-compressed-oops-1167745277.html"
    fi
    _test_template "$(rg -g jmx.json -q -- '-XX:\+UseG1GC' || rg -g jmx.json -- '-Xmx')" "WARN" "No '-XX:+UseG1GC' for below Xmx (only for Java 8)" "Also consider using -XX:+ExplicitGCInvokesConcurrent"
    _test_template "$(rg -g jmx.json -q -- '-XX:MaxDirectMemorySize' || rg -g jmx.json -- '-Xmx')" "WARN" "No '-XX:MaxDirectMemorySize' (better set '-Djdk.nio.maxCachedBufferSize=262144' as well)"
    _test_template "$(rg -g jmx.json 'UseCGroupMemoryLimitForHeap')" "WARN" "UseCGroupMemoryLimitForHeap is specified (not required from 8v191)"
    _test_template "$(rg -g jmx.json 'MaxMetaspaceSize')" "WARN" "MaxMetaspaceSize is specified"
    _test_template "$(rg -g jmx.json -- '-Djavax\.net\.ssl..+=')" "WARN" "javax.net.ssl.* (eg. trustStore) is used in jmx.json"
    _test_template "$(rg -g jmx.json 'add-exports=' | rg -v 'java.base/sun.security.\S+=ALL-UNNAMED')" "WARN" "add-exports=java.base/sun.security.\S+=ALL-UNNAMED might be missing in jmx.json (eg: NEXUS-44004)"   # TODO: this is wrong
    _test_template "$(rg -g jmx.json -m1 '1\.8\.0.(29[2-9]|30[01])\b')" "WARN" "Java version might be 1.8.0_292, which has critical bug: https://bugs.java.com/bugdatabase/view_bug?bug_id=JDK-8266929 (JDK-8266261)" "java.security.NoSuchAlgorithmException: unrecognized algorithm name: PBEWithSHA1AndDESede"

    if ! _rg -g jmx.json -q -w 'x86_64'; then
        if ! _rg -g jmx.json -q -w 'amd64'; then
            _head "WARN" "No 'x86_64' or 'amd64' found in jmx.json. Might be 32 bit Java or Windows, check jvm.log or Arch in jmx.json"
        fi
    fi
    if _rg -g sysinfo.json -q '(DOCKER_TYPE|"SONATYPE_INTERNAL_HOST_SYSTEM"\s*:\s*"Docker"|"container"\s*:\s*"oci")'; then
        _head "WARN" "Might be installed on DOCKER"
    fi
    if _rg -g sysinfo.json -q 'KUBERNETES_'; then
        _head "WARN" "Might be installed on KUBERNETES (shouldn't use H2/OrientDB)"
    fi
}
function t_pg_config() {
    local _pg_cfg_glob="${1:-"dbFileInfo.txt"}"
    local _excl_regex="${2-"\\\s*[:=]\\\s*"}"   #\",\"[^\"]+\",
    [ ! -s "${_pg_cfg_glob}" ] && _pg_cfg_glob="-g ${_pg_cfg_glob}"
    #_test_template "$(rg --no-filename -i '^["]?max_connections'${_excl_regex}'(\d{1,2}|100)\b' ${_pg_cfg_glob})" "WARN" "max_connections might be too small"
    #TODO: _test_template "$(rg --no-filename -i '^["]?shared_buffers'${_excl_regex}'([1-4]\d{1,5}|\d{1,5}|[1-3]\d{1,3}kb|\d{1,6}kb|[1-3]\d{1,3}mb|\d{1,3}mb|[1-3]gb)\b' ${_pg_cfg_glob})" "WARN" "shared_buffers might be too small"
    _test_template "$(rg --no-filename -i "^\s*['\"]?(max_connections|shared_buffers|work_mem|effective_cache_size|synchronous_standby_names)\b" ${_pg_cfg_glob})" "WARN" "Please review DB configs"
}
function t_mounts() {
    _basic_check "" "${_FILTERED_DATA_DIR%/}/system-filestores.json" || return
    # language=Python
    python3 -c "import sys,json
with open('${_FILTERED_DATA_DIR%/}/system-filestores.json') as f:
    fsDicts=json.load(f)
for key in fsDicts['system-filestores']:
    if fsDicts['system-filestores'][key]['description'].startswith(('/sys', '/proc', '/boot', '/tmp', '/dev', '/run')):
        continue
    if fsDicts['system-filestores'][key]['totalSpace'] >= (4 * 1024 * 1024 * 1024) and fsDicts['system-filestores'][key]['usableSpace'] < (4 * 1024 * 1024 * 1024):
        print(fsDicts['system-filestores'][key])
" > /tmp/${FUNCNAME[0]}_$$.out
    _test_template "$(cat /tmp/${FUNCNAME[0]}_$$.out)" "WARN" "some of 'usableSpace' might be less than 8GB" "NOTE: 'No space left on device' can be also caused by Inode, which won't be shown in above."

    local _workingDirectory="$(_search_json "sysinfo.json" "nexus-configuration,workingDirectory" | _rg -o -r '$1' '"(/[^"]+)"')"
    local _display_result=""
    local _result="$(_is_mount "${_workingDirectory%/}" "${_FILTERED_DATA_DIR%/}/system-filestores.json")"
    if [ -n "${_result}" ]; then
        _head "WARN" "workingDirectory:${_workingDirectory} might be nfs|cifs"
        _display_result="Y"
    else
        _result="$(_is_mount "${_workingDirectory%/}" "${_FILTERED_DATA_DIR%/}/system-filestores.json" "(overlay)")"
        if [ -n "${_result}" ]; then
            _head "INFO" "workingDirectory:${_workingDirectory} might be in overlay"
            _display_result="Y"
        fi
    fi
    if [ -n "${_display_result}" ]; then
        echo '```'
        echo "${_result}"
        # NOTE: 'bs=1 count=0 seek=104857600' is for creating one 100MB file very quickly
        echo "# Command examples to check (disk) performance with 100MB file:"
        echo "    time sudo -u <nexus> dd if=/dev/zero of=\${_workingDirectory}/tmp/test100m.img bs=100M count=1 oflag=dsync
    time curl -D- -u admin:admin123 -T \${_workingDirectory}/tmp/test100m.img -k http://localhost:8081/repository/\${_rawHosted}/test/ --progress-bar | tee /dev/null
    # Download test: creating a dummy file very quickly with seek= (note: /public may not work from 3.68)
    sudo -u <nexus> dd if=/dev/zero of=\${installDirectory}/public/test100m.img bs=1 count=0 seek=104857600
    time curl -D- -o/dev/null http://localhost:8081/test100m.img"
        echo '```'
    fi
}

# TODO: For this one, checking without size limit (not _rg)?
function t_oome() {
    # audit.log can contains `attribute.changes` which contains large test and some Nuget package mentions OutOfMemoryError
    _test_template "$(_RG_MAX_FILESIZE="6G" _rg 'java.lang.OutOfMemoryError:.+' -m1 -B1 -g "${_LOG_GLOB}" -g '*.log.gz' -g '\!jvm.log' -g '\!audit*log*' | sort | uniq)" "ERROR" "OutOfMemoryError detected from ${_LOG_GLOB} (Xms is too small?)"
}
function t_sofe() {
    _test_template "$(_RG_MAX_FILESIZE="6G" _rg 'java.lang.StackOverflowError:.+' -m1 -B1 -g "${_LOG_GLOB}" -g '*.log.gz' -g '\!jvm.log' -g '\!audit*log*' | sort | uniq)" "ERROR" "StackOverflowError detected from ${_LOG_GLOB}"
}
function t_psqlexception() {
    _test_template "$(_RG_MAX_FILESIZE="6G" _rg '^Caused by: org\.postgresql\.util\.PSQLException.+' -o -g "${_LOG_GLOB}" -g '*.log.gz' -g '\!jvm.log' -g '\!audit*log*'| sort | uniq -c | sort -nr | rg '^\s*\d\d+')" "WARN" "Many 'PSQLException' detected from ${_LOG_GLOB}"
}
function t_fips() {
    _test_template "$(_rg -m1 '(KeyStore must be from provider SunPKCS11-NSS-FIPS|PBE AlgorithmParameters not available)' -g "${_LOG_GLOB}")" "WARN" "FIPS mode might be detected from ${_LOG_GLOB}" "-Dcom.redhat.fips=false"
}
function t_errors() {
    if [ -s "${_FILTERED_DATA_DIR%/}/f_topErrors.out" ]; then
        if _test_template "$(_rg -q '^\s*\d\d+.+\s+ERROR\s+' ${_FILTERED_DATA_DIR%/}/f_topErrors.out && cat ${_FILTERED_DATA_DIR%/}/f_topErrors.out)" "ERROR" "Many ERROR detected from ${_FILTERED_DATA_DIR%/}/f_topErrors.out (since last start if restarted)"; then
            _test_template "$(_rg '^\s*\d\d\d+.+\s+WARN\s+' ${_FILTERED_DATA_DIR%/}/f_topErrors.out && cat ${_FILTERED_DATA_DIR%/}/f_topErrors.out)" "WARN" "Many WARN detected from ${_FILTERED_DATA_DIR%/}/f_topErrors.out (since last start if restarted)"
        fi
    fi
    #_test_template "$(_rg '([^ ()]+\.[a-zA-Z0-9]+Exception):' -o -r '$1' --no-filename -g "${_LOG_GLOB}" | sort | uniq -c | sort -nr | _rg '^\s*\d\d+' | head -n10)" "WARN" "Many exceptions detected from ${_LOG_GLOB}"
    local _dir="$(find . -maxdepth 3 -type d -name "_split_logs" -print -quit)"
    if [ -n "${_dir%/}" ]; then
        local _num="$(ls -1 ${_dir%/}/ | _line_num)"
        if [ 2 -lt "${_num}" ]; then
            # TODO: some important issue uses WARN.
            _test_template "$(_rg -m2 "^${_DATE_FORMAT}.+ (ERROR |WARN .+DataStoreManagerImpl)" ${_dir%/}/)" "WARN" "First two ERRORs after multiple restart (${_dir%/} | ${_num})"
        fi
    fi
}
function t_threads() {
    _test_template "$(rg -g threads.txt -i -w "deadlock" | rg -v 'New Relic Deadlock Detector')" "ERROR" "deadlock found in threads.txt"
    local _dir="$(find . -maxdepth 3 -type d -name "_threads" -print -quit)"
    if [ -z "${_dir}" ]; then
        _head "INFO" "Can not run ${FUNCNAME[0]} as no _threads directory."
        return
    fi
    if type _threads_extra_check &>/dev/null; then
        _test_template "$(_threads_extra_check "${_dir}")" "WARN" "${_dir} may have some known performance issue(s)"
    fi
}
function t_requests() {
    _basic_check "" "${_FILTERED_DATA_DIR%/}/request.csv" || return
    local _query="SELECT requestURL, statusCode, count(*) as c, avg(bytesSent) as avg_bytes, max(bytesSent) as max_bytes, sum(bytesSent) as sum_bytes, avg(elapsedTime) as avg_elapsed, max(elapsedTime) as max_elapsed, sum(elapsedTime) as sum_elapsed FROM ${_FILTERED_DATA_DIR}/request.csv WHERE (statusCode like '5%') GROUP BY requestURL, statusCode HAVING (c > 100 or avg_elapsed > 1000 or max_elapsed > 7000) ORDER BY sum_elapsed DESC LIMIT 10"
    if _q -H "${_query}" 2>/dev/null > ${_FILTERED_DATA_DIR%/}/agg_requests_5xx_slow.ssv; then
        local _line_num="$(cat ${_FILTERED_DATA_DIR%/}/agg_requests_5xx_slow.ssv | wc -l | tr -d '[:space:]')"
        if [ -n "${_line_num}" ] && [ ${_line_num} -gt 5 ]; then
            _test_template "$(head -n10 ${_FILTERED_DATA_DIR%/}/agg_requests_5xx_slow.ssv)" "WARN" "Many slow 5xx status in ${_FILTERED_DATA_DIR}/request.csv" "${_query}"
        fi
    fi

    # TODO: Using agg_requests_count_hour_api.ssv as SQLite does not have regex replace (so that can include elapsed)
    if [ -s "${_FILTERED_DATA_DIR%/}/agg_requests_count_hour_api.ssv" ]; then
        # Greater than 1 request per sec APIs. NXRM3's /rest/v1/status is light and fast so excluding
        local _query="SELECT c2 as hour, c3 as api, sum(c1) as c FROM ${_FILTERED_DATA_DIR%/}/agg_requests_count_hour_api.ssv WHERE api not like '%/rest/v1/status%' GROUP BY hour, api HAVING c > 3600 ORDER BY c DESC LIMIT 40"
        _test_tmpl_auto "$(_q -d" " -T  --disable-double-double-quoting "${_query}")" "2" "5" "Potentially too frequent API-like requests per hour (${_FILTERED_DATA_DIR%/}/agg_requests_count_hour_api.ssv)" \
          "_q -H \"SELECT substr(date,1,14) as hour, count(*), avg(elapsedTime), max(elapsedTime), sum(elapsedTime) FROM ${_FILTERED_DATA_DIR%/}/request.csv where requestURL like '%/<REPLACE_HERE>/%' GROUP by hour HAVING max(elapsedTime) > 2000\""
    fi

    # NOTE: can't use headerContentLength as some request.log doesn't have it
    local _excludes="GET %/maven-metadata.xml %"
    f_reqsFromCSV "request.csv" "7000" "" "20" "AND requestURL NOT LIKE '${_excludes}'" 2>/dev/null >${_FILTERED_DATA_DIR%/}/agg_requests_top20_slow_GET.out
    _test_template "$(_rg -q '\s+GET\s+' -m1 ${_FILTERED_DATA_DIR%/}/agg_requests_top20_slow_GET.out && cat ${_FILTERED_DATA_DIR%/}/agg_requests_top20_slow_GET.out)" "WARN" "Top 20 slow downloads excluding '${_excludes}' from ${_FILTERED_DATA_DIR}/request.csv"
}


main() {
    local _result_file="${1:-"/dev/stdout"}"
    _prerequisites || return $?
    f_run_extract || return $?
    jobs -l | grep -vw "Done"; sleep 1 # Just in case
    echo "# $(basename "$BASH_SOURCE" ".sh") results" > "${_result_file}"
    echo "[[toc]]" >> "${_result_file}"
    echo "" >> "${_result_file}"
    f_run_tests >> "${_result_file}"|| return $?
    f_run_report >> "${_result_file}"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    if [[ "$1" =~ ^(-h|help|--help)$ ]]; then
        _usage | less
        exit
    fi
    main > "$(basename "$BASH_SOURCE" .sh).md"
fi
