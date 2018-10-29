#!/usr/bin/env bash
# NOTE: shouldn't use OS dependant command, such as apt-get, yum, brew etc.

function usage() {
    echo "$BASH_SOURCE -c -v ${_VERSION} [-n <container_name>] [-s] [-l /path/to/dev-license.json]

This script is for building a docker container for standalone/sandbox for testing in dev env, and does the followings:

CREATE IMAGE/CONTAINER:
    -c [-v <version>|-n <container_name>]
        Create a docker image for Standalone/Sandbox
        Docker container will be created if -n <container_name> or -v <version> is provided.
        Then installs necessary service in the container.

START CONTAINER:
    -n <container_name>     <<< no '-c'
        Start a docker container of the given name (hostname), and start services in the container.

    -v <version>            <<< no '-c'
        Start a docker container of this version, and start services in the container.

SAVE CONTAINER:
    -s -n <container_name>
        Save this container as image, so that creating a container will be faster.
        NOTE: this operation takes time.

OTHERS:
    -N
        Not installing Application Service or starting, just creating a container.

    -P
        Use with -c to use docker's port forwarding for the application

    -R
        Re-use the image. Default is not re-using image and create a container from base.
        If this option is used, if similar image name exist, will create a container from that image.

    -S
        Use with -c, -n, -v to stop any other port conflicting containers.
        When -P is used or the host is Mac, this option would be needed.

    -l /path/to/dev-license.json
        A path to the software licene file

    -u
        Update this script to the latest

    -h
        To see this message

NOTES:
    This script assumes your application is stored under /usr/local/_SERVICE.
"
    docker stats --no-stream
}


### Default values
[ -z "${_WORK_DIR}" ] && _WORK_DIR="/var/tmp/share"     # If Mac, may need to be /private/var/tmp/share
[ -z "${_SHARE_DIR}" ] && _SHARE_DIR="/var/tmp/share"   # Docker container's share dir (normally same as _WORK_DIR except Mac)
#_DOMAIN_SUFFIX="$(echo `hostname -s` | sed 's/[^a-zA-Z0-9_]//g').localdomain"
[ -z "${_DOMAIN}" ] && _DOMAIN="standalone.localdomain" # Default container domain suffix
[ -z "${_OS_VERSION}" ] && _OS_VERSION="7.5.1804"       # Container OS version (normally CentOS version)
[ -z "${_IMAGE_NAME}" ] && _IMAGE_NAME="hdp/base"       # Docker image name TODO: change to more appropriate image name
[ -z "${_SERVICE}" ] && _SERVICE="atscale"              # This is used by the app installer script so shouldn't change
[ -z "${_VERSION}" ] && _VERSION="7.3.0"                # Default software version, mainly used to find the right installer file
[ -z "${_LICENSE}" ] && _LICENSE="$(ls -1t ${_WORK_DIR%/}/${_SERVICE%/}/dev*license*.json | head -n1)" # A license file to use the _SERVICE
_PORTS="${_PORTS-"10500 10501 10502 10503 10504 10508 10516 11111 11112 11113"}"    # Used by docker port forwarding
_REMOTE_REPO="${_REMOTE_REPO-"http://192.168.6.162/${_SERVICE}/"}"                  # Curl understandable string
#_CUSTOM_NETWORK="hdp"

_CREATE_AND_SETUP=false
_DOCKER_PORT_FORWARD=false
_DOCKER_STOP_OTHER=false
_DOCKER_SAVE=false
_DOCKER_REUSE_IMAGE=false
_AS_NO_INSTALL_START=false
_SUDO_SED=false


### Functions used to build and setup a container
function f_update() {
    local __doc__="Download the latest code from git and replace"
    local _target="${1:-${BASH_SOURCE}}"
    local _remote_repo="${2:-"https://raw.githubusercontent.com/hajimeo/samples/master/bash/"}"

    local _file_name="`basename ${_target}`"
    local _backup_file="/tmp/${_file_name}_$(date +"%Y%m%d%H%M%S")"
    if [ -f "${_target}" ]; then
        local _remote_length=`curl -m 4 -s -k -L --head "${_remote_repo%/}/${_file_name}" | grep -i '^Content-Length:' | awk '{print $2}' | tr -d '\r'`
        local _local_length=`wc -c <${_target}`
        if [ "${_remote_length}" -lt $(( ${_local_length} / 2 )) ] || [ ${_remote_length} -eq ${_local_length} ]; then
            _log "INFO" "Not updating ${_target}"
            return 0
        fi

        cp "${_target}" "${_backup_file}" || return $?
    fi

    curl -s -f --retry 3 "${_remote_repo%/}/${_file_name}" -o "${_target}"
    if [ $? -ne 0 ]; then
        # Restore from backup
        mv -f "${_backup_file}" "${_target}"
        return 1
    fi
    if [ -f "${_backup_file}" ]; then
        local _length=`wc -c <${_target}`
        local _old_length=`wc -c <${_backup_file}`
        if [ ${_length} -lt $(( ${_old_length} / 2 )) ]; then
            mv -f "${_backup_file}" "${_target}"
            return 1
        fi
    fi
    _log "INFO" "Script has been updated. Backup: ${_backup_file}"
}

function f_update_hosts_file_by_fqdn() {
    local __doc__="Update hosts file with given hostname (FQDN) and IP"
    local _hostname="${1}"
    local _name="`echo "${_hostname}" | cut -d"." -f1`"

    local _hosts_file="/etc/hosts"
    which dnsmasq &>/dev/null && [ -f /etc/banner_add_hosts ] && _hosts_file="/etc/banner_add_hosts"

    if ! docker ps --format "{{.Names}}" | grep -qE "^${_name}$"; then
        _log "WARN" "${_name} is NOT running. Please check and update ${_hosts_file} manually."
        return 1
    fi

    local _container_ip="`docker exec -it ${_name} hostname -i | tr -cd "[:print:]"`"   # tr to remove unnecessary control characters
    if [ -z "${_container_ip}" ]; then
        _log "WARN" "${_name} is running but not returning IP. Please check and update ${_hosts_file} manually."
        return 1
    fi

    # If no root user, uses "sudo" in sed
    if [ "$USER" != "root" ]; then
        _SUDO_SED=true
        _log "INFO" "Updating ${_hosts_file}. It may ask your sudo password."
    fi

    # If port forwarding is used, better use localhost
    $_DOCKER_PORT_FORWARD && _container_ip="127.0.0.1"
    f_update_hosts_file "${_hostname}" "${_container_ip}" "${_hosts_file}" ||  _log "WARN" "Please update ${_hosts_file} to add '${_container_ip} ${_hostname}'"

    which dnsmasq &>/dev/null && service dnsmasq reload
}

function f_update_hosts_file() {
    local __doc__="Update hosts file with given hostname (FQDN) and IP"
    local _fqdn="$1"
    local _ip="$2"
    local _file="${3:-"/etc/hosts"}"

    if [ -z "${_fqdn}" ]; then
        _log "ERROR" "hostname is required"; return 11
    fi
    local _name="`echo "${_fqdn}" | cut -d"." -f1`"

    if [ -z "${_ip}" ]; then
        _log "ERROR" "IP is required"; return 12
    fi

    # Checking if this combination is already in the hosts file. TODO: this regex is not perfect
    local _ip_in_hosts="$(_sed -nr "s/^([0-9.]+).*\s${_fqdn}.*$/\1/p" ${_file})"
    [ "${_ip_in_hosts}" = "${_ip}" ] && return 0

    # Take backup before modifying
    cp ${_file} /tmp/hosts_$(date +"%Y%m%d%H%M%S")

    # Remove the hostname and unnecessary line
    _sed -i -r "s/\s${_fqdn} ${_name}\s?/ /" ${_file}
    _sed -i -r "s/\s${_fqdn}\s?/ /" ${_file}
    _sed -i -r "/^${_ip_in_hosts}\s+$/d" ${_file}

    # If IP already exists, append the hostname in the end of line
    if grep -qE "^${_ip}\s+" ${_file}; then
        _sed -i -r "/^${_ip}\s+/ s/\s*$/ ${_fqdn} ${_name}/" ${_file}
        return $?
    fi

    if [ -z "${_ip_in_hosts}" ] || [ "${_ip_in_hosts}" != "${_ip}" ]; then
        _sed -i -e "\$a${_ip} ${_fqdn} ${_name}" ${_file}
    fi
}

function _gen_dockerFile() {
    local __doc__="Download dockerfile and replace few strings"
    local _url="${1}"
    local _os_and_ver="${2}"
    local _new_filepath="${3}"
    [ -z "${_new_filepath}" ] && _new_filepath="./$(basename "${_url}")"

    if [ -s ${_new_filepath} ]; then
        # only one backup would be enough
        mv -f ${_new_filepath} /tmp/${_new_filepath}.bak
    fi

    curl -s --retry 3 "${_url}" -o ${_new_filepath}

    # make sure ssh key is set up to replace Dockerfile's _REPLACE_WITH_YOUR_PRIVATE_KEY_
    if [ -s $HOME/.ssh/id_rsa ]; then
        local _pkey="`_sed ':a;N;$!ba;s/\n/\\\\\\\n/g' $HOME/.ssh/id_rsa`"
        _sed -i "s@_REPLACE_WITH_YOUR_PRIVATE_KEY_@${_pkey}@1" ${_new_filepath}
    else
        _log "WARN" "No private key to replace _REPLACE_WITH_YOUR_PRIVATE_KEY_"
    fi

    [ -z "$_os_and_ver" ] || _sed -i "s/FROM centos.*/FROM ${_os_and_ver}/" ${_new_filepath}
}

function f_docker_base_create() {
    local __doc__="Create a docker base image (f_docker_base_create ./Dockerfile centos 6.8)"
    local _docker_file="${1:-DockerFile7}"
    local _os_name="${2:-centos}"
    local _os_ver_num="${3:-${_OS_VERSION}}"
    local _force_build="${4}"

    local _base="${_IMAGE_NAME}:$_os_ver_num"

    if [[ ! "$_force_build" =~ ^(y|Y) ]]; then
        local _existing_id="`docker images -q ${_base}`"
        if [ -n "${_existing_id}" ]; then
            _log "INFO" "Skipping creating ${_base} as already exists. Please run 'docker rmi ${_existing_id}' to recreate."
            return 0
        fi
    fi

    if [ ! -s "${_docker_file}" ]; then
        _gen_dockerFile "https://raw.githubusercontent.com/hajimeo/samples/master/docker/${_docker_file}" "${_os_name}:${_os_ver_num}" "${_docker_file}" || return $?
    fi

    #_local_docker_file="`realpath "${_local_docker_file}"`"
    if [ ! -r "${_docker_file}" ]; then
        _log "ERROR" "${_docker_file} is not readable"
        return 1
    fi

    if ! docker images | grep -E "^${_os_name}\s+${_os_ver_num}"; then
        _log "INFO" "pulling OS image ${_os_name}:${_os_ver_num} ..."
        docker pull ${_os_name}:${_os_ver_num} || return $?
    fi
    # "." is not good if there are so many files/folders but https://github.com/moby/moby/issues/14339 is unclear
    local _build_dir="$(mktemp -d)" || return $?
    mv ${_docker_file} ${_build_dir%/}/DockerFile || return $?
    cd ${_build_dir} || return $?
    docker build -f ${_build_dir%/}/DockerFile -t ${_base} . || return $?
    cd -
}

function f_docker_run() {
    local __doc__="Execute docker run with my preferred options"
    local _hostname="$1"
    local _base="$2"
    local _ports="${3}"      #"10500 10501 10502 10503 10504 10508 10516 11111 11112 11113"
    local _extra_opts="${4}" # eg: "--add-host=imagename.standalone:127.0.0.1"
    local _stop_other=${5:-${_DOCKER_STOP_OTHER}}
    local _share_dir_from="${6:-${_WORK_DIR}}"
    local _share_dir_to="${7:-${_SHARE_DIR}}"
    # NOTE: At this moment, removed _ip as it requires a custom network (see start_hdp.sh for how)

    local _name="`echo "${_hostname}" | cut -d"." -f1`"
    [ ! -d "${_share_dir_from%/}" ] && mkdir -p -m 777 "${_share_dir_from%/}"

    _line="`docker ps -a --format "{{.Names}}" | grep -E "^${_name}$"`"
    if [ -n "$_line" ]; then
        _log "WARN" "Container name ${_name} already exists. Skipping..."; sleep 1
        return 0
    fi

    # NOTE: to add more port, use 'docker port <container> <guest port>'
    local _port_opts=""
    for _p in $_ports; do
        local _pid="`lsof -ti:${_p} | head -n1`"
        if [ -n "${_pid}" ]; then
            if ${_stop_other}; then
                local _cname="`_docker_find_by_port ${_p}`"
                if [ -n "${_cname}" ]; then
                    _log "INFO" "Stopping ${_cname} container..."
                    docker stop -t 7 ${_cname}
                fi
            else
                _log "ERROR" "Docker run could not use the port ${_p} as it's used by pid:${_pid}"docker inspect -format="{{ .NetworkSettings.IPAddress }}"
                return 1
            fi
        fi
        _port_opts="${_port_opts} -p ${_p}:${_p}"
    done
    [ -n "${_port_opts}" ] && ! lsof -ti:22222 && _port_opts="${_port_opts} -p 22222:22"


    local _network=""   # TODO: without specifying IP, no point of using custom network
    #if docker network ls | grep -qw "$_CUSTOM_NETWORK"; then
    #    _network="--network=${_CUSTOM_NETWORK}"
    #fi

    local _dns=""
    # If dnsmasq is installed, assuming it's setup correctly
    if which dnsmasq &>/dev/null; then
        _dns="--dns=`hostname -i`"
    fi

    #    -v /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket \
    docker run -t -i -d \
        -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
        -v ${_share_dir_from%/}:${_share_dir_to%/} ${_port_opts} ${_network} ${_dns} \
        --privileged --hostname=${_hostname} --name=${_name} ${_extra_opts} ${_base} /sbin/init || return $?

    f_update_hosts_file_by_fqdn "${_hostname}"
}

function p_container_setup() {
    local _name="${1:-${_NAME}}"
    local _service="${2:-${_SERVICE}}"

    _log "INFO" "Setting up ${_name} container..."
    f_container_useradd "${_name}" "${_service}" || return $?
    f_container_ssh_config "${_name}"   # it's OK to fail || return $?
    f_container_misc "${_name}"         # it's OK to fail || return $?
    return 0
}

function f_docker_start() {
    local __doc__="Starting one docker container (TODO: with a few customization)"
    local _hostname="$1"    # short name is also OK
    local _stop_other=${2:-${_DOCKER_STOP_OTHER}}

    local _name="`echo "${_hostname}" | cut -d"." -f1`"

    if docker ps --format "{{.Names}}" | grep -qE "^${_name}$"; then
        _log "INFO" "Container ${_name} is already running."
        return
    fi

    if ${_stop_other}; then
        # Probably --filter can do better...
        for _p in `docker inspect ${_name} | python -c "import sys,json;a=json.loads(sys.stdin.read());print ' '.join([l.replace('/tcp', '') for l in a[0]['Config']['ExposedPorts'].keys()])"`; do
            local _cname="`_docker_find_by_port ${_p}`"
            if [ -n "${_cname}" ]; then
                _log "INFO" "Stopping ${_cname} container..."
                docker stop -t 7 ${_cname}
            fi
        done
    fi

    docker start --attach=false ${_name}

    # Somehow docker disable a container communicates to outside by adding 0.0.0.0 GW
    #local _docker_ip="172.17.0.1"
    #local _regex="([0-9]+)\.([0-9]+)\.[0-9]+\.[0-9]+"
    #local _docker_net_addr="172.17.0.0"
    #[[ "${_docker_ip}" =~ $_regex ]] && _docker_net_addr="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.0.0"
    #docker exec -it ${_name} bash -c "ip route del ${_docker_net_addr}/24 via 0.0.0.0 &>/dev/null || ip route del ${_docker_net_addr}/16 via 0.0.0.0"

    f_update_hosts_file_by_fqdn "${_hostname}"
}

function f_as_log_cleanup() {
    local _hostname="$1"    # short name is also OK
    local _service="${2:-${_SERVICE}}"
    local _name="`echo "${_hostname}" | cut -d"." -f1`"
    docker exec -it ${_name} bash -c 'find /usr/local/'${_service}'/{log,share/postgresql-*/data/pg_log} -type f -and \( -name "*.log*" -o -name "postgresql-2*.log" -o -name "*.stdout" \) -and -print0| xargs -0 -P3 -n1 -I {} rm -f {}'
}

function f_docker_commit() {
    local __doc__="Cleaning up unncecessary files and then save a container as an image"
    local _hostname="$1"    # short name is also OK
    local _service="${2:-${_SERVICE}}"

    local _name="`echo "${_hostname}" | cut -d"." -f1`"

    if docker images --format "{{.Repository}}" | grep -qE "^${_name}$"; then
        _log "WARN" "Image ${_name} already exists. Please do 'docker rmi ${_name}' first."; sleep 1
        return
    fi
    if ! docker ps --format "{{.Names}}" | grep -qE "^${_name}$"; then
        _log "INFO" "Container ${_name} is NOT running, so that not cleaning up..."; sleep 1
    fi

    f_as_log_cleanup "${_name}"
    # TODO: need better way, shouldn't be in docker commit function
    docker exec -it ${_name} bash -c 'rm -rf /home/'${_service}'/'${_service}'-*-el6.x86_64;rm -rf /home/'${_service}'/log/*'

    _log "INFO" "Stopping and Committing ${_name} ..."; sleep 1
    docker stop -t 7 ${_name} || return $?
    docker commit ${_name} ${_name} || return $?
    _log "INFO" "Saving ${_name} as image was completed. Feel free to do 'docker rm ${_name}'"; sleep 1
}

function _docker_find_by_port() {
    local _port="$1"
    for _n in `docker ps --format "{{.Names}}"`; do
        if docker port ${_n} | grep -q "^${_port}/"; then
            echo "${_n}"
            return
        fi
    done
    return 1
}

function f_container_misc() {
    local __doc__="Add user in a node (container)"
    local _name="${1:-${_NAME}}"
    local _password="${2-$_SERVICE}"  # Optional. If empty, will be _SERVICE

    docker exec -it ${_name} bash -c "chpasswd <<< root:${_password}"
    docker exec -it ${_name} bash -c "echo -e '\nexport TERM=xterm-256color' >> /etc/profile"
}

function f_container_useradd() {
    local __doc__="Add user in a node (container)"
    local _name="${1:-${_NAME}}"
    local _user="${2:-${_SERVICE}}"
    local _password="${3}"  # Optional. If empty, will be username-password

    [ -z "$_user" ] && return 1
    [ -z "$_password" ] && _password="${_user}-password"

    docker exec -it ${_name} bash -c 'grep -q "^'$_user':" /etc/passwd && exit 0; useradd '$_user' -s `which bash` -p $(echo "'$_password'" | openssl passwd -1 -stdin) && usermod -a -G users '$_user || return $?

    if [ "`uname`" = "Linux" ]; then
        which kadmin.local &>/dev/null && kadmin.local -q "add_principal -pw $_password $_user"
        # it's ok if kadmin.local, fails
        return 0
    fi
}

function f_container_ssh_config() {
    local __doc__="Copy keys and setup authorized key to a node (container)"
    local _name="${1:-${_NAME}}"
    local _key="$2"
    local _pub_key="$3"

    # ssh -q -oBatchMode=yes ${_name} echo && return 0
    [ -z "${_key}" ] && [ -r ~/.ssh/id_rsa ] && _key=~/.ssh/id_rsa
    [ -z "${_pub_key}" ] && [ -r ~/.ssh/id_rsa.pub ] && _pub_key=~/.ssh/id_rsa.pub

    docker exec -it ${_name} bash -c "[ -f /root/.ssh/authorized_keys ] || ( install -D -m 600 /dev/null /root/.ssh/authorized_keys && chmod 700 /root/.ssh )"
    docker exec -it ${_name} bash -c "[ -f /root/.ssh/id_rsa.orig ] && exit; [ -f /root/.ssh/id_rsa ] && mv /root/.ssh/id_rsa /root/.ssh/id_rsa.orig; echo \"`cat ${_key}`\" > /root/.ssh/id_rsa; chmod 600 /root/.ssh/id_rsa;echo \"`cat ${_pub_key}`\" > /root/.ssh/id_rsa.pub; chmod 644 /root/.ssh/id_rsa.pub"
    docker exec -it ${_name} bash -c "grep -q \"^`cat ${_pub_key}`\" /root/.ssh/authorized_keys || echo \"`cat ${_pub_key}`\" >> /root/.ssh/authorized_keys"
    docker exec -it ${_name} bash -c "[ -f /root/.ssh/config ] || echo -e \"Host *\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\" > /root/.ssh/config"
}

function f_as_setup() {
    local __doc__="Install/Setup a specific Application Service for the container"
    local _hostname="$1"
    local _version="${2:-${_VERSION}}"
    local _license="${3:-${_LICENSE}}"
    local _service="${4:-${_SERVICE}}"
    local _work_dir="${5:-${_WORK_DIR}}"
    local _share_dir="${6:-${_SHARE_DIR}}"

    [ ! -d "${_work_dir%/}/${_service%/}" ] && mkdir -p -m 777 "${_work_dir%/}${_service%/}"

    # Get the latest script but it's OK if fails if the file exists
    [ -n "${_REMOTE_REPO}" ] && f_update "${_work_dir%/}/${_service%/}/install_atscale.sh" "${_REMOTE_REPO}"

    if [ ! -s ${_work_dir%/}/${_service%/}/install_atscale.sh ]; then
        _log "ERROR" "Failed to create ${_work_dir%/}/${_service%/}/install_atscale.sh"
        return 1
    fi

    if [ ! -s "${_license}" ]; then
        _log "ERROR" "Please copy a license file as ${_work_dir%/}/${_service%/}/dev-vm-license.json"
        return 1
    fi

    if [ ! -f "${_work_dir%/}/${_service%/}/$(basename "${_license}")" ]; then
        cp ${_license} ${_work_dir%/}/${_service%/}/ || return 11
    fi

    local _name="`echo "${_hostname}" | cut -d"." -f1`"
    docker exec -it ${_name} bash -c "bash ${_share_dir%/}/${_service%/}/install_atscale.sh -v ${_version} -l ${_share_dir%/}/${_service%/}/$(basename "${_license}") -S"
    #ssh -q root@${_hostname} -t "export _STANDALONE=Y;bash ${_share_dir%/}${_user%/}/install_atscale.sh ${_version}"
}

function f_as_start() {
    local __doc__="Start a specific Application Service for the container"
    local _hostname="$1"
    local _service="${2:-${_SERVICE}}"
    local _restart="${3}"
    local _old_hostname="${4}"

    local _name="`echo "${_hostname}" | cut -d"." -f1`"
    [[ "${_restart}" =~ ^(y|Y) ]] && docker exec -it ${_name} bash -c "sudo -u ${_service} /usr/local/${_service}/bin/${_service}_stop -f"
    docker exec -d ${_name} bash -c "sudo -u ${_service} -i /usr/local/apache-hive/apache_hive.sh"
    docker exec -it ${_name} bash -c "sudo -u ${_service} -i /usr/local/${_service}/bin/${_service}_start"
    # Update hostname if old hostname is given
    if [ -n "${_old_hostname}" ]; then
        # NOTE: At this moment, assuming only one postgresql version. Not using 'at' command as minimum time unit is minutes
        _log "INFO" "UPDATE engines SET host='${_hostname}' where default_engine is true AND host='${_old_hostname}'"
        docker exec -it ${_name} bash -c 'cd /usr/local/'${_service}'/share/postgresql-*
for _i in {1..5}; do
  sleep 2
  LD_LIBRARY_PATH=./lib ./bin/pg_isready -p 10520 -q && break
done
sleep 2
sudo -u '${_service}' ./bin/postgres_psql -cl "-c \"UPDATE engines SET host='${_hostname}' where host='${_old_hostname}'\""
'
    fi
}

function f_as_backup() {
    local __doc__="Backup the application directory as tgz file"
    local _name="${1:-${_NAME}}"
    local _service="${2:-${_SERVICE}}"
    local _work_dir="${3:-${_WORK_DIR}}"
    local _share_dir="${4:-${_SHARE_DIR}}"

    [ ! -d "${_work_dir%/}/${_service%/}" ] && mkdir -p -m 777 "${_work_dir%/}${_service%/}"

    local _file_name="${_service}_standalone_${_name}.tgz"

    if [ -s "${_work_dir%/}${_service%/}/${_file_name}" ]; then
        _log "WARN" "${_work_dir%/}${_service%/}/${_file_name} already exists. Please remove this first."; sleep 3
        return 1
    fi

    f_as_log_cleanup "${_name}"
    docker exec -it ${_name} bash -c 'sudo -u '${_service}' /usr/local/'${_service}'/bin/atscale_service_control stop all;for _i in {1..4}; do lsof -ti:10520 -s TCP:LISTEN || break;sleep 3;done'
    docker exec -it ${_name} bash -c 'cp -p /home/'${_service}'/custom.yaml /usr/local/'${_service}'/custom.bak.yaml &>/dev/null'
    _log "INFO" "Creating '${_share_dir%/}/${_service%/}/${_file_name}' from /usr/local/${_service%/}"; sleep 1
    docker exec -it ${_name} bash -c 'tar -chzf '${_share_dir%/}'/'${_service%/}'/'${_file_name}' -C /usr/local/ '${_service%/}''

    if [ ! -s "${_work_dir%/}/${_service%/}/${_file_name}" ] || [ 2097152 -gt "`wc -c <${_work_dir%/}/${_service%/}/${_file_name}`" ]; then
        _log "ERROR" "Backup to ${_work_dir%/}/${_service%/}/${_file_name} failed"; sleep 3
        return 1
    fi
    _log "INFO" "Backup to ${_work_dir%/}/${_service%/}/${_file_name} completed"
}

function f_as_restore() {
    local __doc__="Restore the application directory from a tgz file which filename is generated from the _name and _service"
    local _name="${1:-${_NAME}}"
    local _service="${2:-${_SERVICE}}"
    local _work_dir="${3:-${_WORK_DIR}}"
    local _share_dir="${4:-${_SHARE_DIR}}"

    [ ! -d "${_work_dir%/}/${_service%/}" ] && mkdir -p -m 777 "${_work_dir%/}${_service%/}"

    local _file_name="${_service}_standalone_${_name}.tgz"

    if [ ! -s "${_work_dir%/}${_service%/}/${_file_name}" ] && [ -n "$_REMOTE_REPO" ]; then
        _log "INFO" "${_work_dir%/}${_service%/}/${_file_name} does not exist, so that downloading from $_REMOTE_REPO ..."; sleep 1
        curl --retry 3 -f -C - -o "${_work_dir%/}${_service%/}/${_file_name}" "${_REMOTE_REPO%/}/${_file_name}" || return $?
    fi

    _log "INFO" "Restoring ${_file_name} on the container"; sleep 1
    docker exec -it ${_name} bash -c 'source '${_share_dir%/}'/'${_service%/}'/install_atscale.sh && f_atscale_restore "'${_share_dir%/}'/'${_service%/}'/'${_file_name}'"' || return $?
}

function f_install_as() {
    local _name="${1:-$_NAME}"
    local _version="${2:-$_VERSION}"
    local _base="$3"
    local _ports="${4}"      #"10500 10501 10502 10503 10504 10508 10516 11111 11112 11113"
    local _extra_opts="${5}" # eg: "--add-host=imagename.standalone:127.0.0.1"

    # Creating a new (empty) container and install the application
    f_docker_run "${_name}.${_DOMAIN#.}" "${_base}" "${_ports}" "${_extra_opts}" || return $?
    sleep 1
    p_container_setup "${_name}" || return $?

    if [ -n "$_version" ] && ! $_AS_NO_INSTALL_START; then
        _log "INFO" "Setting up an Application for version ${_version} on ${_name} ..."
        if ! f_as_setup "${_name}.${_DOMAIN#.}" "${_version}"; then
            _log "ERROR" "Setting up an Application for version ${_version} on ${_name} failed"; sleep 3
            return 1
        fi
    fi
}

function f_large_file_download() {
    local _url="${1}"
    local _tmp_dir="${2:-"."}"
    local _min_disk="6"

    local _file_name="`basename "${_url}"`"

    if [ -s "${_tmp_dir%/}/${_file_name}" ]; then
        _log "INFO" "${_tmp_dir%/}/${_file_name} exists. Not downloading it..."
        return
    fi

    if ! _isEnoughDisk "$_tmp_dir%/" "$_min_disk"; then
        _log "ERROR" "Not enough space to download ${_file_name}"
        return 1
    fi

    _log "INFO" "Executing \"cur \"${_url}\" -o ${_tmp_dir%/}/${_file_name}\""
    curl --retry 100 -C - "${_url}" -o "${_tmp_dir%/}/${_file_name}" || return $?
}

function f_docker_image_import() {
    local _tar_gz_file="${1}"
    local _image_name="${2}"
    local _tmp_dir="${3:-./}"   # To extract tar gz file
    local _min_disk="16"

    if ! which docker &>/dev/null; then
        echo "ERROR: Please install docker - https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/"
        echo "or "
        echo "./start_hdp.sh -f f_docker_setup"
        return 1
    fi

    if [ -n "${_image_name}" ]; then
        local _existing_img="`docker images --format "{{.Repository}}:{{.Tag}}" | grep -m 1 -E "^${_image_name}:"`"
        if [ ! -z "$_existing_img" ]; then
            echo "WARN: Image $_image_name already exist. Exiting."
            echo "To rename image:
        docker tag ${_existing_img} <new_name>:<new_tag>
        docker rmi ${_existing_img}
    To backup image:
        docker save <image id> | gzip > saved_image_name.tgz
        docker export <container id> | gzip > exported_container_name.tgz
    To restore
        gunzip -c saved_exported.tgz | docker load
    "
            return
        fi
    fi

    if ! _isEnoughDisk "/var/lib/docker" "$_min_disk"; then
        echo "ERROR: /var/lib/docker may not have enough space to create ${_image_name}"
        return 1
    fi

    if [ ! -s ${_tar_gz_file} ]; then
        echo "ERROR: file: ${_tar_gz_file} does not exist."
        return 1
    fi

    if file ${_tar_gz_file} | grep -qi 'tar archive'; then
        docker import ${_tar_gz_file} ${_image_name}
    else
        tar -xzv -C ${_tmp_dir} -f ${_tar_gz_file} || return $?
        docker import ${_tmp_dir%/}/cloudera-quickstart-vm-*-docker/*.tar ${_image_name}
    fi
}

function f_ssh_config() {
    local __doc__="Copy keys and setup authorized key to a node (container)"
    local _name="${1}"
    local _key="$2"
    local _pub_key="$3"
    # ssh -q -oBatchMode=yes ${_name} echo && return 0

    if [ -z "${_name}" ]; then
        _log "ERROR" "Need a container name to setup password less ssh"
        return 1
    fi

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

function f_cdh_setup() {
    local _container_name="${1:-"sandbox-cdh"}"

    _log "INFO" "(re)Installing SSH and other commands ..."
    docker exec -it ${_container_name} bash -c 'yum install -y openssh-server openssh-clients; service sshd start'
    docker exec -d ${_container_name} bash -c 'yum install -y yum-plugin-ovl scp curl unzip tar wget openssl python nscd yum-utils sudo which vim net-tools strace lsof tcpdump fuse sshfs nc rsync bzip2 bzip2-libs'
    _log "INFO" "Customising ${_container_name} ..."
    f_container_misc "${_container_name}"
    f_ssh_config "${_container_name}"
    docker exec -it ${_container_name} bash -c 'sed -i_$(date +"%Y%m%d%H%M%S") "s/cloudera-quickstart-init//" /usr/bin/docker-quickstart'
    docker exec -it ${_container_name} bash -c 'sed -i -r "/hbase-|oozie|sqoop2-server|spark-history-server|solr-server|exec bash/d" /usr/bin/docker-quickstart'
    docker exec -it ${_container_name} bash -c 'sed -i "s/ start$/ \$1/g" /usr/bin/docker-quickstart'
}

function p_cdh_sandbox() {
    local _container_name="${1:-"sandbox-cdh"}"
    local _is_quick_starting="${2:-Y}"
    local _download_dir="${3:-"."}"

    local _tar_gz_file="cloudera-quickstart-vm-5.13.0-0-beta-docker.tar.gz"
    local _image_name="cloudera/quickstart"

    if ! docker ps -a --format "{{.Names}}" | grep -qE "^${_container_name}$"; then
        if ! docker images --format "{{.Repository}}" | grep -qE "^${_image_name}$"; then
            _log "INFO" "Downloading ${_tar_gz_file} ..."
            f_large_file_download "https://downloads.cloudera.com/demo_vm/docker/${_tar_gz_file}" "${_download_dir}" || return $?
            _log "INFO" "Importing ${_tar_gz_file} ..."
            f_docker_image_import "${_tar_gz_file}" "${_image_name}"|| return $?
        fi

        _log "INFO" "docker run ${_container_name} ..."
        f_docker_run "${_container_name}.${_DOMAIN}" "${_image_name}" "" "--add-host=quickstart.cloudera:127.0.0.1" || return $?
        f_cdh_setup "${_container_name}" || return $?
    else
        f_docker_start "${_container_name}.${_DOMAIN}" || return $?
    fi
    _log "INFO" "Starting CDH (Quick Start: ${_is_quick_starting}) ..."
    if [[ "${_is_quick_starting}" =~ ^(y|Y) ]]; then
        docker exec -it ${_container_name} bash -c '/usr/bin/docker-quickstart start'
    else
        docker exec -it ${_container_name} bash -c '/home/cloudera/cloudera-manager --express'
        #curl 'http://`hostname -f`:7180/cmf/services/12/maintenanceMode?enter=true' -X POST
    fi
}



## Generic/reusable functions ###################################################
function _sed() {
    local _cmd="sed"; which gsed &>/dev/null && _cmd="gsed"
    if ${_SUDO_SED}; then
        sudo ${_cmd} "$@"
    else
        ${_cmd} "$@"
    fi
}

function _log() {
    # At this moment, outputting to STDERR
    if [ -n "${_LOG_FILE_PATH}" ]; then
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $@" | tee -a ${_LOG_FILE_PATH} 1>&2
    else
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $@" 1>&2
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


## main ###################################################
main() {
    local __doc__="Main function which accepts global variables (any dirty code should be written in here)"

    # Validations
    if ! which docker &>/dev/null; then
        _log "ERROR" "docker is required for this script. (https://docs.docker.com/install/)"
        return 1
    fi
    if ! which lsof &>/dev/null; then
        _log "ERROR" "lsof is required for this script."
        return 1
    fi
    if ! which python &>/dev/null; then
        _log "ERROR" "python is required for this script."
        return 1
    fi
    if ! which dnsmasq &>/dev/null; then
        _log "WARN" "No dnsmasq, which may cause name resolution issue, but keep continuing..."
        sleep 3
    fi
    if [ "`uname`" = "Darwin" ]; then
        if ! which gsed &>/dev/null; then
            _log "ERROR" "gsed is required for this script. (brew uninstall gnu-sed)"
            return 1
        fi

        _WORK_DIR=/private/var/tmp/share
        _DOCKER_PORT_FORWARD=true
    fi

    if [ ! -d "${_WORK_DIR%/}/${_SERVICE}" ]; then
        mkdir -p -m 777 "${_WORK_DIR%/}/${_SERVICE}" || return $?
    fi

    local _ver_num="$(echo "${_VERSION}" | sed 's/[^0-9]//g')"
    if [ -z "$_NAME" ] && [ -n "$_VERSION" ]; then
        _NAME="${_SERVICE}${_ver_num}"
    fi

    # It's hard to access container directly on Mac, so adding port forwarding
    local _ports="";
    if $_DOCKER_PORT_FORWARD; then
        _ports=${_PORTS}
    fi

    if $_CREATE_AND_SETUP; then
        _log "INFO" "Creating docker image and container"
        local _existing_img="`docker images --format "{{.Repository}}:{{.Tag}}" | grep -m 1 -E "^${_IMAGE_NAME}:${_OS_VERSION}"`"
        if [ ! -z "$_existing_img" ]; then
            _log "INFO" "${_IMAGE_NAME} already exists so that skipping image creating part..."
        else
            _log "INFO" "Creating a docker image ${_IMAGE_NAME}..."
            f_docker_base_create || return $?
        fi

        if [ -n "$_NAME" ]; then
            _log "INFO" "Creating ${_NAME} container..."
            local _image="$(docker images --format "{{.Repository}}" | grep -E "^(${_NAME}|${_SERVICE}${_ver_num})$")"
            if $_DOCKER_REUSE_IMAGE && [ -n "${_image}" ]; then
                # Re-using existing images but renaming host
                _log "INFO" "Image ${_image} for ${_NAME}|${_SERVICE}${_ver_num} already exists. Using this ..."; sleep 1
                local _add_host=""
                local _old_hostname=""
                if [ "${_NAME}" != "${_image}" ]; then
                    _add_host="--add-host=${_image}.${_DOMAIN#.}:127.0.0.1"
                    _old_hostname="${_image}.${_DOMAIN#.}"
                fi
                f_docker_run "${_NAME}.${_DOMAIN#.}" "${_image}" "${_ports}" "${_add_host}" || return $?
                sleep 1
                if ! $_DOCKER_SAVE && ! $_AS_NO_INSTALL_START; then
                    f_as_start "${_NAME}.${_DOMAIN#.}" "${_SERVICE}" "Y" "${_old_hostname}"
                fi
            else
                # Creating a new (empty) container and install the application
                f_install_as "${_NAME}" "$_VERSION" "${_IMAGE_NAME}:${_OS_VERSION}" "${_ports}" || return $?
            fi
        fi
    fi

    if $_DOCKER_SAVE; then
        if [ -z "$_NAME" ]; then
            _log "ERROR" "Docker Save (commit) was specified but no name (-n or -v) to save."
            return 1
        fi
        f_docker_commit "$_NAME" || return $?
    fi

    # If creating, container should be started already. If saving, it intentionally stops the container.
    if [ -n "$_NAME" ] && ! $_CREATE_AND_SETUP && ! $_DOCKER_SAVE; then
        if ! docker ps -a --format "{{.Names}}" | grep -qE "^${_NAME}$"; then
            if ! docker images --format "{{.Repository}}" | grep -qE "^${_NAME}$"; then
                _log "WARN" "Container does not exist"; sleep 1
                return 1
            fi
            _log "INFO" "Container does not exist but image ${_NAME} exists. Using this ..."; sleep 1
            f_docker_run "${_NAME}.${_DOMAIN#.}" "${_NAME}" "${_ports}" || return $?
        else
            _log "INFO" "Starting container: $_NAME"
            f_docker_start "${_NAME}.${_DOMAIN#.}" || return $?
        fi
        sleep 1
        $_AS_NO_INSTALL_START || f_as_start "${_NAME}.${_DOMAIN#.}"
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    # parsing command options
    while getopts "chl:Nn:PRSsuv:" opts; do
        case $opts in
            c)
                _CREATE_AND_SETUP=true
                ;;
            h)
                usage | less
                exit 0
                ;;
            l)
                _LICENSE="$OPTARG"
                ;;
            N)
                _AS_NO_INSTALL_START=true
                ;;
            n)
                _NAME="$OPTARG"
                ;;
            P)
                _DOCKER_PORT_FORWARD=true
                ;;
            R)
                _DOCKER_REUSE_IMAGE=true
                ;;
            S)
                _DOCKER_STOP_OTHER=true
                ;;
            s)
                _DOCKER_SAVE=true
                ;;
            u)
                f_update
                exit $?
                ;;
            v)
                _VERSION="$OPTARG"
                ;;
        esac
    done

    if (($# < 1)); then
        usage
        exit 0
    fi

    main
fi