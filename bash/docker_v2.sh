#!/usr/bin/env bash
# https://success.docker.com/article/how-do-i-authenticate-with-the-v2-api
# https://www.docker.com/blog/checking-your-current-docker-pull-rate-limits-and-status/
# https://docs.docker.com/registry/spec/auth/token/
#
# Require: python and jwt (brew tap mike-engel/jwt-cli && brew install jwt-cli)
#
# Simpler test:
#   curl -I -u "${_USER}:${_PWD}" -L -k "${_DOCKER_REGISTRY_URL%/}/v2/"
#

# Use 'export' to overwrite
: ${_USER:=""}
: ${_PWD:=""}
: ${_IMAGE:="ratelimitpreview/test"}
: ${_TAG="latest"}
: ${_TOKEN_SERVER_URL:="https://auth.docker.io/token?service=registry.docker.io"}   # http://dh1.standalone.localdomain:8081/repository/docker-proxy/v2/token
: ${_DOCKER_REGISTRY_URL:="https://registry-1.docker.io"}   # http://dh1.standalone.localdomain:8081/repository/docker-proxy/

: ${_TMP:="/tmp"}

#_curl="curl -v -f -D /dev/stderr --compressed -k"
_curl="curl -s -f -D /dev/stderr --compressed -k"

function _print_token() {
    python -c "import sys,json
s=sys.stdin.read()
try:
  a=json.loads(s)
  print(a['token'])
except:
  sys.stderr.write(s+'\n')
"
}

function get_token() {
    local _token_server_url="${1:-"${_TOKEN_SERVER_URL}"}"
    local _user="${2:-"${_USER}"}"
    local _pwd="${3:-"${_PWD}"}"
    local _image="${4:-"${_IMAGE}"}"

    if [ -n "${_user}" ] && [ -z "${_pwd}" ]; then
        ${_curl} -u "${_user}" "${_token_server_url}" --get --data-urlencode "scope=repository:${_image}:pull"
    elif [ -n "${_user}" ] && [ -n "${_pwd}" ]; then
        ${_curl} -u "${_user}:${_pwd}" "${_token_server_url}" --get --data-urlencode "scope=repository:${_image}:pull"
    else
        ${_curl} "${_token_server_url}" --get --data-urlencode "scope=repository:${_image}:pull"
    fi | _print_token
}

if [ "$0" = "$BASH_SOURCE" ]; then
    echo "### Requesting '${_TOKEN_SERVER_URL}&scope=repository:${_IMAGE}:pull'" >&2
    _TOKEN="$(get_token)"

    if [ -n "${_TOKEN}" ]; then
        echo "### Got token" >&2
        echo "${_TOKEN}" >&2
        # For debugging (Nexus's token can't be decoded)
        if which jwt &>/dev/null; then
            echo "### Decoding JWT" >&2
            jwt decode "${_TOKEN}"
        fi

        # NOTE: curl with -I (HEAD) does not return RateLimit-Limit or RateLimit-Remaining
        if [ -n "${_TAG}" ]; then
            echo "### Requesting '${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/manifests/${_TAG}'" >&2
            ${_curl} -H "Authorization: Bearer ${_TOKEN}" -H "Accept: application/json" "${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/manifests/${_TAG}" | python -m json.tool
        else
            echo "### Requesting Tags for '${_IMAGE}'" >&2
            #${_curl} -H "Authorization: Bearer ${_TOKEN}" "${_DOCKER_REGISTRY_URL%/}/v1/repositories/${_IMAGE}/tags"
            ${_curl} -H "Authorization: Bearer ${_TOKEN}" -H "Accept: application/json" "${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/tags/list" | python -m json.tool
        fi
    fi
fi