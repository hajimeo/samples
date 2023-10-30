source "$(dirname ${BASH_SOURCE[0]})/iq-threaddumps.sh"

# TODO: Not implemented yet (just copied from nrm3 one)

function test_usage() {
    if ! usage >/dev/null; then
        _error
    fi
}

function test_detectDirs() {
    unset _PID
    unset _INSTALL_DIR
    unset _WORK_DIR
    unset _STORE_FILE

    local _wpid=""
    local _pid="$(ps auxwww | grep -E 'nexus-iq-server.*\.jar server' | grep -vw grep | awk '{print $2}' | tail -n1)"
    if [ -z "${_pid}" ]; then
        echo "sleep 1" > /tmp/sleep.sh
        chmod u+x /tmp/sleep.sh
        echo "sonatypeWork: $HOME" > /tmp/config.yml
        # Mac can't detect _INSTALL_DIR from /proc/PID/cwd, so added /tmp/
        bash -c "cd /tmp && ./sleep.sh java /tmp/nexus-iq-server-aaaaaa.jar server /tmp/config.yml" &
        _wpid=$!
    fi

    #set -x
    if ! detectDirs >/dev/null; then
        _error
    fi
    #set +x

    if [ -n "${_wpid}" ]; then
        if [[ ! "${_INSTALL_DIR%/}" =~ /tmp$ ]]; then # Mac appends /private
            _error "_INSTALL_DIR: ${_INSTALL_DIR%/} != /tmp"
        fi
        if [[ ! "${_STORE_FILE}" =~ /tmp/config.yml$ ]]; then # Mac appends /private
            _error "_STORE_FILE: ${_STORE_FILE%/} != /tmp/config.yml"
        fi
        if [ "${_WORK_DIR%/}" != "$HOME" ]; then
            _error "_WORK_DIR: ${_WORK_DIR%/} != $HOME"
        fi
        wait ${_wpid}
    fi

    export _INSTALL_DIR="/var/tmp" _WORK_DIR="."
    if ! detectDirs "9999" >/dev/null; then
        _error
    fi
    if [ "${_INSTALL_DIR%/}" != "/var/tmp" ]; then
        _error "_INSTALL_DIR: ${_INSTALL_DIR%/} != /var/tmp"
    fi
    if [ "${_WORK_DIR%/}" != "." ]; then
        _error "_WORK_DIR: ${_WORK_DIR%/} != '.'"
    fi
    jobs -l
}

function test_detectAdminUrl() {
    unset _ADMIN_URL
    cat << EOF > /tmp/test_detectAdminUrl.tmp
server:
  adminConnectors:
  - port: 8471
    type: https
EOF
    _STORE_FILE="/tmp/test_detectAdminUrl.tmp"
    detectAdminUrl
    local _rc=$?
    #if [ "${_rc}" -ne 0 ] ; then
    #    _error "Return code was not 0 but ${_rc}"
    #fi
    if [ "${_ADMIN_URL%/}" != "https://localhost:8471" ] ; then
        _error "${_ADMIN_URL%/} was not https://localhost:8471"
    fi
}

function test_tailStdout() {
    rm -f /tmp/test_tailStdout.out &>/dev/null
    echo "sleep 1" > /tmp/sleep.sh
    bash /tmp/sleep.sh -XX:LogFile=/tmp/sleep.sh &
    local _pid=$!
    tailStdout "${_pid}" "1" "/tmp/test_tailStdout.out" "/"
    local _rc=$?
    if [ "${_rc}" -ne 0 ] && [ "${_rc}" -ne 124 ] ; then    # 124 = timeout
        _error
    fi
    wait
    # NOTE: more complex test may not work on Mac
    #if [ "$(cat /tmp/test_tailStdout.out)" != "this is test" ] ; then
    #    _error "/tmp/test_tailStdout.out doesn't contain 'this is test'"
    #fi
}

function test_takeDumps() {
    echo "sleep 1" > /tmp/sleep.sh
    bash /tmp/sleep.sh -XX:LogFile=/tmp/sleep.sh &
    local _pid=$!
    if ! takeDumps "${_pid}" "1" "1" "" "/" 2>/dev/null; then
        _error
    fi
    wait
}

function test_miscChecks() {
    # This function never returns non zero though...
    if ! miscChecks &>/tmp/test_miscChecks.out; then
        _error
    fi
    if ! grep -q -F '+ set +x' /tmp/test_miscChecks.out ; then
        _error "Unexpected output in /tmp/test_miscChecks.out"
    fi
    wait
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