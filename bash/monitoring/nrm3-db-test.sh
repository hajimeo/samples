#!/usr/bin/env bash
usage() {
    cat <<EOF
USAGE:
    bash <(curl -sfL https://raw.githubusercontent.com/sonatype-nexus-community/nexus-monitoring/main/scripts/nrm3-db-test.sh --compressed)
# Or
    curl -O -sfL https://raw.githubusercontent.com/sonatype-nexus-community/nexus-monitoring/main/scripts/nrm3-db-test.sh --compressed
    bash ./nrm3-db-test.sh [-i <installDir>] [-s /path/to/nexus-store.properties] [-q "query"]

# Count & Size per Repository (format, repo_name, count, bytes)
    bash ./nrm3-db-test.sh 2>./elapsed.out | tee ./repo_count_size.out

# If no 'nexus-store.properties', use 'export:
    export username="nxrm" password="nxrm123" jdbcUrl="jdbc:postgresql://localhost:5432/nxrm"
    bash ./nrm3-db-test.sh [-q "query"]

# If Nexus is not running, specify '-i <installDir>' (and '-s' or 'export' for DB connection):
    bash ./nrm3-db-test.sh -i ./nexus-3.62.0-01/ -s ./sonatype-work/nexus3/etc/fabric/nexus-store.properties
EOF
}

: "${_INSTALL_DIR:=""}"
: "${_WORK_DIR:=""}"
: "${_LIB_EXTRACT_DIR:=""}"
: "${_TMP:="/tmp"}"     # in case /tmp is read-only
_STORE_FILE=""
_DB_CONN_TEST_FILE=""
_PID=""
_GROOVY_CLASSPATH=""
_GROOVY_JAR=""
# Also username, password, jdbcUrl

function genDbConnTest() {
    local __doc__="Generate a DB connection script file"
    local _dbConnFile="${1:-"${_DB_CONN_TEST_FILE:-"${_WORK_DIR%/}/tmp/DbConnTest.groovy"}"}"
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

function prepareLibs() {
    local __doc__="Prepare the library jars for groovy"
    local _installDir="${1:-"${_INSTALL_DIR}"}"
    local _workDir="${2:-"${_WORK_DIR}"}"
    local _lib_extract_dir="${3:-"${_LIB_EXTRACT_DIR:-"${_workDir%/}/tmp/lib"}"}"

    if [ -n "${_GROOVY_JAR}" ] && [ -n "${_GROOVY_CLASSPATH}" ]; then
        echo "INFO: Using ${_GROOVY_JAR} and ${_GROOVY_CLASSPATH}" >&2
        return 0
    fi
    if [ -z "${_installDir}" ]; then
        echo "ERROR: No _installDir (_workDir is optional)" >&2
        return 1
    fi

    # For older versions
    local _groovy_jar="${_installDir%/}/system/org/codehaus/groovy/groovy-all/2.4.17/groovy-all-2.4.17.jar"
    local _pgJar=""
    local _h2Jar=""
    local _groovySqlJar=""
    # For "around" 3.68+
    if [ ! -s "${_groovy_jar}" ]; then
        _groovy_jar="$(find "${_installDir%/}/system/org/codehaus/groovy/groovy" -type f -name 'groovy-3.*.jar' 2>/dev/null | head -n1)"
        if [ -s "${_groovy_jar}" ]; then
            _pgJar="$(find "${_installDir%/}/system/org/postgresql/postgresql" -type f -name 'postgresql-*.jar' 2>/dev/null | tail -n1)"
            _h2Jar="$(find "${_installDir%/}/system/com/h2database/h2" -type f -name 'h2-*.jar' 2>/dev/null | tail -n1)"
            _groovySqlJar="$(find "${_installDir%/}/system/org/codehaus/groovy/groovy-sql" -type f -name 'groovy-sql-3.*.jar' 2>/dev/null | tail -n1)"
        fi
    fi
    # For 3.78+
    if [ ! -s "${_groovy_jar}" ]; then
        local _single_jar="$(find "${_installDir%/}/bin" -type f -name 'sonatype-nexus-repository-3.*.jar' 2>/dev/null | head -n1)"
        if [ ! -s "${_single_jar}" ]; then
            echo "ERROR: No single jar file found under ${_installDir%/}/bin." >&2
            return 1
        fi
        if ! type unzip >/dev/null 2>&1; then
            echo "ERROR: unzip not found, please install it." >&2
            return 1
        fi
        local _tmp_list="$(unzip -l "${_single_jar}" | grep -E 'BOOT-INF/lib/(groovy|postgresql|h2)-.+\.jar')"
        local _groovy_ver="$(echo "${_tmp_list}" | sed -n -E 's/.+ BOOT-INF\/lib\/groovy-(3\..+)\.jar/\1/p')"
        if [ -z "${_groovy_ver}" ]; then
            echo "ERROR: No groovy version detected from ${_single_jar}" >&2
            return 1
        fi
        if [ ! -s "${_lib_extract_dir%/}/BOOT-INF/lib/groovy-${_groovy_ver}.jar" ]; then
            local _postgres_ver="$(echo "${_tmp_list}" | sed -n -E 's/.+ BOOT-INF\/lib\/postgresql-(.+)\.jar/\1/p')"
            local _h2_ver="$(echo "${_tmp_list}" | sed -n -E 's/.+ BOOT-INF\/lib\/h2-(.+)\.jar/\1/p')"

            if [ ! -d "${_lib_extract_dir%/}" ]; then
                mkdir -v -p "${_lib_extract_dir%/}" || return $?
            fi
            if [ ! -s "${_lib_extract_dir%/}/BOOT-INF/lib/groovy-${_groovy_ver}.jar" ]; then
                unzip -q -d "${_lib_extract_dir%/}" "${_single_jar}" "BOOT-INF/lib/groovy-${_groovy_ver}.jar"
                unzip -q -d "${_lib_extract_dir%/}" "${_single_jar}" "BOOT-INF/lib/groovy-sql-${_groovy_ver}.jar"
                unzip -q -d "${_lib_extract_dir%/}" "${_single_jar}" "BOOT-INF/lib/postgresql-${_postgres_ver}.jar"
                unzip -q -d "${_lib_extract_dir%/}" "${_single_jar}" "BOOT-INF/lib/h2-${_h2_ver}.jar"
            fi
            if [ ! -s "${_lib_extract_dir%/}/BOOT-INF/lib/groovy-${_groovy_ver}.jar" ]; then
                echo "ERROR: Failed to unzip libs from ${_single_jar}." >&2
                return 1
            fi
            _groovy_jar="${_lib_extract_dir%/}/BOOT-INF/lib/groovy-${_groovy_ver}.jar"
            _groovySqlJar="${_lib_extract_dir%/}/BOOT-INF/lib/groovy-sql-${_groovy_ver}.jar"
            _pgJar="${_lib_extract_dir%/}/BOOT-INF/lib/postgresql-${_postgres_ver}.jar"
            _h2Jar="${_lib_extract_dir%/}/BOOT-INF/lib/h2-${_h2_ver}.jar"
        fi
    fi

    if [ ! -s "${_groovy_jar}" ]; then
        echo "ERROR: No groovy jar file under ${_installDir%/}." >&2
        return 1
    fi

    [ -z "${_GROOVY_JAR}" ] && export _GROOVY_JAR="${_groovy_jar}"
    [ -z "${_GROOVY_CLASSPATH}" ] && export _GROOVY_CLASSPATH="${_groovySqlJar}:${_pgJar}:${_h2Jar}"
}

function runDbQuery() {
    local __doc__="Run a query against DB connection specified in the _storeProp"
    local _query="$1"
    local _storeProp="${2:-"${_STORE_FILE}"}"
    local _timeout="${3:-"30"}"
    local _installDir="${4:-"${_INSTALL_DIR}"}"
    local _workDir="${5:-"${_WORK_DIR}"}"
    local _dbConnFile="${6:-"${_DB_CONN_TEST_FILE:-"${_workDir%/}/tmp/DbConnTest.groovy"}"}"

    if [ ! -s "${_storeProp}" ] && [ -z "${jdbcUrl}" ]; then
        echo "ERROR: No nexus-store.properties file and no jdbcUrl set." >&2
        return 1
    fi

    prepareLibs "${_installDir%/}" "${_workDir%/}" || return $?

    if [ ! -s "${_dbConnFile}" ]; then
        genDbConnTest "${_dbConnFile}" || return $?
    fi

    local _java="java"
    [ -d "${JAVA_HOME%/}" ] && _java="${JAVA_HOME%/}/bin/java"
    timeout ${_timeout}s ${_java} -Dgroovy.classpath="${_GROOVY_CLASSPATH%:}" -jar "${_GROOVY_JAR}" \
        "${_dbConnFile}" "${_query}" "${_storeProp}"
}

#setGlobals; JAVA_HOME=$JAVA_HOME_17 startDbWebUi
#_INSTALL_DIR=nexus-3.* JAVA_HOME=$JAVA_HOME_17 startDbWebUi "8282" "./sonatype-work/nexus3/db"
function startDbWebUi() {
    local __doc__="Run a query against DB connection specified in the _storeProp"
    local _webPort="${1:-"8282"}"
    local _baseDir="${2:-"."}"
    local _installDir="${3:-"${_INSTALL_DIR}"}"
    local _workDir="${4:-"${_WORK_DIR}"}"

    prepareLibs "${_installDir%/}" "${_workDir%/}" || return $?

    echo "INFO: Starting H2 Console from \"${_baseDir}\" on http://localhost:${_webPort}/ ..." >&2
    local _java="java"  # In case needs to change to java 8 / java 17
    [ -n "${JAVA_HOME}" ] && _java="${JAVA_HOME%/}/bin/java"
    ${_java} -Dgroovy.classpath="${_GROOVY_CLASSPATH%:}" -jar "${_GROOVY_JAR}" \
        -e "org.h2.tools.Server.createWebServer(\"-webPort\", \"${_webPort}\", \"-webAllowOthers\", \"-ifExists\", \"-baseDir\", \"${_baseDir}\").start()"
}

function setGlobals() { # Best effort. may not return accurate dir path
    local __doc__="Populate PID and directory path global variables etc."
    local _pid="${1:-"${_PID}"}"
    if [ -z "${_pid}" ]; then
        _pid="$(ps auxwww | grep -w -e 'NexusMain' -e 'sonatype-nexus-repository' | grep -vw grep | awk '{print $2}' | tail -n1)"
        _PID="${_pid}"
        [ -z "${_pid}" ] && return 1
    fi
    if [ ! -d "${_INSTALL_DIR}" ]; then
        if [ -n "${_pid}" ]; then
            _INSTALL_DIR="$(ps wwwp ${_pid} | sed -n -E 's/.+-Dexe4j.moduleName=([^ ]+)\/bin\/nexus .+/\1/p' | head -1)"
            if [ -z "${_INSTALL_DIR}" ]; then
                # from 3.80+, this could be `-(jar|classpath) /path/to/sonatype-nexus-repository-{ver}.jar`
                _INSTALL_DIR="$(ps wwwp ${_pid} | sed -n -E 's/.+ ([^ ]+)\/bin\/sonatype-nexus-repository\-[0-9.]+\-[0-9]+\.jar.*/\1/p' | head -1)"
            fi
        fi
        [ -d "${_INSTALL_DIR}" ] || return 1
    fi
    if [ ! -d "${_WORK_DIR}" ] && [ -d "${_INSTALL_DIR%/}" ]; then
        _WORK_DIR="$(ps wwwp ${_pid} | sed -n -E 's/.+-Dkaraf.data=([^ ]+) .+/\1/p' | head -n1)"
        [[ ! "${_WORK_DIR}" =~ ^/ ]] && _WORK_DIR="${_INSTALL_DIR%/}/${_WORK_DIR}"
        [ -d "${_WORK_DIR}" ] || return 1
    fi
    if [ ! -s "${_STORE_FILE}" ] && [ -z "${jdbcUrl}" ] && [ -n "${_pid}" ]; then
        if [ -e "/proc/${_pid}/environ" ]; then
            if grep -q 'NEXUS_DATASTORE_NEXUS_' "/proc/${_pid}/environ"; then
                eval "$(cat "/proc/${_pid}/environ" | tr '\0' '\n' | grep -E '^NEXUS_DATASTORE_NEXUS_.+=')"
                export username="${NEXUS_DATASTORE_NEXUS_USERNAME}" password="${NEXUS_DATASTORE_NEXUS_PASSWORD}" jdbcUrl="${NEXUS_DATASTORE_NEXUS_JDBCURL}"
            elif grep -q 'JDBC_URL=' "/proc/${_pid}/environ"; then
                eval "$(cat "/proc/${_pid}/environ" | tr '\0' '\n' | grep -E '^(JDBC_URL|DB_USER|DB_PWD)=')"
                export username="${DB_USER}" password="${DB_PWD}" jdbcUrl="${JDBC_URL}"
            else
                eval "$(cat "/proc/${_pid}/environ" | tr '\0' '\n' | grep -E '^DB_')"
                # Currently HA helm doesn't allow to change the DB port
                export username="${DB_USER}" password="${DB_PASSWORD}" jdbcUrl="jdbc:postgresql://${DB_HOST}:5432/${DB_NAME}"
            fi
        elif [ -s "${_WORK_DIR%/}/etc/fabric/nexus-store.properties" ] && grep -q -w jdbcUrl "${_WORK_DIR%/}/etc/fabric/nexus-store.properties"; then
            _STORE_FILE="${_WORK_DIR%/}/etc/fabric/nexus-store.properties"
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
    done >${_TMP%/}/.queries.sql
    if [ -s ${_TMP%/}/.queries.sql ]; then
        echo "# format, repo_name, asset_blob_id, blob_ref, blob_size, path, kind"
        query="$(cat ${_TMP%/}/.queries.sql)"
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
        echo "ERROR: Could not find install directory." >&2
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
            echo "# Count & Size per Repository (format, repo_name, count, bytes)"
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
