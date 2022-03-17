# login_userId docker_registry_host_port1 docker_registry_host_port2 ...
# eg: "hosako" "https://dh1.standalone.localdomain:5000/" "http://node-nxrm-ha1.standalone.localdomain:8081/repository/docker-hosted" "http://node-nxrm-ha1.standalone.localdomain:18181/"

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

for _h in ${@:2}; do
  echo "# Testing ${_h} ..."
  _TOKEN="$(curl -s -k -u "$1" "${_h%/}/v2/token?account=$1&client_id=docker&offline_token=true" --get --data-urlencode "service=${_h%/}/v2/token" | _print_token)"
  echo "# Testing TOKEN: ${_TOKEN} with curl ${_h%/}/v2/"
  curl -D- -k -H "Authorization: Bearer ${_TOKEN}" -H "Accept: application/json" "${_h%/}/v2/"
done
