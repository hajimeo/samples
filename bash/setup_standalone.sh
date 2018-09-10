#!/usr/bin/env bash

function usage() {
    echo "$BASH_SOURCE [-c|-u|-h] -n=container_name -v=version

This script does the followings:
    -c
        If docker image does not exist, create a docker image.

    -c -n=name
        Above plus create a named container.
        Install necessary services if not installed yet in the container (the version can be specified).

    -n=name     <<< no '-c'
        Start a docker container if the given name (hostname) exists, and stat services in the container.

    -u
        Update this script to the latest

    -h
        To see this message
"
}


### Default values
[ -z "${_VERSION}" ] && _VERSION="${7.1.2}"          # Default software version, mainly used to find the right installer file
[ -z "${_NAME}" ] && _NAME="${standalone}"              # Default container name
[ -z "${_DOMAIN}" ] && _DOMAIN="localdomain"         # Default container domain

_IMAGE_NAME="hdp/base"                               # TODO: change to more appropriate image name
_CREATE_AND_SETUP=false
_START_SERVICE=false
_USER="atscale"
_CENTOS_VERSION="7.5.1804"
_WORK_DIR="/var/tmp/share"


### Functions used to build and setup a container
function f_update() {
    local __doc__="Download the latest code from git and replace"
    local _target="${1:-${BASH_SOURCE}}"
    local _file_name="`basename ${_target}`"
    local _backup_file="/tmp/${_file_name}_$(date +"%Y%m%d%H%M%S")"
    cp "${_target}" "${_backup_file}" || return $?
    curl --retry 3 "https://raw.githubusercontent.com/hajimeo/samples/master/bash/${_file_name}" -o "${_target}"
    if $? -ne 0; then
        mv -f "${_backup_file}" "${_target}"
        return 1
    fi
    local _length=`wc -c <./${_target}`
    local _old_length=`wc -c <./${_backup_file}`
    if [ ${_length} -lt $(( ${_old_length} / 2 )) ]; then
        mv -f "${_backup_file}" "${_target}"
        return 1
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
        local _pkey="`sed ':a;N;$!ba;s/\n/\\\\\\\n/g' $HOME/.ssh/id_rsa`"
        sed -i "s@_REPLACE_WITH_YOUR_PRIVATE_KEY_@${_pkey}@1" ${_new_filepath}
    else
        _warn "No private key to replace _REPLACE_WITH_YOUR_PRIVATE_KEY_"
    fi

    [ -z "$_os_and_ver" ] || sed -i "s/FROM centos.*/FROM ${_os_and_ver}/" ${_new_filepath}
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

    if ! docker images | grep -P "^${_os_name}\s+${_os_ver_num}"; then
        _log "INFO" "pulling OS image ${_os_name}:${_os_ver_num} ..."
        docker pull ${_os_name}:${_os_ver_num} || return $?
    fi
    # "." is not good if there are so many files/folders but https://github.com/moby/moby/issues/14339 is unclear
    local _build_dir="$(mktemp -d)" || return $?
    mv ${_docker_file} ${_build_dir%/}/DockerFile || return $?
    cd ${_build_dir} || return $?
    docker build -t ${_base} . || return $?
    cd -
}

function f_docker_run() {
    local __doc__="Execute docker run with my preferred options"
    local _hostname="$1"
    local _base="$2"
    local _share_dir="${3:-${_WORK_DIR}}"
    # NOTE: At this moment, removed _ip as it requires a custom network (see start_hdp.sh for how)

    local _name="`echo "${_hostname}" | cut -d"." -f1`"
    [ ! -d "${_share_dir%/}" ] && mkdir -p -m 777 "${_share_dir%/}"

    _line="`docker ps -a --format "{{.Names}}" | grep -E "^${_name}$"`"
    if [ -n "$_line" ]; then
        _warn "Container name:${_name} already exists. Skipping..."
        return 2
    fi

    #    -v /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket \
    docker run -t -i -d \
        -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
        -v ${_share_dir%/}:${_share_dir%/} \
        --privileged --hostname=${_hostname} --name=${_name} ${_base} /sbin/init
}

function f_docker_start() {
    local __doc__="Starting one docker container (TODO: with a few customization)"
    local _hostname="$1"    # short name is also OK

    local _name="`echo "${_hostname}" | cut -d"." -f1`"
    docker start --attach=false ${_name}
}

function f_container_useradd() {
    local __doc__="Add user in a node (container)"
    local _user="${1}"
    local _password="${2}"  # Optional. If empty, will be username-password
    local _container="${3-${_NAME}}"

    [ -z "$_user" ] && return 1
    [ -z "$_password" ] && _password="${_user}-password"

    docker exec -it ${_container} bash -c 'useradd '$_user' -s `which bash` -p $(echo "'$_password'" | openssl passwd -1 -stdin) && usermod -a -G users '$_user || return $?
    if which kadmin.local; then
        kadmin.local -q "add_principal -pw $_password $_user"
    fi
}

function f_container_ssh_config() {
    local __doc__="Copy keys and setup authorized key to a node (container)"
    local _name="${1-$_NAME}"
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

function f_setup_app() {
    local __doc__="Setup a specific app for the container"
    local _hostname="$1"
    local _version="${2:-${_VERSION}}"
    local _user="${3:-${_USER}}"
    local _share_dir="${4:-${_WORK_DIR}}"

    [ ! -d "${_share_dir%/}/${_user}" ] && mkdir -p -m 777 "${_share_dir%/}${_user}"

    # Always get the latest script for now
    curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/install_atscale.sh -o ${_share_dir%/}${_user%/}/install_atscale.sh
    # should I use docker exec?
    #local _name="`echo "${_hostname}" | cut -d"." -f1`"
    ssh -q root@${_hostname} -t "export _STANDALONE=Y;bash ${_share_dir%/}${_user%/}/install_atscale.sh ${_version}"
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
    local __doc__="Main function which accepts global variables"

    if ! which docker &>/dev/null; then
        _log "ERROR" "docker is required for this script. https://docs.docker.com/install/"
        return 1
    fi

    [ ! -d "${_WORK_DIR%/}" ] && mkdir -p -m 777 "${_WORK_DIR%/}"

    if $_CREATE_AND_SETUP; then
        _log "INFO" "Creating docker image and container"

        local _existing_img="`docker images --format "{{.Repository}}:{{.Tag}}" | grep -m 1 -E "^${_IMAGE_NAME}:"`"
        if [ ! -z "$_existing_img" ]; then
            _log "INFO" "${_IMAGE_NAME} already exists so that skipping image creating part..."
        else
            _log "INFO" "Creating a docker image ${_IMAGE_NAME}..."
            f_docker_base_create || return $?
        fi

        if [ -n "$_NAME" ]; then
            _log "INFO" "Creating ${_NAME} (container)..."
            f_docker_run "${_NAME}.${_DOMAIN#.}" "${_IMAGE_NAME}:${_CENTOS_VERSION}" || return $?

            _log "INFO" "Setting up ${_NAME} (container)..."
            f_container_useradd "${_USER}" || return $?
            f_container_ssh_config "${_USER}" || return $?

            _log "INFO" "Setting up ${_NAME} (container)..."
            f_setup_app "${_NAME}.${_DOMAIN#.}"
        fi
        return #?
    fi

    if [ -n "$_NAME" ]; then
        _log "INFO" "Starting $_NAME"
        f_docker_start "${_NAME}.${_DOMAIN#.}"
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

    main
fi