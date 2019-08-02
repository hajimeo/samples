#!/usr/bin/env bash
# NOTE: This script requires "lsof", so may require root priv.
#       Put this script under /etc/cron.hourly/ with *execution* permission.
# curl -o /etc/cron.hourly/resource_chk.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/resource_chk.sh && chmod a+x /etc/cron.hourly/resource_chk.sh

_PER_HOUR="${1:-3}"   # How often checks per hour (3 means 20 mins interval)
_TIMEOUT_SEC="${2:-5}"  # If health check takes longer this seconds, it does extra check

_PORT="10502"           # Used to determine PID
_URLS=""                # Health check url per line


function cmds() {
    local _user="${1:-${_USER}}"
    date -u
    lsof -nPu ${_user} | awk '{print "PID-->"$2}' | uniq -c | sort -n | tail -5
    echo -n "# Total AtScale Usage -->";lsof -u ${_user} | wc -l
    echo -n "# Total System Usage -->";lsof | wc -l
    echo "# AtScale User processes are -->"; lsof -nPu ${_user} | awk '{print $2}' | uniq -c | sort -n | tail -5 | awk '{print $2}' |while IFS= read a_pid ; do pwdx $a_pid; done
    echo "# Memory Usage --->"; free -tm
    echo "# Disk Usage --->"; df -h /
    echo "# CPU Usage --->"; mpstat -P ALL
    top -c -b -n 1 | head -n 20
    netstat -i
    echo ""
}

function health() {
    local _url="$1"
    local _timeout="${2:-${_TIMEOUT_SEC}}"
    [[ "${_url}" =~ ^https?://([^:/]+) ]]
    local _host="${BASH_REMATCH[1]}"
    if [ -n "${_host}" ]; then
        echo "# Ping to ${_host} check --->"
        ping -n -W 1 -c 1 ${_host}
    fi
    echo "# URL ${_url} check --->"
    if ! curl -s -m ${_timeout} --retry 1 -w " - %{time_starttransfer}\n" -f -k "${_url}"; then
        echo "# URL took more than ${_timeout} sec --->"
        java_chk
    fi
}

function java_chk() {
    local _pid="${1:-${_PID}}"   # Java PID
    local _user="${2:-${_USER}}"
    local _dir="${3:-${_DIR}}"
    [ -z "$_pid" ] && return 1
    local _cmd_dir="$(dirname `readlink /proc/${_pid}/exe` 2>/dev/null)"
    #cat /proc/${_pid}/limits
    #cat /proc/${_pid}/status
    #pmap -x ${_pid} &> ${_dir%}/pmap_$(date +%u).out
    if [ -d "$_cmd_dir" ]; then
        local _java_home="$(dirname $_cmd_dir)"
        local _pre_cmd=""; which timeout &>/dev/null && _pre_cmd="timeout 12"
        [ -x "${_cmd_dir}/jstat" ] && $_pre_cmd sudo -u ${_user} ${_cmd_dir}/jstat -gccause ${_pid} 1000 9 &> ${_dir%}/gccause_$(date +%u).out &
        for i in {1..3};do top -Hb -p ${_pid} | head -n 20; $_pre_cmd kill -QUIT ${_pid}; sleep 3; done
    fi
    wait
}

if [ "$0" = "$BASH_SOURCE" ]; then
    _INTERVAL=$(( 60 * 60 / ${_PER_HOUR} ))

    _PID="$(lsof -ti:${_PORT} -s TCP:LISTEN)" || exit 1
    _USER="$(stat -c '%U' /proc/${_PID})" || exit 1
    _DIR="$(strings /proc/${_PID}/environ | sed -nr 's/^AS_LOG_DIR=(.+)/\1/p')" || exit 1
    [ ! -d "${_DIR}" ] && _DIR="/tmp"
    _FILE_PATH="${_DIR%/}/resource_chk_$(date +%u).log"

    if [ -s "${_FILE_PATH}" ]; then
        _LAST_MOD_TS=$(stat -c%Y ${_FILE_PATH})
        _NOW=$(date +%s)
        # If older than one day, clear
        [ 86400 -lt $((${_NOW} - ${_LAST_MOD_TS})) ] && > ${_FILE_PATH}
    fi

    for i in `seq 1 ${_PER_HOUR}`; do
        cmds "${_USER}" &>> ${_FILE_PATH}
        if [ -n "${_URLS}" ]; then
            echo "${_URLS}" | while read -r _u; do health "$_u"; done
        fi
        sleep ${_INTERVAL}
    done
fi