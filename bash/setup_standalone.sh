#!/usr/bin/env bash

function usage() {
    echo "$BASH_SOURCE [-c|-u|-h] -n <container_name> -v <version>

This script does the followings:
    -c [-n <container_name>|-v <version>]
        Create a docker image.
        If -n <container_name> or -v <version> is provided, a docker container will be created.
        Also, Installs necessary service in the container.

    -n <container_name>     <<< no '-c'
        Start a docker container of the given name (hostname), and stat services in the container.

    -p
        Use docker's port forwarding for the application

    -u
        Update this script to the latest

    -h
        To see this message
"
}


### Default values
[ -z "${_VERSION}" ] && _VERSION="7.1.2"        # Default software version, mainly used to find the right installer file
[ -z "${_DOMAIN}" ] && _DOMAIN="localdomain"    # Default container domain

_IMAGE_NAME="hdp/base"                          # TODO: change to more appropriate image name
_CREATE_AND_SETUP=false
_DOCKER_PORT_FORWARD=false
_PORTS="10500 10501 10502 10503 10504 10508 10516 11111 11112 11113"
_SERVICE="atscale"                              # This is used by the app installer script so shouldn't change
_WORK_DIR="/var/tmp/share"                      # If Mac, needs to be /private/var/tmp/share
_CENTOS_VERSION="7.5.1804"


### Functions used to build and setup a container
function f_update() {
    local __doc__="Download the latest code from git and replace"
    local _target="${1:-${BASH_SOURCE}}"
    local _file_name="`basename ${_target}`"
    local _backup_file="/tmp/${_file_name}_$(date +"%Y%m%d%H%M%S")"
    if [ -f "${_target}" ]; then
        cp "${_target}" "${_backup_file}" || return $?
    fi
    curl --retry 3 "https://raw.githubusercontent.com/hajimeo/samples/master/bash/${_file_name}" -o "${_target}"
    if [ $? -ne 0 ]; then
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
}

function f_update_hosts() {
    local __doc__="Update /etc/hosts"
    local _ip="$1"
    local _hostname="$2"
    [ -z "${_ip}" ] && return 11
    [ -z "${_hostname}" ] && return 12
    # TODO: this regex is not perfect
    local _ip_in_hosts="$(_sed -nr "s/^([0-9.]+).*\s${_hostname}.*$/\1/p" /etc/hosts)"

    # If a good entry is already exists.
    [ "${_ip_in_hosts}" = "${_ip}" ] && return 0

    cp -p /etc/hosts /tmp/hosts_$(date +"%Y%m%d%H%M%S")
    # Remove the hostname
    _sed -i -r "s/\s${_hostname}\s?/ /" /etc/hosts
    # Delete unnecessary line
    _sed -i -r "/^${_ip_in_hosts}\s+$/d" /etc/hosts

    # If IP already exists, append the hostname in the end of line
    if grep -qE "^${_ip}\s+" /etc/hosts; then
        _sed -i -r "/^${_ip}\s+/ s/\s*$/ ${_hostname}/" /etc/hosts
        return $?
    fi

    if [ -z "${_ip_in_hosts}" ] || [ "${_ip_in_hosts}" != "${_ip}" ]; then
        echo "${_ip} ${_hostname}" >> /etc/hosts
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
    local _os_ver_num="${3:-${_CENTOS_VERSION}}"
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
    local _ports="${3}" #"10500 10501 10502 10503 10504 10508 10516 11111 11112 11113"
    local _share_dir="${4:-${_WORK_DIR}}"
    # NOTE: At this moment, removed _ip as it requires a custom network (see start_hdp.sh for how)

    local _name="`echo "${_hostname}" | cut -d"." -f1`"
    [ ! -d "${_share_dir%/}" ] && mkdir -p -m 777 "${_share_dir%/}"

    _line="`docker ps -a --format "{{.Names}}" | grep -E "^${_name}$"`"
    if [ -n "$_line" ]; then
        _log "WARN" "Container name ${_name} already exists. Skipping..."; sleep 3
        return 0
    fi

    local _port_opts=""
    for _p in $_ports; do
        local _pid="`lsof -ti:${_p} | head -n1`"
        if [ -n "${_pid}" ]; then
            _log "ERROR" "Docker run could not use the port ${_p} as it's used by pid:${_pid}"
            return 1
        fi
        _port_opts="${_port_opts} -p ${_p}:${_p}"
    done

    #    -v /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket \
    docker run -t -i -d \
        -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
        -v ${_share_dir%/}:/var/tmp/share ${_port_opts} \
        --privileged --hostname=${_hostname} --name=${_name} ${_base} /sbin/init || return $?
}

function f_docker_start() {
    local __doc__="Starting one docker container (TODO: with a few customization)"
    local _hostname="$1"    # short name is also OK

    local _name="`echo "${_hostname}" | cut -d"." -f1`"
    docker start --attach=false ${_name}

    # Somehow docker disable a container communicates outside by adding 0.0.0.0 GW, which will be problem when we test distcp
    #local _docker_ip="172.17.0.1"
    #local _regex="([0-9]+)\.([0-9]+)\.[0-9]+\.[0-9]+"
    #local _docker_net_addr="172.17.0.0"
    #[[ "${_docker_ip}" =~ $_regex ]] && _docker_net_addr="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.0.0"
    #docker exec -it ${_name} bash -c "ip route del ${_docker_net_addr}/24 via 0.0.0.0 &>/dev/null || ip route del ${_docker_net_addr}/16 via 0.0.0.0"
}

function f_container_useradd() {
    local __doc__="Add user in a node (container)"
    local _name="${1:-${_NAME}}"
    local _user="${2:-${_SERVICE}}"
    local _password="${3}"  # Optional. If empty, will be username-password

    [ -z "$_user" ] && return 1
    [ -z "$_password" ] && _password="${_user}-password"

    docker exec -it ${_name} bash -c 'useradd '$_user' -s `which bash` -p $(echo "'$_password'" | openssl passwd -1 -stdin) && usermod -a -G users '$_user || return $?

    if [ "`uname`" = "Linux" ]; then
        which kadmin.local &>/dev/null && kadmin.local -q "add_principal -pw $_password $_user"
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
    local __doc__="Setup a specific Application Service for the container"
    local _hostname="$1"
    local _version="${2:-${_VERSION}}"
    local _user="${3:-${_SERVICE}}"
    local _share_dir="${4:-${_WORK_DIR}}"

    [ ! -d "${_share_dir%/}/${_user}" ] && mkdir -p -m 777 "${_share_dir%/}${_user}"

    # Always get the latest script for now
    f_update "${_share_dir%/}/${_user%/}/install_atscale.sh" || return $?

    if [ ! -s ${_share_dir%/}/${_user%/}/install_atscale.sh ]; then
        _log "ERROR" "Failed to create ${_share_dir%/}/${_user%/}/install_atscale.sh"
        return 1
    fi

    if [ ! -s ${_share_dir%/}/${_user%/}/dev-vm-license-atscale.json ]; then
        _log "ERROR" "Please copy  a license file as ${_share_dir%/}/${_user%/}/dev-vm-license-atscale.json"
        return 1
    fi

    local _name="`echo "${_hostname}" | cut -d"." -f1`"
    docker exec -it ${_name} bash -c "export _STANDALONE=Y;bash /var/tmp/share/atscale/install_atscale.sh ${_version}"
    #ssh -q root@${_hostname} -t "export _STANDALONE=Y;bash ${_share_dir%/}${_user%/}/install_atscale.sh ${_version}"
}

function f_as_start() {
    local __doc__="Start a specific Application Service for the container"
    local _hostname="$1"
    local _user="${2:-${_SERVICE}}"
    local _share_dir="${3:-${_WORK_DIR}}"

    local _name="`echo "${_hostname}" | cut -d"." -f1`"
    docker exec -it ${_name} bash -c "sudo -u ${_user} /usr/local/apache-hive/apache_hive.sh"
    docker exec -it ${_name} bash -c "source /var/tmp/share/atscale/install_atscale.sh;f_atscale_start"
    #ssh -q root@${_hostname} -t "source ${_share_dir%/}${_user%/}/install_atscale.sh;f_atscale_start"
}

function _sed() {
    if which gsed &>/dev/null; then
        gsed "$@"
    else
        sed "$@"
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
function _log() {
    # At this moment, outputting to STDERR
    if [ -n "${_LOG_FILE_PATH}" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" | tee -a ${g_LOG_FILE_PATH} 1>&2
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" 1>&2
    fi
}


main() {
    local __doc__="Main function which accepts global variables (old dirty code should be written in here)"

    # Validations
    if ! which docker &>/dev/null; then
        _log "ERROR" "docker is required for this script. (https://docs.docker.com/install/)"
        return 1
    fi
    if ! which lsof &>/dev/null; then
        _log "ERROR" "lsof is required for this script."
        return 1
    fi
    if [ "`uname`" = "Darwin" ]; then
        if ! which gsed &>/dev/null; then
            _log "ERROR" "gsed is required for this script. (brew uninstall gnu-sed)"
            return 1
        fi

        _WORK_DIR=/private/var/tmp/share
    fi

    if [ ! -d "${_WORK_DIR%/}/${_SERVICE}" ]; then
        mkdir -p -m 777 "${_WORK_DIR%/}/${_SERVICE}" || return $?
    fi

    if [ -z "$_NAME" ] && [ -n "$_VERSION" ]; then
        _NAME="${_SERVICE}$(echo ${_VERSION} | sed 's/[^0-9]//g')"
    fi

    if $_CREATE_AND_SETUP; then
        _log "INFO" "Creating docker image and container"
        local _existing_img="`docker images --format "{{.Repository}}:{{.Tag}}" | grep -m 1 -E "^${_IMAGE_NAME}:${_CENTOS_VERSION}"`"
        if [ ! -z "$_existing_img" ]; then
            _log "INFO" "${_IMAGE_NAME} already exists so that skipping image creating part..."
        else
            _log "INFO" "Creating a docker image ${_IMAGE_NAME}..."
            f_docker_base_create || return $?
        fi

        if [ -n "$_NAME" ]; then
            _log "INFO" "Creating ${_NAME} (container)..."
            # It's hard to access container directly on Mac, so adding port forwarding
            local _ports="";
            if $_DOCKER_PORT_FORWARD || [ "`uname`" = "Darwin" ]; then
                _ports=${_PORTS}
            fi
            f_docker_run "${_NAME}.${_DOMAIN#.}" "${_IMAGE_NAME}:${_CENTOS_VERSION}" "${_ports}" || return $?
            sleep 3
            #local _ip="`docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${_NAME}`"
            local _container_ip="`docker exec -it ${_NAME} hostname -i | tr -cd "[:print:]"`"
            if [ -z "${_container_ip}" ]; then
                _log "ERROR" "No IP assigned to the container ${_NAME}"
                return 1
            fi

            if [ "$USER" = "root" ]; then
                f_update_hosts "${_container_ip}" "${_NAME}.${_DOMAIN#.}" || _log "WARN" "Failed to update /etc/hosts for ${_container_ip} ${_NAME}.${_DOMAIN#.}"
            else
                _log "WARN" "Please update /etc/hosts for ${_container_ip} ${_NAME}.${_DOMAIN#.}"
            fi

            _log "INFO" "Setting up ${_NAME} (container)..."
            f_container_useradd "${_NAME}" "${_SERVICE}" || return $?
            f_container_ssh_config "${_NAME}" || return $?

            if [ -n "$_VERSION" ]; then
                _log "INFO" "Setting up an Application for version ${_VERSION} on ${_NAME} ..."
                f_as_setup "${_NAME}.${_DOMAIN#.}" "${_VERSION}" || return $?
                # as setup starts the app, no need f_as_start
            fi
        fi
        return $?
    fi

    if [ -n "$_NAME" ]; then
        _log "INFO" "Starting $_NAME"
        f_docker_start "${_NAME}.${_DOMAIN#.}" || return $?
        sleep 3
        f_as_start || return $?
        return $?
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    # parsing command options
    while getopts "cn:v:uh" opts; do
        case $opts in
            h)
                usage
                exit 0
                ;;
            u)
                f_update
                exit $?
                ;;
            c)
                _CREATE_AND_SETUP=true
                ;;
            n)
                _NAME="$OPTARG"
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