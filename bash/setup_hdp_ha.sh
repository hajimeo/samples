#!/usr/bin/env bash
### Global variable ###################
g_AMBARI_USER='admin'
g_AMBARI_PASS='admin'

usage() {
    echo '
    source ./setup_hdp_ha.sh
    setup_nn_ha "http://ambari-host:8080/api/v1/clusters/YourClusterName" "nameservice" "first_nn_fqdn" "second_nn_fqdn" "jn1,jn2,jn3"
    setup_rm_ha "http://ambari-host:8080/api/v1/clusters/YourClusterName" "first_rm_fqdn" "second_rm_fqdn"
'
}

function setup_nn_ha() {
    local _ambari_cluster_api_url="${1}"    # eg: http://ho-ubu01:8080/api/v1/clusters/houbu01_1
    local _nameservice="${2}"
    local _first_nn="${3}"
    local _second_nn="${4}"        # TODO: currently new NN must be Secondary NameNode
    local _journal_nodes="${5}"             # eg: "node2.houbu01.localdomain,node3.houbu01.localdomain,node4.houbu01.localdomain"
    local _cluster="`basename "${_ambari_cluster_api_url%/}"`"

    # Safemode and checkpointing
    ssh -qt root@${_first_nn} "su hdfs -l -c \"kinit -kt /etc/security/keytabs/hdfs.headless.keytab hdfs-${_cluster,,}\"" &>/dev/null
    ssh -qt root@${_first_nn} "su hdfs -l -c 'hdfs dfsadmin -safemode enter && hdfs dfsadmin -saveNamespace'" || return $?

    # Stop all
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services?" -X PUT --data '{"RequestInfo":{"context":"Stop all services","operation_level":{"level":"CLUSTER","cluster_name":"houbu01_1"}},"Body":{"ServiceInfo":{"state":"INSTALLED"}}}' | grep -q '^HTTP/1.1 2' || return $?
    # Wait until stop. TODO: Assuming ZOOKEEPER will be the last
    _ambari_wait_comp_state "${_ambari_cluster_api_url}" "ZOOKEEPER" "ZOOKEEPER_SERVER" "INSTALLED"

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

    local _regex="^(http|https)://([^:]+):([0-9]+)/"
    [[ "${_ambari_cluster_api_url}" =~ ${_regex} ]] || return 101
    local _protocol="${BASH_REMATCH[1]}"
    local _host="${BASH_REMATCH[2]}"
    local _port="${BASH_REMATCH[3]}"
    local _qjournal="`echo "$_journal_nodes" | sed 's/,/:8485;/g'`:8485"

    # Update config
    _ambari_configs "core-site" '{"fs.defaultFS":"hdfs://'${_nameservice}'","ha.zookeeper.quorum":"'${_first_nn}':2181"}' "${_host}" "${_port}" "${_protocol}" "${_cluster}" || return $?
    _ambari_configs "hdfs-site" '{"dfs.journalnode.edits.dir":"/hadoop/hdfs/journal","dfs.nameservices":"'${_nameservice}'","dfs.internal.nameservices":"'${_nameservice}'","dfs.ha.namenodes.'${_nameservice}'":"nn1,nn2","dfs.namenode.rpc-address.'${_nameservice}'.nn1":"'${_first_nn}':8020","dfs.namenode.rpc-address.'${_nameservice}'.nn2":"'${_second_nn}':8020","dfs.namenode.http-address.'${_nameservice}'.nn1":"'${_first_nn}':50070","dfs.namenode.http-address.'${_nameservice}'.nn2":"'${_second_nn}':50070","dfs.namenode.https-address.'${_nameservice}'.nn1":"'${_first_nn}':50470","dfs.namenode.https-address.'${_nameservice}'.nn2":"'${_second_nn}':50470","dfs.client.failover.proxy.provider.'${_nameservice}'":"org.apache.hadoop.hdfs.server.namenode.ha.ConfiguredFailoverProxyProvider","dfs.namenode.shared.edits.dir":"qjournal://'${_qjournal}'/'${_nameservice}'","dfs.ha.fencing.methods":"shell(/bin/true)","dfs.ha.automatic-failover.enabled":true}' "${_host}" "${_port}" "${_protocol}" "${_cluster}" || return $?

    # Install HDFS client
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/host_components?" -X PUT --data '{"RequestInfo":{"context":"Install HDFS Client","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"},"query":"HostRoles/component_name=HDFS_CLIENT&HostRoles/host_name.in('${_journal_nodes}')&HostRoles/maintenance_state=OFF"},"Body":{"HostRoles":{"state":"INSTALLED"}}}' | grep -q '^HTTP/1.1 2' || return $?
    # Start Journal nodes
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/host_components?" -X PUT --data '{"RequestInfo":{"context":"Start JournalNode","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"},"query":"HostRoles/component_name=JOURNALNODE&HostRoles/host_name.in('${_journal_nodes}')&HostRoles/maintenance_state=OFF"},"Body":{"HostRoles":{"state":"STARTED"}}}' | grep -q '^HTTP/1.1 2' || return $?
    # Maintenance mode on SECONDARY NameNode (if fails, keep going)
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/hosts/'${_second_nn}'/host_components/SECONDARY_NAMENODE" -X PUT --data '{"RequestInfo":{},"Body":{"HostRoles":{"maintenance_state":"ON"}}}'

    # Wait Journal Nodes starts
    _ambari_wait_comp_state "${_ambari_cluster_api_url}" "HDFS" "JOURNALNODE" "STARTED"
    # Initialize JournalNodes
    ssh -qt root@${_first_nn} "su hdfs -l -c 'hdfs namenode -initializeSharedEdits'" || return $?
    
    # Start required services, starting all components including clients...
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services?ServiceInfo/service_name.in(ZOOKEEPER)" -X PUT --data '{"RequestInfo":{"context":"Start required services ZOOKEEPER","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"}},"Body":{"ServiceInfo":{"state":"STARTED"}}}' | grep -q '^HTTP/1.1 2' || return $?
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services?ServiceInfo/service_name.in(AMBARI_INFRA)" -X PUT --data '{"RequestInfo":{"context":"Start required services AMBARI_INFRA","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"}},"Body":{"ServiceInfo":{"state":"STARTED"}}}'

    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/host_components?" -X PUT --data '{"RequestInfo":{"context":"Start NameNode","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"},"query":"HostRoles/component_name=NAMENODE&HostRoles/host_name.in('${_first_nn}')&HostRoles/maintenance_state=OFF"},"Body":{"HostRoles":{"state":"STARTED"}}}' | grep -q '^HTTP/1.1 2' || return $?

    _ambari_wait_comp_state "${_ambari_cluster_api_url}" "HDFS" "NAMENODE" "STARTED"
    #TODO: should i wait until safemode finished?
    ssh -qt root@${_first_nn} "su hdfs -l -c 'hdfs zkfc -formatZK'" || return $?
    ssh -qt root@${_second_nn} "su hdfs -l -c \"kinit -kt /etc/security/keytabs/hdfs.headless.keytab hdfs-${_cluster,,}\"" &>/dev/null
    ssh -qt root@${_second_nn} "su hdfs -l -c 'hdfs namenode -bootstrapStandby'" || return $?

    # Starting new NN
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/host_components?" -X PUT --data '{"RequestInfo":{"context":"Start NameNode","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"},"query":"HostRoles/component_name=NAMENODE&HostRoles/host_name.in('${_second_nn}')&HostRoles/maintenance_state=OFF"},"Body":{"HostRoles":{"state":"STARTED"}}}'

    # Adding, assigining to hosts, installing and starting ZKFC
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services?ServiceInfo/service_name=HDFS" --data '{"components":[{"ServiceComponentInfo":{"component_name":"ZKFC"}}]}' | grep -q '^HTTP/1.1 2' || return $?
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/hosts" --data '{"RequestInfo":{"query":"Hosts/host_name='${_second_nn}'|Hosts/host_name='${_first_nn}'"},"Body":{"host_components":[{"HostRoles":{"component_name":"ZKFC"}}]}}' | grep -q '^HTTP/1.1 2' || return $?
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/host_components?" -X PUT --data '{"RequestInfo":{"context":"Install ZKFailoverController","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"},"query":"HostRoles/component_name=ZKFC&HostRoles/host_name.in('${_second_nn}','${_first_nn}')&HostRoles/maintenance_state=OFF"},"Body":{"HostRoles":{"state":"INSTALLED"}}}'
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/host_components?" -X PUT --data '{"RequestInfo":{"context":"Start ZKFailoverController","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"},"query":"HostRoles/component_name=ZKFC&HostRoles/host_name.in('${_second_nn}','${_first_nn}')&HostRoles/maintenance_state=OFF"},"Body":{"HostRoles":{"state":"STARTED"}}}'

    # TODO: Ranger config update if Ranger is installed in here

    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/hosts/'${_second_nn}'/host_components/SECONDARY_NAMENODE" -X DELETE

    # STOP ALL, then START ALL
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services?ServiceInfo/service_name.in(HDFS)" -X PUT --data '{"RequestInfo":{"context":"Stop required services","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"}},"Body":{"ServiceInfo":{"state":"INSTALLED"}}}'
    # Wait until stop. TODO: Assuming ZOOKEEPER will be the last
    _ambari_wait_comp_state "${_ambari_cluster_api_url}" "ZOOKEEPER" "ZOOKEEPER_SERVER" "INSTALLED"
    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services" -X PUT --data '{"RequestInfo":{"context":"_PARSE_.START.ALL_SERVICES","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"}},"Body":{"ServiceInfo":{"state":"STARTED"}}}'
}

function setup_rm_ha() {
    local _ambari_cluster_api_url="${1}"    # eg: http://ho-ubu01:8080/api/v1/clusters/houbu01_1
    local _first_rm="${2}"
    local _second_rm="${3}"        # TODO: currently new NN must be Secondary NameNode
    local _cluster="`basename "${_ambari_cluster_api_url%/}"`"

    # TODO: not done yet
    return

    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services?ServiceInfo/service_name.in(YARN,MAPREDUCE2,TEZ,HIVE,HBASE,PIG,ZOOKEEPER,AMBARI_INFRA,KAFKA,KNOX,RANGER,RANGER_KMS,SLIDER)" -X PUT --data '{"RequestInfo":{"context":"Stop required services","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"}},"Body":{"ServiceInfo":{"state":"INSTALLED"}}}'

    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/hosts" --data '{"RequestInfo":{"query":"Hosts/host_name=node3.houbu01.localdomain"},"Body":{"host_components":[{"HostRoles":{"component_name":"RESOURCEMANAGER"}}]}}'

    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/host_components?" -X PUT --data '{"RequestInfo":{"context":"Install ResourceManager","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"},"query":"HostRoles/component_name=RESOURCEMANAGER&HostRoles/host_name.in(node3.houbu01.localdomain)&HostRoles/maintenance_state=OFF"},"Body":{"HostRoles":{"state":"INSTALLED"}}}'

    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}" -X PUT --data '{"Clusters":{"desired_config":[{"type":"yarn-site","tag":"version1522238825006","properties":{"hadoop.registry.rm.enabled":"true","hadoop.registry.zk.quorum":"node2.houbu01.localdomain:2181","manage.include.files":"false","yarn.acl.enable":"false","yarn.admin.acl":"yarn","yarn.application.classpath":"{{hadoop_home}}/conf,{{hadoop_home}}/*,{{hadoop_home}}/lib/*,/usr/hdp/current/hadoop-hdfs-client/*,/usr/hdp/current/hadoop-hdfs-client/lib/*,/usr/hdp/current/hadoop-yarn-client/*,/usr/hdp/current/hadoop-yarn-client/lib/*,/usr/hdp/current/ext/hadoop/*","yarn.client.failover-proxy-provider":"org.apache.hadoop.yarn.client.RequestHedgingRMFailoverProxyProvider","yarn.client.nodemanager-connect.max-wait-ms":"60000","yarn.client.nodemanager-connect.retry-interval-ms":"10000","yarn.http.policy":"HTTP_ONLY","yarn.log-aggregation-enable":"true","yarn.log-aggregation.file-controller.IndexedFormat.class":"org.apache.hadoop.yarn.logaggregation.filecontroller.ifile.LogAggregationIndexedFileController","yarn.log-aggregation.file-controller.TFile.class":"org.apache.hadoop.yarn.logaggregation.filecontroller.tfile.LogAggregationTFileController","yarn.log-aggregation.file-formats":"IndexedFormat,TFile","yarn.log-aggregation.retain-seconds":"2592000","yarn.log.server.url":"http://node2.houbu01.localdomain:19888/jobhistory/logs","yarn.log.server.web-service.url":"http://node2.houbu01.localdomain:8188/ws/v1/applicationhistory","yarn.node-labels.enabled":"false","yarn.node-labels.fs-store.retry-policy-spec":"2000, 500","yarn.node-labels.fs-store.root-dir":"/system/yarn/node-labels","yarn.nodemanager.address":"0.0.0.0:45454","yarn.nodemanager.admin-env":"MALLOC_ARENA_MAX=$MALLOC_ARENA_MAX","yarn.nodemanager.aux-services":"mapreduce_shuffle,spark_shuffle,spark2_shuffle","yarn.nodemanager.aux-services.mapreduce_shuffle.class":"org.apache.hadoop.mapred.ShuffleHandler","yarn.nodemanager.aux-services.spark2_shuffle.class":"org.apache.spark.network.yarn.YarnShuffleService","yarn.nodemanager.aux-services.spark2_shuffle.classpath":"{{stack_root}}/${hdp.version}/spark2/aux/*","yarn.nodemanager.aux-services.spark_shuffle.class":"org.apache.spark.network.yarn.YarnShuffleService","yarn.nodemanager.aux-services.spark_shuffle.classpath":"{{stack_root}}/${hdp.version}/spark/aux/*","yarn.nodemanager.bind-host":"0.0.0.0","yarn.nodemanager.container-executor.class":"org.apache.hadoop.yarn.server.nodemanager.DefaultContainerExecutor","yarn.nodemanager.container-metrics.unregister-delay-ms":"60000","yarn.nodemanager.container-monitor.interval-ms":"3000","yarn.nodemanager.delete.debug-delay-sec":"1800","yarn.nodemanager.disk-health-checker.max-disk-utilization-per-disk-percentage":"90","yarn.nodemanager.disk-health-checker.min-free-space-per-disk-mb":"1000","yarn.nodemanager.disk-health-checker.min-healthy-disks":"0.25","yarn.nodemanager.health-checker.interval-ms":"135000","yarn.nodemanager.health-checker.script.timeout-ms":"60000","yarn.nodemanager.kill-escape.launch-command-line":"slider-agent,LLAP","yarn.nodemanager.kill-escape.user":"hive","yarn.nodemanager.linux-container-executor.cgroups.strict-resource-usage":"false","yarn.nodemanager.linux-container-executor.group":"hadoop","yarn.nodemanager.local-dirs":"/hadoop/yarn/local","yarn.nodemanager.log-aggregation.compression-type":"gz","yarn.nodemanager.log-aggregation.debug-enabled":"false","yarn.nodemanager.log-aggregation.num-log-files-per-app":"336","yarn.nodemanager.log-aggregation.roll-monitoring-interval-seconds":"3600","yarn.nodemanager.log-dirs":"/hadoop/yarn/log","yarn.nodemanager.log.retain-seconds":"604800","yarn.nodemanager.recovery.dir":"{{yarn_log_dir_prefix}}/nodemanager/recovery-state","yarn.nodemanager.recovery.enabled":"true","yarn.nodemanager.remote-app-log-dir":"/app-logs","yarn.nodemanager.remote-app-log-dir-suffix":"logs","yarn.nodemanager.resource.cpu-vcores":"6","yarn.nodemanager.resource.memory-mb":"9216","yarn.nodemanager.resource.percentage-physical-cpu-limit":"80","yarn.nodemanager.vmem-check-enabled":"false","yarn.nodemanager.vmem-pmem-ratio":"2.1","yarn.resourcemanager.address":"node2.houbu01.localdomain:8050","yarn.resourcemanager.admin.address":"node2.houbu01.localdomain:8141","yarn.resourcemanager.am.max-attempts":"2","yarn.resourcemanager.bind-host":"0.0.0.0","yarn.resourcemanager.connect.max-wait.ms":"-1","yarn.resourcemanager.connect.retry-interval.ms":"15000","yarn.resourcemanager.fs.state-store.retry-policy-spec":"2000, 500","yarn.resourcemanager.fs.state-store.uri":" ","yarn.resourcemanager.ha.enabled":true,"yarn.resourcemanager.hostname":"node2.houbu01.localdomain","yarn.resourcemanager.monitor.capacity.preemption.natural_termination_factor":"1","yarn.resourcemanager.monitor.capacity.preemption.total_preemption_per_round":"0.25","yarn.resourcemanager.nodes.exclude-path":"/etc/hadoop/conf/yarn.exclude","yarn.resourcemanager.recovery.enabled":true,"yarn.resourcemanager.resource-tracker.address":"node2.houbu01.localdomain:8025","yarn.resourcemanager.scheduler.address":"node2.houbu01.localdomain:8030","yarn.resourcemanager.scheduler.class":"org.apache.hadoop.yarn.server.resourcemanager.scheduler.capacity.CapacityScheduler","yarn.resourcemanager.scheduler.monitor.enable":"false","yarn.resourcemanager.state-store.max-completed-applications":"${yarn.resourcemanager.max-completed-applications}","yarn.resourcemanager.store.class":"org.apache.hadoop.yarn.server.resourcemanager.recovery.ZKRMStateStore","yarn.resourcemanager.system-metrics-publisher.dispatcher.pool-size":"10","yarn.resourcemanager.system-metrics-publisher.enabled":"true","yarn.resourcemanager.webapp.address":"node2.houbu01.localdomain:8088","yarn.resourcemanager.webapp.delegation-token-auth-filter.enabled":"false","yarn.resourcemanager.webapp.https.address":"node2.houbu01.localdomain:8090","yarn.resourcemanager.work-preserving-recovery.enabled":"true","yarn.resourcemanager.work-preserving-recovery.scheduling-wait-ms":"10000","yarn.resourcemanager.zk-acl":"world:anyone:rwcda","yarn.resourcemanager.zk-address":"node2.houbu01.localdomain:2181","yarn.resourcemanager.zk-num-retries":"1000","yarn.resourcemanager.zk-retry-interval-ms":"1000","yarn.resourcemanager.zk-state-store.parent-path":"/rmstore","yarn.resourcemanager.zk-timeout-ms":"10000","yarn.scheduler.capacity.ordering-policy.priority-utilization.underutilized-preemption.enabled":"false","yarn.scheduler.maximum-allocation-mb":"9216","yarn.scheduler.maximum-allocation-vcores":"6","yarn.scheduler.minimum-allocation-mb":"250","yarn.scheduler.minimum-allocation-vcores":"1","yarn.timeline-service.address":"node2.houbu01.localdomain:10200","yarn.timeline-service.bind-host":"0.0.0.0","yarn.timeline-service.client.fd-flush-interval-secs":"5","yarn.timeline-service.client.max-retries":"30","yarn.timeline-service.client.retry-interval-ms":"1000","yarn.timeline-service.enabled":"true","yarn.timeline-service.entity-group-fs-store.active-dir":"/ats/active/","yarn.timeline-service.entity-group-fs-store.app-cache-size":"10","yarn.timeline-service.entity-group-fs-store.cleaner-interval-seconds":"3600","yarn.timeline-service.entity-group-fs-store.done-dir":"/ats/done/","yarn.timeline-service.entity-group-fs-store.group-id-plugin-classes":"org.apache.tez.dag.history.logging.ats.TimelineCachePluginImpl","yarn.timeline-service.entity-group-fs-store.group-id-plugin-classpath":"","yarn.timeline-service.entity-group-fs-store.retain-seconds":"604800","yarn.timeline-service.entity-group-fs-store.scan-interval-seconds":"15","yarn.timeline-service.entity-group-fs-store.summary-store":"org.apache.hadoop.yarn.server.timeline.RollingLevelDBTimelineStore","yarn.timeline-service.generic-application-history.store-class":"org.apache.hadoop.yarn.server.applicationhistoryservice.NullApplicationHistoryStore","yarn.timeline-service.http-authentication.proxyuser.root.groups":"*","yarn.timeline-service.http-authentication.proxyuser.root.hosts":"node1.houbu01.localdomain","yarn.timeline-service.http-authentication.simple.anonymous.allowed":"true","yarn.timeline-service.http-authentication.type":"simple","yarn.timeline-service.leveldb-state-store.path":"/hadoop/yarn/timeline","yarn.timeline-service.leveldb-timeline-store.path":"/hadoop/yarn/timeline","yarn.timeline-service.leveldb-timeline-store.read-cache-size":"104857600","yarn.timeline-service.leveldb-timeline-store.start-time-read-cache-size":"10000","yarn.timeline-service.leveldb-timeline-store.start-time-write-cache-size":"10000","yarn.timeline-service.leveldb-timeline-store.ttl-interval-ms":"300000","yarn.timeline-service.recovery.enabled":"true","yarn.timeline-service.state-store-class":"org.apache.hadoop.yarn.server.timeline.recovery.LeveldbTimelineStateStore","yarn.timeline-service.store-class":"org.apache.hadoop.yarn.server.timeline.EntityGroupFSTimelineStore","yarn.timeline-service.ttl-enable":"true","yarn.timeline-service.ttl-ms":"2678400000","yarn.timeline-service.version":"1.5","yarn.timeline-service.webapp.address":"node2.houbu01.localdomain:8188","yarn.timeline-service.webapp.https.address":"node2.houbu01.localdomain:8190","yarn.resourcemanager.ha.rm-ids":"rm1,rm2","yarn.resourcemanager.hostname.rm1":"node2.houbu01.localdomain","yarn.resourcemanager.webapp.address.rm1":"node2.houbu01.localdomain:8088","yarn.resourcemanager.webapp.address.rm2":"node3.houbu01.localdomain:8088","yarn.resourcemanager.webapp.https.address.rm1":"node2.houbu01.localdomain:8090","yarn.resourcemanager.webapp.https.address.rm2":"node3.houbu01.localdomain:8090","yarn.resourcemanager.hostname.rm2":"node3.houbu01.localdomain","yarn.resourcemanager.cluster-id":"yarn-cluster","yarn.resourcemanager.ha.automatic-failover.zk-base-path":"/yarn-leader-election"},"service_config_version_note":"This configuration is created by Enable ResourceManager HA wizard"}]}}'

    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}" -X PUT --data '{"Clusters":{"desired_config":[{"type":"core-site","tag":"version1522238826780","properties":{"fs.defaultFS":"hdfs://'${_nameservice}'","fs.trash.interval":"360","ha.failover-controller.active-standby-elector.zk.op.retries":"120","ha.zookeeper.quorum":"node2.houbu01.localdomain:2181","hadoop.custom-extensions.root":"/hdp/ext/{{major_stack_version}}/hadoop","hadoop.http.authentication.simple.anonymous.allowed":"true","hadoop.proxyuser.hbase.groups":"*","hadoop.proxyuser.hbase.hosts":"*","hadoop.proxyuser.hcat.groups":"*","hadoop.proxyuser.hcat.hosts":"node2.houbu01.localdomain","hadoop.proxyuser.hdfs.groups":"*","hadoop.proxyuser.hdfs.hosts":"*","hadoop.proxyuser.hive.groups":"*","hadoop.proxyuser.hive.hosts":"node2.houbu01.localdomain","hadoop.proxyuser.root.groups":"*","hadoop.proxyuser.root.hosts":"node1.houbu01.localdomain","hadoop.security.auth_to_local":"DEFAULT","hadoop.security.authentication":"simple","hadoop.security.authorization":"false","hadoop.security.key.provider.path":"kms://http@node3.houbu01.localdomain:9292/kms","io.compression.codecs":"org.apache.hadoop.io.compress.GzipCodec,org.apache.hadoop.io.compress.DefaultCodec,org.apache.hadoop.io.compress.SnappyCodec","io.file.buffer.size":"131072","io.serializations":"org.apache.hadoop.io.serializer.WritableSerialization","ipc.client.connect.max.retries":"50","ipc.client.connection.maxidletime":"30000","ipc.client.idlethreshold":"8000","ipc.server.tcpnodelay":"true","mapreduce.jobtracker.webinterface.trusted":"false","net.topology.script.file.name":"/etc/hadoop/conf/topology_script.py","hadoop.proxyuser.yarn.hosts":"node2.houbu01.localdomain,node3.houbu01.localdomain"},"service_config_version_note":"This configuration is created by Enable ResourceManager HA wizard","properties_attributes":{"final":{"fs.defaultFS":"true"}}}]}}'

    curl -siku "${g_AMBARI_USER}":"${g_AMBARI_PASS}" -H "X-Requested-By:ambari" "${_ambari_cluster_api_url%/}/services?params/run_smoke_test=true" -X PUT --data '{"RequestInfo":{"context":"Start all services","operation_level":{"level":"CLUSTER","cluster_name":"'${_cluster}'"}},"Body":{"ServiceInfo":{"state":"STARTED"}}}'
}

function _ambari_wait_comp_state() {
    local __doc__="Sleep until state becomes _state or timeout (_loop x _interval)"
    local _ambari_cluster_api_url="${1}"    # eg: http://ho-ubu01:8080/api/v1/clusters/houbu01_1
    local _service="${2}"
    local _comp="${3}"
    local _state="${4}"
    local _loop="${5-10}"
    local _interval="${6-10}"
    [ -z "${_state}" ] && return 1

    local _url="${_ambari_cluster_api_url%/}/services/${_service}?fields=ServiceInfo/state"
    [ -n "${_comp}" ] && _url="${_ambari_cluster_api_url%/}/services/${_service}/components/${_comp}?fields=ServiceComponentInfo/state"

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