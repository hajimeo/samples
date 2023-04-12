source "$(dirname $BASH_SOURCE)/nrm3-threaddumps.sh"

function test_usage() {
    if ! usage >/dev/null; then
        _error
    fi
}

function test_genDbConnTest() {
    if [ -z "${_DB_CONN_TEST_FILE}" ]; then
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

function test_detectDirs() {
    echo "sleep 3" > /tmp/sleep.sh
    bash /tmp/sleep.sh -Dkaraf.data=/var/tmp/sonatype-work -Dexe4j.moduleName=/tmp/bin/nexus org.sonatype.nexus.karaf.NexusMain &
    local _wpid=$!
    #set -x
    if ! detectDirs >/dev/null; then
        _error
    fi
    #set +x
    if [ "${_PID}" != "${_wpid}" ]; then
        _error "_PID: ${_PID} != ${_wpid}"
    fi
    if [ "${_INSTALL_DIR%/}" != "/tmp" ]; then
        _error "_INSTALL_DIR: ${_INSTALL_DIR%/} != /tmp"
    fi
    if [ "${_WORD_DIR%/}" != "${_INSTALL_DIR%/}/var/tmp/sonatype-work" ]; then
        _error "_WORD_DIR: ${_WORD_DIR%/} != ${_INSTALL_DIR%/}/var/tmp/sonatype-work"
    fi
}

function test_runDbQuery() {
    if ! runDbQuery >/dev/null; then
        _error "Not implemented yet." "TODO"
    fi
}

function test_takeDumps() {
    if ! takeDumps "1" "1" >/dev/null; then
        _error
    fi
}

function test_kill3() {
    rm -f /tmp/stdout_${_pid}.out
    local _pid
    if type jps &>/dev/null; then
        _pid="$(jps -l | grep -vw Jps | grep -E '^\d+ \S+' | tail -n1 | cut -d' ' -f1)"
    fi
    if [ -z "${_pid}" ]; then
        echo "sleep 3" > /tmp/sleep.sh
        bash /tmp/sleep.sh &
        _pid=$!
    fi
    detectDirs "${_pid}"
    if ! kill3 "${_pid}" >/dev/null; then
        _error
    fi
    if [ ! -f "/tmp/stdout_${_pid}.out" ]; then
        _error "/tmp/stdout_${_pid}.out does not exist"
    else
        head "/tmp/stdout_${_pid}.out"
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
fi