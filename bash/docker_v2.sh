#!/usr/bin/env bash
###
# Testing Docker V2 API with curl

# Simpler test:
#   curl -D/dev/stderr -u "${_USER}:${_PWD}" -s "https://auth.docker.io/token?service=registry.docker.io" --get --data-urlencode "scope=repository:library/alpine:pull"
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

# Use 'export' to overwrite
: ${_USER:=""}      # admin
: ${_PWD:=""}       # admin123
#http://dh1:8081/repository/docker-proxy/v2/ratelimitpreview/test/manifests/latest
: ${_IMAGE:="ratelimitpreview/test"}
: ${_TAG="latest"}
#: ${_PATH="/v2/ratelimitpreview/test/blobs/sha256:edabd795951a0baa224f156b81ab1afa71c64c3cf10b1ded9225c2a6810f4a3d"}    # This path can be diff from Nexus's path
#: ${_DOCKER_REGISTRY_URL:="http://localhost:8081/repository/docker-proxy/"}
#: ${_TOKEN_SERVER_URL:="${_DOCKER_REGISTRY_URL%/}/v2/token"}
: ${_DOCKER_REGISTRY_URL:="https://registry-1.docker.io"}                           # Basically 'remoteUrl'
: ${_TOKEN_SERVER_URL:="https://auth.docker.io/token?service=registry.docker.io"}   #www-authenticate: Bearer realm="https://auth.docker.io/token",service="registry.docker.io"
: ${_CURL_OPTS:="-D /dev/stderr"}   # or -v -p -x http://proxyhost:port --proxy-basic -U proxyuser:proxypwd

_CURL="curl -sfLk --compressed ${_CURL_OPTS}"
_TMP="/tmp"
_UPLOAD_TEST="" # eg. "alpine"

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
    echo ""
}

function upload() {
    return  # TODO: Implement upload (PUT) test. not -d or --data (how about -T / --upload-file?)
    cat <<EOF
curl -sf -u admin:admin123 -H 'Content-Type: application/vnd.docker.distribution.manifest.v2+json' -X PUT http://localhost:5001/v2/alpine/manifests/sha256:e2e16842c9b54d985bf1ef9242a313f36b856181f188de21313820e177002501 --data-binary @e2e16842c9b54d985bf1ef9242a313f36b856181f188de21313820e177002501.json

for i in {1..50}; do
  _digest="$(curl -s -D/dev/stdout -u 'admin:admin123' -H 'Accept:application/vnd.docker.distribution.manifest.v2+json' "http://utm-ubuntu:8081/repository/docker-hosted/v2/alpine_hosted/manifests/latest" -o./latest | sed -n -E '/^Docker-Content-Diges/ s/^Docker-Content-Digest: (.+)$/\1/p')"
  curl -sf -D- -u admin:admin123 -X DELETE "http://utm-ubuntu:8081/repository/docker-hosted/v2/alpine_hosted/manifests/${_digest}";
  curl -sf -D- -u admin:admin123 -H 'Content-Type: application/vnd.docker.distribution.manifest.v2+json' -T ./latest "http://utm-ubuntu:8081/repository/docker-hosted/v2/alpine_hosted/manifests/latest" -o/tmp/last.out || break;
  _digest37="$(curl -s -D/dev/stdout -u 'admin:admin123' -H 'Accept:application/vnd.docker.distribution.manifest.v2+json' "http://utm-ubuntu:8081/repository/docker-hosted/v2/alpine_hosted_37/manifests/latest" -o./latest37 | sed -n -E '/^Docker-Content-Diges/ s/^Docker-Content-Digest: (.+)$/\1/p')"
  curl -sf -D- -u admin:admin123 -X DELETE "http://utm-ubuntu:8081/repository/docker-hosted/v2/alpine_hosted_37/manifests/${_digest37}";
  curl -sf -D- -u admin:admin123 -H 'Content-Type: application/vnd.docker.distribution.manifest.v2+json' -T ./latest37 "http://utm-ubuntu:8081/repository/docker-hosted/v2/alpine_hosted_37/manifests/latest" -o/tmp/last.out || break;
  sleep 0.5
done

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

main() {
    # NOTE: Token server URL is decided by https://dh1:5000/v2/ then the header "HTTP/1.1 401 Unauthorized" and "www-authenticate: Bearer realm="https://dh1:5000/v2/token",service="https://dh1:5000/v2/token"
    echo "### Requesting '${_TOKEN_SERVER_URL}&scope=repository:${_IMAGE}:pull'" >&2
    _TOKEN="$(get_token)"

    if [ -n "${_TOKEN}" ]; then
        echo "### Got token (length: $(echo "${_TOKEN}" | wc -c))" >&2
        #echo "${_TOKEN}" >&2
        # For debugging (NOTE: Nexus's Docker bearer token can't be decoded)
        echo "### [DEBUG] Decoding JWT" >&2
        decode_jwt "${_TOKEN}" || return $?

        # NOTE: curl with -I (HEAD) does not return RateLimit-Limit or RateLimit-Remaining
        if [ -n "${_IMAGE}" ] && [ -n "${_TAG}" ]; then
            echo "### Requesting '${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/manifests/${_TAG}'" >&2
            ${_CURL} -H "Authorization: Bearer ${_TOKEN}" -H "Accept: application/json" "${_DOCKER_REGISTRY_URL%/}/v2/${_IMAGE}/manifests/${_TAG}"
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
                echo "### sha256 of ${_PATH#/}" >&2
                sha256sum ${_TMP%/}/path_result.out
            fi
        fi

        if [ -n "${_UPLOAD_TEST}" ]; then
            echo "### Requesting POST '${_DOCKER_REGISTRY_URL%/}/v2/${_UPLOAD_TEST}/blobs/uploads/'" >&2
            # TODO: Bearer is send when "Allow anonymous docker pull" is enabled (forceBasicAuth is false), so need some check
            ${_CURL} -H "Authorization: Bearer ${_TOKEN}" -X POST "${_DOCKER_REGISTRY_URL%/}/v2/${_UPLOAD_TEST}/blobs/uploads/"
            #${_CURL} -u "${_USER}:${_PWD}" -X POST "${_DOCKER_REGISTRY_URL%/}/v2/${_UPLOAD_TEST}/blobs/uploads/"
            # Then gets "Location:" header to upload with -X PATCH
        fi
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main
fi