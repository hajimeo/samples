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

: ${_USER:=""}
: ${_PWD:=""}
: ${_IMAGE:="ratelimitpreview/test"}
: ${_TAG:="latest"}
: ${_TOKEN_SERVER_URL:="https://auth.docker.io/token?service=registry.docker.io"}
: ${_DOCKER_REGISTRY_URL:="https://registry-1.docker.io"}

_curl="curl -sf -D /dev/stderr --compressed"

echo "### Requesting '${_TOKEN_SERVER_URL}&scope=repository:${_IMAGE}:pull'" >&2
_TOKEN="$(if [ -n "${_USER}" ] && [ -z "${_PWD}" ]; then
    ${_curl} -u "${_USER}" "${_TOKEN_SERVER_URL}&scope=repository:${_IMAGE}:pull"
elif [ -n "${_USER}" ] && [ -z "${_PWD}" ]; then
    ${_curl} -sf -D ${_TMP%/}/_api_header_$$.out -u "${_USER}:${_PWD}" "${_TOKEN_SERVER_URL}&scope=repository:${_IMAGE}:pull"
else
    ${_curl} "${_TOKEN_SERVER_URL}&scope=repository:${_IMAGE}:pull"
fi | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a['token'])")"

if [ -n "${_TOKEN}" ]; then
    if which jwt &>/dev/null; then
        echo "### Decoding JWT" >&2
        jwt decode "${_TOKEN}"
    fi

    # NOTE: curl with -I (HEAD) does not return RateLimit-Limit or RateLimit-Remaining
    echo "### Requesting '${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/manifests/${_TAG}'" >&2
    ${_curl} -H "Authorization: Bearer ${_TOKEN}" "${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/manifests/${_TAG}" | python -m json.tool
fi
