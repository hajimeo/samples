#!/usr/bin/env bash
# @see http://hortonworks.com/hadoop-tutorial/hortonworks-sandbox-guide/#section_4
# curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/start_sandbox.sh -O
#
_NAME="${1-sandbox}"
_NEED_RESET_ADMIN_PWD=false
_SHMMAX=41943040

echo "Waiting for docker daemon to start up:"
until /usr/bin/docker ps 2>&1| grep STATUS>/dev/null; do  sleep 1; done;  >/dev/null
/usr/bin/docker ps -a --format "{{.Names}}" | grep -w "${_NAME}"
if [ $? -eq 0 ]; then
    /usr/bin/docker start "${_NAME}"
else
    docker run -v hadoop:/hadoop --name "${_NAME}" --hostname "sandbox.hortonworks.com" --privileged -d \
    -p 6080:6080 \
    -p 9090:9090 \
    -p 9000:9000 \
    -p 8000:8000 \
    -p 8020:8020 \
    -p 42111:42111 \
    -p 10500:10500 \
    -p 16030:16030 \
    -p 8042:8042 \
    -p 8040:8040 \
    -p 2100:2100 \
    -p 4200:4200 \
    -p 4040:4040 \
    -p 8050:8050 \
    -p 9996:9996 \
    -p 9995:9995 \
    -p 8080:8080 \
    -p 8088:8088 \
    -p 8886:8886 \
    -p 8889:8889 \
    -p 8443:8443 \
    -p 8744:8744 \
    -p 8888:8888 \
    -p 8188:8188 \
    -p 8983:8983 \
    -p 1000:1000 \
    -p 1100:1100 \
    -p 11000:11000 \
    -p 10001:10001 \
    -p 15000:15000 \
    -p 10000:10000 \
    -p 8993:8993 \
    -p 1988:1988 \
    -p 5007:5007 \
    -p 50070:50070 \
    -p 19888:19888 \
    -p 16010:16010 \
    -p 50111:50111 \
    -p 50075:50075 \
    -p 50095:50095 \
    -p 18080:18080 \
    -p 60000:60000 \
    -p 8090:8090 \
    -p 8091:8091 \
    -p 8005:8005 \
    -p 8086:8086 \
    -p 8082:8082 \
    -p 60080:60080 \
    -p 8765:8765 \
    -p 5011:5011 \
    -p 6001:6001 \
    -p 6003:6003 \
    -p 6008:6008 \
    -p 1220:1220 \
    -p 21000:21000 \
    -p 6188:6188 \
    -p 61888:61888 \
    -p 8030:8030 \
    -p 1520:1520 \
    -p 3000:3000 \
    -p 10016:10016 \
    -p 50470:50470 \
    -p 50475:50475 \
    -p 19889:19889 \
    -p 8044:8044 \
    -p 2222:22 \
    --sysctl kernel.shmmax=${_SHMMAX} \
    sandbox /usr/sbin/sshd -D

    _NEED_RESET_ADMIN_PWD=true
fi
# TODO: how to change/add port later (does not work)
# copy /var/lib/docker/containers/${_CONTAINER_ID}*/config.v2.json
# stop the container, then stop docker service
# paste config.v2.json
# start docker service, then cotainer

#docker exec -t ${_NAME} /etc/init.d/startup_script start
#docker exec -t ${_NAME} make --makefile /usr/lib/hue/tools/start_scripts/start_deps.mf  -B Startup -j -i
#docker exec -t ${_NAME} nohup su - hue -c '/bin/bash /usr/lib/tutorials/tutorials_app/run/run.sh' &>/dev/null
docker exec -t ${_NAME} touch /usr/hdp/current/oozie-server/oozie-server/work/Catalina/localhost/oozie/SESSIONS.ser
docker exec -t ${_NAME} chown oozie:hadoop /usr/hdp/current/oozie-server/oozie-server/work/Catalina/localhost/oozie/SESSIONS.ser
#docker exec -d ${_NAME} /etc/init.d/tutorials start
#docker exec -d ${_NAME} /etc/init.d/splash
docker exec -d ${_NAME} /etc/init.d/shellinaboxd start

if ${_NEED_RESET_ADMIN_PWD} ; then
    echo "INFO: Resetting Ambari password (type 'admin' twice) ..."
    docker exec -it ${_NAME} /usr/sbin/ambari-admin-password-reset
    # (optional) Fixing public hostname (169.254.169.254 issue) by appending public_hostname.sh"
    docker exec -it ${_NAME} bash -c 'grep "^public_hostname_script" /etc/ambari-agent/conf/ambari-agent.ini || ( echo -e "#!/bin/bash\necho \`hostname -f\`" > /var/lib/ambari-agent/public_hostname.sh && chmod a+x /var/lib/ambari-agent/public_hostname.sh && sed -i.bak "/run_as_user/i public_hostname_script=/var/lib/ambari-agent/public_hostname.sh\n" /etc/ambari-agent/conf/ambari-agent.ini )'
else
    docker exec -d ${_NAME} sysctl -w kernel.shmmax=${_SHMMAX}
    docker exec -d ${_NAME} /sbin/sysctl -p
    # Clean up old logs to save disk space
    docker exec -it ${_NAME} bash -c 'find /var/log/ -type f -group hadoop \( -name "*\.log*" -o -name "*\.out*" \) -mtime +7 -exec grep -Iq . {} \; -and -print0 | xargs -0 -t -n1 -I {} rm -f {}'
    docker exec -it ${_NAME} bash -c 'find /var/log/ambari-server/ -type f \( -name "*\.log*" -o -name "*\.out*" \) -mtime +7 -exec grep -Iq . {} \; -and -print0 | xargs -0 -t -n1 -I {} rm -f {}'
    docker exec -it ${_NAME} bash -c 'find /var/log/ambari-agent/ -type f \( -name "*\.log*" -o -name "*\.out*" \) -mtime +7 -exec grep -Iq . {} \; -and -print0 | xargs -0 -t -n1 -I {} rm -f {}'
fi

docker exec -it ${_NAME} /usr/sbin/ambari-server start
docker exec -it ${_NAME} /usr/sbin/ambari-agent start
docker exec -it ${_NAME} /sbin/service mysqld start
curl -s -u admin:admin -H "X-Requested-By:ambari" -k "http://sandbox.hortonworks.com:8080/api/v1/clusters/Sandbox/services?" -X PUT --data '{"RequestInfo":{"context":"START ALL_SERVICES","operation_level":{"level":"CLUSTER","cluster_name":"Sandbox"}},"Body":{"ServiceInfo":{"state":"STARTED"}}}'

#docker exec -it ${_NAME} bash
