#!/usr/bin/env bash
usage() {
    cat << EOS
Taking Java thread dumps with some OS / database stats.
Designed for Nexus official docker image: https://github.com/sonatype/docker-nexus3

USAGE:
    bash ./nxrm3-threaddumps.sh [-p /path/to/nexus-store.properties] [-i 5] [-c 10]

    -c  How many dumps (default 5)
    -i  Interval seconds (default 2)
    -p  Path to nexus-store.properties file
    -f  File to monitor (-r is required)
    -r  Regex (used in 'grep -E') to monitor -f file
EOS
}


: "${_INSTALL_DIR:=""}"
: "${_WORK_DIR:=""}"
_INTERVAL=2
_COUNT=5
_PROP_FILE=""
_LOG_FILE=""
_REGEX=""
_DB_CONN_TEST_FILE="/tmp/DbConnTest.groovy"
_PID=""


function genDbConnTest() {
    local _dbConnFile="${1:-"${_DB_CONN_TEST_FILE}"}"
    cat << EOF > "${_dbConnFile}"
import org.postgresql.*
import groovy.sql.Sql
def p = new Properties()
if (!args) p = System.getenv()
else {
   def pf = new File(args[0])
   pf.withInputStream { p.load(it) }
}
def _query = (args.length > 1 && args[1]) ? args[1] : "SELECT 'ok' as test"
def driver = Class.forName('org.postgresql.Driver').newInstance() as Driver
def dbP = new Properties()
dbP.setProperty("user", p.username)
dbP.setProperty("password", p.password)
def conn = driver.connect(p.jdbcUrl, dbP)
def sql = new Sql(conn)
try {
   sql.eachRow(_query) {println(it)}
} finally {
   sql.close()
   conn.close()
}
EOF
}

function detectDirs() {    # Best effort. may not return accurate dir path
    local _pid="${1:-"${_PID}"}"
    if [ -z "${_pid}" ]; then
        _pid="$(ps auxwww | grep -F 'org.sonatype.nexus.karaf.NexusMain' | grep -vw grep | awk '{print $2}' | tail -n1)"
        _PID="${_pid}"
        [ -z "${_pid}" ] && return 1
    fi
    if [ ! -d "${_INSTALL_DIR}" ]; then
        _INSTALL_DIR="$(ps wwwp ${_pid} | sed -n -E '/org.sonatype.nexus.karaf.NexusMain/ s/.+-Dexe4j.moduleName=([^ ]+)\/bin\/nexus .+/\1/p' | head -1)"
    fi
    if [ ! -d "${_WORD_DIR}" ] && [ -d "${_INSTALL_DIR%/}" ]; then
        local _karafData="$(ps wwwp ${_pid} | sed -n -E '/org.sonatype.nexus.karaf.NexusMain/ s/.+-Dkaraf.data=([^ ]+) .+/\1/p' | head -n1)"
        _WORD_DIR="${_INSTALL_DIR%/}/${_karafData#/}"
    fi
}

function runDbQuery() {
    local _query="$1"
    local _storeProp="${2:-"${_PROP_FILE}"}"
    local _timeout="${3:-"30"}"
    local _dbConnFile="${4:-"${_DB_CONN_TEST_FILE}"}"
    local _installDir="${5:-"${_INSTALL_DIR}"}"
    local _groovyAllVer="2.4.17"
    if [ ! -s "${_storeProp}" ]; then
        echo "No nexus-store.properties file." >&2
        return 1
    fi
    if [ ! -s "${_dbConnFile}" ]; then
        genDbConnTest "${_dbConnFile}" || return $?
    fi
    timeout ${_timeout}s java -Dgroovy.classpath="$(find "${_installDir%/}/system/org/postgresql/postgresql" -type f -name 'postgresql-42.*.jar' | tail -n1)" -jar "${_installDir%/}/system/org/codehaus/groovy/groovy-all/${_groovyAllVer}/groovy-all-${_groovyAllVer}.jar" \
    "${_dbConnFile}" "${_storeProp}" "${_query}"
}

function tailStdout() {
    local _pid="$1"
    local _timeout="${2:-"30"}"
    local _outputFile="${3}"
    local _installDir="${4-"${_INSTALL_DIR%/}"}"
    local _cmd=""
    #if ls -l /proc/${_pid}/fd/1 2>/dev/null | grep -qw pipe; then
    #    _cmd="cat /proc/${_pid}/fd/1"
    if [ -f /proc/${_pid}/fd/1 ]; then
        _cmd="tail -n0 -f /proc/${_pid}/fd/1"
    elif [ -n "${_installDir}" ] && [[ "$(ps wwwp ${_pid})" =~ XX:LogFile=([^[:space:]]+) ]]; then
        local jvmLog="${BASH_REMATCH[1]}"
        _cmd="tail -n0 -f "${_installDir%/}/${jvmLog#/}""
    fi
    if [ -z "${_cmd}" ]; then
        echo "No file to tail for pid:${_pid}" >&2
        return 1
    fi
    if [ -n "${_outputFile}" ]; then
        _cmd="${_cmd} >> ${_outputFile}"
    fi
    eval "timeout ${_timeout}s ${_cmd}"
}

function takeDumps() {
    local _pid=${1:-${_PID}}
    local _count=${2:-${_COUNT:-5}}
    local _interval=${3:-${_INTERVAL:-2}}
    local _storeProp="${4:-"${_PROP_FILE}"}"
    local _outDir="${5:-"/tmp"}"
    local _outPfx="${_outDir%/}/script-$(date +"%Y%m%d%H%M%S")"

    tailStdout "${_pid}" "$(((${_count} + 1) * ${_interval}))" "${_outPfx}000.log" &
    sleep 1

    for _i in $(seq 1 ${_count}); do
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] taking dump ${_i}/${_count} ..." >&2
        (date +'%Y-%m-%d %H:%M:%S'; runDbQuery "select * from pg_stat_activity where state <> 'idle' and query not like '% pg_stat_activity %' order by query_start limit 100" "${_storeProp}" "${_interval}") >> "${_outPfx}101.log" &
        kill -3 "${_PID}"
        (date +"%Y-%m-%d %H:%M:%S"; top -H -b -n1 2>/dev/null | head -n60) >> "${_outPfx}001.log"
        (date +"%Y-%m-%d %H:%M:%S"; netstat -topen 2>/dev/null || cat /proc/net/tcp 2>/dev/null) >> "${_outPfx}002.log"
        [ ${_i} -lt ${_count} ] && sleep ${_interval}
    done
    echo ""
    wait
}


main() {
    # Preparing
    detectDirs
    if [ -z "${_INSTALL_DIR}" ]; then
        echo "Could not find install directory." >&2
        return 1
    fi
    if [ -z "${_WORD_DIR}" ]; then
        echo "Could not find work directory." >&2
        return 1
    fi
    if [ -z "${_PROP_FILE}" ] && [ -d "${_WORD_DIR%/}" ]; then
        _PROP_FILE="${_WORD_DIR%/}/etc/fabric/nexus-store.properties"
    fi
    genDbConnTest || return $?

    if [ -n "${_LOG_FILE}" ]; then
        [ ! -f "${_LOG_FILE}" ] && echo "${_LOG_FILE} does not exist" >&2 && return 1
        [ -z "${_REGEX}" ] && echo "'-f' is provided but no '-r'" >&2 && return 1
        local _wpid=""
        tail -n0 -F "${_LOG_FILE}" | while read -r _l; do
            if [ -n "${_wpid}" ] && jobs -l | grep -qw "${_wpid}"; then
                continue
            fi
            if echo "${_l}" | grep -E "${_REGEX}"; then
                takeDumps "${_PID}" "${_COUNT}" "${_INTERVAL}" "${_PROP_FILE}" "${_WORD_DIR%/}/log/tasks" &
                _wpid=$!
                sleep 1
            fi
        done
        wait
    else
        takeDumps "${_PID}" "${_COUNT}" "${_INTERVAL}" "${_PROP_FILE}" "${_WORD_DIR%/}/log/tasks" || return $?
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    #if [ "$#" -eq 0 ]; then
    if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ]; then
        usage
        exit 1
    fi

    while getopts "c:i:p:f:r:" opts; do
        case $opts in
            c)
                _COUNT="$OPTARG"
                ;;
            i)
                _INTERVAL="$OPTARG"
                ;;
            p)
                _PROP_FILE="$OPTARG"
                ;;
            f)
                _LOG_FILE="$OPTARG"
                ;;
            r)
                _REGEX="$OPTARG"
                ;;
            *)
                echo "$opts $OPTARG is not supported" >&2
                ;;
        esac
    done

    main "$@"
fi
