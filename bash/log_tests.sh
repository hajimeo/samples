#!/usr/bin/env bash

usage() {
    cat << EOF
Check/test log files such as request.log and report any suspicious entry.

REQUIREMENTS:
    bash, ripgrep (rg), coreutils (realpath, timeout)
    q from https://github.com/harelba/q
    bar_chart.py from https://github.com/bitly/data_hacks (TODO: this project is dead)

TARGET OS:
    macOS Mojave
EOF
}

# Importing external libraries
_import() { . $HOME/IdeaProjects/samples/bash/${1} &>/dev/null && return; [ ! -s /tmp/${1}_$$ ] && curl -sf --compressed "https://raw.githubusercontent.com/hajimeo/samples/master/bash/${1}" -o /tmp/${1}_$$; . /tmp/${1}_$$; }
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
    rg "$@"
}
_q() {
    q -O -d"," -T --disable-double-double-quoting "$@"
}


function f_run_extract() {
    _LOG "INFO" "Extracting data into ${_FILTERED_DATA_DIR%/} ..."
    [ -d "${_FILTERED_DATA_DIR%/}" ] || mkdir -v -p "${_FILTERED_DATA_DIR%/}" || return $?
    if [ "$(ls -1 "${_FILTERED_DATA_DIR%/}")" ]; then
        _LOG "INFO" "${_FILTERED_DATA_DIR%/} is not empty so not extracting."
        return
    fi

    local _log_path="$(find . -maxdepth 3 -type f -print | grep -m1 -E "/(${_NXRM_LOG}|${_NXIQ_LOG}|server.log)$")"
    local _log_size="$(_actual_file_size "${_log_path}")"
    [ -z "${_log_path}" ] && _log_path="*.log"
    _LOG_GLOB="$(basename ${_log_path} | sed 's/.\///')"
    local _req_log_path="$(find . -maxdepth 3 -name ${_REQUEST_LOG} | head -n1 2>/dev/null)"
    local _req_log_size="$(_actual_file_size "${_req_log_path}")"

    ### Doing time consuming extracting first #########################################
    if [ -n "${_log_size}" ] && [ ${_log_size} -gt 0 ] && [ ${_log_size} -le ${_LOG_THRESHOLD_BYTES} ]; then
        f_topErrors "${_LOG_GLOB}" "" "" "(WARN .+ high disk watermark)" >${_FILTERED_DATA_DIR%/}/f_topErrors.out &
    fi

    _NOT_SPLIT_BY_DATE=Y f_threads &>${_FILTERED_DATA_DIR%/}/f_threads.out &

    if [ -n "${_req_log_size}" ] && [ ${_req_log_size} -gt 0 ] && [ ${_req_log_size} -le ${_LOG_THRESHOLD_BYTES} ]; then
        f_request2csv "${_REQUEST_LOG}" ${_FILTERED_DATA_DIR%/}/request.csv 2>/dev/null &
    else
        _LOG "INFO" "Run: f_request2csv "${_REQUEST_LOG}" ${_FILTERED_DATA_DIR%/}/request.csv # ${_req_log_size} > ${_LOG_THRESHOLD_BYTES}"
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

    # below is not heavy but still takes a few secs
    _extract_configs >${_FILTERED_DATA_DIR%/}/extracted_configs.md &
    _extract_log_last_start >${_FILTERED_DATA_DIR%/}/extract_log_last_start.md &
    ############################################################################

    _search_json "sysinfo.json" "system-filestores" > ${_FILTERED_DATA_DIR%/}/system-filestores.json
    wait
    _LOG "INFO" "Completed ${FUNCNAME} ($?)"
}

function _extract_configs() {
    _head "CONFIG: OS/server information from jmx.json"
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
    # TODO: detect if container(cgroup) or not. Maybe check overlay or not?
    echo '```'
    _head "CONFIG: system-runtime"
    echo '```'
    _search_json "sysinfo.json" "system-runtime,totalMemory" "Y"
    _search_json "sysinfo.json" "system-runtime,freeMemory" "Y"
    _search_json "sysinfo.json" "system-runtime,maxMemory" "Y"
    _search_json "sysinfo.json" "system-runtime,threads"
    echo '```'
    _head "CONFIG: network interfaces"
    echo '```json'
    _search_json "sysinfo.json" "system-network"
    echo '```'
    _head "CONFIG: database (TODO: IQ)"
    echo '```'
    _find_and_cat "config_ds_info.properties" 2>/dev/null
    echo '```'
}
function _extract_log_last_start() {
    _head "LOGS" "Instance start time (from jmx.json)"
    local _tz="$(_find_and_cat "jmx.json" 2>/dev/null | _get_json "java.lang:type=Runtime,SystemProperties,key=user.timezone,value")"
    [ -z "${_tz}" ] && _tz="$(_find_and_cat "sysinfo.json" 2>/dev/null | _get_json "nexus-properties,user.timezone" | rg '"([^"]+)' -o -r '$1')"
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
    echo '```'
    _check_log_stop_start "${_log_path}"
    echo '```'
}
function _check_log_stop_start() {
    local _log_path="$1"
    [ ! -s "${_log_path}" ] && _log_path="-g \"${_log_path}\""
    # NXRM2 stopping/starting, NXRM3 stopping/starting, IQ stopping/starting (IQ doesn't clearly say stopped so that checking 'Stopping')
    # NXRM2: org.sonatype.nexus.bootstrap.jetty.JettyServer - Stopped
    _rg --no-filename '(org.sonatype.nexus.bootstrap.jsw.JswLauncher - Stopping with code:|org.eclipse.jetty.server.AbstractConnector - Stopped ServerConnector|org.sonatype.nexus.events.EventSubscriberHost - Initialized|org.sonatype.nexus.webapp.WebappBootstrap - Initialized|org.eclipse.jetty.server.Server - Started|Started InstrumentedSelectChannelConnector|Received signal: SIGTERM|org.sonatype.nexus.extender.NexusContextListener - Uptime:|org.sonatype.nexus.extender.NexusLifecycleManager - Shutting down|org.sonatype.nexus.extender.NexusLifecycleManager - Stop KERNEL|org.sonatype.nexus.bootstrap.jetty.JettyServer - Stopped|org.sonatype.nexus.pax.logging.NexusLogActivator - start|com.sonatype.insight.brain.service.InsightBrainService - Stopping Nexus IQ Server|Disabled session validation scheduler|Initializing Nexus IQ Server)' ${_log_path} | sort | uniq | tail -n10
}

function f_run_report() {
    if [ -s "${_FILTERED_DATA_DIR%/}/extracted_configs.md" ]; then
        cat ${_FILTERED_DATA_DIR%/}/extracted_configs.md
    fi
    if [ -s "${_FILTERED_DATA_DIR%/}/extract_log_last_start.md" ]; then
        cat ${_FILTERED_DATA_DIR%/}/extract_log_last_start.md
    fi

    # TODO: should extract first?
    echo "## AUDIT: Top 20 'domain','type' from audit.log"
    echo '```'
    _rg --no-filename '"domain":"([^"]+)", *"type":"([^"]+)"' -o -r '$1,$2' -g audit.log | sort | uniq -c | sort -nr | head -n20
    echo "# NOTE: taskblockedevent would mean another task is running (dupe tasks?). repositorymetadataupdatedevent would mean quarantine."
    echo '```'

    if [ -s ${_FILTERED_DATA_DIR%/}f_topErrors.out ]; then
        [ -n "${_f_topErrors_pid}" ] && wait ${_f_topErrors_pid}
        echo "## APP LOG: counting WARNs and above, then displaying 10+ occurrences in ${_LOG_GLOB} (${_FILTERED_DATA_DIR%/}f_topErrors.out)"
        echo '```'
        cat /tmp/f_topErrors_$$.out | rg -v '^\s*\d\s+' # NOTE: be careful to modify this. It might hides bar_chart output
        echo '```'
    else
        echo "## APP LOG: NOT counting WARNs and above in ${_LOG_GLOB} as no ${_FILTERED_DATA_DIR%/}f_topErrors.out"
    fi

    if [ -s ${_FILTERED_DATA_DIR%/}/f_threads.out ]; then
        echo "## THREADS: Result of f_threads from ${_FILTERED_DATA_DIR%/}/f_threads.out"
        echo '```'
        cat ${_FILTERED_DATA_DIR%/}/f_threads.out
        echo '```'
    else
        echo "## THREADS: NOT checking threads as no ${_FILTERED_DATA_DIR%/}/f_threads.out"
    fi

    echo "## max 100 *.log files' start and end (start time, end time, difference(sec), filesize)"
    echo '```'
    f_list_start_end "*.log"
    echo '```'

    echo "### NOTE: To split logs by hour:"
    echo '```'
    echo "_SPLIT_BY_REGEX_SORT=\"Y\" f_splitByRegex \"./log/nexus.log\" \"^${_DATE_FORMAT}.\d\d\" \"_hourly_logs\""
    echo "f_extractFromLog \"./log/nexus.log\" \"^${_DATE_FORMAT}.XX\" \"^${_DATE_FORMAT}.YY\" > extracted_XX_YY.out"
    echo "_SPLIT_BY_REGEX_SORT=\"Y\" f_splitByRegex \"./log/request.log\" \"${_DATE_FMT_REQ}:\d\d\" \"_hourly_logs_req\""
    echo "f_extractFromLog \"./log/request.log\" \"${_DATE_FMT_REQ}.XX\" \"${_DATE_FMT_REQ}.YY\" > extracted_req_XX_YY.out"
    echo '```'

    r_requests
}

function f_run_tests() {
    # TODO: Check/Get the product version
    echo "## ${FUNCNAME} results"
    _LOG "INFO" "Executing $(typeset -F | grep '^declare -f t_' | wc -l) tests."
    for _t in $(typeset -F | grep '^declare -f t_' | cut -d' ' -f3); do
        if ! _wait_jobs; then
            _LOG "ERROR" "${FUNCNAME} failed."
            return 11
        fi
        eval "_LOG \"DEBUG\" \"Started ${_t}\";${_t};echo '';_LOG \"DEBUG\" \"Completed ${_t} ($?)\"" &
    done
    _wait_jobs 0
    _LOG "INFO" "Completed tests."  # TODO: currently can't count failed test.
}
function _head() {
    local _X="###"
    [ "$1" == "WARN" ] && _X="####"
    [ "$1" == "INFO" ] && _X="#####"
    echo "${_X} $*"
}
function _test_template() {
    local _bad_result="$1"
    local _level="$2"
    local _message="$3"
    local _note="$4"
    [ -z "${_bad_result}" ] && return
    _head "${_level}" "${_message}"
    echo '```'
    echo "${_bad_result}"
    [ -n "${_note}" ] && echo "# ${_note}"
    echo '```'
    return 1
}


### Tests ###################################################################
function t_system() {
    if [ ! -s ${_FILTERED_DATA_DIR%/}/extracted_configs.md ]; then
        _head "INFO" "Can not run ${FUNCNAME} as no ${_FILTERED_DATA_DIR%/}/extracted_configs.md"
        return
    fi
    _test_template "$(_rg 'AvailableProcessors: *[1-3]$' ${_FILTERED_DATA_DIR%/}/extracted_configs.md)" "WARN" "AvailableProcessors might be too low"
    _test_template "$(_rg 'TotalPhysicalMemorySize: *(.+ MB|[1-7]\.\d+ GB)' ${_FILTERED_DATA_DIR%/}/extracted_configs.md)" "WARN" "TotalPhysicalMemorySize might be too low"
    _test_template "$(_rg 'MaxFileDescriptorCount: *\d{4}$' ${_FILTERED_DATA_DIR%/}/extracted_configs.md)" "WARN" "MaxFileDescriptorCount might be too low"
    _test_template "$(_rg 'SystemLoadAverage: *([2-9]\.|\d\d+)' ${_FILTERED_DATA_DIR%/}/extracted_configs.md)" "WARN" "SystemLoadAverage might be too high"
    _test_template "$(_rg 'maxMemory: *(.+ MB|[1-3]\.\d+ GB)' ${_FILTERED_DATA_DIR%/}/extracted_configs.md)" "WARN" "maxMemory (heap|Xmx) might be too low"
    # TODO: check -XX:+UseG1GC
}
function t_disk_space() {
    if [ ! -s ${_FILTERED_DATA_DIR%/}/system-filestores.json ]; then
        _head "INFO" "Can not run ${FUNCNAME} as no ${_FILTERED_DATA_DIR%/}/system-filestores.json"
        return
    fi
    local _result=
    _test_template "$(_rg '"totalSpace": [1-9]' -B2 -A3 ${_FILTERED_DATA_DIR%/}/system-filestores.json | _rg '"usableSpace": [1-7]?\d{1,9},' -B3 -A2)" "ERROR" "Storage/disk space (usableSpace) is less than 8GB" "NOTE: 'No space left on device' can be also caused by Inode, which won't be shown in above."
}
function t_network_mount() {
    if [ ! -s ${_FILTERED_DATA_DIR%/}/system-filestores.json ]; then
        _head "INFO" "Can not run ${FUNCNAME} as no ${_FILTERED_DATA_DIR%/}/system-filestores.json"
        return
    fi
    local _workingDirectory="$(_search_json "sysinfo.json" "nexus-configuration,workingDirectory" | _rg -o -r '$1' '"(/[^"]+)"')"
    local _parent_dir="$(echo "${_workingDirectory}" | _rg -o -r '$1' '^(/[^/]+)')"
    [ -z "${_parent_dir}" ] && _parent_dir="$(_search_json "sysinfo.json" "install-info,sonatypeWork" | _rg -o '"(/[^/]+).+sonatype-work.*"' -r '$1')"
    local _result="$(_rg -B1 -A6 '("description": "'${_parent_dir}'\b|"description": "/[ "]|"description": "/tmp[ "])' ${_FILTERED_DATA_DIR%/}/system-filestores.json)"
    local _display_result=""
    if echo "${_result}" | grep -qEi '(nfs|cifs)'; then
        _head "WARN" "workingDirectory:${_workingDirectory} might be in a mount point (${_parent_dir})"
        _display_result="Y"
    fi
    if echo "${_result}" | grep -qwi '(overlay)'; then
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
# TODO: this might be slow
function t_exceptions() {
    _test_template "$(rg '([^ ()]+\.[a-zA-Z0-9]+Exception):' -o -r '$1' --no-filename -g "${_LOG_GLOB}" | sort | uniq -c | sort -nr | rg '^\s*\d\d+' | head -n10)" "WARN" "Many exceptions detected from ${_LOG_GLOB}"
}
function t_errors() {
    if [ ! -s ${_FILTERED_DATA_DIR%/}/f_topErrors.out ]; then
        _head "INFO" "Can not run ${FUNCNAME} as no ${_FILTERED_DATA_DIR%/}/f_topErrors.out"
        return
    fi
    _test_template "$(rg '^\s*\d\d+.+\s+ERROR\s+' ${_FILTERED_DATA_DIR%/}/f_topErrors.out | head -n10)" "WARN" "Many ERROR detected from ${_FILTERED_DATA_DIR%/}/f_topErrors.out"
}
function t_threads() {
    local _dir="$(find . -maxdepth 3 -type d -name "_threads" -print -quit)"
    if [ -z "${_dir}" ]; then
        _head "INFO" "Can not run ${FUNCNAME} as no _threads directory."
        return
    fi
    _test_template "$(rg '(MessageDigest|findAssetByContentDigest|WeakHashMap)' -m1 ${_dir} | head -n10)" "WARN" "'MessageDigest|findAssetByContentDigest|WeakHashMap' may indicates CPU issue (eg: NEXUS-10991)"
}

function r_requests() {
    if [ ! -s ${_FILTERED_DATA_DIR%/}/request.csv ]; then
        _head "INFO" "Can not run ${FUNCNAME} as no ${_FILTERED_DATA_DIR%/}/request.csv."
        return
    fi
    # first and end time per user
    #_q -H "select clientHost, user, count(*), min(date), max(date) from ${_FILTERED_DATA_DIR%/}/request.csv group by 1,2"
    echo "### Counting host_ip + user per hour for last 10 ('-' in user is counted as 1)"
    echo '```'
    _q -H "SELECT substr(date,1,14) as hour, count(*), count(distinct clientHost), count(distinct user), count(distinct clientHost||user) from ${_FILTERED_DATA_DIR%/}/request.csv group by 1 order by hour desc LIMIT 10"
    echo '```'

    echo "### Request counts per hour from ${_REQUEST_LOG}"
    echo '```'
    rg "${_DATE_FMT_REQ}:\d\d" -o --no-filename -g ${_REQUEST_LOG} | bar_chart.py
    echo '```'

    echo "### API-like requests per hour from ${_REQUEST_LOG}"
    echo '```'
    #_q -H "select substr(date,1,16) as ten_min, count(*) as c, CAST(avg(elapsedTime) as INT) as avg_elapsed from ${_FILTERED_DATA_DIR%/}/request.csv WHERE (requestURL like '%/service/rest/%' OR requestURL like '%/api/v2/%') GROUP BY ten_min HAVING avg_elapsed > 7000"
    rg "(${_DATE_FMT_REQ}:\d\d).+(/service/rest/|/api/v2/)" --no-filename -g ${_REQUEST_LOG} -o -r '$1' | bar_chart.py
    echo '```'

    rg 'HTTP/\d\.\d" 5\d\d\s' --no-filename -g ${_REQUEST_LOG} > ${_FILTERED_DATA_DIR%/}/log_requests_5xx.out
    if [ -s ${_FILTERED_DATA_DIR%/}/log_requests_5xx.out ]; then
        echo "### 5xx statusCode in ${_REQUEST_LOG} (${_FILTERED_DATA_DIR%/}/log_requests_5xx.out)"
        echo '```'
        rg "${_DATE_FMT_REQ}.\d\d" -o ${_FILTERED_DATA_DIR%/}/log_requests_5xx.out | bar_chart.py
        echo '```'
    fi
}
function t_requests() {
    if [ ! -s ${_FILTERED_DATA_DIR%/}/request.csv ]; then
        _head "INFO" "Can not run ${FUNCNAME} as no ${_FILTERED_DATA_DIR%/}/request.csv."
        return
    fi

    _q -H "SELECT requestURL, statusCode, count(*) as c FROM ${_FILTERED_DATA_DIR}/request.csv WHERE requestURL LIKE '%/repository/%' AND (statusCode like '5%') GROUP BY requestURL, statusCode HAVING c > 10 ORDER BY c DESC LIMIT 10" > /tmp/t_requests.out
    _test_template "$(rg -q '\s+5\d\d\s+' -m1 /tmp/t_requests.out && cat /tmp/t_requests.out)" "WARN" "Many repeated 5xx status in ${_FILTERED_DATA_DIR}/request.csv (${_FILTERED_DATA_DIR%/}/log_requests_5xx.out)"

    _q -H "SELECT clientHost, user, date, requestURL, statusCode, bytesSent, elapsedTime, CAST((CAST(bytesSent as INT) / CAST(elapsedTime as INT)) as DECIMAL(10, 2)) as bytes_per_ms, TIME(CAST((julianday(DATE('now')||' '||substr(date,13,8)) - 2440587.5) * 86400.0 - elapsedTime/1000 AS INT), 'unixepoch') as started_time FROM ${_FILTERED_DATA_DIR%/}/request.csv WHERE elapsedTime > 7000 AND (headerContentLength <> '-' OR bytes_per_ms < 1024) ORDER BY elapsedTime DESC LIMIT 20" > /tmp/t_requests.out
    _test_template "$(rg -q '\s+GET\s+' -m1 /tmp/t_requests.out && cat /tmp/t_requests.out)" "WARN" "Unusually slow downloads in ${_FILTERED_DATA_DIR}/request.csv"
}


main() {
    f_run_extract || return $?
    echo "# $(basename "$BASH_SOURCE" ".sh") results"
    echo "[[toc]]"
    echo ""
    f_run_report
    f_run_tests || return $?
}

if [ "$0" = "$BASH_SOURCE" ]; then
    if [[ "$1" =~ ^(-h|help)$ ]]; then
        usage | less
        exit
    fi
    main
fi