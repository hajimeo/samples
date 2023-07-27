source "$(dirname ${BASH_SOURCE[0]})/iq-threaddumps.sh"

# TODO: Not implemented yet (just copied from nrm3 one)

function test_usage() {
    if ! usage >/dev/null; then
        _error
    fi
}

function test_detectDirs() {
    echo "sleep 1" > /tmp/sleep.sh
    echo "sonatypeWork: $HOME" > /tmp/config.yml
    # Mac can't detect _INSTALL_DIR from /proc/PID/cwd, so added /tmp/
    bash /tmp/sleep.sh /tmp/nexus-iq-server-aaaaaa.jar server /tmp/config.yml &
    local _wpid=$!

    unset _PID
    unset _INSTALL_DIR
    unset _WORK_DIR
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
    if [ "${_WORK_DIR%/}" != "$HOME" ]; then
        _error "_WORK_DIR: ${_WORK_DIR%/} != $HOME"
    fi
    wait

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
    wait
}

function test_tailStdout() {
    rm -f /tmp/test_tailStdout.out &>/dev/null
    echo "sleep 1" > /tmp/sleep.sh
    bash /tmp/sleep.sh -XX:LogFile=/tmp/sleep.sh &
    local _pid=$!
    tailStdout "${_pid}" "1" "/tmp/test_tailStdout.out" "/"
    local _rc=$?
    if [ "${_rc}" -ne 0 ] && [ "${_rc}" -ne 124 ] ; then
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