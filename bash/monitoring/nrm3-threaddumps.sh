#!/usr/bin/env bash
usage() {
    cat << EOF
PURPOSE:
Gather basic information to troubleshoot Java process related *performance* issues.
Tested with Nexus official docker image: https://github.com/sonatype/docker-nexus3
Currently this script gathers the following information:
 - Java thread dumps with kill -3, with netstat (or equivalent) and top
 - If nexus-store.properties is given, pg_stat_activity

EXAMPLES:
    # Taking thread dumps whenever the log line contains "QuartzTaskInfo"
    cd /nexus-data
    curl --compressed -O https://raw.githubusercontent.com/sonatype-nexus-community/nexus-monitoring/main/scripts/nrm3-threaddumps.sh
    bash ./nrm3-threaddumps.sh -s ./etc/fabric/nexus-store.properties -f ./log/nexus.log -r "QuartzTaskInfo"

OPTIONS:
    -c  How many dumps (default 5)
    -i  Interval seconds (default 2)
    -s  Path to nexus-store.properties file (default empty = no DB check)
    -f  File to monitor (-r is required)
    -r  Regex (used in 'grep -E') to monitor -f file
    -p  PID
EOF
}


: "${_INSTALL_DIR:=""}"
: "${_WORK_DIR:=""}"
_INTERVAL=2
_COUNT=5
_STORE_FILE=""
_LOG_FILE=""
_REGEX=""
_DB_CONN_TEST_FILE="/tmp/DbConnTest.groovy"
_PID=""


function genDbConnTest() {
    local __doc__="Generate a DB connection script file"
    local _dbConnFile="${1:-"${_DB_CONN_TEST_FILE}"}"
    cat << 'EOF' > "${_dbConnFile}"
import org.postgresql.*
import groovy.sql.Sql
import java.time.Duration
import java.time.Instant

def elapse(Instant start, String word) {
    Instant end = Instant.now()
    Duration d = Duration.between(start, end)
    println("# '${word}' took ${d}")
}

def p = new Properties()
if (!args) p = System.getenv()  //username, password, jdbcUrl
else {
    def pf = new File(args[0])
    pf.withInputStream { p.load(it) }
}
def query = (args.length > 1 && !args[1].empty) ? args[1] : "SELECT 'ok' as test"
def driver = Class.forName('org.postgresql.Driver').newInstance() as Driver
def dbP = new Properties()
dbP.setProperty("user", p.username)
dbP.setProperty("password", p.password)
def start = Instant.now()
def conn = driver.connect(p.jdbcUrl, dbP)
elapse(start, "connect")
def sql = new Sql(conn)
try {
    def queries = query.split(";")
    queries.each { q ->
        start = Instant.now()
        sql.eachRow(q) { println(it) }
        elapse(start, q)
    }
} finally {
    sql.close()
    conn.close()
}
EOF
}

function detectDirs() {    # Best effort. may not return accurate dir path
    local __doc__="Populate PID and directory path global variables"
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
    local __doc__="Run a query against DB connection specified in the _storeProp"
    local _query="$1"
    local _storeProp="${2:-"${_STORE_FILE}"}"
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
    local _java="java"
    [ -d "${JAVA_HOME%/}" ] && _java="${JAVA_HOME%/}/bin/java"
    timeout ${_timeout}s ${_java} -Dgroovy.classpath="$(find "${_installDir%/}/system/org/postgresql/postgresql" -type f -name 'postgresql-42.*.jar' | tail -n1)" -jar "${_installDir%/}/system/org/codehaus/groovy/groovy-all/${_groovyAllVer}/groovy-all-${_groovyAllVer}.jar" \
    "${_dbConnFile}" "${_storeProp}" "${_query}"
}

function tailStdout() {
    local __doc__="Tail stdout file or XX:LogFile file"
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

    tailStdout "${_pid}" "$((${_count} * ${_interval} + 2))" "${_outPfx}000.log" "${_installDir}" &
    local _wpid0="$!"
    echo "${_wpid0}" > /tmp/.tailStdout.run
    sleep 0.5
    for _i in $(seq 1 ${_count}); do
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] taking dump ${_i}/${_count} ..." >&2
        local _wpid=""
        if [ -s "${_storeProp}" ]; then
            (date +'%Y-%m-%d %H:%M:%S'; runDbQuery "select * from pg_stat_activity where state <> 'idle' and query not like '% pg_stat_activity %' order by query_start limit 100;select relation::regclass, * from pg_locks where relation::regclass::text != 'pg_locks' limit 100;" "${_storeProp}" "${_interval}") >> "${_outPfx}101.log" &
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
        if ! ps -p "$(cat /tmp/.tailStdout.run)" &>/dev/null ; then
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
    genDbConnTest || return $?
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] miscChecks() started." >&2
    miscChecks "${_PID}" &> "${_WORD_DIR%/}/log/tasks/script-$(date +"%Y%m%d%H%M%S")900.log"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] miscChecks() completed." >&2
    # NOTE: same infor as prometheus is in support zip

    if [ -z "${_LOG_FILE}" ]; then
        takeDumps "${_PID}" "${_COUNT}" "${_INTERVAL}" "${_STORE_FILE}" "${_INSTALL_DIR%/}" "${_WORD_DIR%/}/log/tasks"
        return $?
    fi

    [ ! -f "${_LOG_FILE}" ] && echo "${_LOG_FILE} does not exist" >&2 && return 1
    [ -z "${_REGEX}" ] && echo "'-f' is provided but no '-r'" >&2 && return 1
    echo "Monitoring ${_LOG_FILE} with '${_REGEX}' ..." >&2
    while true; do
        if tail -n0 -F "${_LOG_FILE}" | grep --line-buffered -m1 -E "${_REGEX}"; then
            trap "_stopping" SIGINT
            takeDumps "${_PID}" "${_COUNT}" "${_INTERVAL}" "${_PROP_FILE}" "${_INSTALL_DIR%/}" "${_WORD_DIR%/}/log/tasks"
            sleep 1
        fi
    done
}

if [ "$0" = "${BASH_SOURCE[0]}" ]; then
    #if [ "$#" -eq 0 ]; then
    if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ]; then
        usage
        exit 1
    fi

    while getopts "c:i:s:p:f:r:" opts; do
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
                _PID="$OPTARG"
                ;;
            *)
                echo "$opts $OPTARG is not supported. Ignored." >&2
                ;;
        esac
    done

    main #"$@"
fi
