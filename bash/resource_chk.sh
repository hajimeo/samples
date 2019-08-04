#!/usr/bin/env bash
# NOTE: This script requires "lsof" and "sysstat" (and iperf/iperf3).
#       Put this script under /etc/cron.hourly/ with *execution* permission.
#
# curl -o /etc/cron.hourly/resource_chk.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/resource_chk.sh && chmod a+x /etc/cron.hourly/resource_chk.sh
# run-parts --test /etc/cron.hourly
# service crond status
# cat /etc/cron.d/0hourly
#

_PER_HOUR="${1:-6}"   # How often checks per hour (3 means 20 mins interval)
_TIMEOUT_SEC="${2:-5}"  # If health check takes longer this seconds, it does extra check

_PORT="10502"           # Used to determine PID
# Health check url per line
_URLS="http://node2.ubu18kvm2.localdomain:10502/health
http://node3.ubu18kvm2.localdomain:10502/health"

# OS commands which run once in hour or when health issue happens
function cmds() {
    local _user="${1:-${_USER}}"
    echo "### Start 'comds' at $(date -u +'%Y-%m-%d %H:%M:%S') UTC ################"
    echo "# Memory Usage --->"; free -tm
    echo "# CPU Usage --->"; mpstat -P ALL; top -c -b -n 1 | head -n 20
    echo "# Disk Usage --->"; df -h /; iostat -x
    echo "# Network Usage --->"; netstat -i
    #echo -n "# Total System Usage -->";lsof | wc -l
    if [ -n "${_user}" ]; then
        lsof -nPu ${_user} > /tmp/.cmds_lsof.out
        cat /tmp/.cmds_lsof.out | awk '{print "PID-->"$2}' | uniq -c | sort -n | tail -5
        echo -n "# Total AtScale Usage -->";cat /tmp/.cmds_lsof.out | wc -l
        echo "# AtScale User processes are -->"; cat /tmp/.cmds_lsof.out | awk '{print $2}' | uniq -c | sort -n | tail -5 | awk '{print $2}' | while IFS= read a_pid ; do pwdx $a_pid; done
    fi
    echo "### Ended 'comds' at $(date -u +'%Y-%m-%d %H:%M:%S') UTC ################"
    echo ""
}

# Health monitoring commands which should be OK to run frequently (don't put any slow command)
function health() {
    local _url="$1"
    local _timeout="${2:-${_TIMEOUT_SEC}}"
    [ -z "${_url}" ] && return 1
    [[ "${_url}" =~ ^https?://([^:/]+) ]]
    local _host="${BASH_REMATCH[1]}"

    echo "# URL ${_url} check --->"
    curl -s -m ${_timeout} --retry 1 -w " - %{time_starttransfer}\n" -f -k "${_url}"
    local _rc="$?"
    if [ "${_rc}" != "0" ]; then
        echo "# URL took more than ${_timeout} sec or failed --->"
        if [ "${_rc}" == "28" ]; then
            # Currently, only if hostname matches, so that when remote is down, it won't spam local.
            [ "$(hostname -f)" == "${_host}" ] && java_chk
        fi
        cmds
        if [ -n "${_host}" ]; then
            echo "# Ping to ${_host} check --->"
            # Sometimes ICMP is blocked, so not stop if ping fails
            # TODO: add better network checking. eg: traceroute
            ping -W 1 -c 4 ${_host} # -n
        fi
    fi
}

# Variouse check commands for Java process
function java_chk() {
    local _pid="${1:-${_PID}}"   # Java PID
    local _user="${2:-${_USER}}"
    local _dir="${3:-${_DIR}}"
    [ -z "$_pid" ] && return 1
    #cat /proc/${_pid}/limits
    #cat /proc/${_pid}/status
    #pmap -x ${_pid} &> ${_dir%}/pmap_$(date +%u).out
    local _cmd_dir="$(dirname `readlink /proc/${_pid}/exe` 2>/dev/null)"
    [ ! -d "$_cmd_dir" ] && return 1
    
    local _java_home="$(dirname $_cmd_dir)"
    local _pre_cmd=""; which timeout &>/dev/null && _pre_cmd="timeout 12"
    [ -x "${_cmd_dir}/jstat" ] && $_pre_cmd sudo -u ${_user} ${_cmd_dir}/jstat -gccause ${_pid} 1000 9 &> ${_dir%}/gccause_$(date +%u).out &
    for i in {1..3};do top -Hb -p ${_pid} | head -n 20; $_pre_cmd kill -QUIT ${_pid}; sleep 3; done &> ${_dir%}/top_thread_$(date +%u).out
    wait
}

# Cron may not like below, so just in case commenting
#if [ "$0" = "$BASH_SOURCE" ]; then
    _INTERVAL=$(( 60 * 60 / ${_PER_HOUR} ))
    _PID="$(lsof -ti:${_PORT} -s TCP:LISTEN)" || exit 0
    _USER="$(stat -c '%U' /proc/${_PID})" || exit 1
    _DIR="$(strings /proc/${_PID}/environ | sed -nr 's/^AS_LOG_DIR=(.+)/\1/p')"
    [ ! -d "${_DIR}" ] && _DIR="/tmp"
    _FILE_PATH="${_DIR%/}/resource_chk_$(date +%u).log"

    if [ -s "${_FILE_PATH}" ]; then
        _LAST_MOD_TS=$(stat -c%Y ${_FILE_PATH})
        _NOW=$(date +%s)
        # If older than one day, clear
        [ 86400 -lt $((${_NOW} - ${_LAST_MOD_TS})) ] && > ${_FILE_PATH}
    fi

    # Executing commands which should be run once per hour
    cmds &>> ${_FILE_PATH}

    # Executing health monitoring commands
    for i in `seq 1 ${_PER_HOUR}`; do
        [ -n "${_URLS}" ] && echo "${_URLS}" | while read -r _u; do health "$_u" &>> ${_FILE_PATH}; done
        sleep ${_INTERVAL}
    done
#fi
