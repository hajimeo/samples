#!/usr/bin/env bash
usage() {
    cat << EOF
USAGE:
    bash ./nrm3-db-test.sh [/path/to/nexus-store.properties] [query]
EOF
}

_DB_CONN_TEST_FILE="/tmp/DbConnTest.groovy"
_GROOVY_ALL_VER="2.4.17"
: "${_INSTALL_DIR:=""}"
: "${_WORK_DIR:=""}"

function _genDbConnTest() {
    cat << 'EOF' > "${_DB_CONN_TEST_FILE}"
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

function _detectDirs() {    # Best effort. may not return accurate dir path
    if [ ! -d "${_INSTALL_DIR}" ]; then
        _INSTALL_DIR="$(ps auxwww | sed -n -E '/org.sonatype.nexus.karaf.NexusMain/ s/.+-Dexe4j.moduleName=([^ ]+)\/bin\/nexus .+/\1/p' | head -1)"
    fi
    if [ ! -d "${_WORD_DIR}" ] && [ -d "${_INSTALL_DIR%/}" ]; then
        local _karafData="$(ps auxwww | sed -n -E '/org.sonatype.nexus.karaf.NexusMain/ s/.+-Dkaraf.data=([^ ]+) .+/\1/p' | head -1)"
        _WORD_DIR="${_INSTALL_DIR%/}/${_karafData%/}"
    fi
}

function runDbConnTest() {
    local storeProp="$1"
    local query="$2"
    if [ ! -s "${_DB_CONN_TEST_FILE}" ]; then
        _genDbConnTest || return $?
    fi
    if [ -z "${storeProp}" ] && [ -d "${_WORD_DIR%/}" ]; then
        storeProp="${_WORD_DIR%/}/etc/fabric/nexus-store.properties"
    fi
    if [ ! -s "${storeProp}" ]; then
        echo "Could not find nexus-store.properties file." >&2
        return 1
    fi
    java -Dgroovy.classpath="$(find "${_INSTALL_DIR%/}/system/org/postgresql/postgresql" -type f -name 'postgresql-42.*.jar' | tail -n1)" -jar "${_INSTALL_DIR%/}/system/org/codehaus/groovy/groovy-all/${_GROOVY_ALL_VER}/groovy-all-${_GROOVY_ALL_VER}.jar" \
    "${_DB_CONN_TEST_FILE}" "${storeProp}" "${query}"
}

main() {
    local storeProp="$1"
    local query="$2"
    _detectDirs
    if [ -z "${_INSTALL_DIR}" ]; then
        echo "Could not find install directory." >&2
        return 1
    fi
    runDbConnTest "${storeProp}" "${query}" || return $?
}

if [ "$0" = "$BASH_SOURCE" ]; then
    #if [ "$#" -eq 0 ]; then
    if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ]; then
        usage
        exit 1
    fi
    main "$@"
fi
