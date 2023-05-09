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
    unset _WORD_DIR
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
    if [ "${_WORD_DIR%/}" != "$HOME" ]; then
        _error "_WORD_DIR: ${_WORD_DIR%/} != $HOME"
    fi
    wait
}

function test_tailStdout() {
    echo "sleep 1" > /tmp/sleep.sh
    bash /tmp/sleep.sh -XX:LogFile=/tmp/sleep.sh &
    local _pid=$!
    rm -f /tmp/stdout_${_pid}.out
    tailStdout "${_pid}" "1" "" "/"
    local _rc=$?
    if [ "${_rc}" -ne 0 ] && [ "${_rc}" -ne 124 ] ; then
        _error
    fi
    wait
    # More complex test doesn't work on Mac
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