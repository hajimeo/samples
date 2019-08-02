#!/usr/bin/env bash
# NOTE: This script requires "lsof", so may require root priv.
#       Put this script under /etc/cron.hourly/ with *execution* permission.
# curl -o /etc/cron.hourly/collect_stats.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/collect_stats.sh && chmod a+x /etc/cron.hourly/collect_stats.sh

_PORT="10502"

function cmds() {
    local _user="${1:-${_USER}}"
    date -u
    lsof -nPu ${_user} | awk '{print "PID-->"$2}' | uniq -c | sort -n | tail -5
    echo -n "Total AtScale Usage -->";lsof -u ${_user} | wc -l
    echo -n "Total System Usage -->";lsof | wc -l
    echo "AtScale User processes are -->"; lsof -nPu ${_user} | awk '{print $2}' | uniq -c | sort -n | tail -5 | awk '{print $2}' |while IFS= read a_pid ; do pwdx $a_pid; done
    echo "Memory Usage --->"; free -tm
    echo "Disk Usage --->"; df -h /
    echo "CPU Usage --->"; mpstat -P ALL
    echo ""
}

if [ "$0" = "$BASH_SOURCE" ]; then
    _PER_HOUR="${1:-"3"}"
    _INTERVAL=$(( 60 * 60 / ${_PER_HOUR} ))

    _PID="$(lsof -ti:${_PORT} -s TCP:LISTEN)" || exit 1
    _USER="$(stat -c '%U' /proc/${_PID})" || exit 1
    _DIR="$(strings /proc/${_PID}/environ | sed -nr 's/^AS_LOG_DIR=(.+)/\1/p')" || exit 1
    [ ! -d "${_DIR}" ] && _DIR="/tmp"
    _FILE_PATH="${_DIR%/}/as_usage_$(date +%u).out"

    if [ -s "${_FILE_PATH}" ]; then
        _LAST_MOD_TS=$(stat -c%Y ${_FILE_PATH})
        _NOW=$(date +%s)
        # If older than one day, clear
        [ 86400 -lt $((${_NOW} - ${_LAST_MOD_TS})) ] && > ${_FILE_PATH}
    fi

    for i in `seq 1 ${_PER_HOUR}`; do
        cmds &> ${_FILE_PATH}
        sleep ${_INTERVAL}
    done
fi