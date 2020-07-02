#!/usr/bin/env bash
# Utility type / reusable functions
# NOTE: Overwriting sourced function in bash is hard, so need to be careful when add a new function.

__PID="$$"
__LAST_ANSWER=""
__TMP="/tmp"

function _check_update() {
    local _file_path="${1:-${BASH_SOURCE}}"
    local _remote_repo="${2:-"https://raw.githubusercontent.com/hajimeo/samples/master/bash/"}"
    local _force="${3:-"Y"}"        # Currently default is force
    local _mins_old="${4-"480"}"    # 8 hours

    local _file_name="`basename ${_file_path}`"
    local _tmp_file="${__TMP%/}/${_file_name}_$(date +"%Y%m%d%H%M%S")"
    if [ -f "${_file_path}" ]; then
        if [[ "${_mins_old}" =~ ^[0-9]+$ ]]; then
            # stat is different between Mac and Linux
            _file_path="$(find ${_file_path} -mmin +${_mins_old} -print)"
            if [ -z "${_file_path}" ]; then
                _log "DEBUG" "${_file_path} is not older than ${_mins_old} minutes"
                return 0
            fi
        fi

        # If URL ends with / , append the filename
        [ "${_remote_repo: -1}" == "/" ] && _remote_repo="${_remote_repo%/}/${_file_name}"
        # Currently max timeout is set to 3 seconds
        local _remote_length=`curl -m 3 -s -k -L --head "${_remote_repo}" | grep -i '^Content-Length:' | awk '{print $2}' | tr -d '\r'`
        local _local_length=`wc -c <${_file_path}`
        # If the remote file size is suspiciously different, not taking it
        if [ -z "${_remote_length}" ] || [ "${_remote_length}" -lt $(( ${_local_length} / 2 )) ] || [ ${_remote_length} -eq ${_local_length} ]; then
            _log "DEBUG" "Remote length(size) is suspicious: ${_remote_length} (vs. ${_local_length}). Ignoring this remote."
            return 0
        fi

        # If can't take a backup, not proceeding.
        _backup "${_file_path}" || return $?
    fi

    if ! _isYes "${_force}"; then
        local _shall_update=""
        _ask "New file is available. Would you like to update ${_file_path}?" "Y" "_shall_update"
        if ! _isYes; then
            [ -s "${_file_path}" ] && touch ${_file_path}
            return 0
        fi
    fi
    if curl -s -k -L -f --retry 3 "${_remote_repo}" -o "${_tmp_file}"; then
        mv -f "${_tmp_file}" "${_file_path}" || return $?
    fi
    _log "INFO" "${_file_path} has been updated. (if not new file) a backup is under ${__TMP%/}/."
}

function _save_resp() {
    local __doc__="Save current responses(answers) in memory into a file."
    local _file_path="${1}"

    if [ -z "${_file_path}" ]; then
        local _default_file_path="./$(basename "$BASH_SOURCE" ".sh")_$(date +'%Y%m%d%H%M%S').resp"
        _ask "Response file path" "${_default_file_path}" "_file_path"
    fi

    if [ -s "${_file_path}" ]; then
        local _file_overwrite=""
        _ask "${_file_path} exists. Overwrite?" "Y" "_file_overwrite"
        if ! _isYes; then
            _log "INFO" "Not saving the response file."
            return 0
        fi
    else
        _backup "${_file_path}"
    fi

    echo "# Saved at `date`" > ${_file_path} || return $?
    for _v in $(set | grep -E -o "^r_.+?[^\s]="); do
        _new_v="${_v%=}"
        echo "${_new_v}=\"${!_new_v}\"" >> ${_file_path} || return $?
    done
    _log "INFO" "Saved ${_file_path}"
}

function _load_resp() {
    local __doc__="Load responses(answers) from given file path or from default location."
    local _file_path="${1}"

    if [ -z "${_file_path}" ]; then
        _log "Available response files:
$(ls -1t ./*.resp)"
        local _default_file_path="$(ls -1t ./*.resp | head -n1)"
        _file_path=""
        _ask "Type a response file path" "$_default_file_path" "_file_path" "N" "Y"
    fi

    if [ ! -r "${_file_path}" ]; then
        _log "ERROR" "Not a readable response file: ${_file_path}"
        return 1
    fi

    # Note: somehow "source <(...)" does noe work, so that created tmp file.
    grep -P -o '^r_.+[^\s]=\".*?\"' ${_file_path} > .${FUNCNAME}_${__PID}.tmp || return $?
    source .${FUNCNAME}_${__PID}.tmp || return $?
    rm -f .${FUNCNAME}_${__PID}.tmp  # clean up the temp file
    touch ${_file_path} # To update modified datetime
    _log "INFO" "Loaded $_file_path"
}

function _b64_url_enc() {
    python -c "import base64, urllib; print(urllib.quote(base64.urlsafe_b64encode('$1')))"
    #python3 -c "import base64, urllib.parse; print(urllib.parse.quote(base64.urlsafe_b64encode('$1'.encode('utf-8')), safe=''))"
}

function _sed() {
    # To support Mac...
    local _cmd="sed"; which gsed &>/dev/null && _cmd="gsed"
    ${_cmd} "$@"
}

function _pid_by_port() {
    local _port="$1"
    [ -z "${_port}" ] && return 1
    # Some Linux doesn't have 'lsof'
    #lsof -ti:${_port} -sTCP:LISTEN
    netstat -t4lnp | grep -w "0.0.0.0:${_port}" | awk '{print $7}' | grep -oE '[0-9]+'
}

function _wait_url() {
    local _url="${1}"
    local _times="${2:-30}"
    local _interval="${3:-6}"
    [ -z "${_url}" ] && return 99

    for i in `seq 1 ${_times}`; do
        # NOTE: --retry-connrefused is from curl v 7.52.0
        if curl -f -s -I -L -k -m1 --retry=0 "${_url}" &>/dev/null; then
            return 0
        fi
        _log "DEBUG" "${_url} is unreachable. Waiting for ${_interval} secs ($i/${_times})..."
        sleep ${_interval}
    done
    return 1
}

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
function _isYes() {
    local _answer="$1"
    [ $# -eq 0 ] && _answer="${__LAST_ANSWER}"
    [[ "${_answer}" =~ ^[yY] ]] && return 0
    return 1
}

function _backup() {
    local _file_path="$1"
    local _force="$2"
    local _backup_dir="${3:-"${__TMP%/}"}"

    if [ ! -e "${_file_path}" ]; then
        _log "WARN" "No backup created as $_file_path does not exist."
        return 0
    fi

    # Mac's stat is different, and as using cp -p, wouldn't need to use below anyway
    #local _mod_ts=`date -d "`stat -c%y $_file_path`" +"%Y%m%d-%H%M%S"`
    local _mod_ts="`date +"%Y%m%d-%H%M%S"`"
    local _file_name="`basename $_file_path`"
    local _new_file_name="${_file_name}_${_mod_ts}"
    if ! _isYes "${_force}"; then
        if [ -e "${_backup_dir%/}/${_new_file_name}" ]; then
            _log "WARN" "No new backup as $_file_name already exists."
            return 0
        fi
    fi

    if [ ! -d "${_backup_dir}" ]; then
        if _isYes "${_force}"; then
            mkdir -p "${_backup_dir}" || return $?
        else
            _log "ERROR" "No backup dir:${_backup_dir}"
            return 1
        fi
    fi
    cp -p ${_file_path} ${_backup_dir%/}/${_new_file_name} || return $?
    _log "DEBUG" "Backup-ed ${_file_path} to ${_backup_dir%/}/${_new_file_name}"
}

function _log() {
    [ "$1" == "DEBUG" ] && ! ${_DEBUG} && return
    # At this moment, outputting to STDERR
    if [ -n "${_LOG_FILE_PATH}" ]; then
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%Sz')] $@" | tee -a ${_LOG_FILE_PATH}
    else
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%Sz')] $@"
    fi 1>&2
}
