#!/usr/bin/env bash
usage() {
    cat <<EOF
USAGE:
    bash <(curl -sfL https://raw.githubusercontent.com/hajimeo/samples/master/bash/monitoring/nrm3-db-test.sh --compressed)

    bash ./nrm3-db-test.sh [-q "query"] [-s /path/to/nexus-store.properties]

    export username="nexus" password="nexus123" jdbcUrl="jdbc:postgresql://localhost:5432/nexus"
    bash ./nrm3-db-test.sh [-q "query"]
EOF
}

: "${_INSTALL_DIR:=""}"
_STORE_FILE=""
_DB_CONN_TEST_FILE="/tmp/DbConnTest.groovy"
_PID=""

function genDbConnTest() {
    local __doc__="Generate a DB connection script file"
    local _dbConnFile="${1:-"${_DB_CONN_TEST_FILE}"}"
    cat <<'EOF' >"${_dbConnFile}"
import org.postgresql.*
import groovy.sql.Sql
import java.time.Duration
import java.time.Instant

def elapse(Instant start, String word) {
    Instant end = Instant.now()
    Duration d = Duration.between(start, end)
    println("# Elapsed ${d}: ${word}")
}

def p = new Properties()
if (args.length > 1 && !args[1].empty) {
    def pf = new File(args[1])
    pf.withInputStream { p.load(it) }
} else {
    p = System.getenv()  //username, password, jdbcUrl
}
def query = (args.length > 0 && !args[0].empty) ? args[0] : "SELECT version()"
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
    if [ ! -s "${_storeProp}" ] && [ -z "${jdbcUrl}" ]; then
        echo "No nexus-store.properties file and no jdbcUrl set." >&2
        return 1
    fi
    if [ ! -s "${_dbConnFile}" ]; then
        genDbConnTest "${_dbConnFile}" || return $?
    fi
    local _java="java"
    [ -d "${JAVA_HOME%/}" ] && _java="${JAVA_HOME%/}/bin/java"
    timeout ${_timeout}s ${_java} -Dgroovy.classpath="$(find "${_installDir%/}/system/org/postgresql/postgresql" -type f -name 'postgresql-42.*.jar' | tail -n1)" -jar "${_installDir%/}/system/org/codehaus/groovy/groovy-all/${_groovyAllVer}/groovy-all-${_groovyAllVer}.jar" \
        "${_dbConnFile}" "${_query}" "${_storeProp}"
}

function setGlobals() { # Best effort. may not return accurate dir path
    local __doc__="Populate PID and directory path global variables etc."
    local _pid="${1:-"${_PID}"}"
    if [ -z "${_pid}" ]; then
        _pid="$(ps auxwww | grep -F 'org.sonatype.nexus.karaf.NexusMain' | grep -vw grep | awk '{print $2}' | tail -n1)"
        _PID="${_pid}"
        [ -z "${_pid}" ] && echo "[WARN] no PID found"
    fi
    if [ ! -d "${_INSTALL_DIR}" ]; then
        if [ -n "${_pid}" ]; then
            _INSTALL_DIR="$(ps wwwp ${_pid} | sed -n -E '/org.sonatype.nexus.karaf.NexusMain/ s/.+-Dexe4j.moduleName=([^ ]+)\/bin\/nexus .+/\1/p' | head -1)"
        fi
        [ -d "${_INSTALL_DIR}" ] || echo "[WARN] no install directory found"
    fi
    if [ ! -s "${_STORE_FILE}" ] && [ -n "${_pid}" ]; then
        if [ -e "/proc/${_pid}/environ" ]; then
            if grep -q 'NEXUS_DATASTORE_NEXUS_' "/proc/${_pid}/environ"; then
                eval "$(cat "/proc/${_pid}/environ" | tr '\0' '\n' | grep -E '^NEXUS_DATASTORE_NEXUS_.+=')"
                export username="${NEXUS_DATASTORE_NEXUS_USERNAME}" password="${NEXUS_DATASTORE_NEXUS_PASSWORD}" jdbcUrl="${NEXUS_DATASTORE_NEXUS_JDBCURL}"
            elif grep -q 'JDBC_URL=' "/proc/${_pid}/environ"; then
                eval "$(cat "/proc/${_pid}/environ" | tr '\0' '\n' | grep -E '^(JDBC_URL|DB_USER|DB_PWD)=')"
                export username="${DB_USER}" password="${DB_PWD}" jdbcUrl="${JDBC_URL}"
            fi
        else
            local _work_dir="$(ps wwwp ${_pid} | sed -n -E '/org.sonatype.nexus.karaf.NexusMain/ s/.+-Dkaraf.data=([^ ]+) .+/\1/p' | head -n1)"
            [[ "${_work_dir}" =~ ^/ ]] || _work_dir="${_INSTALL_DIR%/}/${_work_dir}"
            [ -s "${_work_dir%/}/etc/fabric/nexus-store.properties" ] && grep -q -w jdbcUrl "${_work_dir%/}/etc/fabric/nexus-store.properties" && _STORE_FILE="${_work_dir%/}/etc/fabric/nexus-store.properties"
        fi
    fi
}

main() {
    local query="$1"
    local storeProp="$2"

    setGlobals "${_PID}"
    if [ -z "${_INSTALL_DIR}" ]; then
        # Required to set the classpath
        echo "Could not find install directory." >&2
        return 1
    fi

    runDbQuery "${query}" "${storeProp}"
}

if [ "$0" = "${BASH_SOURCE[0]}" ]; then
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
