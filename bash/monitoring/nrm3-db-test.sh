#!/usr/bin/env bash
usage() {
    cat <<EOF
USAGE:
    bash <(curl -sfL https://raw.githubusercontent.com/sonatype-nexus-community/nexus-monitoring/main/scripts/nrm3-db-test.sh --compressed)
# Or
    curl -O -sfL https://raw.githubusercontent.com/sonatype-nexus-community/nexus-monitoring/main/scripts/nrm3-db-test.sh --compressed
    bash ./nrm3-db-test.sh [-i <installDir>] [-s /path/to/nexus-store.properties] [-q "query"]

# If no 'nexus-store.properties', use 'export:
    export username="nxrm" password="nxrm123" jdbcUrl="jdbc:postgresql://localhost:5432/nxrm"
    bash ./nrm3-db-test.sh [-q "query"]

# If Nexus is not running, specify '-i <installDir>' (and '-s' or 'export' for DB connection):
    bash ./nrm3-db-test.sh -i ./nexus-3.62.0-01/ -s ./sonatype-work/nexus3/etc/fabric/nexus-store.properties
EOF
}

: "${_INSTALL_DIR:=""}"
_STORE_FILE=""
_DB_CONN_TEST_FILE="/tmp/DbConnTest.groovy"
_PID=""
_GROOVY_CLASSPATH=""
# Also username, password, jdbcUrl

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
    System.err.println("# Elapsed ${d}${word.take(200)}")
}

def p = new Properties()
if (args.length > 1 && !args[1].empty) {
    def pf = new File(args[1])
    pf.withInputStream { p.load(it) }
} else {
    p = System.getenv()  //username, password, jdbcUrl
}
def query = (args.length > 0 && !args[0].empty) ? args[0] : "SELECT 'ok' as test"
def driver = Class.forName('org.postgresql.Driver').newInstance() as Driver
def dbP = new Properties()
dbP.setProperty("user", p.username)
dbP.setProperty("password", p.password)
def start = Instant.now()
def conn = driver.connect(p.jdbcUrl, dbP)
elapse(start, " - connect")
def sql = new Sql(conn)
try {
    def queries = query.split(";")
    queries.each { q ->
        q = q.trim()
        System.err.println("# Querying: ${q.take(100)} ...")
        start = Instant.now()
        sql.eachRow(q) { println(it) }
        elapse(start, "")
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
    local _groovyAllVer=""
    local _groovy_jar="${_installDir%/}/system/org/codehaus/groovy/groovy-all/2.4.17/groovy-all-2.4.17.jar"
    if [ ! -s "${_installDir%/}/system/org/codehaus/groovy/groovy-all/${_groovyAllVer}/groovy-all-${_groovyAllVer}.jar" ]; then
        _groovy_jar="$(find "${_installDir%/}/system/org/codehaus/groovy/groovy" -type f -name 'groovy-3.*.jar' 2>/dev/null | head -n1)"
    fi
    if [ ! -s "${_storeProp}" ] && [ -z "${jdbcUrl}" ]; then
        echo "ERROR:No nexus-store.properties file and no jdbcUrl set." >&2
        return 1
    fi
    if [ ! -s "${_dbConnFile}" ]; then
        genDbConnTest "${_dbConnFile}" || return $?
    fi
    local _java="java"
    [ -d "${JAVA_HOME%/}" ] && _java="${JAVA_HOME%/}/bin/java"
    if [ -z "${_GROOVY_CLASSPATH}" ]; then
        local _pgJar="$(find "${_installDir%/}/system/org/postgresql/postgresql" -type f -name 'postgresql-*.jar' 2>/dev/null | tail -n1)"
        local _groovySqlJar="$(find "${_installDir%/}/system/org/codehaus/groovy/groovy-sql" -type f -name 'groovy-sql-*.jar' 2>/dev/null | tail -n1)"
        _GROOVY_CLASSPATH="${_pgJar}"
        [ -n "${_groovySqlJar}" ] && _GROOVY_CLASSPATH="${_GROOVY_CLASSPATH}:${_groovySqlJar}"
    fi
    timeout ${_timeout}s ${_java} -Dgroovy.classpath="${_GROOVY_CLASSPATH}" -jar "${_groovy_jar}" \
        "${_dbConnFile}" "${_query}" "${_storeProp}"
}

function setGlobals() { # Best effort. may not return accurate dir path
    local __doc__="Populate PID and directory path global variables etc."
    local _pid="${1:-"${_PID}"}"
    if [ -z "${_pid}" ]; then
        _pid="$(ps auxwww | grep -F 'org.sonatype.nexus.karaf.NexusMain' | grep -vw grep | awk '{print $2}' | tail -n1)"
        _PID="${_pid}"
        [ -z "${_pid}" ] && echo "INFO: no PID found" >&2
    fi
    if [ ! -d "${_INSTALL_DIR}" ]; then
        if [ -n "${_pid}" ]; then
            _INSTALL_DIR="$(ps wwwp ${_pid} | sed -n -E '/org.sonatype.nexus.karaf.NexusMain/ s/.+-Dexe4j.moduleName=([^ ]+)\/bin\/nexus .+/\1/p' | head -1)"
        fi
        [ -d "${_INSTALL_DIR}" ] || echo "WARN: no _INSTALL_DIR found" >&2
    fi
    if [ ! -s "${_STORE_FILE}" ] && [ -z "${jdbcUrl}" ] && [ -n "${_pid}" ]; then
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

# Query example. Start this after 'setGlobals ${_PID}', also better redirect STDERR
function searchBlobId() {
    local _blobId="$1"
    [ -z "${_blobId}" ] && return 1
    runDbQuery "SELECT distinct REGEXP_REPLACE(recipe_name, '-.+', '') AS fmt FROM repository" 2>/dev/null | while read -r _fmt; do
        if [[ "${_fmt}" =~ \[fmt:([^\]]+)\] ]]; then
            local _format="${BASH_REMATCH[1]}"
            echo "SELECT '${_format}' as format, r.name as repo_name, ab.asset_blob_id, ab.blob_ref, ab.blob_size, a.path, a.kind FROM ${_format}_asset_blob ab INNER JOIN ${_format}_asset a USING (asset_blob_id) INNER JOIN ${_format}_content_repository cr USING (repository_id) INNER JOIN repository r on cr.config_repository_id = r.id WHERE ab.blob_ref like '%${_blobId}';"
        fi
    done >/tmp/.queries.sql
    if [ -s /tmp/.queries.sql ]; then
        echo "# format, repo_name, asset_blob_id, blob_ref, blob_size, path, kind"
        query="$(cat /tmp/.queries.sql)"
    fi
    if [ -n "${query%;}" ]; then
        runDbQuery "${query%;}"
    fi
}

main() {
    local query="$1"

    setGlobals "${_PID}"
    if [ -z "${_INSTALL_DIR}" ]; then
        # Required to set the classpath
        echo "Could not find install directory." >&2
        return 1
    fi

    if [ -z "${query}" ]; then
        runDbQuery "SELECT version()"
        # check the estimate count and size
        runDbQuery "SELECT distinct REGEXP_REPLACE(recipe_name, '-.+', '') AS fmt FROM repository" 2>/dev/null | while read -r _fmt; do
            if [[ "${_fmt}" =~ \[fmt:([^\]]+)\] ]]; then
                local _format="${BASH_REMATCH[1]}"
                echo "SELECT '${_format}' as format, r.name as repo_name, count(*) as count, SUM(ab.blob_size) as bytes FROM ${_format}_asset_blob ab INNER JOIN ${_format}_asset a USING (asset_blob_id) INNER JOIN ${_format}_content_repository cr USING (repository_id) INNER JOIN repository r on cr.config_repository_id = r.id GROUP BY 1, 2 UNION ALL SELECT '${_format}' as format, '(soft-deleting)' as repo_name, count(*) as count, SUM(ab.blob_size) as bytes FROM ${_format}_asset_blob ab LEFT JOIN ${_format}_asset a USING (asset_blob_id) WHERE a.asset_blob_id IS NULL GROUP BY 1, 2;"
            fi
        done >/tmp/.queries.sql
        if [ -s /tmp/.queries.sql ]; then
            echo "# format, repo_name, count, bytes"
            query="$(cat /tmp/.queries.sql)"
        fi
    fi
    if [ -n "${query%;}" ]; then
        runDbQuery "${query%;}"
    fi
}

if [ "$0" = "${BASH_SOURCE[0]}" ]; then
    #if [ "$#" -eq 0 ]; then
    if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ]; then
        usage
        exit 0
    fi
    while getopts "i:q:s:" opts; do
        case $opts in
        i)
            _INSTALL_DIR="$OPTARG"
            ;;
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

    main "${_QUERY}" #"$@"
fi
