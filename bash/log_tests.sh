#!/usr/bin/env bash

usage() {
    cat << EOF
Implementing test cases (like programing lanugage's Unit tests) with bash.

All functions start with "e_" are for extracting data, so that tests do not need to check large log files repeatedly.
All functions start with "r_" are for reporting, just displaying some useful, good-to-know information with Markdown.
All functions start with "t_" are actual testing.

REQUIREMENTS:
    bash, not tested with zsh.
    Please install below: (eg: 'brew install coreutils ripgrep jq q')
        coreutils (realpath, timeout)
        rg  https://github.com/BurntSushi/ripgrep
        jq  https://stedolan.github.io/jq/download/
        q   https://github.com/harelba/q
    Also, please put below in the PATH:
        https://github.com/bitly/data_hacks/blob/master/data_hacks/bar_chart.py (TODO: project is no longer updated)

TARGET OS:
    macOS Mojave
EOF
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
else
    _NXRM_LOG="${_NXRM_LOG:-"nexus.log"}"
    _NXIQ_LOG="${_NXIQ_LOG:-"clm-server.log"}"
    _REQUEST_LOG="${_REQUEST_LOG:-"request.log"}"
fi
: ${_LOG_THRESHOLD_BYTES:=125829120}    # 120MB (large number significantly affects to the time)
: ${_FILTERED_DATA_DIR:="./_filtered"}
: ${_LOG_GLOB:="*.log"}

# Aliases (can't use alias in shell script, so functions)
_rg() {
    rg -z "$@" 2>/tmp/_rg_last.err
}
_q() {
    q -O -d"," -T --disable-double-double-quoting "$@" 2>/tmp/_q_last.err
}
_runner() {
    local _pfx="$1"
    local _n="${2:-"3"}"
    local _tmp="$(mktemp -d)"
    _LOG "INFO" "Executing ${FUNCNAME[1]}->${FUNCNAME} $(typeset -F | grep "^declare -f ${_pfx}" | wc -l  | tr -d "[:space:]") functions."
    for _t in $(typeset -F | grep "^declare -f ${_pfx}" | cut -d' ' -f3); do
        if ! _wait_jobs "${_n}"; then
            _LOG "ERROR" "${FUNCNAME} failed."
            return 11
        fi
        _LOG "DEBUG" "Started ${_t}"    # TODO: couldn't display actual command in jogs -l command
        eval "${_t} > ${_tmp}/${_t}.out;_LOG DEBUG \"Completed ${_t} (\$?)\"" &
    done
    _wait_jobs 0
    cat ${_tmp}/${_pfx}*.out
    _LOG "INFO" "Completed ${FUNCNAME[1]}->${FUNCNAME}."
}

function f_run_extract() {
    [ -d "${_FILTERED_DATA_DIR%/}" ] || mkdir -v -p "${_FILTERED_DATA_DIR%/}" || return $?
    #if [ "$(ls -1 "${_FILTERED_DATA_DIR%/}")" ]; then
    #    _LOG "INFO" "${_FILTERED_DATA_DIR%/} is not empty so not extracting."
    #    return
    #fi
    _runner "e_"
}

function f_run_report() {
    echo "# ${FUNCNAME} results"
    echo ""
    if [ ! -s ${_FILTERED_DATA_DIR%/}/extracted_configs.md ]; then
        _head "INFO" "No ${_FILTERED_DATA_DIR%/}/extracted_configs.md"
    else
        cat ${_FILTERED_DATA_DIR%/}/extracted_configs.md
    fi
    _runner "r_"
}

function f_run_tests() {
    echo "# ${FUNCNAME} results"
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
    _search_json "jmx.json" "java.lang:type=Runtime,Name" # to find PID and hostname (in case no HOSTNAME env set)
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

    _head "CONFIG" "database related (TODO: IQ)"
    echo '```'
    _find_and_cat "config_ds_info.properties" 2>/dev/null
    echo '```'

    _head "CONFIG" "application related"
    echo '```'
    echo "sonatypeWork: \"$(_working_dir)\""
    echo "app version: \"$(_app_ver)\""
    echo '```'
}
: ${_WORKING_DIR:="<null>"}   # either workingDirectory or sonatypeWork
function _working_dir() {
    [ -n "${_WORKING_DIR}" ] && [ "${_WORKING_DIR}" != "<null>" ] && echo "${_WORKING_DIR}" && return
    local _working_dir_line="$(_search_json "sysinfo.json" "nexus-configuration,workingDirectory" || _search_json "sysinfo.json" "install-info,sonatypeWork")"
    local _result="$(echo "${_working_dir_line}" | _rg ': "([^"]+)' -o -r '$1')"
    [ -n "${_result}" ] && [ "${_result}" != "<null>" ] && _WORKING_DIR="$(echo "${_result}")" && echo "${_WORKING_DIR}"
}
: ${_APP_VER:="<null>"}   # 3.36.0-01
function _app_ver() {
    [ -n "${_APP_VER}" ] && [ "${_APP_VER}" != "<null>" ] && echo "${_APP_VER}" && return
    local _app_ver_line="$(_search_json "sysinfo.json" "nexus-status,version" || _search_json "product-version.json" "product-version,version")"
    local _result="$(echo "${_app_ver_line}" | _rg ': "([^"]+)' -o -r '$1')"
    [ -n "${_result}" ] && [ "${_result}" != "<null>" ] && _APP_VER="$(echo "${_result}")" && echo "${_APP_VER}"
}
function _extract_log_last_start() {
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
function _basic_check() {
    local _required_app_ver_regex="${1}"
    local _required_file="${2}"
    local _level="${3:-"INFO"}"
    local _message="${4}"
    if [ -n "${_required_app_ver_regex}" ]; then
        local _ver="$(_app_ver)"
        [ -z "${_ver}" ] && _head "${_level}" "Can not run ${FUNCNAME[1]} as no _APP_VER detected" && return 8
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
function _test_template() {
    local _bad_result="$1"
    local _level="$2"
    local _message="$3"
    local _note="$4"
    local _style="$5"
    [ -z "${_bad_result}" ] && return
    _head "${_level}" "${_message}"
    echo '```'${_style}
    echo "${_bad_result}"
    [ -n "${_note}" ] && echo "# ${_note}"
    echo '```'
    return 1
}


### Extracts ###################################################################
function e_configs() {
    _extract_configs >${_FILTERED_DATA_DIR%/}/extracted_configs.md &
    _extract_log_last_start >${_FILTERED_DATA_DIR%/}/extract_log_last_start.md &
    _search_json "sysinfo.json" "system-filestores" > ${_FILTERED_DATA_DIR%/}/system-filestores.json
}
function e_threads() {
    _NOT_SPLIT_BY_DATE=Y f_threads &>${_FILTERED_DATA_DIR%/}/f_threads.out &
}
function e_app_logs() {
    local _log_path="$(find . -maxdepth 3 -type f -print | grep -m1 -E "/(${_NXRM_LOG}|${_NXIQ_LOG}|server.log)$")"
    local _log_size="$(_actual_file_size "${_log_path}")"
    [ -z "${_log_path}" ] && _log_path="*.log"
    _LOG_GLOB="$(basename ${_log_path} | sed 's/.\///')"

    if [ -n "${_log_size}" ] && [ ${_log_size} -gt 0 ] && [ ${_log_size} -le ${_LOG_THRESHOLD_BYTES} ]; then
        f_topErrors "${_LOG_GLOB}" "" "" "(WARN .+ high disk watermark)" >${_FILTERED_DATA_DIR%/}/f_topErrors.out
    fi
    if [ -s "${_log_path}" ]; then
        local _start_log_line=""
        if [[ "${_log_path}" =~ (nexus)[^*]*log[^*]* ]]; then
            #_start_log_line=".*org.sonatype.nexus.(webapp.WebappBootstrap|events.EventSubscriberHost) - Initialized"  # NXRM2 (if no DEBUG)
            _start_log_line=".*org.sonatype.nexus.pax.logging.NexusLogActivator - start" # NXRM3
        elif [[ "${_log_path}" =~ (clm-server)[^*]*log[^*]* ]]; then
            _start_log_line=".* Initializing Nexus IQ Server .*"   # IQ
        fi
        if [ -n "${_start_log_line}" ]; then
            f_splitByRegex ${_log_path} "${_start_log_line}" "_split_logs" &
        #if [ -n "${_log_size}" ] && [ ${_log_size} -gt 0 ] && [ ${_log_size} -le ${_LOG_THRESHOLD_BYTES} ]; then
        #    echo 'Use: f_splitByRegex '${_log_path}' "'${_start_log_line}'" "_split_logs"'
        fi
    fi
}
function e_req_logs() {
    local _req_log_path="$(find . -maxdepth 3 -name "${_REQUEST_LOG:-"request.log"}" | sort -r | head -n1 2>/dev/null)"
    local _req_log_size="$(_actual_file_size "${_req_log_path}")"
    if [ -n "${_req_log_size}" ] && [ ${_req_log_size} -gt 0 ] && [ ${_req_log_size} -le ${_LOG_THRESHOLD_BYTES} ]; then
        f_request2csv "${_req_log_path}" ${_FILTERED_DATA_DIR%/}/request.csv 2>/dev/null &
    else
        _LOG "INFO" "Not converting "${_req_log_path}" to CSV as no ${_REQUEST_LOG:-"request.log"} or log size (${_req_log_size}) is larger than ${_LOG_THRESHOLD_BYTES}"
    fi
}

### Reports ###################################################################
function r_configs() {
    cat ${_FILTERED_DATA_DIR%/}/extracted_configs*.md
    if [ -s "${_FILTERED_DATA_DIR%/}/extract_log_last_start.md" ]; then
        cat ${_FILTERED_DATA_DIR%/}/extract_log_last_start.md
    fi
}
function r_audits() {
    _head "AUDIT" "Top 20 'domain','type' from audit.log"
    echo '```'
    _rg --no-filename '"domain":"([^"]+)", *"type":"([^"]+)"' -o -r '$1,$2' -g audit.log | sort | uniq -c | sort -nr | head -n20
    echo "NOTE: taskblockedevent would mean another task is running (dupe tasks?). repositorymetadataupdatedevent would mean quarantine."
    echo '```'
}
function r_app_logs() {
    _basic_check "" "${_FILTERED_DATA_DIR%/}/f_topErrors.out" || return
    _head "APP LOG" "Counting WARNs and above, then displaying 10+ occurrences in ${_LOG_GLOB} ${_FILTERED_DATA_DIR%/}f_topErrors.out"
    echo '```'
    _rg -v '^\s*\d\s+' ${_FILTERED_DATA_DIR%/}/f_topErrors.out # NOTE: be careful to modify this. It might hides bar_chart output
    echo '```'
}
function r_threads() {
    _basic_check "" "${_FILTERED_DATA_DIR%/}/f_threads.out" || return
    _head "THREADS" "Result of f_threads from ${_FILTERED_DATA_DIR%/}/f_threads.out"
    echo '```'
    cat ${_FILTERED_DATA_DIR%/}/f_threads.out
    echo '```'
}
function r_requests() {
    _basic_check "" "${_FILTERED_DATA_DIR%/}/request.csv" || return
    # first and end time per user
    #_q -H "select clientHost, user, count(*), min(date), max(date) from ${_FILTERED_DATA_DIR%/}/request.csv group by 1,2"
    _head "REQUESTS" "Counting host_ip + user per hour for last 10 ('-' in user is counted as 1)"
    echo '```'
    _q -H "SELECT substr(date,1,14) as hour, count(*), count(distinct clientHost), count(distinct user), count(distinct clientHost||user) from ${_FILTERED_DATA_DIR%/}/request.csv group by 1 order by hour desc LIMIT 10"
    echo '```'

    _head "REQUESTS" "Request counts per hour from ${_REQUEST_LOG}"
    echo '```'
    _rg "${_DATE_FMT_REQ}:\d\d" -o --no-filename -g ${_REQUEST_LOG} | bar_chart.py
    echo '```'

    echo "### API-like requests per hour from ${_REQUEST_LOG}"
    echo '```'
    #_q -H "select substr(date,1,16) as ten_min, count(*) as c, CAST(avg(elapsedTime) as INT) as avg_elapsed from ${_FILTERED_DATA_DIR%/}/request.csv WHERE (requestURL like '%/service/rest/%' OR requestURL like '%/api/v2/%') GROUP BY ten_min HAVING avg_elapsed > 7000"
    _rg "(${_DATE_FMT_REQ}:\d\d).+(/service/rest/|/api/v2/)" --no-filename -g ${_REQUEST_LOG} -o -r '$1' | bar_chart.py
    echo '```'

    _rg 'HTTP/\d\.\d" 5\d\d\s' --no-filename -g ${_REQUEST_LOG} > ${_FILTERED_DATA_DIR%/}/log_requests_5xx.out
    if [ -s ${_FILTERED_DATA_DIR%/}/log_requests_5xx.out ]; then
        echo "### 5xx statusCode in ${_REQUEST_LOG} (${_FILTERED_DATA_DIR%/}/log_requests_5xx.out)"
        echo '```'
        _rg "${_DATE_FMT_REQ}.\d\d" -o ${_FILTERED_DATA_DIR%/}/log_requests_5xx.out | bar_chart.py
        echo '```'
    fi
}
function r_list_logs() {
    _head "APP LOG" "max 100 *.log files' start and end (start time, end time, difference(sec), filesize)"
    echo '```'
    f_list_start_end "*.log"
    echo '```'

    _head "NOTE" "To split logs by hour:"
    echo '```'
    echo "_SPLIT_BY_REGEX_SORT=\"Y\" f_splitByRegex \"./log/nexus.log\" \"^${_DATE_FORMAT}.\d\d\" \"_hourly_logs\""
    echo "f_extractFromLog \"./log/nexus.log\" \"^${_DATE_FORMAT}.XX\" \"^${_DATE_FORMAT}.YY\" > extracted_XX_YY.out"
    echo "_SPLIT_BY_REGEX_SORT=\"Y\" f_splitByRegex \"./log/request.log\" \"${_DATE_FMT_REQ}:\d\d\" \"_hourly_logs_req\""
    echo "f_extractFromLog \"./log/request.log\" \"${_DATE_FMT_REQ}.XX\" \"${_DATE_FMT_REQ}.YY\" > extracted_req_XX_YY.out"
    echo '```'
}

### Tests ###################################################################
function t_basic() {
    if ! find . -maxdepth 5 -type f -name sysinfo.json | grep -q 'sysinfo.json'; then
        _head "ERROR" "No 'sysinfo.json' found under $(realpath .) with maxdepth 5"
    fi
}
function t_system() {
    _basic_check "" "${_FILTERED_DATA_DIR%/}/extracted_configs.md" || return
    _test_template "$(_rg 'AvailableProcessors: *[1-3]$' ${_FILTERED_DATA_DIR%/}/extracted_configs.md)" "WARN" "AvailableProcessors might be too low"
    _test_template "$(_rg 'TotalPhysicalMemorySize: *(.+ MB|[1-7]\.\d+ GB)' ${_FILTERED_DATA_DIR%/}/extracted_configs.md)" "WARN" "TotalPhysicalMemorySize might be too low"
    _test_template "$(_rg 'MaxFileDescriptorCount: *\d{4}$' ${_FILTERED_DATA_DIR%/}/extracted_configs.md)" "WARN" "MaxFileDescriptorCount might be too low"
    _test_template "$(_rg 'SystemLoadAverage: *([2-9]\.|\d\d+)' ${_FILTERED_DATA_DIR%/}/extracted_configs.md)" "WARN" "SystemLoadAverage might be too high"
    _test_template "$(_rg 'maxMemory: *(.+ MB|[1-3]\.\d+ GB)' ${_FILTERED_DATA_DIR%/}/extracted_configs.md)" "WARN" "maxMemory (heap|Xmx) might be too low"
    _test_template "$(_rg -g jmx.json -q -- '-XX:+UseG1GC' || _rg -g jmx.json -- '-Xmx')" "INFO" "No '-XX:+UseG1GC' for below Xmx"
}
function t_mounts() {
    _basic_check "" "${_FILTERED_DATA_DIR%/}/system-filestores.json" || return
    _test_template "$(_rg '"totalSpace": [1-9]' -B2 -A3 ${_FILTERED_DATA_DIR%/}/system-filestores.json | _rg '"usableSpace": [1-7]?\d{1,9},' -B3 -A2)" "ERROR" "Storage/disk space (usableSpace) is less than 8GB" "NOTE: 'No space left on device' can be also caused by Inode, which won't be shown in above."

    local _workingDirectory="$(_search_json "sysinfo.json" "nexus-configuration,workingDirectory" | _rg -o -r '$1' '"(/[^"]+)"')"
    local _parent_dir="$(echo "${_workingDirectory}" | _rg -o -r '$1' '^(/[^/]+)')"
    [ -z "${_parent_dir}" ] && _parent_dir="$(_search_json "sysinfo.json" "install-info,sonatypeWork" | _rg -o '"(/[^/]+).+sonatype-work.*"' -r '$1')"
    local _result="$(_rg -B1 -A6 '("description": "'${_parent_dir}'\b|"description": "/[ "]|"description": "/tmp[ "])' ${_FILTERED_DATA_DIR%/}/system-filestores.json)"
    local _display_result=""
    if echo "${_result}" | grep -qEi '(nfs|cifs)'; then
        _head "WARN" "workingDirectory:${_workingDirectory} might be in a mount point (${_parent_dir})"
        _display_result="Y"
    elif echo "${_result}" | grep -qwi '(overlay)'; then
        _head "INFO" "workingDirectory:${_workingDirectory} might be in overlay (${_parent_dir})"
        _display_result="Y"
    fi
    if [ -n "${_display_result}" ]; then
        echo '```'
        echo "${_result}"
        # NOTE: 'bs=1 count=0 seek=104857600' is for creating one 100MB file very quickly
        echo "# Command examples to check (disk) performance with 100MB file:"
        echo "time sudo -u <nexus> dd if=/dev/zero of=\${_workingDirectory}/tmp/test.img bs=100M count=1 oflag=dsync
    time curl -u admin:admin123 -T \${_workingDirectory}/tmp/test.img http://localhost:8081/repository/raw-hosted/test/ --progress-bar | tee /dev/null
    sudo -u <nexus> dd if=/dev/zero of=\${installDirectory}/public/test.img bs=1 count=0 seek=104857600
    time curl -o/dev/null http://localhost:8081/test.img"
        echo '```'
    fi
}
function t_performance_issue() {
    _test_template "$(_rg -i '\b(Too many open files|No space left|low heap memory|Not enough physical memory available|huge system clock jump|Timed out|Timeout waiting for connection|waiting for more room|read only)\b' -o -g "${_LOG_GLOB}" | sort | uniq -c | sort -nr | head -n20)" "WARN" "This instance may have some performance issue (${_LOG_GLOB})"
}
function t_oome() {
    _test_template "$(_rg -c 'OutOfMemoryError' -g "${_LOG_GLOB}")" "ERROR" "OutOfMemoryError detected from ${_LOG_GLOB}"
}
# NOTE: this might be slow
function t_exceptions() {
    _test_template "$(_rg '([^ ()]+\.[a-zA-Z0-9]+Exception):' -o -r '$1' --no-filename -g "${_LOG_GLOB}" | sort | uniq -c | sort -nr | _rg '^\s*\d\d+' | head -n10)" "WARN" "Many exceptions detected from ${_LOG_GLOB}"
}
function t_errors() {
    _basic_check "" "${_FILTERED_DATA_DIR%/}/f_topErrors.out" || return
    _test_template "$(_rg '^\s*\d\d+.+\s+ERROR\s+' ${_FILTERED_DATA_DIR%/}/f_topErrors.out | head -n10)" "WARN" "Many ERROR detected from ${_FILTERED_DATA_DIR%/}/f_topErrors.out"
}
function t_threads() {
    local _dir="$(find . -maxdepth 3 -type d -name "_threads" -print -quit)"
    if [ -z "${_dir}" ]; then
        _head "INFO" "Can not run ${FUNCNAME} as no _threads directory."
        return
    fi
    _test_template "$(_rg '(MessageDigest|findAssetByContentDigest|WeakHashMap)' -m1 ${_dir} | head -n10)" "WARN" "'MessageDigest|findAssetByContentDigest|WeakHashMap' may indicates CPU issue (eg: NEXUS-10991)"
}
function t_requests() {
    _basic_check "" "${_FILTERED_DATA_DIR%/}/request.csv" || return
    _q -H "SELECT requestURL, statusCode, count(*) as c FROM ${_FILTERED_DATA_DIR}/request.csv WHERE requestURL LIKE '%/repository/%' AND (statusCode like '5%') GROUP BY requestURL, statusCode HAVING c > 10 ORDER BY c DESC LIMIT 10" > /tmp/t_requests.out
    _test_template "$(_rg -q '\s+5\d\d\s+' -m1 /tmp/t_requests.out && cat /tmp/t_requests.out)" "WARN" "Many repeated 5xx status in ${_FILTERED_DATA_DIR}/request.csv (${_FILTERED_DATA_DIR%/}/log_requests_5xx.out)"

    # NOTE: can't use headerContentLength as some request.log doesn't have it
    f_reqsFromCSV "request.csv" "7000" "" "20" 2>/dev/null >/tmp/t_requests.out
    _test_template "$(_rg -q '\s+GET\s+' -m1 /tmp/t_requests.out && cat /tmp/t_requests.out)" "WARN" "Unusually slow downloads in ${_FILTERED_DATA_DIR}/request.csv"
}


main() {
    f_run_extract || return $?
    echo "# $(basename "$BASH_SOURCE" ".sh") results"
    echo "[[toc]]"
    echo ""
    f_run_tests || return $?
    f_run_report
}

if [ "$0" = "$BASH_SOURCE" ]; then
    if [[ "$1" =~ ^(-h|help)$ ]]; then
        usage | less
        exit
    fi
    main > "$(basename "$BASH_SOURCE" .sh).md"
fi