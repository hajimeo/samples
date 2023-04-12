#!/usr/bin/env bash
usage() {
    cat << EOS
USAGE:
    bash ./nxrm3-threaddumps.sh [-p /path/to/nexus-store.properties] [-i 5] [-c 10]

    -c  How many dumps (default 5)
    -i  Interval seconds (default 2)
    -p  Path to nexus-store.properties file
EOS
}

: "${_INSTALL_DIR:=""}"
: "${_WORK_DIR:=""}"
_PROP_FILE=""
_INTERVAL=2
_COUNT=5
_DB_CONN_TEST_FILE="/tmp/DbConnTest.groovy"
_GROOVY_ALL_VER="2.4.17"
_PID=""

function genDbConnTest() {
    cat << EOF > "${_DB_CONN_TEST_FILE}"
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
    if [ -z "${_storeProp}" ] && [ -d "${_WORD_DIR%/}" ]; then
        _storeProp="${_WORD_DIR%/}/etc/fabric/nexus-store.properties"
    fi
    if [ ! -s "${_storeProp}" ]; then
        echo "Could not find nexus-store.properties file." >&2
        return 1
    fi
    if [ ! -s "${_DB_CONN_TEST_FILE}" ]; then
        genDbConnTest || return $?
    fi
    java -Dgroovy.classpath="$(find "${_INSTALL_DIR%/}/system/org/postgresql/postgresql" -type f -name 'postgresql-42.*.jar' | tail -n1)" -jar "${_INSTALL_DIR%/}/system/org/codehaus/groovy/groovy-all/${_GROOVY_ALL_VER}/groovy-all-${_GROOVY_ALL_VER}.jar" \
    "${_DB_CONN_TEST_FILE}" "${_storeProp}" "${_query}"
}

function tailStdout() {
    local _pid="$1"
    local _timeout="${2:-"30"}"
    local _installDir="${3-"${_INSTALL_DIR%/}"}"
    if ls -l /proc/${_pid}/fd/1 2>/dev/null | grep -qw pipe; then
        timeout ${_timeout}s cat /proc/${_pid}/fd/1
    elif [ -f /proc/${_pid}/fd/1 ]; then
        timeout ${_timeout}s tail -f /proc/${_pid}/fd/1
    elif [ -n "${_installDir}" ] && [[ "$(ps wwwp ${_pid})" =~ XX:LogFile=([^[:space:]]+) ]]; then
        local jvmLog="${BASH_REMATCH[1]}"
        timeout ${_timeout}s tail -f "${_installDir%/}/${jvmLog#/}"
    else
        echo "No file to tail for ${_pid}" >&2
        return 1
    fi
}

function takeDumps() {
    local _pid=${1:-${_PID}}
    local _count=${2:-${_COUNT:-5}}
    local _interval=${3:-${_INTERVAL:-2}}
    local _storeProp="${4:-"${_PROP_FILE}"}"
    local _outDir="${5:-"/tmp"}"
    local _outPfx="${_outDir%/}/script-$(date +"%Y%m%d%H%M%S")"

    tailStdout "${_pid}" "$(((${_count} + 1) * ${_interval}))" >> "${_outPfx}000.log" &
    local _wpid=$!

    for _i in $(seq 1 ${_count}); do
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] taking dump ${_i}/${_count} ..." >&2
        (date +'%Y-%m-%d %H:%M:%S'; runDbQuery "select * from pg_stat_activity where state <> 'idle' order by query_start limit 10" "${_storeProp}") >> "${_outPfx}101.log" &
        local _wpid2=$!
        # TODO: Does "cat /proc/${_PID}/fd/1" work?
        kill -3 "${_PID}"
        (date +"%Y-%m-%d %H:%M:%S"; top -Hb -n1 | head -n60) >> "${_outPfx}001.log"
        (date +"%Y-%m-%d %H:%M:%S"; netstat -topen 2>/dev/null || cat /proc/net/tcp 2>/dev/null) >> "${_outPfx}002.log"
        [ ${_i} -lt ${_count} ] && sleep ${_interval}
        wait ${_wpid2}
    done
    [ -n "${_wpid}" ] && sleep 1 && kill ${_wpid}
    echo ""
}



main() {
    # Preparing
    detectDirs || return $?
    if [ -z "${_INSTALL_DIR}" ]; then
        echo "Could not find install directory." >&2
        return 1
    fi
    if [ -z "${_WORD_DIR}" ]; then
        echo "Could not find work directory." >&2
        return 1
    fi
    genDbConnTest || return $?

    # TODO: trigger below by keyword from the tailing log
    takeDumps "${_PID}" "${_COUNT}" "${_INTERVAL}" "${_PROP_FILE}" "${_WORD_DIR%/}/log/tasks" || return $?
}

if [ "$0" = "$BASH_SOURCE" ]; then
    #if [ "$#" -eq 0 ]; then
    if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ]; then
        usage
        exit 1
    fi

    while getopts "c:i:p:" opts; do
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
            *)
                echo "$opts $OPTARG is not supported" >&2
                ;;
        esac
    done

    main "$@"
fi
