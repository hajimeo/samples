#!/usr/bin/env bash
# curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_standalone.sh

function usage() {
    echo "$BASH_SOURCE -c -v ${_VERSION} [-n <container_name>] [-s]

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
    -P
        Used with -c to use docker's port forwarding for the application

    -S
        Used with -c, -n, -v to stop any other conflicting containers.
        When -P is used or the host is Mac, this option would be needed.

    -u
        Update this script to the latest

    -h
        To see this message

"
    docker stats --no-stream
}


### Default values
[ -z "${_VERSION}" ] && _VERSION="7.1.2"                # Default software version, mainly used to find the right installer file
[ -z "${_DOMAIN}" ] && _DOMAIN="standalone.localdomain" # Default container domain

_IMAGE_NAME="hdp/base"                                  # TODO: change to more appropriate image name
_CREATE_AND_SETUP=false
_DOCKER_PORT_FORWARD=false
_DOCKER_STOP_OTHER=false
_DOCKER_SAVE=false
_SUDO_SED=false
_PORTS="10500 10501 10502 10503 10504 10508 10516 11111 11112 11113"
_SERVICE="atscale"                                      # This is used by the app installer script so shouldn't change
_WORK_DIR="/var/tmp/share"                              # If Mac, needs to be /private/var/tmp/share
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
    local __doc__="Update /etc/hosts for the container"
    local _hostname="$1"
    local _container_ip="$2"

    [ -z "${_hostname}" ] && return 12
    local _name="`echo "${_hostname}" | cut -d"." -f1`"

    if [ -z "${_container_ip}" ]; then
        #local _ip="`docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${_NAME}`"
        _container_ip="`docker exec -it ${_NAME} hostname -i | tr -cd "[:print:]"`"
        if [ -z "${_container_ip}" ]; then
            _log "ERROR" "No IP assigned to the container ${_NAME}"
            return 1
        fi
    fi

    # TODO: this regex is not perfect
    local _ip_in_hosts="$(_sed -nr "s/^([0-9.]+).*\s${_hostname}.*$/\1/p" /etc/hosts)"
    # If a good entry is already exists.
    [ "${_ip_in_hosts}" = "${_container_ip}" ] && return 0

    # Take backup before modifying
    cp /etc/hosts /tmp/hosts_$(date +"%Y%m%d%H%M%S")

    # Remove the hostname and unnecessary line
    _sed -i -r "s/\s${_hostname} ${_name}\s?/ /" /etc/hosts
    _sed -i -r "s/\s${_hostname}\s?/ /" /etc/hosts
    _sed -i -r "/^${_ip_in_hosts}\s+$/d" /etc/hosts

    # If IP already exists, append the hostname in the end of line
    if grep -qE "^${_container_ip}\s+" /etc/hosts; then
        _sed -i -r "/^${_container_ip}\s+/ s/\s*$/ ${_hostname} ${_name}/" /etc/hosts
        return $?
    fi

    if [ -z "${_ip_in_hosts}" ] || [ "${_ip_in_hosts}" != "${_container_ip}" ]; then
        _sed -i -e "\$a${_container_ip} ${_hostname} ${_name}" /etc/hosts
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
    local _stop_other=${4:-${_DOCKER_STOP_OTHER}}
    local _share_dir="${5:-${_WORK_DIR}}"
    # NOTE: At this moment, removed _ip as it requires a custom network (see start_hdp.sh for how)

    local _name="`echo "${_hostname}" | cut -d"." -f1`"
    [ ! -d "${_share_dir%/}" ] && mkdir -p -m 777 "${_share_dir%/}"

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
                    _log "INFO" "Stopping ${_cname} container..."
                    docker stop ${_cname}
                fi
            else
                _log "ERROR" "Docker run could not use the port ${_p} as it's used by pid:${_pid}"
                return 1
            fi
        fi
        _port_opts="${_port_opts} -p ${_p}:${_p}"
    done
    [ -n "${_port_opts}" ] && ! lsof -ti:22222 && _port_opts="${_port_opts} -p 22222:22"

    #    -v /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket \
    docker run -t -i -d \
        -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
        -v ${_share_dir%/}:/var/tmp/share ${_port_opts} \
        --privileged --hostname=${_hostname} --name=${_name} ${_base} /sbin/init || return $?
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
                docker stop ${_cname}
            fi
        done
    fi

    docker start --attach=false ${_name}

    # Somehow docker disable a container communicates outside by adding 0.0.0.0 GW, which will be problem when we test distcp
    #local _docker_ip="172.17.0.1"
    #local _regex="([0-9]+)\.([0-9]+)\.[0-9]+\.[0-9]+"
    #local _docker_net_addr="172.17.0.0"
    #[[ "${_docker_ip}" =~ $_regex ]] && _docker_net_addr="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.0.0"
    #docker exec -it ${_name} bash -c "ip route del ${_docker_net_addr}/24 via 0.0.0.0 &>/dev/null || ip route del ${_docker_net_addr}/16 via 0.0.0.0"
}

function f_docker_commit() {
    local __doc__="Cleaning up unncecessary files and then save a container as an image"
    local _hostname="$1"    # short name is also OK

    local _name="`echo "${_hostname}" | cut -d"." -f1`"

    if docker images --format "{{.Repository}}" | grep -qE "^${_name}$"; then
        _log "WARN" "Image ${_name} already exists. Please do 'docker rmi ${_name}' first."; sleep 1
        return
    fi
    if ! docker ps --format "{{.Names}}" | grep -qE "^${_name}$"; then
        _log "INFO" "Container ${_name} is NOT running, so that not cleaning up..."; sleep 1
    fi

    docker exec -it ${_name} bash -c 'find /usr/local/atscale/{log,share/postgresql-*/data/pg_log} -type f -and \( -name "*.log*" -o -name "postgresql-2*.log" -o -name "*.stdout" \) -and -print0| xargs -0 -P3 -n1 -I {} rm -f {}'
    docker exec -it ${_name} bash -c 'rm -rf /home/atscale/atscale-*-el6.x86_64;rm -rf /home/atscale/log/*'

    docker stop ${_name} || return $?
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
    f_update "${_share_dir%/}/${_user%/}/install_atscale.sh"

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
    docker exec -it ${_name} bash -c "sudo -u ${_user} /usr/local/atscale/bin/atscale_start;sudo -u ${_user} /usr/local/apache-hive/apache_hive.sh"
}

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
    if ! which python &>/dev/null; then
        _log "ERROR" "python is required for this script."
        return 1
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
            if $_DOCKER_PORT_FORWARD; then
                _ports=${_PORTS}
            fi

            if docker images --format "{{.Repository}}" | grep -qE "^${_NAME}$"; then
                _log "INFO" "Image ${_NAME} already exists. Using this instead of ${_IMAGE_NAME}:${_CENTOS_VERSION}..."; sleep 1
                f_docker_run "${_NAME}.${_DOMAIN#.}" "${_NAME}" "${_ports}" || return $?
                sleep 1
                f_as_start "${_NAME}.${_DOMAIN#.}"
            else
                f_docker_run "${_NAME}.${_DOMAIN#.}" "${_IMAGE_NAME}:${_CENTOS_VERSION}" "${_ports}" || return $?
                sleep 1
                _log "INFO" "Setting up ${_NAME} (container)..."
                f_container_useradd "${_NAME}" "${_SERVICE}" || return $?
                f_container_ssh_config "${_NAME}"   # it's OK to fail || return $?
                f_container_misc "${_NAME}"         # it's OK to fail || return $?

                if [ -n "$_VERSION" ]; then
                    _log "INFO" "Setting up an Application for version ${_VERSION} on ${_NAME} ..."
                    f_as_setup "${_NAME}.${_DOMAIN#.}" "${_VERSION}" || return $?
                    # as setup starts the app, no need f_as_start
                fi
            fi
        fi
    fi

    if $_DOCKER_SAVE; then
        if [ -z "$_NAME" ]; then
            _log "ERROR" "Docker save (commit) was specified but no name to save."
            return 1
        fi
        f_docker_commit "$_NAME"
    fi

    if [ -n "$_NAME" ]; then
        # If creating, container should be started already. If saveing, it intentionally stops the container.
        if ! $_CREATE_AND_SETUP && ! $_DOCKER_SAVE; then
            _log "INFO" "Starting container: $_NAME"
            f_docker_start "${_NAME}.${_DOMAIN#.}" || return $?
            sleep 1
            f_as_start "${_NAME}.${_DOMAIN#.}"
        fi

        # if name is given and running, updates /etc/hosts
        if docker ps --format "{{.Names}}" | grep -qE "^${_NAME}$"; then
            local _container_ip="`docker exec -it ${_NAME} hostname -i | tr -cd "[:print:]"`"
            if [ -z "${_container_ip}" ]; then
                _log "WARN" "${_NAME} is running but not returning IP. Please check and update /etc/hosts manually."
            else
                # If no root user, uses "sudo" in sed
                if [ "$USER" != "root" ]; then
                    _SUDO_SED=true
                    _log "INFO" "Updating /etc/hosts. It may ask your sudo password."
                fi

                # If port forwarding is used, better use localhost
                $_DOCKER_PORT_FORWARD && _container_ip="127.0.0.1"
                f_update_hosts "${_NAME}.${_DOMAIN#.}" "${_container_ip}" ||  _log "WARN" "Please update /etc/hosts to add '${_container_ip} ${_NAME}.${_DOMAIN#.}'"
            fi
        fi
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    # parsing command options
    while getopts "cn:v:sPSuh" opts; do
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
            s)
                _DOCKER_SAVE=true
                ;;
            n)
                _NAME="$OPTARG"
                ;;
            v)
                _VERSION="$OPTARG"
                ;;
            P)
                _DOCKER_PORT_FORWARD=true
                ;;
            S)
                _DOCKER_STOP_OTHER=true
                ;;
        esac
    done

    if (($# < 1)); then
        usage
        exit 0
    fi

    main
fi