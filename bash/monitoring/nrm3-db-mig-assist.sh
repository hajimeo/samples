#!/usr/bin/env bash
usage() {
    cat <<EOF
Output necessary commands to migrate the DB on this Nexus

USAGE:
# Set DB connection related environment variables:
    export username="nxrm" password="nxrm123" jdbcUrl="jdbc:postgresql://localhost:5432/nxrm"

# Oneliner command:
    bash <(curl -sfL https://raw.githubusercontent.com/hajimeo/samples/master/bash/monitoring/nrm3-db-mig-assist.sh --compressed)
# Or, to specify DB Migrator version with '-m':
    curl -O -sfL https://raw.githubusercontent.com/hajimeo/samples/master/bash/monitoring/nrm3-db-mig-assist.sh --compressed
    bash ./nrm3-db-mig-assist.sh -m 3.63.0-01

# If Nexus is not running, specify '-i <installDir>' for connection test (and '-s' or 'export' for DB connection):
    bash ./nrm3-db-mig-assist.sh -i ./nexus-3.62.0-01/ -s ./sonatype-work/nexus3/etc/fabric/nexus-store.properties
EOF
}

: "${_ADMIN_CRED:="admin"}" # no ':password' will ask the password
: "${_NEXUS_URL:="http://localhost:8081/"}"
_DB_CONN_TEST_FILE="/tmp/DbConnTest.groovy"
# Also' username', 'password', 'jdbcUrl' are used for DB connection.

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
    local _groovyAllVer="2.4.17"
    if [ ! -s "${_storeProp}" ] && [ -z "${jdbcUrl}" ]; then
        echo "ERROR:No nexus-store.properties file and no jdbcUrl set." >&2
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
        [ -z "${_pid}" ] && echo "WARN: no PID found" >&2
    fi
    if [ ! -d "${_INSTALL_DIR}" ]; then
        if [ -n "${_pid}" ]; then
            _INSTALL_DIR="$(ps wwwp ${_pid} | sed -n -E '/org.sonatype.nexus.karaf.NexusMain/ s/.+-Dexe4j.moduleName=([^ ]+)\/bin\/nexus .+/\1/p' | head -1)"
        fi
        [ -d "${_INSTALL_DIR}" ] || echo "WARN: no install directory found" >&2
    fi
    if [ ! -d "${_WORK_DIR}" ] && [ -d "${_INSTALL_DIR%/}" ]; then
        _WORK_DIR="$(ps wwwp ${_pid} | sed -n -E '/org.sonatype.nexus.karaf.NexusMain/ s/.+-Dkaraf.data=([^ ]+) .+/\1/p' | head -n1)"
        [[ ! "${_WORK_DIR}" =~ ^/ ]] && _WORK_DIR="${_INSTALL_DIR%/}/${_WORK_DIR}"
        [ -d "${_WORK_DIR}" ] || echo "WARN: no sonatype work directory found" >&2
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
        elif [ -s "${_WORK_DIR%/}/etc/fabric/nexus-store.properties" ] && grep -q -w jdbcUrl "${_WORK_DIR%/}/etc/fabric/nexus-store.properties"; then
            _STORE_FILE="${_WORK_DIR%/}/etc/fabric/nexus-store.properties"
        fi
    fi
}

function chkDirSize() {
    local __doc__="Check temp directory size and if no _min_gb, compare with DB directory"
    local _tmp="${1:-"${TMPDIR:-"/tmp"}"}"
    local _min_gb="${2}"    # default is "4"
    if [ ! -d "${_tmp%/}" ]; then
        echo "WARN: Couldn't find temp directory ${_tmp%/}." >&2
        return 1
    fi
    if [ -z "${_min_gb}" ]; then
        if [ -z "${_DB_DIR%/}" ] && [ -d "${_WORK_DIR%/}/db" ]; then
            _DB_DIR="${_WORK_DIR%/}/db"
        fi
        if [ -d "${_DB_DIR%/}" ]; then
            # No _idx.* size + 2 GB
            _min_gb="$(find "${_DB_DIR%/}/component" -maxdepth 1 -type f ! -name "*_idx.*" -printf '%s\n'  | awk '{ s+=$1 }; END { printf "%d\n", s / 1024 / 1024 / 1024 + 2 }')"
            if [ -n "${_min_gb}" ] && [ ${_min_gb} -gt 10 ]; then
                echo "WARN: ${_DB_DIR%/}/component is very large (${_min_gb} GB)" >&2
            fi
        fi
        if [ -z "${_min_gb}" ]; then
            _min_gb="4"
        fi
    fi
    local _free_gb="$(df -k -P "${_tmp%/}" | tail -n1 | awk '{printf "%d\n", $4 / 1024 / 1024}')"
    if [ -z "${_free_gb}" ] || [ ${_free_gb} -lt ${_min_gb} ]; then
        echo "WARN: Temp directory: ${_tmp%/} may not have enough disk space (free:${_free_gb} < min:${_min_gb})" >&2
        return 1
    fi
}

function chkJavaVer() {
    local _java="${1:-"java"}"
    if ! eval "${_java} -version" 2>&1 | grep -q -E -i '^openjdk .+1\.8\.0'; then
        echo "WARN: java executable: ${_java} may not be OpenJDK v8." >&2
        return 1
    fi
}

function chkDbConn() {
    if [ -n "${_INSTALL_DIR%/}" ]; then
        echo "INFO: Checking PostgreSQL connection ..." >&2
        runDbQuery "SELECT version()" || return $?
    else
        echo "WARN: No DB connection tests as no _INSTALL_DIR (-i)" >&2
    fi
}

function prepareDbMigJar() {
    local __doc__="Prepare DB migration jar"
    local _migrator_jar="${1:-"${_MIGRATOR_JAR}"}"
    local _nexus_url="${2:-"${_NEXUS_URL}"}"
    local _download_dir="${3:-"/tmp"}"

    local _ver=""
    # If _migrator_jar is version string instead of file path
    if [[ "${_migrator_jar}" =~ ^3\.[0-9]+\.[0-9]+-[0-9][0-9]$ ]]; then
        _ver="${BASH_REMATCH[0]}"
        _migrator_jar="${_download_dir%/}/nexus-db-migrator-${_ver}.jar"
        export _MIGRATOR_JAR="${_migrator_jar}"
    fi

    # Trying to guess the migrator version
    if [ -z "${_ver}" ]; then
        local _pid="$(ps auxwww | grep -F 'org.sonatype.nexus.karaf.NexusMain' | grep -vw grep | awk '{print $2}' | tail -n1)"
        if [[ "${_migrator_jar}" =~ 3\.[0-9]+\.[0-9]+-[0-9][0-9] ]]; then
            _ver="${BASH_REMATCH[0]}"
        elif [ -n "${_pid}" ]; then
            _ver="$(curl -sSf -I "${_nexus_url%/}/" | sed -n -E '/^server/ s/.*\/([^ ]+).*/\1/p')"
            if [ -z "${_ver}" ]; then
                echo "WARN: ${_nexus_url%/} might not be working (PID: ${_pid})" >&2
            fi
        else
            echo "INFO: No NexusMain running (assuming it's stopped)" >&2
        fi
    fi

    # If no version, can't download the jar file, so returning
    if [ -z "${_ver}" ] && [ ! -s "${_migrator_jar}" ]; then
        echo "ERROR:No _MIGRATOR_JAR (-m) specified" >&2
        return 1
    fi

    if [ ! -s "${_migrator_jar}" ]; then
        echo "INFO: Downloading DB migrator for version: ${_ver} into ${_migrator_jar} ..." >&2
        local _tmp_dir="$(mktemp -d)"
        curl -Sf -L -o "${_tmp_dir%/}/nexus-db-migrator-${_ver}.jar" "https://download.sonatype.com/nexus/nxrm3-migrator/nexus-db-migrator-${_ver}.jar" || return $?
        mv -v "${_tmp_dir%/}/nexus-db-migrator-${_ver}.jar" "${_MIGRATOR_JAR}" || return $?
    fi
}

function printDbUserCreateSQLs(){
    local _dbname="${1}"
    local _dbusr="${2:-"${username:-"testDbUser"}"}"
    local _dbpwd="${3:-"${password:-"testDbUserPwd"}"}"
    if [ -z "${_dbname}" ]; then
        [ -n "${jdbcUrl}" ] && _dbname="$(basename "${jdbcUrl}")"
        [ -z "${_dbname}" ] && _dbname="testDbName"
    fi
    cat << EOF
CREATE USER "${_dbusr}" WITH LOGIN PASSWORD '${_dbpwd}';
CREATE DATABASE "${_dbname}" WITH OWNER "${_dbusr}" ENCODING 'UTF8';
\c "${_dbname}"
GRANT ALL ON SCHEMA public TO "${_dbusr}";
-- Also update pg_hba.conf which location can be found with the below
SELECT setting, context from pg_settings where name = 'hba_file';
-- After updating pg_hba.conf, reload (not restart)
SELECT pg_reload_conf();
EOF
}

main() {
    setGlobals "${_PID}"

    chkDbConn
    chkDirSize
    chkJavaVer

    prepareDbMigJar

    echo ""
    echo "# Please make sure the database and DB user are created"
    echo "# //----------------------------------------"
    printDbUserCreateSQLs
    echo "# ----------------------------------------//"
    echo ""
    echo "# Below makes this OrientDB read-only/freeze (should not unfreeze after completing the migration)"
    echo "curl -sSf -X POST -u \"${_ADMIN_CRED}\" -k \"${_NEXUS_URL%/}/service/rest/v1/read-only/freeze\""
    echo ""
    echo "# Example DB migrator command ('-Xmx<N>g', --debug', '--force=true', '--yes' may be required)"
    echo "java -jar ${_MIGRATOR_JAR} --migration_type=postgres --db_url=\"${jdbcUrl}?user=${username}&password=${password}\" --orient.folder=\"$(readlink -f "${_DB_DIR%/}")\""
    echo "# More info: https://help.sonatype.com/repomanager3/installation-and-upgrades/migrating-to-a-new-database#MigratingtoaNewDatabase-MigratingtoPostgreSQL"
}


if [ "$0" = "${BASH_SOURCE[0]}" ]; then
    #if [ "$#" -eq 0 ]; then
    if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ]; then
        usage
        exit 0
    fi
    while getopts "c:d:i:m:s:u:" opts; do
        case $opts in
        c)
            _ADMIN_CRED="$OPTARG"
            ;;
        d)
            _DB_DIR="$OPTARG"
            ;;
        i)
            # When Nexus process is not running and for DB connection test. If not set, no connection test
            _INSTALL_DIR="$OPTARG"
            ;;
        m)
            _MIGRATOR_JAR="$OPTARG"
            ;;
        s)
            _STORE_FILE="$OPTARG"
            ;;
        u)
            _NEXUS_URL="$OPTARG"
            ;;
        *)
            echo "$opts $OPTARG is not supported. Ignored." >&2
            ;;
        esac
    done

    main #"$@"
fi
