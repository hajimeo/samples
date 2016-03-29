#!/bin/bash
# This script setups docker, then create a container(s), and install ambari-server
#
# Steps:
# 1. Install OS. Recommend Ubuntu 14.x
# 2. sudo -i    (TODO: only root works at this moment)
# 3. (optional) screen
# 4. wget https://raw.githubusercontent.com/hajimeo/samples/master/bash/start_hdp.sh -O ./start_hdp.sh
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
# TODO: tcpdump (not tested), localrepo (not tested)
#

### OS/shell settings
shopt -s nocasematch
#shopt -s nocaseglob
set -o posix
#umask 0000


usage() {
    echo "HELP/USAGE:"
    echo "This script is for setting up this host for HDP or start HDP services.

How to run initial set up:
    ./${g_SCRIPT_NAME} -i [-r=some_file_name.resp]

How to start containers and Ambari and HDP services:
    ./${g_SCRIPT_NAME} -s [-r=some_file_name.resp]

How to run a function:
    ./${g_SCRIPT_NAME} -f some_function_name

    or

    . ./${g_SCRIPT_NAME}
    f_loadResp              # loading your response which is required for many functions
    some_function_name

Available options:
    -i    Initial set up this host for HDP

    -s    Start HDP services (default)

    -r=response_file_path
          To reuse your previously saved response file.

    -f=function_name
          To run particular function (ex: f_log_cleanup in crontab)

    -h    Show this message.
"
    echo "Available functions:"
    list
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
    _ask "Run apt-get upgrade before setting up?" "N" "r_APTGET_UPGRADE" "N"
    _ask "NTP Server" "ntp.ubuntu.com" "r_NTP_SERVER" "N" "Y"
    # TODO: Changing this IP later is troublesome, so need to be careful
    local _docker_ip=`f_docker_ip "172.17.0.1"`
    _ask "IP address for docker0 interface" "$_docker_ip" "r_DOCKER_HOST_IP" "N" "Y"
    _ask "Network Address (xxx.xxx.xxx.) for docker containers" "172.17.100." "r_DOCKER_NETWORK_ADDR" "N" "Y"
    _ask "Domain Suffix for docker containers" ".localdomain" "r_DOMAIN_SUFFIX" "N" "Y"
    _ask "Container OS type (small letters)" "centos" "r_CONTAINER_OS" "N" "Y"
    if [ -n "$r_CONTAINER_OS" ]; then
        r_CONTAINER_OS="`echo "$r_CONTAINER_OS" | tr '[:upper:]' '[:lower:]'`"
    fi
    _ask "Container OS version" "6" "r_CONTAINER_OS_VER" "N" "Y"
    _ask "DockerFile URL or path" "https://raw.githubusercontent.com/hajimeo/samples/master/docker/DockerFile" "r_DOCKERFILE_URL" "N" "N"
    _ask "How many nodes?" "4" "r_NUM_NODES" "N" "Y"
    _ask "Node starting number" "1" "r_NODE_START_NUM" "N" "Y"
    _ask "Hostname for docker host in docker private network?" "dockerhost1" "r_DOCKER_PRIVATE_HOSTNAME" "N" "Y"
    #_ask "Username to mount VM host directory for local repo (optional)" "$SUDO_UID" "r_VMHOST_USERNAME" "N" "N"

    # TODO: Questions to install Ambari
    _ask "Ambari server hostname" "node1$r_DOMAIN_SUFFIX" "r_AMBARI_HOST" "N" "Y"
    _ask "Ambari version (used to build repo URL)" "2.2.1.1" "r_AMBARI_VER" "N" "Y"
    _echo "If you have set up a Local Repo, please change below"
    _ask "Ambari repo" "http://public-repo-1.hortonworks.com/ambari/${r_CONTAINER_OS}${r_CONTAINER_OS_VER}/2.x/updates/${r_AMBARI_VER}/ambari.repo" "r_AMBARI_REPO_FILE" "N" "Y"

    _ask "Would you like to set up local repo for HDP? (may take long time to downlaod)" "N" "r_HDP_LOCAL_REPO"
    if _isYes "$r_HDP_LOCAL_REPO"; then
        _ask "Local repository directory (Apache root)" "/var/www/html" "r_HDP_REPO_DIR"
        _ask "HDP (repo) version" "2.3.4.7" "r_HDP_REPO_VER"
        _ask "URL for HDP repo tar.gz file" "http://public-repo-1.hortonworks.com/HDP/${r_CONTAINER_OS}${r_CONTAINER_OS_VER}/2.x/updates/${r_HDP_REPO_VER}/HDP-${r_HDP_REPO_VER}-${r_CONTAINER_OS}${r_CONTAINER_OS_VER}-rpm.tar.gz" "r_HDP_REPO_TARGZ"
        _ask "URL for UTIL repo tar.gz file" "http://public-repo-1.hortonworks.com/HDP-UTILS-1.1.0.20/repos/${r_CONTAINER_OS}${r_CONTAINER_OS_VER}/HDP-UTILS-1.1.0.20-${r_CONTAINER_OS}${r_CONTAINER_OS_VER}.tar.gz" "r_HDP_REPO_UTIL_TARGZ"
    fi
}

function p_interview_or_load() {
    local __doc__="Asks user to start interview, review interview, or start installing with given response file."

    if [ -z "${_RESPONSE_FILEPATH}" ]; then
        _info "No response file specified, so that using ${g_DEFAULT_RESPONSE_FILEPATH}..."
        _RESPONSE_FILEPATH="$g_DEFAULT_RESPONSE_FILEPATH"
    fi

    if [ -r "${_RESPONSE_FILEPATH}" ]; then
        _ask "Would you like to load ${_RESPONSE_FILEPATH}?" "Y"
        if ! _isYes; then _echo "Bye."; exit 0; fi
        f_loadResp
        _ask "Would you like to review your responses?" "Y"
        # if don't want to review, just load and exit
        if ! _isYes; then
            return 0
        fi
    else
        _info "responses will be saved into ${_RESPONSE_FILEPATH}"
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

function p_hdp_start() {
    f_loadResp
    f_docker0_setup
    f_ntp
    f_docker_start
    sleep 4
    _info "Not setting up the default GW. please use f_gw_set if necessary"
    #f_gw_set
    f_ambari_server_start
    f_ambari_agent_start
    f_etcs_mount
    echo "WARN: Will start all services..."
    f_services_start
    f_screen_cmd
}

function f_saveResp() {
    local __doc__="Save current responses(answers) in memory into a file."
    local _file_path="${1-$_RESPONSE_FILEPATH}"
    
    if [ -z "$_file_path" ]; then
        _ask "Response file path" "$g_DEFAULT_RESPONSE_FILEPATH" "_RESPONSE_FILEPATH"
        _file_path="$_RESPONSE_FILEPATH"
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
    local _file_path="${1-$_RESPONSE_FILEPATH}"
    
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

function _docker_seq() {
    local _how_many="${1-$r_NUM_NODES}"
    local _start_from="${2-$r_NODE_START_NUM}"
    local _output_cmd="$3"

    if [ -z "$_start_from" ]; then
        _start_from=1
    fi

    if [ -z "$_how_many" ]; then
        _how_many=1
    fi

    if [ $_start_from -lt 1 ]; then
        _warn "Starting from number is not specified."
        return 1
    fi

    local _e=`expr $_start_from + $_how_many - 1`
    if [ $_e -lt 1 ]; then
        _warn "Number of nodes (containers) is not specified."
        return 1
    fi

    if _isYes "$_output_cmd"; then
        echo "seq $_start_from $_e"
    else
        seq $_start_from $_e
    fi
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
    local __doc__="Starting some docker containers"
    local _how_many="${1-$r_NUM_NODES}"
    local _start_from="${2-$r_NODE_START_NUM}"

    _info "starting $_how_many docker containers starting from $_start_from ..."
    for _n in `_docker_seq "$_how_many" "$_start_from"`; do
        # docker seems doesn't care if i try to start already started one
        docker start --attach=false node$_n
    done
}

function f_docker_stop() {
    local __doc__="Stopping some docker containers"
    local _how_many="${1-$r_NUM_NODES}"
    local _start_from="${2-$r_NODE_START_NUM}"

    _info "stopping $_how_many docker containers starting from $_start_from ..."
    for _n in `_docker_seq "$_how_many" "$_start_from"`; do
        docker stop node$_n
    done
}

function f_docker_rm() {
    local _force="$1"
    local __doc__="Removing *all* docker containers"
    _ask "Are you sure to delete ALL containers?"
    if _isYes; then
        if _isYes $_force; then
            for _q in `docker ps -aq`; do docker rm --force ${_q} & done
        else
            for _q in `docker ps -aq`; do docker rm ${_q} & done
        fi
        wait
    fi
}

function f_docker_run() {
    local __doc__="Running (creating) docker containers"
    local _how_many="${1-$r_NUM_NODES}"
    local _start_from="${2-$r_NODE_START_NUM}"

    local _ip="`f_docker_ip`"

    if [ -z "$_ip" ]; then
        _warn "No Docker interface IP"
        return 1
    fi

    local _id=""
    for _n in `_docker_seq "$_how_many" "$_start_from"`; do
        _id="`docker ps -qa -f name=node$_n`"
        if [ -n "$_id" ]; then
            _warn "node$_n already exists. Skipping..."
            continue
        fi
        docker run -t -i -d --dns $_ip --name node$_n --privileged ${g_DOCKER_BASE} /startup.sh ${r_DOCKER_NETWORK_ADDR}$_n node$_n${r_DOMAIN_SUFFIX} $_ip
    done
}

function f_ambari_server_install() {
    local __doc__="Install Ambari Server to $r_AMBARI_HOST"
    if [ -z "$r_AMBARI_REPO_FILE" ]; then
        _error "Please specify Ambari repo *file* URL"
        return 1
    fi

    # TODO: at this moment, only Centos (yum)
    wget -nv "$r_AMBARI_REPO_FILE" -O /tmp/ambari.repo || retuen 1
    scp /tmp/ambari.repo root@$r_AMBARI_HOST:/etc/yum.repos.d/
    ssh root@$r_AMBARI_HOST "yum install ambari-server -y && ambari-server setup -s"
}

function f_ambari_server_start() {
    local __doc__="Starting ambari-server on $r_AMBARI_HOST"
    ssh root@$r_AMBARI_HOST "ambari-server start --silent"
    if [ $? -ne 0 ]; then
        # TODO: lazy retry
        sleep 5
        ssh root@$r_AMBARI_HOST "ambari-server start --silent"
    fi
}

function f_ambari_agent_install() {
    local __doc__="TODO: Installing ambari-agent on all containers"
    local _how_many="${1-$r_NUM_NODES}"
    local _start_from="${2-$r_NODE_START_NUM}"

    if [ ! -e /tmp/ambari.repo ]; then
        scp root@$r_AMBARI_HOST:/etc/yum.repos.d/ambari.repo /tmp/ambari.repo
    fi

    local _cmd="yum install ambari-agent -y && grep "^hostname=$r_AMBARI_HOST"/etc/ambari-agent/conf/ambari-agent.ini || sed -i.bak "s@hostname=.+$@hostname=$r_AMBARI_HOST@1" /etc/ambari-agent/conf/ambari-agent.ini"

    for i in `_docker_seq "$_how_many" "$_start_from"`; do
        scp /tmp/ambari.repo root@$node$i${r_DOMAIN_SUFFIX}:/etc/yum.repos.d/
        # Executing yum command one by one (not parallel)
        ssh root@node$i${r_DOMAIN_SUFFIX} "$_cmd"
    done
}

function f_ambari_agent_start() {
    local __doc__="Starting ambari-agent on some containers"
    local _how_many="${1-$r_NUM_NODES}"
    local _start_from="${2-$r_NODE_START_NUM}"

    for i in `_docker_seq "$_how_many" "$_start_from"`; do
        ssh root@node$i${r_DOMAIN_SUFFIX} 'ambari-agent start'
        if [ $? -ne 0 ]; then
            # TODO: lazy retry
            sleep 5
            ssh root@node$i${r_DOMAIN_SUFFIX} 'ambari-agent start'
        fi
    done
}

function f_etcs_mount() {
    local __doc__="Mounting all agent's etc directories (handy for troubleshooting)"
    local _remount="$1"
    local _how_many="${2-$r_NUM_NODES}"
    local _start_from="${3-$r_NODE_START_NUM}"

    for i in `_docker_seq "$_how_many" "$_start_from"`; do
        if [ ! -d /mnt/etc/node$i ]; then
            mkdir -p /mnt/etc/node$i
        fi

        if _isNotEmptyDir "/mnt/etc/node$i" ;then
            if ! _isYes "$_remount"; then
                continue
            else
                umount -f /mnt/etc/node$i
            fi
        fi

        sshfs -o allow_other,uid=0,gid=0,umask=002,reconnect,follow_symlinks node${i}${r_DOMAIN_SUFFIX}:/etc /mnt/etc/node${i}
    done
}

function f_local_repo() {
    local __doc__="Setup local repo on Docker host (Ubuntu)"
    local _local_dir="$1"
    local _force_extract=""
    local _download_only=""

    apt-get install -y apache2 createrepo

    if [ -z "$r_HDP_REPO_TARGZ" ]; then
        _error "Please specify HDP repo *tar.gz* file URL"
        return 1
    fi

    if [ -z "$_local_dir" ]; then
        if [ -z "$r_HDP_REPO_DIR" ]; then
            _warn "HDP local repository dirctory is not specified. Using /var/www/html/hdp"
            _local_dir="/var/www/html/hdp"
        else
            _local_dir="$r_HDP_REPO_DIR"
        fi
    fi

    set -v
    if [ ! -d "$_local_dir" ]; then
        # Making directory for Apache2
        mkdir -p -m 777 $_local_dir
    fi

    cd "$_local_dir" || return 1

    local _tar_gz_file="`basename "$r_HDP_REPO_TARGZ"`"
    local _has_extracted=""
    local _hdp_dir="`find . -type d | grep -m1 -E "/${r_CONTAINER_OS}${r_CONTAINER_OS_VER}/.+?/${r_HDP_REPO_VER}$"`"

    if _isNotEmptyDir "$_hdp_dir"; then
        if ! _isYes "$_force_extract"; then
            _has_extracted="Y"
        fi
        _info "$_hdp_dir already exists and not empty. Skipping download."
    elif [ -e "$_tar_gz_file" ]; then
        _info "$_tar_gz_file already exists. Skipping download."
    else
        #curl --limit-rate 200K --retry 20 -C - "$r_HDP_REPO_TARGZ" -o $_tar_gz_file
        wget -c -t 20 --timeout=60 --waitretry=60 "$r_HDP_REPO_TARGZ"
    fi

    if _isYes "$_download_only"; then
        return $?
    fi

    if ! _isYes "$_has_extracted"; then
        tar xzvf "$_tar_gz_file"
        _hdp_dir="`find . -type d | grep -m1 -E "/${r_CONTAINER_OS}${r_CONTAINER_OS_VER}/.+?/${r_HDP_REPO_VER}$"`"
        createrepo "$_hdp_dir"
    fi

    local _util_tar_gz_file="`basename "$r_HDP_REPO_UTIL_TARGZ"`"
    local _util_has_extracted=""
    # TODO: not accurate
    local _hdp_util_dir="`find . -type d | grep -m1 -E "/HDP-UTILS-.+?/${r_CONTAINER_OS}${r_CONTAINER_OS_VER}$"`"

    if _isNotEmptyDir "$_hdp_util_dir"; then
        if ! _isYes "$_force_extract"; then
            _util_has_extracted="Y"
        fi
        _info "$_hdp_util_dir already exists and not empty. Skipping download."
    elif [ -e "$_util_tar_gz_file" ]; then
        _info "$_util_tar_gz_file already exists. Skipping download."
    else
        wget -c -t 20 --timeout=60 --waitretry=60 "$r_HDP_REPO_UTIL_TARGZ"
    fi

    if ! _isYes "$_util_has_extracted"; then
        tar xzvf "$_util_tar_gz_file"
        _hdp_util_dir="`find . -type d | grep -m1 -E "/HDP-UTILS-.+?/${r_CONTAINER_OS}${r_CONTAINER_OS_VER}$"`"
        createrepo "$_hdp_util_dir"
    fi

    set +v
    service apache2 start
    cd - &>/dev/null

    if [ -n "$r_DOCKER_PRIVATE_HOSTNAME" ]; then
        local _repo_path="${_hdp_dir#\.}"
        echo "### Local Repo URL: http://${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}${_repo_path}"
        local _util_repo_path="${_hdp_util_dir#\.}"
        echo "### Local Repo URL: http://${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}${_util_repo_path}"

        # TODO: this part is best effort...
        if [ "${r_CONTAINER_OS}" = "centos" ] || [ "${r_CONTAINER_OS_VER}" = "redhat" ]; then
            for i in `seq 1 10`; do
              nc -z $r_AMBARI_HOST 8080 && break
              _info "Ambari server is not listening on $r_AMBARI_HOST:8080 Waiting..."
              sleep 5
            done

            nc -z $r_AMBARI_HOST 8080
            if [ $? -eq 0 ]; then
                curl -H "X-Requested-By: ambari" -X PUT -u admin:admin "http://${r_AMBARI_HOST}:8080/api/v1/stacks/HDP/versions/2.3/operating_systems/redhat${r_CONTAINER_OS_VER}/repositories/HDP-2.3" -d '{"Repositories":{"base_url":"'http://${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}${_repo_path}'","verify_base_url":true}}'

                local _hdp_util_name="`echo $_util_repo_path | grep -oP 'HDP-UTILS-[\d\.]+'`"
                curl -H "X-Requested-By: ambari" -X PUT -u admin:admin "http://${r_AMBARI_HOST}:8080/api/v1/stacks/HDP/versions/2.3/operating_systems/redhat${r_CONTAINER_OS_VER}/repositories/${_hdp_util_name}" -d '{"Repositories":{"base_url":"'http://${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}${_util_repo_path}'","verify_base_url":true}}'
            fi
        fi
    fi
}

function f_repo_mount() {
    local __doc__="TODO: This would work on only my environment. Mounting VM host's directory to use for local repo"
    local _user="$1"
    local _host_pc="$2"
    local _src="${3-/Users/${_user}/Public/hdp/}"  # needs ending slash
    local _mounting_dir="${4-/var/www/html/hdp}" # no need ending slash

    if [ -z "$_host_pc" ]; then
        _host_pc="`env | awk '/SSH_CONNECTION/ {gsub("SSH_CONNECTION=", "", $1); print $1}'`"
        if [ -z "$_host_pc" ]; then
            _host_pc="`netstat -rn | awk '/^0\.0\.0\.0/ {print $2}'`"
        fi

        local _src="/Users/${_user}/Public/hdp/"
        _connect_str="${_user}@${_host_pc}:${_src}"
    fi

    if [ -z "${_user}" ]; then
        if [ -n "$SUDO_USER" ]; then
            _user="$SUDO_USER"
        else
            _user="$USER"
        fi
    fi

    mount | grep "$_mounting_dir"
    if [ $? -eq 0 ]; then
      umount -f "$_mounting_dir"
    fi
    if [ ! -d "$_mounting_dir" ]; then
        mkdir "$_mounting_dir" || return
    fi

    _info "Mounting ${_user}@${_host_pc}:${_src} to $_mounting_dir ..."
    _info "TODO: Edit this function for your env if above is not good (and Ctrl+c now)"
    sleep 4
    sshfs -o allow_other,uid=0,gid=0,umask=002,reconnect,follow_symlinks ${_user}@${_host_pc}:${_src} "${_mounting_dir%/}"
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
      _info "You may want to run the following commands to start GNU Screen:"
      echo "screen -S \"docker\" bash -c 'for s in \``_docker_seq "$r_NUM_NODES" "$r_NODE_START_NUM" "Y"`\`; do screen -t \"node\${s}\" \"ssh\" \"node\${s}${r_DOMAIN_SUFFIX}\"; done'"
    fi
}

function p_host_setup() {
    local __doc__="Install packages into this host (Ubuntu)"
    local _docer0="${1-$r_DOCKER_HOST_IP}"

    # TODO: Testing set -e which might cause unwanted issue
    set -e
    set -v
    if _isYes "$r_APTGET_UPGRADE"; then
        apt-get update && apt-get upgrade -y
    fi

    apt-key adv --keyserver hkp://pgp.mit.edu:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D || _info "Did not add key"
    grep "deb https://apt.dockerproject.org/repo" /etc/apt/sources.list.d/docker.list || echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" >> /etc/apt/sources.list.d/docker.list
    apt-get update && apt-get purge lxc-docker*; apt-get install docker-engine -y

    apt-get -y install wget sshfs htop dstat iotop sysv-rc-conf postgresql-client mysql-client tcpdump sharutils
    #krb5-kdc krb5-admin-server mailutils postfix

    # To use tcpdump from container
    if [ ! -L /etc/apparmor.d/disable/usr.sbin.tcpdump ]; then
        ln -sf /etc/apparmor.d/usr.sbin.tcpdump /etc/apparmor.d/disable/
        apparmor_parser -R /etc/apparmor.d/usr.sbin.tcpdump
    fi

    f_dnsmasq

    f_host_performance

    f_docker0_setup "$_docer0"

    f_dockerfile
    f_docker_base_create

    f_docker_run

    f_ambari_server_install
    set +e

    sleep 3
    f_ambari_server_start
    sleep 3

    if _isYes "$r_HDP_LOCAL_REPO"; then
        f_local_repo
    fi
    set +v
    f_screen_cmd
}

function f_dnsmasq() {
    local __doc__="Install and set up dnsmasq"
    apt-get -y install dnsmasq

    grep '^addn-hosts=' /etc/dnsmasq.conf || echo 'addn-hosts=/etc/banner_add_hosts' >> /etc/dnsmasq.conf

    # TODO: the first IP can be wrong one
    _docer0="`f_docker_ip`"

    if [ -z "$r_DOCKER_PRIVATE_HOSTNAME" ]; then
        _warn="Hostname for docker host in the private network is empty. using dockerhost1"
        r_DOCKER_PRIVATE_HOSTNAME="dockerhost1"
    fi

    echo "$_docer0     ${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX} ${r_DOCKER_PRIVATE_HOSTNAME}" > /etc/banner_add_hosts
    for i in `seq 1 99`; do
        echo "${r_DOCKER_NETWORK_ADDR}${i}    node${i}${r_DOMAIN_SUFFIX} node${i}" >> /etc/banner_add_hosts
    done
    service dnsmasq restart
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
    local _url="$1"
    if [ -z "$_url" ]; then
        _url="$r_DOCKERFILE_URL"
    fi
    if [ -z "$_url" ]; then
        _error "No DockerFile URL to download"
        return 1
    fi

    if [ -e ./DockerFile ]; then
        _backup "./DockerFile" && rm -f ./DockerFile
    fi

    if [ -e "$_url" ]; then
        _info "$_url is a local file path"
        cat "$_url" > ./DockerFile
    else
        wget "$_url" -O ./DockerFile
    fi

    f_ssh_setup

    local _pkey="`sed ':a;N;$!ba;s/\n/\\\\\\\n/g' $HOME/.ssh/id_rsa`"

    sed -i "s@_REPLACE_WITH_YOUR_PRIVATE_KEY_@${_pkey}@1" ./DockerFile
    if [ -n "$r_CONTAINER_OS" ]; then
        sed -i "s@centos:6@${r_CONTAINER_OS}:${r_CONTAINER_OS_VER}@1" ./DockerFile
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

function f_apache_proxy() {
    local _proxy_dir="/var/www/proxy"
    local _cache_dir="/var/cache/apache2/mod_cache_disk"
    local _port="28080"

    apt-get install -y apache2 apache2-utils
    a2enmod proxy proxy_http proxy_connect cache cache_disk
    mkdir -m 777 $_proxy_dir || _info "${_proxy_dir} already exists"
    mkdir -p -m 777 ${_cache_dir} || _info "mod_cache_disk already exists"

    grep -i "^Listen ${_port}" /etc/apache2/ports.conf || echo "Listen ${_port}" >> /etc/apache2/ports.conf

    if [ -s /etc/apache2/sites-available/proxy.conf ]; then
        _warn "/etc/apache2/sites-available/proxy.conf already exists. Skipping..."
        return 0
    fi

    echo "<VirtualHost *:${_port}>
    DocumentRoot ${_proxy_dir}
    LogLevel warn
    ErrorLog \${APACHE_LOG_DIR}/proxy_error.log
    CustomLog \${APACHE_LOG_DIR}/proxy_access.log combined

    <IfModule mod_proxy.c>

        ProxyRequests On
        <Proxy *>
            AddDefaultCharset off
            Order deny,allow
            Deny from all
            Allow from ${r_DOCKER_NETWORK_ADDR%.}
        </Proxy>

        ProxyVia On

        <IfModule mod_cache_disk.c>
            CacheRoot ${_cache_dir}
            CacheIgnoreCacheControl On
            CacheEnable disk /
            CacheEnable disk http://
            CacheDirLevels 2
            CacheDirLength 1
        </IfModule>

    </IfModule>
</VirtualHost>" > /etc/apache2/sites-available/proxy.conf

    a2ensite proxy
    # TODO: should use restart?
    service apache2 reload
}

function f_yum_remote_proxy() {
    local __doc__="This function edits yum.conf of each running container to set up proxy (http://your.proxy.server:port)"
    local _proxy="$1"

    if [ -z "$_proxy" ]; then
        _error "No proxy (http://your.proxy.server:port) to set"
        return 1
    fi

    # TODO: set up proxy with Apache2
    for _host in `docker ps --format "{{.Names}}"`; do
        ssh root@$_host "grep ^proxy /etc/yum.conf || echo \"proxy=${_proxy}\" >> /etc/yum.conf"
    done
}

function f_gw_set() {
    local __doc__="Set new default gateway to each container"
    local _gw="`f_docker_ip`"
    # NOTE: Assuming docker name and hostname is same
    for _name in `docker ps --format "{{.Names}}"`; do
        ssh root@${_name}${r_DOMAIN_SUFFIX} "route add default gw $_gw eth0"
    done
}

function f_docker_ip() {
    local __doc__="Output docker0 IP or specified NIC's IP"
    local _ip="${1}"
    local _if="${2-docker0}"
    local _ifconfig="`ifconfig $_if 2>/dev/null`"

    if [ -z "$_ifconfig" ]; then
        if [ -n "$_ip" ]; then
            echo "$_ip"
            return 0
        fi
        return $?
    fi

    echo "$_ifconfig" | grep -oP 'inet addr:\d+\.\d+\.\d+\.\d' | cut -d":" -f2
    return $?
}

function f_log_cleanup() {
    local __doc__="Deleting log files which group owner is hadoop"
    local _days="${1-7}"
    echo "Deleting hadoop logs which is older than $_days..."
    # NOTE: Assuming docker name and hostname is same
    for _name in `docker ps --format "{{.Names}}"`; do
        ssh root@${_name}${r_DOMAIN_SUFFIX} 'find /var/log/ -type f -group hadoop -mtime +'${_days}' -exec grep -Iq . {} \; -and -print0 | xargs -0 -n1 -I {} rm -f {}'
    done
}

function f_checkUpdate() {
    local __doc__="Check if newer script is available, then download."
    local _local_file_path="${1-$BASH_SOURCE}"
    local _file_name=`basename ${_local_file_path}`
    local _remote_url="https://raw.githubusercontent.com/hajimeo/samples/master/bash/$_file_name"   # TODO: shouldn't I hard-code?

    if [ ! -s "$_local_file_path" ]; then
        _warn "$FUNCNAME: $_local_file_path does not exist or empty"
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

    # --basic --user ${r_svn_user}:${r_svn_pass}      last-modified    cut -c16-
    local _remote_length=`curl -m 4 -s -k -L --head "${_remote_url}" | grep -i '^Content-Length:' | awk '{print $2}' | tr -d '\r'`
    if [ -z "$_remote_length" ]; then _warn "$FUNCNAME: Unknown remote length."; return 1; fi

    #local _local_last_mod_ts=`stat -c%Y ${_local_file_path}`
    _local_last_length=`wc -c ./start_hdp.sh | awk '{print $1}'`

    if [ ${_remote_length} -ne ${_local_last_length} ]; then
        _info "Different file is available (r=$_remote_length/l=$_local_last_length)"
        _ask "Would you like to download?" "Y"
        if ! _isYes; then return 0; fi
        if [ ${_remote_length} -lt ${_local_last_length} ]; then
            _ask "Are you sure?" "N"
            if ! _isYes; then return 0; fi
        fi

        _backup "${_local_file_path}"

        curl -k -L "$_remote_url" -o ${_local_file_path} || _critical "$FUNCNAME: Update failed."

        _info "Validating the downloaded script..."
        source ${_local_file_path} || _critical "Please contact the script author."
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
    local _force="$2"
    local _file_name="`basename $_file_path`"
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
function _isNotEmptyDir() {
	local _dir_path="$1"

    # If path is empty, treat as eampty
	if [ -z "$_dir_path" ]; then return 1; fi

    # If path is not directory, treat as eampty
	if [ ! -d "$_dir_path" ]; then return 1; fi

	if [ "$(ls -A ${_dir_path})" ]; then
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
    #local _width=$(( $(tput cols) - 2 ))
    local _tmp_txt=""

    if [[ -z "$_name" ]]; then
        (for _f in `typeset -F | grep -E '^declare -f [fp]_' | cut -d' ' -f3`; do
            #eval "echo \"--[ $_f ]\" | sed -e :a -e 's/^.\{1,${_width}\}$/&-/;ta'"
            _tmp_txt="`help "$_f" "Y"`"
            printf "%-28s%s\n" "$_f" "$_tmp_txt"
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
    while getopts "r:f:ish" opts; do
        case $opts in
            i)
                _SETUP_HDP="Y"
                ;;
            s)
                _START_HDP="Y"
                ;;
            r)
                _RESPONSE_FILEPATH="$OPTARG"
                ;;
            f)
                _FUNCTION_NAME="$OPTARG"
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

    _IS_SCRIPT_RUNNING=true

    f_checkUpdate

    if _isYes "$_SETUP_HDP"; then
        p_interview_or_load
        _ask "Would you like to start setup this host?" "Y"
        if ! _isYes; then echo "Bye"; exit; fi

        g_START_TIME="`date -u`"
        p_host_setup
        g_END_TIME="`date -u`"
        echo "Started at : $g_START_TIME"
        echo "Finished at: $g_END_TIME"
    elif [ -n "$_FUNCTION_NAME" ]; then
        if [[ "$_FUNCTION_NAME" =~ ^[fph]_ ]]; then
            type $_FUNCTION_NAME 2>/dev/null | grep " is a function" &>/dev/null
            if [ $? -eq 0 ]; then
                f_loadResp
                $_FUNCTION_NAME
            fi
        fi
    elif _isYes "$_START_HDP"; then
        f_loadResp
        p_hdp_start
    else
        usage | less
        exit 0
    fi
else
    _info "You may want to run 'f_loadResp' to load your response file"
fi
