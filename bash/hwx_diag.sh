#!/bin/env bash

function f_chksys() {
    local __doc__="Execute OS command to check system for triage"
    local _u="$1"	# component process owner
    local _p="$2"	# Java PID ex: `cat /var/run/kafka/kafka.pid`
    local _work_dir="$3"
    [ -z "${_work_dir}" ] && _work_dir="${FUNCNAME}_tmp_dir"
    if [ ! -d "$_work_dir" ] && ! mkdir $_work_dir; then
        echo "ERROR: Couldn't create $_work_dir directory"; return 1
    fi

    if [ -n "$_p" ]; then
        echo "Collecting java PID $_p related information..."
        local _j="$(dirname `readlink /proc/${_p}/exe`)" 2>/dev/null
        if [ -n "$_u" ] && [ -n "$_j" ]; then
            for i in {1..3};do sudo -u ${_u} ${_j}/jstack -l ${_p}; sleep 5; done &> ${_work_dir%/}/jstack_${_p}.out &
            sudo -u ${_u} ${_j}/jstat -gccause ${_p} 1000 5 &> ${_work_dir%/}/jstat_${_p}.out &
            sudo -u ${_u} ${_j}/jmap -histo ${_p} &> ${_work_dir%/}/jmap_histo_${_p}.out &
        fi
        ps -eLo user,pid,lwp,nlwp,ruser,pcpu,stime,etime,args | grep -w "${_p}" &> ${_work_dir%/}/pseLo_${_p}.out
        cat /proc/${_p}/limits &> ${_work_dir%/}/proc_limits_${_p}.out
        cat /proc/${_p}/status &> ${_work_dir%/}/proc_status_${_p}.out
        cat /proc/${_p}/io &> ${_work_dir%/}/proc_io_${_p}.out;sleep 5;cat /proc/${_p}/io >> ${_work_dir%/}/proc_io_${_p}.out
        cat /proc/${_p}/environ | tr '\0' '\n' > ${_work_dir%/}/proc_environ_${_p}.out
        pmap -x ${_p} &> ${_work_dir%/}/pmap_${_p}.out
    fi

    echo "Collecting OS related information..."
    vmstat 1 3 &> ${_work_dir%/}/vmstat.out &
    pidstat -dl 3 3 &> ${_work_dir%/}/pstat.out &
    top -b -n 1 -c &> ${_work_dir%/}/top.out
    ps auxwwwf &> ${_work_dir%/}/ps.out
    netstat -aopen &> ${_work_dir%/}/netstat.out
    netstat -i &> ${_work_dir%/}/netstat_i.out
    netstat -s &> ${_work_dir%/}/netstat_s.out
    ifconfig &> ${_work_dir%/}/ifconfig.out
    nscd -g &> ${_work_dir%/}/nscd.out
    wait
    echo "Creating tar.gz file..."
    tar czf ./${FUNCNAME}_$(hostname)_$(date +"%Y%m%d%H%M%S").tar.gz ${_work_dir%/}/*.out
    echo "Completed!"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    if [ -z "$1" ]; then
        echo "$BASH_SOURCE userId PID [workspace dir]"
        echo "Example:"
        echo $BASH_SOURCE 'kafka "`cat /var/run/kafka/kafka.pid`"'
        exit
    fi

    if [ "$USER" != "root" ]; then
        echo "Please run as 'root' user"
        exit 1
    fi
    f_chksys "$1" "$2" "$3"
fi