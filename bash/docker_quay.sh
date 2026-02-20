#!/usr/bin/env bash
QUAY_IMAGE="$1"
QUAY_API_PATH="$2"  # Optional, default to "/tags/list"
QUAY_USERNAME="$3"
QUAY_PASSWORD="$4"
QUAY_URL="https://quay.io/"

function test_quay() {
    local _img="${1:-"${QUAY_IMAGE}"}"   #"hosako/test-repo"
    local _path="${2:-"${QUAY_API_PATH:-"/tags/list"}"}"
    local _username="${3:-"${QUAY_USERNAME}"}"
    local _password="${4:-"${QUAY_PASSWORD}"}"
    if [ -n "${_password}" ]; then
        _password=":${_password}"
    fi
    local _query="scope=repository:${_img#/}:pull"
    echo "# Getting token for user ${_username} for ${_query} ..." >&2
    local _token="$(curl -sf -u "${_username}${_password}" -L "${QUAY_URL%/}/v2/auth" --get --data-urlencode "${_query}" --data-urlencode "service=quay.io" | sed -E 's/.+"token":"([^"]+)".+/\1/')"

    if [ -z "${_token}" ]; then
      echo "Failed to get token for user ${_username}" >&2
      return 1
    fi

    local _suffix="_$(date +"%Y%m%d%H%M%S")"
    echo "# Testing Token against ${_img} with -D ./test_quay-header${_suffix}.out -o ./test_quay-result${_suffix}.json" >&2
    curl -sf -k -H "Authorization: Bearer ${_token}" -H "Accept: application/json" -k -L "${QUAY_URL%/}/v2/${_img#/}${_path}" -D ./test_quay-header${_suffix}.out -o ./test_quay-result${_suffix}.json
    return $?
}

test_quay