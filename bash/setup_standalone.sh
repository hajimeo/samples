#!/usr/bin/env bash
#
# Download / setup:
# curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_standalone.sh -o /usr/local/bin/setup_standalone.sh
# chown root:docker /usr/local/bin/setup_standalone*
# chmod 750 /usr/local/bin/setup_standalone*
#
# export _SERVICE="xxxxxxxxx"
#
# TODO: shouldn't use OS dependant command, such as apt-get, yum, brew etc.
#
# To recreate multiple images:
# _PREFIX=xxxxx
# #docker images | grep "^${_PREFIX}" | awk '{print $1}' | sed -nr "s/${_PREFIX}([67])([0-9])([0-9])/\1.\2.\3/p" | sort -n
# ls -1 /var/tmp/share/${_PREFIX}/${_PREFIX}-*.latest-el6.x86_64.{tar.gz,rpm} | sed -n -r "s/.+${_PREFIX}-([0-9]+\.[0-9]+\.[0-9]+).+/\1/p" | sort -n
# for _v in `!!`; do _n=${_PREFIX}$(echo $_v | sed 's/[^0-9]//g'); docker rm -f $_n; docker rmi $_n; setup_standalone.sh -c -v $_v -s || break; done
#

function usage() {
    echo "$BASH_SOURCE
This script is for building a small docker container for testing an application in dev environment.

CREATE CONTAINER:
    -c [-v <version>] [-n <container name>] [-o <install options>]
        Strict mode to create a container. If the named container exists, this script fails.
        <version> in -v is such as x.x.x.
        <container name> in -n is a container name (= hostname).
        If no name specified, generates some random name.
    Ex:
        setup_standalone.sh -c -n node-nxiq1740 -v 1.74.0 -o \"-t nxiq\"

    NOTE: Below location is used to download app installer
        export _DOWNLOAD_URL=http://xxx.xxx.xxx.xxx/zzz/

START/CREATE CONTAINER:
    -n <container name> [-v <version>]     <<< no '-c'
        NOTE: If *exactly* same name image exists or -v/-N options are used, this will create a container from that image.

SAVE CONTAINER AS IMAGE:
    -s -n <container_name>
        Save this container as image, so that creating a container will be faster next time.
        NOTE: saving a container may take a few minutes.

OTHERS (which normally you don't need to use):
    -u
        Update this script to the latest version.

    -i Image_name
        Experimental.
        To specify a image name to create a container

    -l /path/to/software_license_file
        To specify a path of the software licence file.
        If not specified (default), the installer script (install_${_SERVICE}.sh) should decide.

    -M 8081
        Monitoring port. Script watis until this port will be available or timeouts.

    -N
        Not installing anything, just creating an empty container.

    -P
        Experimental.
        Use with -c (or when same name container doesn't exist), so that docker run command includes port forwards.

    -S
        To stop any other port conflicting containers.
        When -P is used or the host is Mac, this option mgiht be required.

    -X
        Stop service and container

    -R
        Restart service

    -h
        To see this message

Another way to create a container:
    . $BASH_SOURCE
    f_as_install <name> <version> '' '' '' <install opts>
"
    docker stats --no-stream
}


### Default values
[ -z "${_SERVICE}" ] && (echo "WARN: _SERVICE env variable is missing!"; sleep 5) # This is used to select the app installer script
[ -z "${_NAME_PREFIX}" ] && _NAME_PREFIX="node"         # If no name specified (-n), this one + type + version will be the name
[ -z "${_WORK_DIR}" ] && _WORK_DIR="/var/tmp/share"     # If Mac, this will be $HOME/share. Also Check "File and Sharing".
[ -z "${_SHARE_DIR}" ] && _SHARE_DIR="/var/tmp/share"   # *container*'s share dir (normally same as _WORK_DIR except Mac)
#_DOMAIN_SUFFIX="$(echo `hostname -s` | sed 's/[^a-zA-Z0-9_]//g').localdomain"
[ -z "${_DOMAIN}" ] && _DOMAIN="standalone.localdomain" # Default container domain suffix
[ -z "${_OS_VERSION}" ] && _OS_VERSION="7.6.1810"       # Container OS version (normally CentOS version)
[ -z "${_BASE_IMAGE}" ] && _BASE_IMAGE="node/base"      # Docker image name TODO: change to more appropriate image name
#[ -z "${_VERSION}" ] && _VERSION=""                     # Default software version, mainly used to find the right installer file
_PORTS="${_PORTS-"8070 8071 8081 8444 8443 5005"}"       # Used by -P (docker port forwarding). for _p in ${_PORTS}; do lsof -i:${_p}; done
# Below is for storing files which I do not want to store in github. NOTE: Mac does not have "hostname -I"
#_DOWNLOAD_URL="${_DOWNLOAD_URL-"http://$(hostname -I | awk '{print $1}')/${_SERVICE}/"}"
#_CUSTOM_NETWORK="hdp"

_CREATE_CONTAINER=false
_CREATE_OR_START=false
_AS_STOP=false
_AS_RESTART=false
_DOCKER_PORT_FORWARD=false
_DOCKER_STOP_OTHER=false
_DOCKER_SAVE=false
_AS_NO_INSTALL_START=false
_SUDO_SED=false
_URL_REGEX='(https?|ftp|file|svn)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'


### Load config file
if [ -s /etc/setup_standalone.conf ]; then
    . /etc/setup_standalone.conf
fi
if [ -s $HOME/.setup_standalone.conf ]; then
    . $HOME/.setup_standalone.conf
fi


### Functions used to build and setup a container
function f_update() {
    local __doc__="Download the latest code/package from the given URL (or github) and replace"
    local _target="${1:-${BASH_SOURCE}}"
    local _remote_repo="${2:-"https://raw.githubusercontent.com/hajimeo/samples/master/bash/"}"

    local _file_name="`basename ${_target}`"
    local _backup_file="/tmp/${_file_name}_$(date +"%Y%m%d%H%M%S")"
    if [ -f "${_target}" ]; then
        local _remote_length=`curl -m 4 -s -k -L --head "${_remote_repo%/}/${_file_name}" | grep -i '^Content-Length:' | awk '{print $2}' | tr -d '\r'`
        local _local_length=`wc -c <${_target}`
        if [ -z "${_remote_length}" ] || [ "${_remote_length}" -lt $(( ${_local_length} / 2 )) ] || [ ${_remote_length} -eq ${_local_length} ]; then
            #_log "INFO" "Not updating ${_target}"
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
    _log "INFO" "${_target} has been updated. Backup: ${_backup_file}"
}

function f_update_hosts_file_by_fqdn() {
    local __doc__="Update hosts file with given hostname (FQDN) and IP"
    local _hostname="${1}"
    local _container_name="${2}"
    local _inject_hostname="${3}"

    [ -z "${_container_name}" ] && _container_name="`echo "${_hostname}" | cut -d"." -f1`"

    local _hosts_file="/etc/hosts"
    [ -f /etc/banner_add_hosts ] && _hosts_file="/etc/banner_add_hosts"

    if ! docker ps --format "{{.Names}}" | grep -qE "^${_container_name}$"; then
        _log "WARN" "${_container_name} is NOT running. Please check and update ${_hosts_file} manually."
        return 1
    fi

    local _container_ip="`docker exec -it ${_container_name} hostname -i | tr -cd "[:print:]"`"   # tr to remove unnecessary control characters
    if [ -z "${_container_ip}" ]; then
        _log "WARN" "${_container_name} is running but not returning IP. Please check and update ${_hosts_file} manually."
        return 1
    fi

    # If no root user, uses "sudo" in sed
    if [ "$USER" != "root" ] && [ ! -w "${_hosts_file}" ]; then
        _SUDO_SED=true
        _log "INFO" "Updating ${_hosts_file}. ***It may ask your sudo password***"
    fi

    # If port forwarding is used and Mac, better use localhost
    $_DOCKER_PORT_FORWARD && [ "`uname`" = "Darwin" ] && _container_ip="127.0.0.1"
    if ! f_update_hosts_file "${_hostname}" "${_container_ip}" "${_hosts_file}" "${_inject_hostname}"; then
        _log "WARN" "Please update ${_hosts_file} to add '${_container_ip} ${_hostname}'"
        return 1
    fi

    if [ -s /etc/init.d/dnsmasq ]; then
        # NOTE: /etc/sudoers is visible by root only so that grep to check won't work, and get "Authentication is required to reload 'dnsmasq.service'"
        if ! sudo /etc/init.d/dnsmasq reload; then
            _log "TODO" "%docker ALL=(ALL) NOPASSWD: /etc/init.d/dnsmasq reload"
            /etc/init.d/dnsmasq reload
        fi
        sleep 1
    fi
}

function f_update_hosts_file() {
    local __doc__="Update hosts file with given hostname (FQDN) and IP"
    local _fqdn="$1"
    local _ip="$2"
    local _file="${3:-"/etc/hosts"}"
    local _inject_hostname="${4}"

    if [ -z "${_fqdn}" ]; then
        _log "ERROR" "hostname (FQDN) is required"; return 11
    fi
    local _name="`echo "${_fqdn}" | cut -d"." -f1`"
    # Checking if this combination is already in the hosts file. TODO: this regex is not perfect
    local _old_ip="$(_sed -nr "s/^([0-9.]+).*\s${_fqdn}.*$/\1/p" ${_file})"

    if [ -z "${_ip}" ]; then
        if [[ ! "${_inject_hostname}" =~ ^(y|Y) ]] || [ -z "${_old_ip}" ]; then
            _log "ERROR" "IP is required"; return 12
        else
            _log "INFO" "Using ${_old_ip} for IP"
            _ip="${_old_ip}"
        fi
    else
        # Already configured, so do nothing.
        [ "${_old_ip}" = "${_ip}" ] && return 0
    fi

    # Take backup before modifying
    local _backup_file="/tmp/hosts_$(date +"%Y%m%d%H%M%S")"
    cp -p ${_file} ${_backup_file} || return $?

    local _tmp_file="${_file}"
    if [ "`uname`" = "Darwin" ]; then
        _log "WARN" "Updating ${_tmp_file} (backup: ${_backup_file})"; sleep 3
    else
        # TODO: ideally should lock
        cp -p -f ${_file} /tmp/f_update_hosts_file_$$.tmp || return $?
        _tmp_file="/tmp/f_update_hosts_file_$$.tmp"
    fi

    if [[ ! "${_inject_hostname}" =~ ^(y|Y) ]]; then
        # Remove all lines contain hostname or IP
        _sed -i -r "/\s${_fqdn}\s+${_name}\s?/d" ${_tmp_file}
        _sed -i -r "/\s${_fqdn}\s?/d" ${_tmp_file}
        _sed -i -r "/^${_ip}\s?/d" ${_tmp_file}
    fi

    # This shouldn't match but just in case
    [ -n "${_old_ip}" ] && _sed -i -r "/^${_old_ip}\s?/d" ${_tmp_file}

    if [[ ! "${_inject_hostname}" =~ ^(y|Y) ]]; then
        # Append in the end of file
        # it seems sed a (append) does not work if file is empty
        #_sed -i -e "\$a${_ip} ${_fqdn} ${_name}" ${_tmp_file}
        # Mac is hard to modify hosts file
        if [ "`uname`" = "Darwin" ]; then
            echo "${_ip} ${_fqdn} ${_name}" | sudo tee -a ${_tmp_file}
        else
            echo "${_ip} ${_fqdn} ${_name}" >> ${_tmp_file}
        fi
    else
        # as injecting is Y, adding this host before other hosts
        _sed -i "/^${_ip}\s/ s/${_ip}\s/${_ip} ${_fqdn} /" ${_tmp_file}
    fi

    if [ ! "`uname`" = "Darwin" ]; then
        _log "INFO" "Updating ${_file} for ${_fqdn} ${_ip} ..."
        # cp / mv fails if no permission on the directory
        cat ${_tmp_file} > ${_file} || return $?
        rm -f ${_tmp_file}
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

    curl -s -f --retry 3 "${_url}" -o ${_new_filepath} || return $?

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

    local _base="${_BASE_IMAGE}:$_os_ver_num"

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
    mv ${_docker_file} ${_build_dir%/}/Dockerfile || return $?
    cd ${_build_dir} || return $?
    docker build --rm -t ${_base} . || return $?
    cd -
}

function f_docker_run() {
    local __doc__="Execute docker run with my preferred options"
    local _fqdn="$1"
    local _base="${2:-"${_BASE_IMAGE}:${_OS_VERSION}"}"
    local _ports="${3}"      #"10500 10501 10502 10503 10504 10508 10516 11111 11112 11113"
    local _extra_opts="${4}" # eg: "--add-host=imagename.standalone:127.0.0.1"
    local _stop_other=${5:-${_DOCKER_STOP_OTHER}}
    local _share_dir_from="${6:-${_WORK_DIR}}"
    local _share_dir_to="${7:-${_SHARE_DIR}}"
    # NOTE: At this moment, removed _ip as it requires a custom network (see start_hdp.sh for how)

    local _name="`echo "${_fqdn}" | cut -d"." -f1`"
    [ ! -d "${_share_dir_from%/}" ] && mkdir -p -m 777 "${_share_dir_from%/}"

    _line="`docker ps -a --format "{{.Names}}" | grep -E "^${_name}$"`"
    if [ -n "$_line" ]; then
        _log "WARN" "Container name ${_name} already exists. Skipping..."; sleep 1
        return 0
    fi

    local _port_opts=""
    for _p in $_ports; do
        local _pid="`lsof -ti:${_p} | head -n1`"
        if [ -n "${_pid}" ]; then
            if ${_stop_other}; then
                local _cname="`_docker_find_by_port ${_p}`"
                if [ -n "${_cname}" ]; then
                    _log "WARN" "Stopping ${_cname} container as port ${_p} is used..."
                    docker stop -t 7 ${_cname}
                fi
            else
                _log "WARN" "Docker run could not use the port ${_p} as it's used by pid:${_pid}, so skipping..."
            fi
        else
            _port_opts="${_port_opts} -p ${_p}:${_p}"
        fi
    done
    # Only if port forwarding is in use or Mac, append SSH port forwarding, just in case
    if [ -n "${_ports}" ] || [ "`uname`" = "Darwin" ]; then
        local _num=`echo ${_name} | sed 's/[^0-9]//g' | cut -c1-3`
        local _ssh_pf_num=$(( 22000 + ${_num:-1} ))
        if ! lsof -ti:${_ssh_pf_num} -s TCP:LISTEN; then
            _log "INFO" "Adding port forward:${_ssh_pf_num}->22 (eg: ssh -p${_ssh_pf_num} -D28081 localhost)..."
            _port_opts="${_port_opts} -p ${_ssh_pf_num}:22"
        fi
    fi

    local _network=""   # Currently not accepting an IP, so no point of using custom network
    #if docker network ls | grep -qw "$_CUSTOM_NETWORK"; then
    #    _network="--network=${_CUSTOM_NETWORK}"
    #fi

    local _dns=""       # in case of IP change on the host, not specifying DNS.
    # If dnsmasq is installed, assuming it's setup correctly
    #if [ -s /etc/init.d/dnsmasq ]; then
    #    _dns="--dns=`hostname -I | cut -d " " -f1`"
    #fi

    # Hostname can be overwritten by _extra_opts
    local _hostname_opt="--hostname=${_fqdn}"
    if [[ "${_extra_opts}" =~ hostname=([^ ]+) ]]; then
        _hostname_opt=""
        #_fqdn="${BASH_REMATCH[1]}"
    fi

    #    -v /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket \
    _log "INFO" "docker run ${_name} from ${_base} ..."
    docker run -t -i -d \
        -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
        -v ${_share_dir_from%/}:${_share_dir_to%/} ${_port_opts} ${_network} ${_dns} \
        --privileged=true --name=${_name} ${_hostname_opt} ${_extra_opts} ${_base} /sbin/init || return $?

    f_update_hosts_file_by_fqdn "${_fqdn}"
    sleep 1
    p_container_setup "${_name}" || return $?
}

function p_container_setup() {
    local __doc__="various config setup (eg: ssh client)"
    local _name="${1:-${_NAME}}"

    f_container_ssh_config "${_name}"   # it's OK to fail || return $?
    f_container_misc "${_name}"         # it's OK to fail || return $?
    #_log "INFO" "Setting up ${_name} container completed."
    return 0
}

function f_docker_start() {
    local __doc__="Starting one docker container (TODO: with a few customization)"
    local _hostname="$1"    # short name is also OK
    local _stop_other=${2:-${_DOCKER_STOP_OTHER}}

    local _container_name="`echo "${_hostname}" | cut -d"." -f1`"

    if ${_stop_other}; then
        # Probably --filter can do better...
        for _p in `docker inspect ${_container_name} | python -c "import sys,json;a=json.loads(sys.stdin.read());print ' '.join([l.replace('/tcp', '') for l in a[0]['Config']['ExposedPorts'].keys()])"`; do
            local _cname="`_docker_find_by_port ${_p}`"
            if [ -n "${_cname}" ]; then
                _log "INFO" "Stopping ${_cname} container..."
                docker stop -t 7 ${_container_name}
            fi
        done
    fi

    if docker ps --format "{{.Names}}" | grep -E "^${_container_name}$"; then
        #_log "INFO" "Container ${_container_name} is already running."; sleep 1
        return 0
    fi
    docker start --attach=false ${_container_name}

    # Somehow docker disable a container communicates to outside by adding 0.0.0.0 GW
    #local _docker_ip="`docker inspect bridge | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['IPAM']['Config'][0]['Gateway'])"`"
    #local _regex="([0-9]+)\.([0-9]+)\.[0-9]+\.[0-9]+"
    #local _docker_net_addr="172.17.0.0"
    #[[ "${_docker_ip}" =~ $_regex ]] && _docker_net_addr="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.0.0"
    #docker exec -it ${_name} bash -c "ip route del ${_docker_net_addr}/24 via 0.0.0.0 &>/dev/null"

    f_update_hosts_file_by_fqdn "${_hostname}"
}

function f_as_log_cleanup() {
    local __doc__="Find log|logs|tmp directories and delete non binary files older than X days"
    local _hostname="$1"    # short name is also OK
    local _days="${2:-2}"  # NOT in use (was before)
    local _service="${3:-${_SERVICE}}"  # NOT in use (was before)

    local _name="`echo "${_hostname}" | cut -d"." -f1`"
    # Using xargs instead of -delete so that can see what's deleted. Also -mount for not checking non-local file system, and -size +0 for not deleting placeholder files.
    docker exec -it ${_name} bash -c 'for _d in $(find /{var,opt} -mount -type d \( -name log -o -name logs -o -name tmp \) -print); do
        if [ "tmp" == "$(basename "${_d}")" ]; then
            find "${_d%/}" -mount -type f -size +0 -mtime +'${_days}' -print0
        else
            find "${_d%/}" -mount -type f -size +0 -mtime +'${_days}' \( -name '*log*' -o -name '*.out' -o -name '*.tmp' \) -exec grep -Iq . {} \; -print0
        fi 2>/dev/null | xargs -0 -P3 -n1 -t -I {} rm -f {}
    done'
    docker exec -it ${_name} bash -c 'find /tmp -mount -type f -mtime +'${_days}' -delete'
}

function f_docker_commit() {
    local __doc__="Cleaning up unncecessary files and then save a container as an image"
    local _container_name="$1"    # FQDN is also OK
    local _service="${2:-${_SERVICE}}"
    local _remove_log="${3-Y}"

    local _name="`echo "${_container_name}" | cut -d"." -f1`"

    if docker images --format "{{.Repository}}" | grep -qE "^${_name}$"; then
        _log "WARN" "Image ${_name} already exists. Please do 'docker rmi ${_name}' first."; sleep 1
        return
    fi
    if ! docker ps --format "{{.Names}}" | grep -qE "^${_name}$"; then
        _log "INFO" "Container ${_name} is NOT running, so that not cleaning up..."; sleep 1
    fi

    if [[ "${_remove_log}" =~ ^(y|Y) ]]; then
        f_as_log_cleanup "${_name}" "Y"
    fi

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
    local _key="${2:-"$HOME/.ssh/id_rsa"}"
    local _pub_key="${3:-"$HOME/.ssh/id_rsa.pub"}"
    local _global_auth_key_file="${4:-"${_SHARE_DIR%/}/.ssh/authorized_keys"}"

    # ssh -q -oBatchMode=yes ${_name} echo && return 0
    if [ -z "${_name}" ]; then
        _log "ERROR" "Need a container name to setup password less ssh"
        return 1
    fi

    if [ ! -r "${_key}" ]; then
        _log "ERROR" "key: ${_key} is not readable"
        return 1
    fi
    if [ ! -r "${_pub_key}" ]; then
        _log "ERROR" "publikc key: ${_pub_key} is not readable. Use 'ssh-keygen -y -f ${_key} > ~/.ssh/id_rsa.pub'"
        return 1
    fi

    docker exec -it ${_name} bash -c "[ -f /root/.ssh/authorized_keys ] || ( install -D -m 600 /dev/null /root/.ssh/authorized_keys && chmod 700 /root/.ssh )"
    docker exec -it ${_name} bash -c "[ -f /root/.ssh/id_rsa.orig ] && exit; [ -f /root/.ssh/id_rsa ] && mv /root/.ssh/id_rsa /root/.ssh/id_rsa.orig; echo \"`cat ${_key}`\" > /root/.ssh/id_rsa; chmod 600 /root/.ssh/id_rsa;echo \"`cat ${_pub_key}`\" > /root/.ssh/id_rsa.pub; chmod 644 /root/.ssh/id_rsa.pub"
    docker exec -it ${_name} bash -c "grep -q \"^`cat ${_pub_key}`\" /root/.ssh/authorized_keys || echo \"`cat ${_pub_key}`\" >> /root/.ssh/authorized_keys"
    [ -s "${_global_auth_key_file}" ] && f_update_auth_key "${_name}" "${_global_auth_key_file}"
    #docker exec -it ${_name} bash -c "grep -q '^AuthorizedKeysFile' /etc/ssh/sshd_config && sed -i '/^AuthorizedKeysFile/ s@\$@ ${_global_auth_key_file}@' /etc/ssh/sshd_config && service sshd restart"
    docker exec -it ${_name} bash -c "[ -f /root/.ssh/config ] || echo -e \"Host *\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n  LogLevel ERROR\" > /root/.ssh/config"
}

function f_update_auth_key() {
    local __doc__="Update authorized_keys file of one container from *this* host"
    local _name="${1:-${_NAME}}"
    local _global_auth_key_file="${2:-"${_SHARE_DIR%/}/.ssh/authorized_keys"}"

    if [ ! -s ${_global_auth_key_file} ]; then
        _log "ERROR" "Please check ${_global_auth_key_file}"
        return 1
    fi

    chmod 700 "$(dirname "${_global_auth_key_file}")"
    chmod 600 "${_global_auth_key_file}"
    docker exec -it ${_name} bash -c "echo \"`cat ${_global_auth_key_file}`\" >> /root/.ssh/authorized_keys && cat /root/.ssh/authorized_keys | sort | uniq > /root/.ssh/.authorized_keys.tmp && mv -f /root/.ssh/.authorized_keys.tmp /root/.ssh/authorized_keys"
}

function f_container_add_NIC() {
    local __doc__="Add one network interface on one container"
    local _name="${1}"
    local _network="${2:-bridge}"

    local _before_gw="$(docker inspect ${_name} | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['NetworkSettings']['Gateway'])")"
    docker network connect ${_network} ${_name} || return $?
    local _after_gw="$(docker inspect ${_name} | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['NetworkSettings']['Gateway'])")"
    if [ -n "${_before_gw}" ] && [ "${_before_gw}" != "${_after_gw}" ]; then
        _log "WARN" "Gateway address has been changed (before: "${_before_gw}", after: ${_after_gw})
     May want to execute below (please double check NIC name):
route add default gw ${_before_gw} eth0\
route del default gw ${_after_gw}\
"
    fi
    docker exec -it ${_name} bash -c "netstat -rn"
}

function f_as_setup() {
    local __doc__="Install/Setup a specific Application Service for the container"
    local _hostname="$1"
    local _version="${2:-${_VERSION}}"
    local _options="${3}"
    local _license="${4:-${_LICENSE}}"
    local _service="${5:-${_SERVICE}}"
    local _work_dir="${6:-${_WORK_DIR}}"
    local _share_dir="${7:-${_SHARE_DIR}}"

    [ ! -d "${_work_dir%/}/${_service%/}" ] && mkdir -p -m 777 "${_work_dir%/}${_service%/}"

    # Get the latest install_{service}.sh script but it's OK if fails if the file exists
    [ -n "${_DOWNLOAD_URL}" ] && f_update "${_work_dir%/}/${_service%/}/install_${_service%/}.sh" "${_DOWNLOAD_URL}"

    if [ ! -s ${_work_dir%/}/${_service%/}/install_${_service%/}.sh ]; then
        _log "ERROR" "Failed to create ${_work_dir%/}/${_service%/}/install_${_service%/}.sh"
        return 1
    fi

    local _cmd="bash -x ${_share_dir%/}/${_service%/}/install_${_service%/}.sh -v ${_version} ${_options# }"
    if [ -n "${_license}" ]; then
        if [ ! -f "${_work_dir%/}/${_service%/}/$(basename "${_license}")" ]; then
            cp ${_license} ${_work_dir%/}/${_service%/}/ || return 11
        fi
        _cmd="${_cmd} -l ${_share_dir%/}/${_service%/}/$(basename "${_license}")"
    fi

    local _name="`echo "${_hostname}" | cut -d"." -f1`"
    _log "INFO" "Executing '${_cmd}' ..."
    docker exec -it ${_name} bash -c "${_cmd} 2>/tmp/install.err"
    if [ $? -ne 0 ]; then
        _log "ERROR" "Installation/Setup failed. Please check container's /tmp/install.err for STDERR"
        return 1
    fi
    docker exec -it ${_name} bash -c "grep -E '^\[.+\] ERROR' /tmp/install.err"
    return 0
}

function f_as_start() {
    local __doc__="Start a specific Application Service for the container. Expecting install_SERVICE.sh and start_SERVICE"
    local _hostname="$1"
    local _service="${2:-${_SERVICE}}"
    local _is_restarting="${3}"

    # NOTE: To support different version, f_as_setup should create a symlink
    local _name="`echo "${_hostname}" | cut -d"." -f1`"

    if [[ "${_is_restarting}" =~ ^(y|Y) ]]; then
        f_as_stop || return $?
    fi
    docker exec -it ${_name} bash -c "source ${_SHARE_DIR}/${_service}/install_${_service}.sh;start_${_service}"
}

function f_as_stop() {
    local __doc__="Stop a specific Application Service for the container. Expecting install_SERVICE.sh and stop_SERVICE"
    local _hostname="$1"
    local _service="${2:-${_SERVICE}}"

    # NOTE: To support different version, f_as_setup should create a symlink
    local _name="`echo "${_hostname}" | cut -d"." -f1`"
    docker exec -it ${_name} bash -c "source ${_SHARE_DIR}/${_service}/install_${_service}.sh;stop_${_service}"
}

function f_as_hostname_change() {
    local __doc__="Scheduling hostname change of the application side"
    local _hostname="$1"
    local _old_hostname="$2"
    local _service="${3:-${_SERVICE}}"

    local _name="`echo "${_hostname}" | cut -d"." -f1`"
    _log "INFO" "Scheduling hostname change to ${_hostname} (from ${_old_hostname})"
    echo "docker exec -it ${_name} bash -c \". ${_SHARE_DIR%/}/${_service%/}/install_${_service%/}.sh;f_hostname_change '${_hostname}' '${_old_hostname}'\"" | at now +1 minute
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
    docker exec -it ${_name} bash -c 'sudo -u '${_service}' /usr/local/'${_service}'/bin/${_service%/}_service_control stop all;for _i in {1..4}; do lsof -ti:10520 -s TCP:LISTEN || break;sleep 3;done'
    docker exec -it ${_name} bash -c 'cp -p /home/'${_service}'/custom.yaml /usr/local/'${_service}'/custom.bak.yaml &>/dev/null'
    _log "INFO" "Creating '${_share_dir%/}/${_service%/}/${_file_name}' from /usr/local/${_service%/}"; sleep 1
    docker exec -it ${_name} bash -c 'tar -chzf '${_share_dir%/}'/'${_service%/}'/'${_file_name}' -C /usr/local/ '${_service%/}''

    if [ ! -s "${_work_dir%/}/${_service%/}/${_file_name}" ] || [ 2097152 -gt "`wc -c <${_work_dir%/}/${_service%/}/${_file_name}`" ]; then
        _log "ERROR" "Backup to ${_work_dir%/}/${_service%/}/${_file_name} failed"; sleep 3
        return 1
    fi
    _log "INFO" "Backup to ${_work_dir%/}/${_service%/}/${_file_name} completed"
}

function f_as_install() {
    local __doc__="Install the application from creating a container (_AS_NO_INSTALL_START for no setup)"
    local _name="${1:-$_NAME}"
    local _version="${2-$_VERSION}" # If no version, do not install(setup) the application
    local _base="${3:-"${_BASE_IMAGE}:${_OS_VERSION}"}"
    local _ports="${4}"      #"10500 10501 10502 10503 10504 10508 10516 11111 11112 11113"
    local _docker_opts="${5}" # eg: "--add-host=imagename.standalone:127.0.0.1"
    local _install_opts="${6}"

    # Creating a new (empty) container and install the application
    f_docker_run "${_name}.${_DOMAIN#.}" "${_base}" "${_ports}" "${_docker_opts}" || return $?
    f_container_useradd "${_name}" "${_SERVICE}" || return $?

    if [ -n "$_version" ] && ! $_AS_NO_INSTALL_START; then
        if ! f_as_setup "${_name}.${_DOMAIN#.}" "${_version}" "${_install_opts}"; then
            _log "ERROR" "Setting up an Application for version ${_version} on ${_name} failed"; sleep 3
            return 1
        fi
        _log "INFO" "Setting up an Application for version ${_version} on ${_name} completed."
    fi
}

function f_large_file_download() {
    local __doc__="Function for downloading a large file (checks disk space and retries)"
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
    curl -f --retry 100 -C - "${_url}" -o "${_tmp_dir%/}/${_file_name}" || return $?
}

function f_docker_image_import() {
    local __doc__="Download and Import an image"
    local _tar_uri="${1}"       # URL to download or a path of .tar file
    local _image_name="${2}"
    local _use_load="${3}"
    local _min_disk="${4:-16}"
    local _tmp_dir="${5:-${_WORK_DIR}}"   # To extract tar gz file

    if ! which docker &>/dev/null; then
        _log "ERROR" "Please install docker - https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/"
        return 1
    fi

    # If an image name is given, check if already exists.
    if [ -n "${_image_name}" ]; then
        local _existing_img="`docker images --format "{{.Repository}}:{{.Tag}}" | grep -m 1 -P "^${_image_name}\b"`"
        if [ ! -z "$_existing_img" ]; then
            _log "WARN" "Image $_image_name already exist. Exiting.
    To rename image:
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

    local _tar_file_path="${_tmp_dir%/}/$(basename "${_tar_uri}")"
    [ -s "${_tar_uri}" ] && _tar_file_path="${_tar_uri}"

    if [[ "${_tar_uri}" =~ $_URL_REGEX ]]; then
        _log "INFO" "Downloading ${_tar_uri} to ${_tmp_dir}..."; sleep 1
        f_large_file_download "${_tar_uri}" "${_tmp_dir}" || return $?
    elif [ ! -s "${_tar_file_path}" ]; then
        _log "ERROR" "No URL to download and import."
        return 1
    fi

    if [ ! -s ${_tar_file_path} ]; then
        _log "ERROR" "file: ${_tar_file_path} does not exist."
        return 1
    fi

    if ! _isEnoughDisk "/var/lib/docker" "$_min_disk"; then
        _log "WARN" "/var/lib/docker may not have enough space to create ${_image_name}"
        return 1
    fi

    # This part is for workaround-ing CDH's tar.gz file which contains another tar file.
    if ! file ${_tar_file_path} | grep -qi 'gzip compressed data, was'; then
        local _filename="$(basename ${_tar_file_path})"
        local _extract_dir="${_tmp_dir%/}/${_filename%.*}"
        if [ ! -d "${_extract_dir}" ]; then
            mkdir -p "${_extract_dir}" || return $?
        fi
        local _tmp_tar_file="`find ${_extract_dir%/} -name '*.tar' -size +1024k`"
        if [ -s "${_tmp_tar_file}" ]; then
            _log "INFO" "Found ${_tmp_tar_file} in ${_extract_dir%/}. Re-using..."
        else
            tar -xzv -C ${_extract_dir} -f ${_tar_file_path} || return $?
            _tmp_tar_file="`find ${_extract_dir%/} -name '*.tar' -amin -10 -size +1024k`"
            if [ ! -s "${_tmp_tar_file}" ]; then
                _log "ERROR" "Couldn't find any tar file in ${_extract_dir%/}."
                return 1
            fi
        fi
        _tar_file_path="${_tmp_tar_file}"
    fi

    _log "INFO" "Importing ${_tar_file_path} as ${_image_name} (empty means using load)..."
    if [ -z "${_image_name}" ]; then
        docker load -i ${_tar_file_path}
    else
        docker import ${_tar_file_path} ${_image_name}
    fi
}

function _cdh_setup() {
    local _container_name="${1:-"node-cdh"}"

    _log "INFO" "(re)Installing SSH and other commands ..."
    docker exec -it ${_container_name} bash -c 'yum install -y openssh-server openssh-clients; service sshd start'
    docker exec -dt ${_container_name} bash -c 'yum install -y yum-plugin-ovl scp curl unzip tar wget openssl python nscd yum-utils sudo which vim net-tools strace lsof tcpdump fuse sshfs nc rsync bzip2 bzip2-libs krb5-workstation'
    _log "INFO" "Customising ${_container_name} ..."
    f_container_misc "${_container_name}"
    f_container_ssh_config "${_container_name}"
    docker exec -it ${_container_name} bash -c '[ ! -f /usr/bin/docker-quickstart.orig ] && cp -p /usr/bin/docker-quickstart /usr/bin/docker-quickstart.orig'
    docker exec -it ${_container_name} bash -c 'sed -i_$(date +"%Y%m%d%H%M%S") "s/cloudera-quickstart-init//" /usr/bin/docker-quickstart'
    docker exec -it ${_container_name} bash -c 'sed -i -r "/hbase-|oozie|sqoop2-server|solr-server|exec bash/d" /usr/bin/docker-quickstart'
    docker exec -it ${_container_name} bash -c 'sed -i "s/ start$/ \$1/g" /usr/bin/docker-quickstart'
    docker exec -it ${_container_name} bash -c 'grep -q "^net.ipv4.ip_local_reserved_ports" /etc/sysctl.conf || (echo -e "\nnet.ipv4.ip_local_reserved_ports = 50000-50099" >> /etc/sysctl.conf && sysctl -e -p /etc/sysctl.conf)'
}

function p_cdh_sandbox() {
    local __doc__="Setup CDH Sandbox (NOTE: may need to stop another container which uses previously used IP)"
    local _container_name="${1:-"node-cdh"}"
    local _is_using_cm="${2}"
    local _image_name="${3:-"node-cdh"}"
    local _tar_uri="${4:-"https://downloads.cloudera.com/demo_vm/docker/cloudera-quickstart-vm-5.13.0-0-beta-docker.tar.gz"}"
    # As of this typing, quickstart:latest is using 5.7

    local _base_image="cloudera/quickstart:latest"
    local _first_time=false

    if ! docker ps -a --format "{{.Names}}" | grep -qE "^${_container_name}$"; then
        if docker images --format "{{.Repository}}" | grep -qE "^${_image_name}$"; then
            _log "INFO" "Image ${_image_name} exists. Creating a container from this image..."
            f_docker_run "${_container_name}.${_DOMAIN}" "${_image_name}" "4433 7180 7182 7184 7185 7190 7191 8084 8480 8485 9994 9996 9083 10000 10002 13562 21000 21050 22000 23000 23020 24000 25000 25010 25020 26000 50010 50020 50070 50075 50090" "--hostname=quickstart.cloudera" || return $?
        else
            if [ -n "${_tar_uri}" ]; then
                f_docker_image_import "${_tar_uri}" "${_base_image}" || return $?
            else
                docker pull ${_base_image} || return $?
            fi
            # NOTE: Cloudera quickstart does not work well if hostname is different ...
            f_docker_run "${_container_name}.${_DOMAIN}" "${_base_image}" "4433 7180 7182 7184 7185 7190 7191 8084 8480 8485 9994 9996 9083 10000 10002 13562 21000 21050 22000 23000 23020 24000 25000 25010 25020 26000 50010 50020 50070 50075 50090" "--hostname=quickstart.cloudera" || return $?
            _cdh_setup "${_container_name}" || return $?
            f_container_useradd "${_container_name}" "${_SERVICE}" # || return $?
            docker exec -it ${_container_name} bash -c 'echo "sudo -u '${_SERVICE}' impala-shell -i localhost -q \"CREATE DATABASE IF NOT EXISTS '${_SERVICE}'\";sudo -u hdfs hdfs dfs -mkdir /user/'${_SERVICE}';sudo -u hdfs hdfs dfs -chown '${_SERVICE}': /user/'${_SERVICE}'" | at now +7 minutes'
            _first_time=true
        fi
    else
        f_docker_start "${_container_name}.${_DOMAIN}" || return $?
    fi

    # It might be using hostname "quickstart.cloudera", so just in case, updating DNS before starting
    f_update_hosts_file_by_fqdn "quickstart.cloudera" "${_container_name}" "Y"
    _log "INFO" "Starting CDH (Using Cloudera Manager: ${_is_using_cm}) ..."
    if [[ "${_is_using_cm}" =~ ^(y|Y) ]]; then
        if ${_first_time}; then
            #curl 'http://`hostname -f`:7180/cmf/services/12/maintenanceMode?enter=true' -X POST
            docker exec -it ${_container_name} bash -c '/home/cloudera/cloudera-manager --express' || return $?
        else
            docker exec -it ${_container_name} bash -c 'service cloudera-scm-server-db start; service cloudera-scm-server start;service cloudera-scm-agent start;' || return $?
        fi
    else
        docker exec -it ${_container_name} bash -c '/usr/bin/docker-quickstart start' || return $?
        _log "INFO" "To enable CM, run '/home/cloudera/cloudera-manager --express' as *root*."
    fi
    # Schedule refresh commands in case DataNode and NodeManager's IP has been changed
    #docker exec -it ${_container_name} bash -c 'echo "sudo -u hdfs hadoop dfsadmin -refreshNodes; sudo -u yarn yarn rmadmin -refreshNodes" | at now +5 minutes'
    _log "INFO" "To reuse this container: p_cdh_sandbox ${_container_name} ${_is_using_cm}"
}

function _hdp_setup() {
    local _container_name="${1:-"node-hdp"}"

    # startup_script modify /etc/resolv.conf so removing
    docker exec -dt ${_container_name} bash -c 'chkconfig startup_script off ; chkconfig tutorials off; chkconfig shellinaboxd off; chkconfig hue off; chkconfig httpd off'
    docker exec -it ${_container_name} bash -c 'service startup_script stop; service tutorials stop; service shellinaboxd stop; service httpd stop; service hue stop'
    docker exec -dt ${_container_name} bash -c 'grep -q -F "> /etc/resolv.conf" /etc/rc.d/init.d/startup_script && tar -cvzf /root/startup_script.tgz `find /etc/rc.d/ -name '*startup_script' -o -name '*tutorials'` --remove-files'
    docker exec -dt ${_container_name} bash -c 'grep -q "^public_hostname_script" /etc/ambari-agent/conf/ambari-agent.ini && exit 0;( echo -e "#!/bin/bash\necho \`hostname -f\`" > /var/lib/ambari-agent/public_hostname.sh && chmod a+x /var/lib/ambari-agent/public_hostname.sh && sed -i.bak "/run_as_user/i public_hostname_script=/var/lib/ambari-agent/public_hostname.sh\n" /etc/ambari-agent/conf/ambari-agent.ini );ambari-agent stop;ambari-agent reset `hostname -f`;ambari-agent start'
    docker exec -dt ${_container_name} bash -c "(set -x;[ -S /tmp/.s.PGSQL.5432 ] || (service postgresql restart;sleep 5); PGPASSWORD=bigdata psql -h localhost -Uambari -tAc \"UPDATE users SET user_password='538916f8943ec225d97a9a86a2c6ec0818c1cd400e09e03b660fdaaec4af29ddbb6f2b1033b81b00', active=1 WHERE user_name='admin' and user_type='LOCAL';UPDATE hosts set host_name='${_container_name}.${_DOMAIN}', public_host_name='${_container_name}.${_DOMAIN}' where host_id=1;\")"
    docker exec -dt ${_container_name} bash -c '_javahome="`grep java.home /etc/ambari-server/conf/ambari.properties | cut -d "=" -f2`" && grep -q "^securerandom.source=file:/dev/random" ${_javahome%/}/jre/lib/security/java.security && sed -i.bak -e "s/^securerandom.source=file:\/dev\/random/securerandom.source=file:\/dev\/urandom/" ${_javahome%/}/jre/lib/security/java.security'

    #local _dns_ip="`docker inspect bridge | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['IPAM']['Config'][0]['Gateway'])"`"
    local _dns_ip="8.8.8.8"
    docker exec -it ${_container_name} bash -c '_f=/etc/resolv.conf; grep -q "^nameserver '${_dns_ip}'" $_f && exit 0; echo "nameserver '${_dns_ip}'" > /tmp/${_f}.tmp && cat ${_f} >> /tmp/${_f}.tmp && cat /tmp/${_f}.tmp > ${_f}'
    docker exec -it ${_container_name} bash -c 'yum install -y openssh-server openssh-clients; service sshd start' || return $?
    docker exec -dt ${_container_name} bash -c 'yum install -y yum-plugin-ovl scp curl unzip tar wget openssl python nscd yum-utils sudo which vim net-tools strace lsof tcpdump fuse sshfs nc rsync bzip2 bzip2-libs'
}

function p_hdp_sandbox() {
    local __doc__="Setup HDP Sandbox (up to 2.6.3 or need .tar file in local)"
    local _container_name="${1:-"node-hdp"}"
    local _tar_uri="${2:-"https://downloads-hortonworks.akamaized.net/sandbox-hdp-2.6.3/HDP_2.6.3_docker_10_11_2017.tar"}"
    local _image_name="sandbox-hdp" # Note: when changing _tar_uri, _image_name may need to change too.
    # Ref: https://hortonworks.com/tutorial/sandbox-deployment-and-install-guide/section/3/
    # https://downloads-hortonworks.akamaized.net/sandbox-hdp-2.6.5/HDP_2.6.5_deploy-scripts_180624d542a25.zip

    if ! docker ps -a --format "{{.Names}}" | grep -qE "^${_container_name}$"; then
        f_docker_image_import "${_tar_uri}" "${_image_name}" "Y" || return $?
        f_docker_run "${_container_name}.${_DOMAIN}" "${_image_name}" "" "--add-host=${_image_name}.hortonworks.com:127.0.0.1" || return $?
        _hdp_setup "${_container_name}" || return $?
    else
        f_docker_start "${_container_name}.${_DOMAIN}" || return $?
    fi

    _log "INFO" "Starting Ambari ..."
    docker exec -dt ${_container_name} bash -c '/usr/sbin/ambari-agent restart'
    docker exec -it ${_container_name} bash -c '/usr/sbin/ambari-server start --skip-database-check'
}

function _tableau_server_setup() {
    local _container_name="${1:-"node-ts"}"
    local _tableau_version="${2:-"2018.2.5"}"
    local _not_initializing="${3}"

    local _tsm_user="tsm"
    local _work_dir="${_WORK_DIR}"
    [ ! -d "${_work_dir%/}" ] && mkdir -p -m 777 "${_work_dir%/}"

    local _file_path="${_work_dir%/}/tableau-server-${_tableau_version//\./-}.x86_64.rpm"
    if [ ! -s "${_file_path}" ]; then
        curl -f -o "${_file_path}" -C - --retry 3 "https://downloads.tableau.com/esdalt/${_tableau_version}/tableau-server-${_tableau_version//\./-}.x86_64.rpm" || return $?
    fi
    local _driver_file_path="${_work_dir%/}/tableau-postgresql-odbc-09.06.0500-1.x86_64.rpm"
    if [ ! -s "${_driver_file_path}" ]; then
        curl -f -o "${_driver_file_path}" -C - --retry 3 "https://downloads.tableau.com/drivers/linux/yum/tableau-driver/tableau-postgresql-odbc-09.06.0500-1.x86_64.rpm" || return $?
    fi

    # TODO: not good to add NOPASSWD:ALL
    docker exec -it ${_container_name} bash -c "grep -wq '${_tsm_user}' /etc/passwd || (adduser ${_tsm_user} && echo ${_tsm_user}:${_tsm_user} | chpasswd)"
    docker exec -it ${_container_name} bash -c "[ ! -f /etc/sudoers.d/${_tsm_user} ] && echo '${_tsm_user} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/${_tsm_user}"
    docker exec -it ${_container_name} bash -c "yum install -y ${_file_path} ${_driver_file_path}" || return $?

    if [[ "${_not_initializing}" =~ ^(y|Y) ]]; then
        _log "WARN" "NOT executing 'initialize-tsm'. Please run this manually."; sleep 3
    else
        _log "INFO" "Executing 'initialize-tsm'..."; sleep 1
        docker exec -it ${_container_name} bash -c "cd /opt/tableau/tableau_server/packages/scripts.20* && ./initialize-tsm --accepteula -a ${_tsm_user} -p ${_tsm_user}"
    fi
}

function p_tableau_server() {
    local __doc__="Install Tableau Server"
    local _container_name="${1:-"node-ts"}"
    local _tableau_version="${2:-"2018.2.5"}"
    local _save_container="$3"
    local _gw_port="${4:-8000}"

    local _tsm_port="8850"

    if ! docker ps -a --format "{{.Names}}" | grep -qE "^${_container_name}$"; then
        if lsof -ti:${_gw_port}; then
            _log "ERROR" "Port number ${_gw_port} is in use, so that can't do port forward"
            return 1
        fi
        f_docker_run "${_container_name}.${_DOMAIN}" "" "${_gw_port} ${_tsm_port}" || return $?
        # When saving, NOT initializing
        _tableau_server_setup "${_container_name}" "${_tableau_version}" "${_save_container}" || return $?
        _log "WARN" "Please use port ${_gw_port} for the Gateway Port."; sleep 3
        _log "NOTE" "After initializing from 'https://`hostname -I | awk '{print $1}'`:${_tsm_port}/', login ${_container_name} and run:
    sudo -u tsm -i tabcmd initialuser --server 'localhost:${_gw_port}' -u <admin user> -p <admin pwd>"; sleep 3
    else
        # Not sure if this works because of below TODO.
        f_docker_start "${_container_name}.${_DOMAIN}" || return $?
    fi

    # TODO: Saved container fails to initialize due to "Failed to get D-Bus connection: No such file or directory"
    #if [[ "${_save_container}" =~ ^(y|Y) ]]; then
    #    f_docker_commit "${_container_name}.${_DOMAIN}" "" "N" || return $?
    #    _log "INFO" "How to start: setup_standalone.sh -N -n ${_container_name}"
    #fi
}

function _useradd() {
    local __doc__="Add user on Host"
    local _user="$1"
    local _pwd="$2"
    local _copy_ssh_config="$3"

    if grep -q "$_user" /etc/passwd; then
        _log "INFO" "$_user already exists. Skipping useradd command..."
    else
        # should specify home directory just in case?
        useradd -d "/home/$_user/" -s `which bash` -p $(echo "$_pwd" | openssl passwd -1 -stdin) "$_user"
        mkdir "/home/$_user/" && chown "$_user":"$_user" "/home/$_user/"
    fi

    if [[ "$_copy_ssh_config" =~ ^(y|Y) ]]; then
        if [ ! -f ${HOME%/}/.ssh/id_rsa ]; then
            _log "INFO" "${HOME%/}/.ssh/id_rsa does not exist. Not copying ssh configs ..."
            return
        fi

        if [ ! -d "/home/$_user/" ]; then
            _log "INFO" "No /home/$_user/ . Not copying ssh configs ..."
            return
        fi

        mkdir "/home/$_user/.ssh" && chown "$_user":"$_user" "/home/$_user/.ssh"
        cp ${HOME%/}/.ssh/id_rsa* "/home/$_user/.ssh/"
        cp ${HOME%/}/.ssh/config "/home/$_user/.ssh/"
        cp ${HOME%/}/.ssh/authorized_keys "/home/$_user/.ssh/"
        chown "$_user":"$_user" /home/$_user/.ssh/*
        chmod 600 "/home/$_user/.ssh/id_rsa"
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
    if [ "`uname`" = "Darwin" ]; then
        if ! which gsed &>/dev/null; then
            _log "ERROR" "gsed is required for this script. (brew uninstall gnu-sed)"
            return 1
        fi

        _WORK_DIR=$HOME/share
        # NOTE: This was in case of empty string, but now the default is "false", so nomally it wouldn't be true.
        [ "x${_DOCKER_PORT_FORWARD}" == "x" ] && _DOCKER_PORT_FORWARD=true
    fi

    if [ -z "${_SERVICE}" ]; then
        _log "ERROR" "The env variable '_SERVICE' is not defined."
        return 1
    fi
    if [ ! -d "${_WORK_DIR%/}/${_SERVICE}" ]; then
        mkdir -p -m 777 "${_WORK_DIR%/}/${_SERVICE}" || return $?
    fi

    if ${_AS_STOP}; then
        if [ -z "${_NAME}" ]; then
            _log "ERROR" "To stop|restart, need -n <name>"
            return 1
        fi
        _log "INFO" "Stopping service (best effort)..."
        f_as_stop "${_NAME}" "${_SERVICE}" || return $?
        # Default 10 seconds might be a bit dangerous.
        _log "INFO" "Stopping container (best effort)..."
        docker stop -t 120 ${_NAME}
        return $?
    fi

    if ${_AS_RESTART}; then
        if [ -z "${_NAME}" ]; then
            _log "ERROR" "To restart, need -n <name>"
            return 1
        fi
        f_as_start "${_NAME}" "${_SERVICE}" "Y"
        return $?
    fi

    # It's hard to access container directly on Mac, so adding port forwarding. Ref: https://docs.docker.com/docker-for-mac/networking/
    local _ports="";
    if $_DOCKER_PORT_FORWARD; then
        _ports=${_PORTS}
    fi

    # _CREATE_CONTAINER means setting up the service/application by executing f_as_setup
    if $_CREATE_CONTAINER || $_CREATE_OR_START; then
        # Check if the base OS image exists
        local _existing_img="`docker images --format "{{.Repository}}:{{.Tag}}" | grep -m 1 -E "^${_BASE_IMAGE}:${_OS_VERSION}"`"
        if [ -z "${_existing_img}" ]; then
            _log "INFO" "Creating a docker image ${_BASE_IMAGE}..."
            f_docker_base_create || return $?
        fi

        # If no name, generating automatically.
        if [ -z "${_NAME}" ]; then
            if [ -n "${_IMAGE_NAME}" ]; then
                _NAME="${_IMAGE_NAME}"
            else
                if [ -n "${_NAME_PREFIX}" ]; then
                    _NAME="${_NAME_PREFIX}"
                else
                    _NAME="${_SERVICE}"
                fi
                if [ -n "${_APP_TYPE}" ]; then
                    _NAME="${_NAME}-${_APP_TYPE}"
                fi
                if [ -n "${_VERSION}" ]; then
                    _NAME="${_NAME}$(echo "${_VERSION}" | sed 's/[^0-9]//g')"
                else
                    _NAME="${_NAME}000"
                fi
            fi

            if docker ps -a --format "{{.Names}}" | grep -qE "^${_NAME}$"; then
                _NAME="${_NAME}-$(date +"%S")"
            fi
        fi

        # If no "-c" and -v is given, will check if image for same name already exists.
        if ! $_CREATE_CONTAINER && [ -n "${_SERVICE}" ] && [ -z "${_IMAGE_NAME}" ] && [ -n ${_VERSION} ]; then
            local _tmp_image_name="${_SERVICE}$(echo "${_VERSION}" | sed 's/[^0-9]//g')"
            if docker images --format "{{.Repository}}" | grep -qE "^${_tmp_image_name}$"; then
                _IMAGE_NAME="${_tmp_image_name}"
            fi
        fi

        if ! $_CREATE_CONTAINER && docker ps -a --format "{{.Names}}" | grep -qE "^${_NAME}$"; then
            _log "INFO" "Container:${_NAME} already exists and no -c, so no f_as_install ..."
        elif ! $_CREATE_CONTAINER && docker images --format "{{.Repository}}" | grep -qE "^${_NAME}$"; then
            # A bit confusing, but because of the Special Condition 1, will create a container without installing app.
            _log "INFO" "An image which same name as ${_NAME} already exists and no -c, so no f_as_install ..."
        elif $_CREATE_CONTAINER; then
            local _base="${_IMAGE_NAME:-"${_BASE_IMAGE}:${_OS_VERSION}"}"
            _log "INFO" "Creating ${_NAME} container from ${_base} (v:${_VERSION})..."
            # Creating a new (empty) container and install the application
            f_as_install "${_NAME}" "${_VERSION}" "${_base}" "${_ports}" "" "${_INSTALL_OPTS}" || return $?
        fi
    fi

    if $_DOCKER_SAVE; then
        if [ -z "$_NAME" ]; then
            _log "ERROR" "Docker Save (commit) was specified but no name (-n or -v) to save."
            return 1
        fi
        f_docker_commit "$_NAME" || return $?
    fi

    # Finally, starts a container if _NAME is not empty
    # If -c is used, container should be already started, so don't need to start.
    # If -s is used, it intentionally stops the container, so don't need to start.
    if [ -n "$_NAME" ] && ! $_CREATE_CONTAINER && ! $_DOCKER_SAVE; then
        if docker ps --format "{{.Names}}" | grep -qE "^${_NAME}$"; then
            _log "INFO" "Container ${_NAME} is already running ..."; sleep 1
        else
            local _hostname_rename=false

            if ! docker ps -a --format "{{.Names}}" | grep -qE "^${_NAME}$"; then
                # Special condition 1: If _NAME = some image name, create this container even no _CREATE_CONTAINER
                if docker images --format "{{.Repository}}" | grep -qE "^(${_NAME})$"; then
                    _log "INFO" "Container does not exist but same name image:${_NAME} exists. Using this ..."; sleep 1
                    f_docker_run "${_NAME}.${_DOMAIN#.}" "${_NAME}" "${_ports}" || return $?
                fi
                # Special condition 2: If _IMAGE_NAME = some image name, create this container even no _CREATE_CONTAINER
                if docker images --format "{{.Repository}}" | grep -qE "^(${_IMAGE_NAME})$"; then
                    _log "INFO" "Container does not exist but image:${_IMAGE_NAME} exists. Using this ..."; sleep 1
                    f_docker_run "${_NAME}.${_DOMAIN#.}" "${_IMAGE_NAME}" "${_ports}" "--add-host=${_IMAGE_NAME}.${_DOMAIN#.}:127.0.0.1" || return $?
                    _hostname_rename=true
                fi
            else
                _log "INFO" "Starting container: $_NAME"
                f_docker_start "${_NAME}.${_DOMAIN#.}" || return $?
            fi

            if ! $_AS_NO_INSTALL_START; then
                _log "INFO" "Starting application/service on ${_NAME} ..."; sleep 1
                f_as_start "${_NAME}.${_DOMAIN#.}"
                if $_hostname_rename; then
                    sleep 10
                    f_as_hostname_change "${_NAME}.${_DOMAIN#.}" #"${_IMAGE_NAME}.${_DOMAIN#.}"
                fi
            fi
        fi

        if [[ "${_MONITOR_PORT}" =~ [0-9]+ ]]; then
            # nc might not be installed, so using curl
            _log "INFO" "Waiting ${_NAME} ${_MONITOR_PORT} is up ..."
            for _i in {1..20}; do curl -m 2 -k -s -o /dev/null "${_NAME}:${_MONITOR_PORT}" && break;sleep 3;done
        fi
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    # parsing command options
    while getopts "chi:l:M:Nn:o:PRSst:uv:X" opts; do
        case $opts in
            c)
                _CREATE_CONTAINER=true
                ;;
            h)
                usage | less
                exit 0
                ;;
            i)
                _IMAGE_NAME="$OPTARG"
                _CREATE_OR_START=true
                ;;
            l)
                _LICENSE="$OPTARG"
                ;;
            M)
                _MONITOR_PORT="$OPTARG"
                ;;
            N)
                _AS_NO_INSTALL_START=true
                _CREATE_OR_START=true
                ;;
            n)
                _NAME="$OPTARG"
                ;;
            o)
                _INSTALL_OPTS="${_INSTALL_OPTS} $OPTARG"
                ;;
            P)
                _DOCKER_PORT_FORWARD=true
                ;;
            R)
                _AS_RESTART=true
                ;;
            S)
                _DOCKER_STOP_OTHER=true
                ;;
            s)
                _DOCKER_SAVE=true
                ;;
            t)
                _APP_TYPE="$OPTARG"
                _INSTALL_OPTS="${_INSTALL_OPTS} -t ${_APP_TYPE}"
                ;;
            u)
                f_update
                exit $?
                ;;
            v)
                _VERSION="$OPTARG"
                _CREATE_OR_START=true
                ;;
            X)
                _AS_STOP=true
                ;;
        esac
    done

    if (($# < 1)); then
        usage
        exit 0
    fi

    main
fi