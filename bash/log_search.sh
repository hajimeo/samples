#!/usr/bin/env bash
#
# Bunch of grep functions to search log files
# Don't use complex one, so that each function can be easily copied and pasted
# TODO: tested on Mac only (eg: gsed, ggrep)
#
# DOWNLOAD:
#   curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/log_search.sh
#   source /dev/stdin <<< "$(curl -s --compressed https://raw.githubusercontent.com/hajimeo/samples/master/bash/log_search.sh)"
#   (optional)
#   curl https://raw.githubusercontent.com/hajimeo/samples/master/python/line_parser.py -o /usr/local/bin/line_parser.py
#

[ -n "$_DEBUG" ] && (set -x; set -e)
# NOTE below two lines make BASH_REMATCH work with same index as bash, but gave up on supporting zsh (too different)
#setopt KSH_ARRAYS &>/dev/null
#setopt BASH_REMATCH &>/dev/null

usage() {
    if [ -n "$1" ]; then
        _help "$1"
        return $?
    fi
    echo "HELP/USAGE:\
This script contains useful functions to search log files.

Required commands:
    brew install ripgrep      # for rg
    brew install gnu-sed      # for gsed
    brew install coreutils    # for gtac gdate realpath
    brew install findutils    # for gtac gdate realpath
    brew install q            # To query csv files https://github.com/harelba/q/releases/download/2.0.19/q-text-as-data_2.0.19-2_amd64.deb
    brew install jq           # To query json files
    brew install grep         # Do not need anymore, but ggrep is faster than Mac's grep
    pip install data_hacks    # for bar_chart.py

Setup:
    ln -s ${0} /usr/local/bin/log_search

HOW-TO: source (.), then use some function
    . log_search
    # Display usage/help of one function
    usage f_someFunctionName

    Examples:
    # Check what kind of caused by is most
    f_topCausedByExceptions yarn_application.log | tail -n 10

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

_elapsed() {
    local _end_time=$(date +%s)
    echo "elapsed $(( _end_time - _STARTED_TS ))s"
    _STARTED_TS=${_end_time}
}
### Public functions ###################################################################################################

function f_postgres_log() {
    local __doc__="grep (rg) postgresql log files"
    local _date_regex="${1}"    # No need ^
    local _glob="${2:-postgresql-*log*}"
    [ -z "${_date_regex}" ] && _date_regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d"

    echo "### system is ready to|timeline|redo done at|archive recovery ###############################################"
    # log_line_prefix = %t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h (%l = Number of the log line for each session or process. No idea why -1)
    rg -z -N --no-filename -g "${_glob}" "^${_date_regex}.+( system is ready to|timeline|redo done at|archive recovery|FATAL:|ERROR:)" | grep -v 'no pg_hba.conf entry' | sort -n | uniq
    echo ' '
    echo "### Slow checkpoint complete ################################################################################"
    # With log_checkpoints = on
    rg -z -N --sort=path -g "${_glob}" "^${_date_regex}.+ checkpoint complete:.+(longest=[^0].+|average=[^0].+)"
}

#f_grep_multilines top_2021-03-31_17-49-17.out "" "Active Internet connections" > threads_2021-03-31_17-49-17.out
function f_grep_multilines() {
    local __doc__="Multiline search with 'rg' dotall. Including the last line. NOTE: dot and brace can't be used in _str_in_1st_line"
    local _file="${1}" # -g "*.*log*" may work too
    local _str_in_1st_line="${2:-"^2\\d\\d\\d-\\d\\d-\\d\\d.\\d\\d:\\d\\d:\\d\\d"}"
    local _str_in_last_line="${3:-"^2\\d\\d\\d-\\d\\d-\\d\\d.\\d\\d:\\d\\d:\\d\\d"}"

    # NOTE: '\Z' to try matching the end of file returns 'unrecognized escape sequence'
    local _regex="${_str_in_1st_line}.+?(${_str_in_last_line}|\z)"
    echo "# regex:${_regex} ${_file}" >&2
    rg "${_regex}" \
        --multiline --multiline-dotall --no-line-number --no-filename -z \
        -m 2000 --sort=path ${_file} | tr -d '\000' # | grep -v "${_boundary_str}" # this would remove unwanted line too
    # not sure if rg sorts properly with --sort, so best effort (can not use ' | sort' as multi-lines)
}

# in case no rg
function _grep_multilines() {
    # requires ggrep
    local _file="${1}"
    local _start="${2:-"202\\d-\\d\\d-\\d\\d \\d\\d:\\d\\d:\\d\\d"}"
    local _end="${3:-"Active Internet connections"}"
    _grep -Pzo "(?s)${_start}[\s\S]*?${_end}.+?\n" "${_file}" | tr -d '\000'
}


function f_grep_logs() {
    local __doc__="Grep YYYY-MM-DD.hh:mm:ss.+<something>"
    local _str_in_1st_line="$1"
    local _glob="${2:-"*.*log*"}"
    local _exclude_warn_error="${3}"

    local _regex_1="^${_DATE_FORMAT}.\d\d:\d\d:\d\d.+(${_str_in_1st_line})"
    local _final_glob=""
    for _l in `rg "${_regex_1}" -l -g "${_glob}"`; do
        _final_glob="${_final_glob} -g ${_l}"
    done
    [ -z "${_final_glob}" ] && return

    local _regex="^${_DATE_FORMAT}.\d\d:\d\d:\d\d.+(${_str_in_1st_line}|\bWARN\b|\bERROR\b|\b.+?Exception\b|\b[Ff]ailed\b)"
    # It's a bit wasting resources...
    [[ "${_exclude_warn_error}" =~ ^[yY] ]] && _regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d.+(${_str_in_1st_line})"

    echo "# regex:${_regex} -g '${_glob}'" >&2
    rg -z "${_regex}" \
        --no-line-number --no-filename \
        ${_final_glob} | sort -n | uniq
}

function f_topCausedByExceptions() {
    local __doc__="List Caused By xxxxException (Requires rg)"
    local _glob="${1:-"*.log"}"
    local _is_shorter="$2"
    local _regex="Caused by.+Exception"

    if [[ "$_is_shorter" =~ (^y|^Y) ]]; then
        _regex="Caused by.+?Exception"
    fi
    rg -z -N -o "$_regex" -g "$_glob" | sort | uniq -c | sort -nr | head -n40
}

#f_topErrors ./nexus.log.2022-04-21.gz "^\d\d\d\d-\d\d-\d\d.(12|13).\d"
function f_topErrors() {
    local __doc__="List top X ERRORs with -m Y, and removing 1 or 2 occurrences"
    local _glob="${1:-"*.*log*"}"   # file path which rg accepts and NEEDS double-quotes
    local _date_regex="$2"          # for bar_chart.py. ISO format datetime, but no seconds (eg: 2018-11-05 21:00)
    local _regex="$3"               # to overwrite default regex to detect ERRORs
    local _exclude_regex="$4"       # exclude some lines before _replace_number
    local _top_N="${5:-20}"
    local _max_N="${6-${_TOP_ERROR_MAX_N}}"
    local _max_N_opt=""
    [ -z "${_regex}" ] && _regex="\b(WARN|ERROR|SEVERE|FATAL|SHUTDOWN|Caused by|.+?Exception|FAILED)\b.+"
    [ -n "${_date_regex}" ] && _regex="${_date_regex}.*${_regex}"
    [ -n "${_max_N}" ] && _max_N_opt="-m ${_max_N}"
    echo "# rg \"${_regex}\" ${_glob} | rg -v \"${_exclude_regex}\""
    if [ -f "${_glob}" ]; then
        rg -z -c "${_regex}" -H "${_glob}" && echo " "
        rg -z --no-line-number --no-filename "${_regex}" ${_max_N_opt} "${_glob}"
    else
        rg -z -c -g "${_glob}" "${_regex}" && echo " "
        rg -z --no-line-number --no-filename -g "${_glob}" ${_max_N_opt} "${_regex}"
    fi > /tmp/${FUNCNAME[0]}_$$.tmp
    [ -n "${_max_N}" ] && echo "# Top ${_top_N} with -m ${_max_N}"
    if [ -z "${_exclude_regex}" ]; then
        cat /tmp/${FUNCNAME[0]}_$$.tmp
    else
        cat /tmp/${FUNCNAME[0]}_$$.tmp | rg -v "${_exclude_regex}"
    fi | _replace_number | sort | uniq -c | sort -nr | head -n ${_top_N}

    # just for fun, drawing bar chart
    if which bar_chart.py &>/dev/null; then
        if [ -z "${_date_regex}" ]; then
            local _num=$(rg -z --no-line-number --no-filename -o '^\d\d\d\d-\d\d-\d\d.\d\d:\d' /tmp/${FUNCNAME[0]}_$$.tmp | sort | uniq | wc -l | tr -d '[:space:]')
            if [ "${_num}" -lt 30 ]; then
                _date_regex="^\d\d\d\d-\d\d-\d\d.\d\d:\d"
            else
                _date_regex="^\d\d\d\d-\d\d-\d\d.\d\d"
            fi
        fi

        echo " "
        if [ -z "${_exclude_regex}" ]; then
            cat /tmp/${FUNCNAME[0]}_$$.tmp
        else
            cat /tmp/${FUNCNAME[0]}_$$.tmp | rg -v "${_exclude_regex}"
        fi | rg -z --no-line-number --no-filename -o "${_date_regex}" | sed 's/T/ /' | bar_chart.py
    fi
}

function f_listWarns() {
    local __doc__="List the counts of frequent warns and also errors"
    local _glob="${1:-"*.*log*"}"
    local _date_4_bar="${2:-"\\d\\d\\d\\d-\\d\\d-\\d\\d.\\d\\d"}"
    local _top_N="${3:-40}"

    local _regex="\b(WARN|ERROR|SEVERE|FATAL|FAILED)\b"
    rg -z -c -g "${_glob}" "^${_date_4_bar}.+${_regex}"
    echo " "
    rg -z -N --no-filename -g "${_glob}" "^${_date_4_bar}.+${_regex}" > /tmp/f_listWarns.$$.tmp
    # count by class name and ignoring only once or twice warns
    rg "${_regex}\s+.+" -o /tmp/f_listWarns.$$.tmp | _replace_number | sort | uniq -c | sort -nr | head -n ${_top_N}
    echo " "
    rg -o "^${_date_4_bar}" /tmp/f_listWarns.$$.tmp | bar_chart.py 2>/dev/null
}

function f_topSlowLogs() {
    local __doc__="List top performance related log entries."
    local _glob="${1:-"*.*log*"}"
    local _date_regex="$2"
    local _regex="$3"
    local _not_hiding_number="$4"
    local _top_N="${5:-10}" # how many result to show

    if [ -z "$_regex" ]; then
        # case insensitive
        _regex="\b(slow|delay|delaying|latency|too many|not sufficient|lock held|took [1-9][0-9]+ ?ms|timeout[^=]|timed out|waiting for)\b.+"
    fi
    if [ -n "${_date_regex}" ]; then
        _regex="^${_date_regex}.+${_regex}"
    fi

    echo "# Regex = '${_regex}'"
    #rg -z -c -g "${_glob}" -wio "${_regex}"
    rg -z -N --no-filename -g "${_glob}" -i -o "$_regex" > /tmp/f_topSlowLogs.$$.tmp
    if [[ "$_not_hiding_number" =~ (^y|^Y) ]]; then
        cat /tmp/f_topSlowLogs.$$.tmp
    else
        # ([0-9]){2,4} didn't work also (my note) sed doesn't support \d
        cat /tmp/f_topSlowLogs.$$.tmp | _replace_number
    fi | sort | uniq -c | sort -nr | head -n ${_top_N}
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

function f_appLogSplit() {
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

function f_appLogCSplit() {
    local __doc__="Split YARN App log with csplit/gcsplit"
    local _app_log="$1"
    local _no_rename="$2"

    local _out_dir="`basename $_app_log .log`_containers"
    if [ ! -r "$_app_log" ]; then
        echo "$_app_log is not readable"
        return 1
    fi

    if [ ! -d $_out_dir ]; then
        mkdir -p $_out_dir || return $?
    fi

    _csplit -z -f $_out_dir/lineNo_ $_app_log "/^Container: container_/" '{*}' || return $?
    if [[ "${_no_rename}" =~ ^(y|Y) ]]; then
        echo "Not renaming 'lineNo_*' files."
    else
        _appLogCSplit_rename "." "${_out_dir}"
    fi
}

function _appLogCSplit_rename() {
    local _in_dir="${1:-.}"
    local _out_dir="${2:-.}"

    local _new_filename=""
    local _type=""
    # -bash: /bin/ls: Argument list too long, also i think xargs can't use eval, also there is command length limit!
    #find $_out_dir -type f -name 'lineNo_*' -print0 | xargs -P 3 -0 -n1 -I {} bash -c "cd $PWD; _f={};_new_filepath=\"\`head -n 1 \${_f} | grep -oE \"container_.+\" | tr ' ' '_'\`\" && mv \${_f} \"${_out_dir%/}/\${_new_filepath}.out\""
    find ${_in_dir} -type f -name 'lineNo_*' -print > /tmp/f_appLogCSplit.out
    for _f in `cat f_appLogCSplit.out`; do
        _new_filename="`head -n 1 ${_f} | grep -oE "container_[a-z0-9_]+"`"
        _type="`grep -m 1 '^LogType:' ${_f} | cut -d ':' -f2`"
        if [ -n "${_new_filename}" ]; then
            if [[ "${_type}" =~ ^.+\.dot$ ]]; then
                rg '^digraph.+\}' --multiline --multiline-dotall --no-filename --no-line-number ${_f} > "${_out_dir%/}/${_new_filename}.${_type}" && rm -f "${_f}"
            else
                # .${_type} is always .stderr but file contains all types for the container, so using .log
                mv -v -i ${_f} "${_out_dir%/}/${_new_filename}.log"
            fi
        fi
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
        echo "# sudo -H pip3 install data_hacks"
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
        _sed -n "s@\($_datetime_regex\).*\(cmd=[\S]*\).*src=.*\$@\1,\2@p" $_path | $_cmd
    else
        _sed -n 's:^.*\(cmd=[\S]*\) .*$:\1:p' $_path | $_cmd
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
        _sed -n 's:^.*\(ugi=[\S]*\) .*\(cmd=[\S]*\).*src=.*$:\1,\2:p' $_path | $_cmd
    else
        _sed -n 's:^.*\(ugi=[\S]*\) .*$:\1:p' $_path | $_cmd
    fi
}

function f_listPerflogEnd() {
    local __doc__="Hive: _grep </PERFLOG ...> to see duration"
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
    local __doc__="Hive: Get lines between PERFLOG method=xxxxx"
    local _path="$1"
    local _approx_datetime="$2"
    local _thread_id="$3"
    local _method="${4-compile}"

    _getAfterFirstMatch "$_path" "^${_approx_datetime}.+ Thread-${_thread_id}\]: .+<PERFLOG method=${_method} " "Thread-${_thread_id}\]: .+<\/PERFLOG method=${_method} " | _grep -vP ": Thread-(?!${_thread_id})\]"
}

function f_list_start_end(){
    local __doc__="Output start time, end time, difference(sec), (filesize) from *multiple* log files"
    local _glob="${1}"
    local _date_regex="${2}"
    local _sort="${3:-3}"   # Sort by end time
    local _tail_n="${4:-100}"   # Sort by end time
    local _files=""
    # If no file(s) given, check current working directory
    if [ -n "${_glob}" ]; then
        _files="`find . \( ! -regex '.*/\..*' \) -type f \( -name "${_glob}" -o -name "${_glob}.gz" \) -size +0 -print | tail -n ${_tail_n}`"
    else
        _files="`find . \( ! -regex '.*/\..*' \) -type f -size +0 -print | tail -n ${_tail_n}`"
        #_files="`ls -1 | tail -n ${_tail_n}`"
    fi
    for _f in `echo ${_files}`; do f_start_end_time "${_f}" "${_date_regex}"; done | sort -t$'\t' -k${_sort} | column -t -s$'\t'
}

function f_start_end_time(){
    local __doc__="Output start time, end time, duration(sec), (filesize) from one log or log.gz"
    #eg: for _f in \`ls\`; do f_start_end_time \$_f \"^${_DATE_FORMAT}.\d\d:\d\d:\d\d,\d\d\d\"; done | sort -t$'\\t' -k2)
    local _log="$1"
    local _date_regex="${2}"    # Use (). See below line for example
    # NOTE: not including milliseconds as some log wouldn't have
    [ -z "$_date_regex" ] && _date_regex="(^${_DATE_FORMAT}.\d\d:\d\d:\d\d|\[\d{2}[-/][a-zA-Z]{3}[-/]\d{4}.\d\d:\d\d:\d\d)"

    local _start_date="$(_date2iso "`rg -z -N -om1 -r '$1' "$_date_regex" ${_log}`")" || return $?
    local _extension="${_log##*.}"
    if [ "${_extension}" = 'gz' ]; then
        local _end_date="$(_date2iso "`_gunzip -c ${_log} | _tac | rg -z -N -om1 -r '$1' "$_date_regex"`")" || return $?
    else
        local _end_date="$(_date2iso "`_tac ${_log} | rg -z -N -om1 -r '$1' "$_date_regex"`")" || return $?
    fi
    local _start_int=`_date2int "${_start_date}"`
    local _end_int=`_date2int "${_end_date}"`
    local _diff=$(( $_end_int - $_start_int ))
    # Filename, start datetime, enddatetime, difference, (filesize)
    echo -e "`basename ${_log}`\t${_start_date}\t${_end_date}\t${_diff} s\t$(bc <<< "scale=1;$(wc -c <${_log}) / 1024") KB"
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
    if [ ! -s "${_save_dir%/}/._pid_list.tmp" ]; then
        awk '{print $1}' "${_strace_file}" | sort -n | uniq > "${_save_dir%/}/._pid_list.tmp"
    else
        echo "${_save_dir%/}/._pid_list.tmp exists. Reusing..." 1>&2
    fi

    for _p in `${_cat} "${_save_dir%/}/._pid_list.tmp"`
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
    echo "Done. You might want to run: f_list_start_end '*.out' '^\d+\s+(\d\d:\d\d:\d\d.\d+)'" >&2
}

function f_find_size_sort_by_basename() {
    local __doc__="Find (xml) files then sort by the basename and list with the file size (CSV format)"
    local _name="${1:-"*.xml"}"
    local _dir="${2:-"."}"
    local _maxdepth="${3:-"5"}"
    # awk part may work with specific OS only
    # ex: add padding with awk: awk '{printf("%10s %s\n", $7, $11)}'
    find ${_dir%/} -maxdepth ${_maxdepth} -type f -name "${_name}" -ls | awk '{printf("%s %s\n", $7, $11)}' | rg '^(\d+) (.+)/(.+)$' -o -r '$1,"$2/$3","$3"'
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
    local __doc__="Outputs some OS kernel parameters (and compare with working one)"
    local _conf="${1-./}"

    #cat /sys/kernel/mm/transparent_hugepage/enabled
    #cat /sys/kernel/mm/transparent_hugepage/defrag

    # 1. check "sysctl -a" output
    # Ref: http://www.tweaked.io/guide/kernel/ https://github.com/t3rmin4t0r/notes/wiki/Hadoop-Tuning-notes
    # So far, removing net.ipv4.conf.*.forwarding
    local _props="fs.file-nr vm.zone_reclaim_mode vm.overcommit_memory vm.swappiness vm.dirty_ratio vm.dirty_background_ratio kernel.shmmax kernel.shmall kernel.sem kernel.msgmni kernel.sysrq vm.oom_dump_tasks net.core.somaxconn net.core.netdev_max_backlog net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.ipv4.ip_local_port_range net.ipv4.tcp_mtu_probing net.ipv4.tcp_fin_timeout net.ipv4.tcp_syncookies net.ipv4.conf.default.accept_source_route net.ipv4.tcp_tw_recycle net.ipv4.tcp_max_syn_backlog net.ipv4.conf.all.arp_filter"

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

# Simple way
#rg -i 'real=[^0]\d\S+' gc.2025-03-28_21-48-30.log
# Generate chart for one specific class size (should check count?)
#rg '(^20\d\d.\d\d.\d\d.+Class Histogram \(before full gc\)|org.sonatype.nexus.repository.content.store.AssetBlobData)' gc.2023-01-13_09-12-22.log.0 | paste - - | rg '^(\d\d\d\d.\d\d.\d\d.\d\d:\d\d:\d\d\.\d\d\d).+ (\d+)\s+org.sonatype.nexus.repository.content.store.AssetBlobData' -o -r '$1 $2' | bar_chart.py -A
#f_gc_overview gc.2021-10-30_15-03-15.log.0.current.gz "" "M" "2021-12-28.0[5678]:\d\d:\d\d.\d+"
function f_gc_overview() {
    local __doc__="Generate elapsed and Heap usage with CSV format (probably works with only G1GC)"
    local _file="$1"
    local _saveTo="$2"
    local _size="${3:-"M"}"
    local _datetime_filter="${4:-"${_DATE_FORMAT}.\\d\\d:\\d\\d:\\d\\d.?\\d*"}"
    [ -z "${_saveTo}" ] && _saveTo="$(basename ${_file%.*}).csv"
    # TODO: ([0-9.]+) secs does not work with PrintClassHistogramBeforeFullGC
    if rg 'Class Histogram' -q ${_file}; then
        rg -z "(^20\d\d-\d\d-\d\d.+(GC pause|Full GC).+$|Heap:\s*[^\]]+|\[Times: .+real=.+$)" -o ${_file} | rg '(GC pause|Full GC)' -A2 | rg -v -- '--' | paste - - - > /tmp/${FUNCNAME[0]}.tmp || return $?
        rg "^(${_datetime_filter}).+(GC pause[^,]+|Full GC.+?\)).+Heap:\s*([0-9.]+)${_size}[\(\)0-9.KMG ]+->\s*([0-9.]+)${_size}.+ real=([0-9.]+) secs.+" -o -r '"${1}",${5},${3},${4},"${2}"' /tmp/${FUNCNAME[0]}.tmp > "${_saveTo}" || return $?
    else
        if rg '^\s*\[Times:' -q ${_file}; then
            # TODO: this is not working as too many 'Times':
            rg -z '(^20\d\d-\d\d-\d\d.+(GC pause|Full GC).+$|Heap:\s*[^\]]+|Times:[^\]]+ secs)' -o ${_file} | paste - - - > /tmp/${FUNCNAME[0]}.tmp || return $?
            rg "^(${_datetime_filter}).+(GC pause[^,]+|Full GC[^,]+).+\s*Heap:\s*([0-9.]+)${_size}[\(\)0-9.KMG ]+->\s*([0-9.]+)${_size}.*\s* ([0-9.]+) secs" -o -r '"${1}",${5},${3},${4},"${2}"' /tmp/${FUNCNAME[0]}.tmp
        else
            # TODO: can't use the _datetime_filter at below rg command. Need to use more complex rg command
            rg -z '(^20\d\d-\d\d-\d\d.+(GC pause|Full GC).+$|Heap:\s*[^\]]+)' -o ${_file} | paste - - > /tmp/${FUNCNAME[0]}.tmp || return $?
            rg "^(${_datetime_filter}).+(GC pause[^,]+|Full GC[^,]+).* ([0-9.]+) secs.+Heap:\s*([0-9.]+)${_size}[\(\)0-9.KMG ]+->\s*([0-9.]+)${_size}" -o -r '"${1}",${3},${4},${5},"${2}"' /tmp/${FUNCNAME[0]}.tmp
         fi > "${_saveTo}" || return $?
    fi
    head -n1 "${_saveTo}" | rg -q '^date_time' || echo "date_time,elapsed_secs,heap_before_${_size},heap_after_${_size},gc_type
$(cat "${_saveTo}")" > ${_saveTo}
    echo "# Full GCs"
    rg "^\"(${_DATE_FORMAT}.\d\d:\d).+Full GC" -o -r '$1' ${_saveTo} | bar_chart.py
    echo "# All GCs"
    rg "^\"(${_DATE_FORMAT}.\d\d)" -o -r '$1' ${_saveTo} | bar_chart.py
    ls -l /tmp/${FUNCNAME[0]}.tmp ${_saveTo}
    #df = ju.q(\"SELECT date_time,elapsed_secs,heap_before_M,heap_after_M from t_gc WHERE gc_type like 'Full GC%'\")"
}

#JAVA_GC_LOG_DIR="/some/location"
#JAVA_GC_OPTS="-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=${JAVA_GC_LOG_DIR%/}/ -XX:+PrintClassHistogramBeforeFullGC -XX:+PrintClassHistogramAfterFullGC -XX:+TraceClassLoading -XX:+TraceClassUnloading -verbose:gc -XX:+PrintGC -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCApplicationStoppedTime -Xloggc:${JAVA_GC_LOG_DIR}/gc.%t.log -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=100m"
function f_gc_before_after_check() {
    local __doc__="Check PrintClassHistogramBeforeFullGC/PrintClassHistogramAfterFullGC (not jmap -histo) to find which objects are increasing"
    local _log_dir="${1:-"."}"
    local _keyword="${2-"sonatype"}"
    local _A_max="${3-"100"}"
    echo "# Total : 'date_time' '#instances' '#bytes'"
    rg -z -N --sort=path --no-filename "(${_DT_FMT}.*\s+\[?Class Histogram|Total\s+\d+\s+\d+)" ${_log_dir} | paste - - | rg "(${_DT_FMT}).+\s+Total\s+(\d+\s+\d+)" -o -r '$1   $2' | sort | uniq
    echo ""
    #rg -z -N --no-filename "^(${_DT_FMT}).+\bFull GC" -o -r '$1' ${_log_dir} | sort | uniq > /tmp/${FUNCNAME[0]}_datetimes_$$.tmp || return $?
    # NOTE: expecting filenames works with --sort=path
    rg -z -N --sort=path --no-filename '\b(Full GC|Class Histogram)\b' -A ${_A_max} ${_log_dir}  > /tmp/${FUNCNAME[0]}_$$.tmp || return $?
    cat /tmp/${FUNCNAME[0]}_$$.tmp | rg "\S*${_keyword:-"\S+"}\S*" -o | sort | uniq | while read -r _cls; do
        echo "# 'date_time' '#instances' '#bytes' for ${_cls}"
        rg "(${_DT_FMT}|\s+\d+\s+\d+\s+${_cls//$/\\$}$)" -o /tmp/${FUNCNAME[0]}_$$.tmp | rg "${_cls//$/\\$}" -B1 | rg -v -- '--' | paste - -
        echo ""
    done
    echo "# diff between first and last for class includes '${_keyword}':"
    local _n1=$((${_A_max} + 1))
    diff -w -y -W200 <(head -n ${_n1} /tmp/${FUNCNAME[0]}_$$.tmp | rg "(\d+)\s+(\d+)\s+(.*${_keyword}.*)" -o -r '${3} ${2} ${1}') <(tail -n ${_n1} /tmp/${FUNCNAME[0]}_$$.tmp | rg "(\d+)\s+(\d+)\s+(.*${_keyword}.*)" -o -r '${3} ${2} ${1}')
    echo ""
    echo "# Temp file: /tmp/${FUNCNAME[0]}_$$.tmp"
}

# If jmap output starts with YYYY-MM-DD hh:mm:ss.xxx
#_csplit -z -f "./jmap_histos/jmap_histo_" ${_file} "/^2023-/" '{*}'
function f_jmap_histo_compare() {
    local _file_glob="${1:-${_HISTO_FILE_GLOB:-"jmap_histo_*"}}"
    local _keyword="${2:-".*sonatype.*"}"
    local _m="${3:-"10"}"
    rg "\s*\d+:\s+\d+\s+\d{6,}\s+${_keyword}" -m${_m} -g "${_file_glob}"
}

#mkdir -v ./jmap_histos
#_csplit -z -f "./jmap_histos/jmap_histo_" ${_file} "/^ *num /" '{*}'
#_i=1; for _f in $(ls -1 ./jmap_histos/jmap_histo_*); do f_jmap_histo2csv "${_f}" "./jmap_histos.csv" "" "${_i}"; _i=$((${_i}+1)); done
# If jmap output starts with YYYY-MM-DD hh:mm:ss.xxx
#for _f in $(ls -1 ./jmap_histos/jmap_histo_*); do f_jmap_histo2csv "${_f}" "./jmap_histos.csv" "" "$(rg -m1 '^202\d-\d\d-\d\d.+' -o ${_f})"; done
#
#  ju.csv2df("./jmap_histos.csv", tablename="t_jmap_histos")
#  ju.d(ju.q("""SELECT min(key), count(*), class_name, instances, bytes FROM t_jmap_histos WHERE class_name like '%.sonatype.%' and bytes > 500000 GROUP BY class_name, instances, bytes ORDER BY class_name, key"""))
#  ju.d(ju.q("""SELECT min(key), count(*), class_name, instances, bytes FROM t_jmap_histos WHERE bytes > 500000 GROUP BY class_name, instances, bytes ORDER BY bytes DESC"""))
function f_jmap_histo2csv() {
    local __doc__="Convert jmap -histo output to csv"
    local _file="${1}"      # File path which contains one jmap histo output
    local _save_to="${2}"   # Saving path. If empty $(basename "${_file%.*}").csv
    local _class_ex="${3-".*sonatype.*"}"   # If not empty, count classes which contains this word
    local _key="${4}"       # Used for the first column. Expecting date_time but if empty, then the file name
    [ -z "${_key}" ] && _key="$(basename "${_file%.*}")"    # Not using "%%.*"
    [ -z "${_key}" ] && _key="$(basename "${_file}")"
    [ -z "${_save_to}" ] && _save_to="./$(basename "${_file%.*}").csv"
    [ -z "${_class_ex}" ] && _class_ex=".+"
    if [ -s "${_save_to}" ]; then
        echo "${_save_to} exists, so appending ${_file} results ..." >&2
    fi
    # num     #instances         #bytes  class name
    rg -z "^\s*\d+:\s+(\d+)\s+(\d+)\s+(${_class_ex})" -o -r "\"${_key}\",\"\$3\",\$1,\$2" ${_file} >> "${_save_to}" || return $?
    head -n1 "${_save_to}" | rg -q '^key' || echo "key,class_name,instances,bytes
$(cat "${_save_to}")" > ${_save_to}
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
        local _line_num=`_gunzip -c ${_file} | wc -l | tr -d '[:space:]'`
        rg -n --no-filename -z "${_search_regex}" ${_file} | rg -o '^(\d+):(2\d\d\d-\d\d-\d\d) (\d\d:\d\d:\d\d,\d\d\d)' -r '${2}T${3} ${1}' | line_parser.py thread_num ${_line_num} | bar_chart.py -A
    else
        local _line_num=`wc -l <${_file} | tr -d '[:space:]'`
        rg -n --no-filename -z "${_search_regex}" ${_file} | rg -o '^(\d+):(2\d\d\d-\d\d-\d\d) (\d\d:\d\d:\d\d,\d\d\d)' -r '${2}T${3} ${1}' | line_parser.py thread_num ${_line_num} | bar_chart.py -A
    fi
}

#f_check_topH "top_netstat/top_0*"
function f_check_topH() {
    # grep top output and return PID (currently over 90% CUP one) for the user, then use printf to convert to hex
    local _file="${1}"  # file path or glob for rg
    local _user="${2:-"\\S+"}" # [^ ]+
    local _search_word="${3-"sonatype"}"
    local _threads_dir="${4-"./_threads"}"
    local _cpu_pct_regex="${5-"${_CPU_PCT_REGEX:-"[6-9]\\d\.\\d+"}"}"
    local _n="${6:-20}"
    echo "# Overview from top ${_n} (check long 'TIME+')"
    if [ -f "${_file}" ]; then
        rg '^top' -A ${_n} "${_file}"
    else
        rg '^top' -A ${_n} -g "${_file}" --no-filename
    fi | rg "^(top|\s*\d+\s+${_user}\s.+\s.[^ ]+)" | tee /tmp/${FUNCNAME[0]}_$$.tmp || return $?
    echo ""
    echo "# Converting suspicious PIDs to hex"
    cat /tmp/${FUNCNAME[0]}_$$.tmp | rg "^\s*(\d+) +${_user} +\S+ +\S+ +\S+ +\S+ +\S+ +\S+ +(\d\d\d+|${_cpu_pct_regex})" -o -r '$1' | sort | uniq -c | sort -nr | head -n${_n} | while read -r _l; do
        if [[ "${_l}" =~ ([0-9]+)[[:space:]]+([0-9]+) ]]; then
            local _cnt="${BASH_REMATCH[1]}"
            local _pid="${BASH_REMATCH[2]}"
            local _hex_pid="$(printf "0x%x" ${_pid})"
            printf "%s\t%s\t%s\n" ${_cnt} ${_pid} ${_hex_pid}
            if [ ${_cnt} -gt 2 ] && [ -d "${_threads_dir%/}" ]; then
                rg -w "nid=${_hex_pid}" -l "${_threads_dir%/}/" | while read -r _f; do
                    if rg -q "${_search_word}" ${_f}; then
                        rg "(^\"|^\s+java.lang.Thread.State\b|\blocked\b|${_search_word})" ${_f}
                    fi
                done > ./high_cpu_threads_${_pid}_${_hex_pid}.out
            fi
        fi
    done
    echo ""
    echo "# High CPU thread summaries"
    ls -ltr ./high_cpu_threads_*.out
}

function f_check_netstat() {
    local _file="${1}"  # file path or glob for rg
    local _port="${2}"
    #rg '^Proto' "${_file}"
    #if [ ! -f "${_file}" ]; then
    #    _file="-g ${_file}"
    #fi
    echo "# Large Receive / Send Q from netstat"
    rg "^(Proto|tcp\s+(\d{5,}\s+\d+|\d+\s+\d{5,})\s+[^ ]+:${_port:-"[0-9]+"}\s+.+/)" ${_file}
    echo ""
    echo "# Counting _WAIT|SYN_RECV"
    rg "\s+([^ ]+_WAIT[0-9]?|SYN_RECV)\s+" -o -r '$1' ${_file} | sort | uniq -c
    if [ -n "${_port}" ]; then
        echo "# Counting _WAIT against Local Address:${_port}"
        rg "\s+[^ ]+:${_port}\s+([^:]+):\d+\s+([^ ]+_WAIT)\s+" -o -r '$1 $2' ${_file} | sort | uniq -c
        echo "# Counting _WAIT against Foreign Address:${_port} (top 10)"
        rg "\s+[^ ]+:${_port}\s+([^:]+:\d+)\s+([^ ]+_WAIT)\s+" -o -r '$1 $2' --no-filename ${_file} | sort | uniq -c | rg -v '^\s+1\s+' | sort -nr | head -n10
    fi
    echo "(check /proc/sys/net/ipv4/tcp_tw_reuse)"
}

function f_splitTopNetstat() {
    local __doc__="Split a file which contains multiple top and netstat outputs"
    local _file="$1"
    local _out_dir="${2:-"./top_netstat"}"

    local _netstat_str=""   # used to split netstat output
    local _useGonetstat=false

    if [ ! -d $_out_dir ]; then
        mkdir -v -p $_out_dir || return $?
    fi

    if rg -q "^Active Internet\s+" "${_file}"; then
        _netstat_str="Active Internet"
    elif rg -q "^\s*sl\s+" "${_file}"; then
        # if /proc/net/tcp, " *sl" NOTE: the value in HEX is reversed order
        _netstat_str=" *sl"
        if ! type gonetstat &>/dev/null; then
            curl -o /usr/local/bin/gonetstat -L "https://github.com/hajimeo/samples/raw/master/misc/gonetstat_$(uname)_$(uname -m)" && chmod a+x /usr/local/bin/gonetstat
        fi
        if type gonetstat &>/dev/null; then
            _useGonetstat=true
        fi
    fi

    local _tmpDir="$(mktemp -d)"
    local _split_pfx="${_tmpDir%/}/_topOrNet_"
    if ! rg -q "^(Active Internet\s+|\s*sl\s+)" "${_file}"; then
        _split_pfx="${_out_dir%/}/top_"
    fi
    _csplit -z -f "${_split_pfx}" ${_file} "/^top /" '{*}' || return $?

    if [ -z "${_netstat_str}" ]; then
        return
    fi
    for _f in $(ls -1 ${_split_pfx}*); do
        _csplit -z -f "${_out_dir%/}/`basename ${_f}`_" ${_f} "/^${_netstat_str} /" '{*}' || return $?
    done
    ls -1 ${_out_dir%/}/_topOrNet_* | while read _fpath; do
        [[ "${_fpath}" =~ .+/_topOrNet_([0-9]+)_([0-9]+)$ ]]
        local _n1="${BASH_REMATCH[1]}"
        local _n2="${BASH_REMATCH[2]}"
        if [ "${_n2}" == "00" ]; then
            mv "${_fpath}" "${_out_dir%/}/top_${_n1}.out"
        elif [ "${_n2}" == "01" ]; then
            if ${_useGonetstat}; then
                gonetstat "${_fpath}" > "${_out_dir%/}/netstat_${_n1}.out" #&& rm -f "${_fpath}"
            else
                mv "${_fpath}" "${_out_dir%/}/netstat_${_n1}.out"
            fi
        fi
    done
}

#f_splitNetstats script-20241025085904002.log
function f_splitNetstats() {
    local _file="$1"
    local _out_dir="${2:-"./netstats"}"
    local _netstat_str=""   # used to split netstat output
    local _useGonetstat=false

    if rg -q "^Active Internet\s+" "${_file}"; then
        _netstat_str="Active Internet"
    elif rg -q "^\s*sl\s+" "${_file}"; then
        # if /proc/net/tcp, " *sl" NOTE: the value in HEX is reversed order
        _netstat_str=" *sl"
        if ! type gonetstat &>/dev/null; then
            curl -o /usr/local/bin/gonetstat -L "https://github.com/hajimeo/samples/raw/master/misc/gonetstat_$(uname)_$(uname -m)" && chmod a+x /usr/local/bin/gonetstat
        fi
        if type gonetstat &>/dev/null; then
            _useGonetstat=true
        fi
    fi

    if [ -z "${_netstat_str}" ]; then
        return
    fi

    if [ ! -d $_out_dir ]; then
        mkdir -v -p $_out_dir || return $?
    fi

    local _split_pfx="${_out_dir%/}/$(basename ${_file})_"
    if rg -q '^\d\d\d\d-\d\d-\d\d \d\d\:\d\d:\d\d$' "${_file}"; then
        rg -v '^\d\d\d\d-\d\d-\d\d \d\d\:\d\d:\d\d$' "${_file}" > ${_file}.tmp
        _file="${_file}.tmp"
    fi
    _csplit -z -f "${_split_pfx}" "${_file}" "/^${_netstat_str} /" '{*}' || return $?

    ls -1 ${_split_pfx}* | while read _fpath; do
        [[ "${_fpath}" =~ ._([0-9]+)$ ]]
        local _n1="${BASH_REMATCH[1]}"
        if ${_useGonetstat}; then
            gonetstat ${_fpath} > "${_out_dir%/}/netstat_${_n1}.out" && rm -f "${_fpath}"
        else
            mv "${_fpath}" "${_out_dir%/}/netstat_${_n1}.out"
        fi
    done
}
# Extract threads from some stdout log or jvm.log
#curl -o /usr/local/bin/echolines -L https://github.com/hajimeo/samples/raw/master/misc/echolines_$(uname)_$(uname -m);
#HTML_REMOVE=Y EXCL_REGEX="^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d\.\d+" echolines "./sonatype-work/nexus3/log/jvm.log" "^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$" "(^\s+(class space|Metaspace).+)" > "./threads.txt"
function f_jvmlog2threads() {
    local _files="${1:-"./jvm.log"}"
    local _save_to="${2-"./thread_dumps"}"
    local _end_regex="$3"
    local _from_regex="$4"
    [ -z "${_from_regex}" ] && _from_regex="^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$"
    [ -z "${_end_regex}" ] && _end_regex="(^\s+class space.+|^\s+Metaspace\s+.+)"
    if [ -n "${_save_to}" ] && [ "$(ls -A "${_save_to}" 2>/dev/null)" ]; then
        echo "${_save_to} is not empty"
        return 1
    fi
    if [ -z "${_save_to}" ] && [ -s "./threads.txt" ]; then
        echo "./threads.txt is not empty"
        return 1
    fi

    local _cmd="HTML_REMOVE=Y EXCL_REGEX=\"^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d\.\d+\" echolines \"${_files}\" \"${_from_regex}\" \"${_end_regex}\""
    if [ -z "${_save_to}" ]; then
        eval "${_cmd} > ./threads.txt" || return $?
    else
        eval "${_cmd} \"${_save_to}\"" || return $?
        echo "_THREAD_FILE_GLOB=\"0*.out\" f_threads \"${_save_to}\""
    fi
}

function f_wrapper2threads() {
    local __doc__="Concatenate multiple wrapper.log in correct order and generate threads.txt (if 'echolines' is available)"
    local _wrapper_dir="${1:-"."}"
    local _output_to="${2:-"./threads.txt"}"
    local _end_regex="${3:-"^ +class space.+"}"
    if [ -s "${_output_to}" ]; then
        echo "${_output_to} exists."
        return 1
    fi
    find ${_wrapper_dir%/} -name 'wrapper.log*' | sort -r | xargs -I{} -t cat {} | sed "s/^jvm 1    | //" >> ${_output_to}
    if ! type echolines &>/dev/null; then
        echo 'curl -o /usr/local/bin/echolines -L https://github.com/hajimeo/samples/raw/master/misc/logs2csv_$(uname)_$(uname -m)'
        return
    fi
    echolines ${_output_to} "^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$" "(${_end_regex})" > ${_output_to}.tmp
    if [ -s ${_output_to}.tmp ]; then
        mv -v -f ${_output_to}.tmp ${_output_to}
    fi
}

# f_splitScriptLog ./script-20231030142554000.log "Y"
function f_splitScriptLog() {
    local _script_log="$1"
    local _full_split="$2"
    rg -o '^(top - \d\d:\d\d:\d\d|Active Internet |20\d\d-\d\d-\d\d.\d\d:\d\d:\d\d$)' "${_script_log}" | tee /tmp/${FUNCNAME[0]}_$$.tmp
    if head -n2 "/tmp/${FUNCNAME[0]}_$$.tmp" | paste - -  | rg -q 'top - \d\d:\d\d:\d\d\s+Active Internet'; then
        # Assuming top, netstat, thread, repeat
        echolines ${_script_log} '^top - ' '^Active .+' > ./tops.txt
        echolines ${_script_log} '^Active .+' '^20\d\d-\d\d-\d\d.\d\d:\d\d:\d\d' > ./netstats.txt
        HTML_REMOVE=Y echolines ${_script_log} '^20\d\d-\d\d-\d\d.\d\d:\d\d:\d\d$' '^top - ' > ./threads.txt
        cat ./tops.txt ./netstats.txt > ./tops_netstats.txt
    elif head -n1 "/tmp/${FUNCNAME[0]}_$$.tmp" | rg -q '^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]'; then
        # Assuming threads are beginning of the file
        HTML_REMOVE=Y echolines ${_script_log} "^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$" "" ./_tmp_script_log
        ls -1 _tmp_script_log/* | while read _f; do
            local _prefix=$(basename ${_f})
            sed -n "/^top - /q;p" "${_f}" > ./${_prefix}_threads.txt
            sed -n "/^top - /,\$p" "${_script_log}" > ./${_prefix}_tops_netstats.txt
        done
    else
        # Expecting threads are end of the file
        sed -n "/^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/,\$p" "${_script_log}" > ./threads.raw
        sed -n "/^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/q;p" "${_script_log}" > ./tops_netstats.txt

        if [ -s ./threads.raw ]; then
            cat ./threads.raw | python3 -c "import sys,html,re;rx=re.compile(r\"<[^>]+>\");print(html.unescape(rx.sub(\"\",sys.stdin.read())))" > threads.txt && rm -f ./threads.raw
        fi
    fi
    if [[ "${_full_split}" =~ [yY] ]]; then
        [ -s ./threads.txt ] && f_threads ./threads.txt
        if [ -s ./tops_netstats.txt ]; then
            f_splitTopNetstat ./tops_netstats.txt >/dev/null
            f_check_topH ./tops_netstats.txt
            f_check_netstat ./tops_netstats.txt
        fi
    fi
}

#f_splitByRegex threads.txt "^${_DATE_FORMAT}.+"
#f_threads "?-dump.txt"   # Don't use "*" beginning of the file name
# NOTE: f_last_tid_in_log would be useful.
# Full thread dump OpenJDK 64-Bit Server VM (25.352-b08 mixed mode):
function f_threads() {
    # TODO: replace the split part to echolines
    local __doc__="Split file to each thread, then output thread count"
    local _file="$1"    # Or dir contains thread_xxxx.txt files
    local _split_search="${2}"  # "^\".+" or if NXRM2, "^[a-zA-Z].+"
    local _running_thread_search_re="${3-".sonatype."}"
    local _save_dir="${4}"
    local _not_split_by_date="${5:-${_NOT_SPLIT_BY_DATE}}"
    local _incl_datetime_rx="${6:-${_INCL_DATETIME_RX}}"

    [ -z "${_save_dir%/}" ] && _save_dir="./_threads"
    local _thread_file_glob="${_THREAD_FILE_GLOB:-"thread*.txt*"}"
    if [ -z "${_file}" ]; then
        _file="$(find . -type f -name threads.txt 2>/dev/null | grep "${_thread_file_glob}" -m 1)"
        [ -z "${_file}" ] && _file="."
    elif [ ! -f "${_file}" ] && [ ! -d "${_file}" ]; then
        _thread_file_glob="${_file}"
        _file="."
    fi

    if [ -z "${_split_search}" ]; then
        if rg -q "^\".+" "${_file}"; then
            _split_search="^\".+"
        else
            _split_search="^[a-zA-Z].+"
        fi
    fi

    if [ -z "${_save_dir%/}" ]; then
        if [ -f "${_file}" ]; then
            local _filename=$(basename ${_file})
            _save_dir="_${_filename%%.*}"
        fi
        [ -z "${_save_dir%/}" ] && _save_dir="./_threads"
    fi

    [ ! -d "${_save_dir%/}" ] && mkdir -p ${_save_dir%/}
    local _tmp_dir="./_threads_per_datetime"

    if [ -f "${_file}" ] && [[ ! "${_not_split_by_date}" =~ ^(y|Y) ]]; then
        local _how_many_threads=$(rg '^20\d\d-\d\d-\d\d \d\d:\d\d:\d\d' -c ${_file})
        echo "## Found ${_how_many_threads} threads from ${_file}"
        if [ 1 -lt ${_how_many_threads:-0} ]; then
            echo "## Check if any 'Heap' information exists"
            rg '^Heap' -A8 ${_file} | rg '(total|\d\d+% used)'    # % didn't work with G1GC
            echo " "
            echo "## Check if any 'deadlock' information exists"
            rg -i 'deadlock' ${_file}
            echo " "

            f_splitByRegex "${_file}" "^20\d\d-\d\d-\d\d \d\d:\d\d:\d\d" "${_tmp_dir%/}" "" || return $?
            _file="${_tmp_dir%/}"
        fi
    fi

    if [ -d "${_file}" ]; then
        local _count=0
        # _count doesn't work with 'while'
        #find ${_file%/} -type f -name 'threads*.txt' 2>/dev/null | while read -r _f; do
        for _f in $(find ${_file%/} -type f \( -name "${_thread_file_glob}" -o -name '20*.out' \) -print 2>/dev/null | sort -n); do
            local _filename=$(basename ${_f})
            _count=$(( ${_count} + 1 ))
            if [ -s "./f_thread_${_filename%.*}.out" ]; then
                _LOG "WARN" "./f_thread_${_filename%.*}.out exists, so not executing f_threads ..."
                continue
            fi
            if ! head -n1 "${_f}" | grep -E "${_incl_datetime_rx}"; then
                _LOG "WARN" "The first line of $(basename ${_f}) does not start with '${_incl_datetime_rx}', so not executing f_threads ..."
                continue
            fi
            _LOG "INFO" "Saving outputs into f_thread_${_filename%.*}.out (and ${_save_dir%/}/${_filename%.*}) ..."
            f_threads "${_f}" "${_split_search}" "${_running_thread_search_re}" "${_save_dir%/}/${_filename%.*}" "Y" > ./f_thread_${_filename%.*}.out
            _LOG "INFO" "f_thread_${_filename%.*}.out $(_elapsed)"
        done

        echo " "
        # Doing below only when checking multiple thread dumps
        f_analyse_multiple_dumps "${_save_dir}" "${_running_thread_search_re}"
        return $?
    fi

    _elapsed &>/dev/null
    f_splitByRegex "${_file}" "${_split_search}" "${_save_dir%/}" ""
    _LOG "INFO" "f_splitByRegex with \"${_file}\" \"${_split_search}\" \"${_save_dir%/}\" $(_elapsed)"

    echo "## Listening ports (acceptor)"
    # Sometimes this can be a hostname
    #rg '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+' --no-filename "${_file}"
    rg '^[^ ].+(\-acceptor\-| Acceptor\d+).+:\d+[\} "]' --no-filename "${_file}" | sort | uniq
    echo " "

    echo "## Counting 'QueuedThreadPool.*\.run' for Jetty pool (QueuedThreadPool.runJob may not work with older NXRM2)"
    echo "BLOCKED: $(rg '\bQueuedThreadPool.*\.run' ${_save_dir%/}/ -l -g '*BLOCKED*' -g '*blocked*' | wc -l)"
    echo "RUNNABLE:$(rg '\bQueuedThreadPool.*\.run' ${_save_dir%/}/ -l -g '*RUNNABLE*' -g '*runnable*' | wc -l)"
    echo "WAITING: $(rg '\bQueuedThreadPool.*\.run' ${_save_dir%/}/ -l -g '*WAITING*' -g '*waiting*' | wc -l)"
    echo " "

    echo "## 'deadlock'"
    rg -i -w 'deadlock' ${_save_dir%/}/ -m1 --no-filename | sort | uniq -c
    echo " "

    echo "## Counting 'Pool.acquire' for DB pool"
    rg -i 'Pool\.acquire\b' ${_save_dir%/}/ -m1 --no-filename | sort | uniq -c
    echo " "

    echo "## Counting *probably* waiting for connection pool by checking 'getConnection' and 'org.apache.http.pool.PoolEntryFuture.await'"
    rg -m1 '\b(getConnection|org.apache.http.pool.PoolEntryFuture.await)\b' ${_save_dir%/}/ -g '*WAITING*' -g '*waiting*' --no-filename | sort | uniq -c
    echo " "

    echo "## Counting locked thread from 'Locked ownable synchronizers:' and runnable and more than 3"
    rg "Locked ownable synchronizers:" -l -g '*runnable*' ${_save_dir%/} | while read -r _f; do
        rg -H -c '^\s+- <0x' ${_f} | rg -v ":[1-2]$"
    done | sort -t":" -k1,1 -k2,2r
    echo " "

    echo "## Finding BLOCKED or waiting to lock lines (excluding '-acceptor-')"
    rg -w '(BLOCKED|waiting to lock)' -C1 --no-filename -g '!*-acceptor-*' -g '!*_Acceptor*' ${_save_dir%/}/
    echo " "

    #echo "## Counting 2nd lines from .out files (top 20)"
    #awk 'FNR == 2' ${_save_dir%/}/*.out | sort | uniq -c | sort -r | head -n 20
    #echo " "

    echo "## Counting 'waiting to lock|waiting on|waiting to lock' etc. basically hung processes (excluding smaller than 2k size threads, 'parking to wait for' and 'None', and top 20)"
    rg '^\s+\- [^<]' --no-filename `find ${_save_dir%/} -type f -size +2k` | rg -v '(- locked|- None|parking to wait for)' | sort | uniq -c | sort -nr | tee /tmp/f_threads_$$_waiting_counts.out | head -n 20
    echo " "

    echo "## Checking 'parking to wait for' qtp threads, because it may indicate the pool exhaustion issue (eg:NEXUS-17896 / NEXUS-10372) (excluding smaller than 2k size threads)"
    #rg '\bparking to wait for\b' -l `find ${_save_dir%/} -type f -size +2k -name 'qtp*.out'` | wc -l
    find ${_save_dir%/} -type f -size +2k \( -name 'qtp*.out' -o -name 'dw-*.out' \) -print | while read -r _f; do
        rg '\bparking to wait for\s+<([^>]+)>.+\(([^\)]+)\)' -o -r '$1 $2' "${_f}"
    done | sort | uniq -c | sort -nr | head -n10
    # NOTE: probably java.util.concurrent.SynchronousQueue can be ignored
    echo " "

    # At least more than 5 waiting. waiting_counts.out can be empty
    local _most_waiting="$(rg -m 1 '^\s*([5-9]|\d\d+)\s+.+(0x[0-9a-f]+)' -o -r '$2' /tmp/f_threads_$$_waiting_counts.out 2>/dev/null)"
    if [ -n "${_most_waiting}" ]; then
        echo "## Finding thread(s) locked '${_most_waiting}' (excluding smaller than 2k size threads)"
        # I was doing 'rg ... `find ...` | xargs', but when find is empty, rg checks everything, so below is not efficient but safer
        find ${_save_dir%/} -type f -size +2k -name '*.out' -print | while read -r _f; do
            if rg -q "locked.+${_most_waiting}" -l "${_f}"; then
                rg -H '(java.lang.Thread.State:| state=)' "${_f}"
            fi
        done
        echo " "

        echo "## Finding top 10 'owned by' for '${_most_waiting}' (excluding smaller than 1k threads)"
        rg "waiting to lock .${_most_waiting}\b" -A1 ${_save_dir%/} | rg -o 'owned by .+' | sort | uniq -c | sort -n | head -n10
        echo " "

        echo "## Finding (TIMED_)WAITING which contains \"${_running_thread_search_re}\""
        rg 'State:\s*.*WAITING' -l ${_save_dir%/} | xargs -I{} rg -m1 "${_running_thread_search_re}" {} | sort | uniq -c | sort -nr | head -n10
        echo " "
    fi

    echo "## 'locked' objects or id excluding synchronizers (top 20 and more than once)"    # | rg -v '^\s+1\s'
    rg ' locked [^ @]+' -o --no-filename ${_save_dir%/}/ | rg -vw synchronizers | sort | uniq -c | sort -nr | head -n 20
    echo " "

    if [ -n "${_running_thread_search_re}" ]; then
        #echo "## Finding running threads with size is over 4k and containing '${_running_thread_search_re}'"
        #find ${_save_dir%/} -size +4k -iname '*run*' -exec rg -H -m1 "${_running_thread_search_re}[^$]+$" {} \;
        #echo " "

        echo "## Finding popular first *3* methods from *probably* running threads containing '${_running_thread_search_re}'"
        #rg -w RUNNABLE -A1 -H ${_save_dir%/} | rg '^\sat' | sort | uniq -c
        rg "${_running_thread_search_re}" -l -g '*runnable*' ${_save_dir%/} | xargs -P3 -I {} rg '^\s+at\s' -m3 "{}" | sort | uniq -c | sort -nr | head -10
        # NOTE: RUNNABLE "sun.nio.ch.EPollArrayWrapper.epollWait" would be ignorable
        # https://support.sonatype.com/hc/en-us/articles/360000744687-Understanding-Eclipse-Jetty-9-4-Thread-Allocation#SelectorManager-SelectorThreads
        echo " "

        echo "## Finding first line which contains \"${_running_thread_search_re}\" from RUNNABLE"
        rg 'State:\s*RUNNABLE' -l ${_save_dir%/} | xargs -I{} rg -m1 "${_running_thread_search_re}" {} | sort | uniq -c | sort -nr | head -n10
        echo " "

        echo "## Finding runnable (expecting QuartzTaskJob) '${_running_thread_search_re}.+Task.execute' from ${_save_dir%/}"
        rg -m1 -s "${_running_thread_search_re}.+Task\.execute\(" -g '*runnable*' "${_save_dir%/}"
        echo " "

        echo "## Counting (BLOCKED|waiting to lock) except acceptors and first 10 matching and more than 10 threads"
        rg -w '(BLOCKED|waiting to lock)' -l -g '!*-acceptor-*' -g '!*_Acceptor*' "${_save_dir%/}" | while read -r _ff; do
            rg -m10 "${_running_thread_search_re}" "${_ff}"
        done | sort | uniq -c | sort -r | rg '^\s*\d\d+'
        echo " "
    fi

    echo "## Counting thread types excluding WAITING (top 20)"
    # java 17 has the lines starting with 0x
    rg '^[^\s]...' ${_file} | rg -v -i WAITING | rg -v '^0x' | _replace_number 1 | sort | uniq -c | sort -nr | head -n 20
    echo " "

    echo "### Counting thread states"
    _thread_state_sum "${_file}"
    echo " "

    echo "### (Java 17 only) top 5 CPU consuming non GC etc, running threads"
    #rg '^("[^\"]+").+cpu=(\S+).+elapsed=(\S+)' -o -r '$1,$2,$3' ${_file} | rg '^"qtp' | sort -t',' -k3nr | head -n5
    f_threads_cpu_elapsed "${_save_dir%/}" | rg 'RUNNABLE' | sort -t',' -k2nr | head -n5
    echo " "

    echo "### _threads_extra_check against ${_file} (product specific issues)"
    _threads_extra_check "${_file}"
}
function f_threads_cpu_elapsed() {  # Java 17 only
    local _dir="$1"
    local _running_thread_search_re="${2:-".sonatype."}"
    local _times="${3:-"3"}"
    rg "${_running_thread_search_re}" -l "${_dir}" | while read -r _file; do
        _t_c_e="$(rg '^("[^\"]+").+cpu=(\S+).+elapsed=(\S+)' -o -r '$1,$2,$3' ${_file})"
        _state="$(head -n2 ${_file} | rg -i 'java.lang.Thread.State:\s*(.+)$' -o -r '$1')"
        echo "${_t_c_e},\"${_state:-"(unknown)"}\""
    done
}
function f_analyse_multiple_dumps() {
    local _individual_thread_dir="${1:-"."}"
    local _running_thread_search_re="${2-".sonatype."}"
    local _times="${3:-"3"}"

    echo "## Thread status counts from ./f_thread_*.out"
    rg -A10 '^### Counting thread states' --no-filename ./f_thread_*.out | rg -v '^#'
    echo " "

    echo "## Long running threads and no-change (same hash) threads which contain '${_running_thread_search_re}' and +3k"
    _elapsed &>/dev/null
    _long_running "${_individual_thread_dir%/}" "${_running_thread_search_re}" "${_times}" "3k"
    echo 'NOTE: rg -A7 -m1 "RUNNABLE" -g <filename>'
    _LOG "INFO" "_long_running $(_elapsed)"
    echo " "
    echo "## Potential network slowness \"ConditionObject\.await .+ ${_running_thread_search_re}\" threads"
    _many_wait "${_individual_thread_dir%/}" "${_running_thread_search_re}"
    _LOG "INFO" "_many_wait $(_elapsed)"
    echo " "

    # not easy to check size so using _running_thread_search_re
    echo "## Long Running (more than ${_times} times) threads which contain '${_running_thread_search_re}' (size +2k but can be diff)"
    find ${_individual_thread_dir%/} -type f -size +2k -iname '*run*.out' -print | while read -r _f; do
        if rg -q "${_running_thread_search_re}" ${_f}; then
            echo "$(basename ${_f})"
        fi
    done | sort | uniq -c | rg "^\s+([${_times}-9]|\d\d+)\s+.+" -o | sort -nr
    #| rg -v "(ParallelGC|G1 Concurrent Refinement|Parallel Marking Threads|GC Thread|VM Thread)"
    echo " "

    echo "## Counting methods per the Running thread, which thread contains '${_running_thread_search_re}'"
    rg "${_running_thread_search_re}" -l -g '*runnable*' ${_individual_thread_dir%/} | while read -r _f; do
        echo "$(basename "${_f}") $(rg '^\sat\s' -m1 "${_f}")"
    done | sort | uniq -c | sort -nr | rg -v '^\s*1\s' | head -n40
    echo " "

    echo "## Counting locked thread from 'Locked ownable synchronizers:' and runnable and more than 3"
    rg "Locked ownable synchronizers:" -l -g '*runnable*' ${_individual_thread_dir%/} | while read -r _f; do
        rg -H -c '^\s+- <0x' ${_f} | rg -v ":[1-2]$"
    done | sort -t":" -k1,1 -k2,2r
    echo " "

    echo "### May also want to use the below (need double-quotes):
     f_splitTopNetstat \"./tops_netstats.txt\"
     f_check_topH \"top_netstat/top_0*\"
     f_check_netstat \"top_netstat/netstat_0*\""
    echo " "
}
function _thread_state_sum() {
    local _file="$1"
    if rg -q 'java.lang.Thread.State:' ${_file}; then
        rg 'java.lang.Thread.State:\s*(.+)$' -o -r '$1' --no-filename ${_file} | sort | uniq -c
    elif rg -q 'state=' ${_file}; then
        rg -iw 'state=(.+)' -o -r '$1' --no-filename ${_file} | sort -r | uniq -c
    else
        rg -iw 'nid=0x[a-z0-9]+ ([^\[]+)' -o -r '$1' --no-filename ${_file} | sort -r | uniq -c
    fi
    echo "Total: `rg '^"' ${_file} -c`"
}
function _long_running() {
    local _search_dir="${1:-"."}"
    local _search_re="${2}"
    local _min_count="${3:-"3"}"
    local _size="${4:-"2k"}"
    find ${_search_dir%/} -type f -size +${_size} -print | while read -r _f; do
        if [ -n "${_search_re}" ] && ! rg -q "${_search_re}" ${_f}; then
            continue
        fi
        echo "$(basename "${_f}") ($(tail -n +2 ${_f} | md5))"
    done | sort | uniq -c | rg "^\s*([${_min_count}-9]|\d\d+)\s+" | sort -nr | tee /tmp/${FUNCNAME[0]}_$$.out
    if [ -s /tmp/${FUNCNAME[0]}_$$.out ]; then
        echo "NOTE: /tmp/${FUNCNAME[0]}_$$.out exists."
    fi
}
function _many_wait() {
    local _search_dir="${1:-"."}"   # "_threads"
    local _search_re="${2}"         # "sonatype"
    local _min_10_count="${3:-"2"}"
    #local _size="${4:-"1k"}"   # For performance, not using size
    #find ${_search_dir%/} -type f -iname '*waiting_on_condition*.out' -size -${_size} -print | while read -r _f; do
    rg -l "ConditionObject\.await\(." -g '*waiting_on_condition*.out' -g '*WAITING_ON_CONDITION*.out' "${_search_dir}" | while read -r _f; do
        local _method=""
        if [ -n "${_search_re}" ]; then
            _method="$(rg -m1 "${_search_re}" ${_f})"
            [ -z "${_method}" ] && continue
        fi
        echo "$(dirname "${_f}") ${_method}"
    done | sort | uniq -c | rg "^\s*([${_min_10_count}-9]\d|\d\d\d+)\s+" | sort -nr
}
function _threads_extra_check() {
    local _file="${1:-"threads.txt"}"
    if [ -n "${_file}" ] && [ ! -f "${_file}" ]; then
        #_file="--no-filename -g \"${_file}\""
        _file="$(_find "${_file}")"
    fi
    if [ -z "${_file}" ]; then
        echo "## No file provided for _threads_extra_check" >&2
        return 1
    fi
    rg '(DefaultTimelineIndexer|content_digest|findAssetByContentDigest|touchItemLastRequested|preClose0|sun\.security\.util\.MemoryCache|java\.lang\.Class\.forName|CachingDateFormatter|metrics\.health\.HealthCheck\.execute|WeakHashMap|userId\.toLowerCase|MessageDigest|UploadManagerImpl\.startUpload|UploadManagerImpl\.blobsByName|maybeTrimRepositories|getQuarantinedVersions|nonCatalogedVersions|getProxyDownloadNumbers|RepositoryManagerImpl.retrieveConfigurationByName|\.StorageFacetManagerImpl\.|OTransactionRealAbstract\.isIndexKeyMayDependOnRid|AptFacetImpl.put|componentMetadata|ensureGetUpload|OrientCommonQueryDataService|getWaivedFixed|AbstractOperationalSqlDAO\.getAll|NewestRiskService|acquireLock|com\.sonatype\.insight\.brain\.dataaccess\.policy\.PolicyViolationDAO\.getUnfixed|SearchTableStore\.searchComponents)' ${_file} | sort | uniq -c > /tmp/$FUNCNAME_$$.out || return $?
    if [ -s /tmp/$FUNCNAME_$$.out ]; then
        echo "## Counting:"
        echo "##    'DefaultTimelineIndexer' for NXRM2 System Feeds: timeline-plugin,"
        # https://support.sonatype.com/hc/en-us/articles/213464998-How-to-disable-the-System-Feeds-nexus-timeline-plugin-feature-to-improve-Nexus-performance
        echo "##    'content_digest' NEXUS-26379 (3.29.x) and NEXUS-25294 (3.27.x and older)"
        echo "##    'findAssetByContentDigest' NEXUS-26379 / NEXUS-36069"
        echo "##    'touchItemLastRequested' NEXUS-10372 all NXRM2"
        echo "##    'preClose0' NEXUS-30865 Jetty, all NXRM2"
        echo "##    'MemoryCache' https://bugs.openjdk.java.net/browse/JDK-8259886 < 8u301"
        echo "##    'java.lang.Class.forName' NEXUS-28608 up to NXRM 2.14.20"
        echo "##    'CachingDateFormatter' NEXUS-31564 (logback)"
        echo "##    'com.codahale.metrics.health.HealthCheck.execute' (nexus.healthcheck.refreshInterval)"
        echo "##    'WeakHashMap' NEXUS-10991"
        echo "##    'userId\.toLowerCase' NEXUS-31776"
        echo "##    'UploadManagerImpl.startUpload|.blobsByName' NEXUS-31395"
        echo "##    'MessageDigest' (May indicate CPU resource issue?)"
        echo "##    'maybeTrimRepositories' NEXUS-28891"
        echo "##    'getQuarantinedVersions|nonCatalogedVersions' NEXUS-31891"
        echo "##    'getProxyDownloadNumbers' NEXUS-37536"
        echo "##    'RepositoryManagerImpl.retrieveConfigurationByName' NEXUS-38579"
        echo "##    'StorageFacetManagerImpl' Storage facet cleanup might might cause performance issue"
        echo "##    'OTransactionRealAbstract.isIndexKeyMayDependOnRid' https://github.com/orientechnologies/orientdb/issues/9396"
        echo "##    'AptFacetImpl.put' NEXUS-30812 / NEXUS-37102"
        echo "##    'componentMetadata' CLM-26850"
        echo "##    'ensureGetUpload' NEXUS-40177"
        echo "##    'OrientCommonQueryDataService' NEXUS-41312"
        echo "##    'getWaivedFixed' CLM-29328"
        echo "##    'AbstractOperationalSqlDAO.getAll' CLM-29339"
        echo "##    'getUnfixed' CLM-31559"
        echo "##    'NewestRiskService' dashboard/policy/newestRisks"
        echo "##    'acquireLock' SELECT * FROM insight_brain_ods.lock WHERE lock_id = \$1 FOR UPDATE"
        echo "##    'SearchTableStore.searchComponents' NEXUS-43504"
        cat /tmp/$FUNCNAME_$$.out
        echo " "
    fi
}

#f_last_tid_in_log "" ../support-20200915-143729-1/log/request.log "15/Sep/2020:08:" > f_last_tid_in_log.csv 2> f_last_tid_in_log.err
#qcsv "select * from f_last_tid_in_log.csv order by c4 limit 1"
function f_last_tid_in_log() {
    local __doc__="Get thread IDs (starts with \") from the tread dump, then find the *last* match from the log"
    local _threads_file="$1"
    local _log="$2"     # NOTE: deafult is request.log but some request.log does not have tid at all.
    local _log_rx="${3}"
    local _tid_rx="${4:-"^\"([^\" ]+)"}"    # TODO: shouldn't include space but tedious if space is included
    [ -z "${_threads_file}" ] && _threads_file="$(find . -type f -name threads.txt 2>/dev/null | grep '/threads.txt$' -m 1)"
    [ -z "${_threads_file}" ] && return 1
    [ -z "${_log}" ] && _log="$(find . -type f -name request.log 2>/dev/null | grep '/request.log$' -m 1)"
    [ -z "${_log}" ] && return 1
    _tac "${_log}" > /tmp/f_last_tid_in_log.log || return $?    # Not using $$ as it can be large
    rg "${_tid_rx}" -o -r '$1' "${_threads_file}" | rg -v -- '-acceptor-' | sort | uniq | while read -r _tid; do
        #echo "# Checking '${_tid}' ..." >&2
        # expecting tid is surrounded by [] or ""
        if ! rg -w -m 1 "${_log_rx}.*[\[\"]${_tid}[\]\"]" /tmp/f_last_tid_in_log.log; then
            echo "# No match for '${_tid}'" >&2
            if [ -d ./_threads ]; then
                find ./_threads -name "*${_tid}[_-]*" -ls >&2
            fi
        fi
    done
}

#2023-03-09 09:26:37,551-0500 WARN  [qtp1219689879-378062]  ADUBEY19
function f_find_requests() {
    local _date_lvl_thread_user="$1"
    local _rg_opts="${2-"-g \"request*log*\""}"
    if [[ "${_date_lvl_thread_user}" =~ ([0-9]{4})-[0-9]{2}-[0-9]{2}.([^, ]+).+[[:space:]]+\[([^]]+)\][[:space:]]+([^ ]*) ]]; then
        local _regex=""
        if [ -n "${BASH_REMATCH[4]}" ]; then
            _regex="${_regex}\s+${BASH_REMATCH[4]}\s+"
        fi
        _regex="${_regex}.+[:/-]${BASH_REMATCH[1]}:${BASH_REMATCH[2]}.+\[${BASH_REMATCH[3]}\]"
        local _cmd="rg '${_regex}' ${_rg_opts}"
        echo "$ ${_cmd}"
        eval "${_cmd}"
    fi
}

function f_request2csv() {
    local __doc__="Convert a jetty request.log to a csv file"
    local _glob="${1:-"request.log"}"
    local _out_file="${2}"
    local _filter="${3}"    # eg "\[\d\d/.../\d\d\d\d:0[789]"
    local _pattern_str="${4}"

    local _g_opt="-g"
    [ -s "${_glob}" ] && _g_opt=""

    if [ -d "${_out_file}" ]; then
        _out_file="${_out_file%/}/$(basename ${_glob} .log).csv"
    elif [ -z "${_out_file}" ]; then
        _out_file="$(basename ${_glob} .log).csv"
    fi
    # NOTE: check jetty-requestlog.xml and logback-access.xml
    if [ -z "${_pattern_str}" ]; then
        _pattern_str="$(rg -g logback-access.xml -g jetty-requestlog.xml --no-filename -m1 -w '^\s*<pattern>(.+)</pattern>' -o -r '$1' | sort | uniq | tail -n1)"
        # Or IQ uses: "%clientHost %l %user [%date] \"%requestURL\" %statusCode %bytesSent %elapsedTime \"%header{User-Agent}\""
        # If _patter_str is still empty, doing best guess.
        if [ -z "${_pattern_str}" ]; then
            local _tmp_first_line="$(rg --no-filename -m1 -z '\b20\d\d.\d\d.\d\d' ${_g_opt} "${_glob}")"
            #echo "# first line: ${_tmp_first_line}" >&2
            if echo "${_tmp_first_line}"   | rg -q '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) "([^"]*)" \[([^\]]+)\]$'; then
                _pattern_str='%clientHost %l %user [%date] "%requestURL" %statusCode %header{Content-Length} %bytesSent %elapsedTime "%header{User-Agent}" [%thread]'
            elif echo "${_tmp_first_line}" | rg -q '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) "([^"]*)" \[([^\]]+)\] (.+)$'; then
                _pattern_str='%clientHost %l %user [%date] "%requestURL" %statusCode %header{Content-Length} %bytesSent %elapsedTime "%header{User-Agent}" [%thread] %misc'
            elif echo "${_tmp_first_line}" | rg -q '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) "([^"]*)"$'; then
                _pattern_str='%clientHost %l %user [%date] "%requestURL" %statusCode %header{Content-Length} %bytesSent %elapsedTime "%header{User-Agent}"'
            elif echo "${_tmp_first_line}" | rg -q '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) "([^"]*)" \[([^\]]+)\]$'; then
                _pattern_str='%clientHost %l %user [%date] "%requestURL" %statusCode %bytesSent %elapsedTime "%header{User-Agent}" [%thread]'
            elif echo "${_tmp_first_line}" | rg -q '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) "([^"]*)" \[([^\]]+)\] (.+)$'; then
                _pattern_str='%clientHost %l %user [%date] "%requestURL" %statusCode %bytesSent %elapsedTime "%header{User-Agent}" [%thread] %misc'
            elif echo "${_tmp_first_line}" | rg -q '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) "([^"]*)" (.+)$'; then
                _pattern_str='%clientHost %l %user [%date] "%requestURL" %statusCode %bytesSent %elapsedTime "%header{User-Agent}" "%misc"'
            elif echo "${_tmp_first_line}" | rg -q '^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) "([^"]*)"'; then
                _pattern_str='%clientHost %l %user [%date] "%requestURL" %statusCode %bytesSent %elapsedTime "%header{User-Agent}"'
            elif echo "${_tmp_first_line}" | rg -q '^\[([^\]]+)\] ([^ ]+) "([^"]+)" ([^ ]+) ([^ ]+) ([^ ]+) "([^"]*)"'; then
                # Nexus outbound-request.log
                _pattern_str='[%date] %user "%requestURL" %statusCode %bytesSent %elapsedTime "%header{User-Agent}"'
            else
                _pattern_str="%clientHost %l %user [%date] \"%requestURL\" %statusCode %bytesSent %elapsedTime"
            fi
            # NOTE: if the above is updated, also update analyse_logs._gen_regex_for_request_logs
        fi
        echo "# pattern_str: ${_pattern_str}" >&2
    fi
    if [ -z "${_pattern_str}" ]; then
        echo "_pattern_str required." >&2
        return 1
    fi
    echo "\"$(echo "${_pattern_str}" | tr -cd '[:alnum:]._ ' | _sed 's/ /","/g')\"" > "${_out_file}"
    local _pattern="^$(_gen_pattern "${_pattern_str}")"
    echo "# pattern: ${_pattern}" >&2
    local _pattern_out=""
    local _i=1
    for _col in ${_pattern_str}; do
        if [ -n "${_pattern_out}" ]; then
            _pattern_out="${_pattern_out},"
        fi
        if [[ "${_col}" =~ (bytesSent|elapsedTime) ]]; then
            _pattern_out="${_pattern_out}\$${_i}"
        else
            _pattern_out="${_pattern_out}\"\$${_i}\""
        fi
        _i=$((_i + 1))
    done
    if [ -n "${_filter}" ]; then
        # TODO: this would be slower than single 'rg'
        rg --no-filename -N -z "${_filter}" ${_g_opt} "${_glob}" | rg "${_pattern}" -o -r "${_pattern_out}"
    else
        rg --no-filename -N -z "${_pattern}" -o -r "${_pattern_out}" ${_g_opt} "${_glob}"
    fi >> ${_out_file}
    local _rc=$?
    [ ${_rc} -ne 0 ] && cat /dev/null > "${_out_file}" || echo "Completed. Use 'f_reqsFromCSV \"${_out_file}\"' as well" >&2
    return ${_rc}
}

#f_log2csv "(Starting|Finished) upload to key (.+) in bucket" nexus.log ",\"\$6\",\"\$7\"" ",start_end,key" > ./s3_upload.csv
#qcsv -H "SELECT min(date_time) as min_dt, max(date_time) as max_dt, CAST((julianday(max(date_time)) - julianday(min(date_time))) * 86400000 AS INT) as duration_ms, SUM(CASE WHEN start_end = 'Starting' THEN 1 WHEN start_end = 'Finished' THEN -1 ELSE -99999 END) as sum_start_end, key FROM ./s3_upload.csv GROUP BY key HAVING sum_start_end = 0 ORDER BY min_dt"
#
#rg SocketTimeoutException -B1 ./log/nexus.log | rg '^2021-03-11' > nexus_filtered.log
#f_log2csv "" "nexus_filtered.log" > nexus_filtered.csv
# NOTE: change date and timezone. Also not perfect as not considering duration.
#q -O -d"," -D"," -H "SELECT '18/Mar/2021:'||strftime('%H:%M:%S', date_time)||' -0700' as req_datetime, thread, message FROM ./nexus_filtered.csv" > nexus_filtered_req.csv
#qcsv -H "SELECT r.*, n.message FROM ./_filtered/request.csv r JOIN nexus_filtered_req.csv n ON r.date = n.req_datetime and r.thread = n.thread"
function f_log2csv() {
    local _log_regex="${1:-"- (.*)"}"
    local _glob="${2:-"*.log"}"
    local _r_from_6_append="${3:-"\"\$6\""}"
    local _col_append="${4:-"message"}"
    # Sqlite does not like "," before milliseconds
    rg "^(${_DATE_FORMAT}.\d\d:\d\d:\d\d).([\d]+)[^\[]+\[([^\]]+)\] [^ ]* ([^ ]*) ([^ ]+) ${_log_regex}" -o -r '"$1.$2","$3","$4","$5",'${_r_from_6_append} --no-filename -g "${_glob}" > /tmp/f_log2csv_$$.out
    if [ -s /tmp/f_log2csv_$$.out ]; then
        echo "date_time,thread,user,class,${_col_append}" | cat - /tmp/f_log2csv_$$.out
    fi
}

# Accept _REQ_ORDER_BY and _REQ_LIMIT env variables
function f_reqsFromCSV() {
    local _file="${1:-"request.csv"}"
    local _where="${2}"
    local _elapsedTime_gt="${3:-"7000"}"
    if [ -n "${_file}" ] && [ ! -f "${_file}" ]; then
        _file="$(_find "${_file}")"
    fi
    [ -z "${_file}" ] && return 1
    local _extra_cols=""
    #local _extra_cols_where=" AND (headerContentLength <> '-' AND headerContentLength <> '0')"
    head -n1 "${_file}" | grep -q "headerContentLength" && _extra_cols=", headerContentLength"
    if [ -n "${_where}" ] && [[ ! "${_where}" =~ [[:space:]]*(AND|and)[[:space:]] ]]; then
        _where="AND ${_where}"
    fi
    local _sql="SELECT clientHost, user, date, requestURL, statusCode, bytesSent ${_extra_cols}, elapsedTime, CAST((CAST(bytesSent as INT) / CAST(elapsedTime as INT)) as DECIMAL(10, 2)) as bytes_per_ms, TIME(CAST((julianday(DATE('now')||' '||substr(date,13,8))  - 2440587.5) * 86400.0 - elapsedTime/1000 AS INT), 'unixepoch') as started_time FROM ${_file} WHERE elapsedTime >= ${_elapsedTime_gt} ${_where} order by ${_REQ_ORDER_BY:-"elapsedTime DESC"} limit ${_REQ_LIMIT:-"40"}"
    echo "# SQL: ${_sql}" >&2
    q -O -d"," -T --disable-double-double-quoting -H "${_sql}"
}


function _gen_pattern() {
    local _pattern_str="${1}"
    local _pattern=""
    for _p in ${_pattern_str}; do
        local _first_c="${_p:0:1}"
        local _last_c="${_p: -1}"
        if [ "${_last_c}" == "\"" ]; then
            _pattern="${_pattern# } ${_first_c}([^\"]+)${_last_c}"
        elif [ "${_last_c}" == "]" ]; then
            _pattern="${_pattern# } \\${_first_c}([^\]]+)\\${_last_c}"
        else
            _pattern="${_pattern# } ([^ ]+)"
        fi
    done
    echo "${_pattern}"
}

function f_audit2json() {
    local __doc__="Convert audit.log which looks like a json but not"
    local _glob="${1:-"audit.log"}"
    local _out_file="$2"

    if [ -d "${_out_file}" ]; then
        _out_file="${_out_file%/}/$(basename ${_glob} .log).json"
    elif [ -z "${_out_file}" ]; then
        _out_file="$(basename ${_glob} .log).json"
    fi

    rg --no-filename -N -z "^(\{.+\})\s*$" -o -r ',$1' -g "${_glob}" > ${_out_file}
    if [ -s ${_out_file} ]; then
        echo "]" >> ${_out_file}
        _sed -i '1s/^,/[/' ${_out_file}
    fi
}

function f_healthlog2json() {
    local __doc__="TODO: Convert some log text to json"
    local _glob="${1:-"nexus.log"}"
    local _out_file="${2:-"health_monitor.json"}"
    rg "^($_DATE_FORMAT.\d\d:\d\d:\d\d).(\d+).+INFO.+com.hazelcast.internal.diagnostics.HealthMonitor - \[([^]]+)\]:(\d+) \[([^]]+)\] \[([^]]+)\] (.+)" -r 'date_time=${1}.${2}, address=${3}:${4}, user=${5}, cluster_ver=${6}, ${7}' --no-filename -g ${_glob} > /tmp/f_log2json_$$.tmp
    if [ -s /tmp/f_log2json_$$.tmp ]; then
        _sed -r 's/ *([^=]+)=([^,]+),?/"\1":"\2",/g' /tmp/f_log2json_$$.tmp | _sed 's/,$/}/g' | _sed 's/^"/,{"/g' > ${_out_file}
        echo ']' >> ${_out_file}
        _sed -i '1s/^,/[/' ${_out_file}
    fi
}

function f_healthlog2csv() {
    local __doc__="TODO: Convert some log text to csv. Requires python3 and pandas"
    local _glob="${1:-"nexus.log"}"
    local _out_file="${2:-"health_monitor.csv"}"
    f_healthlog2json "${_glob}" "/tmp/_health_monitor_$$.json" || return $?
    [ -s "/tmp/_health_monitor_$$.json" ] || return 1
    # language=Python
    python3 -c "import pandas as pd;import csv;df=pd.read_json('/tmp/_health_monitor_$$.json');df.to_csv('${_out_file}', mode='w', header=True, index=False, escapechar='\\\', quoting=csv.QUOTE_NONNUMERIC)"
}

#SELECT TIME(substr(date_time, 12, 8)) as hhmmss, AVG(mbs) as avg_MBperSec, count(*) as requests FROM t_log_iostat GROUP BY hhmmss
function f_iostat2csv() {
    local __doc__="Convert some log which contains org.sonatype.nexus.blobstore.iostat to csv (may not include 'deleted')"
    local _glob="${1:-"nexus.log"}"
    local _out_file="${2:-"./log_iostat.csv"}"
    local _rg_opts="-g \"${_glob}\""
    if [ -s "${_glob}" ]; then
        _rg_opts="${_glob}"
    fi
    # NOTE "read" and "written" only, no "deleted" as it's different
    #2024-07-23 14:05:45,646+0000 DEBUG [qtp498394633-47939]  *SYSTEM org.sonatype.nexus.blobstore.iostat - blobstore imc-snapshots: 1410 bytes written in 92.8994 ms (0.0151777 mb/s)
    #2024-07-23 20:30:45,643+0000 DEBUG [qtp498394633-47939]  *SYSTEM org.sonatype.nexus.blobstore.iostat - blobstore imc-snapshots: blob deleted in 51.5723 ms
    rg "^(${_DATE_FORMAT}.\d\d:\d\d:\d\d).([\d]+)[^\[]+\[([^\]]+)\] [^ ]* ([^ ]*) org.sonatype.nexus.blobstore.iostat - blobstore ([^:]+): (\d*) *(\S+) (\S+) in (\S+) (\S+)" -o -r '"$1.$2","$3","$4","$5",$6,"$7","$8",$9,"$10"' --no-filename ${_rg_opts} > "${_out_file}" || return $?
    _add_header "${_out_file}" "date_time,thread,user,blobstore,size,size_unit,type,elapsed,elapsed_unit"
}

function f_get_pems_from_xml() {
    local _file="$1"
    # language=Python
    python3 -c "import sys,xmltodict,json
j = xmltodict.parse(open('${_file}').read())
for c in j['capabilitiesConfiguration']['capabilities']['capability']:
    if c['typeId'] == 'smartproxy.security.trust':
        f_name = c['notes'] + '.pem'
        with open(f_name, 'w') as f:
            f.write(c['properties']['property']['value'])
"
}
# curl -O https://repo1.maven.org/maven2/com/h2database/h2/1.4.196/h2-1.4.196.jar
# curl -o $HOME/IdeaProjects/libs/h2-1.4.200.jar https://repo1.maven.org/maven2/com/h2database/h2/1.4.200/h2-1.4.200.jar
# Jira Data Center: curl -O https://repo1.maven.org/maven2/com/h2database/h2/2.1.214/h2-2.1.214.jar
function f_h2_start() {
    local __doc__="http://www.h2database.com/javadoc/org/h2/tools/Server.html"
    # NXRM3
    #Save Settings: Generic H2 (Embedded)
    #Driver: org.h2.Driver
    #JDBC URL: jdbc:h2:file:nexus
    #username: <LEAVE BLANK>
    #password: <LEAVE BLANK>
    local _baseDir="${1}"
    local _port="${2:-"8082"}"
    local _Xmx="${3:-"8g"}"
    local _h2_jar="${4}"
    local _h2_ver="${5:-"2.2.224"}" # or 1.4.200 for RM3
    if [ -z "${_baseDir}" ]; then
        if [ -d ./sonatype-work/clm-server/data ]; then
            _baseDir="./sonatype-work/clm-server/data/"
            _h2_ver="1.4.196"
        elif [ -d ./sonatype-work/nexus3/db ]; then
            _baseDir="./sonatype-work/nexus3/db"
        else
            _baseDir="."
        fi
    fi
    if [ -z "${_h2_jar}" ]; then
        _h2_jar="$HOME/IdeaProjects/libs/h2-${_h2_ver}.jar"
    fi
    # NOTE: 1.4.200 is used by NXRM# but may causes org.h2.jdbc.JdbcSQLIntegrityConstraintViolationException with IQ    # -ifNotExists
    java -Xmx${_Xmx} -cp ${_h2_jar} org.h2.tools.Server -webPort ${_port} -baseDir "${_baseDir}" -webAllowOthers -tcpAllowOthers -pgAllowOthers
}

# TODO: backup function with:
#java -cp h2-1.4.200.jar org.h2.tools.Script -url jdbc:h2:/<path-to-old-db-file>/<DB-name> -user <username> -password <password> -script backup.zip -options compression zip

#SELECT TABLE_SCHEMA, TABLE_NAME, ROW_COUNT_ESTIMATE FROM INFORMATION_SCHEMA.TABLES WHERE ROW_COUNT_ESTIMATE > 0 ORDER BY ROW_COUNT_ESTIMATE DESC;

#f_h2_shell ./ods.h2.db "SCRIPT TO 'db-dump.sql' TABLE <tablename1>, <tablename2>...
# CALL CSVWRITE('./conan_conan-center-proxy.csv', '')
function f_h2_shell() {
    local _db_file="${1}"
    local _query_file="${2}"
    local _Xmx="${3:-"2g"}"
    local _opts="${4-"${_H2_DB_OPTS:-";DATABASE_TO_UPPER=FALSE;SCHEMA=insight_brain_ods;IFEXISTS=true;MV_STORE=FALSE;"}"}"
    local _h2_ver="1.4.200" # or 1.4.196 for IQ
    _db_file="$(realpath ${_db_file})"
    # DB_CLOSE_ON_EXIT=FALSE may have some bug: https://github.com/h2database/h2database/issues/1259
    # IGNORECASE=TRUE for case insensitive column value
    local _url="jdbc:h2:${_db_file%%.*}${_opts}"
    if [ -s "${_query_file}" ]; then
        java -Xmx${_Xmx} -cp $HOME/IdeaProjects/libs/h2-${_h2_ver}.jar org.h2.tools.RunScript -url "${_url};TRACE_LEVEL_SYSTEM_OUT=2" -user sa -password "" -driver org.h2.Driver -script "${_query_file}"
    elif [ -n "${_query_file}" ]; then  # probably SQL statement
        java -Xmx${_Xmx} -cp $HOME/IdeaProjects/libs/h2-${_h2_ver}.jar org.h2.tools.RunScript -url "${_url};TRACE_LEVEL_SYSTEM_OUT=2" -user sa -password "" -driver org.h2.Driver -script <(echo "${_query_file}")
    else
        java -Xmx${_Xmx} -cp $HOME/IdeaProjects/libs/h2-${_h2_ver}.jar org.h2.tools.Shell -url "${_url};TRACE_LEVEL_SYSTEM_OUT=2" -user sa -password "" -driver org.h2.Driver
    fi
}

function f_csv2h2() {
    local _file="${1:-"./request.csv"}"
    local _saveTo="${2}"
    local _append="${3}"    # default is replace
    if [ ! -s /var/tmp/share/java/h2-console.jar ]; then
        echo "This function requires /var/tmp/share/java/h2-console.jar"
        return 1
    fi
    if [ -z "${_saveTo}" ]; then
        _saveTo="./$(basename "${_file}" ".csv")"
    fi
    local _table="t_$(basename "${_file}" ".csv")"
    local _sql="CREATE TABLE IF NOT EXISTS ${_table} AS SELECT * FROM CSVREAD('${_file}');"
    [[ "${_append}" =~ ^[yY] ]] || _sql="DROP TABLE IF EXISTS ${_table};${_sql}"

    # TODO: add startedTime: DATEADD('SECOND', 0 - ("elapsedTime" / 1000), PARSEDATETIME(DATE, 'dd/MMM/yyyy:hh:mm:ss z')), this display's my timezone time which is a bit confusing
    if [[ "${_table}" =~ request ]]; then
        _sql="${_sql%;};ALTER TABLE ${_table} ALTER COLUMN bytesSent SET DATA TYPE BIGINT;"
        _sql="${_sql%;};ALTER TABLE ${_table} ALTER COLUMN elapsedTime SET DATA TYPE BIGINT;"
    fi
    echo "${_sql}" | java -jar /var/tmp/share/java/h2-console.jar "${_saveTo}" || return $?
    # TODO: start H2 service
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
                _end_line_num=`_gunzip -c "$_file_path" | tail -n +${_tmp_start_line_num} | _grep -m1 -nP "$_end_regex" | cut -d ":" -f 1`
            else
                _end_line_num=`tail -n +${_tmp_start_line_num} "$_file_path" | _grep -m1 -nP "$_end_regex" | cut -d ":" -f 1`
            fi
            _end_line_num=$(( $_end_line_num + $_start_line_num - 1 ))
        fi
        if [ "${_extension}" = 'gz' ]; then
            _gunzip -c "${_file_path}" | _sed -n "${_start_line_num},${_end_line_num}p"
        else
            _sed -n "${_start_line_num},${_end_line_num}p" "${_file_path}"
        fi
    fi
}

# To split hourly: f_splitByRegex nexus.log, and f_splitByRegex request.log '(\d\d/[a-zA-Z]{3}/\d\d\d\d).(\d\d)'
# f_extractFromLog uses this function
function f_splitByRegex() {
    # TODO: this doesn't work with Ubuntu?
    local _file="$1"        # can't be a glob as used in sed later
    local _line_regex="$2"  # Entire line regex. If empty, split by hourly. NOTE: For request.log use '(\d\d/[a-zA-Z]{3}/\d\d\d\d).(\d\d)'
    local _save_to="${3}"
    local _prefix="${4-"*None*"}"   # Can be an empty string
    local _out_ext="${5:-"out"}"
    local _sort="${6:-"${_SPLIT_BY_REGEX_SORT}"}"   # If regex-ing with some numeric value (eg: date/time), sort with -u is faster
    #echo "${FUNCNAME[2]} > ${FUNCNAME[1]} $@" >> /tmp/DEBUG_${FUNCNAME[0]}_$$.tmp
    if [ -z "${_line_regex}" ]; then
        _line_regex="^${_DATE_FORMAT}.\d\d"
        if [[ "${_file}" =~ request.*log ]]; then
            _line_regex="${_DATE_FMT_REQ}:\d\d"
        fi
        [ -z "${_sort}" ] && _sort="Y"
    fi

    #_file="$(echo ${_file} | _sed 's/.\///')"
    local _base_name="$(basename "${_file}")"
    [ "${_prefix}" == "*None*" ] && _prefix="${_base_name%%.*}_"
    [ -z "${_save_to%/}" ] && _save_to="_split_${_prefix%_}"
    [ ! -d "${_save_to%/}" ] && mkdir -p "${_save_to%/}"
    local _save_path_prefix="${_save_to%/}/${_prefix}"
    local _orig_ext="${_base_name##*.}"
    local _tmp_file="/tmp/$(basename "${_file}" ".${_orig_ext}")_$$"
    if [ "${_orig_ext}" == 'gz' ]; then
        _gunzip -c "${_file}" > "${_tmp_file}" || return $?
        _file="${_tmp_file}"
    fi
    # this may not be working
    local _tmp_filename=""
    local _prev_n=1
    local _prev_str=""

    if [[ "${_sort}" =~ ^(y|Y) ]]; then
        # somehow this magically works with request.log date:hour
        rg "${_line_regex}" --search-zip --no-filename -n -o "${_file}" | sed 's/:/\./2' | sort -u -t":" -k2
    else
        rg "${_line_regex}" --search-zip --no-filename -n -o "${_file}"
    fi > /tmp/${FUNCNAME[0]}_${FUNCNAME[1]}_$$.out
    echo "END_OF_FILE:ZZZ" >> /tmp/${FUNCNAME[0]}_${FUNCNAME[1]}_$$.out
    # NOTE: scope of variable in BASH is strange. _prev_str can't be used outside of while loop.
    cat /tmp/${FUNCNAME[0]}_${FUNCNAME[1]}_$$.out | while read -r _t; do
        if [[ "${_t}" =~ ^([0-9]+):(.+) ]]; then
            # Skip if this number is already processed
            if [ ${_prev_n} == ${BASH_REMATCH[1]} ]; then
                _prev_str="${BASH_REMATCH[2]}"  # Used for the file name and detecting a new value
                continue
            fi
            # At this moment, Skip if the previous key is same as current key. Expecting key is unique...
            [ -n "${_prev_str}" ] && [ "${_prev_str}" == "${BASH_REMATCH[2]}" ] && continue
            # Found new value (next date, next thread etc.)
            _tmp_filename="$(_gen_filename "${_prev_str}")"
            # TODO: this might cause some performance issue
            sed -n "${_prev_n},$((${BASH_REMATCH[1]} - 1))p;$((${BASH_REMATCH[1]} - 1))q" ${_file} > ${_save_path_prefix}${_tmp_filename}.${_out_ext} || return $?
            _prev_str="${BASH_REMATCH[2]}"  # Used for the file name and detecting a new value
            _prev_n=${BASH_REMATCH[1]}
        elif [ "${_t}" == "END_OF_FILE:ZZZ" ] && [ -n "${_prev_str}" ]; then
            _tmp_filename="$(_gen_filename "${_prev_str}")"
            sed -n "${_prev_n},\$p" ${_file} > ${_save_path_prefix}${_tmp_filename}.${_out_ext} || return $?
        fi
    done
    if [ -n "${_tmp_file}" ] && [ -f "${_tmp_file}" ]; then
        rm -f ${_tmp_file}
    fi
}
function _gen_filename() {
    local _str="$1"
    # TODO: not good location to handle this but Java 17 thread includes cpu and elapsed
    echo "${_str}" | sed -E "s/ cpu=[^ ]+ elapsed=[^ ]+//" | sed "s/[ =]/_/g" | tr -cd '[:alnum:]._-\n' | cut -c1-192
}
function f_splitPerHour() {
    local _file="$1"
    local _dest_dir="${2:-"_hourly_logs"}"
    _SPLIT_BY_REGEX_SORT="Y" f_splitByRegex "${_file}" "^${_DATE_FORMAT}.\d\d" "${_dest_dir}"
}
function f_splitPerHourReq() {
    local _file="$1"
    local _dest_dir="${2:-"_hourly_logs_req"}"
    # Can't use _SPLIT_BY_REGEX_SORT="Y" when regex contains un-sortable values such as "dd/MMM/yyyy"
    _SPLIT_BY_REGEX_SORT="Y" f_splitByRegex "${_file}" "${_DATE_FMT_REQ}:\d\d" "${_dest_dir}"
}
#f_extractFromLog ./nexus-2024-07-08.log.gz "^2024-07-08 19:45:[23]" "^2024-07-08 19:46:4" | tee nexus-2024-07-08_1945to1946.out
#f_extractFromLog ./clm-server.log '^2025-01-15 01:4' '^2025-01-15 02:' > filtered_logs2.log
function f_extractFromLog() {
    local __doc__="Extract specific lines from file"
    local _file="$1"        # Need to be a path (not glob) as used in sed later
    local _regex_from="$2"  # This regex must match with at least one line
    local _regex_to="$3"    # This regex must match with at least one line

    local _n1="$(rg "${_regex_from}" --no-filename -m1 -n -o "${_file}" | cut -d':' -f1)"
    [ -z "${_n1}" ] && return 11
    local _n2="\$"
    if [ -n "${_regex_to}" ]; then
        _n2="$(rg "${_regex_to}" --no-filename -m1 -n -o "${_file}" | cut -d':' -f1)"
        [ -z "${_n2}" ] && return 12
    fi
    if [ "${_file##*.}" = 'gz' ]; then
        _gunzip -c "${_file}"
    else
        cat "${_file}"
    fi | _sed -n "${_n1},${_n2}p;"
}
function f_extractByHours() {
    local _file="$1"
    local _start_hour="${2}"
    local _end_hour="${3}"
    local _date_format="${_DATE_FORMAT}"
    [ -z "${_end_hour}" ] && _end_hour="$(( ${_start_hour} + 1 ))"
    local _tmp_filename="$(basename "${_file}")"
    [[ "${_tmp_filename}" =~ request ]] && _date_format="${_DATE_FMT_REQ}"
    f_extractFromLog "${_file}" "${_date_format}[: T.]${_start_hour}" "${_date_format}[: T.]${_end_hour}" > "${_tmp_filename%%.*}_extracted_${_start_hour}_${_end_hour}.out"
}
function f_logDuration() {
    local _log_file="$1"
    local _start_group="$2"
    local _end_group="$3"   # optional
    local _datetime_group="$4"  # ^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d.\d\d\d)'
    if [ -z "${_start_group}" ]; then
        echo "No _start_regex"; return 1
    fi
    if [ -z "${_datetime_group}" ]; then
        _datetime_regex="^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d.\d\d\d).+"
    fi
    local _tmp_chars="$(echo "${_datetime_regex}${_start_group}" | tr -d -c '(')"
    local _num="${#_tmp_chars}"
    local _pattern_out="\"\$1\""
    for _i in `seq 2 ${_num}`; do
        _pattern_out="${_pattern_out},\"\$${_i}\""
    done
    rg "${_datetime_regex}${_start_group}" -o -r "${_pattern_out}" ${_log_file} > /tmp/f_logDuration_start.out
    if [ -n "${_end_group}" ]; then
        rg "${_datetime_regex}${_end_group}" -o -r "${_pattern_out}" ${_log_file} > /tmp/f_logDuration_end.out
        cat /tmp/f_logDuration_start.out /tmp/f_logDuration_end.out | sort -n > /tmp/f_logDuration_combined.out
        cat /tmp/f_logDuration_combined.out > /tmp/f_logDuration_start.out
    fi
}

function _date2int() {
    local _date_str="$1"
    _date -u -d "$(__extractdate "${_date_str}")" +"%s"
}

function _date2iso() {
    local _date_str="$1"
    # --rfc-3339=seconds outputs timezone
    _date -d "$(__extractdate "${_date_str}")" +'%Y-%m-%d %H:%M:%S'
}

function __extractdate() {
    local _date_str="$1"
    # if YYYY-MM-DD.hh:mm:ss
    if [[ "${_date_str}" =~ ([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]).([0-9][0-9]:[0-9][0-9]:[0-9][0-9]) ]]; then
        _date_str="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    # if DD/Mon/YYYY.hh:mm:ss
    elif [[ "${_date_str}" =~ ([0-9][0-9])\/([a-zA-Z][a-zA-Z][a-zA-Z])\/([0-9][0-9][0-9][0-9]).([0-9][0-9]:[0-9][0-9]:[0-9][0-9]) ]]; then
        _date_str="${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]}"
    # if YY/MM/DD.hh:mm:ss
    elif [[ "${_date_str}" =~ ([0-9][0-9]\/[0-9][0-9]\/[0-9][0-9]).([0-9][0-9]:[0-9][0-9]:[0-9][0-9]) ]]; then
        _date_str="20${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    fi
    echo "${_date_str}"
}

function _find() {
    local _name="$1"
    local _find_all="$2"
    local _max_depth="${3:-"5"}"
    local _result=1
    # Accept not only file name but also /<dir>/<filename> so that using grep
    for _f in `find . -maxdepth ${_max_depth} -type f -print | grep -w "${_name}$"`; do
        echo "${_f}" && _result=0
        [[ "${_find_all}" =~ ^(y|Y) ]] || break
    done
    return ${_result}
}

function _find_and_cat() {
    local _name="$1"
    local _find_all="$2"
    local _max_depth="${3:-"5"}"
    local _result=1
    if [ -z "${_find_all}" ] && [ -s "${_name}" ]; then
        cat "${_name}"
        return 0
    fi
    # Accept not only file name but also /<dir>/<filename> so that using grep
    for _f in $(find . -maxdepth ${_max_depth} -type f -print | grep -w "${_name}$"); do
        cat "${_f}" && _result=0
        [[ "${_find_all}" =~ ^(y|Y) ]] || break
        echo ''
    done
    return ${_result}
}

function _replace_number() {
    local _min="${1:-5}"
    local _N_="_NUM_"
    [ 5 -gt ${_min} ] && _N_="*"
    _sed -r -e "s/[0-9a-fA-F]{20,}/___SHA*___/g" \
     -e "s/\b[0-9a-fA-F]{32}\b/___UUID___/g" \
     -e "s/\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4,8}-[0-9a-fA-F]{4,8}-[0-9a-fA-F]{4,8}-[0-9a-fA-F]{8,12}\b/___U-U-I-D___/g" \
     -e "s/\b[0-9\.]+ ?ms\b/_MSEC_/g" \
     -e "s/\b[0-9\.]+ ?s\b/_SEC_/g" \
     -e "s/\b0x[0-9a-f]{2,}\b/0x_HEX_/g" \
     -e "s/\b[0-9a-f]{6,8}\b/__HEX__/g" \
     -e "s/20[0-9][0-9][-/][0-9][0-9][-/][0-9][0-9][ T]/___DATE___./g" \
     -e "s/[0-2]?[0-9]:[0-6][0-9]:[0-6][0-9][.,0-9]*/__TIME__/g" \
     -e "s/([+-])[0-1][0-9][03]0\b/\1_TZ_/g" \
     -e "s/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/__IP_ADDRESS__/g" \
     -e "s/[0-9]{8,10}-[0-9]+\b/__THREAD_ID__/g" \
     -e "s/\b(CVE|sonatype|SONATYPE)-[0-9]{4}-[0-9]{3,}\b/__CVE__/g" \
     -e "s/:[0-9]{2,5}/:_PORT_/g" \
     -e "s/#[0-9]{${_min},}+/#_N_/g" \
     -e "s/-[0-9]{${_min},}+\] /-_N_] /g" \
     -e "s/-[0-9]{${_min},}+\//-_N_\//g" \
     -e "s/[0-9]{${_min},}+\b/${_N_}/g"
}

# DEPRECATED: utils.sh now has this so this function should be removed.
function _load_yaml() {
    local _yaml_file="${1}"
    local _name_space="${2}"
    # TODO: probably this can be done only with awk
    #awk -F "=" '{out=$2;gsub(/[^0-9a-zA-Z_]/,"_",$1);for(i=3;i<=NF;i++){out=out"="$i};print $1"=\""$out"\""}' ${_yaml_file} > /tmp/_load_yaml.out || return $?
    _sed -n -r 's/^[[:space:]]*([^=:]+)[[:space:]]*[=:][[:space:]]+(.+)/'${_name_space}'\1\t"\2"/p' ${_yaml_file} | awk -F "\t" '{gsub(/[^0-9a-zA-Z_]/,"_",$1); print $1"="$2}' > /tmp/_load_yaml.out || return $?
    source /tmp/_load_yaml.out
}

function _search_properties() {
    local _path="${1-./}"
    local _props="$2" # space separated regex
    local _is_name_value_xml="$3"

    for _p in ${_props}; do
        if [[ "${_is_name_value_xml}" =~ (^y|^Y) ]]; then
            local _out="`_grep -Pzo "(?s)<name>${_p}</name>.+?</value>" ${_path}`"
            [[ "${_out}" =~ (\<value\>)(.*)(\</value\>) ]]
            echo "${_p}=${BASH_REMATCH[2]}"
        else
            # Expecting hive 'set' command output or similar style (prop=value)
            _grep -P "${_p}" "${_path}"
        fi
    done
}

function _json_dump() {
    # escaping "," for _get_json is hard so another function
    local _dict_keys="$1"   # eg: ['com.sonatype.nexus.hazelcast.internal.cluster:name=nexus,type=ClusterDetails']['ClusterDetail']
    local _indent="${2}"
    if [ -n "${_indent}" ]; then
        python3 -c "import sys,json;a=json.loads(sys.stdin.read());print(json.dumps(a${_dict_keys},indent=2,sort_keys=True))"
    else
        python3 -c "import sys,json;a=json.loads(sys.stdin.read());print(a${_dict_keys})"
    fi
}

function _get_json() {
    local _props="$1"           # search hierarchy list string. eg: "xxxx,yyyy,key[:=]value" (*NO* space)
    local _key="${2}"           # a key attribute in props. eg: '@class' (OrientDB), 'key' (jmx.json)
    local _attrs="${3}"         # attribute1,attribute2,attr3.*subattr3* (using dot) to return only those attributes' value
    local _find_all="${4}"      # If Y, not stopping after finding one
    local _no_pprint="${5}"     # no prettified output
    local _get_json_py="${_GET_JSON_PY}"
    if [ -z "${_get_json_py}" ]; then
        if which get_json.py &>/dev/null; then
            _get_json_py="$(which get_json.py)"
        elif [ -s "$HOME/IdeaProjects/samples/python/get_json.py" ]; then
            _get_json_py="$HOME/IdeaProjects/samples/python/get_json.py"
        elif [ ! -s "/tmp/get_json.py" ]; then
            if ! curl -sf -o /tmp/get_json.py -L "https://github.com/hajimeo/samples/blob/master/python/get_json.py"; then
                _LOG "ERROR" "No get_json.py"
                return 1
            fi
        fi
        [ -z "${_get_json_py}" ] && _get_json_py="/tmp/get_json.py"
    fi
    python3 "${_get_json_py}" "${_props}" "${_key}" "${_attrs}" "${_find_all}" "${_no_pprint}"
}

# _get_json warpper to convert some numeric values to human friendly formats
function _search_json() {
    local _file="$1"
    local _search="$2"
    local _h="$3" # Human readable
    local _no_pprint="$4"
    # NOTE: jmx.json can be TRUNCATED
    local _result="$(_find_and_cat "${_file}" 2>/dev/null | _get_json "${_search}" "" "" "" "${_no_pprint}" 2>/dev/null)"
    [ -z "${_result}" ] && return 1
    if [[ "${_search}" =~ \[.+,.(.+).\] ]]; then
        _search="${BASH_REMATCH[1]}"
    elif [[ "${_search}" =~ \[.(.+).\] ]]; then
        _search="${BASH_REMATCH[1]}"
    fi
    # If human friendly output is on and the value/result is an integer
    if [[ "${_h}" =~ ^(y|Y) ]] && [[ "${_result}" =~ [1-9]+ ]]; then
        _result="$(_human_friendly "${_result}")"
    fi
    echo "{\"${_search}\": ${_result}}"
}

function _search_size_in_bytes() {
    local _search_prefix="$1"   # ^["]?shared_buffers\b
    local _search_target="$2"   # -g dbFileInfo.txt
    local _result="$(rg --no-filename -i "${_search_prefix}[^0-9]*([0-9]+)\s*TB\b" -o -r '$1' ${_search_target})"
    if [ -n "${_result}" ]; then
        echo "$(bc <<<"${_result} * 1099511627776")"
        return
    fi
    _result="$(rg --no-filename -i "${_search_prefix}[^0-9]*([0-9]+)\s*GB\b" -o -r '$1' ${_search_target})"
    if [ -n "${_result}" ]; then
        echo "$(bc <<<"${_result} * 1073741824")"
        return
    fi
    _result="$(rg --no-filename -i "${_search_prefix}[^0-9]*([0-9]+)\s*MB\b" -o -r '$1' ${_search_target})"
    if [ -n "${_result}" ]; then
        echo "$(bc <<<"${_result} * 1048576")"
        return
    fi
    _result="$(rg --no-filename -i "${_search_prefix}[^0-9]*([0-9]+)\s*KB\b" -o -r '$1' ${_search_target})"
    if [ -n "${_result}" ]; then
        echo "$(bc <<<"${_result} * 1024")"
        return
    fi
    # Not perfect but assuming as bytes
    _result="$(rg --no-filename -i "${_search_prefix}[^0-9]*([0-9]+)\s*B?\b" -o -r '$1' ${_search_target})"
    if [ -n "${_result}" ]; then
        echo "$(bc <<<"${_result} * 1024")"
        return
    fi
}

function _human_friendly() {
    local _result="$1"
    local _scale="${2:-"2"}"
    if [[ "${_result}" -gt 1099511627776 ]]; then
        _result="$(bc <<<"scale=${_scale};${_result} / 1099511627776") TB"
    elif [[ "${_result}" -gt 1073741824 ]]; then
        _result="$(bc <<<"scale=${_scale};${_result} / 1073741824") GB"
    elif [[ "${_result}" -gt 1048576 ]]; then
        _result="$(bc <<<"scale=${_scale};${_result} / 1048576") MB"
    elif [[ "${_result}" -gt 1024 ]]; then
        _result="$(bc <<<"scale=${_scale};${_result} / 1024") KB"
    fi
    echo "${_result}"
}

function _human_friendly_todo() {
    # TODO: Too slow
    local _num=$1
    # NOTE: requires jn_utils.py in PYTHON_PATH (for python3)
    # language=Python
    echo "${_num}" | python3 -c "import sys, json
import jn_utils as ju
print(ju._human_readable_num(sys.stdin.read()))
"
}

function _py3i_pipe() {
    local _pipe=${1}
    [ -z "${_pipe}" ] && _pipe="$(mktemp -u)"
    mkfifo ${_pipe}
    echo "# Starting python3 interactive with ${_pipe} ..." >&2
    tail -n1 -f ${_pipe} | python3 -i
    rm -v -f ${_pipe}
}

function _actual_file_size() {
    local _log_path="$1"
    [ ! -f "${_log_path}" ] && return
    if [[ "${_log_path}" != *.gz ]] && [[ "${_log_path}" != *.zip ]]; then
        wc -c "${_log_path}" | awk '{print $1}'
        return
    fi
    local _file_cmd_out="$(file "${_log_path}")"
    if ! echo "${_file_cmd_out}" | grep -qi "compress"; then
        wc -c "${_log_path}" | awk '{print $1}'
    else
        # file ... original size modulo 2^32 2348225
        echo "${_file_cmd_out}" | rg " (\d+)$" -o -r '$1'
    fi
}

function _wait_jobs() {
    local _until_how_many="${1:-2}" # Running two is OK
    local _timeout_sec="${2:-180}"
    local _sp="0.2"
    local _loop_num="$(echo "${_timeout_sec}/${_sp}" | bc)"
    for _i in $(seq 0 ${_loop_num}); do
        local _num="$(jobs -l | grep -iw "Running" | wc -l | tr -d '[:space:]')"
        if [ -z "${_num}" ] || [ ${_num} -le ${_until_how_many} ]; then
            return 0
        fi
        #echo "${_num} background jobs are still running" >&2
        sleep ${_sp}
    done
}
#ls -1 _split_logs/* | _line_num
function _line_num() {
    local _file="$1"
    local _opt="${2:-"-l"}"
    local _cmd="wc ${_opt}"
    if [[ "${_file}" =~ \.gz$ ]]; then
        _cmd="_gunzip -c ${_file} | ${_cmd}"
    elif [ -n "${_file}" ]; then
        _cmd="cat ${_file} | ${_cmd}"
    fi
    eval "${_cmd}" | tr -d "[:space:]"
}
function _add_header() {
    local _file="$1"
    local _header="$2"
    if [ -s "${_file}" ]; then
        head -n1 "${_file}" | rg -q "${_header}" || _sed -i'' "1i ${_header}" "${_file}"
    fi
}
function _sed() {
    local _cmd="sed"; which gsed &>/dev/null && _cmd="gsed"
    ${_cmd} "$@"
}
function _csplit() {
    # NOTE: Mac (or BSD) has split -p for pattern, but not gsplit
    local _cmd="csplit"; which gcsplit &>/dev/null && _cmd="gcsplit"
    ${_cmd} "$@"
}
function _grep() {
    local _cmd="grep"; which ggrep &>/dev/null && _cmd="ggrep"
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
function _uniq() {
    local _cmd="uniq"; which guniq &>/dev/null && _cmd="guniq"
    ${_cmd} "$@"
}
function _gunzip() {
    if type unpigz &>/dev/null; then
        unpigz "$@"
    else
        gunzip "$@"
    fi
}

function _LOG() {
    if [ "$1" != "DEBUG" ] || [ -n "${_DEBUG}" ]; then
        if [ -n "${_LOG_FILE_PATH}" ]; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a ${_LOG_FILE_PATH}
        else
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
        fi
    fi >&2
}


### Help ###############################################################################################################

_help() {
    local _function_name="$1"
    local _show_code="$2"
    local _doc_only="$3"

    if [ -z "$_function_name" ]; then
        # The workd "help" is already taken in bash
        echo "_help <function name> [Y]"
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
            echo "(\"_help $_function_name y\" to show code)"
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
            _tmp_txt="`_help "$_f" "" "Y"`"
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
_SCRIPT_DIR="$(dirname "$BASH_SOURCE")"

[ -z "${_DATE_FORMAT}" ] && _DATE_FORMAT="\d\d\d\d-\d\d-\d\d"
[ -z "${_DATE_FMT}" ] && _DATE_FMT="${_DATE_FORMAT}"
[ -z "${_DATE_FMT_REQ}" ] && _DATE_FMT_REQ="\d\d.[a-zA-Z]{3}.\d\d\d\d"
[ -z "${_DT_FMT}" ] && _DT_FMT="${_DATE_FORMAT}.\d\d:\d\d:\d\d.\d+"
[ -z "${_DT_FMT_REQ}" ] && _DT_FMT_REQ="${_DATE_FMT_REQ}.\d\d:\d\d:\d\d"


### Main ###############################################################################################################
[ -z "${BASH}" ] && echo "WARN: The functions in this script work with only 'bash'."
if [ "$0" = "$BASH_SOURCE" ]; then
    usage | less
fi