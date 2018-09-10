#!/usr/bin/env bash

function usage() {
    echo "$BASH_SOURCE [-c|-s|-h] [container name] [version]

This script does the followings:
    -c
        If docker image does not exist, create one and create a container if the given named one does not exist
        Install necessary services if not installed yet in the container (the version can be specified)
    -s
        Start a docker container if the given name exists, and stat services in the container
    -h
        To see this message
"
}

[ -z "${_VERSION}" ] && _VERSION="${1:-7.1.2}"          # Default software version, mainly used to find the right installer file
[ -z "${_NAME}" ] && _NAME="as-sandbox"                 # Default container name


### Functions used to build and setup a container
function f_useradd() {
    local __doc__="Add user in a node (container)"
    local _user="${1}"
    local _password="${2}"  # Optional. If empty, will be username-password
    local _container="${3-${_NAME}}"
    [ -z "$_user" ] && return 1
    [ -z "$_password" ] && _password="${_user}-password"
    [ -z "$_container" ] && _container=`docker ps --format "{{.Names}}" | grep -m1 -i '^sandbox'`

    docker exec -it ${_container} bash -c 'useradd '$_user' -s `which bash` -p $(echo "'$_password'" | openssl passwd -1 -stdin) && usermod -a -G users '$_user || return $?
    docker exec -it ${_container} bash -c "which hdfs || exit; sudo -u hdfs bash -c \"kinit -kt /etc/security/keytabs/hdfs.headless.keytab hdfs-${_cluster} &>/dev/null; hdfs dfs -mkdir /user/$_user && hdfs dfs -chown $_user:hadoop /user/$_user\""
    if which kadmin.local; then
        kadmin.local -q "add_principal -pw $_password $_user"
    fi
}

function f_ssh_config() {
    local __doc__="Copy keys and setup authorized key to a node (container)"
    local _name="${1-$_NAME}"
    local _key="$2"
    local _pub_key="$3"
    # ssh -q -oBatchMode=yes ${_name} echo && return 0

    if [ -z "${_key}" ] && [ -r ~/.ssh/id_rsa ]; then
        _key=~/.ssh/id_rsa
    fi

    if [ -z "${_pub_key}" ] && [ -r ~/.ssh/id_rsa.pub ]; then
        _pub_key=~/.ssh/id_rsa.pub
    fi

    docker exec -it ${_name} bash -c "[ -f /root/.ssh/authorized_keys ] || ( install -D -m 600 /dev/null /root/.ssh/authorized_keys && chmod 700 /root/.ssh )"
    docker exec -it ${_name} bash -c "[ -f /root/.ssh/id_rsa.orig ] && exit; [ -f /root/.ssh/id_rsa ] && mv /root/.ssh/id_rsa /root/.ssh/id_rsa.orig; echo \"`cat ${_key}`\" > /root/.ssh/id_rsa; chmod 600 /root/.ssh/id_rsa;echo \"`cat ${_pub_key}`\" > /root/.ssh/id_rsa.pub; chmod 644 /root/.ssh/id_rsa.pub"
    docker exec -it ${_name} bash -c "grep -q \"^`cat ${_pub_key}`\" /root/.ssh/authorized_keys || echo \"`cat ${_pub_key}`\" >> /root/.ssh/authorized_keys"
    docker exec -it ${_name} bash -c "[ -f /root/.ssh/config ] || echo -e \"Host *\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\" > /root/.ssh/config"
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



main() {
    if [ -n "${_UPDATE_CODE}" ] && ${_UPDATE_CODE}; then
        curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/start_sandbox.sh -o "$BASH_SOURCE"
        exit
    fi

    if [ -n "${_LIST_SANDBOX_CONTAINERS}" ] && ${_LIST_SANDBOX_CONTAINERS}; then
        docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.RunningFor}}\t{{.Status}}\t{{.Networks}}\t{{.Mounts}}"
        exit
    fi

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

    if [ ! -s /etc/docker/daemon.json ] && [ ! -s $HOME/.docker/daemon.json ]; then
        echo "WARN: daemon.json is not configured
If you would like to fis this now, press Ctrl+c to stop (sleep 7 seconds)"
        sleep 7
    fi

    # To use tcpdump from container
    if which apparmor_parser &>/dev/null; then
        if [ ! -L /etc/apparmor.d/disable/usr.sbin.tcpdump ]; then
            ln -sf /etc/apparmor.d/usr.sbin.tcpdump /etc/apparmor.d/disable/
            apparmor_parser -R /etc/apparmor.d/usr.sbin.tcpdump
        fi

        # To use mysql from container
        if [ ! -L /etc/apparmor.d/disable/usr.sbin.mysqld ]; then
            ln -sf /etc/apparmor.d/usr.sbin.mysqld /etc/apparmor.d/disable/
            apparmor_parser -R /etc/apparmor.d/usr.sbin.mysqld
        fi
    fi

    _HOST_HDP_IP=`ifconfig $_CUSTOM_NETWORK | grep -oE 'inet addr:\d+\.\d+\.\d+\.\d+' | cut -d":" -f2`

    echo "INFO: Waiting for docker daemon to start up:"
    until docker ps 2>&1| grep -q STATUS; do  sleep 1; done;  >/dev/null

    if [ -n "${_STOP_SANDBOX_CONTAINERS}" ] && ${_STOP_SANDBOX_CONTAINERS}; then
        if docker ps --format "{{.Names}}" | grep -vE "^${_NAME}$"; then    # | grep -qiE "^sandbox"
            echo "INFO: Stopping other container(s)"
            docker stop `docker ps --format "{{.Names}}" | grep -vE "^${_NAME}$"`
        fi
    fi

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
            -p 6667:6667 \
            -p 6668:6668 \
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
            -p 8081:8081 \
            -p 8082:8082 \
            -p 8083:8083 \
            -p 8086:8086 \
            -p 8088:8088 \
            -p 8090:8090 \
            -p 8091:8091 \
            -p 8100:8100 \
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

    echo "INFO: OS config changes, and starting SSHd, and stopping unnecessary services ..."
    # setting up password-less ssh to sandbox whenever it starts in case .ssh is updated.
    f_ssh_config
    docker exec -it ${_NAME} bash -c '[ ! -d /home/admin ] && mkdir -m 700 /home/admin && chown admin:admin /home/admin'
    # for Knox LDAP demo users
    docker exec -it ${_NAME} bash -c '[ ! -d /home/tom ] && useradd tom'
    docker exec -it ${_NAME} bash -c '[ ! -d /home/sam ] && useradd sam'
    # startup_script modify /etc/resolv.conf so removing
    #docker exec -it ${_NAME} bash -c 'grep -q -F "> /etc/resolv.conf" /etc/rc.d/init.d/startup_script && tar -cvzf /root/startup_script.tgz `find /etc/rc.d/ -name '*startup_script' -o -name '*tutorials'` --remove-files'

    docker exec -it ${_NAME} bash -c "service sshd start"
    docker exec -dt ${_NAME} bash -c 'service startup_script stop; service tutorials stop; service shellinaboxd stop; service httpd stop; service hue stop'

    if ${_NEW_CONTAINER} ; then
        echo "INFO: New container only: OS & PostgreSQL config changes..."

        # PostgreSQL
        docker exec -it ${_NAME} bash -c "sed -i -r \"s/^#?log_line_prefix = ''/log_line_prefix = '%m '/\" /var/lib/pgsql/data/postgresql.conf"
        docker exec -it ${_NAME} bash -c "sed -i -r \"s/^#?log_statement = 'none'/log_statement = 'mod'/\" /var/lib/pgsql/data/postgresql.conf"
        docker exec -it ${_NAME} bash -c "[ -d /var/log/postgresql ] || ln -s /var/lib/pgsql/data/pg_log /var/log/postgresql"
        docker exec -it ${_NAME} bash -c "sysctl -w kernel.shmmax=${_SHMMAX};service postgresql restart"
        #docker exec -d ${_NAME} /sbin/sysctl -p

        docker exec -it ${_NAME} bash -c 'chkconfig startup_script off ; chkconfig tutorials off; chkconfig shellinaboxd off; chkconfig hue off; chkconfig httpd off'
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
        #curl -s -u admin:admin -H 'X-Requested-By:ambari' "http://${_HOSTNAME}:8080/api/v1/users/admin" -X PUT -d '{"Users/pasword":"admin","Users/old_password":"admin"}'
        docker exec -it ${_NAME} bash -c "(set -x;[ -S /tmp/.s.PGSQL.5432 ] || (sleep 5;service postgresql restart;sleep 5); PGPASSWORD=bigdata psql -h ${_HOSTNAME} -Uambari -tAc \"UPDATE users SET user_password='538916f8943ec225d97a9a86a2c6ec0818c1cd400e09e03b660fdaaec4af29ddbb6f2b1033b81b00', active=1 WHERE user_name='admin' and user_type='LOCAL';UPDATE hosts set host_name='${_HOSTNAME}', public_host_name='${_HOSTNAME}' where host_id=1;\")"
        #docker exec -it ${_NAME} bash -c "PGPASSWORD=bigdata psql -h ${_HOSTNAME}  -Uambari -tAc \"UPDATE metainfo SET metainfo_value = '${_AMBARI_VERSION}' where metainfo_key = 'version';\""
        docker exec -it ${_NAME} bash -c '_javahome="`grep java.home /etc/ambari-server/conf/ambari.properties | cut -d "=" -f2`" && grep -q "^securerandom.source=file:/dev/random" ${_javahome%/}/jre/lib/security/java.security && sed -i.bak -e "s/^securerandom.source=file:\/dev\/random/securerandom.source=file:\/dev\/urandom/" ${_javahome%/}/jre/lib/security/java.security'

        docker exec -it ${_NAME} bash -c 'chown -R mysql:mysql /var/lib/mysql /var/run/mysqld'
    fi

    echo "INFO: Starting mysql ..."
    # MySQL, for Hive, Oozie, Ranger, KMS etc, making sure mysql starts
    docker exec -d ${_NAME} bash -c 'service mysqld restart'
    # TODO: may need to reset root db user password
    # mysql -uroot -phadoop mysql -e "select user, host from user where User='root' and Password =''"
    # mysql -uroot -phadoop mysql -e "set password for 'root'@'%'= PASSWORD('hadoop')"

    #docker exec -d ${_NAME} /root/start_sandbox.sh
    #docker exec -d ${_NAME} /etc/init.d/shellinaboxd start
    #docker exec -d ${_NAME} /etc/init.d/tutorials start

    # NOTE: docker exec add '$' and '\r'
    _NETWORK_ADDR=`ssh -q -p 2222 root@localhost hostname -i | sed 's/\(.\+\)\.[0-9]\+$/\1/'`
    if [ -n "$_NETWORK_ADDR" ]; then
        echo "INFO: Removing ${_NETWORK_ADDR%.}.0/24 via 0.0.0.0 which prevents container access ${_NETWORK_ADDR%.}.1 ..."
        docker exec -it ${_NAME} bash -c "ip route del ${_NETWORK_ADDR%.}.0/24 via 0.0.0.0 || ip route del ${_NETWORK_ADDR%.}.0/16 via 0.0.0.0"

        if nc -z ${_NETWORK_ADDR%.}.1 28080; then
            docker exec -it ${_NAME} bash -c "grep -q ^proxy /etc/yum.conf || echo \"proxy=http://${_NETWORK_ADDR%.}.1:28080\" >> /etc/yum.conf"
        fi
    fi

    echo "INFO: Starting Ambari Server & Agent, and Knox Demo LDAP ..."
    docker exec -d ${_NAME} bash -c 'sudo -u knox -i /usr/hdp/current/knox-server/bin/ldap.sh start'
    docker exec -d ${_NAME} service ambari-agent start
    if ! nc -z ${_HOSTNAME} ${_AMBARI_PORT}; then
        docker exec -d ${_NAME} bash -c 'service postgresql start; service ambari-server start --skip-database-check || (service postgresql start;sleep 5;service ambari-server restart --skip-database-check)' || exit $?
    fi

    echo "INFO: Waiting Ambari Server is ready (feel free to press Ctrl+c to exit)..."
    f_ambari_wait ${_HOSTNAME} ${_AMBARI_PORT}

    if ${_NEW_CONTAINER}; then
        echo "INFO: Starting minimum services after 5 seconds:..."
        sleep 5
        if [[ "${_NAME}" =~ "-hdf" ]]; then
            f_service "STORM KAFKA LOGSEARCH" "STOP" "${_HOSTNAME}"
        else
            f_service "ZEPPELIN SPARK SPARK2 STORM FALCON OOZIE FLUME ATLAS HBASE KAFKA" "STOP" "${_HOSTNAME}"
        fi
    fi
    f_ambari_start_all
    echo ""
    echo "*** Completed! ***"
    #docker exec -it ${_NAME} bash
}

if [ "$0" = "$BASH_SOURCE" ]; then
    #_NAME="sandbox-hdp"
    _NEW_CONTAINER=${_NEW_CONTAINER:-false}
    _STOP_SANDBOX_CONTAINERS=false
    _LIST_SANDBOX_CONTAINERS=false
    _UPDATE_CODE=false

    # parsing command options
    while getopts "m:n:h:i:slu" opts; do
        case $opts in
            h)
                _HOSTNAME="$OPTARG"
                ;;
            i)
                _IP="$OPTARG"
                ;;
            l)
                _LIST_SANDBOX_CONTAINERS=true
                ;;
            m)
                _IMAGE="$OPTARG"
                ;;
            n)
                _NAME="$OPTARG"
                ;;
            s)
                _STOP_SANDBOX_CONTAINERS=true
                ;;
            u)
                _UPDATE_CODE=true
                ;;
        esac
    done

    main()
fi
