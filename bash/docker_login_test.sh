# docker_login login_userId docker_registry_host_port1
#docker_login "admin" "https://nxrm3helmha-docker-k8s.standalone.localdomain/"
function docker_login() {
  _userid="${1%%:*}"
  _h="${2}"
  echo "# Accessing ${_h%/}/v2/ (expecting 401) ..."
  curl -D/dev/stderr -sSf -k -H "Accept: application/json" -L "${_h%/}/v2/"
  echo "# Generating token from host:${_h} with userId:${_userid} ..."
  # --get --data-urlencode "service=${_h%/}/v2/token"
  _TOKEN="$(curl -D/dev/stderr -sSf -k -u "$1" -L "${_h%/}/v2/token?account=${_userid}&client_id=docker&offline_token=true&service=${_h%/}/v2/token" | sed -E 's/.+"token":"([^"]+)".+/\1/')"
  echo "# Testing TOKEN:${_TOKEN} by requesting to ${_h%/}/v2/"
  curl -D/dev/stderr -sSf -k -H "Authorization: Bearer ${_TOKEN}" -H "Accept: application/json" -L "${_h%/}/v2/"
}

# Simple test. In case the Index is REGISTRY
# curl -sS -I "https://localhost:12346/v2/" | grep 'WWW-Authenticate'
#   WWW-Authenticate: Bearer realm="http://localhost:8081/v2/token",service="http://localhost:8081/v2/token"
_TOKEN="$(curl -D/dev/stderr -s "${realm}" --get --data-urlencode "scope=repository:elasticsearch/elasticsearch:pull" --data-urlencode "service=${service}")"
# Returns 401
curl -D/dev/stderr -sSf -k -H "Authorization: Bearer ${_TOKEN}" -H "Accept: application/json" -L "http://localhost:12345/v2/"

# SELECT * FROM api_key_v2 WHERE username ='anonymous' and domain = 'DockerToken';