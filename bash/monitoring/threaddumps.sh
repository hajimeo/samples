#!/usr/bin/env bash
usage() {
    cat << 'EOF'

PURPOSE:
    Gather basic information to troubleshoot Java process related *performance* issues.
    Tested with Nexus official docker image: https://github.com/sonatype/docker-nexus3
    Currently this script gathers the following information:
     - Java thread dumps with jstack if available otherwise kill -3 (000.log)
     - top -H (001.log)
     - netstat or similar (002.log)
     - misc. OS info (900.log)

EXAMPLES:
    # Taking thread dumps whenever the log line contains "QuartzTaskInfo"
    # as "nexus" user
    cd /nexus-data;
    curl --compressed -O -L https://raw.githubusercontent.com/sonatype-nexus-community/nexus-monitoring/main/scripts/threaddumps.sh;
    bash ./threaddumps.sh -p `lsof -ti:8081 -sTCP:LISTEN` -f ./log/nexus.log -r "QuartzTaskInfo";

OPTIONS:
    -c  How many dumps (default 5)
    -i  Interval seconds (default 2)
    -f  File to monitor (-r is required)
    -r  Regex (used in 'grep -E') to monitor -f file
    -p  PID
    -o  Output directory (default: /tmp/)
EOF
}


_INTERVAL=2
_COUNT=5
_LOG_FILE=""
_REGEX=""
_PID=""
_OUT_DIR="/tmp"


function tailStdout() {
    local __doc__="Tail stdout file or XX:LogFile file"
    local _pid="$1"
    local _timeout="${2:-"30"}"
    local _outputFile="${3}"

    if [ -z "${_pid}" ]; then
        echo "No file to tail for pid:${_pid}" >&2
        return 1
    fi

    local _cmd=""
    local _sleep="0.5"
    rm -f /tmp/.tailStdout.run || return $?

    if [ -f /proc/${_pid}/fd/1 ]; then
        _cmd="tail -n0 -f /proc/${_pid}/fd/1"
    elif [[ "$(ps wwwp ${_pid})" =~ XX:LogFile=([^[:space:]]+) ]]; then
        # best effort. if one PID uses multiple jvm log paths (or if path contains space), can't find the correct one
        local jvmLog="$(basename "${BASH_REMATCH[1]}")"
        local jmvLogPath="$(ls -l /proc/${_pid}/fd | grep -oE "/[^ ]+/${jvmLog}$")"
        _cmd="tail -n0 -f "${jmvLogPath}""
    elif readlink -f /proc/${_pid}/fd/1 2>/dev/null | grep -q '/pipe:'; then
        _cmd="cat /proc/${_pid}/fd/1"
        _sleep="1"
    fi
    if [ -z "${_cmd}" ]; then
        echo "No file to tail for pid:${_pid}" >&2
        return 1
    fi
    if [ -n "${_outputFile}" ]; then
        _cmd="${_cmd} >> ${_outputFile}"
    fi
    eval "timeout ${_timeout}s ${_cmd}" &
    echo "$!" > /tmp/.tailStdout.run
    sleep ${_sleep}
}

function takeDumps() {
    local __doc__="Take multiple thread dumps for _pid"
    local _pid=${1:-${_PID}}
    local _count=${2:-${_COUNT:-5}}
    local _interval=${3:-${_INTERVAL:-2}}
    local _outDir="${4:-"/tmp"}"
    local _pfx="${5:-"script-$(date +"%Y%m%d%H%M%S")"}"
    local _outPfx="${_outDir%/}/${_pfx}"

    local _jstack=""
    if [ -x "${JAVA_HOME%/}/bin/jstack" ]; then
        _jstack="${JAVA_HOME%/}/bin/jstack"
    elif type jstack &>/dev/null; then
        _jstack="jstack"
    fi
    if [ -z "${_jstack}" ]; then
        if [ ! -f /proc/${_pid}/fd/1 ]; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN  No 'jstack' and no stdout file (so best effort)" >&2
        fi
        tailStdout "${_pid}" "$((${_count} * ${_interval} + 4))" "${_outPfx}000.log"
    fi

    for _i in $(seq 1 ${_count}); do
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] taking dump ${_i}/${_count} into '${_outPfx}*' ..." >&2
        if [ -n "${_jstack}" ]; then
            ${_jstack} -l ${_pid} >> "${_outPfx}000.log"
        else
            kill -3 "${_pid}"
        fi
        (date +"%Y-%m-%d %H:%M:%S"; top -H -b -n1 2>/dev/null | head -n60) >> "${_outPfx}001.log"
        (date +"%Y-%m-%d %H:%M:%S"; netstat -topen 2>/dev/null || cat /proc/net/tcp* 2>/dev/null) >> "${_outPfx}002.log"
        [ ${_i} -lt ${_count} ] && sleep ${_interval}
    done
    if [ -s /tmp/.tailStdout.run ]; then
        local _wpid="$(cat /tmp/.tailStdout.run)"
        ps -p ${_wpid} &>/dev/null && wait ${_wpid}
    fi
    if [ ! -s "${_outPfx}000.log" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR Failed to take Java thread dumps into ${_outPfx}000.log" >&2
    fi
    return 0
}

# miscChecks &> "${_outFile}"
function miscChecks() {
    local __doc__="Gather Misc. information"
    local _pid="$1"
    set -x
    # OS / kernel related
    uname -a
    cat /etc/*-release
    cat /proc/cmdline
    # disk / mount (nfs options)
    df -Th
    cat /proc/mounts
    # selinux / fips
    sestatus
    sysctl crypto.fips_enabled
    # is this k8s?
    cat /var/run/secrets/kubernetes.io/serviceaccount/namespace
    # service slowness
    systemd-analyze blame | head -n40
    # DNS (LDAP but not for Nexus) slowness
    nscd -g

    ps auxwwwf
    if [ -n "${_pid}" ]; then
        cat /proc/${_pid}/limits
        cat /proc/locks | grep -w "${_pid}"
        #ls -li /proc/${_pid}/fd/*
        pmap -x ${_pid}
    fi
    set +x
}

function _stopping() {
    local _pid="$(cat /tmp/.tailStdout.run 2>/dev/null)"
    [ -z "${_pid}" ] && exit
    echo -n -e "\nStopping "
    for _i in $(seq 1 10); do
        sleep 1
        if ! ps -p "${_pid}" &>/dev/null ; then
            echo "" | tee /tmp/.tailStdout.run
            exit
        fi
        echo -n "."
    done
    echo -e "\nFailed to stop gracefully (${_pid})"
    exit 1
}

main() {
    local _pfx="${1:-"script-$(date +"%Y%m%d%H%M%S")"}"
    local _pid="${2:-"${_PID}"}"
    [ -z "${_pid}" ] && echo "No PID (-p) provided." >&2 && usage && return 1

    local _misc_start=$(date +%s)
    miscChecks "${_PID}" &> "${_OUT_DIR%/}/${_pfx}900.log"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] miscChecks completed ($(( $(date +%s) - ${_misc_start} ))s)" >&2
    # NOTE: same infor as prometheus is in support zip

    # No monitoring log file specified, so taking dumps normally
    if [ -z "${_LOG_FILE}" ]; then
        takeDumps "${_PID}" "${_COUNT}" "${_INTERVAL}" "${_OUT_DIR%/}" "${_pfx}"
        return $?
    fi

    [ ! -f "${_LOG_FILE}" ] && echo "${_LOG_FILE} does not exist." >&2 && usage && return 1
    [ -z "${_REGEX}" ] && echo "'-f' is provided but no '-r'." >&2 && usage && return 1
    echo "Monitoring ${_LOG_FILE} with '${_REGEX}' ..." >&2
    while true; do
        if tail -n0 -F "${_LOG_FILE}" | grep --line-buffered -m1 -E "${_REGEX}"; then
            trap "_stopping" SIGINT
            takeDumps "${_PID}" "${_COUNT}" "${_INTERVAL}" "${_OUT_DIR%/}"
            sleep 1
        fi
    done
}

if [ "$0" = "${BASH_SOURCE[0]}" ]; then
    #if [ "$#" -eq 0 ]; then
    if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ]; then
        usage
        exit 0
    fi

    while getopts "c:i:p:f:r:o:" opts; do
        case $opts in
            c)
                [ -n "$OPTARG" ] && _COUNT="$OPTARG"
                ;;
            i)
                [ -n "$OPTARG" ] && _INTERVAL="$OPTARG"
                ;;
            f)
                _LOG_FILE="$OPTARG"
                ;;
            r)
                _REGEX="$OPTARG"
                ;;
            p)
                [ -n "$OPTARG" ] && _PID="$OPTARG"
                ;;
            o)
                [ -n "$OPTARG" ] && _OUT_DIR="$OPTARG"
                ;;
            *)
                echo "$opts $OPTARG is not supported. Ignored." >&2
                ;;
        esac
    done

    _PFX="script-$(date +"%Y%m%d%H%M%S")"
    main "${_PFX}" #"$@"
    echo "Completed (${_OUT_DIR%/}/${_PFX}*)"
fi
