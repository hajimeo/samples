#!/usr/bin/env bash
# @see http://hortonworks.com/hadoop-tutorial/hortonworks-sandbox-guide/#section_4
#
# curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/start_sandbox.sh -O
# ./start_sandbox.sh [sandblx|sandbox-hdf|sandbox-hdp]
#
_NAME="${1-sandbox}"
_AMBARI_PORT=8080
_SHMMAX=41943040
_NEW_CONTAINER=false

function f_docker_image_setup() {
    #Install Sandbox docker version. See https://hortonworks.com/hadoop-tutorial/hortonworks-sandbox-guide"
    local _tmp_dir="${1-./}"
    local _name="${2-$_NAME}" # sandbox or sandbox-hdf
    local _url="$3"
    local _min_disk="12"

    which docker &>/dev/null
    if [ $? -ne 0 ]; then
        echo "Please install docker - https://docs.docker.com/engine/installation/linux/ubuntu/"
        echo "or "
        echo "./start_hdp.sh -f f_docker_setup"
        return 1
    fi

    docker ps -a --format "{{.Names}}" | grep -w "${_NAME}"
    if [ $? -eq 0 ]; then
        echo "Image $_name already exist. Exiting."
        return
    fi

    if [ "${_name}" = "sandbox-hdf" ]; then
        _url="https://downloads-hortonworks.akamaized.net/sandbox-hdf-2.1/HDF_2.1.2_docker_image_04_05_2017_13_12_03.tar.gz"
        _min_disk=6
    elif [ -z "$_url" ]; then
        #_url="http://hortonassets.s3.amazonaws.com/2.5/HDP_2.5_docker.tar.gz"
        _url="https://downloads-hortonworks.akamaized.net/sandbox-hdp-2.6/HDP_2.6_docker_05_05_2017_15_01_40.tar.gz"
    fi

    local _file_name="`basename "${_url}"`"

    if ! _isEnoughDisk "$_tmp_dir" "$_min_disk"; then
        echo "ERROR: Not enough space to download sandbox"
        return 1
    fi

    if [ -s "${_tmp_dir%/}/${_file_name}" ]; then
        echo "${_tmp_dir%/}/${_file_name} exists. Reusing it..."
    else
        curl --retry 100 -C - "${_url}" -o "${_tmp_dir%/}/${_file_name}" || return $?
    fi

    docker load < "${_tmp_dir%/}/${_file_name}" || return $?
}

function _port_wait() {
    local _host="$1"
    local _port="$2"
    local _times="${3-10}"
    local _interval="${4-5}"

    for i in `seq 1 $_times`; do
      sleep $_interval
      nc -z $_host $_port && return 0
      echo "$_host:$_port is unreachable. Waiting..."
    done
    echo "$_host:$_port is unreachable."
    return 1
}
function _isEnoughDisk() {
    local __doc__="Check if entire system or the given path has enough space with GB."
    local _dir_path="${1-/}"
    local _required_gb="$2"
    local _available_space_gb=""

    _available_space_gb=`_freeSpaceGB "${_dir_path}"`

    if [ -z "$_required_gb" ]; then
        echo "${_available_space_gb}GB free space"
        _required_gb=`_totalSpaceGB`
        _required_gb="`expr $_required_gb / 10`"
    fi

    if [ $_available_space_gb -lt $_required_gb ]; then return 1; fi
    return 0
}
function _freeSpaceGB() {
    local __doc__="Output how much space for given directory path."
    local _dir_path="$1"
    if [ ! -d "$_dir_path" ]; then _dir_path="-l"; fi
    df -P --total ${_dir_path} | grep -i ^total | awk '{gb=sprintf("%.0f",$4/1024/1024);print gb}'
}
function _totalSpaceGB() {
    local __doc__="Output how much space for given directory path."
    local _dir_path="$1"
    if [ ! -d "$_dir_path" ]; then _dir_path="-l"; fi
    df -P --total ${_dir_path} | grep -i ^total | awk '{gb=sprintf("%.0f",$2/1024/1024);print gb}'
}

### main() ############################################################
if [ "$0" = "$BASH_SOURCE" ]; then
    echo "Waiting for docker daemon to start up:"
    until docker ps 2>&1| grep STATUS>/dev/null; do  sleep 1; done;  >/dev/null

    echo "Stopping other containers..."
    for _n in `docker ps --format "{{.Names}}" | grep -vE "^${_NAME}$"`; do docker stop $_n; done

    docker ps -a --format "{{.Names}}" | grep -w "${_NAME}"
    if [ $? -eq 0 ]; then
        docker start "${_NAME}"
    else
      if [ "${_NAME}" = "sandbox-hdf" ]; then
        docker run -v hadoop:/hadoop --name "${_NAME}" --hostname "${_NAME}.hortonworks.com" --privileged -d \
        -p 12181:2181 \
        -p 13000:3000 \
        -p 14200:4200 \
        -p 14557:4557 \
        -p 16080:6080 \
        -p 18000:8000 \
        -p ${_AMBARI_PORT}:8080 \
        -p 18744:8744 \
        -p 18886:8886 \
        -p 18888:8888 \
        -p 18993:8993 \
        -p 19000:9000 \
        -p 19090:9090 \
        -p 19091:9091 \
        -p 43111:42111 \
        -p 62888:61888 \
        -p 25100:15100 \
        -p 25101:15101 \
        -p 25102:15102 \
        -p 25103:15103 \
        -p 25104:15104 \
        -p 25105:15105 \
        -p 17000:17000 \
        -p 17001:17001 \
        -p 17002:17002 \
        -p 17003:17003 \
        -p 17004:17004 \
        -p 17005:17005 \
        -p 2222:22 \
        ${_NAME} /usr/sbin/sshd -D
        # NOTE: Using 8080 and 2222 for HDF as well
      else
        docker run -v hadoop:/hadoop --name "${_NAME}" --hostname "${_NAME}.hortonworks.com" --privileged -d \
        -p 1111:111 \
        -p 1000:1000 \
        -p 1100:1100 \
        -p 1220:1220 \
        -p 1520:1520 \
        -p 1988:1988 \
        -p 2049:2049 \
        -p 2100:2100 \
        -p 2181:2181 \
        -p 3000:3000 \
        -p 4040:4040 \
        -p 4200:4200 \
        -p 4242:4242 \
        -p 5007:5007 \
        -p 5011:5011 \
        -p 6001:6001 \
        -p 6003:6003 \
        -p 6008:6008 \
        -p 6080:6080 \
        -p 6188:6188 \
        -p 8000:8000 \
        -p 8005:8005 \
        -p 8020:8020 \
        -p 8030:8030 \
        -p 8032:8032 \
        -p 8040:8040 \
        -p 8042:8042 \
        -p 8044:8044 \
        -p 8050:8050 \
        -p ${_AMBARI_PORT}:8080 \
        -p 8082:8082 \
        -p 8086:8086 \
        -p 8088:8088 \
        -p 8090:8090 \
        -p 8091:8091 \
        -p 8188:8188 \
        -p 8443:8443 \
        -p 8744:8744 \
        -p 8765:8765 \
        -p 8886:8886 \
        -p 8888:8888 \
        -p 8889:8889 \
        -p 8983:8983 \
        -p 8993:8993 \
        -p 9000:9000 \
        -p 9090:9090 \
        -p 9995:9995 \
        -p 9996:9996 \
        -p 10000:10000 \
        -p 10001:10001 \
        -p 10015:10015 \
        -p 10016:10016 \
        -p 10500:10500 \
        -p 10502:10502 \
        -p 11000:11000 \
        -p 15000:15000 \
        -p 15002:15002 \
        -p 15500:15500 \
        -p 15501:15501 \
        -p 15502:15502 \
        -p 15503:15503 \
        -p 15504:15504 \
        -p 15505:15505 \
        -p 16000:16000 \
        -p 16010:16010 \
        -p 16020:16020 \
        -p 16030:16030 \
        -p 18080:18080 \
        -p 18081:18081 \
        -p 19888:19888 \
        -p 21000:21000 \
        -p 33553:33553 \
        -p 39419:39419 \
        -p 42111:42111 \
        -p 50070:50070 \
        -p 50075:50075 \
        -p 50079:50079 \
        -p 50095:50095 \
        -p 50111:50111 \
        -p 50470:50470 \
        -p 50475:50475 \
        -p 60000:60000 \
        -p 60080:60080 \
        -p 61310:61310 \
        -p 61888:61888 \
        -p 2222:22 \
        --sysctl kernel.shmmax=${_SHMMAX} \
        ${_NAME} /usr/sbin/sshd -D
      fi

      _NEW_CONTAINER=true
    fi

    # TODO: how to change/add port later (does not work)
    # copy /var/lib/docker/containers/${_CONTAINER_ID}*/config.v2.json
    # stop the container, then stop docker service
    # paste config.v2.json
    # start docker service, then cotainer

    #docker exec -t ${_NAME} /etc/init.d/startup_script start
    #docker exec -t ${_NAME} make --makefile /usr/lib/hue/tools/start_scripts/start_deps.mf  -B Startup -j -i
    #docker exec -t ${_NAME} nohup su - hue -c '/bin/bash /usr/lib/tutorials/tutorials_app/run/run.sh' &>/dev/null
    #docker exec -t ${_NAME} touch /usr/hdp/current/oozie-server/oozie-server/work/Catalina/localhost/oozie/SESSIONS.ser
    #docker exec -t ${_NAME} chown oozie:hadoop /usr/hdp/current/oozie-server/oozie-server/work/Catalina/localhost/oozie/SESSIONS.ser
    #docker exec -d ${_NAME} /etc/init.d/splash

    sleep 3
    docker exec -d ${_NAME} sysctl -w kernel.shmmax=${_SHMMAX}
    #docker exec -d ${_NAME} /sbin/sysctl -p
    docker exec -d ${_NAME} service postgresql start

    #ssh -p 2222 localhost -t /sbin/service mysqld start
    docker exec -d ${_NAME} service mysqld start
    docker exec -d ${_NAME} service mysqld start

    if ${_NEW_CONTAINER} ; then
        if [ -s  ~/.ssh/id_rsa.pub ]; then
            docker exec -it ${_NAME} bash -c "grep -q \"^`cat ~/.ssh/id_rsa.pub`\" /root/.ssh/authorized_keys || echo \"`cat ~/.ssh/id_rsa.pub`\" >> ~/.ssh/authorized_keys"
        fi
        echo "Resetting Ambari password (type 'admin' twice) ..."
        docker exec -it ${_NAME} /usr/sbin/ambari-admin-password-reset
        # (optional) Fixing public hostname (169.254.169.254 issue) by appending public_hostname.sh"
        docker exec -it ${_NAME} bash -c 'grep "^public_hostname_script" /etc/ambari-agent/conf/ambari-agent.ini || ( echo -e "#!/bin/bash\necho \`hostname -f\`" > /var/lib/ambari-agent/public_hostname.sh && chmod a+x /var/lib/ambari-agent/public_hostname.sh && sed -i.bak "/run_as_user/i public_hostname_script=/var/lib/ambari-agent/public_hostname.sh\n" /etc/ambari-agent/conf/ambari-agent.ini )'
    else
        docker exec -d ${_NAME} service ambari-server start
    fi
    docker exec -d ${_NAME} service ambari-agent start

    docker exec -d ${_NAME} /root/start_sandbox.sh
    docker exec -d ${_NAME} /etc/init.d/shellinaboxd start
    docker exec -d ${_NAME} /etc/init.d/tutorials start

    # Clean up old logs to save disk space
    docker exec -it ${_NAME} bash -c 'find /var/log/ -type f -group hadoop \( -name "*\.log*" -o -name "*\.out*" \) -mtime +7 -exec grep -Iq . {} \; -and -print0 | xargs -0 -t -n1 -I {} rm -f {}'
    docker exec -it ${_NAME} bash -c 'find /var/log/ambari-server/ -type f \( -name "*\.log*" -o -name "*\.out*" \) -mtime +7 -exec grep -Iq . {} \; -and -print0 | xargs -0 -t -n1 -I {} rm -f {}'
    docker exec -it ${_NAME} bash -c 'find /var/log/ambari-agent/ -type f \( -name "*\.log*" -o -name "*\.out*" \) -mtime +7 -exec grep -Iq . {} \; -and -print0 | xargs -0 -t -n1 -I {} rm -f {}'

    _port_wait "localhost" $_AMBARI_PORT
    curl -u admin:admin -H "X-Requested-By:ambari" -k "http://localhost:${_AMBARI_PORT}/api/v1/clusters/Sandbox/services?" -X PUT --data '{"RequestInfo":{"context":"START ALL_SERVICES","operation_level":{"level":"CLUSTER","cluster_name":"Sandbox"}},"Body":{"ServiceInfo":{"state":"STARTED"}}}'
    echo ""
    #docker exec -it ${_NAME} bash
fi