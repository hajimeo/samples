#!/usr/bin/env bash

if [ ! -x /var/lib/ambari-server/resources/scripts/configs.py ]; then
    echo "This script requires /var/lib/ambari-server/resources/scripts/configs.py"
    exit 1
fi

_CLUSTER="$1"
_ADM_PWD="$2"

if [ -z "$_CLUSTER" ]; then
    echo "Cluster name is missing."
    echo "$BASH_SOURCE <clsuter name> <admin password>"
    exit 1
fi
if [ -z "$_ADM_PWD" ]; then
    echo "Ambari 'admin' password is missing."
    echo "$BASH_SOURCE <clsuter name> <admin password>"
    exit 1
fi

_CMD="/var/lib/ambari-server/resources/scripts/configs.py -a set -l localhost -n ${_CLUSTER} -u admin -p ${_ADM_PWD}"
${_CMD} -c yarn-site -k yarn.scheduler.minimum-allocation-mb -v 256

${_CMD} -c tez-site -k tez.am.resource.memory.mb -v 512
${_CMD} -c tez-site -k tez.task.resource.memory.mb -v 512
${_CMD} -c tez-site -k tez.runtime.io.sort.mb -v 256
${_CMD} -c tez-site -k tez.runtime.unordered.output.buffer.size-mb -v 48

${_CMD} -c hive-site -k hive.tez.container.size -v 512
${_CMD} -c hive-site -k tez.am.resource.memory.mb -v 512

${_CMD} -c hive-env -k hive.heapsize -v 1024
${_CMD} -c hive-env -k hive.metastore.heapsize -v 512

${_CMD} -c core-site -k hadoop.proxyuser.hcat.hosts -v '*'
${_CMD} -c core-site -k hadoop.proxyuser.hive.hosts -v '*'
${_CMD} -c core-site -k hadoop.proxyuser.root.hosts -v '*'

echo "$(date +"%Y-%m-%d %H:%M:%S,%3N") INFO Restarting all required services..." 1>&2
curl -s -u admin:"${_ADM_PWD}" -H "X-Requested-By:ambari" "http://`hostname -f`:8080/api/v1/clusters/${_CLUSTER}/requests" -X POST --data '{"RequestInfo":{"command":"RESTART","context":"Restart all required services","operation_level":"host_component"},"Requests/resource_filters":[{"hosts_predicate":"HostRoles/stale_configs=true"}]}'

rm -f ./doSet_*.json
