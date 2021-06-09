#!/usr/bin/env bash
# source <(curl -sL --compressed https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils.sh)
# source <(curl -sL --compressed https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils_container.sh)

_DOCKER_CMD=${_DOCKER_CMD:-"docker"}    # To support podman etc.
_KUBECTL_CMD=${_KUBECTL_CMD:-"kubectl"}
_DOMAIN="${_DOMAIN:-"standalone.localdomain"}"
_DNS_RELOAD="sudo systemctl reload dnsmasq >/dev/null"
__TMP=${__TMP:-"/tmp"}
#_LOG_FILE_PATH=""


function _docker_cmd() {
    # Checking in my prefered order
    #TODO: if which skopeo &>/dev/null; then
    #    echo "skopeo"
    if which docker &>/dev/null; then
        echo "docker"
    elif which podman &>/dev/null; then
        echo "podman"
    fi
}

function _docker_add_network() {
    local _network_name="${1}"
    local _subnet_16="${2:-"172.100"}"
    local _cmd="${3-"${_DOCKER_CMD}"}"  # blank means auto-detect
    [ -z "${_cmd}" ] && _cmd="$(_docker_cmd)"
    [ -z "${_cmd}" ] && return 1

    ${_cmd} network ls --format "{{.Name}}" | grep -qE "^${_network_name}$" && return 0
    # TODO: add validation of the subnet. --subnet is needed to specify an IP in 'docker run'.
    ${_cmd} network create --driver=bridge --subnet=${_subnet_16}.0.0/16 --gateway=${_subnet_16}.0.1 ${_network_name} || return $?
    _log "DEBUG" "Bridge network '${_network_name}' is created with --subnet=${_subnet_16}.0.0/16 --gateway=${_subnet_16}.0.1"
}

function _container_add_NIC() {
    local _name="${1}"
    local _network="${2:-"bridge"}"
    local _keep_gw="${3}"
    local _cmd="${4-"${_DOCKER_CMD}"}"  # blank means auto-detect
    [ -z "${_cmd}" ] && _cmd="$(_docker_cmd)"
    [ -z "${_cmd}" ] && return 1

    local _net_names="$(${_cmd} inspect ${_name} | python -c "import sys,json;a=json.loads(sys.stdin.read());print(json.dumps(a[0]['NetworkSettings']['Networks'].keys()))")"
    if [[ "${_net_names}" =~ \"${_network}\" ]]; then
        _log "INFO" "The network '${_network}' is already set (${_net_names})"
        return 0
    fi
    local _before_gw="$(${_cmd} inspect ${_name} | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['NetworkSettings']['Gateway'])")"
    ${_cmd} network connect ${_network} ${_name} || return $?
    local _after_gw="$(${_cmd} inspect ${_name} | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['NetworkSettings']['Gateway'])")"
    if [ -n "${_before_gw}" ] && [ "${_before_gw}" != "${_after_gw}" ]; then
        if _isYes "${_keep_gw}"; then
            ${_cmd} exec -it ${_name} bash -c "route add default gw ${_before_gw} eth0; route del default gw ${_after_gw}"
        else
            _log "WARN" "Gateway address has been changed (before: ${_before_gw}, after: ${_after_gw})"
        fi
    fi
    ${_cmd} exec -it ${_name} bash -c "netstat -rn"
}

function _container_available_ip() {
    local _hostname="${1}"      # optional
    local _check_file="${2}"    # /etc/hosts or /etc/banner_add_hosts
    local _subnet="${3}"        # 172.18.0.0
    local _network_name="${4:-${_DOCKER_NETWORK_NAME:-"bridge"}}"
    local _cmd="${5-"${_DOCKER_CMD}"}"  # blank means auto-detect
    [ -z "${_cmd}" ] && _cmd="$(_docker_cmd)"
    [ -z "${_cmd}" ] && return 1

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
    local _cmd="${5-"${_DOCKER_CMD}"}"  # blank means auto-detect
    [ -z "${_cmd}" ] && _cmd="$(_docker_cmd)"
    [ -z "${_cmd}" ] && return 1

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
    local _cmd="${5-"${_DOCKER_CMD}"}"  # blank means auto-detect
    [ -z "${_cmd}" ] && _cmd="$(_docker_cmd)"
    [ -z "${_cmd}" ] && return 1

    if [ -n "${_backup_ports}" ]; then
        if [ -z "${_host_port}" ] || [[ "${_host_port}" =~ ^https?://([^:/]+) ]]; then
            local _host="${BASH_REMATCH[1]}"
            local _test_host="${_host:-"localhost"}"
            for __p in ${_backup_ports}; do
                nc -w1 -z ${_test_host} ${__p} &>/dev/null && _host_port="${_test_host}:${__p}" && break
            done
            if [ -n "${_host_port}" ]; then
                _log "DEBUG" "No hostname:port is given, so trying with ${_host_port}"
            fi
        fi
    fi
    if [ -z "${_host_port}" ]; then
        _log "WARN" "No hostname:port, so exiting"
        return 0
    fi

    _log "DEBUG" "${_cmd} login ${_host_port} --username ${_user} --password ********"
    ${_cmd} login ${_host_port} --username ${_user} --password ${_pwd} >&2 || return $?
    echo "${_host_port}"
}

# Install NXRM3 OSS
#   _docker_run_or_start "nexus3-oss" "-p 8181:8081" "sonatype/nexus3:3.24.0"
# Install NXRM2 OSS
#   _docker_run_or_start "nexus2-oss" "-p 8181:8081" "sonatype/nexus:2.14.18-01"
function _docker_run_or_start() {
    local _name="$1"
    local _ext_opts="$2"
    local _image_name="$3"
    local _cmd="${4-"${_DOCKER_CMD}"}"  # blank means auto-detect
    [ -z "${_cmd}" ] && _cmd="$(_docker_cmd)"
    [ -z "${_cmd}" ] && return 1

    if ${_cmd} ps -a --format "{{.Names}}" | grep -qE "^${_name}$"; then
        _log "INFO" "Container:'${_name}' already exists. Executing ${_cmd} start ${_name} ..."
        ${_cmd} start ${_name} || return $?
    else
        _log "DEBUG" "Creating a container with \"$@\""
        # TODO: normally container fails after a few minutes, so checking the exit code of below is not so useful.
        _docker_run "${_name}" "${_ext_opts}" "${_image_name}" "${_cmd}" || return $?
    fi
    sleep 3
    _log "INFO" "Container started (progress: \"${_cmd} logs -f ${_name}\") Updating hosts ..."
    # Even specifying --ip, get IP from the container in below function
    _update_hosts_for_container "${_name}" "" "${_cmd}"
}

function _docker_run() {
    # TODO: shouldn't use any global variables in a function.
    local _name="$1"
    local _ext_opts="$2"
    local _image_name="${3}"
    local _cmd="${4-"${_DOCKER_CMD}"}"  # blank means auto-detect
    [ -z "${_cmd}" ] && _cmd="$(_docker_cmd)"
    [ -z "${_cmd}" ] && return 1

    # If dnsmasq or some dns is locally installed, assuming it's setup correctly
    if grep -qE '^nameserver\s+127\.' /etc/resolv.conf; then
        _ext_opts="--dns=`hostname -I | cut -d " " -f1` ${_ext_opts}"
    fi
    # add one more if set
    local _another_dns="$(grep -m1 -E '^nameserver +[0-9]+\.' /etc/resolv.conf | grep -vE '^nameserver\s+127\.' | sed -E 's/^nameserver +//')"
    if [ -n "${_another_dns}" ]; then
        # REMINDER: adding back the default DNS 127.0.0.11 generates WARNING
        _ext_opts="--dns=${_another_dns} ${_ext_opts}"
    fi

    # NXRM3 specific (TODO: below shouldn't be in this function)
    [ -n "${INSTALL4J_ADD_VM_PARAMS}" ] && _ext_opts="${_ext_opts} -e INSTALL4J_ADD_VM_PARAMS=\"${INSTALL4J_ADD_VM_PARAMS}\""

    local _full_cmd="${_cmd} run -t -d --name=${_name} --hostname=${_name}.${_DOMAIN#.} \\
        ${_ext_opts} \\
        ${_image_name}"
    _log "DEBUG" "${_full_cmd}"
    eval "${_full_cmd}" || return $?
}

# NOTE: To test name resolution as no nslookup,ping,nc, docker exec -ti nexus3240-1 curl -v -I http://nexus3240-3.standalone.localdomain:8081/
function _update_hosts_for_container() {
    local _container_name="${1}"
    local _fqdn="${2}"  # Optional
    local _cmd="${3-"${_DOCKER_CMD}"}"  # blank means auto-detect
    [ -z "${_cmd}" ] && _cmd="$(_docker_cmd)"
    [ -z "${_cmd}" ] && return 1

    [ -z "${_container_name}" ] && _container_name="`echo "${_fqdn}" | cut -d"." -f1`"
    [ -z "${_container_name}" ] && return 1
    [ -z "${_fqdn}" ] && _fqdn="${_container_name}.${_DOMAIN#.}"

    local _container_ip="`_container_ip "${_container_name}" "${_cmd}"`"
    if [ -z "${_container_ip}" ]; then
        _log "WARN" "${_container_name} is not returning IP. Please update hosts file manually."
        return 1
    fi

    if ! _update_hosts_file "${_fqdn}" "${_container_ip}" "/etc/hosts"; then
        _log "WARN" "Please update /etc/hosts file to add '${_container_ip} ${_fqdn}'"
        return 1
    fi
    [ -n "${_DNS_RELOAD}" ] && eval "${_DNS_RELOAD}" 2>/dev/null
    _log "DEBUG" "Updated /etc/hosts file with '${_container_ip} ${_fqdn}'"
}

function _update_hosts_for_k8s() {
    local _host_file="${1}"
    local _labelname="${2}" # nexus-repository-manager
    local _namespace="${3:-"default"}"
    local _k="${4:-"${_KUBECTL_CMD:-"kubectl"}"}"
    [ -f "${_host_file}" ] || return 11
    if [ -n "${_labelname}" ]; then
        _labelname="app.kubernetes.io/name=${_labelname}"
    fi
    _k8s_exec 'echo $(hostname -f) $(hostname -i)' "${_labelname}" "${_namespace}" "3" | grep ".${_namespace}." > "${__TMP%/}/${FUNCNAME}.tmp" || return $?
    cat "${__TMP%/}/${FUNCNAME}.tmp" | while read -r _line; do
        if ! _update_hosts_file ${_line} ${_host_file}; then
            _log "WARN" "Please update ${_host_file} file to add ${_line}"
        fi
        [ "${_host_file}" -nt "${__TMP%/}/${FUNCNAME}.last" ] && _log "INFO" "${_host_file} was updated with ${_line}"
    done
    [ -n "${_DNS_RELOAD}" ] && [ "${_host_file}" -nt "${__TMP%/}/${FUNCNAME}.last" ] && eval "${_DNS_RELOAD}" 2>/dev/null
    date > "${__TMP%/}/${FUNCNAME}.last"
}

_CONTAINER_CMD="${_CONTAINER_CMD:-"microk8s ctr containers"}"
function _k8s_nsenter() {
    local _cmd="${1}"
    local _filter="${2}" # docker.io/sonatype/nexus3:30.1 or image_id
    local _parallel="${3}"
    : > ${__TMP%/}/${FUNCNAME}.list
    # | python -c "import sys,json;a=json.loads(sys.stdin.read());print(json.dumps(a['Spec']['linux']['namespaces']))"
    ${_CONTAINER_CMD} ls | grep -E "${_filter}" | awk '{print $1}' | while read -r _i; do
        ${_CONTAINER_CMD} info ${_i} | sed -n -r 's@.+/proc/([0-9]+)/ns/.+@\1@p' | head -n1 >> ${__TMP%/}/${FUNCNAME}.list
    done 2>/dev/null
    cat ${__TMP%/}/${FUNCNAME}.list | xargs -I{} -t -P${_parallel:-"1"} nsenter -t {} -n ${_cmd}
}

function _k8s_exec() {
    local _cmd="${1}"
    local _l="${2}" # kubernetes.io/name=nexus-repository-manager
    local _ns="${3:-"default"}"
    local _parallel="${4}"
    local _k="${5:-"${_KUBECTL_CMD:-"kubectl"}"}"
    if [ -z "${_l}" ]; then
        ${_k} get pods -n "${_ns}" --show-labels --field-selector=status.phase=Running | awk '{print $1"\n    "$6}'
        return 11
    fi
    ${_k} get pods -n "${_ns}" -l "${_l}" --field-selector=status.phase=Running -o custom-columns=name:metadata.name --no-headers | xargs -I{} -t -P${_parallel:-"1"} kubectl exec -n "${_ns}" {} -- sh -c "${_cmd}"
}

#_k8s_stop "nxrm3-ha3,nxrm3-ha2,nxrm3-ha1" "-nexus-repository-manager" "sonatype"
function _k8s_stop() {
    local _names="${1}"
    local _suffix="${2}"
    local _ns="${3:-"default"}"
    local _ttl="${4:-60}"
    local _k="${5:-"${_KUBECTL_CMD:-"kubectl"}"}"
    for _name in $(echo ${_names} | sed "s/,/ /g"); do
        ${_k} scale -n "${_ns}" deployment ${_name}${_suffix} --replicas=0 || return $?
        # TODO: should check status
        sleep ${_ttl}
    done
}

#_k8s_stop "nxrm3-ha1,nxrm3-ha2,nxrm3-ha3" "-nexus-repository-manager" "sonatype"
function _k8s_start() {
    local _names="${1}"
    local _suffix="${2}"
    local _ns="${3:-"default"}"
    local _ttl="${4:-120}"
    local _k="${5:-"${_KUBECTL_CMD:-"kubectl"}"}"
    for _name in $(echo ${_names} | sed "s/,/ /g"); do
        ${_k} scale -n "${_ns}" deployment ${_name}${_suffix} --replicas=1 || return $?
        # TODO: should check status
        sleep ${_ttl}
    done
}
