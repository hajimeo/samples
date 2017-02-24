#!/usr/bin/env bash
# @see http://hortonworks.com/hadoop-tutorial/hortonworks-sandbox-guide/#section_4
# curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/start_sandbox.sh -O
#
_NAME="${1-sandbox}"

echo "Waiting for docker daemon to start up:"
until /usr/bin/docker ps 2>&1| grep STATUS>/dev/null; do  sleep 1; done;  >/dev/null
/usr/bin/docker ps -a | grep -w "${_NAME}"
if [ $? -eq 0 ]; then
    /usr/bin/docker start "${_NAME}"
else
    docker run -v hadoop:/hadoop --name "${_NAME}" --hostname "sandbox.hortonworks.com" --privileged -d \
    -p 6080:6080 \
    -p 9090:9090 \
    -p 9000:9000 \
    -p 8000:8000 \
    -p 8020:8020 \
    -p 8030:8030 \
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
    -p 1520:1520 \
    -p 2222:22 \
    # --sysctl kernel.shmmax=41943040 \
    sandbox /usr/sbin/sshd -D

    sleep 5
    echo "running ambari-admin-password-reset ..."
    docker exec -it ${_NAME} /usr/sbin/ambari-admin-password-reset
fi

#docker exec -t ${_NAME} /etc/init.d/startup_script start
docker exec -d sandbox sysctl -w kernel.shmmax=41943040
docker exec -d sandbox /sbin/sysctl -p
#docker exec -t ${_NAME} make --makefile /usr/lib/hue/tools/start_scripts/start_deps.mf  -B Startup -j -i
#docker exec -t ${_NAME} nohup su - hue -c '/bin/bash /usr/lib/tutorials/tutorials_app/run/run.sh' &>/dev/nul
docker exec -t ${_NAME} touch /usr/hdp/current/oozie-server/oozie-server/work/Catalina/localhost/oozie/SESSIONS.ser
docker exec -t ${_NAME} chown oozie:hadoop /usr/hdp/current/oozie-server/oozie-server/work/Catalina/localhost/oozie/SESSIONS.ser
#docker exec -d ${_NAME} /etc/init.d/tutorials start
docker exec -d ${_NAME} /etc/init.d/splash
docker exec -d ${_NAME} /etc/init.d/shellinaboxd start

# Clean up old logs to save disk space
docker exec -it ${_NAME} bash -c 'find /var/log/ -type f -group hadoop \( -name "*\.log*" -o -name "*\.out*" \) -mtime +7 -exec grep -Iq . {} \; -and -print0 | xargs -0 -t -n1 -I {} rm -f {}'
docker exec -it ${_NAME} bash -c 'find /var/log/ambari-server/ -type f \( -name "*\.log*" -o -name "*\.out*" \) -mtime +7 -exec grep -Iq . {} \; -and -print0 | xargs -0 -t -n1 -I {} rm -f {}'
docker exec -it ${_NAME} bash -c 'find /var/log/ambari-agent/ -type f \( -name "*\.log*" -o -name "*\.out*" \) -mtime +7 -exec grep -Iq . {} \; -and -print0 | xargs -0 -t -n1 -I {} rm -f {}'

#docker exec -it ${_NAME} bash
