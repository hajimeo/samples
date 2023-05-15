#!/usr/bin/env bash
usage() {
    cat << EOF
USAGE:
    bash <(curl -sfL https://raw.githubusercontent.com/hajimeo/samples/master/bash/monitoring/nrm3-db-test.sh --compressed) -q "query"

    bash ./nrm3-db-test.sh [-q "query"] [-s /path/to/nexus-store.properties]
EOF
}

: "${_INSTALL_DIR:=""}"
: "${_WORK_DIR:=""}"
_STORE_FILE=""
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
        [ -d "${_INSTALL_DIR}" ] || return 1
    fi
    if [ ! -d "${_WORD_DIR}" ] && [ -d "${_INSTALL_DIR%/}" ]; then
        _WORD_DIR="$(ps wwwp ${_pid} | sed -n -E '/org.sonatype.nexus.karaf.NexusMain/ s/.+-Dkaraf.data=([^ ]+) .+/\1/p' | head -n1)"
        [[ ! "${_WORD_DIR}" =~ ^/ ]] && _WORD_DIR="${_INSTALL_DIR%/}/${_WORD_DIR}"
        [ -d "${_WORD_DIR}" ] || return 1
    fi
}

main() {
    local query="$1"
    local storeProp="$2"
    detectDirs "${_PID}"
    if [ -z "${_INSTALL_DIR}" ]; then
        echo "Could not find install directory." >&2
        return 1
    fi
    if [ -z "${_WORD_DIR}" ]; then
        echo "Could not find work directory." >&2
        return 1
    fi
    if [ -z "${storeProp}" ] && [ -d "${_WORD_DIR%/}" ]; then
        storeProp="${_WORD_DIR%/}/etc/fabric/nexus-store.properties"
    fi

    runDbQuery "${query}" "${storeProp}"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    #if [ "$#" -eq 0 ]; then
    if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ]; then
        usage
        exit 0
    fi
    while getopts "s:q:" opts; do
        case $opts in
            q)
                _QUERY="$OPTARG"
                ;;
            s)
                _STORE_FILE="$OPTARG"
                ;;
            *)
                echo "$opts $OPTARG is not supported. Ignored." >&2
                ;;
        esac
    done

    main "${_QUERY}" "${_STORE_FILE}" #"$@"
fi
