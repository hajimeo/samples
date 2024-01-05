#!/usr/bin/env bash
usage() {
    cat << EOF
bash <(curl -sfL https://raw.githubusercontent.com/sonatype-nexus-community/nexus-monitoring/main/scripts/iq-threaddumps.sh --compressed)

PURPOSE:
Gather basic information to troubleshoot Java process related *performance* issues.
Designed for Nexus official docker image: https://github.com/sonatype/docker-nexus-iq-server
Currently this script gathers the following information:
 - Java thread dumps with kill -3 or jstack or :8071/threads, with netstat (or equivalent) and top

EXAMPLE:
    # Taking thread dumps whenever the log line contains "QuartzJobStoreTX"
    # as "nexus" user
    cd /sonatype-work;  # or cd /sonatype-work/clm-cluster;
    curl --compressed -O -L https://raw.githubusercontent.com/sonatype-nexus-community/nexus-monitoring/main/scripts/iq-threaddumps.sh;
    bash ./iq-threaddumps.sh -f /var/log/nexus-iq-server/clm-server.log -r "QuartzJobStoreTX";

USAGE:
    -c  How many dumps (default 5)
    -i  Interval seconds (default 2)
    -s  Path to config.yml file
    -f  File to monitor (-r is required)
    -r  Regex (used in 'grep -E') to monitor -f file
    -p  PID
    -o  Output directory (default /tmp)
EOF
}


: "${_INSTALL_DIR:=""}"
: "${_WORK_DIR:=""}"
: "${_ADMIN_URL:=""}"
_INTERVAL=2
_COUNT=5
_STORE_FILE=""
_LOG_FILE=""
_REGEX=""
_PID=""
_OUT_DIR=""


function detectDirs() {    # Best effort. may not return accurate dir path
    local __doc__="Populate PID and directory path global variables"
    local _pid="${1:-"${_PID}"}"
    if [ -z "${_pid}" ]; then
        _pid="$(ps auxwww | grep -E 'nexus-iq-server.*\.jar server' | grep -vw grep | awk '{print $2}' | tail -n1)"
        _PID="${_pid}"
        [ -z "${_pid}" ] && return 11
    fi
    if [ ! -d "${_INSTALL_DIR}" ]; then
        _INSTALL_DIR="$(readlink -f /proc/${_pid}/cwd 2>/dev/null)"
        if [ -z "${_INSTALL_DIR}" ]; then
            if type lsof &>/dev/null; then  # eg. Mac (Darwin)
                _INSTALL_DIR="$(lsof -a -d cwd -p ${_pid} | grep -w "${_pid}" | awk '{print $9}')"
            else
                local _jarpath="$(ps wwwp ${_pid} 2>/dev/null | grep -m1 -E -o 'nexus-iq-server.*\.jar')"
                _INSTALL_DIR="$(dirname "${_jarpath}")"
            fi
        fi
        [ -d "${_INSTALL_DIR}" ] || return 12
    fi
    if [ -z "${_STORE_FILE}" ]; then
        _STORE_FILE="$(ps wwwp ${_pid} | sed -n -E '/nexus-iq-server/ s/.+\.jar server ([^ ]+).*/\1/p' | head -n1)"
        [[ ! "${_STORE_FILE}" =~ ^/ ]] && _STORE_FILE="${_INSTALL_DIR%/}/${_STORE_FILE}"
        [ -e "${_STORE_FILE}" ] && _STORE_FILE="$(readlink -f "${_STORE_FILE}")"
    fi
    if [ ! -d "${_WORK_DIR}" ] && [ -d "${_INSTALL_DIR%/}" ]; then
        _WORK_DIR="$(sed -n -E 's/sonatypeWork[[:space:]]*:[[:space:]]*(.+)/\1/p' "${_STORE_FILE}")"
        [[ ! "${_WORK_DIR}" =~ ^/ ]] && _WORK_DIR="${_INSTALL_DIR%/}/${_WORK_DIR}"
        [ -d "${_WORK_DIR}" ] || return 13
    fi
}

function detectAdminUrl() {
    if [ -z "${_ADMIN_URL}" ]; then
        # Expecting detectDirs has already run or _STORE_FILE has been specified
        if [ -f "${_STORE_FILE}" ]; then
            # Best effort. If customised, won't work
            local _proto="http"
            local _port="8071"
            local _lines="$(grep -E '^server:' -A 100 "${_STORE_FILE}" | grep -E '^\s+adminConnectors:' -A3 | grep -wE "(port|type)" | paste - -)"
            if [[ "${_lines}" =~ port[[:space:]]*:[[:space:]]*[![:space:]]?([0-9]+) ]]; then    # \d wouldn't work
                _port="${BASH_REMATCH[1]}"
            fi
            if [[ "${_lines}" =~ type[[:space:]]*:[[:space:]]*[![:space:]]?(http|https) ]]; then
                _proto="${BASH_REMATCH[1]}"
            fi
            _ADMIN_URL="${_proto}://localhost:${_port}"
        else
            _ADMIN_URL="http://localhost:8071"
        fi
    fi
    if [ -n "${_ADMIN_URL%/}" ] && curl -m1 -sf -k "${_ADMIN_URL%/}/ping" -o/dev/null; then
        echo "${_ADMIN_URL%/}"
        return 0
    fi
    return 1
}

function tailStdout() {
    local __doc__="Tail stdout file or XX:LogFile file"
    local _pid="$1"
    local _timeout="${2:-"30"}"
    local _outputFile="${3}"
    local _installDir="${4-"${_INSTALL_DIR%/}"}"
    local _cmd=""
    local _sleep="0.5"
    rm -f /tmp/.tailStdout.run || return $?

    if [ -f /proc/${_pid}/fd/1 ]; then
        _cmd="tail -n0 -f /proc/${_pid}/fd/1"
    elif [ -n "${_installDir}" ] && [[ "$(ps wwwp ${_pid})" =~ XX:LogFile=([^[:space:]]+) ]]; then
        local jvmLog="${BASH_REMATCH[1]}"
        _cmd="tail -n0 -f "${_installDir%/}/${jvmLog#/}""
    elif readlink -f /proc/${_pid}/fd/1 2>/dev/null | grep -q '/pipe:'; then
        #_cmd="cat /proc/${_pid}/fd/1"
        _cmd=""
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
    local _storeProp="${4:-"${_STORE_FILE}"}"
    local _installDir="${5-"${_INSTALL_DIR%/}"}"
    local _outDir="${6:-"/tmp"}"
    local _pfx="${7:-"script-$(date +"%Y%m%d%H%M%S")"}"
    local _outPfx="${_outDir%/}/${_pfx}"

    local _jstack=""
    local _admin_url=""
    if [ -x "${JAVA_HOME%/}/bin/jstack" ]; then
        _jstack="${JAVA_HOME%/}/bin/jstack"
    elif type jstack &>/dev/null; then
        _jstack="jstack"
    fi
    if [ -z "${_jstack}" ]; then
        if [ ! -f /proc/${_pid}/fd/1 ]; then
            _admin_url="$(detectAdminUrl)"
            if [ -n "${_admin_url}" ]; then
                echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN  No 'jstack' and no stdout file. Using ${_admin_url%/}/threads" >&2
            else
                echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN  No 'jstack' and no stdout file (so best effort)" >&2
            fi
        fi
        if [ -z "${_admin_url}" ]; then
            tailStdout "${_pid}" "$((${_count} * ${_interval} + 4))" "${_outPfx}000.log" "${_installDir}"
        fi
    fi

    for _i in $(seq 1 ${_count}); do
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] taking dump ${_i}/${_count} into '${_outPfx}*' ..." >&2
        local _wpid_in_for=""
        if [ -s "${_storeProp}" ]; then
            # TODO: If _storeProp is given, do extra check for IQ
            _wpid_in_for="" #$!
        fi
        if [ -n "${_jstack}" ]; then
            ${_jstack} -l ${_pid} >> "${_outPfx}000.log"
        elif [ -n "${_admin_url}" ]; then
            local _curl_m="$((${_interval} + 3))"   # for IQ admin port, wait a bit longer
            date --rfc-3339=seconds >> "${_outPfx}000.log"
            if ! curl -m${_curl_m:-"5"} -sSf -k "${_admin_url%/}/threads" >> "${_outPfx}000.log"; then
                kill -3 "${_pid}"   # Need to use 'docker logs' or 'kubectl logs'
            fi
        else
            kill -3 "${_pid}"
        fi
        (date +"%Y-%m-%d %H:%M:%S"; top -H -b -n1 2>/dev/null | head -n60) >> "${_outPfx}001.log"
        (date +"%Y-%m-%d %H:%M:%S"; netstat -topen 2>/dev/null || cat /proc/net/tcp* 2>/dev/null) >> "${_outPfx}002.log"
        (date +"%Y-%m-%d %H:%M:%S"; netstat -s 2>/dev/null || cat /proc/net/dev 2>/dev/null) >> "${_outPfx}003.log"
        [ ${_i} -lt ${_count} ] && sleep ${_interval}
        [ -n "${_wpid_in_for}" ] && wait ${_wpid_in_for}
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
    # STDOUT / STDERR
    ls -l /proc/${_pid}/fd/{1,2}
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
    detectDirs "${_PID}"

    local _outDir="${_OUT_DIR:-"/tmp"}"
    _OUT_DIR="${_outDir}"
    if [ -z "${_INSTALL_DIR}" ]; then
        echo "Could not find install directory (_INSTALL_DIR)." >&2
        return 1
    fi
    if [ -z "${_WORK_DIR}" ]; then
        echo "Could not find work directory (_WORK_DIR)." >&2
        return 1
    fi
    if [ -z "${_STORE_FILE}" ] && [ -d "${_WORK_DIR%/}" ]; then
        _STORE_FILE="${_INSTALL_DIR%/}/config.yml"  # TODO: for k8s, no DB connection in this file
    fi
    local _misc_start=$(date +%s)
    miscChecks "${_PID}" &> "${_outDir%/}/${_pfx}900.log"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] miscChecks completed ($(( $(date +%s) - ${_misc_start} ))s)" >&2
    # NOTE: same infor as prometheus is in support zip

    if [ -z "${_LOG_FILE}" ]; then
        takeDumps "${_PID}" "${_COUNT}" "${_INTERVAL}" "${_STORE_FILE}" "${_INSTALL_DIR%/}" "${_outDir%/}" "${_pfx}"
        return $?
    fi

    [ ! -f "${_LOG_FILE}" ] && echo "${_LOG_FILE} does not exist" >&2 && return 1
    [ -z "${_REGEX}" ] && echo "'-f' is provided but no '-r'" >&2 && return 1
    echo "Monitoring ${_LOG_FILE} with '${_REGEX}' ..." >&2
    while true; do
        if tail -n0 -F "${_LOG_FILE}" | grep --line-buffered -m1 -E "${_REGEX}"; then
            trap "_stopping" SIGINT
            takeDumps "${_PID}" "${_COUNT}" "${_INTERVAL}" "${_PROP_FILE}" "${_INSTALL_DIR%/}" "${_outDir%/}"
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

    while getopts "c:i:s:p:f:r:o:" opts; do
        case $opts in
            c)
                [ -n "$OPTARG" ] && _COUNT="$OPTARG"
                ;;
            i)
                [ -n "$OPTARG" ] && _INTERVAL="$OPTARG"
                ;;
            s)
                _STORE_FILE="$OPTARG"
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
