#!/usr/bin/env bash

_DOCKER_CMD=${_DOCKER_CMD:-"docker"}    # To support podman
_DOMAIN="${_DOMAIN:-"standalone.localdomain"}"
_DNS_RELOAD="sudo systemctl reload dnsmasq >/dev/null"
__TMP=${__TMP:-"/tmp"}
#_LOG_FILE_PATH=""


function _docker_add_network() {
    local _network_name="${1}"
    local _subnet_16="${2:-"172.100"}"
    local _cmd="${3:-"${_DOCKER_CMD}"}"

    ${_cmd} network ls --format "{{.Name}}" | grep -qE "^${_network_name}$" && return 0
    # TODO: add validation of the subnet. --subnet is needed to specify an IP in 'docker run'.
    ${_cmd} network create --driver=bridge --subnet=${_subnet_16}.0.0/16 --gateway=${_subnet_16}.0.1 ${_network_name} || return $?
    _log "DEBUG" "Bridge network '${_network_name}' is created with --subnet=${_subnet_16}.0.0/16 --gateway=${_subnet_16}.0.1"
}

function _container_add_NIC() {
    local _name="${1}"
    local _network="${2:-"bridge"}"
    local _cmd="${3:-"${_DOCKER_CMD}"}"

    local _net_names="$(${_cmd} inspect ${_name} | python -c "import sys,json;a=json.loads(sys.stdin.read());print(json.dumps(a[0]['NetworkSettings']['Networks'].keys()))")"
    if [[ "${_net_names}" =~ "${_network}" ]]; then
        _log "INFO" "The network '${_network}' is already set (${_net_names})"
        return 0
    fi
    local _before_gw="$(${_cmd} inspect ${_name} | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['NetworkSettings']['Gateway'])")"
    ${_cmd} network connect ${_network} ${_name} || return $?
    local _after_gw="$(${_cmd} inspect ${_name} | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['NetworkSettings']['Gateway'])")"
    if [ -n "${_before_gw}" ] && [ "${_before_gw}" != "${_after_gw}" ]; then
        _log "WARN" "Gateway address has been changed (before: "${_before_gw}", after: ${_after_gw})
     May want to execute below (please double check NIC name):
route add default gw ${_before_gw} eth0\
route del default gw ${_after_gw}\
"
    fi
    ${_cmd} exec -it ${_name} bash -c "netstat -rn"
}

function _container_available_ip() {
    local _hostname="${1}"      # optional
    local _check_file="${2}"    # /etc/hosts or /etc/banner_add_hosts
    local _subnet="${3}"        # 172.18.0.0
    local _network_name="${4:-${_DOCKER_NETWORK_NAME:-"bridge"}}"
    local _cmd="${5:-"${_DOCKER_CMD}"}"

    local _ip=""
    [ -z "${_subnet}" ] && _subnet="$(${_cmd} inspect ${_network_name} | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['IPAM']['Config'][0]['Subnet'])" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')"
    local _subnet_24="$(echo "${_subnet}" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')"
    ${_cmd} network inspect ${_network_name} | grep '"IPv4Address"' > ${__TMP%/}/${FUNCNAME}.list

    if [ -n "${_hostname}" ]; then
        local _short_name="`echo "${_hostname}" | cut -d"." -f1`"
        [ "${_short_name}" == "${_hostname}" ] && _hostname="${_short_name}.${_DOMAIN#.}"
        # Not perfect but... if the IP is in the /etc/hosts, then reuse it
        [ -s "${_check_file}" ] && _ip="$(grep -E "^${_subnet_24%.}\.[0-9]+\s+${_hostname}\s*" ${_check_file} | awk '{print $1}' | tail -n1)"
    fi

    if [ -z "${_ip}" ]; then
        # Using the range 101 - 199
        for _i in {101..199}; do
            if [ -s "${_check_file}" ] && grep -qE "^${_subnet_24%.}\.${_i}\s+" ${_check_file}; then
                _log "DEBUG" "${_subnet_24%.}\.${_i} exists in ${_check_file}. Skipping..."
                continue
            fi
            if ! grep -q "\"${_subnet_24%.}.${_i}/" ${__TMP%/}/${FUNCNAME}.list; then
                _log "DEBUG" "Using ${_subnet_24%.}\.${_i} as it does not exist in ${__TMP%/}/${FUNCNAME}.list."
                _ip="${_subnet_24%.}.${_i}"
                break
            fi
        done
    fi
    [ -z "${_ip}" ] && return 111

    if [ -n "${_hostname}" ] && [ -s "${_check_file}" ]; then
        # To reserve this IP, updating the check_file
        if _update_hosts_file "${_hostname}" "${_ip}" "${_check_file}"; then
            _log "DEBUG" "Updated ${_check_file} with \"${_hostname}\" \"${_ip}\""
        fi
    fi
    _log "DEBUG" "IP:${_ip} ($@)"
    echo "${_ip}"
}

function _container_ip() {
    local _container_name="$1"
    local _cmd="${2:-"${_DOCKER_CMD}"}"
    ${_cmd} exec -it ${_container_name} hostname -i | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' -m1 -o | tr -cd "[:print:]"   # remove unnecessary control characters
}

function _container_useradd() {
    local _name="${1}"
    local _user="${2:-"$USER"}"
    local _password="${3:-"${_user}123"}"
    local _sudoer="${4}"
    local _cmd="${5:-"${_DOCKER_CMD}"}"

    ${_cmd} exec -it ${_name} bash -c 'grep -q "^'$_user':" /etc/passwd && exit 0; useradd '$_user' -s `which bash` -p $(echo "'$_password'" | openssl passwd -1 -stdin) && usermod -a -G users '$_user || return $?
    ${_cmd} exec -it ${_name} bash -c 'if [ -f /root/.ssh/authorized_keys ]; then mkdir /home/'$_user'/.ssh &>/dev/null; [ ! -s /home/'$_user'/.ssh/id_rsa ] && ssh-keygen -q -N "" -f /home/'$_user'/.ssh/id_rsa; cp /root/.ssh/authorized_keys /home/'$_user'/.ssh/; chown -R '$_user': /home/'$_user'/.ssh; fi' || return $?
    if _isYes "${_sudoer}"; then
        ${_cmd} exec -it ${_name} bash -c "[ ! -f /etc/sudoers.d/${_user} ] && echo '${_user} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/${_user}"
    fi

    if ! grep -qw "nexus-client" $HOME/.ssh/config; then
        echo '
Host nexus-client
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  User '${_user} >> $HOME/.ssh/config
    fi
}

function _docker_login() {
    local _host_port="${1}"
    local _backup_ports="${2}"
    local _user="${3}"
    local _pwd="${4}"
    local _cmd="${5:-"${_DOCKER_CMD}"}"

    if [ -z "${_host_port}" ] && [ -n "${_backup_ports}" ]; then
        for __p in ${_backup_ports}; do
            nc -w1 -z localhost ${__p} 2>/dev/null && _host_port="localhost:${__p}" && break
        done
        if [ -n "${_host_port}" ]; then
            _log "DEBUG" "No hostname:port is given, so trying with ${_host_port}"
        fi
    fi
    if [ -z "${_host_port}" ]; then
        _log "WARN" "No hostname:port, so exiting"
        return 0
    fi

    _log "DEBUG" "${_cmd} login ${_host_port} --username ${_user} --password ********"
    ${_cmd} login ${_host_port} --username ${_user} --password ${_pwd} &>>${_LOG_FILE_PATH:-"/dev/null"} || return $?
    echo "${_host_port}"
}

function _docker_run_or_start() {
    local _name="$1"
    local _ext_opts="$2"
    local _image_name="$3"
    local _cmd="${4:-"${_DOCKER_CMD}"}"

    if ${_cmd} ps --format "{{.Names}}" | grep -qE "^${_name}$"; then
        _log "INFO" "Container:'${_name}' already exists. So that starting instead of docker run..."
        ${_cmd} start ${_name} || return $?
    else
        _log "DEBUG" "Creating a container with \"$@\""
        # TODO: normally container fails after a few minutes, so checking the exit code of below is not so useful.
        _docker_run "${_name}" "${_ext_opts}" "${_image_name}" "${_cmd}" || return $?
        _log "INFO" "\"${_cmd} run\" executed. Check progress with \"${_cmd} logs -f ${_name}\""
    fi
    sleep 3
    # Even specifying --ip, get IP from the container in below function
    _update_hosts_for_container "${_name}" "" "${_cmd}"
}

function _docker_run() {
    # TODO: shouldn't use any global variables in a function.
    local _name="$1"
    local _ext_opts="$2"
    local _image_name="${3}"
    local _cmd="${4:-"${_DOCKER_CMD}"}"

    # If dnsmasq or some dns is locally installed, assuming it's setup correctly
    if grep -qE '^nameserver\s+127\.' /etc/resolv.conf; then
        _ext_opts="${_ext_opts} --dns=`hostname -I | cut -d " " -f1`"
    fi
    # add one more if set
    local _another_dns="$(grep -m1 -E '^nameserver\s+[0-9]+\.' /etc/resolv.conf | grep -vE '^nameserver\s+127\.')"
    if [ -n "${_another_dns}" ]; then
        #_ext_opts="${_ext_opts} --dns=127.0.0.11"   # adding back the default DNS 127.0.0.11 generates WARNING
        _ext_opts="${_ext_opts} --dns=${_another_dns}"
    fi

    #[ -z "${_INTERNAL_DNS}" ] && _INTERNAL_DNS="$(docker inspect bridge | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['IPAM']['Config'][0]['Subnet'])" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+').1"
    [ -z "${INSTALL4J_ADD_VM_PARAMS}" ] && INSTALL4J_ADD_VM_PARAMS="-Xms1g -Xmx2g -XX:MaxDirectMemorySize=1g"
    local _full_cmd="${_cmd} run -t -d --name=${_name} --hostname=${_name}.${_DOMAIN#.} \\
        --network=${_DOCKER_NETWORK_NAME} ${_ext_opts} \\
        -e INSTALL4J_ADD_VM_PARAMS=\"${INSTALL4J_ADD_VM_PARAMS}\" \\
        ${_image_name}"
    _log "DEBUG" "${_full_cmd}"
    eval "${_full_cmd}" || return $?
}

# NOTE: To test name resolution as no nslookup,ping,nc, docker exec -ti nexus3240-1 curl -v -I http://nexus3240-3.standalone.localdomain:8081/
function _update_hosts_for_container() {
    local _container_name="${1}"
    local _fqdn="${2}"  # Optional
    local _cmd="${3:-"${_DOCKER_CMD}"}"

    [ -z "${_container_name}" ] && _container_name="`echo "${_fqdn}" | cut -d"." -f1`"
    [ -z "${_container_name}" ] && return 1
    [ -z "${_fqdn}" ] && _fqdn="${_container_name}.${_DOMAIN#.}"

    local _container_ip="`_container_ip "${_container_name}" "${_cmd}"`"
    if [ -z "${_container_ip}" ]; then
        _log "WARN" "${_container_name} is not returning IP. Please update hosts file manually."
        return 1
    fi

    if ! _update_hosts_file "${_fqdn}" "${_container_ip}"; then
        _log "WARN" "Please update hosts file to add '${_container_ip} ${_fqdn}'"
        return 1
    fi
    [ -n "${_DNS_RELOAD}" ] && eval "${_DNS_RELOAD}"
    _log "DEBUG" "Updated hosts file with '${_container_ip} ${_fqdn}'"
}
