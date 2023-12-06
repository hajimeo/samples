source "$(dirname ${BASH_SOURCE[0]})/nrm3-db-mig-assist.sh"

_note() {
    cat << 'EOF' >/dev/null
# MANUAL TEST STEPS:
## Install the latest RM3 with OrientDB
```
helm repo add sonatype https://sonatype.github.io/helm3-charts/
helm install nxrm3-test sonatype/nexus-repository-manager -n default
```
## Create a test DB user and a test DB on PostgreSQL server as DB superuser
Check printDbUserCreateSQLs()
## Set username, password, jdbcUrl environment variables:
export username="nxrm" password="nxrm123" jdbcUrl="jdbc:postgresql://localhost:5432/nxrm"

EOF
}

function test_usage() {
    if ! usage >/dev/null; then
        _error
    fi
}

function test_genDbConnTest() {
    if [ -z "${_DB_CONN_TEST_FILE}" ]; then
        _error "No _DB_CONN_TEST_FILE set"
        return
    fi
    if [ -f "${_DB_CONN_TEST_FILE}" ]; then
        rm -f ${_DB_CONN_TEST_FILE}
    fi
    if ! genDbConnTest >/dev/null; then
        _error
    fi
    if [ ! -s "${_DB_CONN_TEST_FILE}" ]; then
        _error "No ${_DB_CONN_TEST_FILE}"
    fi
}

function test_runDbQuery() {
    # If no ${_STORE_FILE}, should fail
    if [ -z "${_STORE_FILE}" ] && runDbQuery 2>/dev/null; then
        _error "runDbQuery should fail"
    fi
    if [ -n "${_STORE_FILE}" ] && ! runDbQuery "SELECT version()"; then
        _error "runDbQuery should not fail for 'SELECT version()'"
    fi
}

function test_setGlobals() {
    echo "sleep 1" > /tmp/sleep.sh
    # Mac can't detect _INSTALL_DIR from /proc/PID/cwd, so added /tmp/
    bash /tmp/sleep.sh -Dkaraf.data=${HOME} -Dexe4j.moduleName=/tmp/bin/nexus org.sonatype.nexus.karaf.NexusMain &
    local _wpid=$!

    unset _PID
    unset _INSTALL_DIR
    unset _WORK_DIR
    #set -x
    setGlobals
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        _error "rc: ${_rc}"
    fi
    #set +x
    if [ "${_PID}" != "${_wpid}" ]; then
        _error "_PID: ${_PID} != ${_wpid}"
    fi
    if [ "${_INSTALL_DIR%/}" != "/tmp" ]; then
        _error "_INSTALL_DIR: ${_INSTALL_DIR%/} != /tmp"
    fi
    if [ "${_WORK_DIR%/}" != "$HOME" ]; then
        _error "_WORK_DIR: ${_WORK_DIR%/} != $HOME"
    fi
    wait

    export _INSTALL_DIR="/var/tmp" _WORK_DIR="."
    setGlobals "9999"
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        _error "rc: ${_rc} with 9999"
    fi
    if [ "${_INSTALL_DIR%/}" != "/var/tmp" ]; then
        _error "_INSTALL_DIR: ${_INSTALL_DIR%/} != /var/tmp"
    fi
    if [ "${_WORK_DIR%/}" != "." ]; then
        _error "_WORK_DIR: ${_WORK_DIR%/} != '.'"
    fi
    wait
}

function test_chkDirSize() {
    if ! chkDirSize; then
        _error
    fi
}

function test_chkJavaVer() {
    if ! chkJavaVer; then
        _error
    fi
}

function test_chkDbConn() {
    if ! _INSTALL_DIR="" chkDbConn; then
        _error
    fi
}

function test_prepareDbMigJar() {
    if ! prepareDbMigJar "3.63.0-01"; then
        _error
    fi
}

function test_printDbUserCreateSQLs() {
    if ! printDbUserCreateSQLs >/dev/null; then
        _error
    fi
}



# shellcheck disable=SC2120
_error() {
    local _msg="${1:-"failed"}"
    local _lvl="${2:-"ERROR"}"
    echo "[${_lvl}] ${FUNCNAME[1]} ${_msg}" >&2
}

if [ "$0" = "$BASH_SOURCE" ]; then
    for _t in $(typeset -F | grep -E '^declare -f test_' | cut -d' ' -f3); do
        ${_t}
    done
    echo "Tests completed."
fi