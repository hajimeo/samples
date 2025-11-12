#!/usr/bin/env bash
# Simple tests by just executing the commands and check the exit code.
: ${_TEST_STOP_ERROR:=true}
: ${_DEBUG:=false}
_PROXY_PID=""
_TMP="$(mktemp -d)"


### Test functions
function test_1_StartHttpProxyNormally() {
    local _port=38001
    _httpproxy "--port ${_port}" || return $?

	if ! curl -sSf -o "${_TMP%/}/${FUNCNAME[0]}_curl.out" --proxy localhost:${_port} http://search.osakos.com/index.php; then
        _result "ERROR" "http request via localhost:${_port} failed!"
        return 1
    fi
    if [ ! -s "${_TMP%/}/${FUNCNAME[0]}_curl.out" ]; then
        _result "ERROR" "${_TMP%/}/${FUNCNAME[0]}_curl.out is empty!"
        return 1
    fi

	if ! curl -sSf -o "${_TMP%/}/${FUNCNAME[0]}_curl.out" --proxy localhost:${_port} https://www.google.com; then
        _result "ERROR" "httpS request via localhost:${_port} failed!"
        return 1
    fi
    if [ ! -s "${_TMP%/}/${FUNCNAME[0]}_curl.out" ]; then
        _result "ERROR" "${_TMP%/}/${FUNCNAME[0]}_curl.out (2) is empty!"
        return 1
    fi

    _result "OK" "${FUNCNAME[0]}"
    return 0
}

function test_2_StartHttpProxyWithReplCert() {
    local _port=38002
    _httpproxy "--port ${_port} --replCert" || return $?

	# Need -k as cert is replaced
	if curl -sSfv -o /dev/null --proxy localhost:${_port} https://www.google.com 2>"${_TMP%/}/${FUNCNAME[0]}_last.err"; then
        _result "ERROR" "httpS request via localhost:${_port} should have failed but worked!"
        echo "Check ${_TMP%/}/${FUNCNAME[0]}_last.err"
        return 1
    fi
	if ! curl -sSfv -o "${_TMP%/}/${FUNCNAME[0]}_curl.out" --proxy localhost:${_port} -k https://www.google.com 2>"${_TMP%/}/${FUNCNAME[0]}_last.err"; then
        _result "ERROR" "httpS request via localhost:${_port} with '-k' failed!"
        echo "Check ${_TMP%/}/${FUNCNAME[0]}_last.err"
        return 1
    fi
    if [ ! -s "${_TMP%/}/${FUNCNAME[0]}_curl.out" ]; then
        _result "ERROR" "${_TMP%/}/${FUNCNAME[0]}_curl.out is empty!"
        echo "Check ${_TMP%/}/${FUNCNAME[0]}_last.err"
        return 1
    fi

    _result "OK" "${FUNCNAME[0]}"
    return 0
}

function test_3_StartHttpProxyWithHttpS() {
    local _port=38003
    #httpproxy --replCert --proto http
    # Test (need --proxy-insecure and -k)
	#curl -v --proxy https://localhost:8080/ --proxy-insecure -k https://search.osakos.com/index.php
    echo "TEST=SKIPPED ${FUNCNAME[0]} Not implemented yet."
    return 0
}

function test_4_StartHttpProxyWithDelayWithRegex() {
    local _port=38004
    _httpproxy "--port ${_port} --delay 5 --urlregex osakos" || return $?

	if curl -sSfv -o /dev/null -m 3 --proxy localhost:${_port} http://www.osakos.com/ 2>"${_TMP%/}/${FUNCNAME[0]}_last.err"; then
        _result "ERROR" "http request via localhost:${_port} with -m3 should have failed but worked!"
        echo "Check ${_TMP%/}/${FUNCNAME[0]}_last.err"
        return 1
    fi
	if ! curl -sSfv -o /dev/null --proxy localhost:${_port} https://www.google.com/ 2>"${_TMP%/}/${FUNCNAME[0]}_last.err"; then
        _result "ERROR" "http request via localhost:${_port} for non regex matched URL failed!"
        echo "Check ${_TMP%/}/${FUNCNAME[0]}_last.err"
        return 1
    fi

    _result "OK" "${FUNCNAME[0]}"
    return 0
}



### Utility functions
function _log() {
    local _log_file="${_LOG_FILE_PATH:-"/dev/null"}"
    local _is_debug="${_DEBUG:-false}"
    if [ "$1" == "DEBUG" ] && ! ${_is_debug}; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >>${_log_file}
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a ${_log_file}
    fi 1>&2 # At this moment, outputting to STDERR
}

function _result() {
    local _status="${1:-"(nil)"}"
    local _msg="${2}"
    echo "TEST=${_status} ${_msg}"
    kill ${_PROXY_PID}
    sleep 1
}

function _httpproxy() {
    local _options="$1"
    if ${_DEBUG}; then
        httpproxy ${_options} --debug &> ${_TMP%/}/_httpproxy_last.out &
        _PROXY_PID=$!
    else
        httpproxy ${_options} &> ${_TMP%/}/_httpproxy_last.out &
        _PROXY_PID=$!
    fi
    sleep 2
    if ! kill -0 ${_PROXY_PID} 2>/dev/null; then
        echo "TEST=ERROR: 'httpproxy ${_options}' failed to start!"
        echo "Check log: ${_TMP%/}/_httpproxy_last.out"
        return 1
    fi
    echo "Started 'httpproxy ${_options}' (pid: ${_PROXY_PID}, log: ${_TMP%/}/_httpproxy_last.out)"
    return 0
}



function prerequisites() {
    if [ ! -d "${_TMP}" ]; then
        echo "Temporary directory ${_TMP} does not exist."
        return 1
    fi
    if ! type httpproxy &>/dev/null; then
        echo "httpproxy is not installed or not in the PATH. Please install it first."
        return 1
    fi
}

function main() {
    if ! prerequisites; then
        echo "Prerequisites not met. Exiting."
        return 1
    fi

    local _pfx="test_"
    local _final_result=true
    # The function names should start with 'test_', and sorted
    for _t in $(typeset -F | grep "^declare -f ${_pfx}" | cut -d' ' -f3 | sort); do
        local _started="$(date +%s)"
        _log "INFO" "Starting ${_t} ..."
        if ! eval "${_t}" && ${_TEST_STOP_ERROR}; then
            _final_result=false
            break
        fi
        _log "INFO" "Completed ${_t}"
    done
    ps aux | grep httpproxy | grep -v 'httpproxy_test.sh' | grep -v grep
    if ${_final_result}; then
        _log "INFO" "All tests completed successfully."
    else
        _log "ERROR" "Some tests failed. Check ${_TMP%/}/_httpproxy_last.out"
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
