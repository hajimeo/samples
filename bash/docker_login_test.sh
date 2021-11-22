# hosako "https://dh1.standalone.localdomain:5000/" "http://node-nxrm-ha1.standalone.localdomain:8081/repository/docker-hosted" "http://node-nxrm-ha1.standalone.localdomain:18181/"

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
  _TOKEN="$(curl -s -k -u "$1" "${_h%/}/v2/token?account=$1&client_id=docker&offline_token=true&service=https%3A%2F%2Fdocker-dgsi.rec.etat-ge.ch%2Fv2%2Ftoken" | _print_token)"
  echo "# TODKEN: ${_TOKEN}"
  curl -I -k -H "Authorization: Bearer ${_TOKEN}" -H "Accept: application/json" "${_h%/}/v2/"
done
