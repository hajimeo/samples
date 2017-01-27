#!/bin/env bash
#
# Collection of functions to triage HDP related issues
# Tested on CentOS 6.6
# @author Hajime
#

# GLOBAL variables
_WORK_DIR="./hwx_triage"
_PID=""
_LOG_DIR=""
_LOG_DAY="1"
_FUNCTION_NAME=""
_VERBOSE=""
set -o posix


# Public functions
usage() {
    echo "This script is for collecting OS command outputs, and if PID is provided, collecting PID related information.

Example 1: Collect Kafka PID related information
    $BASH_SOURCE -p \"\`cat /var/run/kafka/kafka.pid\`\"

Example 2: Collect Kafka PID related information with Kafka log (for past 1 day)
    $BASH_SOURCE -p \"\`cat /var/run/kafka/kafka.pid\`\" -l \"/var/log/kafka\" [-d 1]

Available options:
    -p PID     This PID will be checked
    -l PATH    A log directory path
    -d NUM     If -l is given, collect past x days of logs (default 1 day)
    -v         Verbose mode
    -h         Show this message

Available functions:
"
_list
echo "
Get more help for a function
    $BASH_SOURCE -f <functionname>
"
}

function f_check_system() {
    local __doc__="Execute OS commands for performance issue"
    _workdir || return 1

    _log "INFO" "Collecting OS related information..."

    [ -n "$_VERBOSE" ] && set -x
    vmstat 1 3 &> ${_WORK_DIR%/}/vmstat.out &
    pidstat -dl 3 3 &> ${_WORK_DIR%/}/pstat.out &
    sysctl -a &> ${_WORK_DIR%/}/sysctl.out
    top -b -n 1 -c &> ${_WORK_DIR%/}/top.out
    ps auxwwwf &> ${_WORK_DIR%/}/ps.out
    netstat -aopen &> ${_WORK_DIR%/}/netstat.out
    netstat -i &> ${_WORK_DIR%/}/netstat_i.out
    netstat -s &> ${_WORK_DIR%/}/netstat_s.out
    ifconfig &> ${_WORK_DIR%/}/ifconfig.out
    nscd -g &> ${_WORK_DIR%/}/nscd.out
    wait
    [ -n "$_VERBOSE" ] && set +x
}

function f_check_process() {
    local __doc__="Execute PID related commands (jstack, jstat, jmap)"
    local _p="$1"	# Java PID ex: `cat /var/run/kafka/kafka.pid`

    _workdir || return 1

    if [ -z "$_p" ]; then
        _log "ERROR" "No PID"; return 1
    fi

    local _user="`stat -c '%U' /proc/${_p}`"
    local _cmd_dir="$(dirname `readlink /proc/${_p}/exe`)" 2>/dev/null

    _log "INFO" "Collecting PID related information..."

    [ -n "$_VERBOSE" ] && set -x
    cat /proc/${_p}/limits &> ${_WORK_DIR%/}/proc_limits_${_p}.out
    cat /proc/${_p}/status &> ${_WORK_DIR%/}/proc_status_${_p}.out
    date > ${_WORK_DIR%/}/proc_io_${_p}.out; cat /proc/${_p}/io >> ${_WORK_DIR%/}/proc_io_${_p}.out
    cat /proc/${_p}/environ | tr '\0' '\n' > ${_WORK_DIR%/}/proc_environ_${_p}.out
    lsof -nPp ${_p} &> ${_WORK_DIR%/}/lsof_${_p}.out

    if [ -d "$_cmd_dir" ]; then
        # NO heap dump at this moment
        [ -x ${_cmd_dir}/jmap ] && sudo -u ${_user} ${_cmd_dir}/jmap -histo ${_p} &> ${_WORK_DIR%/}/jmap_histo_${_p}.out
        [ -x ${_cmd_dir}/jstack ] && for i in {1..3};do sudo -u ${_user} ${_cmd_dir}/jstack -l ${_p}; sleep 3; done &> ${_WORK_DIR%/}/jstack_${_p}.out &
        [ -x ${_cmd_dir}/jstat ] && sudo -u ${_user} ${_cmd_dir}/jstat -gccause ${_p} 1000 9 &> ${_WORK_DIR%/}/jstat_${_p}.out &
    fi

    ps -eLo user,pid,lwp,nlwp,ruser,pcpu,stime,etime,args | grep -w "${_p}" &> ${_WORK_DIR%/}/pseLo_${_p}.out
    pmap -x ${_p} &> ${_WORK_DIR%/}/pmap_${_p}.out
    wait
    date >> ${_WORK_DIR%/}/proc_io_${_p}.out; cat /proc/${_p}/io >> ${_WORK_DIR%/}/proc_io_${_p}.out
    [ -n "$_VERBOSE" ] && set +x
}

function f_collect_config() {
    local __doc__="Collect HDP all config files and generate tgz file"
    _workdir || return 1

    _log "INFO" "Collecting HDP config files ..."

    [ -n "$_VERBOSE" ] && set -x
    if [ -n "$_VERBOSE" ]; then
        tar czvhf ${_WORK_DIR%/}/hdp_all_conf_$(hostname)_$(date +"%Y%m%d%H%M%S").tgz /usr/hdp/current/*/conf/* 2>&1 | grep -v 'Removing leading'
    else
        tar czhf ${_WORK_DIR%/}/hdp_all_conf_$(hostname)_$(date +"%Y%m%d%H%M%S").tgz /usr/hdp/current/*/conf/* 2>&1 | grep -v 'Removing leading'
    fi
    [ -n "$_VERBOSE" ] && set +x
}

function f_collect_log_files() {
    local __doc__="Collect log files for past x days (default is 1 day) and generate tgz file"
    local _path="$1"
    local _day="${2-1}"

    _workdir || return 1

    if [ -z "$_path" ] || [ ! -d "$_path" ]; then
        _log "ERROR" "$_path is not a directory"; return 1
    fi

    _log "INFO" "Collecting log files under ${_path} for past ${_day} day(s) ..."

    [ -n "$_VERBOSE" ] && set -x
    if [ -n "$_VERBOSE" ]; then
        tar czvhf ${_WORK_DIR%/}/hdp_log_$(hostname).tar.gz `find -L "${_path}" -type f -mtime -${_day}` 2>&1 | grep -v 'Removing leading'
    else
        tar czhf ${_WORK_DIR%/}/hdp_log_$(hostname).tar.gz `find -L "${_path}" -type f -mtime -${_day}` 2>&1 | grep -v 'Removing leading'
    fi
    [ -n "$_VERBOSE" ] && set +x
}

function f_tar_work_dir() {
    local __doc__="Create tgz file from work dir and remove work dir"
    local _file_path="$1"

    if [ -z "$_file_path" ]; then
        _file_path="./hdp_triage_$(hostname)_$(date +"%Y%m%d%H%M%S").tgz"
    fi

    _log "INFO" "Creating ${_file_path} file ..."

    [ -n "$_VERBOSE" ] && set -x
    if [ -n "$_VERBOSE" ]; then
        tar --remove-files -czvf ${_file_path} ${_WORK_DIR%/}/* 2>&1 | grep -v 'Removing leading'
    else
        tar --remove-files -czf ${_file_path} ${_WORK_DIR%/}/* 2>&1 | grep -v 'Removing leading'
    fi
    [ -n "$_VERBOSE" ] && set +x
}



help() {
    local _function_name="$1"
    local _doc_only="$2"

    if [ -z "$_function_name" ]; then
        usage; return
    fi

    if [[ "$_function_name" =~ ^[fp]_ ]]; then
        local _code="$(type $_function_name 2>/dev/null | grep -v "^${_function_name} is a function")"
        if [ -z "$_code" ]; then
            _log "ERROR" "Function name '$_function_name' does not exist."; return 1
        fi

        local _eval="$(echo -e "${_code}" | awk '/__doc__=/,/;/')"
        eval "$_eval"

        if [ -z "$__doc__" ]; then
            _log "INFO" "No help information in function name '$_function_name'."
        else
            echo -e "$__doc__"
            [[ "$_doc_only" =~ (^y|^Y) ]] && return
        fi

        local _params="$(type $_function_name 2>/dev/null | grep -iP '^\s*local _[^_].*?=.*?\$\{?[1-9]' | grep -v awk)"
        if [ -n "$_params" ]; then
            echo "Parameters:"
            echo -e "$_params
            "
        fi
        echo -e "${_code}"
    else
        _log "ERROR" "Unsupported Function name '$_function_name'."; return 1
    fi
}

# (supposed to be) private functions

function _log() {
    # At this moment, outputting to STDERR
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" >&2
}

function _workdir() {
    local _work_dir="${1-$_WORK_DIR}"

    [ -z "${_work_dir}" ] && _work_dir="/tmp/${FUNCNAME}_$$"

    if [ ! -d "$_work_dir" ] && ! mkdir $_work_dir; then
        _log "ERROR" "Couldn't create $_work_dir directory"; return 1
    fi

    if [ ! -w "$_work_dir" ]; then
        _log "ERROR" "Couldn't write $_work_dir directory"; return 1
    fi

    _WORK_DIR="${_work_dir}"
}

function _list() {
    local _name="$1"
    #local _width=$(( $(tput cols) - 2 ))
    local _tmp_txt=""

    if [[ -z "$_name" ]]; then
        (for _f in `typeset -F | grep -E '^declare -f [fp]_' | cut -d' ' -f3`; do
            #eval "echo \"--[ $_f ]\" | sed -e :a -e 's/^.\{1,${_width}\}$/&-/;ta'"
            _tmp_txt="`help "$_f" "Y"`"
            printf "%-28s%s\n" "$_f" "$_tmp_txt"
        done)
    elif [[ "$_name" =~ ^func ]]; then
        typeset -F | grep '^declare -f [fp]_' | cut -d' ' -f3
    elif [[ "$_name" =~ ^glob ]]; then
        set | grep ^[g]_
    elif [[ "$_name" =~ ^resp ]]; then
        set | grep ^[r]_
    fi
}


# Main
if [ "$0" = "$BASH_SOURCE" ]; then
    # parsing command options
    while getopts "p:l:d:f:vh" opts; do
        case $opts in
            p)
                _PID="$OPTARG"
                ;;
            l)
                _LOG_DIR="$OPTARG"
                ;;
            d)
                _LOG_DAY="$OPTARG"
                ;;
            f)
                _FUNCTION_NAME="$OPTARG"
                ;;
            v)
                _VERBOSE="Y"
                ;;
            h)
                help | less
                exit 0
        esac
    done

    if [ -n "$_FUNCTION_NAME" ]; then
        help "$_FUNCTION_NAME" | less
        exit
    fi

    # validation
    if [ "$USER" != "root" ]; then
        _log "ERROR" "Please run as 'root' user"
        exit 1
    fi

    f_check_system
    if [ -n "$_PID" ]; then
        f_check_process "$_PID"
    fi
    f_collect_config
    if [ -n "$_LOG_DIR" ]; then
        f_collect_log_files "$_LOG_DIR" "$_LOG_DAY"
    fi
    f_tar_work_dir
    _log "INFO" "Completed!"
fi