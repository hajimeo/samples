#!/usr/bin/env bash
# curl -O -L "https://raw.githubusercontent.com/hajimeo/samples/master/bash/nrm3-db-mig-helper.sh"

usage() {
    cat << EOS
USAGE:
    Before starting this script, prepare nexus-store.properties, then specify the migrator jar version.
    bash ./nxrm3-db-mig-helper.sh <migrator-version> [/path/to/nexus-store.properties]
    bash ./nxrm3-db-mig-helper.sh 3.44.0-01
EOS
}

_DB_CONN_TEST_FILE="/tmp/DbConnTest.groovy"
_GROOVY_ALL_VER="2.4.17"
: ${_INSTALL_DIR:=""}
: ${_WORK_DIR:=""}

function _genDbConnTest() {
    cat << EOF > "${_DB_CONN_TEST_FILE}"
import org.postgresql.*
import groovy.sql.Sql
def p = new Properties()
if (!args) p = System.getenv()
else {
   def pf = new File(args[0])
   pf.withInputStream { p.load(it) }
}
def query = (args.length > 1) ? args[1] : "SELECT 'ok' as test"
def driver = Class.forName('org.postgresql.Driver').newInstance() as Driver
def dbP = new Properties()
dbP.setProperty("user", p.username)
dbP.setProperty("password", p.password)
def conn = driver.connect(p.jdbcUrl, dbP)
def sql = new Sql(conn)
try {
   sql.eachRow(query) {println(it)}
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
        local _KarafData="$(ps auxwww | sed -n -E '/org.sonatype.nexus.karaf.NexusMain/ s/.+-Dkaraf.data([^ ]+) .+/\1/p' | head -1)"
        _WORD_DIR="${_INSTALL_DIR%/}/${_KarafData%/}"
    fi
}

function _ports() { # Best effort. may not return accurate dir path
    local pid="$(ps auxwww | grep -F 'org.sonatype.nexus.karaf.NexusMain' | grep -v 'grep -F' | awk '{print $2}')"
    [ -z "${pid}" ] && return 1
    cat /proc/${pid}/net/tcp | sed -n -E 's/^ *[0-9]+: 00000000:([^ ]+).+/\1/p' | sort | uniq | while read -r x; do printf "%d\n" 0x${x}; done
}

function getVer() {     # requires 'curl'
    _ports | while read -r p; do
        curl -s -f -k -I "localhost:8081" | sed -n -E 's/^Server: *Nexus\/([^ ]+) .*/\1/p' | grep -E '^[0-9.-]+$' && break
    done
}

function runDbConnTest() {
    local storeProp="$1"
    if [ ! -s "${_DB_CONN_TEST_FILE}" ]; then
        _genDbConnTest || return $?
    fi
    java -Dgroovy.classpath="$(find ${installDir%/}/system/org/postgresql/postgresql -type f -name 'postgresql-42.*.jar' | tail -n1)" -jar "${installDir%/}/system/org/codehaus/groovy/groovy-all/${_GROOVY_ALL_VER}/groovy-all-${_GROOVY_ALL_VER}.jar" \
    "${_DB_CONN_TEST_FILE}" "${storeProp}"
}

function getMigratorJar() {
    return
}

main() {
    local migVer="$1"
    local storeProp="$2"
    _detectDirs
    if [ -z "${_INSTALL_DIR}" ]; then
        echo "Could not find install directory." >&2
        return 1
    fi
    runDbConnTest "${storeProp}" }|| return $?
}

if [ "$0" = "$BASH_SOURCE" ]; then
    if [ "$#" -eq 0 ]; then
        usage
        exit 1
    fi

    main "$@"
fi
