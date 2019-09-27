#!/usr/bin/env bash

usage() {
    cat << END
A sample bash script for setting up and installing NXRM
Tested on CentOS6|CentOS7 against hadoop clusters (HDP)

PREPARATION:
  mkdir -p -m 777 /var/tmp/share/${_SERVICE}
  # If you have a license
  scp|cp <your license> /var/tmp/share/${_SERVICE}/${_SERVICE}-license.lic
  Copy this script as /var/tmp/share/${_SERVICE}/install_${_SERVICE}.sh
  chmod a+x /var/tmp/share/${_SERVICE}/install_${_SERVICE}.sh

HELP:
To see help message of a function:
  $BASH_SOURCE -h <function_name>

SCRIPT LIFE CYCLE:
1. Setup one node and Install NXRM (${_VER})
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
[ -z "${_NXRM_NAME}" ] && _NXRM_NAME="nexus"                    #
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
    local _ver="${1:-${_NXRM_VER:-$_VER}}"
    local _license="${2:-${_NXRM_LICENSE}}"
    local _base_dir="${3:-"${_BASE_DIR%/}"}"
    local _usr="${4:-${_SERVICE}}"

    local _updating="${_UPDATING}"
    local _no_backup="${_NO_BACKUP}"

    local _ver_int="$(echo "${_ver}" | sed 's/[^0-9_]//g')"
    local _minor_ver=${_NXRM_MINOR_VERS[${_ver}]}
    local _nxrm_dirname="${_NXRM_NAME}-${_ver}-${_minor_ver:-"01"}"
    local _inst_dir="${_base_dir%/}/${_NXRM_NAME}-${_ver}"

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
            _log "TODO" "Stop service and should take backup..."
            return 1
        fi
    else
        _download_and_extract "${_REPO_URL%/}/${_NXRM_NAME}/${_ver%%.*}/${_nxrm_dirname}-unix.tar.gz" "${_inst_dir}" || return $?
    fi

    # Nexus doesn't need to run any install script, so after extracting, just create a symlink and exit/return
    _symlink ${_inst_dir%/}/${_nxrm_dirname} ${_base_dir%/}/${_NXRM_NAME} || return $?
    _symlink ${_inst_dir%/}/sonatype-work ${_base_dir%/}/sonatype-work || return $?
}

function f_start_nxrm() {
    local _base_dir="${1:-"${_BASE_DIR%/}"}"
    local _usr="${2:-${_SERVICE}}"
    local _port="${3:-8081}"
    local _pid="$(_pid_by_port ${_port})"
    if [ -n "${_pid}" ]; then
        _log "WARN" "PID ${_pid} is listening on ${_port}, so not starting."
        return 1
    fi
    local _log_dir="$(ls -1dt ${_base_dir%/}/sonatype-work/${_NXRM_NAME}*/log 2>/dev/null | head -n1)"
    sudo -u ${_usr} nohup ${_base_dir%/}/${_NXRM_NAME}/bin/nexus run &> ${_log_dir%/}/nexus_run.out &
}

function f_stop_nxrm() {
    local _port="${1:-8081}"
    local _pid="$(_pid_by_port ${_port})"
    if [ -z "${_pid}" ]; then
        _log "INFO" "Nothing listening on ${_port}."
        return 0
    fi
    kill ${_pid}
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

    if [ -d "${_extract_to}" ]; then
        sudo -u ${_as_user} tar -xf ${_save_dir%/}/${_file} -C ${_extract_to%/}/ || return $?
        _log "INFO" "Extracted ${_file} into ${_extract_to}"; sleep 1
    fi
}

function _pid_by_port() {
    #lsof -ti:$1 -sTCP:LISTEN
    netstat -lnp | grep -w "0.0.0.0:$1" | awk '{print $7}' | grep -oE '[0-9]+'
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


### main ########################
main() {
    # TODO: need if conditions for different apps
    f_install_nxrm
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
                _VER="$OPTARG"
                ;;
        esac
    done

    #set -x
    main
fi