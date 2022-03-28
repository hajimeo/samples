# login_userId docker_registry_host_port1 docker_registry_host_port2 ...
# eg: "admin:admin123" "https://dh1.standalone.localdomain:5000/" "http://node-nxrm-ha1.standalone.localdomain:8081/repository/docker-hosted" "http://node-nxrm-ha1.standalone.localdomain:18181/"
for _h in ${@:2}; do
  _userid="${1%%:*}"
  echo "# Testing ${_h} with userId: ${_userid} ..."
  # --get --data-urlencode "service=${_h%/}/v2/token"
  _TOKEN="$(curl -s -k -u "$1" -L "${_h%/}/v2/token?account=${_userid}&client_id=docker&offline_token=true&service=${_h%/}/v2/token" | sed -E 's/.+"token":"([^"]+)".+/\1/')"
  echo "# Testing TOKEN: ${_TOKEN} with curl ${_h%/}/v2/"
  curl -D- -k -H "Authorization: Bearer ${_TOKEN}" -H "Accept: application/json" -L "${_h%/}/v2/"
done
