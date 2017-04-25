#!/usr/bin/env bash
#
# Bunch of grep functions to search log files
# Don't use complex one, so that each function can be easily copied and pasted
#
# HOW-TO:
#     source ./log_search.sh
#     help
#
# TODO: tested on Mac only (eg: sed -E, ggrep)
# which ggrep || alias ggrep=grep
#

usage() {
    echo "HELP/USAGE:"
    echo "This script contains useful functions to search log files.

How to use (just source)
    . ${BASH_SOURCE}

Example:
    # Check what kind of caused by is most
    f_topCausedByExceptions ./yarn_application.log | tail -n 10

    # Check what kind of ERROR is most
    f_topErrors ./yarn_application.log | tail -n 10
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
    local __doc__="List top ERRORs"
    local _path="$1"
    local _is_including_warn="$2"
    local _not_hiding_number="$3"
    local _regex="$4"

    if [ -z "$_regex" ]; then
        _regex="(ERROR|SEVERE|FATAL|java\..+?Exception).+"

        if [[ "$_is_including_warn" =~ (^y|^Y) ]]; then
            _regex="(ERROR|SEVERE|FATAL|java\..+?Exception|WARN|WARNING).+"
        fi
    fi

    if [[ "$_not_hiding_number" =~ (^y|^Y) ]]; then
        egrep -wo "$_regex" "$_path" | sort | uniq -c | sort -n
    else
        egrep -wo "$_regex" "$_path" | sed -E "s/0x[0-9a-f][0-9a-f][0-9a-f]+/0x__________/g" | sed -E "s/[0-9][0-9]+/____/g" | sort | uniq -c | sort -n
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
        ggrep "^Container: container_" "$_path" | sort -k4
    else
        ggrep "^Container: container_" "$_path" | sort
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
    local __doc__="List the Job counters (Tez only?) (from YARN app log)"
    local _path="$1"
    local _line=""
    local _list=""
    local _final_containers=""

    egrep -o "Final Counters for .+$" "$_path" | while read -r _line ; do
        echo $_line | egrep -o "Final Counters for .+?:"
        _list="`echo $_line | egrep -o "\[.+$"`"

        echo $_list | python -c "import sys,pprint;pprint.pprint(sys.stdin.read());"
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

    ( find "${_dir_path%/}" -name "*.syslog" | xargs -I {} bash -c "grep -oHE '^20\d\d-\d\d-\d\d \d\d:\d\d:\d\d' -m 1 {}" | awk -F ':' '{print $2":"$3":"$4" "$1}' ) | sort -n | head -n $_num
}

function f_appLogFindLastSyslog() {
    local __doc__="After yarn_app_logs_splitter, find which one was ended in the last. gtac is required"
    local _dir_path="${1-.}"
    local _num="${2-10}"
    local _regex="${3}"

    if [ -n "$_regex" ]; then
        ( for _f in `grep -l "$_regex" ${_dir_path%/}/*.syslog`; do _dt="`gtac $_f | grep -oE '^20\d\d-\d\d-\d\d \d\d:\d\d:\d\d' -m 1`" && echo "$_dt $_f"; done ) | sort -nr | head -n $_num
    else
        ( for _f in `find "${_dir_path%/}" -name "*.syslog"`; do _dt="`gtac $_f | grep -oE '^20\d\d-\d\d-\d\d \d\d:\d\d:\d\d' -m 1`" && echo "$_dt $_f"; done ) | sort -nr | head -n $_num
    fi
}

function f_hdfsAuditLogCountPerTime() {
    local __doc__="Count a log file (eg.: HDFS audit) per 10 minutes"
    local _path="$1"
    local _datetime_regex="$2"

    if [ -z "$_datetime_regex" ]; then
        _datetime_regex="^\d\d\d\d-\d\d-\d\d \d\d:\d"
    fi

    if ! which bar_chart.py &>/dev/null; then
        echo "## bar_chart.py is missing..."
        local _cmd="uniq -c"
    else
        local _cmd="bar_chart.py"
    fi

    grep -oE "$_datetime_regex" $_path | $_cmd
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
        grep -E "$_datetime_regex" $_path > /tmp/f_hdfs_audit_count_per_user_$$.tmp
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

function f_findJarByClassName() {
    local __doc__="Find jar by class name (add .class in the name)"
    local _search_path="${1-/usr/hdp/current/}"
    local _class_name="$2"

    find -L "$_search_path" -type f -name '*.jar' -print0 | xargs -0 -n1 -I {} bash -c "less {} | grep -m 1 -w $_class_name && echo {}"
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
    local _date="date"

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
        _date="date -u"
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
    python "$_script_path" --container-log-dir $_out_name --app-log $_app_log
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

    local _commits_only="`echo "$_grep_result" | grep ^commit | cut -d ' ' -f 2`"

    echo "# Searching branches ...."
    for c in $_commits_only; do git branch -r --contains $c; done | sort
    echo "# Searching tags ...."
    for c in $_commits_only; do git tag --contains $c; done | sort
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

    ls $_file_path 2>/dev/null | while read l; do
        local _start_line_num=`ggrep -m1 -nP "$_start_regex" "$l" | cut -d ":" -f 1`
        if [ -n "$_start_line_num" ]; then
            local _end_line_num=""
            if [ -n "$_end_regex" ]; then
                _end_line_num=`ggrep -m1 -nP "$_end_regex" "$l" | cut -d ":" -f 1`
            fi
            if [ -n "$_end_line_num" ]; then
                sed -n "${_start_line_num},${_end_line_num}p" "${l}"
            else
                sed -n "${_start_line_num},\$p" "${l}"
            fi
        fi
    done
    return $?
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
            #eval "echo \"--[ $_f ]\" | sed -e :a -e 's/^.\{1,${_width}\}$/&-/;ta'"
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

### Main ###############################################################################################################

if [ "$0" = "$BASH_SOURCE" ]; then
    if [ -z "$1" ]; then
        usage
        exit
    fi

    if [ ! -s "$1" ]; then
        echo "$1 is not a right file."
        usage
        exit
    fi

    if [ -s "$1" ]; then
        echo "# Running f_topErrors $1 ..." >&2
        _f_topErrors_out="`f_topErrors "$1"`" &
        echo "# Running f_topCausedByExceptions $1 ..." >&2
        _f_topCausedByExceptions="`f_topCausedByExceptions "$1"`" &

        wait

        echo "$_f_topErrors_out"
        echo "$_f_topCausedByExceptions"
    fi
fi