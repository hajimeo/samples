#!/usr/bin/env bash
# DOWNLOAD
#   curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_hdp_ha.sh
#

usage() {
    echo '
    source ./setup_hdp_ha.sh
    setup_nn_ha "http://ambari-host:8080/api/v1/clusters/YourClusterName" "nameservice" "first_nn_fqdn" "second_nn_fqdn" "jn1,jn2,jn3" "zk1,zk2,zk3"
    setup_rm_ha "http://ambari-host:8080/api/v1/clusters/YourClusterName" "first_rm_fqdn" "second_rm_fqdn"
'
}

### Global variable ###################
[ -z "${g_AMBARI_USER}" ] && g_AMBARI_USER='admin'
[ -z "${g_AMBARI_PASS}" ] && g_AMBARI_PASS='admin'

function setup_nn_ha() {
    local _ambari_cluster_api_url="${1}"    # eg: http://ho-ubu01:8080/api/v1/clusters/houbu01_1
    local _nameservice="${2}"
    local _first_nn="${3}"
    local _second_nn="${4}"        # TODO: currently new NN must be Secondary NameNode
    local _journal_nodes="${5}"    # eg: "node2.houbu01.localdomain,node3.houbu01.localdomain,node4.houbu01.localdomain"
    local _zookeeper_hosts="${6-$_first_nn}"

    local _cluster="`basename "${_ambari_cluster_api_url%/}"`"
    local _regex="^(http|https)://([^:]+):([0-9]+)/"
    [[ "${_ambari_cluster_api_url}" =~ ${_regex} ]] || return 101
    local _protocol="${BASH_REMATCH[1]}"
    local _host="${BASH_REMATCH[2]}"
    local _port="${BASH_REMATCH[3]}"
    local _qjournal="`echo "${_journal_nodes}" | sed 's/,/:8485;/g'`:8485"
    local _zkquorum="`echo "${_zookeeper_hosts}" | sed 's/,/:2181;/g'`:2181"

    # TODO: If kerberosed, it will ask admin principal to install rpm

    # Safemode and checkpointing
    ssh -qt root@${_first_nn} "su hdfs -l -c \"kinit -kt /etc/security/keytabs/hdfs.headless.keytab hdfs-${_cluster,,}\"" &>/dev/null
    ssh -qt root@${_first_nn} "su hdfs -l -c 'hdfs dfsadmin -safemode enter && hdfs dfsadmin -saveNamespace'" || return $?

    # Stop all
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services?" -X PUT --data '{"RequestInfo":{"context":"Stop all services","operation_level":{"level":"CLUSTER","cluster_name":"houbu01_1"}},"Body":{"ServiceInfo":{"state":"INSTALLED"}}}' | grep -q '^HTTP/1.1 2' || return $?
    # Wait until stop. Assuming ZOOKEEPER will be the last
    for _zk in `echo "${_zookeeper_hosts}" | sed 's/,/\n/g'`; do
        _ambari_wait_comp_state "${_ambari_cluster_api_url}" "${_zk}" "ZOOKEEPER_SERVER" "INSTALLED"
    done

    # Assign a namenode to a host
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/hosts" --data '{"RequestInfo":{"query":"Hosts/host_name='${_second_nn}'"},"Body":{"host_components":[{"HostRoles":{"component_name":"NAMENODE"}}]}}' | grep -q '^HTTP/1.1 2' || return $?
    # Install new namenode
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/host_components?" -X PUT --data '{"RequestInfo":{"context":"Install NameNode","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"},"query":"HostRoles/component_name=NAMENODE&HostRoles/host_name.in('${_second_nn}')&HostRoles/maintenance_state=OFF"},"Body":{"HostRoles":{"state":"INSTALLED"}}}' | grep -q '^HTTP/1.1 2' || return $?
    # Add a JournalNode
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services?ServiceInfo/service_name=HDFS" --data '{"components":[{"ServiceComponentInfo":{"component_name":"JOURNALNODE"}}]}' | grep -q '^HTTP/1.1 2' || return $?

    # Assign JournalNodes to hosts
    [ -z "$_journal_nodes" ] && return 1
    for _jn in `echo "$_journal_nodes" | sed 's/,/\n/g'`; do
        curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/hosts" --data '{"RequestInfo":{"query":"Hosts/host_name='${_jn}'"},"Body":{"host_components":[{"HostRoles":{"component_name":"JOURNALNODE"}}]}}' | grep -q '^HTTP/1.1 2' || return $?
    done
    # Install JournalNodes
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/host_components?" -X PUT --data '{"RequestInfo":{"context":"Install JournalNode","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"},"query":"HostRoles/component_name=JOURNALNODE&HostRoles/host_name.in('${_journal_nodes}')&HostRoles/maintenance_state=OFF"},"Body":{"HostRoles":{"state":"INSTALLED"}}}'

    # Update config
    # NOTE: grep -IRs -wE 'defaultFS|ha\.zookeeper|journalnode|nameservices|dfs\.ha|nn1|nn2|failover|shared\.edits' -A1 *
    _ambari_configs "core-site" '{"fs.defaultFS":"hdfs://'${_nameservice}'","ha.zookeeper.quorum":"'${_zkquorum}'"}' "${_host}" "${_port}" "${_protocol}" "${_cluster}" || return $?
    _ambari_configs "hdfs-site" '{"dfs.journalnode.edits.dir":"/hadoop/hdfs/journal","dfs.nameservices":"'${_nameservice}'","dfs.internal.nameservices":"'${_nameservice}'","dfs.ha.namenodes.'${_nameservice}'":"nn1,nn2","dfs.namenode.rpc-address.'${_nameservice}'.nn1":"'${_first_nn}':8020","dfs.namenode.rpc-address.'${_nameservice}'.nn2":"'${_second_nn}':8020","dfs.namenode.http-address.'${_nameservice}'.nn1":"'${_first_nn}':50070","dfs.namenode.http-address.'${_nameservice}'.nn2":"'${_second_nn}':50070","dfs.namenode.https-address.'${_nameservice}'.nn1":"'${_first_nn}':50470","dfs.namenode.https-address.'${_nameservice}'.nn2":"'${_second_nn}':50470","dfs.client.failover.proxy.provider.'${_nameservice}'":"org.apache.hadoop.hdfs.server.namenode.ha.ConfiguredFailoverProxyProvider","dfs.namenode.shared.edits.dir":"qjournal://'${_qjournal}'/'${_nameservice}'","dfs.ha.fencing.methods":"shell(/bin/true)","dfs.ha.automatic-failover.enabled":true}' "${_host}" "${_port}" "${_protocol}" "${_cluster}" || return $?

    # Install HDFS client
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/host_components?" -X PUT --data '{"RequestInfo":{"context":"Install HDFS Client","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"},"query":"HostRoles/component_name=HDFS_CLIENT&HostRoles/host_name.in('${_journal_nodes}')&HostRoles/maintenance_state=OFF"},"Body":{"HostRoles":{"state":"INSTALLED"}}}' | grep -q '^HTTP/1.1 2' || return $?
    # Start Journal nodes
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/host_components?" -X PUT --data '{"RequestInfo":{"context":"Start JournalNode","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"},"query":"HostRoles/component_name=JOURNALNODE&HostRoles/host_name.in('${_journal_nodes}')&HostRoles/maintenance_state=OFF"},"Body":{"HostRoles":{"state":"STARTED"}}}' | grep -q '^HTTP/1.1 2' || return $?
    # Maintenance mode on SECONDARY NameNode (if fails, keep going)
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/hosts/${_second_nn}/host_components/SECONDARY_NAMENODE" -X PUT --data '{"RequestInfo":{},"Body":{"HostRoles":{"maintenance_state":"ON"}}}'

    # Wait Journal Nodes starts
    for _jn in `echo "$_journal_nodes" | sed 's/,/\n/g'`; do
        _ambari_wait_comp_state "${_ambari_cluster_api_url}" "${_jn}" "JOURNALNODE" "STARTED"
    done
    # Initialize JournalNodes
    ssh -qt root@${_first_nn} "su hdfs -l -c 'hdfs namenode -initializeSharedEdits'" || return $?

    # Start required services to start HDFS, starting all components including clients...
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services?ServiceInfo/service_name.in(ZOOKEEPER)" -X PUT --data '{"RequestInfo":{"context":"Start required services ZOOKEEPER","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"}},"Body":{"ServiceInfo":{"state":"STARTED"}}}' | grep -q '^HTTP/1.1 2' || return $?
    # TODO: at this moment, starting AMBARI_INFRA, but probably RANGER too (and if fails, keep going)
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services?ServiceInfo/service_name.in(AMBARI_INFRA)" -X PUT --data '{"RequestInfo":{"context":"Start required services AMBARI_INFRA","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"}},"Body":{"ServiceInfo":{"state":"STARTED"}}}'

    # Starting NameNode
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/host_components?" -X PUT --data '{"RequestInfo":{"context":"Start NameNode","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"},"query":"HostRoles/component_name=NAMENODE&HostRoles/host_name.in('${_first_nn}')&HostRoles/maintenance_state=OFF"},"Body":{"HostRoles":{"state":"STARTED"}}}' | grep -q '^HTTP/1.1 2' || return $?

    _ambari_wait_comp_state "${_ambari_cluster_api_url}" "${_first_nn}" "NAMENODE" "STARTED"
    #NOTE: should i wait until exiting safemode?
    ssh -qt root@${_first_nn} "su hdfs -l -c 'hdfs zkfc -formatZK'" || return $?
    ssh -qt root@${_second_nn} "su hdfs -l -c \"kinit -kt /etc/security/keytabs/hdfs.headless.keytab hdfs-${_cluster,,}\"" &>/dev/null
    ssh -qt root@${_second_nn} "su hdfs -l -c 'hdfs namenode -bootstrapStandby'" || return $?

    # Starting new NN
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/host_components?" -X PUT --data '{"RequestInfo":{"context":"Start NameNode","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"},"query":"HostRoles/component_name=NAMENODE&HostRoles/host_name.in('${_second_nn}')&HostRoles/maintenance_state=OFF"},"Body":{"HostRoles":{"state":"STARTED"}}}'

    # Adding ZKFC. Assigning to hosts, installing and starting
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services?ServiceInfo/service_name=HDFS" --data '{"components":[{"ServiceComponentInfo":{"component_name":"ZKFC"}}]}' | grep -q '^HTTP/1.1 2' || return $?
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/hosts" --data '{"RequestInfo":{"query":"Hosts/host_name='${_second_nn}'|Hosts/host_name='${_first_nn}'"},"Body":{"host_components":[{"HostRoles":{"component_name":"ZKFC"}}]}}' | grep -q '^HTTP/1.1 2' || return $?
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/host_components?" -X PUT --data '{"RequestInfo":{"context":"Install ZKFailoverController","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"},"query":"HostRoles/component_name=ZKFC&HostRoles/host_name.in('${_second_nn}','${_first_nn}')&HostRoles/maintenance_state=OFF"},"Body":{"HostRoles":{"state":"INSTALLED"}}}' | grep -q '^HTTP/1.1 2' || return $?
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/host_components?" -X PUT --data '{"RequestInfo":{"context":"Start ZKFailoverController","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"},"query":"HostRoles/component_name=ZKFC&HostRoles/host_name.in('${_second_nn}','${_first_nn}')&HostRoles/maintenance_state=OFF"},"Body":{"HostRoles":{"state":"STARTED"}}}'

    # NOTE: Update Ranger config in here, if Ranger is installed

    # Delete unnecessary SECONDARY_NAMENODE. If fails, keep going (can fix this from UI)
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/hosts/${_second_nn}/host_components/SECONDARY_NAMENODE" -X DELETE

    # STOP HDFS, then START ALL
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services?ServiceInfo/service_name.in(HDFS)" -X PUT --data '{"RequestInfo":{"context":"Stop required services","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"}},"Body":{"ServiceInfo":{"state":"INSTALLED"}}}'
    # Wait until stop. Assuming ZKFC will be the last
    _ambari_wait_comp_state "${_ambari_cluster_api_url}" "${_first_nn}" "ZKFC" "INSTALLED"
    _ambari_wait_comp_state "${_ambari_cluster_api_url}" "${_second_nn}" "ZKFC" "INSTALLED"
    curl -sku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services" -X PUT --data '{"RequestInfo":{"context":"_PARSE_.START.ALL_SERVICES","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"}},"Body":{"ServiceInfo":{"state":"STARTED"}}}'
    echo " "
}

function setup_rm_ha() {
    local _ambari_cluster_api_url="${1}"    # eg: http://ho-ubu01:8080/api/v1/clusters/houbu01_1
    local _first_rm="${2}"
    local _second_rm="${3}"

    local _cluster="`basename "${_ambari_cluster_api_url%/}"`"
    local _regex="^(http|https)://([^:]+):([0-9]+)/"
    [[ "${_ambari_cluster_api_url}" =~ ${_regex} ]] || return 101
    local _protocol="${BASH_REMATCH[1]}"
    local _host="${BASH_REMATCH[2]}"
    local _port="${BASH_REMATCH[3]}"

    # Stop related services
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services?ServiceInfo/service_name.in(YARN,MAPREDUCE2,TEZ,HIVE,HBASE,PIG,ZOOKEEPER,AMBARI_INFRA,KAFKA,KNOX,RANGER,RANGER_KMS,SLIDER)" -X PUT --data '{"RequestInfo":{"context":"Stop required services","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"}},"Body":{"ServiceInfo":{"state":"INSTALLED"}}}'
    _ambari_wait_comp_state "${_ambari_cluster_api_url}" "${_first_rm}" "RESOURCEMANAGER" "INSTALLED"
    sleep 20

    # Assign RM to _second_nm
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/hosts" --data '{"RequestInfo":{"query":"Hosts/host_name='${_second_rm}'"},"Body":{"host_components":[{"HostRoles":{"component_name":"RESOURCEMANAGER"}}]}}'
    # Install RM
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/host_components?" -X PUT --data '{"RequestInfo":{"context":"Install ResourceManager","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"},"query":"HostRoles/component_name=RESOURCEMANAGER&HostRoles/host_name.in('${_second_rm}')&HostRoles/maintenance_state=OFF"},"Body":{"HostRoles":{"state":"INSTALLED"}}}'

    # Update config
    # NOTE: grep -IRs -wE 'yarn\.resourcemanager\.ha|yarn\.resourcemanager\.cluster-id|rm1|rm2' -A1 *
    _ambari_configs "yarn-site" '{"yarn.resourcemanager.ha.enabled":true","yarn.resourcemanager.ha.rm-ids":"rm1,rm2","yarn.resourcemanager.hostname.rm1":"'${_first_rm}'","yarn.resourcemanager.webapp.address.rm1":"'${_first_rm}':8088","yarn.resourcemanager.webapp.address.rm2":"'${_second_rm}':8088","yarn.resourcemanager.webapp.https.address.rm1":"'${_first_rm}':8090","yarn.resourcemanager.webapp.https.address.rm2":"'${_second_rm}':8090","yarn.resourcemanager.hostname.rm2":"'${_second_rm}'","yarn.resourcemanager.cluster-id":"yarn-cluster","yarn.resourcemanager.ha.automatic-failover.zk-base-path":"/yarn-leader-election"}' "${_host}" "${_port}" "${_protocol}" "${_cluster}" || return $?
    _ambari_configs "core-site" '{"hadoop.proxyuser.yarn.hosts":"'${_first_rm}','${_second_rm}'"}' "${_host}" "${_port}" "${_protocol}" "${_cluster}" || return $?

    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services?ServiceInfo/service_name.in(YARN,MAPREDUCE2,TEZ,HIVE,HBASE,PIG,ZOOKEEPER,AMBARI_INFRA,KAFKA,KNOX,RANGER,RANGER_KMS,SLIDER)" -X PUT --data '{"RequestInfo":{"context":"Start stopped services","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"}},"Body":{"ServiceInfo":{"state":"STARTED"}}}'
    #curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services?params/run_smoke_test=true" -X PUT --data '{"RequestInfo":{"context":"Start all services","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"}},"Body":{"ServiceInfo":{"state":"STARTED"}}}'
    echo " "
}

function _ambari_wait_comp_state() {
    local __doc__="Sleep until state becomes _state or timeout (_loop x _interval)"
    local _ambari_cluster_api_url="${1}"    # eg: http://ho-ubu01:8080/api/v1/clusters/houbu01_1
    local _host="${2}"
    local _comp="${3}"
    local _state="${4}"
    local _loop="${5-20}"
    local _interval="${6-10}"
    [ -z "${_state}" ] && return 1

    local _url="${_ambari_cluster_api_url%/}/hosts/${_host}/host_components/${_comp}?fields=HostRoles/state"
    sleep 1
    for _i in `seq 1 ${_loop}`; do
        curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_url}" | grep '"state" : "'${_state}'"' && break;
        sleep 10
    done
}

function _ambari_configs() {
    local __doc__="Wrapper function to update *multiple* configs with configs.py"
    local _type="$1"                # eg. "tez-site"
    local _dict="$2"                # eg. "{\"tez.runtime.shuffle.keep-alive.enabled\":\"true\"}"
    local _ambari_host="${3}"
    local _ambari_port="${4-8080}"
    local _protocol="${5-http}"
    local _cluster="${6}"

    if [ ! -s ./configs.py ]; then
        curl -s -O https://raw.githubusercontent.com/hajimeo/samples/master/misc/configs.py || return $?
    fi

    python ./configs.py -u "${g_AMBARI_USER}" -p "${g_AMBARI_PASS}" -l ${_ambari_host} -t ${_ambari_port} -s ${_protocol} -a get -n ${_cluster} -c ${_type} -f /tmp/${_type}_$$.json || return $?

    [ -z "${_dict}" ] && return 0

    echo "import json
a=json.load(open('/tmp/${_type}_$$.json', 'r'))
n=json.loads('"${_dict}"')
a['properties'].update(n)
f=open('/tmp/${_type}_updated_$$.json','w')
json.dump(a, f)
f.close()" > /tmp/configs_$$.py

    python /tmp/configs_$$.py || return $?
    python ./configs.py -u "${g_AMBARI_USER}" -p "${g_AMBARI_PASS}" -l ${_ambari_host} -t ${_ambari_port} -s ${_protocol} -a set -n ${_cluster} -c $_type -f /tmp/${_type}_updated_$$.json || return $?
    rm -f ./doSet_version*.json
}



### main ########################
if [ "$0" = "$BASH_SOURCE" ]; then
    usage
fi