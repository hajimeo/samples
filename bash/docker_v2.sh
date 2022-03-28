#!/usr/bin/env bash
# https://docs.docker.com/registry/spec/api/
#
# https://success.docker.com/article/how-do-i-authenticate-with-the-v2-api
# https://www.docker.com/blog/checking-your-current-docker-pull-rate-limits-and-status/
# https://docs.docker.com/registry/spec/auth/token/
#
# Require: python and jwt (brew tap mike-engel/jwt-cli && brew install jwt-cli)
#
# Simpler test:
#   curl -I -u "${_USER}:${_PWD}" -L -k "${_DOCKER_REGISTRY_URL%/}/v2/"
#
# To get the image names, then tags, then a tag (json):
#   curl -u "${_USER}:${_PWD}" -L -k "${_DOCKER_REGISTRY_URL%/}/v2/_catalog"
#   curl -u "${_USER}:${_PWD}" -L -k "${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/tags/list"  # NEXUS-26037 if proxy
#   curl -u "${_USER}:${_PWD}" -L -k "${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/manifests/${_TAG}"
#

# Use 'export' to overwrite
: ${_USER:=""}
: ${_PWD:=""}
: ${_IMAGE:="ratelimitpreview/test"}
: ${_TAG="latest"}
: ${_DOCKER_REGISTRY_URL:="http://dh1.standalone.localdomain:8081/repository/docker-proxy/"}
: ${_TOKEN_SERVER_URL:="${_DOCKER_REGISTRY_URL%/}/v2/token"}
#: ${_DOCKER_REGISTRY_URL:="https://registry-1.docker.io"}
#: ${_TOKEN_SERVER_URL:="https://auth.docker.io/token?service=registry.docker.io"}

: ${_TMP:="/tmp"}

#_curl="curl -v -f -D /dev/stderr --compressed -k"
_curl="curl -s -f -D /dev/stderr --compressed -k"

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
    fi | sed -E 's/.+"token":"([^"]+)".+/\1/'
}

function upload() {
    # TODO: Implement upload (PUT?) test
    cat << EOF
# Authentication check
DEBU[0000] GET https://node-nxrm-ha1.standalone.localdomain:18183/v2/
DEBU[0000] Ping https://node-nxrm-ha1.standalone.localdomain:18183/v2/ status 401
# Data / layers check
#       podman inspect node-nxrm-ha1.standalone.localdomain:18183/alpine:3.13
            "Layers": [
                "sha256:b2d5eeeaba3a22b9b8aa97261957974a6bd65274ebd43e1d81d0a7b8b752b116"
            ]
DEBU[0000] HEAD https://node-nxrm-ha1.standalone.localdomain:18183/v2/alpine/blobs/sha256:b2d5eeeaba3a22b9b8aa97261957974a6bd65274ebd43e1d81d0a7b8b752b116

DEBU[0000] Trying to reuse cached location sha256:d3470daaa19c14ddf4ec500a3bb4f073fa9827aa4f19145222d459016ee9193e compressed with gzip in node-nxrm-ha1.standalone.localdomain:18183/alpine
DEBU[0000] HEAD https://node-nxrm-ha1.standalone.localdomain:18183/v2/alpine/blobs/sha256:d3470daaa19c14ddf4ec500a3bb4f073fa9827aa4f19145222d459016ee9193e

DEBU[0000] POST https://node-nxrm-ha1.standalone.localdomain:18183/v2/alpine/blobs/uploads/
DEBU[0000] HEAD https://node-nxrm-ha1.standalone.localdomain:18183/v2/alpine/blobs/sha256:6dbb9cc54074106d46d4ccb330f2a40a682d49dda5f4844962b7dce9fe44aaec
DEBU[0000] POST https://node-nxrm-ha1.standalone.localdomain:18183/v2/alpine/blobs/uploads/
DEBU[0000] PATCH https://node-nxrm-ha1.standalone.localdomain:18183/v2/alpine/blobs/uploads/232cde37-563d-4a28-aec0-245a6acb5999
DEBU[0000] PUT https://node-nxrm-ha1.standalone.localdomain:18183/v2/alpine/manifests/3.13
EOF
}

if [ "$0" = "$BASH_SOURCE" ]; then
    echo "### Requesting '${_TOKEN_SERVER_URL}&scope=repository:${_IMAGE}:pull'" >&2
    _TOKEN="$(get_token)"

    if [ -n "${_TOKEN}" ]; then
        echo "### Got token" >&2
        echo "${_TOKEN}" >&2
        # For debugging (NOTE: Nexus's token can't be decoded)
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