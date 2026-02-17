# docker_login login_userId docker_registry_host_port1
#docker_login "admin" "https://local.standalone.localdomain:18182/"
#docker_login "admin" "https://nxrm3helmha-docker-k8s.standalone.localdomain/"
#docker_login "" "http://localhost:8081/" "docker-proxy/library/hello-world:latest"
function docker_login() {
  local _userid="${1%%:*}"  # Empty if anonymous
  local _h="${2}"
  local _p="${3}"
  echo "# Accessing ${_h%/}/v2/ (expecting 401) ..."
  local _s="$(curl -D- -sSf -k -H "Accept: application/json" -L "${_h%/}/v2/" | grep 'WWW-Authenticate' | sed 's/.*service="\([^"]*\/v2\/\).*/\1/')"
  echo "# Generating token from host:${_s} with userId:${_userid} ..."
  if [ -n "${_userid}" ];then
    _TOKEN="$(curl -D/dev/stderr -sSf -k -u "$1" -L "${_s:-"${_h%/}/v2/"}token?account=${_userid}&client_id=docker&offline_token=true&service=${_h%/}/v2/token" | sed -E 's/.+"token":"([^"]+)".+/\1/')"
  else
    # TODO: Should use realm?
    _TOKEN="$(curl -D/dev/stderr -sSf -k -L "${_s:-"${_h%/}/v2/"}token" --get --data-urlencode "scope=repository:${_p#/}:pull&service=${_s}" | sed -E 's/.+"token":"([^"]+)".+/\1/')"
  fi
  [ -n "${_p}" ] && _p="$(echo "${_p}" | sed 's/:\([^:]*\)$/\/manifests\/\1/')"
  echo "# Testing TOKEN:${_TOKEN} against ${_h%/}/v2/${_p#/}" # Not ${_s}
  curl -D/dev/stderr -sSf -k -H "Authorization: Bearer ${_TOKEN}" -H "Accept: application/json" -k -L "${_h%/}/v2/${_p#/}" -o /tmp/docker_login_test_output.json || return $?
  echo "# Output saved into /tmp/docker_login_test_output.json"
}




curl -D/dev/stderr -sSf -k -H "Authorization: Bearer ${_TOKEN}" -H "Accept: application/json" -k -L "http://localhost:8081/v2/docker-proxy/library/hello-world/manifests/latest"

cat <<'EOF'>/dev/null
# For anonymous (requres global anonymous, DockerToken, and forceBasicAuth=false)
DEBU[0000] GET http://localhost:8081/v2/
# scope=repository:docker-proxy/library/hello-world:pull&service=http://localhost:8081/repository/docker-proxy/v2/token
DEBU[0000] GET http://localhost:8081/repository/docker-proxy/v2/token?scope=repository%3Adocker-proxy%2Flibrary%2Fhello-world%3Apull&service=http%3A%2F%2Flocalhost%3A8081%2Frepository%2Fdocker-proxy%2Fv2%2Ftoken

$ curl -I "http://localhost:8081/v2/"
HTTP/1.1 401 Unauthorized
Server: Nexus/3.87.1-01 (PRO)
X-Content-Type-Options: nosniff
Content-Security-Policy: sandbox allow-forms allow-modals allow-popups allow-presentation allow-scripts allow-top-navigation
X-XSS-Protection: 0
Docker-Distribution-Api-Version: registry/2.0
WWW-Authenticate: Bearer realm="http://localhost:8081/repository/docker-proxy/v2/token",service="http://localhost:8081/repository/docker-proxy/v2/token"
Content-Type: application/json
Content-Length: 113


EOF

# Simple test. In case the Index is REGISTRY
# curl -sS -I "https://localhost:12346/v2/" | grep 'WWW-Authenticate'
#   WWW-Authenticate: Bearer realm="http://localhost:8081/v2/token",service="http://localhost:8081/v2/token"
_TOKEN="$(curl -D/dev/stderr -s "${realm}" --get --data-urlencode "scope=repository:elasticsearch/elasticsearch:pull" --data-urlencode "service=${service}")"
# Returns 401
curl -D/dev/stderr -sSf -k -H "Authorization: Bearer ${_TOKEN}" -H "Accept: application/json" -L "http://localhost:12345/v2/"

# SELECT * FROM api_key_v2 WHERE username ='anonymous' and domain = 'DockerToken';