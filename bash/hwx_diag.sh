#!/bin/env bash

usage() {
    echo "This script is for collecting OS command outputs, and if Java, it uses jstat, jstack and jmap for a PID.
$BASH_SOURCE PID [workspace dir]
Example:
    $BASH_SOURCE \"\`cat /var/run/kafka/kafka.pid\`\""
}

function f_chksys() {
    local __doc__="Execute OS commands for performance issue. If PID is given, run more commands"
    local _p="$1"	# Java PID ex: `cat /var/run/kafka/kafka.pid`
    local _work_dir="$2"

    [ -z "${_work_dir}" ] && _work_dir="/tmp/${FUNCNAME}_tmp_dir"
    if [ ! -d "$_work_dir" ] && ! mkdir $_work_dir; then
        _log "ERROR" "Couldn't create $_work_dir directory"; return 1
    fi

    if [ -n "$_p" ]; then
        _log "INFO" "Collecting java PID $_p related information..."
        local _user="`stat -c '%U' /proc/${_p}`"
        local _cmd_dir="$(dirname `readlink /proc/${_p}/exe`)" 2>/dev/null

        if [ -d "$_cmd_dir" ]; then
            [ -x ${_cmd_dir}/jstack ] && for i in {1..3};do sudo -u ${_user} ${_cmd_dir}/jstack -l ${_p}; sleep 5; done &> ${_work_dir%/}/jstack_${_p}.out &
            [ -x ${_cmd_dir}/jstat ] && sudo -u ${_user} ${_cmd_dir}/jstat -gccause ${_p} 1000 5 &> ${_work_dir%/}/jstat_${_p}.out &
            [ -x ${_cmd_dir}/jmap ] && sudo -u ${_user} ${_cmd_dir}/jmap -histo ${_p} &> ${_work_dir%/}/jmap_histo_${_p}.out &
        fi

        ps -eLo user,pid,lwp,nlwp,ruser,pcpu,stime,etime,args | grep -w "${_p}" &> ${_work_dir%/}/pseLo_${_p}.out
        cat /proc/${_p}/limits &> ${_work_dir%/}/proc_limits_${_p}.out
        cat /proc/${_p}/status &> ${_work_dir%/}/proc_status_${_p}.out
        cat /proc/${_p}/io &> ${_work_dir%/}/proc_io_${_p}.out;sleep 5;cat /proc/${_p}/io >> ${_work_dir%/}/proc_io_${_p}.out
        cat /proc/${_p}/environ | tr '\0' '\n' > ${_work_dir%/}/proc_environ_${_p}.out
        lsof -nPp ${_p} &> ${_work_dir%/}/lsof_${_p}.out
        pmap -x ${_p} &> ${_work_dir%/}/pmap_${_p}.out
    fi

    _log "INFO" "Collecting OS related information..."
    vmstat 1 3 &> ${_work_dir%/}/vmstat.out &
    pidstat -dl 3 3 &> ${_work_dir%/}/pstat.out &
    sysctl -a &> ${_work_dir%/}/sysctl.out
    top -b -n 1 -c &> ${_work_dir%/}/top.out
    ps auxwwwf &> ${_work_dir%/}/ps.out
    netstat -aopen &> ${_work_dir%/}/netstat.out
    netstat -i &> ${_work_dir%/}/netstat_i.out
    netstat -s &> ${_work_dir%/}/netstat_s.out
    ifconfig &> ${_work_dir%/}/ifconfig.out
    nscd -g &> ${_work_dir%/}/nscd.out
    wait
    _log "INFO" "Creating tar.gz file..."
    local _file_path="./chksys_$(hostname)_$(date +"%Y%m%d%H%M%S").tar.gz"
    tar --remove-files -czf ${_file_path} ${_work_dir%/}/*.out
    _log "INFO" "Completed! (${_file_path})"
}

function _log() {
    # At this moment, outputting to STDERR
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}

if [ "$0" = "$BASH_SOURCE" ]; then
    if [ -z "$1" ]; then
        usage
        exit
    fi

    if [ "$USER" != "root" ]; then
        _log "ERROR" "Please run as 'root' user"
        exit 1
    fi

    f_chksys $@
fi