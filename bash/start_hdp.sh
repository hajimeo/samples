#!/bin/bash
# This script setups docker, then create a container(s), and install ambari-server
#
# Steps:
# 1. Install OS. Recommend Ubuntu 14.x
# 2. sudo -i    (TODO: only root works at this moment)
# 3. (optional) screen
# 4. wget https://raw.githubusercontent.com/hajimeo/samples/master/bash/start_hdp.sh -O ./start_hdp.sh
# 5. chmod u+x ./start_hdp.sh
# 6. ./start_hdp.sh -i    or './start_hdp.sh -a' for full automated installation
# 7. answer questions
#
# Once setup, just run './start_hdp.sh -s' to start service if server is rebooted
#
# Rules:
# 1. Function name needs to start with f_ or p_
# 2. Function arguments need to use local and start with _
# 3. Variable name which stores user response needs to start with r_
# 4. (optional) __doc__ local variable is for function usage/help
#
# @author hajime
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

    or, Auto setup with default response answers

    ./${g_SCRIPT_NAME} -a

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
g_LATEST_RESPONSE_URL="https://raw.githubusercontent.com/hajimeo/samples/master/misc/latest_hdp.resp"
g_BACKUP_DIR="$HOME/.build_script/"
g_DOCKER_BASE="hdp/base"
g_UNAME_STR="`uname`"
g_DEFAULT_PASSWORD="hadoop"
__PID="$$"
__LAST_ANSWER=""

### Procedure type functions

function p_interview() {
    local __doc__="Asks user questions."
    local _centos_version="6.7"
    local _ambari_version="2.4.1.0"
    local _stack_version="2.4"
    local _stack_version_full="HDP-$_stack_version"
    local _hdp_version="2.4.2.0"
    local _hdp_repo_url=""

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
    _ask "Container OS version" "$_centos_version" "r_CONTAINER_OS_VER" "N" "Y"
    r_REPO_OS_VER="${r_CONTAINER_OS_VER%%.*}"
    _ask "DockerFile URL or path" "https://raw.githubusercontent.com/hajimeo/samples/master/docker/DockerFile" "r_DOCKERFILE_URL" "N" "N"
    _ask "How many nodes?" "4" "r_NUM_NODES" "N" "Y"
    _ask "Node starting number" "1" "r_NODE_START_NUM" "N" "Y"
    _ask "Hostname for docker host in docker private network?" "dockerhost1" "r_DOCKER_PRIVATE_HOSTNAME" "N" "Y"
    #_ask "Username to mount VM host directory for local repo (optional)" "$SUDO_UID" "r_VMHOST_USERNAME" "N" "N"

    # Questions to install Ambari
    _ask "Ambari server hostname" "node${r_NODE_START_NUM}${r_DOMAIN_SUFFIX}" "r_AMBARI_HOST" "N" "Y"
    _ask "Ambari version (used to build repo URL)" "$_ambari_version" "r_AMBARI_VER" "N" "Y"
    _echo "If you have set up a Local Repo, please change below"
    _ask "Ambari repo file URL or path" "http://public-repo-1.hortonworks.com/ambari/${r_CONTAINER_OS}${r_REPO_OS_VER}/2.x/updates/${r_AMBARI_VER}/ambari.repo" "r_AMBARI_REPO_FILE" "N" "Y"

    wget -q -t 1 http://public-repo-1.hortonworks.com/HDP/hdp_urlinfo.json -O /tmp/hdp_urlinfo.json
    if [ -s /tmp/hdp_urlinfo.json ]; then
        _stack_version_full="`cat /tmp/hdp_urlinfo.json | python -c "import sys,json,pprint;a=json.loads(sys.stdin.read());ks=a.keys();ks.sort();print ks[-1]"`"
        _stack_version="`echo $_stack_version_full | cut -d'-' -f2`"
        _hdp_repo_url="`cat /tmp/hdp_urlinfo.json | python -c 'import sys,json,pprint;a=json.loads(sys.stdin.read());print a["'${_stack_version_full}'"]["latest"]["'${r_CONTAINER_OS}${r_REPO_OS_VER}'"]'`"
        _hdp_version="`basename ${_hdp_repo_url%/}`"
    fi

    _ask "Would you like to use Ambari Blueprint?" "Y" "r_AMBARI_BLUEPRINT"
    if _isYes "$r_AMBARI_BLUEPRINT"; then
        _ask "Cluster name" "c${r_NODE_START_NUM}" "r_CLUSTER_NAME" "N" "Y"
        _ask "Default password" "$g_DEFAULT_PASSWORD" "r_DEFAULT_PASSWORD" "N" "Y"
        _ask "Stack Version" "$_stack_version" "r_HDP_STACK_VERSION" "N" "Y"
        _ask "HDP Version for repository" "$_hdp_version" "r_HDP_REPO_VER" "N" "Y"
        r_HDP_REPO_URL="$_hdp_repo_url"
        if [ -z "$r_HDP_REPO_URL" ]; then
            _ask "HDP Repo URL" "http://public-repo-1.hortonworks.com/HDP/${r_CONTAINER_OS}${r_REPO_OS_VER}/2.x/updates/${r_HDP_REPO_VER}/" "r_HDP_REPO_URL" "N" "Y"
        fi
        _ask "Host mapping json path (optional)" "" "r_AMBARI_BLUEPRINT_HOSTMAPPING_PATH"
        _ask "Cluster config json path (optional)" "" "r_AMBARI_BLUEPRINT_CLUSTERCONFIG_PATH"
    fi

    _ask "Would you like to set up a local repo for HDP? (may take long time to downlaod)" "N" "r_HDP_LOCAL_REPO"
    if _isYes "$r_HDP_LOCAL_REPO"; then
        _ask "Local repository directory (Apache root)" "/var/www/html/hdp" "r_HDP_REPO_DIR"
        _ask "Stack Version" "$_stack_version" "r_HDP_STACK_VERSION"
        _stack_version_full="HDP-${_stack_version}"
        _ask "HDP Version for repository" "$_hdp_version" "r_HDP_REPO_VER" "N" "Y"
        _ask "URL for HDP repo tar.gz file" "http://public-repo-1.hortonworks.com/HDP/${r_CONTAINER_OS}${r_REPO_OS_VER}/2.x/updates/${r_HDP_REPO_VER}/HDP-${r_HDP_REPO_VER}-${r_CONTAINER_OS}${r_REPO_OS_VER}-rpm.tar.gz" "r_HDP_REPO_TARGZ"
        _ask "URL for UTIL repo tar.gz file" "http://public-repo-1.hortonworks.com/HDP-UTILS-1.1.0.20/repos/${r_CONTAINER_OS}${r_REPO_OS_VER}/HDP-UTILS-1.1.0.20-${r_CONTAINER_OS}${r_REPO_OS_VER}.tar.gz" "r_HDP_REPO_UTIL_TARGZ"
    fi

    #_ask "Would you like to increase Ambari Alert interval?" "Y" "r_AMBARI_ALERT_INTERVAL"

    _ask "Would you like to set up a proxy server for yum on this server?" "Y" "r_PROXY"
    if _isYes "$r_PROXY"; then
        _ask "Proxy port" "28080" "r_PROXY_PORT"
    fi
}

function p_interview_or_load() {
    local __doc__="Asks user to start interview, review interview, or start installing with given response file."

    if [ -z "${_RESPONSE_FILEPATH}" ]; then
        _info "No response file specified, so that using ${g_DEFAULT_RESPONSE_FILEPATH}..."
        _RESPONSE_FILEPATH="$g_DEFAULT_RESPONSE_FILEPATH"
    fi

    if _isUrl "${_RESPONSE_FILEPATH}"; then
        if [ -s "$g_DEFAULT_RESPONSE_FILEPATH" ]; then
            local _new_resp_filepath="./`basename $_RESPONSE_FILEPATH`"
        else
            local _new_resp_filepath="$g_DEFAULT_RESPONSE_FILEPATH"
        fi
        wget -nv "${_RESPONSE_FILEPATH}" -O ${_new_resp_filepath}
        _RESPONSE_FILEPATH="${_new_resp_filepath}"
    fi

    if [ -r "${_RESPONSE_FILEPATH}" ]; then
        if ! _isYes "$_AUTO_SETUP_HDP"; then
            _ask "Would you like to load ${_RESPONSE_FILEPATH}?" "Y"
            if ! _isYes; then _echo "Bye."; exit 0; fi
        fi

        f_loadResp

        # if auto setup, just load and exit
        if _isYes "$_AUTO_SETUP_HDP"; then
            return 0
        fi

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
    f_docker_stop_other
    f_docker_start
    sleep 4
    _info "NOT setting up the default GW. please use f_gw_set if necessary"
    #f_gw_set
    f_log_cleanup
    #f_etcs_mount

    f_ambari_server_start
    f_ambari_agent_fix_public_hostname
    # not interested in agent restart output
    f_ambari_agent "restart" > /dev/null

    #f_ambari_update_config
    _info "Will start all services ..."
    f_services_start
    f_screen_cmd
}

function p_ambari_blueprint() {
    local __doc__="Build cluster with Ambari Blueprint"
    local _hostmap_json="/tmp/${r_CLUSTER_NAME}_hostmap.json"
    local _cluster_config_json="/tmp/${r_CLUSTER_NAME}_cluster_config.json"

    # just in case, try starting server
    f_ambari_server_start
    _port_wait "$r_AMBARI_HOST" "8080"
    #f_ambari_agent "stop"
    f_ambari_agent_install
    f_ambari_agent_fix_public_hostname
    f_ambari_agent "start"
    _ambari_agent_wait

    if [ ! -z "$r_AMBARI_BLUEPRINT_HOSTMAPPING_PATH" ]; then
        _hostmap_json="$r_AMBARI_BLUEPRINT_HOSTMAPPING_PATH"
        if [ ! -s "$_hostmap_json" ]; then
            _warn "$_hostmap_json does not exist or empty file. Will regenerate automatically..."
            f_ambari_blueprint_hostmap > $_hostmap_json
        fi
    else
        f_ambari_blueprint_hostmap > $_hostmap_json
    fi

    if [ ! -z "$r_AMBARI_BLUEPRINT_CLUSTERCONFIG_PATH" ]; then
        _cluster_config_json="$r_AMBARI_BLUEPRINT_CLUSTERCONFIG_PATH"
        if [ ! -s "$_cluster_config_json" ]; then
            _warn "$_cluster_config_json does not exist or empty file. Will regenerate automatically..."
            f_ambari_blueprint_cluster_config > $_cluster_config_json
        fi
    else
        f_ambari_blueprint_cluster_config > $_cluster_config_json
    fi

    curl -H "X-Requested-By: ambari" -X POST -u admin:admin "http://$r_AMBARI_HOST:8080/api/v1/blueprints/$r_CLUSTER_NAME" -d @${_cluster_config_json}
    curl -H "X-Requested-By: ambari" -X POST -u admin:admin "http://$r_AMBARI_HOST:8080/api/v1/clusters/$r_CLUSTER_NAME" -d @${_hostmap_json}
}

function f_ambari_blueprint_hostmap() {
    local __doc__="Output json string for Ambari Blueprint Host mapping"
    #local _cluster_name="${1-$r_CLUSTER_NAME}"
    local _default_password="${1-$r_DEFAULT_PASSWORD}"
    local _is_kerberos_on="$2"
    local _how_many="${3-$r_NUM_NODES}"
    local _start_from="${4-$r_NODE_START_NUM}"
    local _domain_suffix="${5-$r_DOMAIN_SUFFIX}"

    local _host_loop=""
    local _num=1
    for i in `_docker_seq "$_how_many" "$_start_from"`; do
        _host_loop="${_host_loop}
    {
      \"name\" : \"host_group_$_num\",
      \"hosts\" : [
        {
          \"fqdn\" : \"node$i${_domain_suffix}\"
        }
      ]
    },"
    _num=$((_num+1))
    done
    _host_loop="${_host_loop%,}"

    # TODO: Kerboers https://cwiki.apache.org/confluence/display/AMBARI/Blueprints#Blueprints-BlueprintExample:ProvisioningMulti-NodeHDP2.3ClustertouseKERBEROS
    local _kerberos_config=''
    if _isYes "$_is_kerberos_on"; then
        _kerberos_config=',
  "credentials" : [
    {
      "alias" : "kdc.admin.credential",
      "principal" : "admin/admin",
      "key" : "'$_default_password'",
      "type" : "TEMPORARY"
    }
  ],
  "security" : {
     "type" : "KERBEROS"
  }
'
    fi

    echo "{
  \"blueprint\" : \"multinode-hdp\",
  \"default_password\" : \"$_default_password\",
  \"host_groups\" :["
    echo "$_host_loop"
    echo "  ]${_kerberos_config}
}"
    # NOTE: It seems blueprint works without "Clusters"
    #  , \"Clusters\" : {\"cluster_name\":\"${_cluster_name}\"}
}

function f_ambari_blueprint_cluster_config() {
    local __doc__="Output json string for Ambari Blueprint Cluster mapping TODO: it's fixed map at this moment"
    local _stack_version="${1-$r_HDP_STACK_VERSION}"
    local _is_kerberos_on="$2"
    local _how_many="${3-$r_NUM_NODES}"

    if [ -z "$_how_many" ] || [ 4 -gt "$_how_many" ]; then
        _error "At this moment, Blueprint build needs at least 4 nodes"
        return 1
    fi

    # TODO: Realm is hardcoded (and kdc_host)
    local _kerberos_client=""
    local _security="";
    local _kerberos_config=""
    if _isYes "$_is_kerberos_on"; then
        _kerberos_client=',
        {
          "name" : "KERBEROS_CLIENT"
        }
'
        _security=',
    "security" : {"type" : "KERBEROS"}
'
        _kerberos_config=',
    {
      "kerberos-env": {
        "properties_attributes" : { },
        "properties" : {
          "realm" : "EXAMPLE.COM",
          "kdc_type" : "mit-kdc",
          "kdc_host" : "'$r_AMBARI_HOST'",
          "admin_server_host" : "'$r_AMBARI_HOST'"
        }
      }
    },
    {
      "krb5-conf": {
        "properties_attributes" : { },
        "properties" : {
          "domains" : "EXAMPLE.COM",
          "manage_krb5_conf" : "true"
        }
      }
    }
'
    fi


    echo '{
  "configurations" : [
    {
      "hdfs-site" : {
        "properties" : {
          "dfs.replication" : "1",
          "dfs.datanode.du.reserved" : "536870912"
        }
      }
    }
  ],
  "host_groups": [
    {
      "name" : "host_group_1",
      "components" : [
        {
          "name" : "AMBARI_SERVER"
        }'${_kerberos_client}'
      ],
      "configurations" : [ ],
      "cardinality" : "1"
    },
    {
      "name" : "host_group_2",
      "components" : [
        {
          "name" : "YARN_CLIENT"
        },
        {
          "name" : "HDFS_CLIENT"
        },
        {
          "name" : "TEZ_CLIENT"
        },
        {
          "name" : "ZOOKEEPER_CLIENT"
        },
        {
          "name" : "PIG"
        },
        {
          "name" : "HIVE_CLIENT"
        },
        {
          "name" : "HIVE_SERVER"
        },
        {
          "name" : "MYSQL_SERVER"
        },
        {
          "name" : "HIVE_METASTORE"
        },
        {
          "name" : "HISTORYSERVER"
        },
        {
          "name" : "NAMENODE"
        },
        {
          "name" : "WEBHCAT_SERVER"
        },
        {
          "name" : "MAPREDUCE2_CLIENT"
        },
        {
          "name" : "ZOOKEEPER_SERVER"
        },
        {
          "name" : "APP_TIMELINE_SERVER"
        },
        {
          "name" : "RESOURCEMANAGER"
        }'${_kerberos_client}'
      ],
      "configurations" : [ ],
      "cardinality" : "1"
    },
    {
      "name" : "host_group_3",
      "components" : [
        {
          "name" : "SECONDARY_NAMENODE"
        }'${_kerberos_client}'
      ],
      "configurations" : [ ],
      "cardinality" : "1"
    },
    {
      "name" : "host_group_4",
      "components" : [
        {
          "name" : "YARN_CLIENT"
        },
        {
          "name" : "HDFS_CLIENT"
        },
        {
          "name" : "TEZ_CLIENT"
        },
        {
          "name" : "ZOOKEEPER_CLIENT"
        },
        {
          "name" : "HCAT"
        },
        {
          "name" : "PIG"
        },
        {
          "name" : "MAPREDUCE2_CLIENT"
        },
        {
          "name" : "HIVE_CLIENT"
        },
        {
          "name" : "NODEMANAGER"
        },
        {
          "name" : "DATANODE"
        }'${_kerberos_client}'
      ],
      "configurations" : [ ],
      "cardinality" : "1"
    }
  ],
  "Blueprints": {
    "blueprint_name": "multinode-hdp",
    "stack_name": "HDP",
    "stack_version": "'$_stack_version'"'${_security}'
  }
}'
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
    local _use_default_resp="$2"

    if [ -z "$_file_path" ]; then
        if _isYes "$_use_default_resp"; then
            _file_path="$g_DEFAULT_RESPONSE_FILEPATH";
        else
            _info "Avaliable response files"
            ls -1t ./*.resp
            local _default_file_path="`ls -1t ./*.resp | head -n1`"
	    local _new_response_file=""
            _ask "Type a response file path" "$_default_file_path" "_new_response_file" "N" "Y"
	    _file_path="$_new_response_file"
        fi
    fi
    
    local _actual_file_path="$_file_path"
    if [ ! -r "${_file_path}" ]; then
        _critical "$FUNCNAME: Not a readable response file. ${_file_path}" 1;
        exit 2
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

function f_docker_setup() {
    local __doc__="Install docker (if not yet) and customise for HDP test environment (TODO: Ubuntu only)"

    if [ ! `which apt-get` ]; then
        _warn "No apt-get"
        return 1
    fi

    # https://docs.docker.com/engine/installation/linux/ubuntulinux/
    which docker &>/dev/null
    if [ $? -gt 0 ] || [ ! -s /etc/apt/sources.list.d/docker.list ]; then
        #apt-get update
        apt-get install apt-transport-https ca-certificates -y
        apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D || _info "Did not add key for docker"
        grep "deb https://apt.dockerproject.org/repo" /etc/apt/sources.list.d/docker.list || echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" >> /etc/apt/sources.list.d/docker.list
        apt-get update && apt-get purge lxc-docker*; apt-get install docker-engine -y
    fi

    # To use tcpdump from container
    if [ ! -L /etc/apparmor.d/disable/usr.sbin.tcpdump ]; then
        ln -sf /etc/apparmor.d/usr.sbin.tcpdump /etc/apparmor.d/disable/
        apparmor_parser -R /etc/apparmor.d/usr.sbin.tcpdump
    fi

    local _storage_size="30G"
    # This part is different by docker version, so changing only if it was 10GB or 1*.**GB
    docker info | grep 'Base Device Size' | grep -oP '1\d\.\d\d GB' &>/dev/null
    if [ $? -eq 0 ]; then
        grep 'storage-opt dm.basesize=' /etc/init/docker.conf &>/dev/null
        if [ $? -ne 0 ]; then
            sed -i.bak -e 's/DOCKER_OPTS=$/DOCKER_OPTS=\"--storage-opt dm.basesize='${_storage_size}'\"/' /etc/init/docker.conf
            _warn "Restarting docker (will stop all containers)..."
            sleep 3
            service docker restart
        else
            _warn "storage-opt dm.basesize=${_storage_size} is already set in /etc/init/docker.conf"
        fi
    fi
}

function f_docker_sandbox_install() {
    local __doc__="Install Sandbox docker version"
    local _tmp_dir="${1-./}"
    local _url="$2"

    if [ -z "$_url" ]; then
        _url="http://hortonassets.s3.amazonaws.com/2.5/HDP_2.5_docker.tar.gz"
    fi

    local _file_name="`basename "${_url}"`"

    f_docker_setup

    if ! _isEnoughDisk "$_tmp_dir" "10"; then
        _error "Not enough space to download sandbox"
        return 1
    fi

    if [ -s "${_tmp_dir%/}/${_file_name}" ]; then
        _error "${_tmp_dir%/}/${_file_name} exists. Please delete this first"
        return 1
    fi

    wget -nv -c -t 20 --timeout=60 --waitretry=60 "https://raw.githubusercontent.com/hajimeo/samples/master/bash/start_sandbox.sh" -O ~/start_sandbox.sh
    chmod u+x ~/start_sandbox.sh
    wget -c -t 20 --timeout=60 --waitretry=60 "${_url}" -O "${_tmp_dir%/}/${_file_name}" || return $?

    docker load < "${_tmp_dir%/}/${_file_name}" || return $?

    # This may not work. running 'sysctl' from inside of sandbox docker as well seems to work
    sysctl -w kernel.shmmax=41943040 && sysctl -p
    bash -x ~/start_sandbox.sh
    _info "You may need to run /usr/sbin/ambari-admin-password-reset"
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
        docker start --attach=false node$_n &
        sleep 1
    done
    wait
}

function f_docker_unpause() {
    local __doc__="Experimental: Unpausing some docker containers"
    local _how_many="${1-$r_NUM_NODES}"
    local _start_from="${2-$r_NODE_START_NUM}"

    _info "starting $_how_many docker containers starting from $_start_from ..."
    for _n in `_docker_seq "$_how_many" "$_start_from"`; do
        # docker seems doesn't care if i try to start already started one
        docker unpause node$_n
    done
}

function f_docker_stop() {
    local __doc__="Stopping some docker containers"
    local _how_many="${1-$r_NUM_NODES}"
    local _start_from="${2-$r_NODE_START_NUM}"

    _info "stopping $_how_many docker containers starting from $_start_from ..."
    for _n in `_docker_seq "$_how_many" "$_start_from"`; do
        docker stop node$_n &
        sleep 1
    done
    wait
}

function f_docker_save() {
    local __doc__="Stop containers and commit (save)"
    local _sufix="${1}"
    local _how_many="${2-$r_NUM_NODES}"
    local _start_from="${3-$r_NODE_START_NUM}"

    _warn "If you have not checked disk space, please Ctrl+C now (wait for 3 secs)..."
    sleep 3

    if [ -z "$_sufix" ]; then
        # once a day should be enough?
        _sufix="$(date +"%Y%m%d")"
    fi

    _info "stopping $_how_many docker containers starting from $_start_from ..."
    f_docker_stop $_how_many $_start_from

    _info "saving $_how_many docker containers starting from $_start_from ..."
    for _n in `_docker_seq "$_how_many" "$_start_from"`; do
        docker commit node$_n node${_n}_$_sufix&
        sleep 1
    done
    wait
}

function f_docker_stop_all() {
    local __doc__="Stopping all docker containers if docker command exists"
    which docker &>/dev/null && docker stop $(docker ps -q)
}

function f_docker_stop_other() {
    local __doc__="Stopping other docker containers"
    local _how_many="${1-$r_NUM_NODES}"
    local _start_from="${2-$r_NODE_START_NUM}"

    local _filter=""
    for _s in `_docker_seq "$_how_many" "$_start_from"`; do
        _filter="${_filter}node${_s}|"
    done
    _filter="${_filter%\|}"

    _info "stopping other docker containers (not in ${_filter})..."
    for _n in `docker ps --format "{{.Names}}" | grep -vE "${_filter}"`; do
        docker stop $_n &
        sleep 1
    done
    wait
}

function f_docker_pause_other() {
    local __doc__="Experimental: Pausing(suspending) other docker containers"
    local _how_many="${1-$r_NUM_NODES}"
    local _start_from="${2-$r_NODE_START_NUM}"

    local _filter=""
    for _s in `_docker_seq "$_how_many" "$_start_from"`; do
        _filter="${_filter}node${_s}|"
    done
    _filter="${_filter%\|}"

    _info "stopping other docker containers (not in ${_filter})..."
    for _n in `docker ps --format "{{.Names}}" | grep -vE "${_filter}"`; do
        docker pause $_n &
        sleep 1
    done
    wait
}

function f_docker_rm() {
    local _force="$1"
    local __doc__="Removing *all* docker containers"
    _ask "Are you sure to delete ALL containers?"
    if _isYes; then
        if _isYes $_force; then
            for _q in `docker ps -aq`; do
                docker rm --force ${_q} &
                sleep 1
            done
        else
            for _q in `docker ps -aq`; do
                docker rm ${_q} &
                sleep 1
            done
        fi
        wait
    fi
}

function f_docker_run() {
    local __doc__="Running (creating) docker containers"
    # ./start_hdp.sh -r ./node11-14_2.5.0.resp -f "f_docker_run 1 16"
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

function f_kdc_install_on_ambari_node() {
    # TODO: somehow doesn't work well with docker
    local __doc__="Install KDC/kadmin service to $r_AMBARI_HOST"
    local _realm="${1-EXAMPLE.COM}"
    local _password="${2-$g_DEFAULT_PASSWORD}"
    local _server="${3-$r_AMBARI_HOST}"

    if [ -z "$_server" ]; then
        _error "KDC installing hostname is missing"
        return 1
    fi

    ssh root@$_server -t "yum install krb5-server krb5-libs krb5-workstation -y"
    # this doesn't work with docker though
    ssh root@$_server -t "chkconfig  krb5kdc on; chkconfig kadmin on"
    ssh root@$_server -t "mv /etc/krb5.conf /etc/krb5.conf.orig; echo \"[libdefaults]
 default_realm = $_realm
[realms]
 $_realm = {
   kdc = $_server
   admin_server = $_server
 }\" > /etc/krb5.conf"
    ssh root@$_server -t "kdb5_util create -s -P $_password"
    # chkconfig krb5kdc on;chkconfig kadmin on; doesn't work with docker
    ssh root@$_server -t "echo '*/admin *' > /var/kerberos/krb5kdc/kadm5.acl;service krb5kdc restart;service kadmin restart;kadmin.local -q \"add_principal -pw $_password admin/admin\""
}

function f_ldap_server_install_on_host() {
    local __doc__="Install LDAP server packages on Ubuntu TODO: setup"
    local _ldap_domain="$1"
    local _password="${2-$g_DEFAULT_PASSWORD}"

    if [ ! `which apt-get` ]; then
        _warn "No apt-get"
        return 1
    fi

    if [ -z "$_ldap_domain" ]; then
        _warn "No LDAP Domain, so using dc=example,dc=com"
        _ldap_domain="dc=example,dc=com"
    fi

    local _set_noninteractive=false
    if [ -z "$DEBIAN_FRONTEND" ]; then
        export noninteractive=noninteractive
        _set_noninteractive=true
    fi
    debconf-set-selections <<EOF
slapd slapd/internal/generated_adminpw password ${_password}
slapd slapd/password2 password ${_password}
slapd slapd/internal/adminpw password ${_password}
slapd slapd/password1 password ${_password}
slapd slapd/domain string ${_ldap_domain}
slapd shared/organization string ${_ldap_domain}
EOF
    apt-get install -y slapd ldap-utils
    if $_set_noninteractive ; then
        unset DEBIAN_FRONTEND
    fi

    # test
    ldapsearch -x -D "cn=admin,${_ldap_domain}" -w "${_password}" # -h ${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}
}

function f_ldap_server_install_on_ambari_node() {
    local __doc__="TODO: CentOS6 only: Install LDAP server packages TODO: setup"
    local _ldap_domain="$1"
    local _password="${2-$g_DEFAULT_PASSWORD}"
    local _server="${3-$r_AMBARI_HOST}"

    if [ -z "$_ldap_domain" ]; then
        _warn "No LDAP Domain, so using dc=example,dc=com"
        _ldap_domain="dc=example,dc=com"
    fi

    # TODO: chkconfig slapd on wouldn't do anything on docker container
    ssh root@$_server -t "yum install openldap openldap-servers openldap-clients -y" || return $?
    ssh root@$_server -t "cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG ; chown ldap. /var/lib/ldap/DB_CONFIG && /etc/rc.d/init.d/slapd start" || return $?
    local _md5=""
    _md5="`ssh root@$_server -t "slappasswd -s ${_password}"`" || return $?

    if [ -z "$_md5" ]; then
        _error "Couldn't generate hashed password"
        return 1
    fi

    ssh root@$_server -t 'cat "dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: '${_md5}'
" > /tmp/chrootpw.ldif && ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/chrootpw.ldif' || return $?

    ssh root@$_server -t 'cat "dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth"
  read by dn.base="cn=Manager,'${_ldap_domain}'" read by * none

dn: olcDatabase={2}bdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: '${_ldap_domain}'

dn: olcDatabase={2}bdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=Manager,'${_ldap_domain}'

dn: olcDatabase={2}bdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: '${_md5}'

dn: olcDatabase={2}bdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by
  dn="cn=Manager,'${_ldap_domain}'" write by anonymous auth by self write by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to * by dn="cn=Manager,'${_ldap_domain}'" write by * read
" > /tmp/chdomain.ldif && ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/chdomain.ldif' || return $?

    ssh root@$_server -t 'dn: '${_ldap_domain}'
objectClass: top
objectClass: dcObject
objectclass: organization
o: Server World
dc: Srv

dn: cn=Manager,'${_ldap_domain}'
objectClass: organizationalRole
cn: Manager
description: Directory Manager

dn: ou=People,'${_ldap_domain}'
objectClass: organizationalUnit
ou: People

dn: ou=Group,'${_ldap_domain}'
objectClass: organizationalUnit
ou: Group
" > /tmp/basedomain.ldif && ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/basedomain.ldif' || return $?
}

function f_ldap_client_install() {
    local __doc__="TODO: CentOS6 only: Install LDAP client packages"
    # somehow having difficulty to install openldap in docker so using dockerhost1
    local _ldap_server="${1}"
    local _ldap_basedn="${2}"
    local _how_many="${3-$r_NUM_NODES}"
    local _start_from="${4-$r_NODE_START_NUM}"

    if [ -z "$_ldap_server" ]; then
        _warn "No LDAP server hostname. Using ${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}"
        _ldap_server="${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}"
    fi
    if [ -z "$_ldap_basedn" ]; then
        _warn "No LDAP Base DN, so using dc=example,dc=com"
        _ldap_basedn="dc=example,dc=com"
    fi

    for i in `_docker_seq "$_how_many" "$_start_from"`; do
        ssh root@node$i${r_DOMAIN_SUFFIX} -t "yum -y erase nscd;yum -y install sssd sssd-client sssd-ldap openldap-clients"
        if [ $? -eq 0 ]; then
            ssh root@node$i${r_DOMAIN_SUFFIX} -t "authconfig --enablesssd --enablesssdauth --enablelocauthorize --enableldap --enableldapauth --disableldaptls --ldapserver=ldap://${_ldap_server} --ldapbasedn=${_ldap_basedn} --update" || _warn "node$i failed to setup ldap client"
            # test
            #authconfig --test
            # getent passwd admin
        else
            _warn "node$i failed to install ldap client"
        fi
    done
}

function f_ambari_server_install() {
    local __doc__="Install Ambari Server to $r_AMBARI_HOST"
    if [ -z "$r_AMBARI_REPO_FILE" ]; then
        _error "Please specify Ambari repo *file* URL"
        return 1
    fi

    # TODO: at this moment, only Centos (yum)
    if _isUrl "$r_AMBARI_REPO_FILE"; then
        wget -nv "$r_AMBARI_REPO_FILE" -O /tmp/ambari.repo || return 1
    else
        if [ ! -r "$r_AMBARI_REPO_FILE" ]; then
            _error "Please specify readable Ambari repo file or URL"
            return 1
        fi

        cp -f "$r_AMBARI_REPO_FILE" /tmp/ambari.repo
    fi

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

function f_ambari_update_config() {
    local __doc__="TODO: Change some configuration for this dev environment"

    # TODO: need to find the best way to find the first time
    local _c=$(PGPASSWORD=bigdata psql -Uambari -h $r_AMBARI_HOST -tAc "select count(*) from alert_definition where schedule_interval = 2;")
    if [ $_c -eq 0 ]; then
        ssh -t root@$r_AMBARI_HOST "/var/lib/ambari-server/resources/scripts/configs.sh set localhost $r_CLUSTER_NAME hdfs-site dfs.replication 1" &> /tmp/configs_sh_dfs_replication.out
        # TODO: should I reduce aggregator TTL size?
        #ssh -t root@$r_AMBARI_HOST "/var/lib/ambari-server/resources/scripts/configs.sh set localhost $r_CLUSTER_NAME ams-site " &> /tmp/configs_sh_dfs_replication.out

        PGPASSWORD=bigdata psql -Uambari -h $r_AMBARI_HOST -c "update alert_definition set schedule_interval = 2 where schedule_interval = 1;
        update alert_definition set schedule_interval = 7 where schedule_interval = 3;
        update alert_definition set schedule_interval = 11 where schedule_interval = 4;
        update alert_definition set schedule_interval = 13 where schedule_interval = 5;
        update alert_definition set schedule_interval = 17 where schedule_interval = 8;"

        _info "HDFS Replication Factor and Ambari Alert frequency has been updated."
    fi
}

function f_ambari_agent_install() {
    local __doc__="Installing ambari-agent on all containers for manual registration"
    # ./start_hdp.sh -r ./node11-14_2.5.0.resp -f "f_ambari_agent_install 1 16"
    local _how_many="${1-$r_NUM_NODES}"
    local _start_from="${2-$r_NODE_START_NUM}"

    scp root@$r_AMBARI_HOST:/etc/yum.repos.d/ambari.repo /tmp/ambari.repo

    #local _cmd="yum install ambari-agent -y && grep "^hostname=$r_AMBARI_HOST"/etc/ambari-agent/conf/ambari-agent.ini || sed -i.bak "s@hostname=.+$@hostname=$r_AMBARI_HOST@1" /etc/ambari-agent/conf/ambari-agent.ini"
    local _cmd="yum install ambari-agent -y && ambari-agent reset $r_AMBARI_HOST"

    for i in `_docker_seq "$_how_many" "$_start_from"`; do
        scp /tmp/ambari.repo root@node$i${r_DOMAIN_SUFFIX}:/etc/yum.repos.d/
        # Executing yum command one by one (not parallel)
        ssh -t root@node$i${r_DOMAIN_SUFFIX} "$_cmd"
    done
}

function f_ambari_agent() {
    local __doc__="Executing ambari-agent command on some containers"
    local _cmd="${1-status}"
    local _how_many="${2-$r_NUM_NODES}"
    local _start_from="${3-$r_NODE_START_NUM}"

    for i in `_docker_seq "$_how_many" "$_start_from"`; do
        ssh root@node$i${r_DOMAIN_SUFFIX} -t "ambari-agent $_cmd"
    done
}

function f_ambari_agent_fix_public_hostname() {
    local __doc__="Fixing public hostname (169.254.169.254 issue) by appending public_hostname.sh"
    local _how_many="${1-$r_NUM_NODES}"
    local _start_from="${2-$r_NODE_START_NUM}"
    local _cmd='grep "^public_hostname_script" /etc/ambari-agent/conf/ambari-agent.ini || ( echo -e "#!/bin/bash\necho \`hostname -f\`" > /var/lib/ambari-agent/public_hostname.sh && chmod a+x /var/lib/ambari-agent/public_hostname.sh && sed -i.bak "/run_as_user/i public_hostname_script=/var/lib/ambari-agent/public_hostname.sh\n" /etc/ambari-agent/conf/ambari-agent.ini )'

    for i in `_docker_seq "$_how_many" "$_start_from"`; do
        ssh root@node$i${r_DOMAIN_SUFFIX} -t "$_cmd"
    done
}

function f_nodes_exec() {
    local __doc__="Executing a command against all running nodes/containers"
    local _cmd="${1}"
    local _bg="${2-N}"
    local _how_many="${3-$r_NUM_NODES}"
    local _start_from="${4-$r_NODE_START_NUM}"

    if [ -z "$_cmd" ]; then
        _error "No command"
        return 1
    fi

    if _isYes "$_bg"; then
        local _id=`date +%s`
    fi

    for i in `_docker_seq "$_how_many" "$_start_from"`; do
        if _isYes "$_bg"; then
            # can't use -t for background
            ssh -o StrictHostKeyChecking=no node${i}${r_DOMAIN_SUFFIX} -T "$_cmd" &> /tmp/.${_id}_node${i}.tmp &
        else
            ssh node${i}${r_DOMAIN_SUFFIX} -t "$_cmd"
        fi
    done

    if _isYes "$_bg"; then
        wait

        for i in `_docker_seq "$_how_many" "$_start_from"`; do
            echo "# node${i}${r_DOMAIN_SUFFIX} \"$_cmd\""
            cat /tmp/.${_id}_node${i}.tmp | grep -v '^Warning: Permanently added'
            rm -f /tmp/.${_id}_node${i}.tmp
        done
    fi
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

    if [ ! `which apt-get` ]; then
        _warn "No apt-get"
        return 1
    fi

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

    if [ ! -d "$_local_dir" ]; then
        # Making directory for Apache2
        mkdir -p -m 777 $_local_dir
    fi

    cd "$_local_dir" || return 1

    local _tar_gz_file="`basename "$r_HDP_REPO_TARGZ"`"
    local _has_extracted=""
    local _hdp_dir="`find . -type d | grep -m1 -E "/${r_CONTAINER_OS}${r_REPO_OS_VER}/.+?/${r_HDP_REPO_VER}$"`"

    if _isNotEmptyDir "$_hdp_dir"; then
        if ! _isYes "$_force_extract"; then
            _has_extracted="Y"
        fi
        _info "$_hdp_dir already exists and not empty. Skipping download."
    elif [ -e "$_tar_gz_file" ]; then
        _info "$_tar_gz_file already exists. Skipping download."
    elif [ -e "/var/www/html/hdp/$_tar_gz_file" ]; then
        _info "/var/www/html/hdp/$_tar_gz_file already exists. Skipping download."
        _tar_gz_file="/var/www/html/hdp/$_tar_gz_file"
    else
        if ! _isEnoughDisk "/$_local_dir" "10"; then
            _error "Not enough space to download $r_HDP_REPO_TARGZ"
            return 1
        fi

        #curl --limit-rate 200K --retry 20 -C - "$r_HDP_REPO_TARGZ" -o $_tar_gz_file
        wget -nv -c -t 20 --timeout=60 --waitretry=60 "$r_HDP_REPO_TARGZ"
    fi

    if _isYes "$_download_only"; then
        return $?
    fi

    if ! _isYes "$_has_extracted"; then
        tar xzvf "$_tar_gz_file"
        _hdp_dir="`find . -type d | grep -m1 -E "/${r_CONTAINER_OS}${r_REPO_OS_VER}/.+?/${r_HDP_REPO_VER}$"`"
        createrepo "$_hdp_dir"
    fi

    local _util_tar_gz_file="`basename "$r_HDP_REPO_UTIL_TARGZ"`"
    local _util_has_extracted=""
    # TODO: not accurate
    local _hdp_util_dir="`find . -type d | grep -m1 -E "/HDP-UTILS-.+?/${r_CONTAINER_OS}${r_REPO_OS_VER}$"`"

    if _isNotEmptyDir "$_hdp_util_dir"; then
        if ! _isYes "$_force_extract"; then
            _util_has_extracted="Y"
        fi
        _info "$_hdp_util_dir already exists and not empty. Skipping download."
    elif [ -e "$_util_tar_gz_file" ]; then
        _info "$_util_tar_gz_file already exists. Skipping download."
    else
        wget -nv -c -t 20 --timeout=60 --waitretry=60 "$r_HDP_REPO_UTIL_TARGZ"
    fi

    if ! _isYes "$_util_has_extracted"; then
        tar xzvf "$_util_tar_gz_file"
        _hdp_util_dir="`find . -type d | grep -m1 -E "/HDP-UTILS-.+?/${r_CONTAINER_OS}${r_REPO_OS_VER}$"`"
        createrepo "$_hdp_util_dir"
    fi

    cd - &>/dev/null

    service apache2 start

    if [ -n "$r_DOCKER_PRIVATE_HOSTNAME" ]; then
        local _repo_path="${_hdp_dir#\.}"
        echo "### Local Repo URL: http://${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}${_repo_path}"
        local _util_repo_path="${_hdp_util_dir#\.}"
        echo "### Local Repo URL: http://${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}${_util_repo_path}"

        # TODO: support only CentOS or RedHat at this moment
        if [ "${r_CONTAINER_OS}" = "centos" ] || [ "${r_CONTAINER_OS}" = "redhat" ]; then
            _port_wait "$r_AMBARI_HOST" "8080"

            f_ambari_set_repo "http://${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}${_repo_path}" "http://${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}${_util_repo_path}"
        else
            _warn "At this moment only centos or redhat for local repository"
        fi
    fi
}
function f_ambari_set_repo() {
    local __doc__="Update Ambari's repository URL information"
    local _repo_url="$1"
    local _util_url="$2"
    local _ambari_host="${3-$r_AMBARI_HOST}"
    local _ambari_port="${4-8080}"

    _port_wait $_ambari_host $_ambari_port
    if [ $? -ne 0 ]; then
        _error "Ambari is not running on $_ambari_host $_ambari_port"
        return 1
    fi

    local _os_name="$r_CONTAINER_OS"
    if [ "${_os_name}" = "centos" ]; then
        _os_name="redhat"
    fi

    if _isUrl "$_repo_url"; then
        # TODO: admin:admin
        curl -H "X-Requested-By: ambari" -X PUT -u admin:admin "http://${r_AMBARI_HOST}:8080/api/v1/stacks/HDP/versions/${r_HDP_STACK_VERSION}/operating_systems/${_os_name}${r_REPO_OS_VER}/repositories/HDP-${r_HDP_STACK_VERSION}" -d '{"Repositories":{"base_url":"'${_repo_url}'","verify_base_url":true}}'
    fi

    if _isUrl "$_util_url"; then
        local _hdp_util_name="`echo $_util_url | grep -oP 'HDP-UTILS-[\d\.]+'`"
        curl -H "X-Requested-By: ambari" -X PUT -u admin:admin "http://${r_AMBARI_HOST}:8080/api/v1/stacks/HDP/versions/${r_HDP_STACK_VERSION}/operating_systems/${_os_name}${r_REPO_OS_VER}/repositories/${_hdp_util_name}" -d '{"Repositories":{"base_url":"'${_util_url}'","verify_base_url":true}}'
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
    local _c=$(PGPASSWORD=bigdata psql -Uambari -h $r_AMBARI_HOST -tAc "select cluster_name from ambari.clusters order by cluster_id desc limit 1;")
    if [ -z "$_c" ]; then
      _error "No cluster name (check PostgreSQL)..."
      return 1
    fi

    _port_wait "$r_AMBARI_HOST" "8080"
    _ambari_agent_wait

    curl -u admin:admin -H "X-Requested-By: ambari" "http://$r_AMBARI_HOST:8080/api/v1/clusters/${_c}/services?" -X PUT --data '{"RequestInfo":{"context":"_PARSE_.START.ALL_SERVICES","operation_level":{"level":"CLUSTER","cluster_name":"'${_c}'"}},"Body":{"ServiceInfo":{"state":"STARTED"}}}'
    echo ""
}

function _ambari_agent_wait() {
    local _db_host="${1-$r_AMBARI_HOST}"
    local _u=""

    for i in `seq 1 10`; do
      sleep 5
      _u=$(PGPASSWORD=bigdata psql -Uambari -h $_db_host -tAc "select count(*) from hoststate where health_status ilike '%UNKNOWN%';")
      #curl -s --head "http://$r_AMBARI_HOST:8080/" | grep '200 OK'
      if [ "$_u" -eq 0 ]; then
        return 0
      fi

      _info "Some Ambari agent is in UNKNOWN state ($_u). waiting..."
    done
    return 1
}

function f_screen_cmd() {
    local __doc__="Output GNU screen command"
    screen -ls | grep -w "docker_$r_CLUSTER_NAME"
    if [ $? -ne 0 ]; then
      _info "You may want to run the following commands to start GNU Screen:"
      echo "screen -S \"docker_$r_CLUSTER_NAME\" bash -c 'for s in \``_docker_seq "$r_NUM_NODES" "$r_NODE_START_NUM" "Y"`\`; do screen -t \"node\${s}\" \"ssh\" \"node\${s}${r_DOMAIN_SUFFIX}\"; sleep 1; done'"
    fi
}

function f_vmware_tools_install() {
    local __doc__="Install VMWare Tools in Ubuntu host"
    mkdir /media/cdrom; mount /dev/cdrom /media/cdrom && cd /media/cdrom && cp VMwareTools-*.tar.gz /tmp/ && cd /tmp/ && tar xzvf VMwareTools-*.tar.gz && cd vmware-tools-distrib/ && ./vmware-install.pl -d
}

function f_sysstat_setup() {
    local __doc__="Install and set up sysstat"

    if [ ! `which apt-get` ]; then
        _warn "No apt-get"
        return 1
    fi

    which sar &>/dev/null
    if [ $? -ne 0 ]; then
        apt-get -y install sysstat
    fi
    grep -i '^ENABLED="false"' /etc/default/sysstat &>/dev/null
    if [ $? -eq 0 ]; then
        sed -i.bak -e 's/ENABLED=\"false\"/ENABLED=\"true\"/' /etc/default/sysstat
        service sysstat restart
    fi
}

function p_host_setup() {
    local __doc__="Install packages into this host (Ubuntu)"
    local _docer0="${1-$r_DOCKER_HOST_IP}"

    if [ `which apt-get` ]; then
        if _isYes "$r_APTGET_UPGRADE"; then
            apt-get update && apt-get upgrade -y
        fi

        # NOTE: psql (postgresql-client) is required
        apt-get -y install wget sshfs sysv-rc-conf sysstat dstat iotop tcpdump sharutils unzip postgresql-client libxml2-utils expect
        #krb5-kdc krb5-admin-server mailutils postfix mysql-client htop

        f_sysstat_setup
        f_host_performance
        f_host_misc
        f_docker_setup
        f_dnsmasq
    fi

    f_docker0_setup "$_docer0"
    f_dockerfile
    f_docker_base_create
    f_docker_run
    f_docker_start

    f_ambari_server_install
    sleep 3
    f_ambari_server_start
    sleep 3

    if _isYes "$r_PROXY"; then
        f_apache_proxy
        f_yum_remote_proxy
    fi

    if _isYes "$r_HDP_LOCAL_REPO"; then
        f_local_repo
    elif [ -n "$r_HDP_REPO_URL" ]; then
        # TODO: at this moment r_HDP_UTIL_URL always empty if not local repo
        f_ambari_set_repo "$r_HDP_REPO_URL" "$r_HDP_UTIL_URL"
    fi
    if _isYes "$r_AMBARI_BLUEPRINT"; then
        p_ambari_blueprint
    fi

    f_screen_cmd
}

function f_dnsmasq() {
    local __doc__="Install and set up dnsmasq"
    if [ ! `which apt-get` ]; then
        _warn "No apt-get"
        return 1
    fi
    apt-get -y install dnsmasq

    grep '^addn-hosts=' /etc/dnsmasq.conf || echo 'addn-hosts=/etc/banner_add_hosts' >> /etc/dnsmasq.conf

    # TODO: the first IP can be wrong one
    _docer0="`f_docker_ip`"

    if [ -z "$r_DOCKER_PRIVATE_HOSTNAME" ]; then
        _warn="Hostname for docker host in the private network is empty. using dockerhost1"
        r_DOCKER_PRIVATE_HOSTNAME="dockerhost1"
    fi

    if [ -s /etc/banner_add_hosts ]; then
        _warn "/etc/banner_add_hosts already exists. Skipping..."
        return
    fi

    echo "$_docer0     ${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX} ${r_DOCKER_PRIVATE_HOSTNAME}" > /etc/banner_add_hosts
    for i in `seq 1 99`; do
        echo "${r_DOCKER_NETWORK_ADDR}${i}    node${i}${r_DOMAIN_SUFFIX} node${i}" >> /etc/banner_add_hosts
    done
    service dnsmasq restart
}

function f_host_performance() {
    local __doc__="Performance related changes on the host. Eg: Change kernel parameters on Docker Host (Ubuntu)"
    grep '^vm.swappiness' /etc/sysctl.conf || echo "vm.swappiness = 0" >> /etc/sysctl.conf
    sysctl -w vm.swappiness=0

    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    echo never > /sys/kernel/mm/transparent_hugepage/defrag

    # also ip forwarding as well
    grep '^net.ipv4.ip_forward' /etc/sysctl.conf || echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -w net.ipv4.ip_forward=1
}

function f_host_misc() {
    local __doc__="Misc. changes"
    grep "^IP=" /etc/rc.local &>/dev/null
    if [ $? -ne 0 ]; then
        sed -i.bak '/^exit 0/i IP=$(/sbin/ifconfig eth0 | grep -oP "inet addr:\\\d+\\\.\\\d+\\\.\\\d+\\\.\\\d+" | cut -d":" -f2); echo "eth0 IP: $IP" > /etc/issue\n' /etc/rc.local
    fi

    grep '^PasswordAuthentication no' /etc/ssh/sshd_config && sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config && service ssh restart
    #grep '^PermitRootLogin without-password' /etc/ssh/sshd_config && sed -i 's/^PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config && service ssh restart
}

function f_dockerfile() {
    local __doc__="Download dockerfile and replace private key"
    local _url="$1"
    if [ -z "$_url" ]; then
        _url="$r_DOCKERFILE_URL"
    fi
    if [ -z "$_url" ]; then
        _error "No DockerFile URL/path"
        return 1
    fi

    if _isUrl "$_url"; then
        if [ -e ./DockerFile ]; then
            # only one backup would be enough
            mv -f ./DockerFile ./DockerFile.bak
        fi

        _info "Downloading $_url ..."
        wget -nv "$_url" -O ./DockerFile
    fi

    f_ssh_setup

    local _pkey="`sed ':a;N;$!ba;s/\n/\\\\\\\n/g' $HOME/.ssh/id_rsa`"

    sed -i "s@_REPLACE_WITH_YOUR_PRIVATE_KEY_@${_pkey}@1" ./DockerFile
}

function f_ssh_setup() {
    if [ ! -e $HOME/.ssh/id_rsa ]; then
        ssh-keygen -f $HOME/.ssh/id_rsa -q -N ""
    fi

    if [ ! -e $HOME/.ssh/id_rsa.pub ]; then
        ssh-keygen -y -f $HOME/.ssh/id_rsa > $HOME/.ssh/id_rsa.pub
    fi

    _key="`cat $HOME/.ssh/id_rsa.pub | awk '{print $2}'`"
    grep "$_key" $HOME/.ssh/authorized_keys &>/dev/null
    if [ $? -ne 0 ] ; then
      cat $HOME/.ssh/id_rsa.pub >> $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys
    fi

    if [ ! -e $HOME/.ssh/config ]; then
        echo "Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null" > $HOME/.ssh/config
    fi

    # TODO: At this moment the following lines are not used
    if [ ! -e /root/.ssh/id_rsa ]; then
        mkdir /root/.ssh &>/dev/null
        cp $HOME/.ssh/id_rsa /root/.ssh/id_rsa
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
    
    local _current="`cat /etc/hostname`"
    hostname $_new_name
    echo "$_new_name" > /etc/hostname
    sed -i.bak "s/\b${_current}\b/${_new_name}/g" /etc/hosts
    diff /etc/hosts.bak /etc/hosts
}

function f_apache_proxy() {
    local _proxy_dir="/var/www/proxy"
    local _cache_dir="/var/cache/apache2/mod_cache_disk"
    local _port="${r_PROXY_PORT-28080}"

    if [ ! `which apt-get` ]; then
        _warn "No apt-get"
        return 1
    fi

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
            Allow from all
        </Proxy>

        ProxyVia On

        <IfModule mod_cache_disk.c>
            CacheRoot ${_cache_dir}
            CacheIgnoreCacheControl On
            CacheEnable disk /
            CacheEnable disk http://
            CacheDirLevels 2
            CacheDirLength 1
            CacheMaxFileSize 50000000
        </IfModule>

    </IfModule>
</VirtualHost>" > /etc/apache2/sites-available/proxy.conf

    a2ensite proxy
    # TODO: should use restart?
    service apache2 reload
}

function f_yum_remote_proxy() {
    local __doc__="This function edits yum.conf of each running container to set up proxy (http://your.proxy.server:port)"
    local _proxy_url="$1"
    local _port="${r_PROXY_PORT-28080}"

    if [ -z "$_proxy_url" ]; then
        if [ -z "$r_DOCKER_HOST_IP" ]; then
            _error "No proxy (http://your.proxy.server:port) to set"
            return 1
        else
            _info "No proxy, so that using http://${r_DOCKER_HOST_IP}:${_port}"
            _proxy_url="http://${r_DOCKER_HOST_IP}:${_port}"
        fi
    fi

    # set up proxy for all running containers
    for _host in `docker ps --format "{{.Names}}"`; do
        ssh root@$_host "grep ^proxy /etc/yum.conf || echo \"proxy=${_proxy_url}\" >> /etc/yum.conf"
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
    _warn "Deleting hadoop logs which is older than $_days..."
    # NOTE: Assuming docker name and hostname is same
    for _name in `docker ps --format "{{.Names}}"`; do
        ssh root@${_name}${r_DOMAIN_SUFFIX} 'find /var/log/ -type f -group hadoop \( -name "*\.log*" -o -name "*\.out*" \) -mtime +'${_days}' -exec grep -Iq . {} \; -and -print0 | xargs -0 -t -n1 -I {} rm -f {}'
        # Agent log is owned by root
        ssh root@${_name}${r_DOMAIN_SUFFIX} 'find /var/log/ambari-* -type f \( -name "*\.log*" -o -name "*\.out*" \) -mtime +'${_days}' -exec grep -Iq . {} \; -and -print0 | xargs -0 -t -n1 -I {} rm -f {}'
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
            if [ `which apt-get` ]; then
                _ask "Would you like to install 'curl'?" "Y"
                if _isYes ; then
                    DEBIAN_FRONTEND=noninteractive apt-get -y install curl &>/dev/null
                fi
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

        #_info "Validating the downloaded script..."
        #source ${_local_file_path} || _critical "Please contact the script author."
        _info "Script has been updated. Please re-run."
        _exit 0
    fi
}

function f_vnc_setup() {
    local __doc__="Install X and VNC Server. NOTE: this uses about 400MB space"
    local _user="${1-$USER}"
    local _vpass="${2-$g_DEFAULT_PASSWORD}"
    local _pass="${3-$g_DEFAULT_PASSWORD}"

    if [ ! `which apt-get` ]; then
        _warn "No apt-get"
        return 1
    fi

    if [ ! `grep "$_user" /etc/passwd` ]; then
        f_useradd "$_user" "$_pass" || return $?
    fi

    # apt-get update
    apt-get install -y xfce4 xfce4-goodies tightvncserver firefox

    su - $_user -c 'echo "hadoop" | vncpasswd -f > $HOME/.vnc/passwd
chmod 600 $HOME/.vnc/passwd
mv $HOME/.vnc/xstartup $HOME/.vnc/xstartup.bak &>/dev/null
echo "#!/bin/bash
xrdb $HOME/.Xresources
startxfce4 &" > $HOME/.vnc/xstartup
chmod u+x $HOME/.vnc/xstartup'

    echo "To start:"
    echo "su - $_user -c 'vncserver -geometry 1280x768'"
    echo "To stop:"
    echo "su - $_user -c 'vncserver -kill :1'"

    # to check
    #sudo netstat -aopen | grep 5901
}

function f_sssd_setup() {
    local __doc__="TODO: setup SSSD on each node"
    return
    # https://github.com/HortonworksUniversity/Security_Labs#install-solrcloud

    local ad_user="registersssd"
    local ad_domain="lab.hortonworks.net"
    local ad_dc="ad01.lab.hortonworks.net"
    local ad_root="dc=lab,dc=hortonworks,dc=net"
    local ad_ou="ou=HadoopNodes,${ad_root}"
    local ad_realm=${ad_domain^^}

    sudo kinit ${ad_user}

    # yum makecache fast
    yum -y install sssd oddjob-mkhomedir authconfig sssd-krb5 sssd-ad sssd-tools adcli

    sudo adcli join -v \
      --domain-controller=${ad_dc} \
      --domain-ou="${ad_ou}" \
      --login-ccache="/tmp/krb5cc_0" \
      --login-user="${ad_user}" \
      -v \
      --show-details

    sudo tee /etc/sssd/sssd.conf > /dev/null <<EOF
[sssd]
## master & data nodes only require nss. Edge nodes require pam.
services = nss, pam, ssh, autofs, pac
config_file_version = 2
domains = ${ad_realm}
override_space = _

[domain/${ad_realm}]
id_provider = ad
ad_server = ${ad_dc}
#ad_server = ad01, ad02, ad03
#ad_backup_server = ad-backup01, 02, 03
auth_provider = ad
chpass_provider = ad
access_provider = ad
enumerate = False
krb5_realm = ${ad_realm}
ldap_schema = ad
ldap_id_mapping = True
cache_credentials = True
ldap_access_order = expire
ldap_account_expire_policy = ad
ldap_force_upper_case_realm = true
fallback_homedir = /home/%d/%u
default_shell = /bin/false
ldap_referrals = false

[nss]
memcache_timeout = 3600
override_shell = /bin/bash
EOF

    sudo chmod 0600 /etc/sssd/sssd.conf
    sudo service sssd restart
    sudo authconfig --enablesssd --enablesssdauth --enablemkhomedir --enablelocauthorize --update

    sudo chkconfig oddjobd on
    sudo service oddjobd restart
    sudo chkconfig sssd on
    sudo service sssd restart

    # sudo kdestroy

    #detect name of cluster
    output=`curl -k -u hadoopadmin:$PASSWORD -i -H 'X-Requested-By: ambari'  https://localhost:8443/api/v1/clusters`
    cluster=`echo $output | sed -n 's/.*"cluster_name" : "\([^\"]*\)".*/\1/p'`

    #refresh user and group mappings
    sudo sudo -u hdfs kinit -kt /etc/security/keytabs/hdfs.headless.keytab hdfs-"${cluster,,}"
    sudo sudo -u hdfs hdfs dfsadmin -refreshUserToGroupsMappings

    sudo sudo -u yarn kinit -kt /etc/security/keytabs/yarn.service.keytab yarn/$(hostname -f)@LAB.HORTONWORKS.NET
    sudo sudo -u yarn yarn rmadmin -refreshUserToGroupsMappings
}

function f_certificate_setup() {
    local __doc__="Generate keystore and certificate for Hadoop SSL"
    # http://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.5.3/bk_security/content/create-internal-ca.html
    local _dname="$1"
    local _password="$2"
    local _work_dir="${3-./}"
    local _how_many="${4-$r_NUM_NODES}"
    local _start_from="${5-$r_NODE_START_NUM}"
    local _domain_suffix="${6-$r_DOMAIN_SUFFIX}"

    local SERVER_KEY_LOCATION="/etc/hadoop/conf/secure/"
    local KEYSTORE_FILE="server.keystore.jks"
    local TRUSTSTORE_FILE="server.truststore.jks"
    local CLIENT_TRUSTSTORE_FILE="client.truststore.jks"
    local YARN_USER="yarn"

    if ! which keytool &>/dev/null; then
        _error "Keytool is required to set up SSL"
        return 1
    fi

    if ! which openssl &>/dev/null; then
        _error "openssl is required to set up SSL"
        return 1
    fi

    if [ -z "$_domain_suffix" ]; then
        _domain_suffix="${r_DOMAIN_SUFFIX-.localdomain}"
    fi
    if [ -z "$_dname" ]; then
        _dname="CN=*${_domain_suffix}, OU=Support, O=Hortonworks, L=Brisbane, ST=QLD, C=AU"
    fi

    if [ -z "$_password" ]; then
        _password=${g_DEFAULT_PASSWORD-hadoop}
    fi

    if [ ! -d "$_work_dir" ]; then
        if ! mkdir "$_work_dir" ; then
            _error "Couldn't create $_work_dir"
            return 1
        fi
    fi

    local _a
    local _tmp=""
    _split "_a" "$_dname"

    echo [ req ] > "${_work_dir%/}/openssl.cnf"
    echo input_password = $_password >> "${_work_dir%/}/openssl.cnf"
    echo output_password = $_password >> "${_work_dir%/}/openssl.cnf"
    echo distinguished_name = req_distinguished_name >> "${_work_dir%/}/openssl.cnf"
    echo req_extensions = v3_req  >> "${_work_dir%/}/openssl.cnf"
    echo prompt=no >> "${_work_dir%/}/openssl.cnf"
    echo [req_distinguished_name] >> "${_work_dir%/}/openssl.cnf"
    for (( idx=${#_a[@]}-1 ; idx>=0 ; idx-- )) ; do
        _tmp="`_trim "${_a[$idx]}"`"
        # note: nocasematch is already used
        [[ "${_tmp}" =~ CN=\*\. ]] && _tmp="CN=rootca${_domain_suffix}"
        echo ${_tmp} >> "${_work_dir%/}/openssl.cnf"
    done
    echo [EMAIL PROTECTED] >> "${_work_dir%/}/openssl.cnf"
    echo [EMAIL PROTECTED] >> "${_work_dir%/}/openssl.cnf"
    echo [ v3_req ] >> "${_work_dir%/}/openssl.cnf"
    echo basicConstraints = critical,CA:FALSE >> "${_work_dir%/}/openssl.cnf"
    echo keyUsage = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment, keyAgreement >> "${_work_dir%/}/openssl.cnf"
    echo extendedKeyUsage=emailProtection,clientAuth >> "${_work_dir%/}/openssl.cnf"
    echo [ ${_domain_suffix#.} ] >> "${_work_dir%/}/openssl.cnf"
    echo subjectAltName = DNS:${_domain_suffix#.},DNS:*${_domain_suffix} >> "${_work_dir%/}/openssl.cnf"

    # Generate server certificate in a keystore. TODO: why "localhost" is the alias?
    keytool -keystore "${_work_dir%/}/${KEYSTORE_FILE}" -alias localhost -validity 3650 -genkey -keyalg RSA -keysize 2048 -dname "$_dname" -noprompt -storepass "$_password" -keypass "$_password"

    # creating root CA's key and Certificate rsa 2048bit with x509 format
    openssl req -new -newkey rsa:2048 -x509 -keyout "${_work_dir%/}/ca-key" -out "${_work_dir%/}/ca-cert" -days 3650 -config "${_work_dir%/}/openssl.cnf" -passin pass:$_password || return $?

    # create two Java *trustS stores and import CA's cert
    keytool -keystore "${_work_dir%/}/${TRUSTSTORE_FILE}"        -alias CARoot -import -file "${_work_dir%/}/ca-cert" -noprompt -storepass "$_password" || return $?
    keytool -keystore "${_work_dir%/}/${CLIENT_TRUSTSTORE_FILE}" -alias CARoot -import -file "${_work_dir%/}/ca-cert" -noprompt -storepass "$_password" || return $?

    # Create java keystore and generate CSR
    keytool -keystore "${_work_dir%/}/${KEYSTORE_FILE}" -alias localhost -certreq -file "${_work_dir%/}/csr-file" -noprompt -storepass "$_password" || return $?
    # Gnerated signed certification singed by self CA
    openssl x509 -req -CA "${_work_dir%/}/ca-cert" -CAkey "${_work_dir%/}/ca-key" -in "${_work_dir%/}/csr-file" -out "${_work_dir%/}/cert-signed" -days 3650 -CAcreateserial -passin pass:$_password || return $?
    keytool -keystore "${_work_dir%/}/${KEYSTORE_FILE}" -alias CARoot    -import -file "${_work_dir%/}/ca-cert"     -noprompt -storepass "$_password" || return $?
    keytool -keystore "${_work_dir%/}/${KEYSTORE_FILE}" -alias localhost -import -file "${_work_dir%/}/cert-signed" -noprompt -storepass "$_password" || return $?

    _info "copying jks files for $_how_many nodes from $_start_from ..."
    for i in `_docker_seq "$_how_many" "$_start_from"`; do
        ssh root@node$i${_domain_suffix} -t "mkdir -p ${SERVER_KEY_LOCATION%/}"
        scp ${_work_dir%/}/*.jks root@node$i${_domain_suffix}:${SERVER_KEY_LOCATION%/}/
        ssh root@node$i${_domain_suffix} -t "chmod 755 $SERVER_KEY_LOCATION
chmod 440 $SERVER_KEY_LOCATION$KEYSTORE_FILE
chmod 440 $SERVER_KEY_LOCATION$TRUSTSTORE_FILE
chmod 444 $SERVER_KEY_LOCATION$CLIENT_TRUSTSTORE_FILE"
    done
}

function f_nifidemo_add() {
    local __doc__="Deprecated: Add Nifi in HDP"
    local _stack_version="${1-$r_HDP_STACK_VERSION}"
    # https://github.com/abajwa-hw/ambari-nifi-service

    #rm -rf /var/lib/ambari-server/resources/stacks/HDP/'$_stack_version'/services/NIFI
    #TODO: wget http://public-repo-1.hortonworks.com/HDF/centos6/2.x/updates/2.0.1.0/tars/hdf_ambari_mp/hdf-ambari-mpack-2.0.1.0-12.tar.gz
    ssh root@$r_AMBARI_HOST 'yum install git -y
git clone https://github.com/abajwa-hw/ambari-nifi-service.git /var/lib/ambari-server/resources/stacks/HDP/'$_stack_version'/services/NIFI && service ambari-server restart'
}

function f_useradd() {
    local __doc__="Add user"
    local _user="$1"
    local _pwd="$2"

    # should specify home directory just in case?
    useradd -d "/home/$_user/" -s `which bash` -p $(echo "$_pwd" | openssl passwd -1 -stdin) "$_user"
    mkdir "/home/$_user/" && chown "$_user":"$_user" "/home/$_user/"

    if [ -f $HOME/.ssh/id_rsa ] && [ -d "/home/$_user/" ]; then
        mkdir "/home/$_user/.ssh" && chown "$_user":"$_user" "/home/$_user/.ssh"
        cp $HOME/.ssh/id_rsa* "/home/$_user/.ssh/"
        chown "$_user":"$_user" /home/$_user/.ssh/id_rsa*
        chmod 600 "/home/$_user/.ssh/id_rsa"
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

    local _mod_dt="`stat -c%y $_file_path`"
    local _mod_ts=`date -d "${_mod_dt}" +"%Y%m%d-%H%M%S"`

    if _isYes "$_force"; then

        if [[ ! $_file_name =~ "." ]]; then
            _new_file_name="${_file_name}_${_mod_ts}"
        else
            _new_file_name="${_file_name/\./_${_mod_ts}.}"
        fi
    else
        if [[ ! $_file_name =~ "." ]]; then
            _new_file_name="${_file_name}_${_mod_ts}"
        else
            _new_file_name="${_file_name/\./_${_mod_ts}.}"
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
function _isEnoughDisk() {
    local __doc__="Check if entire system or the given path has enough space with GB."
    local _dir_path="${1-/}"
    local _required_gb="$2"
    local _available_space_gb=""

    _available_space_gb=`_freeSpaceGB "${_dir_path}"`

    if [ -z "$_required_gb" ]; then
        echo "${_available_space_gb}GB free space"
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
function _port_wait() {
    local _host="$1"
    local _port="$2"
    local _times="$3"
    local _interval="$4"

    if [ -z "$_times" ]; then
        _times=10
    fi

    if [ -z "$_interval" ]; then
        _interval=5
    fi

    for i in `seq 1 $_times`; do
      sleep $_interval
      nc -z $_host $_port && return 0
      _info "$_host:$_port is unreachable. Waiting..."
    done
    return 1
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
function _isUrl() {
    local _url="$1"

    if [ -z "$_url" ]; then
        return 1
    fi

    if [[ "$_url" =~ $_URL_REGEX ]]; then
        return 0
    fi

    return 1
}
function _split() {
	local _rtn_var_name="$1"
	local _string="$2"
	local _delimiter="${3-,}"
	local _original_IFS="$IFS"
	eval "IFS=\"$_delimiter\" read -a $_rtn_var_name <<< \"$_string\""
	IFS="$_original_IFS"
}
function _trim() {
	local _string="$1"
	echo "${_string}" | sed -e 's/^ *//g' -e 's/ *$//g'
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

    # Forcing not to go to next step.
    echo "Please press 'Ctrl-c' again to exit."
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



### main() ############################################################

if [ "$0" = "$BASH_SOURCE" ]; then
    # parsing command options
    while getopts "r:f:isah" opts; do
        case $opts in
            a)
                _AUTO_SETUP_HDP="Y"
                _SETUP_HDP="Y"
                ;;
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
        exit 1
    fi
    grep -i 'Ubuntu 14.04' /etc/issue.net &>/dev/null
    if [ $? -ne 0 ]; then
        if [ "$g_UNAME_STR" == "Darwin" ]; then
            echo "Detected Mac OS"
            which docker &>/dev/null
            if [ $? -ne 0 ]; then
                echo "Sorry, at this moment, installing docker manually is required for Mac"
                echo "Please check https://docs.docker.com/engine/installation/mac/"
                exit 1
            fi
        else
            _ask "This script may not work with this OS. Are you sure?" "N"
            if ! _isYes; then echo "Bye"; exit; fi
        fi
    fi

    _IS_SCRIPT_RUNNING=true

    if _isYes "$_SETUP_HDP"; then
        if _isYes "$_AUTO_SETUP_HDP" && [ -z "$_RESPONSE_FILEPATH" ]; then
            _RESPONSE_FILEPATH="$g_LATEST_RESPONSE_URL"
        fi
        f_checkUpdate
        p_interview_or_load

        if ! _isYes "$_AUTO_SETUP_HDP"; then
            _ask "Would you like to start setting up this host?" "Y"
            if ! _isYes; then echo "Bye"; exit; fi
            _ask "Would you like to stop all running containers?" "Y"
            if _isYes; then f_docker_stop_all; fi
        else
            _info "Stopping all docker containers..."
            f_docker_stop_all
        fi

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
        f_checkUpdate
        f_loadResp
        p_hdp_start
    else
        usage | less
        exit 0
    fi
else
    _info "You may want to run 'f_loadResp' to load your response file"
fi
