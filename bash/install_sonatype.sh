#!/usr/bin/env bash

usage() {
    cat << END
A sample bash script for setting up and installing NXRM
Tested on CentOS6|CentOS7 against hadoop clusters (HDP)

PREPARATION:
  mkdir -p -m 777 ${_TMP_DIR%/}/${_SERVICE}
  # If you have a license
  scp|cp <your license> ${_TMP_DIR%/}/${_SERVICE}/${_SERVICE}-license.lic
  Copy this script as ${_TMP_DIR%/}/${_SERVICE}/install_${_SERVICE}.sh
  chmod a+x ${_TMP_DIR%/}/${_SERVICE}/install_${_SERVICE}.sh

HELP:
To see help message of a function:
  $BASH_SOURCE -h <function_name>

SCRIPT LIFE CYCLE:
1. Setup one node and Install NXRM (${_NXRM_VER})
  $BASH_SOURCE [-l /path/to/your/license.lic]

2. Install a specif version of  NXRM. Eg.: to install 3.18.1
  $BASH_SOURCE -v 3.18.1

3. TODO: Upgrade or Update the config of the currently used NXRM. -B for NOT taking backup (faster)
  $BASH_SOURCE -U [-v 3.18.1] [-B]

4. TODO: Switch NXRM (stop current NXRM and start another already installed NXRM)
  source $BASH_SOURCE
  f_switch_version          # This shows which versions are installed
  f_switch_version "3181"   # This stops current NXRM and start nexus_3.18.1*

NOTE: Some of global variables can be overwritten by creating .install_${_SERVICE}.conf file.
END
    _list
}


### Global variables #################
[ -z "${_TMP_DIR}" ] && _TMP_DIR="/var/tmp/share"               # Temp/work directory to store various data, such as installer.tar.gz
[ -z "${_BASE_DIR}" ] && _BASE_DIR="/opt/sonatype"
[ -z "${_DEFAULT_PWD}" ] && _DEFAULT_PWD="admin"                # kadmin password, hive metastore DB password etc.
[ -z "${_KADMIN_USR}" ] && _KADMIN_USR="admin/admin"            # Used to create service principal
[ -z "${_KEYTAB_DIR}" ] && _KEYTAB_DIR="/etc/security/keytabs"  # Keytab default location (this is the default for HDP)
[ -z "${_REPO_URL}" ] && _REPO_URL="http://download.sonatype.com/"
[ -z "${_SERVICE}" ] && _SERVICE="sonatype"                     # Default service name|user
[ -z "${_NXRM_PREFIX}" ] && _NXRM_PREFIX="nexus"                # Prefix of NXRM install package name
[ -z "${_NXRM_VER}" ] && _NXRM_VER="3.18.1"                     # Version number mainly used to find the right installer file
[ -z "${_NXRM_LICENSE}" ] && _NXRM_LICENSE="$(ls -1t ${_TMP_DIR%/}/${_SERVICE}/${_SERVICE}-*.lic 2>/dev/null | head -n1)"
[ -z "${_HTTP}" ] && _HTTP="http"
_DOWNLOAD_URL="${_DOWNLOAD_URL-"http://$(hostname -I | awk '{print $1}')/${_SERVICE}/"}"

# TODO: Not in use yet. Whenever new release and not using "01", update below
declare -A _NXRM_MINOR_VERS
_NXRM_MINOR_VERS[3161]="02"
_NXRM_MINOR_VERS[3140]="04"
_NXRM_MINOR_VERS[3100]="04"
_NXRM_MINOR_VERS[380]="02"
# TODO: add more...


### Functions ########################
function f_install_nxrm() {
    local __doc__="Download (if necessary) and install NXRM"
    local _ver="${1:-${_NXRM_VER}}"
    local _license="${2:-${_NXRM_LICENSE}}"
    local _base_dir="${3:-"${_BASE_DIR%/}"}"
    local _usr="${4:-${_SERVICE}}"

    local _updating="${_UPDATING}"
    local _no_backup="${_NO_BACKUP}"

    local _v="$(echo "${_ver}" | sed 's/[^0-9_]//g')"
    local _minor_ver=${_NXRM_MINOR_VERS[${_ver}]}
    local _nxrm_dirname="${_NXRM_PREFIX}-${_ver}-${_minor_ver:-"01"}"
    local _inst_dir="${_base_dir%/}/${_NXRM_PREFIX}-${_ver}"

    if [ ! -d "${_base_dir%/}" ]; then
        mkdir -p "${_base_dir%/}"
        chown ${_usr}: "${_base_dir%/}" || return $?
    fi
    if [ ! -d "${_inst_dir}" ]; then
        sudo -u ${_usr} mkdir -p "${_inst_dir}" || return $?
    fi

    if [[ "${_updating}}" =~ (^y|^Y) ]]; then
        _log "TODO" "Should update/upgrade instead of installing..."
        return 1
    fi

    if [ -d "${_inst_dir%/}/${_nxrm_dirname}" ]; then
        if [[ ! "${_no_backup}" =~ ^(y|Y) ]]; then
            _log "TODO" "${_inst_dir%/}/${_nxrm_dirname} exists. Stop service and should take backup..."
            return 1
        fi
    else
        _download_and_extract "${_REPO_URL%/}/${_NXRM_PREFIX}/${_ver%%.*}/${_nxrm_dirname}-unix.tar.gz" "${_inst_dir}" || return $?
    fi

    # Nexus doesn't need to run any install script, so after extracting, just create a symlink and exit/return
    _symlink ${_inst_dir%/}/${_nxrm_dirname} ${_base_dir%/}/${_NXRM_PREFIX} || return $?
    _symlink ${_inst_dir%/}/sonatype-work ${_base_dir%/}/sonatype-work || return $?
}

function f_install_nxrm_post_tasks() {
    local __doc__="Misc. setups after first install"
    local _base_dir="${1:-"${_BASE_DIR%/}"}"
    local _dir="$(ls -1dt ${_base_dir%/}/sonatype-work/${_NXRM_PREFIX}* 2>/dev/null | head -n1)"

    _log "INFO" "Updating 'admin' password ..."
    f_api_update_pwd "admin" "$(cat ${_dir%/}/admin.password)" "${_DEFAULT_PWD}"
}

function f_start_nxrm() {
    local __doc__="Start NXRM"
    local _base_dir="${1:-"${_BASE_DIR%/}"}"
    local _usr="${2:-${_SERVICE}}"
    local _port="${3:-8081}"
    local _pid="$(_pid_by_port ${_port})"
    if [ -n "${_pid}" ]; then
        _log "WARN" "PID ${_pid} is listening on ${_port}, so not starting."
        return 1
    fi
    local _dir="$(ls -1dt ${_base_dir%/}/sonatype-work/${_NXRM_PREFIX}* 2>/dev/null | head -n1)"
    sudo -u ${_usr} nohup ${_base_dir%/}/${_NXRM_PREFIX}/bin/nexus run &> ${_dir%/}/log/nexus_run.out &
    _wait_by_port "${_port}" || return $?
}

function f_stop_nxrm() {
    local __doc__="Stop NXRM by using port number"
    local _port="${1:-8081}"
    local _pid="$(_pid_by_port ${_port})"
    if [ -z "${_pid}" ]; then
        _log "INFO" "Nothing listening on ${_port}."
        return 0
    fi
    kill ${_pid}
    _wait ${_pid} "Y"
}

function f_api_update_pwd() {
    local __doc__="Update NXRM (admin) user password"
    local _user="$1"
    local _pwd="$2"
    local _new_pwd="$3"
    f_api ":8081/service/rest/beta/security/users/${_user}/change-password" "${_new_pwd}" "PUT" "${_user}" "${_pwd}" 2>/dev/null
}

function f_api() {
    local __doc__="NXRM API wrapper"
    local _port_path="${1}"
    local _data="${2}"
    local _method="${3}"
    local _usr="${4:-admin}"
    local _pwd="${5-${_DEFAULT_PWD}}"

    local _user_pwd="${_usr}"
    [ -n "${_pwd}" ] && _user_pwd="${_usr}:${_pwd}"
    [ -n "${_data}" ] && [ -z "${_method}" ] && _method="POST"
    [ -z "${_method}" ] && _method="GET"
    # TODO: check if GET and DELETE *can not* use Content-Type json?
    local _content_type="Content-Type: application/json"
    [ "${_data:0:1}" != "{" ] && _content_type="Content-Type: text/plain"

    if [ -z "${_data}" ]; then
        # GET and DELETE *can not* use Content-Type json
        curl -s -f -u "${_user_pwd}" -k "${_HTTP:-"http"}://$(hostname -f):${_port_path#:}" -X ${_method} || return $?
    else
        curl -s -f -u "${_user_pwd}" -k "${_HTTP:-"http"}://$(hostname -f):${_port_path#:}" -X ${_method} -H "${_content_type}" -d ${_data} || return $?
    fi | python -mjson.tool
}

function f_setup_nxrm_HA() {
    local __doc__="Setup NXRM for HA (run f_install_nxrm first)"
    local _first_node="${1:-${_NXRM_LICENSE}}"
    local _license="${2:-${_NXRM_LICENSE}}"
    local _usr="${3:-${_SERVICE}}"
    local _base_dir="${4:-"${_BASE_DIR%/}"}"

    # Because of using symlink, it should be only one directory under sonatype-work dir.
    local _dir="$(ls -1dt ${_base_dir%/}/sonatype-work/${_NXRM_PREFIX}* 2>/dev/null | head -n1)" || return $?
    if [ -z "${_dir}" ] || [ ! -d "${_dir%/}/etc" ]; then
        _log "INFO" "This NXRM hasn't been initialised. Starting ..."
        f_start_nxrm || return $?
        _dir="$(ls -1dt ${_base_dir%/}/sonatype-work/${_NXRM_PREFIX}* 2>/dev/null | head -n1)" || return $?
        [ -z "${_dir}" ] && return 1
    fi

    [ ! -f ${_dir%/}/etc/nexus.properties ] && sudo -u ${_usr} touch ${_dir%/}/etc/nexus.properties
    _upsert ${_dir%/}/etc/nexus.properties "nexus.clustered" "true" || return $?
    _upsert ${_dir%/}/etc/nexus.properties "nexus.licenseFile" "${_license}" || return $?
    # NOTE: need to customise Hazelcast?
    #[ ! -d "${_etc_dir%/}/fabric" ] && sudo -u ${_usr} mkdir "${_etc_dir%/}/fabric"

    _log "INFO" "Restarting NXRM..."
    local _share_blob="${_TMP_DIR%/}/${_SERVICE}/blobs"
    if [[ "${_first_node}" =~ ^(y|Y) ]]; then
        if [ -d "${_share_blob}/default" ]; then
            _log "ERROR" "First node but '${_share_blob}/default' exits."
            return 1
        fi
        if ! f_api ":8081/service/rest/beta/blobstores/file/default" "{\"file\":{\"path\":\"${_share_blob%/}/default\"}}" "PUT"; then
            _log "WARN" "Check ${_HTTP:-"http"}://`hostname -f`:8081/#admin/repository/blobstores:default"
            # TODO: NEXUS-20517 no blobstore API yet?
            sleep 5 #return 1
        fi
        if [ ! -d "${_share_blob}" ]; then
            sudo -u ${_usr} mkdir -p -m 777 "${_share_blob}" || return $?
        fi
    fi
    f_stop_nxrm || return $?
    if [[ "${_first_node}" =~ ^(y|Y) ]]; then
        [ -f "${_share_blob}/default" ] && mv ${_share_blob}/default ${_share_blob}/default.bak
        cp -pR ${_dir%/}/blobs/default ${_share_blob}/ || return $?
    fi
    f_start_nxrm || return $?
    f_api ":8081/service/rest/v1/nodes" > /tmp/f_setup_nxrm_HA_$$.json
    # TODO: lazy to parse the json file
    local _nodeIdentity_line="$(cat /tmp/f_setup_nxrm_HA_$$.json | grep "/`hostname -I | awk '{print $1}'`:" -B 1 | grep "nodeIdentity" | tr -d '[:space:]')"
    local _socketAddress_line="$(cat /tmp/f_setup_nxrm_HA_$$.json | grep "/`hostname -I | awk '{print $1}'`:" | tr -d '[:space:]')"
    # "nodes" api doesn't need to send entire nodes information???
    f_api ":8081/service/rest/v1/nodes" "{${_nodeIdentity_line%,},${_socketAddress_line%,},\"friendlyName\":\"`hostname -f`\"}" "PUT"
    _log "INFO" "Check ${_HTTP:-"http"}://`hostname -f`:8081/#admin/system/nodes"
}


### Reusable (non business logic) functions ##################
function _download_and_extract() {
    local _url="$1"
    local _extract_to="${2}"
    local _save_dir="${3:-"${_TMP_DIR%/}/${_SERVICE}"}"
    local _as_user="${4:-${_SERVICE:-$USER}}"
    local _file="$5"
    [ -z "${_file}" ] && _file="`basename "${_url}"`"

    if [ ! -s "${_save_dir%/}/${_file}" ]; then
        _log "INFO" "No ${_save_dir%/}/${_file}. Downloading from ${_url} ..."; sleep 1
        sudo -u ${_as_user} curl -f --connect-timeout 10 --retry 2 -C - -o "${_save_dir%/}/${_file}" -L "${_url}" || return $?
    fi

    # If no extract directory, just download.
    if [ -n "${_extract_to}" ]; then
        if [ ! -d "${_extract_to}" ]; then
            mkdir -p "${_extract_to}" || return $?
            chown ${_as_user}: "${_extract_to}"
        fi
        sudo -u ${_as_user} tar -xf ${_save_dir%/}/${_file} -C ${_extract_to%/}/ || return $?
        _log "INFO" "Extracted ${_file} into ${_extract_to}"; sleep 1
    fi
}

function _pid_by_port() {
    local _port="$1"
    [ -z "${_port}" ] && return 1
    #lsof -ti:${_port} -sTCP:LISTEN
    netstat -lnp | grep -w "0.0.0.0:${_port}" | awk '{print $7}' | grep -oE '[0-9]+'
}

function _wait() {
    local _pid="$1"
    local _is_stopping="$2"
    local _times="${3:-10}"
    local _interval="${4:-5}"

    [ -z "${_pid}" ] && return 1
    for i in `seq 1 ${_times}`; do
        if [[ "${_is_stopping}" =~ ^(y|Y) ]] && [ ! -d /proc/${_pid} ]; then
            sleep 1 # just in case...
            return 0
        fi
        if [[ ! "${_is_stopping}" =~ ^(y|Y) ]] && [ -d /proc/${_pid} ]; then
            sleep 1 # just in case...
            return 0
        fi
        sleep ${_interval}
    done
    return 1
}

function _wait_by_port() {
    local _port="$1"
    local _is_stopping="$2"
    local _times="${3:-21}"
    local _interval="${4:-5}"

    local _pid=""
    [ -z "${_port}" ] && return 1
    for i in `seq 1 ${_times}`; do
        _pid="$(_pid_by_port "${_port}")"
        if [[ "${_is_stopping}" =~ ^(y|Y) ]] && [ ! -n "${_pid}" ]; then
            sleep 1 # just in case...
            return 0
        fi
        if [[ ! "${_is_stopping}" =~ ^(y|Y) ]] && [ -n "${_pid}" ]; then
            sleep 1 # just in case...
            return 0
        fi
        sleep ${_interval}
    done
    return 1
}

function _symlink() {
    local _source="$1"
    local _symlink_path="$2"
    if [ -e "${_symlink_path}" ]; then
        if [ ! -L "${_symlink_path}" ]; then
            _log "ERROR" "${_symlink_path} should be a symbolic link."
            return 1
        else
            rm -f "${_symlink_path}" || return $?
        fi
    fi
    ln -s ${_source} "${_symlink_path}" || return $?
}

function _upsert() {
    local __doc__="Modify the given file with given name and value."
    local _file_path="$1"
    local _name="$2"
    local _value="$3"
    local _if_not_exist_append_after="$4"    # This needs to be a line, not search keyword
    local _between_char="${5-=}"
    local _comment_char="${6-#}"
    # NOTE & TODO: Not sure why /\\\&/ works, should be /\\&/ ...
    local _name_esc_sed=`echo "${_name}" | sed 's/[][\.^$*\/"&]/\\\&/g'`
    local _name_esc_sed_for_val=`echo "${_name}" | sed 's/[\/]/\\\&/g'`
    local _name_escaped=`printf %q "${_name}"`
    local _value_esc_sed=`echo "${_value}" | sed 's/[\/]/\\\&/g'`
    local _value_escaped=`printf %q "${_value}"`

    [ ! -f "${_file_path}" ] && return 11
    # Make a backup
    local _file_name="`basename "${_file_path}"`"
    [ ! -f "/tmp/${_file_name}.orig" ] && cp -p "${_file_path}" "/tmp/${_file_name}.orig"

    # If name=value is already set, all good
    grep -qP "^\s*${_name_escaped}\s*${_between_char}\s*${_value_escaped}\b" "${_file_path}" && return 0

    # If name= is already set, replace all with /g
    if grep -qP "^\s*${_name_escaped}\s*${_between_char}" "${_file_path}"; then
        sed -i -r "s/^([[:space:]]*${_name_esc_sed})([[:space:]]*${_between_char}[[:space:]]*)[^${_comment_char} ]*(.*)$/\1\2${_value_esc_sed}\3/g" "${_file_path}"
        return $?
    fi

    # If name= is not set and no _if_not_exist_append_after, just append in the end of line (TODO: it might add extra newline)
    if [ -z "${_if_not_exist_append_after}" ]; then
        echo -e "\n${_name}${_between_char}${_value}" >> ${_file_path}
        return $?
    fi

    # If name= is not set and _if_not_exist_append_after is set, inserting
    if [ -n "${_if_not_exist_append_after}" ]; then
        local _if_not_exist_append_after_sed="`echo "${_if_not_exist_append_after}" | sed 's/[][\.^$*\/"&]/\\\&/g'`"
        sed -i -r "0,/^(${_if_not_exist_append_after_sed}.*)$/s//\1\n${_name_esc_sed_for_val}${_between_char}${_value_esc_sed}/" ${_file_path}
        return $?
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

function _help() {
    local _function_name="$1"
    local _show_code="$2"
    local _doc_only="$3"

    if [ -z "$_function_name" ]; then
        echo "help <function name> [Y]"
        echo ""
        _list "func"
        echo ""
        return
    fi

    local _output=""
    if [[ "$_function_name" =~ ^[fp]_ ]]; then
        local _code="$(type $_function_name 2>/dev/null | grep -v "^${_function_name} is a function")"
        if [ -z "$_code" ]; then
            echo "Function name '$_function_name' does not exist."
            return 1
        fi

        eval "$(echo -e "${_code}" | awk '/__doc__=/,/;/')"
        if [ -z "$__doc__" ]; then
            _output="(No help information in function name '$_function_name')\n"
        else
            _output="$__doc__"
        fi

        if [[ "${_doc_only}" =~ (^y|^Y) ]]; then
            echo -e "${_output}"; return
        fi

        local _params="$(type $_function_name 2>/dev/null | grep -iP '^\s*local _[^_].*?=.*?\$\{?[1-9]' | grep -v awk)"
        if [ -n "$_params" ]; then
            _output="${_output}Parameters:\n"
            _output="${_output}${_params}\n\n"
        fi
        if [[ "${_show_code}" =~ (^y|^Y) ]] ; then
            _output="${_output}${_code}\n"
            echo -e "${_output}" | less
        else
            [ -n "$_output" ] && echo -e "${_output}"
        fi
    else
        echo "Unsupported Function name '$_function_name'."
        return 1
    fi
}

function _list() {
    local _name="$1"
    #local _width=$(( $(tput cols) - 2 ))
    local _tmp_txt=""
    # TODO: restore to original posix value
    set -o posix

    if [[ -z "$_name" ]]; then
        (for _f in `typeset -F | grep -P '^declare -f [fp]_' | cut -d' ' -f3`; do
            #eval "echo \"--[ $_f ]\" | gsed -e :a -e 's/^.\{1,${_width}\}$/&-/;ta'"
            _tmp_txt="`help "$_f" "" "Y"`"
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


### mains ########################
function start_sonatype() {
    local __doc__="Start services. Used by setup_standalone.sh"
    f_start_nxrm
}

function stop_sonatype() {
    local __doc__="Stop services. Used by setup_standalone.sh"
    f_stop_nxrm
}

function main() {
    # TODO: need if conditions for different apps
    f_install_nxrm || return $?
    f_start_nxrm || return $?
    f_install_nxrm_post_tasks # || return $?

    _log "INFO" "Completed."
}

if [ "$0" = "$BASH_SOURCE" ]; then
    if [[ "$1" =~ ^(-h|help)$ ]]; then
        if [[ "$2" =~ ^[fp]_ ]]; then
            _help "$2" "Y"
        else
            usage | less
        fi
        exit
    fi

    while getopts "Bl:u:Uv:" opts; do
        case $opts in
            B)
                _NO_BACKUP="Y"
                ;;
            l)
                _LICENSE="$OPTARG"
                ;;
            u)
                _USER="$OPTARG"
                ;;
            U)
                # TODO updating/upgrading
                _UPDATING="Y"
                ;;
            v)
                # Add other software's _XXXX_VER in here
                _NXRM_VER="$OPTARG"
                ;;
        esac
    done

    #set -x
    main
fi