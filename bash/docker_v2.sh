#!/usr/bin/env bash
###
# Testing Docker V2 API with curl

# Simpler test:
#   curl -D/dev/stderr -u "${_USER}:${_PWD}" -s "https://auth.docker.io/token" --get --data-urlencode "scope=repository:library/alpine:pull"  --data-urlencode "service=registry.docker.io"
#   _TOKEN="$(curl -u admin "${_DOCKER_REGISTRY_URL%/}/v2/token" --get --data-urlencode "account=admin&scope=repository:alpine:pull,push&service=${_DOCKER_REGISTRY_URL%/}" | sed -E 's/.+"token":"([^"]+)".+/\1/')"
#
#   curl -I -u "${_USER}:${_PWD}" -L -k "${_DOCKER_REGISTRY_URL%/}/v2/"
# To get the image names, then tags, then a tag (json):
#   curl -u "${_USER}:${_PWD}" -L -k "${_DOCKER_REGISTRY_URL%/}/v2/_catalog"
#   curl -u "${_USER}:${_PWD}" -L -k "${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/tags/list"  # NEXUS-26037 if proxy
#   curl -u "${_USER}:${_PWD}" -L -k "${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/manifests/${_TAG}"
#
# Ref:
#   https://docs.docker.com/registry/spec/api/
#   https://success.docker.com/article/how-do-i-authenticate-with-the-v2-api
#   https://www.docker.com/blog/checking-your-current-docker-pull-rate-limits-and-status/
#   https://docs.docker.com/registry/spec/auth/token/
#
# NOTE: registry.hub.docker.com
# Misc. testing curl commands
#curl -H 'Forwarded: proto=https;host=docker.example.com:443' http://nexus.example.com:8081/repository/docker-repo/v2/ -v
#curl -H 'Host:docker.example.com:443' http://nexus.example.com:8081/repository/docker-repo/v2/ -v
#curl -H 'Host:docker.example.com' -H 'x-forwarded-port:443' http://nexus.example.com:8081/repository/docker-repo/v2/ -v


# Use 'export' to overwrite
: ${_USER:=""}      # admin
: ${_PWD:=""}       # admin123
#http://dh1:8081/repository/docker-proxy/v2/ratelimitpreview/test/manifests/latest
: ${_IMAGE:="library/alpine"}   # ratelimitpreview/test
: ${_TAG="3.18"}                # latest
: ${_DOCKER_METHOD="pull"}
# Require export _IMAGE="library/alpine" _TAG="3.18"
: ${_PATH:="/v2/library/alpine/blobs/sha256:de2b9975f8fd4ab0d5ea39f52592791fadff62c0592a6e7db5640dc0d6469a01"}
#: ${_PATH="/v2/ratelimitpreview/test/blobs/sha256:edabd795951a0baa224f156b81ab1afa71c64c3cf10b1ded9225c2a6810f4a3d"}    # This path can be diff from Nexus's path
: ${_UPLOAD_TEST:=""}   # eg. "alpine"

#: ${_DOCKER_REGISTRY_URL:="http://localhost:8081/repository/docker-proxy/"}
#: ${_TOKEN_SERVER_URL:="${_DOCKER_REGISTRY_URL%/}/v2/token"}
: ${_DOCKER_REGISTRY_URL:="https://registry-1.docker.io"}                           # Basically 'remoteUrl'
: ${_TOKEN_SERVER_URL:="https://auth.docker.io/token?service=registry.docker.io"}   #www-authenticate: Bearer realm="https://auth.docker.io/token",service="registry.docker.io"
: ${_CURL_OPTS:="-D /dev/stderr"}   # if proxy is required, use export ALL_PROXY=http://proxyuser:proxypwd@dh1:28081/ (http_proxy, https_proxy)


_CURL="curl -sfLk --compressed ${_CURL_OPTS}"
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

# If 'jq': jq -R 'split(".") | .[1] | @base64d | fromjson' <<< "$1"
function decode_jwt() {
    local _jwt="$1"
    local _payload="$(echo -n "${_jwt}" | cut -d "." -f 2)"
    local _mod=$((${#_payload} % 4))
    if [ ${_mod} -eq 2 ]; then
        _payload="${_payload}"'=='
    elif [ $_mod -eq 3 ]; then
        _payload="${_payload}"'='
    fi
    echo "${_payload}" | tr '_-' '/+' | openssl enc -d -base64 || return $?
    echo "" >&2
}

main() {
    # NOTE: Token server URL is decided by https://dh1:5000/v2/ then the header "HTTP/1.1 401 Unauthorized" and "www-authenticate: Bearer realm="https://dh1:5000/v2/token",service="https://dh1:5000/v2/token"
    # example: token?service=registry.docker.io&scope=repository%3Alibrary%2Falpine%3Apull
    echo "### Requesting '${_TOKEN_SERVER_URL}&scope=repository:${_IMAGE}:${_DOCKER_METHOD}'" >&2
    _TOKEN="$(get_token)"

    if [ -n "${_TOKEN}" ]; then
        echo "### Got token (length: $(echo "${_TOKEN}" | wc -c)) for scope=repository:${_IMAGE}:${_DOCKER_METHOD}" >&2
        #echo "${_TOKEN}" >&2
        # For debugging (NOTE: Nexus's Docker bearer token can't be decoded)
        echo "### [DEBUG] Decoding JWT" >&2
        decode_jwt "${_TOKEN}" || return $?

        # NOTE: curl with -I (HEAD) does not return RateLimit-Limit or RateLimit-Remaining
        if [ -n "${_IMAGE}" ] && [ -n "${_TAG}" ]; then
            echo "### Requesting '${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/manifests/${_TAG}'" >&2
            ${_CURL} -H "Authorization: Bearer ${_TOKEN}" -o ${_TMP%/}/manifest_result.json -H "Accept: application/json" "${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/manifests/${_TAG}" || return $?
            if [ -s ${_TMP%/}/manifest_result.json ]; then
                if type python &>/dev/null; then
                    echo "### [DEBUG] Parsing JSON | head -n10" >&2
                    python -m json.tool ${_TMP%/}/manifest_result.json | head -n10
                else
                    echo "### [DEBUG] JSON" >&2
                    ls -l ${_TMP%/}/manifest_result.json
                fi
            fi
            echo "" >&2
        fi

        #if [ -n "${_IMAGE}" ]; then
        #    echo "### Testing V1 API with search for '${_IMAGE}'" >&2
        #    ${_CURL} -H "Authorization: Bearer ${_TOKEN}" -H "Accept: application/json" "${_DOCKER_REGISTRY_URL%/}/v1/search?n=10&q=${_IMAGE}"
        #    echo "### Requesting Tags for '${_IMAGE}'" >&2
        #    #${_CURL} -H "Authorization: Bearer ${_TOKEN}" "${_DOCKER_REGISTRY_URL%/}/v1/repositories/${_IMAGE}/tags"
        #    ${_CURL} -H "Authorization: Bearer ${_TOKEN}" -H "Accept: application/json" "${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/tags/list"
        #fi

        if [ -n "${_PATH#/}" ]; then
            echo "### Requesting '${_DOCKER_REGISTRY_URL%/}/${_PATH#/}'" >&2
            # -H "Accept-Encoding: gzip,deflate"
            ${_CURL} -H "Authorization: Bearer ${_TOKEN}" -o ${_TMP%/}/path_result.out "${_DOCKER_REGISTRY_URL%/}/${_PATH#/}"
            if [ -s ${_TMP%/}/path_result.out ]; then
                echo "### sha256 of ${_TMP%/}/path_result.out" >&2
                sha256sum ${_TMP%/}/path_result.out
            fi
            echo "" >&2
        fi

        # TODO: probably doesn't work
        if [ -n "${_UPLOAD_TEST}" ]; then
            echo "### Requesting POST '${_DOCKER_REGISTRY_URL%/}/v2/${_UPLOAD_TEST}/blobs/uploads/'" >&2
            # TODO: Bearer is send when "Allow anonymous docker pull" is enabled (forceBasicAuth is false), so need some check
            ${_CURL} -H "Authorization: Bearer ${_TOKEN}" -X POST "${_DOCKER_REGISTRY_URL%/}/v2/${_UPLOAD_TEST}/blobs/uploads/"
            #${_CURL} -u "${_USER}:${_PWD}" -X POST "${_DOCKER_REGISTRY_URL%/}/v2/${_UPLOAD_TEST}/blobs/uploads/"
            # Then gets "Location:" header to upload with -X PATCH
            echo "" >&2
        fi
    fi

    echo "# Completed." >&2
}


function upload() {
    return  # TODO: Implement upload (PUT) test. not -d or --data (how about -T / --upload-file?)
    cat <<EOF
# example upload requests:
DEBU[0000] Trying to reuse cached location sha256:d3470daaa19c14ddf4ec500a3bb4f073fa9827aa4f19145222d459016ee9193e compressed with gzip in node-nxrm-ha1.standalone.localdomain:18183/alpine
DEBU[0000] HEAD https://node-nxrm-ha1.standalone.localdomain:18183/v2/alpine/blobs/sha256:6dbb9cc54074106d46d4ccb330f2a40a682d49dda5f4844962b7dce9fe44aaec
DEBU[0000] POST https://node-nxrm-ha1.standalone.localdomain:18183/v2/alpine/blobs/uploads/
    # probably no payload but with below headers
    Content-Length: 0
    Authorization: Bearer DockerToken.cdbbae08-ae4e-3551-8522-a2e0c3857e0c   <<< if allow anonymous pull
    Docker-Distribution-Api-Version: registry/2.0
    Accept-Encoding: gzip
    # Then gets:
    Range: 0-0
    Docker-Distribution-Api-Version: registry/2.0
    Docker-Upload-UUID: e4efc743-cf71-4524-b524-a87db6655965
    Location: /v2/alpine/blobs/uploads/e4efc743-cf71-4524-b524-a87db6655965
    Content-Length: 0

DEBU[0000] PATCH https://node-nxrm-ha1.standalone.localdomain:18183/v2/alpine/blobs/uploads/232cde37-563d-4a28-aec0-245a6acb5999
DEBU[0000] PUT https://node-nxrm-ha1.standalone.localdomain:18183/v2/alpine/manifests/3.13
EOF
}



if [ "$0" = "$BASH_SOURCE" ]; then
    main
fi