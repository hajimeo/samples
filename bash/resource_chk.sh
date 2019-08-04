#!/usr/bin/env bash
# NOTE: This script requires "lsof" and "sysstat".
#       Put this script under /etc/cron.hourly/ with *execution* permission.
#
# curl -o /etc/cron.hourly/resource_chk.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/resource_chk.sh && chmod a+x /etc/cron.hourly/resource_chk.sh
# run-parts --test /etc/cron.hourly
# service crond status
# cat /etc/cron.d/0hourly
#

# Arguments
_PORT="${1:-10502}"     # Used to determine the PID
_URLS="${2}"            # Comma separated Health check URLs
_PER_HOUR="${3:-6}"     # How often checks per hour (6 means 10 mins interval)
_TIMEOUT_SEC="${4:-2}"  # If health check takes longer this seconds, it does extra check
_FILE_PATH="${5}"       # Log file path. If empty, automatically decided by PID.

# If no URLs give, check local's port (or please specify your URLs in here)
[ -z "${_URLS}" ] && _URLS="http://`hostname -f`:${_PORT}/"

# Global variables
_INTERVAL=$(( 60 * 60 / ${_PER_HOUR} ))
_PID="$(lsof -ti:${_PORT} -s TCP:LISTEN)" || exit 0
_USER="$(stat -c '%U' /proc/${_PID})" || exit 1
_DIR="$(strings /proc/${_PID}/environ | sed -nr 's/^AS_LOG_DIR=(.+)/\1/p')"
[ ! -d "${_DIR}" ] && _DIR="/tmp"
[ -z "${_FILE_PATH}" ] && _FILE_PATH="${_DIR%/}/resource_chk_$(date +%u).log"


# OS commands which run once in hour or when health issue happens
function cmds() {
    local _user="${1:-${_USER}}"
    if [ -n "${_user}" ]; then
        lsof -nPu ${_user} > /tmp/.cmds_lsof.out
        echo -n "AtScale User lsof count --> ";cat /tmp/.cmds_lsof.out | wc -l
        echo "AtScale User processes (top 5) -->"
        echo -e "COUNT\tPID: pwd"
        cat /tmp/.cmds_lsof.out | awk '{print $2}' | uniq -c | sort -n | tail -5 | while read -r _l; do [[ "${_l}" =~ ^[[:space:]]*([0-9]+)[[:space:]]+([0-9]+) ]] && echo -e "${BASH_REMATCH[1]}\t$(pwdx ${BASH_REMATCH[2]})"; done
        echo -n "OS allocated file handler --> ";cat /proc/sys/fs/file-nr   # NOTE: lsof not equal to fd/fh
    fi
    echo "[$(date -u +'%Y-%m-%d %H:%M:%S') UTC] Memory Usage --->"; free -tm
    echo "[$(date -u +'%Y-%m-%d %H:%M:%S') UTC] CPU Usage --->"; mpstat -P ALL 2>/dev/null; top -c -b -n 1 | head -n 20
    echo "[$(date -u +'%Y-%m-%d %H:%M:%S') UTC] Disk Usage --->"; iostat -x 2>/dev/null; df -h /
    echo "[$(date -u +'%Y-%m-%d %H:%M:%S') UTC] Network Usage --->"; netstat -i
    echo ""
}

# Health monitoring commands which should be OK to run frequently (don't put any slow command)
function health() {
    local _url="$1"
    local _timeout="${2:-${_TIMEOUT_SEC}}"
    [ -z "${_url}" ] && return 1
    [[ "${_url}" =~ ^https?://([^:/]+) ]]
    local _host="${BASH_REMATCH[1]}"

    echo -n "[$(date -u +'%Y-%m-%d %H:%M:%S') UTC] URL ${_url} check --->"; time curl -s -m ${_timeout} --retry 0 -f -L -k -o /dev/null "${_url}"
    local _rc="$?"
    if [ "${_rc}" != "0" ]; then
        echo "[$(date -u +'%Y-%m-%d %H:%M:%S') UTC] URL took more than ${_timeout} sec or failed (${_rc}) --->"
        cmds
        if [ "${_rc}" == "28" ]; then
            time curl -s -v -m 12 --retry 0 -f -L -k -o /dev/null -w "\ntime_namelookup:\t%{time_namelookup}\ntime_connect:\t%{time_connect}\ntime_appconnect:\t%{time_appconnect}\ntime_pretransfer:\t%{time_pretransfer}\ntime_redirect:\t%{time_redirect}\ntime_starttransfer:\t%{time_starttransfer}\n----\ntime_total:\t%{time_total}\nhttp_code:\t%{http_code}\nspeed_download:\t%{speed_download}\nspeed_upload:\t%{speed_upload}\n" "${_url}" &
            local _wpid=$!
            # Currently, only if hostname matches, so that when remote is down, it won't spam local.
            [ "$(hostname -f)" == "${_host}" ] && java_chk
            wait ${_wpid}
        fi
        if [ -n "${_host}" ]; then
            echo "[$(date -u +'%Y-%m-%d %H:%M:%S') UTC] Ping to ${_host} check --->"
            # Sometimes ICMP is blocked, so not stop if ping fails
            # TODO: add better network checking. eg: mtr/traceroute, iperf/iperf3?
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
    for i in {1..3};do echo "$(date -u +'%Y-%m-%d %H:%M:%S') UTC"; top -Hb -p ${_pid} | head -n 20; $_pre_cmd kill -QUIT ${_pid}; sleep 3; done &> /tmp/top_thread.out &
    local _wpid1=$!
    (echo "$(date -u +'%Y-%m-%d %H:%M:%S') UTC"; $_pre_cmd sudo -u ${_user} ${_cmd_dir}/jstat -gccause ${_pid} 1000 10) &> /tmp/gccause.out &
    local _wpid2=$!
    wait ${_wpid1} ${_wpid2}
    cat /tmp/top_thread.out
    cat /tmp/gccause.out
}

if [ "$0" = "$BASH_SOURCE" ]; then
    # If the file last modified date is older than one day, clear the contents
    if [ -s "${_FILE_PATH}" ]; then
        _LAST_MOD_TS=$(stat -c%Y ${_FILE_PATH})
        _NOW=$(date +%s)
        [ 86400 -lt $((${_NOW} - ${_LAST_MOD_TS})) ] && > ${_FILE_PATH}
    fi

    # Executing commands which should be run once per hour
    echo "### START at $(date -u +'%Y-%m-%d %H:%M:%S') UTC ################" &>> ${_FILE_PATH}
    cmds &>> ${_FILE_PATH}

    # Executing health monitoring commands if urls are given
    if [ -n "${_URLS}" ]; then
        for i in `seq 1 ${_PER_HOUR}`; do
            sleep ${_INTERVAL}
            echo "${_URLS}" | sed 's/,/\n/' | while read -r _u; do health "$_u" &>> ${_FILE_PATH}; done
        done
    fi
    echo "### ENDED at $(date -u +'%Y-%m-%d %H:%M:%S') UTC ################" &>> ${_FILE_PATH}
fi