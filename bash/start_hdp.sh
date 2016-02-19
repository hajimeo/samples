#!/bin/bash
# This script setups docker, then create a container(s), and install ambari-server
#
# Steps:
# 1. Install OS. Recommend Ubuntu 14.x
# 2. sudo -i    (TODO: only root works at this moment)
# 3. (optional) screen
# 4. wget https://raw.githubusercontent.com/hajimeo/samples/master/bash/start_hdp.sh  -O ./start_hdp.sh
# 5. chmod u+x ./start_hdp.sh
# 6. ./start_hdp.sh -i
# 7. answer questions
#
# Once setup, just run ./start_hdp.sh to start service if server is rebooted
#
# Rules:
# 1. Function name needs to start with f_ or p_
# 2. Function arguments need to use local and start with _
# 3. Variable name which stores user response needs to start with r_
# 4. (optional) __doc__ local variable is for function usage/help
#

### OS/shell settings
shopt -s nocasematch
#shopt -s nocaseglob
set -o posix
#umask 0000


usage() {
    echo "HELP/USAGE:"
    echo "This script is for setting up this host for HDP or start HDP services.

How to run:
    ./${g_SCRIPT_NAME} [-s] [-r=some_file_name.resp]

How to run only one function:
    1) source ./${g_SCRIPT_NAME}
    2) for example to output help, type 'help'
    3) f_loadResp
    4) list response
    5) f_ambari_server_install

Available options:
    -i    Initial set up this host for HDP

    -s    Start HDP services (default)

    -r=response_file_path
          To reuse your previously saved response file.

    -h    Show this message.
"
}

# Global variables
g_SCRIPT_NAME=`basename $BASH_SOURCE`
g_SCRIPT_BASE=`basename $BASH_SOURCE .sh`
g_DEFAULT_RESPONSE_FILEPATH="./${g_SCRIPT_BASE}.resp"
g_BACKUP_DIR="$HOME/.build_script/"
g_DOCKER_BASE="hdp/base"
__PID="$$"
__LAST_ANSWER=""

### Procedure type functions

function p_interview() {
    local __doc__="Asks user questions."
    _ask "NTP Server" "ntp.ubuntu.com" "r_NTP_SERVER" "N" "Y"
    # TODO: Changing this IP later is troublesome, so need to be careful
    _ask "IP address for docker0 interface" "172.17.42.1" "r_DOCKER_HOST_IP" "N" "Y"
    _ask "Network Address (xxx.xxx.xxx.) for docker containers" "172.17.100." "r_DOCKER_NETWORK_ADDR" "N" "Y"
    _ask "Domain Suffix for docker containers" ".localdomain" "r_DOMAIN_SUFFIX" "N" "Y"
    _ask "Container OS type" "centos" "r_CONTAINER_OS" "N" "Y"
    _ask "Container OS version" "6" "r_CONTAINER_OS_VER" "N" "Y"
    _ask "How many nodes?" "4" "r_NUM_NODES" "N" "Y"
    #_ask "Username to mount VM host directory for local repo (optional)" "$SUDO_UID" "r_VMHOST_USERNAME" "N" "N"

    # TODO: Questions to install Ambari
    _ask "Ambari server hostname" "node1$r_DOMAIN_SUFFIX" "r_AMBARI_HOST" "N" "Y"
    _ask "Ambari server version (used to build repo URL)" "2.2.0.0" "r_AMBARI_VER" "N" "Y"
    _echo "If you have set up a Local Repo, please change below"
    _ask "Ambari repo" "http://public-repo-1.hortonworks.com/ambari/${r_CONTAINER_OS}${r_CONTAINER_OS_VER}/2.x/updates/${r_AMBARI_VER}/ambari.repo" "r_AMBARI_REPO" "N" "Y"
}

function p_interview_or_load() {
    local __doc__="Asks user to start interview, review interview, or start installing with given response file."

    if [ -z "${_RESPONSE_FILE_PATH}" ]; then
        _info "Set up was requested but no response file, so that using ${g_DEFAULT_RESPONSE_FILEPATH}..."
        _RESPONSE_FILE_PATH="$g_DEFAULT_RESPONSE_FILEPATH"
    fi

    if [ -r "${_RESPONSE_FILE_PATH}" ]; then
        if [ _isYes "$_START_HDP" ]; then
            f_loadResp
            return $?
        fi

        _ask "Would you like to load ${_RESPONSE_FILE_PATH}?" "Y"
        if ! _isYes; then _echo "Bye."; exit 0; fi
        f_loadResp
        _ask "Would you like to review your responses?" "Y"
        # if don't want to review, just load and exit
        if ! _isYes; then
            return 0
        fi
    else
        _info "responses will be saved into ${_RESPONSE_FILE_PATH}"
    fi

    _info "Starting Interview mode..."
    _info "You can stop this interview anytime by pressing 'Ctrl+c' (except while typing secret/password)."
    echo ""

    trap '_cancelInterview' SIGINT
    while true; do
        p_interview

        _info "Interview completed."
        _ask "Would you like to save your response?" "Y"
        if ! _isYes; then
            _ask "Would you like to re-do the interview?" "Y"
            if ! _isYes; then
                _echo "Continuing without saving..."
                break
            fi
        else
            break
        fi
    done
    trap - SIGINT

    f_saveResp
}
function _cancelInterview() {
	echo ""
	echo ""
	echo "Exiting..."
	_ask "Would you like to save your current responses?" "N" "is_saving_resp"
	if _isYes "$is_saving_resp"; then
		f_saveResp
	fi
	_exit
}

function p_start_hdp() {
    f_docker0_setup
    f_ntp
    f_docker_start
    sleep 4
    _info "Not setting up the default GW. please use f_gw_set if necessary"
    #f_gw_set
    f_ambari_start
    f_etcs_mount
    echo "WARN: Will start all services..."
    f_services_start
    f_screen_cmd
}

function f_saveResp() {
    local __doc__="Save current responses(answers) in memory into a file."
    local _file_path="${1-$_RESPONSE_FILE_PATH}"
    
    if [ -z "$_file_path" ]; then
        _ask "Response file path" "$g_DEFAULT_RESPONSE_FILEPATH" "_RESPONSE_FILE_PATH"
        _file_path="$_RESPONSE_FILE_PATH"
    fi

    if [ ! -e "${_file_path}" ]; then
        touch ${_file_path}
    else
        _backup "${_file_path}"
    fi
    
    if [ ! -w "${_file_path}" ]; then
        _critical "$FUNCNAME: Not a writeable response file. ${_file_path}" 1
    fi
    
    # clear file (no warning...)
    cat /dev/null > ${_file_path}
    
    for _v in `set | grep -P -o "^r_.+?[^\s]="`; do
        _new_v="${_v%=}"
        echo "${_new_v}=\"${!_new_v}\"" >> ${_file_path}
    done
    
    # trying to be secure as much as possible
    if [ -n "$SUDO_USER" ]; then
        chown $SUDO_UID:$SUDO_GID ${_file_path}
    fi
    chmod 1600 ${_file_path}
    
    _info "Saved ${_file_path}"
}

function f_loadResp() {
    local __doc__="Load responses(answers) from given file path or from default location."
    local _file_path="${1-$g_DEFAULT_RESPONSE_FILEPATH}"
    
    if [ -z "$_file_path" ]; then
        _file_path="$g_DEFAULT_RESPONSE_FILEPATH";
    fi
    
    local _actual_file_path="$_file_path"
    if [ ! -r "${_file_path}" ]; then
        _critical "$FUNCNAME: Not a readable response file. ${_file_path}" 1;
        return 1
    fi
    
    #g_response_file="$_file_path"  TODO: forgot what this line was for
    
    #local _extension="${_actual_file_path##*.}"
    #if [ "$_extension" = "7z" ]; then
    #    local _dir_path="$(dirname ${_actual_file_path})"
    #    cd $_dir_path && 7za e ${_actual_file_path} || _critical "$FUNCNAME: 7za e error."
    #    cd - >/dev/null
    #    _used_7z=true
    #fi
    
    # Note: somehow "source <(...)" does noe work, so that created tmp file.
    grep -P -o '^r_.+[^\s]=\".*?\"' ${_file_path} > /tmp/f_loadResp_${__PID}.out && source /tmp/f_loadResp_${__PID}.out
    
    # clean up
    rm -f /tmp/f_loadResp_${__PID}.out

    return $?
}

function f_ntp() {
    local __doc__="Run ntpdate $r_NTP_SERVER"
    _info "ntpdate ..."
    ntpdate -u $r_NTP_SERVER
}

function f_docker0_setup() {
    local __doc__="Setting IP for docker0 to $r_DOCKER_HOST_IP ..."
    local _docer0="${1-$r_DOCKER_HOST_IP}"
    _info "Setting IP for docker0 to $_docer0 ..."
    ifconfig docker0 $_docer0
}

function f_docker_base_create() {
    local __doc__="Create a docker base image"
    local _docker_file="$1"
    if [ -z "$_docker_file" ]; then
        _docker_file="./DockerFile"
    fi
    if [ ! -r "$_docker_file" ]; then
        _error "$_docker_file is not readable"
        return 1
    fi

    if [ -z "$r_CONTAINER_OS" ]; then
        _error "No container OS specified"
        return 1
    fi
    docker images | grep -P "^${r_CONTAINER_OS}\s+${r_CONTAINER_OS_VER}" || docker pull ${r_CONTAINER_OS}:${r_CONTAINER_OS_VER}
    docker build -t ${g_DOCKER_BASE} -f $_docker_file .
}

function f_docker_start() {
    local __doc__="Starting docker containers"
    local num=`docker ps -aq | wc -l`
    local _num=`docker ps -q | wc -l`
    if [ $_num -ne 0 ]; then
      _info "$_num containers are already running...";
    else
      _info "starting $num docker contains ..."
      for i in `seq 1 $num`; do docker start --attach=false node$i; sleep 1; done
    fi
}

function f_docker_run() {
    local __doc__="Running (creating) docker containers"
    local _num="${1-$r_NUM_NODES}"
    local _num_running=`docker ps -q | wc -l`

    if [ $_num_running -ne 0 ]; then
      _error "$_num_running containers are already running...";
      return 1
    fi

    if [ -z "$_num" ]; then
        _warn "Number of nodes (containers) is not specified."
        return 1
    fi

    local _ip="`f_docker_ip`"

    if [ -z "$_ip" ]; then
        _warn "No Docker interface IP"
        return 1
    fi

    for n in `seq 1 $_num`; do
        docker run -t -i -d --dns $_ip --name node$n --privileged ${g_DOCKER_BASE} /startup.sh ${r_DOCKER_NETWORK_ADDR}$n node$n${r_DOMAIN_SUFFIX} $_ip
    done
}

function f_ambari_server_install() {
    local __doc__="Install Ambari Server to $r_AMBARI_HOST"
    if [ -z "$r_AMBARI_REPO" ]; then
        _error "Please specify Ambari repo URL"
        return 1
    fi

    # TODO: at this moment, only Centos (yum)
    wget -nv "$r_AMBARI_REPO" -O /tmp/ambari.repo || retuen 1
    scp /tmp/ambari.repo root@$r_AMBARI_HOST:/etc/yum.repos.d/
    ssh -t root@$r_AMBARI_HOST "yum install ambari-server -y"
    ssh -t root@$r_AMBARI_HOST "ambari-server setup -s"
    ssh -t root@$r_AMBARI_HOST "ambari-server start"
}

function f_ambari_server_start() {
    local __doc__="Starting ambari-server on $r_AMBARI_HOST"
    ssh -t root@$r_AMBARI_HOST "ambari-server start"
}

function f_ambari_agent_start() {
    local __doc__="Starting ambari-agent on all containers"
    local _num=`docker ps -q | wc -l`
    for i in `seq 1 $_num`; do
        ssh -t root@node$i${r_DOMAIN_SUFFIX} 'ambari-agent start'
    done
}

function f_ambari_start() {
    local __doc__="Starting ambari-server and all ambari-agents"
    f_ambari_server_start || return $?
    f_ambari_agent_start
}

function f_etcs_mount() {
    local __doc__="Mounting all agent's etc directories (handy for troubleshooting)"
    local _num=`docker ps -q | wc -l`
    for i in `seq 1 $_num`; do
        if [ ! -d /mnt/etc/node$i ]; then
            mkdir -p /mnt/etc/node$i
        fi

        if [ -d /mnt/etc/node$i/hadoop ];then
            continue
        fi

        umount /mnt/etc/node$i 2>/dev/null;
        sshfs -o allow_other,uid=0,gid=0,umask=002,reconnect,transform_symlinks node${i}${r_DOMAIN_SUFFIX}:/etc /mnt/etc/node${i}
    done
}

function f_repo_setup() {
    local __doc__="TODO: This would work on only my environment. Mounting VM host's directory to use for local repo"
    local _host_pc="$1"
    local _mu="$2"
    local _src="${3-/Users/${_mu}/Public/hdp/}"
    local _mounting_dir="/var/www/html/hdp"

    if [ -z "$_host_pc" ]; then
      _host_pc="`env | awk '/SSH_CONNECTION/ {gsub("SSH_CONNECTION=", "", $1); print $1}'`"
      if [ -z "$_host_pc" ]; then
        _host_pc="192.168.136.1"
      fi
    fi

    mount | grep "$_mounting_dir"
    if [ $? -eq 0 ]; then
      umount -f "$_mounting_dir"
    fi
    if [ ! -d "$_mounting_dir" ]; then
        mkdir "$_mounting_dir" || return
    fi

    _info "Mounting ${_mu}@${_host_pc}:${_src} to $_mounting_dir ..."
    _info "TODO: Edit this function for your env if above is not good (and Ctrl+c now)"
    sleep 4
    sshfs -o allow_other,uid=0,gid=0,umask=002,reconnect,transform_symlinks ${_mu}@${_host_pc}:${_src} "$_mounting_dir"
    service apache2 start
}

function f_services_start() {
    local __doc__="Request 'Start all' to Ambari via API"
    c=$(PGPASSWORD=bigdata psql -Uambari -h $r_AMBARI_HOST -tAc "select cluster_name from ambari.clusters order by cluster_id desc limit 1;")
    if [ -z "$c" ]; then
      _error "No cluster name (check PostgreSQL)..."
      return 1
    fi
    
    for i in `seq 1 10`; do
      u=$(PGPASSWORD=bigdata psql -Uambari -h $r_AMBARI_HOST -tAc "select count(*) from hoststate where health_status ilike '%UNKNOWN%';")
      #curl -s --head "http://$r_AMBARI_HOST:8080/" | grep '200 OK'
      if [ "$u" -eq 0 ]; then
        break
      fi
  
      _info "Some Ambari agent is in UNKNOWN state ($u). retrying..."
      sleep 5
    done

    for i in `seq 1 10`; do
      nc -z $r_AMBARI_HOST 8080 && break

      _info "Ambari server is not listening on $r_AMBARI_HOST:8080 Waiting..."
      sleep 5
    done

    # trying anyway
    sleep 10
    curl -u admin:admin -H "X-Requested-By: ambari" "http://$r_AMBARI_HOST:8080/api/v1/clusters/${c}/services?" -X PUT --data '{"RequestInfo":{"context":"_PARSE_.START.ALL_SERVICES","operation_level":{"level":"CLUSTER","cluster_name":"'${c}'"}},"Body":{"ServiceInfo":{"state":"STARTED"}}}'
    echo ""
}

function f_screen_cmd() {
    local __doc__="Output GNU screen command"
    screen -ls | grep -w docker
    if [ $? -ne 0 ]; then
      local _num=`docker ps -q | wc -l`
      _info "You may want to run the following commands to start GNU Screen:"
      echo "screen -S \"docker\" bash -c 'for s in \`seq 1 4\`; do screen -t \"node\${s}\" \"ssh\" \"node\${s}${r_DOMAIN_SUFFIX}\"; done'"
    fi
}

function p_host_setup() {
    local __doc__="Install packages into this host (Ubuntu)"
    local _docer0="${1-$r_DOCKER_HOST_IP}"
    set -v
    apt-get update && apt-get upgrade -y
    apt-get -y install wget createrepo sshfs dnsmasq apache2 htop dstat iotop sysv-rc-conf postgresql-client mysql-client
    #krb5-kdc krb5-admin-server mailutils postfix
    
    apt-key adv --keyserver hkp://pgp.mit.edu:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
    grep "deb https://apt.dockerproject.org/repo" /etc/apt/sources.list.d/docker.list || echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" >> /etc/apt/sources.list.d/docker.list
    apt-get update && apt-get purge lxc-docker*; apt-get install docker-engine -y

    grep '^addn-hosts=' /etc/dnsmasq.conf || echo 'addn-hosts=/etc/banner_add_hosts' >> /etc/dnsmasq.conf

    # TODO: the first IP can be wrong one
    _docer0="`f_docker_ip`"
    # TODO: shouldn't hardcode 'dockerhost1'?
    echo "$_docer0     dockerhost1${r_DOMAIN_SUFFIX} dockerhost1" > /etc/banner_add_hosts
    for i in `seq 1 10`; do
        echo "${r_DOCKER_NETWORK_ADDR}${i}    node${i}${r_DOMAIN_SUFFIX} node${i}" >> /etc/banner_add_hosts
    done
    service dnsmasq restart

    f_host_performance

    f_dockerfile
    f_docker0_setup "$_docer0"
    f_docker_base_create

    f_docker_run

    # Making directory for Apache2
    mkdir -m 777 /var/www/html/hdp

    f_ambari_server_install
    set +v
}

function f_host_performance() {
    local __doc__="Change kernel parameters on Docker Host (Ubuntu)"
    grep '^vm.swappiness' /etc/sysctl.conf || echo "vm.swappiness = 0" >> /etc/sysctl.conf
    sysctl -w vm.swappiness=0

    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    echo never > /sys/kernel/mm/transparent_hugepage/defrag
}

function f_dockerfile() {
    local __doc__="Download dockerfile and replace private key"
    wget https://raw.githubusercontent.com/hajimeo/samples/master/docker/DockerFile -O DockerFile

    f_ssh_setup

    local _pkey="`sed ':a;N;$!ba;s/\n/\\\\\\\n/g' $HOME/.ssh/id_rsa`"

    sed -i.bak "s@_REPLACE_WITH_YOUR_PRIVATE_KEY_@${_pkey}@1" DockerFile
    if [ -n "$r_CONTAINER_OS" ]; then
        sed -i.bak "s@centos:6@${r_CONTAINER_OS}:$r_CONTAINER_OS_VER}@1" DockerFile
    fi
}

function f_ssh_setup() {
    if [ ! -e $HOME/.ssh/id_rsa ]; then
        ssh-keygen -f $HOME/.ssh/id_rsa -q -N ""
    fi

    if [ ! -e $HOME/.ssh/config ]; then
        echo "Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null" > $HOME/.ssh/config
    fi

    if [ ! -e /root/.ssh/id_rsa ]; then
        mkdir /root/.ssh &>/dev/null
        cp $HOME/.ssh/config /root/.ssh/id_rsa
        chmod 600 /root/.ssh/id_rsa
        chown -R root:root /root/.ssh
    fi
}

function f_hostname_set() {
    local __doc__="Set hostname"
    local _new_name="$1"
    if [ -z "$_new_name" ]; then
      _error "no hostname"
      return 1
    fi
    
    set -v
    local _current="`cat /etc/hostname`"
    hostname $_new_name
    echo "$_new_name" > /etc/hostname
    sed -i.bak "s/\b${_current}\b/${_new_name}/g" /etc/hosts
    diff /etc/hosts.bak /etc/hosts
    set +v
}

function f_yum_remote_proxy() {
    local __doc__="TODO: This function is to achive less internet usage caused by downloading packges. Havn't completed yet"
    local _proxy="$1"
    local _host="$2"

    ssh -t root@$_host "grep proxy /etc/yum.conf" && return 1
    ssh -t root@$_host "echo "proxy=${_proxy}" >> /etc/yum.conf"
    ssh -t root@$_host "grep proxy /etc/yum.conf"
}

function f_gw_set() {
    local __doc__="Set new default gateway to each container"
    local _gw="`f_docker_ip`"
    local _num=`docker ps -q | wc -l`
    set -v
    for i in `seq 1 $_num`; do
        ssh -t root@node$i${r_DOMAIN_SUFFIX} "route add default gw $_gw eth0"
    done
    set +v
}

function f_docker_ip() {
    local __doc__="Output docker0 IP or specified NIC's IP"
    local _if="${1-docker0}"
    ifconfig $_if | grep -oP 'inet addr:\d+\.\d+\.\d+\.\d' | cut -d":" -f2
    return $?
}

function f_log_cleanup() {
    local __doc__="Deleting log files which group owner is hadoop"
    local _days="${1-7}"
    echo "Deleting hadoop logs which is older than $_days..."
    local _num=`docker ps -q | wc -l`
    #set -x
    for i in `seq 1 $_num`; do
        ssh -t root@node$i${r_DOMAIN_SUFFIX} "\"find /var/log/ -type f -group hadoop -mtime +${_days} -print0 | xargs -0 -n1 -I {} rm -f {}\""
    done
    #set +x
}
function f_checkUpdate() {
    local __doc__="Check if newer script is available, then download."
    local _local_file_path="${1-$BASH_SOURCE}"
    local _file_name=`basename ${_local_file_path}`
    local _remote_url="https://raw.githubusercontent.com/hajimeo/samples/master/bash/$_file_name"   # TODO: should I hard-code?

    if [ ! -s "$_local_file_path" ]; then
        _warn "$FUNCNAME: could not check last modified time of $_local_file_path"
        return 1
    fi

    if ! _isCmd "curl"; then
        if [ "$0" = "$BASH_SOURCE" ]; then
            _warn "$FUNCNAME: No 'curl' command. Exiting."; return 1
        else
            _ask "Would you like to install 'curl'?" "Y"
            if _isYes ; then
                DEBIAN_FRONTEND=noninteractive apt-get -y install curl &>/dev/null
            fi
        fi
    fi

    # --basic --user ${r_svn_user}:${r_svn_pass}
    local _remote_last_mod="$(curl -s -k -L --head "${_remote_url}" | grep -i last-modified | cut -c16-)"
    if [ -z "$_remote_last_mod" ]; then _warn "$FUNCNAME: Unknown last modified."; return 1; fi

    local _remote_last_mod_ts=`date -d "${_remote_last_mod}" +"%s"`
    local _local_last_mod_ts=`stat -c%Y ${_local_file_path}`

    #_log "Remote: ${_remote_last_mod_ts} (gt) Local: ${_local_last_mod_ts}"
    if [ ${_remote_last_mod_ts} -gt ${_local_last_mod_ts} ]; then
        _info "Newer file is available."
        echo "$_remote_last_mod"
        _ask "Would you like to download?" "Y"
        if ! _isYes; then return 0; fi
        _backup "${_local_file_path}"

        if [[ "${_local_file_path}" =~ ^/data/sites/ ]]; then
            svn up ${_local_file_path}
        elif [[ "`pwd`" =~ ^/data/sites/ ]]; then
            svn up ${_local_file_path}
        else
            curl -k -L '$_remote_url' -o ${_local_file_path} || _critical "$FUNCNAME: Update failed."
        fi

        _info "Validating the downloaded script..."
        source ${_local_file_path} || _critical "Please contact the script author."
        changeLog
    fi
}

### Utility type functions #################################################
_YES_REGEX='^(1|y|yes|true|t)$'
_IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
_IP_RANGE_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(/[0-3]?[0-9])?$'
_HOSTNAME_REGEX='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
_URL_REGEX='(https?|ftp|file|svn)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'
_TEST_REGEX='^\[.+\]$'

function _ask() {
    local _question="$1"
    local _default="$2"
    local _var_name="$3"
    local _is_secret="$4"
    local _is_mandatory="$5"
    local _validation_func="$6"

    local _default_orig="$_default"
    local _cmd=""
    local _full_question="${_question}"
    local _trimmed_answer=""
    local _previous_answer=""

    if [ -z "${_var_name}" ]; then
        __LAST_ANSWER=""
        _var_name="__LAST_ANSWER"
    fi

    # currently only checking previous value of the variable name starting with "r_"
    if [[ "${_var_name}" =~ ^r_ ]]; then
        _previous_answer=`_trim "${!_var_name}"`
        if [ -n "${_previous_answer}" ]; then _default="${_previous_answer}"; fi
    fi

    if [ -n "${_default}" ]; then
        if _isYes "$_is_secret" ; then
            _full_question="${_question} [*******]"
        else
            _full_question="${_question} [${_default}]"
        fi
    fi

    if _isYes "$_is_secret" ; then
        local _temp_secret=""

        while true ; do
            read -p "${_full_question}: " -s "${_var_name}"; echo ""

            if [ -z "${!_var_name}" -a -n "${_default}" ]; then
                eval "${_var_name}=\"${_default}\""
                break;
            else
                read -p "${_question} (again): " -s "_temp_secret"; echo ""

                if [ "${!_var_name}" = "${_temp_secret}" ]; then
                    break;
                else
                    echo "1st value and 2nd value do not match."
                fi
            fi
        done
    else
        read -p "${_full_question}: " "${_var_name}"

        _trimmed_answer=`_trim "${!_var_name}"`

        if [ -z "${_trimmed_answer}" -a -n "${_default}" ]; then
            # if new value was only space, use original default value instead of previous value
            if [ -n "${!_var_name}" ]; then
                eval "${_var_name}=\"${_default_orig}\""
            else
                eval "${_var_name}=\"${_default}\""
            fi
        else
            eval "${_var_name}=\"${_trimmed_answer}\""
        fi
    fi

    # if empty value, check if this is a mandatory field.
    if [ -z "${!_var_name}" ]; then
        if _isYes "$_is_mandatory" ; then
            echo "'${_var_name}' is a mandatory parameter."
            _ask "$@"
        fi
    else
        # if not empty and if a validation function is given, use function to check it.
        if _isValidateFunc "$_validation_func" ; then
            $_validation_func "${!_var_name}"
            if [ $? -ne 0 ]; then
                _ask "Given value does not look like correct. Would you like to re-type?" "Y"
                if _isYes; then
                    _ask "$@"
                fi
            fi
        fi
    fi
}
function _backup() {
    local __doc__="Backup the given file path into ${g_BACKUP_DIR}."
    local _file_path="$1"
    local _file_name="`basename $_file_path`"
    local _force="$2"
    local _new_file_name=""

    if [ ! -e "$_file_path" ]; then
        _warn "$FUNCNAME: Not taking a backup as $_file_path does not exist."
        return 1
    fi

    if _isYes "$_force"; then
        local _mod_dt="`stat -c%y $_file_path`"
        local _mod_ts=`date -d "${_mod_dt}" +"%Y%m%d-%H%M%S"`

        if [[ ! $_file_name =~ "." ]]; then
            _new_file_name="${_file_name}_${_mod_ts}"
        else
            _new_file_name="${_file_name/\./_${_mod_ts}.}"
        fi
    else
        if [[ ! $_file_name =~ "." ]]; then
            _new_file_name="${_file_name}_${g_start_time}"
        else
            _new_file_name="${_file_name/\./_${g_start_time}.}"
        fi

        if [ -e "${g_backup_dir}${_new_file_name}" ]; then
            _info "$_file_name has been already backed up. Skipping..."
            return 0
        fi
    fi

    _makeBackupDir
    cp -p ${_file_path} ${g_backup_dir}${_new_file_name} || _critical "$FUNCNAME: failed to backup ${_file_path}"
}
function _makeBackupDir() {
    if [ ! -d "${g_BACKUP_DIR}" ]; then
        mkdir -p -m 700 "${g_BACKUP_DIR}"
        if [ -n "$SUDO_USER" ]; then
            chown $SUDO_UID:$SUDO_GID ${g_BACKUP_DIR}
        fi
    fi
}

function _isYes() {
    # Unlike other languages, 0 is nearly same as True in shell script
    local _answer="$1"
    
    if [ $# -eq 0 ]; then
        _answer="${__LAST_ANSWER}"
    fi

    if [[ "${_answer}" =~ $_YES_REGEX ]]; then
        #_log "$FUNCNAME: \"${_answer}\" matchs."
        return 0
    elif [[ "${_answer}" =~ $_TEST_REGEX ]]; then
        eval "${_answer}" && return 0
    fi
    
    return 1
}
function _trim() {
	local _string="$1"
	echo "${_string}" | sed -e 's/^ *//g' -e 's/ *$//g'
}
function _isCmd() {
    local _cmd="$1"

    if command -v "$_cmd" &>/dev/null ; then
        return 0
    else
        return 1
    fi
}

function _info() {
    # At this moment, not much difference from _echo and _warn, might change later
    local _msg="$1"
    _echo "INFO : ${_msg}" "Y"
}
function _warn() {
    local _msg="$1"
    _echo "WARN : ${_msg}" "Y"
}
function _error() {
    local _msg="$1"
    _echo "ERROR: ${_msg}" "Y"
}
function _critical() {
    local _msg="$1"
    local _exit_code=${2-$__LAST_RC}

    if [ -z "$_exit_code" ]; then _exit_code=1; fi

    _echo "ERROR: ${_msg} (${_exit_code})" "Y" "Y"
    # FIXME: need to test this change
    if $_IS_DRYRUN ; then return ${_exit_code}; fi
    _exit ${_exit_code}
}
function _exit() {
    local _exit_code=$1
    local _exit_code=$1

    # Forcing not to go to next step.
    echo "Please press 'Ctrl-c' to exit."
    tail -f /dev/null

    if $_IS_SCRIPT_RUNNING; then
        exit $_exit_code
    fi
    return $_exit_code
}
function _isValidateFunc() {
    local _function_name="$1"

    # FIXME: not good way
    if [[ "$_function_name" =~ ^_is ]]; then
        typeset -F | grep "^declare -f $_function_name$" &>/dev/null
        return $?
    fi
    return 1
}
function _echo() {
    local _msg="$1"
    local _stderr="$2"
    
    if _isYes "$_stderr" ; then
        echo -e "$_msg" 1>&2
    else 
        echo -e "$_msg"
    fi
}

list() {
    local _name="$1"
    local _width=$(( $(tput cols) - 2 ))

    if [[ -z "$_name" ]]; then
        (for _f in `typeset -F | grep -E '^declare -f [fp]_' | cut -d' ' -f3`; do
            eval "echo \"--[ $_f ]\" | sed -e :a -e 's/^.\{1,${_width}\}$/&-/;ta'"
            help "$_f" "Y"
            echo ""
        done)
    elif [[ "$_name" =~ ^func ]]; then
        typeset -F | grep '^declare -f [fp]_' | cut -d' ' -f3
    elif [[ "$_name" =~ ^glob ]]; then
        set | grep ^[g]_
    elif [[ "$_name" =~ ^resp ]]; then
        set | grep ^[r]_
    fi
}
help() {
    local _function_name="$1"
    local _doc_only="$2"

    if [ -z "$_function_name" ]; then 
        echo "help <function name>"
        echo ""
        list "func"
        echo ""
        return
    fi

    if [[ "$_function_name" =~ ^[fp]_ ]]; then
        local _code="$(type $_function_name 2>/dev/null | grep -v "^${_function_name} is a function")"
        if [ -z "$_code" ]; then
            _echo "Function name '$_function_name' does not exist."
            return 1
        fi

        local _eval="$(echo -e "${_code}" | awk '/__doc__=/,/;/')"
        eval "$_eval"

        if [ -z "$__doc__" ]; then
            echo "No help information in function name '$_function_name'."
        else
            echo -e "$__doc__"
        fi

        if ! _isYes "$_doc_only"; then
            local _params="$(type $_function_name 2>/dev/null | grep -iP '^\s*local _[^_].*?=.*?\$\{?[1-9]' | grep -v awk)"
            if [ -n "$_params" ]; then
                echo ""
                echo "Parameters:"
                echo -e "$_params"
            fi
        
            echo ""
            _ask "Show source code?" "N"
            if _isYes ; then
                echo ""
                echo -e "${_code}" | less
            fi
        fi
    else
        _echo "Unsupported Function name '$_function_name'."
        return 1
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    # parsing command options
    while getopts "r:ish" opts; do
        case $opts in
            i)
                _SETUP_HDP="Y"
                ;;
            s)
                _START_HDP="Y"
                ;;
            r)
                _RESPONSE_FILE_PATH="$OPTARG"
                ;;
            h)
                usage | less
                exit 0
        esac
    done

    if [ "$USER" != "root" ]; then
        echo "Sorry, at this moment, only 'root' user is supported"
        exit
    fi

    _IS_SCRIPT_RUNNING="Y"

    # Testing set -e which might cause unwanted issue
    set -e
    #f_checkUpdate
    p_interview_or_load

    if _isYes "$_SETUP_HDP"; then
        _ask "Would you like to start setup this host?" "Y"
        if ! _isYes; then echo "Bye"; exit; fi

        p_host_setup
    else
        # If no option switch, start HDP services # TODO: can i start without response file?
        p_start_hdp
    fi
fi
