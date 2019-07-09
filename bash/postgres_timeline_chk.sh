#!/usr/bin/env bash
function usage() {
    echo "$BASH_SOURCE hostname1 hostname2 [Y]
    Expecting this script is used in crontab (and cron sends email to admin).
    If the 3rd argument is Y or y, this script outputs CSV and exits.
"
}

_TMP_FILE=/tmp/postgres_timeline_chk.csv

function main() {
    local _node1="$1"
    local _node2="$2"
    local _isCsvOnly="$3"

    > "${_TMP_FILE}"
    _printCsv "${_node1}" >> "${_TMP_FILE}"
    _printCsv "${_node2}" >> "${_TMP_FILE}"

    if [[ "${_isCsvOnly}" =~ ^(y|Y) ]]; then
        cat "${_TMP_FILE}"
        return
    fi

    if ! _chkTimeline "${_node1}" "${_node2}"; then
        # TODO: Change this message for cron (and cron sends email)
        echo "Timeline check failed!"
        cat "${_TMP_FILE}"
    fi
}

function _printCsv() {
    local _host="$1"

    # as a example, using CSV (but json would be better)
    curl -s http://${_host}:10519/ | python -c "import sys,json;a=json.loads(sys.stdin.read());print('"${_host}",'+str(a['role'])+','+str(a['timeline']))"
}

function _chkTimeline() {
    local _node1="$1"
    local _node2="$2"

    _tl1="$(grep "^${_node1}" ${_TMP_FILE} | cut -d ',' -f 3)"
    _tl2="$(grep "^${_node2}" ${_TMP_FILE} | cut -d ',' -f 3)"
    # TODO: add master/replica check (I think master is OK to use larger timeline than replica)
    [ -z "${_tl1}" ] && return 1
    [ -z "${_tl2}" ] && return 1
    [ "${_tl1}" != "${_tl2}" ] && return 1
    return 0
}

if [ "$0" = "$BASH_SOURCE" ]; then
    if [ -z "$1" ]; then
        usage
        exit
    fi

    main "$1" "$2" "$3"
fi