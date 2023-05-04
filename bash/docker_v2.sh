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
: ${_USER:=""}      # admin
: ${_PWD:=""}       # admin123
: ${_IMAGE:="ratelimitpreview/test"}
: ${_TAG="latest"}
: ${_PATH="/v2/library/python/blobs/sha256:18264500740dfbb825d075853637a67404c1da0089bf54f2a5a4d37220da7be2"}
#: ${_DOCKER_REGISTRY_URL:="http://localhost:8081/repository/docker-proxy/"}
#: ${_TOKEN_SERVER_URL:="${_DOCKER_REGISTRY_URL%/}/v2/token"}
: ${_DOCKER_REGISTRY_URL:="https://registry-1.docker.io"}
: ${_TOKEN_SERVER_URL:="https://auth.docker.io/token?service=registry.docker.io"}

#_CURL="curl -s -f -v --compressed -L -k"
_CURL="curl -s -f -D /dev/stderr -L -k"
_TMP="/tmp"

function get_token() {
    local _token_server_url="${1:-"${_TOKEN_SERVER_URL}"}"
    local _user="${2:-"${_USER}"}"
    local _pwd="${3:-"${_PWD}"}"
    local _image="${4:-"${_IMAGE}"}"

    if [ -n "${_user}" ] && [ -z "${_pwd}" ]; then
        ${_CURL} -u "${_user}" "${_token_server_url}" --get --data-urlencode "scope=repository:${_image}:pull"
    elif [ -n "${_user}" ] && [ -n "${_pwd}" ]; then
        ${_CURL} -u "${_user}:${_pwd}" "${_token_server_url}" --get --data-urlencode "scope=repository:${_image}:pull"
    else
        ${_CURL} "${_token_server_url}" --get --data-urlencode "scope=repository:${_image}:pull"
    fi | sed -E 's/.+"token":"([^"]+)".+/\1/'
}

function decode_jwt() {
    # If 'jq': jq -R 'split(".") | .[1] | @base64d | fromjson' <<< "$1"
    local _jwt="$1"
    local _payload="$(echo -n "${_jwt}" | cut -d "." -f 2)"
    local _mod=$((${#_payload} % 4))
    if [ ${_mod} -eq 2 ]; then
        _payload="${_payload}"'=='
    elif [ $_mod -eq 3 ]; then
        _payload="${_payload}"'='
    fi
    echo "${_payload}" | tr '_-' '/+' | openssl enc -d -base64
}

function upload() {
    return
    # TODO: Implement upload (PUT?) test
    cat <<EOF
# TODO: not -d or --data (how about -T / --upload-file?)
curl -v -u admin:admin123 -H 'Content-Type: application/vnd.docker.distribution.manifest.v2+json' -X PUT http://localhost:5001/v2/alpine/manifests/sha256:e2e16842c9b54d985bf1ef9242a313f36b856181f188de21313820e177002501 --data-binary @e2e16842c9b54d985bf1ef9242a313f36b856181f188de21313820e177002501.json

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
    # TODO: the token server URL is decided by "www-authenticate: Bearer realm="https://dh1:5000/v2/token",service="https://dh1:5000/v2/token"
    echo "### Requesting '${_TOKEN_SERVER_URL}&scope=repository:${_IMAGE}:pull'" >&2
    _TOKEN="$(get_token)"

    if [ -n "${_TOKEN}" ]; then
        echo "### Got token" >&2
        echo "${_TOKEN}" >&2
        # For debugging (NOTE: Nexus's Docker bearer token can't be decoded)
        echo "### [DEBUG] Decoding JWT" >&2
        decode_jwt "${_TOKEN}" | python -m json.tool

        # NOTE: curl with -I (HEAD) does not return RateLimit-Limit or RateLimit-Remaining
        if [ -z "${_PATH#/}" ] && [ -n "${_IMAGE}" ] && [ -n "${_TAG}" ]; then
            echo "### Requesting '${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/manifests/${_TAG}'" >&2
            ${_CURL} -H "Authorization: Bearer ${_TOKEN}" -H "Accept: application/json" "${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/manifests/${_TAG}" | python -m json.tool
        fi

        #if [ -n "${_IMAGE}" ]; then
        #    echo "### Testing V1 API with search for '${_IMAGE}'" >&2
        #    ${_CURL} -H "Authorization: Bearer ${_TOKEN}" -H "Accept: application/json" "${_DOCKER_REGISTRY_URL%/}/v1/search?n=10&q=${_IMAGE}" | python -m json.tool
        #    echo "### Requesting Tags for '${_IMAGE}'" >&2
        #    #${_CURL} -H "Authorization: Bearer ${_TOKEN}" "${_DOCKER_REGISTRY_URL%/}/v1/repositories/${_IMAGE}/tags"
        #    ${_CURL} -H "Authorization: Bearer ${_TOKEN}" -H "Accept: application/json" "${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/tags/list" | python -m json.tool
        #fi

        if [ -n "${_PATH#/}" ]; then
            echo "### Requesting '${_DOCKER_REGISTRY_URL%/}/${_PATH#/}'" >&2
            # -H "Accept-Encoding: gzip,deflate"
            ${_CURL} -H "Authorization: Bearer ${_TOKEN}" -o ./layer_result.out "${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/manifests/${_TAG}"
            if [ -s ./layer_result.out ]; then
                sha256sum ./layer_result.out
            fi
        fi
    fi
fi
