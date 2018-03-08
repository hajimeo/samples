#!/usr/bin/env bash
# @see http://hortonworks.com/hadoop-tutorial/hortonworks-sandbox-guide/#section_4
# @see https://raw.githubusercontent.com/hortonworks/data-tutorials/master/tutorials/hdp/sandbox-port-forwarding-guide/assets/start-sandbox-hdp.sh

function usage() {
    echo "To get the latest script:
    curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/start_sandbox.sh -O

To create Sandbox (first time only)
    source ./start_sandbox.sh
    (move to dir which has enough disk space, min. 12GB)
    f_docker_image_setup [sandbox-hdp|sandbox-hdf]

To start Sandbox
    bash ./start_sandbox.sh -n <container name> [-m <image name>] [-h <container hostname>] [-i <container IP>]

    NOTE: To assign an IP with -i, 'hdp' network is required.
    If no -m, if same image name as container name exist, it uses that.

TODO: How to create 'hdp' network (incomplete as how to change docker config is different by OS)
Update docker config file to add \" --bip=172.18.0.1\/24\", then restart docker service, then
    docker network create --driver=bridge --gateway=172.17.0.1 --subnet=172.17.0.0/16 -o com.docker.network.bridge.name=hdp -o com.docker.network.bridge.host_binding_ipv4=172.17.0.1 hdp
"
}

### Global variables
_CUSTOM_NETWORK="hdp"
_AMBARI_PORT=8080
_SHMMAX=41943040
_NEW_CONTAINER=false


### functions
function f_docker_image_setup() {
    #Install Sandbox docker version. See https://hortonworks.com/hadoop-tutorial/hortonworks-sandbox-guide"
    local _name="${1-$_NAME}" # sandbox or sandbox-hdf
    local _url="$2"
    local _tmp_dir="${3-./}"
    local _min_disk="12"

    which docker &>/dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: Please install docker - https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/"
        echo "or "
        echo "./start_hdp.sh -f f_docker_setup"
        return 1
    fi

    local _existing_img="`docker images --format "{{.Repository}}:{{.Tag}}" | grep -m 1 -E "^${_name}:"`"
    if [ ! -z "$_existing_img" ]; then
        echo "WARN: Image $_name already exist. Exiting."
        echo "To rename image:"
        echo "    docker tag ${_existing_img} <new_name>:<new_tag>"
        echo "    docker rmi ${_existing_img}"
        return
    fi

    if [[ "${_name}" =~ ^"sandbox-hdf" ]]; then
        #_url="https://downloads-hortonworks.akamaized.net/sandbox-hdf-2.1/HDF_2.1.2_docker_image_04_05_2017_13_12_03.tar.gz"
        _url="https://downloads-hortonworks.akamaized.net/sandbox-hdf-3.0/HDF_3.0_docker_12_6_2017.tar.gz"
        #TODO: docker pull orendain/sandbox-hdf-analytics:3.0.2.0
        _min_disk=9
    elif [ -z "$_url" ]; then
        #_url="http://hortonassets.s3.amazonaws.com/2.5/HDP_2.5_docker.tar.gz"
        #_url="https://downloads-hortonworks.akamaized.net/sandbox-hdp-2.6/HDP_2.6_docker_05_05_2017_15_01_40.tar.gz"
        #_url="https://downloads-hortonworks.akamaized.net/sandbox-hdp-2.6.1/HDP_2_6_1_docker_image_28_07_2017_14_42_40.tar"
        _url="https://downloads-hortonworks.akamaized.net/sandbox-hdp-2.6.3/HDP_2.6.3_docker_10_11_2017.tar"
    fi

    local _file_name="`basename "${_url}"`"

    if ! _isEnoughDisk "$_tmp_dir" "$_min_disk"; then
        echo "ERROR: Not enough space to download sandbox"
        return 1
    fi

    if [ -s "${_tmp_dir%/}/${_file_name}" ]; then
        echo "INFO: ${_tmp_dir%/}/${_file_name} exists. Reusing it..."
        sleep 3
    else
        echo "INFO: Executing \"cur \"${_url}\" -o ${_tmp_dir%/}/${_file_name}\""
        curl --retry 100 -C - "${_url}" -o "${_tmp_dir%/}/${_file_name}" || return $?
    fi

    if [[ "${_name}" =~ ^"sandbox-hdf" ]]; then
        # Somehow HDF3 does not work with docker load
        docker import "${_tmp_dir%/}/${_file_name}"
    else
        docker load -i "${_tmp_dir%/}/${_file_name}"
    fi
}

function f_ambari_wait() {
    local _host="${1-$_HOSTNAME}"
    local _port="${2-8080}"
    local _cluster="${3-Sandbox}"
    local _times="${3-30}"
    local _interval="${4-10}"

    # NOTE: --retry-connrefused is from curl v 7.52.0
    for i in `seq 1 $_times`; do
        sleep $_interval
        nc -z $_host $_port && curl -sL -u admin:admin "http://$_host:$_port/api/v1/clusters/${_cluster}?fields=Clusters/health_report" | grep -oE '"Host/host_state/HEALTHY" : [1-9]+' && break
        echo "INFO: $_host:$_port is unreachable. Waiting for ${_interval} secs ($i/${_times})..."
    done
    # To wait other agents will be available (but doesn't matter for sandbox)
    sleep 5
}

function f_ambari_start_all() {
    local _host="${1-$_HOSTNAME}"
    local _port="${2-8080}"
    local _cluster="${3-Sandbox}"

    if ${_NEW_CONTAINER} ; then
        # Sandbox's HDFS is always in maintenance mode so that start all does not work
        curl -siL -u admin:admin -H "X-Requested-By:ambari" -k "http://${_host}:${_port}/api/v1/clusters/${_cluster}/services/HDFS" -X PUT -d '{"RequestInfo":{"context":"Maintenance Mode OFF for HDFS"},"Body":{"ServiceInfo":{"maintenance_state":"OFF"}}}'
    fi
    sleep 1
    curl -siL -u admin:admin -H "X-Requested-By:ambari" -k "http://${_host}:${_port}/api/v1/clusters/${_cluster}/services?" -X PUT -d '{"RequestInfo":{"context":"START ALL_SERVICES","operation_level":{"level":"CLUSTER","cluster_name":"Sandbox"}},"Body":{"ServiceInfo":{"state":"STARTED"}}}'
}

function f_service() {
    local _service="$1" # Space separated service name
    local _action="$2"  # Acceptable actions: START and STOP
    local _host="${3-$_HOSTNAME}"
    local _port="${4-8080}"
    local _cluster="${5-Sandbox}"
    local _maintenance_mode="OFF"

    if [ -z "$_service" ]; then
        echo "Available services"
        curl -su admin:admin "http://${_host}:${_port}/api/v1/clusters/${_cluster}/services?fields=ServiceInfo/service_name" | grep -oE '"service_name".+'
        return 0
    fi
    _service="${_service^^}"

    if [ -z "$_action" ]; then
        echo "$_service status"
        for _s in `echo ${_service} | sed 's/ /\n/g'`; do
            curl -su admin:admin "http://${_host}:${_port}/api/v1/clusters/${_cluster}/services/${_s}?fields=ServiceInfo/service_name,ServiceInfo/state" | grep -oE '("service_name"|"state").+'
        done
        return 0
    fi
    _action="${_action^^}"

    for _s in `echo ${_service} | sed 's/ /\n/g'`; do
        if [ "$_action" = "RESTART" ]; then
            f_service "$_s" "stop" "${_ambari_host}" "${_port}" "${_cluster}"|| return $?
            for _i in {1..9}; do
                curl -su admin:admin "http://${_host}:${_port}/api/v1/clusters/${_cluster}/services/${_s}?ServiceInfo/state=INSTALLED&fields=ServiceInfo/state" | grep -wq INSTALLED && break;
                # Waiting it stops
                sleep 10
            done
            # If starting fails, keep going next
            f_service "$_s" "start" "${_ambari_host}" "${_port}" "${_cluster}"
        else
            [ "$_action" = "START" ] && _action="STARTED"
            [ "$_action" = "STOP" ] && _action="INSTALLED"
            [ "$_action" = "INSTALLED" ] && _maintenance_mode="ON"

            curl -s -u admin:admin -H "X-Requested-By:ambari" -X PUT -d '{"RequestInfo":{"context":"Maintenance Mode '$_maintenance_mode' '$_s'"},"Body":{"ServiceInfo":{"maintenance_state":"'$_maintenance_mode'"}}}' "http://${_host}:${_port}/api/v1/clusters/${_cluster}/services/$_s"

            # same action for same service is already done
            curl -su admin:admin "http://${_host}:${_port}/api/v1/clusters/${_cluster}/services/${_s}?ServiceInfo/state=${_action}&fields=ServiceInfo/state" | grep -wq ${_action} && continue;

            curl -si -u admin:admin -H "X-Requested-By:ambari" -X PUT -d '{"RequestInfo":{"context":"set '$_action' for '$_s' by f_service","operation_level":{"level":"SERVICE","cluster_name":"'${_cluster}'","service_name":"'$_s'"}},"Body":{"ServiceInfo":{"state":"'$_action'"}}}' "http://${_host}:${_port}/api/v1/clusters/${_cluster}/services/$_s"
            echo ""
        fi
    done
}

function f_useradd() {
    local __doc__="TODO: Add user"
    local _user="$1"
    local _password="${2}"
    local _cluster="${3-sandbox}"
    local _container="${4-$_NAME}"
    [ -z "$_user" ] && return 11
    [ -z "$_password" ] && _password="${_user}-password"
    [ -z "$_cluster" ] && return 13
    [ -z "$_container" ] && _container=`docker ps --format "{{.Names}}" | grep -m1 -i '^sandbox'`

    docker exec -it ${_container} bash -c 'useradd '$_user' -s `which bash` -p $(echo "'$_password'" | openssl passwd -1 -stdin) && usermod -a -G users '$_user || return $?
    docker exec -it ${_container} bash -c "sudo -u hdfs bash -c \"kinit -kt /etc/security/keytabs/hdfs.headless.keytab hdfs-${_cluster} &>/dev/null; hdfs dfs -mkdir /user/$_user && hdfs dfs -chown $_user:hadoop /user/$_user\""

    if which kadmin.local; then
        kadmin.local -q "add_principal -pw $_password $_user"
    fi
}

function _isEnoughDisk() {
    local __doc__="Check if entire system or the given path has enough space with GB."
    local _dir_path="${1-/}"
    local _required_gb="$2"
    local _available_space_gb=""

    _available_space_gb=`_freeSpaceGB "${_dir_path}"`

    if [ -z "$_required_gb" ]; then
        echo "INFO: ${_available_space_gb}GB free space"
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

### main()
if [ "$0" = "$BASH_SOURCE" ]; then
    #_NAME="sandbox-hdp"

    # parsing command options
    while getopts "m:n:h:i:" opts; do
        case $opts in
            m)
                _IMAGE="$OPTARG"
                ;;
            n)
                _NAME="$OPTARG"
                ;;
            h)
                _HOSTNAME="$OPTARG"
                ;;
            i)
                _IP="$OPTARG"
                ;;
        esac
    done

    if [ -z "$_NAME" ]; then
        if [ -z "$_IMAGE" ]; then
            usage
            exit
        fi
        _NAME=${_IMAGE}
    fi

    if [ -z "$_IMAGE" ]; then
        # If *exactly* same image name exist, use it
        docker images --format "{{.Repository}}" | grep -qE "^${_NAME}$"
        if [ $? -eq 0 ]; then
            _IMAGE="${_NAME}"
        elif [[ "${_NAME}" =~ ^"sandbox-hdf" ]]; then
            _IMAGE="sandbox-hdf"
        elif [[ "${_NAME}" =~ ^"sandbox-hdp" ]]; then
            _IMAGE="sandbox-hdp"
        else
            _IMAGE="sandbox"
        fi
    fi

    if [ -z "${_HOSTNAME}" ]; then
        # TODO: Seems HDF image works with only sandbox-hdf.hortonwroks.com
        if [[ "${_NAME}" =~ ^"sandbox-hdf" ]]; then
            _HOSTNAME="sandbox-hdf.hortonworks.com"
        elif [[ "${_NAME}" =~ ^"sandbox-hdp" ]]; then
            _HOSTNAME="sandbox-hdp.hortonworks.com"
        else
            _HOSTNAME="sandbox.hortonworks.com"
        fi
    fi

    python -c "import socket; socket.gethostbyname(\"${_HOSTNAME}\")" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "WARN: ${_HOSTNAME} may not be resolvable.
If you would like to fix this now, press Ctrl+c to stop (sleep 7 seconds)"
        sleep 7
    fi

    if [ ! -s /etc/docker/daemon.json ]; then
        echo "WARN: /etc/docker/daemon.json is not configured
If you would like to fis this now, press Ctrl+c to stop (sleep 7 seconds)"
        sleep 7
    fi

    # To use tcpdump from container
    if [ ! -L /etc/apparmor.d/disable/usr.sbin.tcpdump ]; then
        ln -sf /etc/apparmor.d/usr.sbin.tcpdump /etc/apparmor.d/disable/
        apparmor_parser -R /etc/apparmor.d/usr.sbin.tcpdump
    fi

    # To use mysql from container
    if [ ! -L /etc/apparmor.d/disable/usr.sbin.mysqld ]; then
        ln -sf /etc/apparmor.d/usr.sbin.mysqld /etc/apparmor.d/disable/
        apparmor_parser -R /etc/apparmor.d/usr.sbin.mysqld
    fi

    _HOST_HDP_IP=`ifconfig $_CUSTOM_NETWORK | grep -oP 'inet addr:\d+\.\d+\.\d+\.\d+' | cut -d":" -f2`

    echo "INFO: Waiting for docker daemon to start up:"
    until docker ps 2>&1| grep -q STATUS; do  sleep 1; done;  >/dev/null

    # Stop all containers (including $_NAME if it's already running)
    #docker stop $(docker ps -q)

    # If same container name exists start it
    if docker ps --format "{{.Names}}" | grep -qE "^${_NAME}$"; then
        echo "INFO: ${_NAME} is already running"
    elif docker ps -a --format "{{.Names}}" | grep -qE "^${_NAME}$"; then
        docker start "${_NAME}" || exit $?
    else
        _network=""
        if [ ! -z "$_IP" ]; then
            if ! docker network ls | grep -qw "$_CUSTOM_NETWORK"; then
                echo "WARN: IP $_IP is given but no custom network $_CUSTOM_NETWORK. Ignoring IP..."
                sleep 5
            else
                _network="--network=${_CUSTOM_NETWORK} --ip=${_IP}"
                # TODO: how about --dns?
            fi
        fi

        # TODO: '--name "${_NAME}"' works if :latest exist, so that 'orendain/sandbox-hdf-analytics:3.0.2.0' doesn't work
        # If name contains hdf assuming HDF
        if [[ "${_NAME}" =~ ^"sandbox-hdf" ]]; then
            docker run --name "${_NAME}" --hostname "${_HOSTNAME}" ${_network} -v /sys/fs/cgroup:/sys/fs/cgroup:ro --privileged -d \
            -p 11099:1099 \
            -p 12181:2181 \
            -p 13000:3000 \
            -p 14200:4200 \
            -p 14557:4557 \
            -p 15005:5005 \
            -p 16080:6080 \
            -p 18000:8000 \
            -p ${_AMBARI_PORT}:8080 \
            -p 18744:8744 \
            -p 18886:8886 \
            -p 18888:8888 \
            -p 18993:8993 \
            -p 19000:9000 \
            -p 19090:9090 \
            -p 19088:9088 \
            -p 19091:9091 \
            -p 5005:5005 \
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
            ${_IMAGE} /sbin/init || exit $?
            # NOTE: Using 8080 and 2222 for HDF as well
        else
            docker run --name "${_NAME}" --hostname "${_HOSTNAME}" ${_network} -v /sys/fs/cgroup:/sys/fs/cgroup:ro --privileged -d \
            -p 1111:111 \
            -p 1000:1000 \
            -p 1099:1099 \
            -p 1100:1100 \
            -p 1220:1220 \
            -p 1520:1520 \
            -p 1521:1521 \
            -p 1988:1988 \
            -p 2049:2049 \
            -p 2100:2100 \
            -p 2181:2181 \
            -p 3000:3000 \
            -p 13306:3306 \
            -p 4040:4040 \
            -p 4200:4200 \
            -p 4242:4242 \
            -p 5005:5005 \
            -p 5007:5007 \
            -p 5011:5011 \
            -p 15432:5432 \
            -p 16001:6001 \
            -p 6003:6003 \
            -p 6008:6008 \
            -p 6080:6080 \
            -p 6188:6188 \
            -p 6182:6182 \
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
            -p 8190:8190 \
            -p 8443:8443 \
            -p 8744:8744 \
            -p 8765:8765 \
            -p 8886:8886 \
            -p 8888:8888 \
            -p 8889:8889 \
            -p 8983:8983 \
            -p 8993:8993 \
            -p 9000:9000 \
            -p 9088:9088 \
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
            ${_IMAGE} /sbin/init || exit $?
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
    #docker exec -d ${_NAME} /etc/init.d/splash  # to intentioanlly break hue?


    echo "INFO: Clean up old logs to save disk space before starting anything ..."
    docker exec -it ${_NAME} bash -c 'find /var/log/ -type f -group hadoop \( -name "*\.log*" -o -name "*\.out*" \) -mtime +7 -exec grep -Iq . {} \; -and -print0 | xargs -0 -t -n1 -I {} rm -f {}'
    docker exec -it ${_NAME} bash -c 'find /var/log/ambari-server/ -type f \( -name "*\.log*" -o -name "*\.out*" \) -mtime +7 -exec grep -Iq . {} \; -and -print0 | xargs -0 -t -n1 -I {} rm -f {}'
    docker exec -it ${_NAME} bash -c 'find /var/log/ambari-agent/ -type f \( -name "*\.log*" -o -name "*\.out*" \) -mtime +7 -exec grep -Iq . {} \; -and -print0 | xargs -0 -t -n1 -I {} rm -f {}'

    echo "INFO: OS config changes, and starting SSHd, PostgreSQL, and MySQL ..."
    # setting up password-less ssh to sandbox whenever it starts in case .ssh is updated.
    if [ -s  ~/.ssh/id_rsa.pub ]; then
        docker exec -it ${_NAME} bash -c "[ -f /root/.ssh/authorized_keys ] || ( install -D -m 600 /dev/null /root/.ssh/authorized_keys && chmod 700 /root/.ssh )"
        docker exec -it ${_NAME} bash -c "grep -q \"^`cat ~/.ssh/id_rsa.pub`\" /root/.ssh/authorized_keys || echo \"`cat ~/.ssh/id_rsa.pub`\" >> /root/.ssh/authorized_keys"
    fi
    docker exec -it ${_NAME} bash -c '[ ! -d /home/admin ] && mkdir -m 700 /home/admin && chown admin:admin /home/admin'
    # for Knox LDAP demo users
    docker exec -it ${_NAME} bash -c '[ ! -d /home/tom ] && useradd tom'
    docker exec -it ${_NAME} bash -c '[ ! -d /home/sam ] && useradd sam'
    # startup_script modify /etc/resolv.conf so removing
    docker exec -it ${_NAME} bash -c 'grep -q -F "> /etc/resolv.conf" /etc/rc.d/init.d/startup_script && tar -cvzf /root/startup_script.tgz `find /etc/rc.d/ -name '*startup_script'` --remove-files'

    docker exec -it ${_NAME} bash -c "service sshd start"

    # PostgreSQL
    docker exec -it ${_NAME} bash -c "sed -i -r \"s/^#?log_line_prefix = ''/log_line_prefix = '%m '/\" /var/lib/pgsql/data/postgresql.conf"
    docker exec -it ${_NAME} bash -c "sed -i -r \"s/^#?log_statement = 'none'/log_statement = 'mod'/\" /var/lib/pgsql/data/postgresql.conf"
    docker exec -it ${_NAME} bash -c "ln -s /var/lib/pgsql/data/pg_log /var/log/postgresql"
    docker exec -it ${_NAME} bash -c "sysctl -w kernel.shmmax=${_SHMMAX};service postgresql start"
    #docker exec -d ${_NAME} /sbin/sysctl -p

    # MySQL, for Hive, Oozie, Ranger, KMS etc, making sure mysql starts
    docker exec -it ${_NAME} bash -c 'chown -R mysql:mysql /var/lib/mysql /var/run/mysqld'
    docker exec -d ${_NAME} service mysqld start
    # TODO: may need to reset root db user password
    # mysql -uroot -phadoop mysql -e "select user, host from user where User='root' and Password =''"
    # mysql -uroot -phadoop mysql -e "set password for 'root'@'%'= PASSWORD('hadoop')"

    if ${_NEW_CONTAINER} ; then
        echo "INFO: New container only OS config changes..."
        docker exec -it ${_NAME} bash -c "chpasswd <<< root:hadoop"
        # In case -v /hadoop was used. TODO: the following three lines should be removed later
        docker exec -it ${_NAME} bash -c 'rm -rf /hadoop/yarn/{local,log}'
        docker exec -it ${_NAME} bash -c 'cd /hadoop && for _n in `ls -1`; do chown -R $_n:hadoop ./$_n 2>/dev/null; done'
        docker exec -it ${_NAME} bash -c 'chown -R mapred:hadoop /hadoop/mapreduce'

        # As of this typing, sandbox repo for tutorial is broken so moving out for now
        docker exec -it ${_NAME} bash -c 'mv /etc/yum.repos.d/sandbox.repo /root/' &>/dev/null
        docker exec -dt ${_NAME} yum -q -y install yum-utils sudo which vim net-tools strace lsof tcpdump openldap-clients nc sharutils

        echo "INFO: New container only Ambari config changes, public_hostname_script, admin password, java.home urandom..."
        # (optional) Fixing public hostname (169.254.169.254 issue) by appending public_hostname.sh"
        docker exec -it ${_NAME} bash -c 'grep -q "^public_hostname_script" /etc/ambari-agent/conf/ambari-agent.ini || ( echo -e "#!/bin/bash\necho \`hostname -f\`" > /var/lib/ambari-agent/public_hostname.sh && chmod a+x /var/lib/ambari-agent/public_hostname.sh && sed -i.bak "/run_as_user/i public_hostname_script=/var/lib/ambari-agent/public_hostname.sh\n" /etc/ambari-agent/conf/ambari-agent.ini )'
        docker exec -it ${_NAME} bash -c "ambari-agent reset ${_HOSTNAME}"
        #docker exec -it ${_NAME} /usr/sbin/ambari-admin-password-reset
        docker exec -it ${_NAME} bash -c "(set -x;[ -S /tmp/.s.PGSQL.5432 ] || (sleep 5;service postgresql restart;sleep 5); PGPASSWORD=bigdata psql -h ${_HOSTNAME} -Uambari -tAc \"UPDATE users SET user_password='538916f8943ec225d97a9a86a2c6ec0818c1cd400e09e03b660fdaaec4af29ddbb6f2b1033b81b00', active=1 WHERE user_name='admin' and user_type='LOCAL';UPDATE hosts set host_name='${_HOSTNAME}', public_host_name='${_HOSTNAME}' where host_id=1;\")"
        #docker exec -it ${_NAME} bash -c "PGPASSWORD=bigdata psql -h ${_HOSTNAME}  -Uambari -tAc \"UPDATE metainfo SET metainfo_value = '${_AMBARI_VERSION}' where metainfo_key = 'version';\""
        docker exec -it ${_NAME} bash -c '_javahome="`grep java.home /etc/ambari-server/conf/ambari.properties | cut -d "=" -f2`" && grep -q "^securerandom.source=file:/dev/random" ${_javahome%/}/jre/lib/security/java.security && sed -i.bak -e "s/^securerandom.source=file:\/dev\/random/securerandom.source=file:\/dev\/urandom/" ${_javahome%/}/jre/lib/security/java.security'
    fi

    echo "INFO: Starting Ambari Server & Agent, and Knox Demo LDAP ..."
    docker exec -d ${_NAME} service ambari-server start --skip-database-check
    docker exec -d ${_NAME} service ambari-agent start
    docker exec -d ${_NAME} bash -c 'sudo -u knox -i /usr/hdp/current/knox-server/bin/ldap.sh start'

    #docker exec -d ${_NAME} /root/start_sandbox.sh
    #docker exec -d ${_NAME} /etc/init.d/shellinaboxd start
    #docker exec -d ${_NAME} /etc/init.d/tutorials start

    # NOTE: docker exec add '$' and '\r'
    _NETWORK_ADDR=`ssh -q ${_HOSTNAME} hostname -i | sed 's/\(.\+\)\.[0-9]\+$/\1/'`
    if [ -n "$_NETWORK_ADDR" ]; then
        echo "INFO: Removing ${_NETWORK_ADDR%.}.0/24 via 0.0.0.0 which prevents container access ${_NETWORK_ADDR%.}.1 ..."
        docker exec -it ${_NAME} bash -c "ip route del ${_NETWORK_ADDR%.}.0/24 via 0.0.0.0 || ip route del ${_NETWORK_ADDR%.}.0/16 via 0.0.0.0"

        if nc -z ${_NETWORK_ADDR%.}.1 28080; then
            docker exec -it ${_NAME} bash -c "grep -q ^proxy /etc/yum.conf || echo \"proxy=http://${_NETWORK_ADDR%.}.1:28080\" >> /etc/yum.conf"
        fi
    fi

    echo "INFO: Waiting Ambari Server is ready (feel free to press Ctrl+c to exit)..."
    f_ambari_wait ${_HOSTNAME} ${_AMBARI_PORT}

    if ${_NEW_CONTAINER} ; then
        echo "INFO: Starting minimum services after 5 seconds:..."
        sleep 5
        f_service "ZEPPELIN SPARK SPARK2 STORM FALCON OOZIE FLUME ATLAS HBASE KAFKA" "STOP" "${_HOSTNAME}"
        f_service "ZOOKEEPER AMBARI_INFRA RANGER HDFS MAPREDUCE2 YARN HIVE" "START" "${_HOSTNAME}"
    else
        f_ambari_start_all
    fi
    echo ""
    echo "*** Completed! ***"
    #docker exec -it ${_NAME} bash
fi
