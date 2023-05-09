#!/usr/bin/env bash
usage() {
    cat << EOF
bash <(curl -sfL https://raw.githubusercontent.com/sonatype-nexus-community/nexus-monitoring/main/scripts/iq-threaddumps.sh --compressed)

PURPOSE:
Gather basic information to troubleshoot Java process related *performance* issues.
Designed for Nexus official docker image: https://github.com/sonatype/docker-nexus-iq-server
Currently this script gathers the following information:
 - Java thread dumps with kill -3, with netstat (or equivalent) and top
 - If config.yml is given, does extra test via admin-port (localhost:8071)

EXAMPLE:
    # Taking thread dumps whenever the log line contains "QuartzJobStoreTX"
    cd /sonatype-work;  # or cd /sonatype-work/clm-cluster;
    curl --compressed -O -L https://raw.githubusercontent.com/sonatype-nexus-community/nexus-monitoring/main/scripts/iq-threaddumps.sh;
    bash ./iq-threaddumps.sh -f /var/log/nexus-iq-server/clm-server.log -r "QuartzJobStoreTX";

USAGE:
    -c  How many dumps (default 5)
    -i  Interval seconds (default 2)
    -s  Path to config.yml file (default /etc/nexus-iq-server/config.yml)
    -f  File to monitor (-r is required)
    -r  Regex (used in 'grep -E') to monitor -f file
    -p  PID
    -o  Output directory (default /tmp)
EOF
}


: "${_INSTALL_DIR:=""}"
: "${_WORK_DIR:=""}"
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
        _pid="$(ps auxwww | grep -E 'nexus-iq-server-.+\.jar server' | grep -vw grep | awk '{print $2}' | tail -n1)"
        _PID="${_pid}"
        [ -z "${_pid}" ] && return 1
    fi
    if [ ! -d "${_INSTALL_DIR}" ]; then
        _INSTALL_DIR="$(readlink -f /proc/${_pid}/cwd 2>/dev/null)"
        if [ -z "${_INSTALL_DIR}" ]; then
            local _jarpath="$(ps wwwp ${_pid} 2>/dev/null | grep -m1 -E -o '[^ ]+/nexus-iq-server-.+\.jar')"
            _INSTALL_DIR="$(dirname "${_jarpath}")"
        fi
        [ -d "${_INSTALL_DIR}" ] || return 1
    fi
    if [ ! -d "${_WORD_DIR}" ] && [ -d "${_INSTALL_DIR%/}" ]; then
        local _config
        if [ -s "${_STORE_FILE}" ]; then
            _config="${_STORE_FILE}"
        else
            _config="$(ps wwwp ${_pid} | sed -n -E '/nexus-iq-server/ s/.+\.jar server ([^ ]+).*/\1/p' | head -n1)"
            [[ ! "${_config}" =~ ^/ ]] && _config="${_INSTALL_DIR%/}/${_config}"
        fi
        [ -z "${_config}" ] && return 1
        #_STORE_FILE="$(readlink -f "${_config}")"
        _WORD_DIR="$(sed -n -E 's/sonatypeWork[[:space:]]*:[[:space:]]*(.+)/\1/p' "${_config}")"
        [[ ! "${_WORD_DIR}" =~ ^/ ]] && _WORD_DIR="${_INSTALL_DIR%/}/${_WORD_DIR}"
        [ -d "${_WORD_DIR}" ] || return 1
    fi
}

function tailStdout() {
    local __doc__="Tail stdout file or XX:LogFile file"
    local _pid="$1"
    local _timeout="${2:-"30"}"
    local _outputFile="${3}"
    local _installDir="${4-"${_INSTALL_DIR%/}"}"
    local _cmd=""
    if [ -f /proc/${_pid}/fd/1 ]; then
        _cmd="tail -n0 -f /proc/${_pid}/fd/1"
    elif [ -n "${_installDir}" ] && [[ "$(ps wwwp ${_pid})" =~ XX:LogFile=([^[:space:]]+) ]]; then
        local jvmLog="${BASH_REMATCH[1]}"
        _cmd="tail -n0 -f "${_installDir%/}/${jvmLog#/}""
    elif readlink -f /proc/${_pid}/fd/1 2>/dev/null | grep -q '/pipe:'; then
        _cmd="cat /proc/${_pid}/fd/1"
    fi
    if [ -z "${_cmd}" ]; then
        echo "No file to tail for pid:${_pid}" >&2
        return 1
    fi
    echo "timeout ${_timeout}s ${_cmd}" > /tmp/.tailStdout.cmd
    if [ -n "${_outputFile}" ]; then
        _cmd="${_cmd} >> ${_outputFile}"
    fi
    eval "timeout ${_timeout}s ${_cmd}"
}

function takeDumps() {
    local __doc__="Take multiple thread dumps for _pid"
    local _pid=${1:-${_PID}}
    local _count=${2:-${_COUNT:-5}}
    local _interval=${3:-${_INTERVAL:-2}}
    local _storeProp="${4:-"${_STORE_FILE}"}"
    local _installDir="${5-"${_INSTALL_DIR%/}"}"
    local _outDir="${6:-"/tmp"}"
    local _outPfx="${_outDir%/}/script-$(date +"%Y%m%d%H%M%S")"

    tailStdout "${_pid}" "$((${_count} * ${_interval} + 4))" "${_outPfx}000.log" "${_installDir}" &
    local _wpid0="$!"
    echo "${_wpid0}" > /tmp/.tailStdout.run
    sleep 1
    for _i in $(seq 1 ${_count}); do
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] taking dump ${_i}/${_count} ..." >&2
        local _wpid=""
        if [ -s "${_storeProp}" ]; then
            # TODO: If _storeProp is given, do extra check for IQ
            _wpid="$!"
        fi
        kill -3 "${_pid}"
        (date +"%Y-%m-%d %H:%M:%S"; top -H -b -n1 2>/dev/null | head -n60) >> "${_outPfx}001.log"
        (date +"%Y-%m-%d %H:%M:%S"; netstat -topen 2>/dev/null || cat /proc/net/tcp 2>/dev/null) >> "${_outPfx}002.log"
        (date +"%Y-%m-%d %H:%M:%S"; netstat -s 2>/dev/null || cat /proc/net/dev 2>/dev/null) >> "${_outPfx}003.log"
        [ ${_i} -lt ${_count} ] && sleep ${_interval}
        [ -n "${_wpid}" ] && wait ${_wpid}
    done
    ps -p ${_wpid0} &>/dev/null && wait ${_wpid0}
    return 0
}

# miscChecks &> "${_outFile}"
function miscChecks() {
    local __doc__="Gather Misc. information"
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
        ls -li /proc/${_pid}/fd/*
        pmap -x ${_pid}
    fi
    set +x
}

function _stopping() {
    echo -n -e "\nStopping "
    local _pid="$(cat /tmp/.tailStdout.run 2>/dev/null)"
    [ -z "${_pid}" ] && return
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
    detectDirs "${_PID}"
    local _start=$(date +%s)
    local _outDir="${_OUT_DIR:-"/tmp"}"
    _OUT_DIR="${_outDir}"
    if [ -z "${_INSTALL_DIR}" ]; then
        echo "Could not find install directory." >&2
        return 1
    fi
    if [ -z "${_WORD_DIR}" ]; then
        echo "Could not find work directory." >&2
        return 1
    fi
    if [ -z "${_STORE_FILE}" ] && [ -d "${_WORD_DIR%/}" ]; then
        _STORE_FILE="${_WORD_DIR%/}/etc/fabric/nexus-store.properties"
    fi
    miscChecks "${_PID}" &> "${_outDir%/}/script-$(date +"%Y%m%d%H%M%S")900.log"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] miscChecks completed ($(( $(date +%s) - ${_start}))s)" >&2
    # NOTE: same infor as prometheus is in support zip

    if [ -z "${_LOG_FILE}" ]; then
        takeDumps "${_PID}" "${_COUNT}" "${_INTERVAL}" "${_STORE_FILE}" "${_INSTALL_DIR%/}" "${_outDir%/}"
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

    main #"$@"
    echo "Completed (${_OUT_DIR%/})"
fi
