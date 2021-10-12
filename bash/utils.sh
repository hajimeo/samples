#!/usr/bin/env bash
# Utility type / reusable functions
# source /dev/stdin <<< "$(curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils.sh --compressed)"

__PID="$$"
__LAST_ANSWER=""
__TMP=${__TMP:-"/tmp"}
if [ "`uname`" = "Darwin" ] && [ -z "${_WORK_DIR}" ]; then
    _WORK_DIR="$HOME/share"
else
    _WORK_DIR="/var/tmp/share"
fi
_IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
_IP_RANGE_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(/[0-3]?[0-9])$'
_HOSTNAME_REGEX='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
_URL_REGEX='(https?|ftp|file|svn)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'


function _log() {
    local _log_file="${_LOG_FILE_PATH:-"/dev/null"}"
    local _is_debug="${_DEBUG:-false}"
    if [ "$1" == "DEBUG" ] && ! ${_is_debug}; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> ${_log_file}
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a ${_log_file}
    fi 1>&2 # At this moment, outputting to STDERR
}

function _find_recent() {
    local __doc__="Find recent (log) files"
    local _dir="${1}"
    local _file_glob="${2:-"*.log"}"
    local _follow_symlink="${3:-"Y"}"
    local _base_dir="${4:-"${_BASE_DIR:-"."}"}" # the global env variable _BASE_DIR is set, using.
    local _mmin="${5-"-60"}"
    if [ ! -d "${_dir}" ]; then
        _dir=$(if [[ "${_follow_symlink}" =~ ^(y|Y) ]]; then
            realpath $(find -L ${_base_dir%/} -type d \( -name log -o -name logs \) | tr '\n' ' ') | sort | uniq | tr '\n' ' '
        else
            find ${_base_dir%/} -type d \( -name log -o -name logs \)| tr '\n' ' '
        fi 2>/dev/null | tail -n1)
    fi
    [ -n "${_mmin}" ] && _mmin="-mmin ${_mmin}"
    if [[ "${_follow_symlink}" =~ ^(y|Y) ]]; then
        local _files_oneline="$(find -L ${_dir} -type f -name "${_file_glob}" ${_mmin} | tr '\n' ' ')"
        [ -n "${_files_oneline}" ] && realpath ${_files_oneline} | sort | uniq | tr '\n' ' '
    else
        find ${_dir} -type f -name "${_file_glob}" ${_mmin} | tr '\n' ' '
    fi
}

function _tail_logs() {
    local __doc__="Tail log files"
    local _log_file_glob="${1:-"*.log"}"
    local _log_dir="${2}"
    local _files_oneline=$(_find_recent "${_log_dir}" "${_log_file_glob}")
    if [ -z "${_files_oneline}" ]; then
        _log "WARN" "No files to tail with $@"
        return 0
    fi
    tail -n20 -f $(_find_recent "${_log_dir}" "${_log_file_glob}")
}

function _grep_logs() {
    local __doc__="Grep (recent) log files"
    local _search_regex="${1}"
    local _log_dir="${2}"
    local _log_file_glob="${3:-"*.log"}"
    local _grep_opts="${4:-"-IrsP"}"
    grep ${_grep_opts} "${_search_regex}" $(_find_recent "${_log_dir}" "${_log_file_glob}")
}


function _help() {
    local _function_name="$1"
    local _show_code="$2"
    local _doc_only="$3"

    if [ -z "$_function_name" ]; then
        echo "_help <function name> [Y]"
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
            _tmp_txt="`_help "$_f" "" "Y"`"
            printf "%-28s%s\n" "$_f" "$_tmp_txt"
        done)
    elif [[ "$_name" =~ ^func ]]; then
        typeset -F | grep '^declare -f [fp]_' | cut -d' ' -f3
    elif [[ "$_name" =~ ^glob ]]; then
        set | grep "^[g]_"
    elif [[ "$_name" =~ ^resp ]]; then
        set | grep "^[r]_"
    fi
}

# To test: touch -d "9 hours ago" xxxxx.sh
function _check_update() {
    local _file_path="${1}"
    local _remote_repo="${2:-"https://raw.githubusercontent.com/hajimeo/samples/master/bash/"}" # should end with "/"
    local _force="${3:-"Y"}"        # Currently default is force (not asking)
    local _mins_old="${4-"480"}"    # 8 hours

    local _file_name="`basename ${_file_path}`"
    local _tmp_file="${__TMP%/}/${_file_name}_$(date +"%Y%m%d%H%M%S")"
    # If URL ends with / , append the filename
    [ "${_remote_repo: -1}" == "/" ] && _remote_repo="${_remote_repo%/}/${_file_name}"
    if [ -f "${_file_path}" ]; then
        if [[ "${_mins_old}" =~ ^[0-9]+$ ]]; then
            # stat is different between Mac and Linux, and 2>/dev/null is for hiding "Permission denied" errors
            _file_path="$(find ${_file_path} -mmin +${_mins_old} -print 2>/dev/null)"
            if [ -z "${_file_path}" ]; then
                _log "DEBUG" "${_file_path} is not older than ${_mins_old} minutes"
                return 0
            fi
        fi

        # Currently max timeout is set to 3 seconds
        local _remote_length=`curl -m 3 -s -k -L --head "${_remote_repo}" | grep -i '^Content-Length:' | awk '{print $2}' | tr -d '\r'`
        local _local_length=`wc -c <${_file_path}`
        # If the remote file size is suspiciously different, not taking it
        if [ -z "${_remote_length}" ] || [ "${_remote_length}" -lt $(( ${_local_length} / 2 )) ] || [ ${_remote_length} -eq ${_local_length} ]; then
            _log "DEBUG" "Remote length(size) is same or suspicious: ${_remote_length} (vs. ${_local_length}). Ignoring this remote."
            return 0
        fi
    fi

    if ! _isYes "${_force}"; then
        _ask "New file is available. Would you like to update ${_file_path}?" "Y"
        if ! _isYes; then
            [ -s "${_file_path}" ] && touch ${_file_path}
            return 0
        fi
    fi
    if curl -s -k -L -f --retry 3 --compressed "${_remote_repo}" -o "${_tmp_file}"; then
        if [ -f "${_file_path}" ]; then
            # If can't take a backup, not proceeding.
            _backup "${_file_path}" || return $?

            chmod --reference=${_file_path} ${_tmp_file}
            chown --reference=${_file_path} ${_tmp_file}
        fi
        mv -f "${_tmp_file}" "${_file_path}" || return $?
    fi
    _isYes "${_force}" || _log "INFO" "${_file_path} has been updated. If this is not a new file, a backup is under ${__TMP%/}/."
}

function _save_resp() {
    local __doc__="Save current responses(answers) in memory into a file."
    local _file_path="${1}"
    local _prefix="${2:-"$(hostname -s)"}"

    if [ -z "${_file_path}" ]; then
        local _default_file_path="./${_prefix}_$(date +'%Y%m%d%H%M%S').resp"
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
        local _default_file_path="$(ls -1t ./*.resp 2>/dev/null | head -n1)"
        if [ -n "${_default_file_path}" ]; then
            echo "Available response files under current directory:
$(ls -1t ./*.resp)"
        fi
        _ask "Type a response file path" "$_default_file_path" "_file_path" "N" "Y"
    fi

    if [ ! -r "${_file_path}" ]; then
        _log "ERROR" "Not a readable response file: ${_file_path}"
        return 1
    fi

    # Note: "source <(...)" does noe work with older bash (Mac), so that created tmp file.
    grep -oE '^r_.+[^\s]=\".*?\"' ${_file_path} > .${FUNCNAME}_${__PID}.tmp || return $?
    source .${FUNCNAME}_${__PID}.tmp || return $?
    rm -f .${FUNCNAME}_${__PID}.tmp  # clean up the temp file
    touch ${_file_path} # To update modified datetime
    _log "INFO" "Loaded $_file_path"
}

function _update_hosts_file() {
    local _fqdn="$1"
    local _ip="$2"
    local _file="${3:-"/etc/hosts"}"
    local _is_beginning="${4}"

    if [ -z "${_fqdn}" ]; then
        _log "ERROR" "hostname (FQDN) is required"; return 11
    fi
    local _name="`echo "${_fqdn}" | cut -d"." -f1`"
    # Checking if this combination is already in the hosts file. TODO: this regex is not perfect
    local _old_ip="$(_sed -nr "s/^([0-9.]+).*\s${_fqdn}.*$/\1/p" ${_file})"

    if [ -z "${_ip}" ]; then
        if [[ ! "${_is_beginning}" =~ ^(y|Y) ]] || [ -z "${_old_ip}" ]; then
            _log "ERROR" "IP is required"; return 12
        else
            _log "INFO" "Using ${_old_ip} for IP"
            _ip="${_old_ip}"
        fi
    else
        # Already configured, so do nothing.
        [ "${_old_ip}" = "${_ip}" ] && return 0
    fi

    # Take backup before modifying
    _backup ${_file} || return $?

    local _tmp_file="`mktemp`"
    cp -f ${_file} ${_tmp_file} || return $?

    if [[ ! "${_is_beginning}" =~ ^(y|Y) ]]; then
        # Remove all lines contain hostname or IP. NOTE: sudo _sed won't work
        _sed -i -r "/\s${_fqdn}\s+${_name}\s?/d" ${_tmp_file}
        _sed -i -r "/\s${_fqdn}\s?/d" ${_tmp_file}
        _sed -i -r "/^${_ip}\s?/d" ${_tmp_file}
    fi

    # This shouldn't match but just in case
    [ -n "${_old_ip}" ] && _sed -i -r "/^${_old_ip}\s?/d" ${_tmp_file}

    if [[ ! "${_is_beginning}" =~ ^(y|Y) ]]; then
        # Append in the end of file
        # it seems sed a (append) does not work if file is empty
        #_sed -i -e "\$a${_ip} ${_fqdn} ${_name}" ${_tmp_file}
        echo "${_ip} ${_fqdn} ${_name}" >> ${_tmp_file}
    else
        # as _is_beginning is Y, adding this host before other hosts
        _sed -i "/^${_ip}\s/ s/${_ip}\s/${_ip} ${_fqdn} /" ${_tmp_file}
    fi

    # Some OS such as Mac is hard to modify /etc/hosts file but seems below works
    sudo -n true    # this outputs 'sudo: a password is required'
    cat ${_tmp_file} | sudo tee ${_file} >/dev/null
}

function _url_enc() {
    python -c "try:
    from urllib import parse
except ImportError:
    import urllib as parse
print(parse.quote('$1'))"
}

function _b64_url_enc() {
    python -c "import base64
try:
    from urllib import parse
    print(parse.quote(base64.urlsafe_b64encode('$1'.encode('utf-8')), safe=''))
except ImportError:
    import urllib as parse
    print(parse.quote(base64.urlsafe_b64encode('$1')))"
}

function _deob() {
    local _f="$1"
    local _u="${2:-"${USER}"}"
    cat ${_f} | openssl enc -aes-128-cbc -md sha256 -salt -pass pass:${_u} -d 2>/dev/null
}

function _trim() {
    local _string="$1"
    echo "${_string}" | _sed -e 's/^ *//g' -e 's/ *$//g'
}

# For For loop
function _split() {
    local _string="$1"
    local _delimiter="${2:-","}"
    echo "${_string}" | sed "s/${_delimiter}/ /g"
}

function _escape() {
    local _string="$1"
    printf %q "${_string}"
}

function _sed() {
    local _cmd="sed"; which gsed &>/dev/null && _cmd="gsed"
    ${_cmd} "$@"
}

function _grep() {
    local _cmd="grep"; which ggrep &>/dev/null && _cmd="ggrep"
    ${_cmd} "$@"
}

function _pid_by_port() {
    local _port="$1"
    [ -z "${_port}" ] && return 1
    # Some Linux doesn't have 'lsof' + no root user can't see all, but Mac's netstat is very different so using only if Mac...
    if [ "`uname`" = "Darwin" ]; then
        lsof -ti:${_port} -sTCP:LISTEN | head -n1
    else
        netstat -t4lnp 2>/dev/null | grep -wE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:${_port}" | awk '{print $7}' | grep -m1 -oE '[0-9-]+' | head -n1
    fi
}

function _user_by_port() {
    local _port="$1"
    [ -z "${_port}" ] && return 1
    # Some Linux doesn't have 'lsof' + no root user can't see all, but Mac's netstat is very different so using only if Mac...
    if [ "`uname`" = "Darwin" ]; then
        lsof -i:${_port} -sTCP:LISTEN | grep -v '^COMMAND' | awk '{print $3}' | head -n1
    else
        netstat -t4le 2>/dev/null | grep -w "0.0.0.0:${_port}" | awk '{print $7}' | head -n1
    fi
}

function _wait_url() {
    local _url="${1}"
    local _times="${2:-30}"
    local _interval="${3:-10}"
    [ -z "${_url}" ] && return 99

    for i in `seq 1 ${_times}`; do
        # NOTE: --retry-connrefused is from curl v 7.52.0
        if curl -f -s -I -L -k -m1 --retry 0 "${_url}" &>/dev/null; then
            return 0
        fi
        _log "DEBUG" "${_url} is unreachable. Waiting for ${_interval} secs ($i/${_times})..."
        sleep ${_interval}
    done
    return 1
}

function _wait_by_port() {
    local _port="$1"
    local _pid="$2"     # If this PID is no longer running, no point of waiting
    local _is_stopping="$3"
    local _times="${4:-30}"
    local _interval="${5:-5}"   # 5 secs x 30 times = 150 secs

    [ -z "${_port}" ] && return 1
    for i in `seq 1 ${_times}`; do
        local _tmp_pid="$(_pid_by_port "${_port}")"
        # Starting ...
        if [[ ! "${_is_stopping}" =~ ^(y|Y) ]]; then
            [ -n "${_pid}" ] && [ ! -e /proc/${_pid} ] && return 1
            if [ -n "${_tmp_pid}" ]; then
                sleep 1 # just in case...
                return 0
            fi
        # Stopping ...
        else
            [ -n "${_pid}" ] && [ ! -e /proc/${_pid} ] && return 0
            if [ -z "${_tmp_pid}" ]; then
                sleep 1 # just in case...
                return 0
            fi
        fi
        sleep ${_interval}
    done
    return 1
}

function _wait() {
    local _pid="$1"
    local _is_stopping="$2"
    local _times="${3:-10}"
    local _interval="${4:-5}"

    [ -z "${_pid}" ] && return 1
    for i in `seq 1 ${_times}`; do
        # TODO: this works with only Linux because of checking /proc
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

function _parallel() {
    local _cmds_list="$1"   # File or strings of commands
    local _prefix_cmd="$2"  # eg: '(date;'
    local _suffix_cmd="$3"  # eg: ';date) &> test_$$.out'
    local _num_process="${4:-3}"
    if [ -f "${_cmds_list}" ]; then
        cat "${_cmds_list}"
    else
        echo ${_cmds_list}
    fi | sed '/^$/d' | tr '\n' '\0' | xargs -t -0 -n1 -P${_num_process} -I @@ bash -c "${_prefix_cmd}@@${_suffix_cmd}"
    # Somehow " | sed 's/"/\\"/g'" does not need... why?
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
    if [ -z "${!_var_name}" ] && _isYes "$_is_mandatory" ; then
        echo "'${_var_name}' is a mandatory parameter."
        _ask "$@"
    fi
    # if not empty and if a validation function is given, use function to check it.
    if _isValidateFunc "$_validation_func" ; then
        $_validation_func "${!_var_name}"
        if [ $? -ne 0 ]; then
            _ask "Would you like to re-type?" "Y"
            if _isYes; then
                _ask "$@"
            fi
        fi
    fi
}
# Checking if the _function_name is the validate type function (isXxxxYyyy)
function _isValidateFunc() {
    local _function_name="$1"
    # FIXME: not good way
    if [[ "$_function_name" =~ ^_is ]]; then
        typeset -F | grep "^declare -f ${_function_name}$" &>/dev/null
        return $?
    fi
    return 1
}

function _isYes() {
    local _answer="$1"
    [ $# -eq 0 ] && _answer="${__LAST_ANSWER}"
    [[ "${_answer}" = "true" ]] && return 0
    [[ "${_answer}" =~ ^[yY] ]] && return 0
    return 1
}

# Using 'which' is not recommended
function _isCmd() {
    local _cmd="$1"
    command -v "${_cmd}" &>/dev/null
}

function _backup() {
    local _file_path="$1"
    local _force="$2"
    local _backup_dir="${3:-"${__TMP%/}"}"

    if [ ! -e "${_file_path}" ]; then
        _log "DEBUG" "No backup created as $_file_path does not exist."
        return 0
    fi

    # Mac's stat is different, and as using cp -p, wouldn't need to use below anyway
    #local _mod_ts=`date -d "`stat -c%y $_file_path`" +"%Y%m%d-%H%M%S"`
    local _mod_ts="`date +"%Y%m%d-%H%M%S"`"
    local _file_name="`basename $_file_path`"
    local _new_file_name="${_file_name}_${_mod_ts}"
    if ! _isYes "${_force}"; then
        if [ -e "${_backup_dir%/}/${_new_file_name}" ]; then
            _log "DEBUG" "No new backup created as $_file_name already exists."
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
    gzip -c ${_file_path} > ${_backup_dir%/}/${_new_file_name}.gz || return $?
    _log "DEBUG" "Backup-ed ${_file_path} to ${_backup_dir%/}/${_new_file_name}"
}

function _isEnoughDisk() {
    local __doc__="Check if entire system or the given path has enough space with GB."
    local _dir_path="${1-/}"
    local _required_gb="$2"
    local _available_space_gb=""

    _available_space_gb=$(_freeSpaceGB "${_dir_path}")

    if [ -z "$_required_gb" ]; then
        echo "${_available_space_gb}GB free space"
        _required_gb=$(_totalSpaceGB)
        _required_gb="$(expr $_required_gb / 10)"
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
function _isNotEmptyDir() {
    local _dir_path="$1"
    # If path is not directory, treat as eampty
    [ ! -d "${_dir_path}" ] && return 1
    [ "$(ls -A ${_dir_path})" ]
}

function _isUrl() {
    local _url="$1"
    local _check_reachability="$2"
    [ -z "${_url}" ] && return 1
    if [[ "${_url}" =~ ${_URL_REGEX} ]]; then
        if _isYes "${_check_reachability}"; then
            curl -s -I -L -k -m2 --retry 0 "$1" &>/dev/null
            return $?
        fi
        return 0
    fi
    return 1
}

function _download() {
    local _url="$1"
    local _save_as="$2"
    local _no_backup="$3"
    local _skip_if_exist="$4"   # default is always continuing or overwriting

    if [[ "${_skip_if_exist}" =~ ^(y|Y) ]] && [ -s "${_save_as}" ]; then
        _log "INFO" "Not downloading as ${_save_as} exists."
        return
    fi
    local _cmd="curl -s -f --retry 3 -L -k '${_url}'"
    # NOTE: if the file already exists, "-C -" may do something unexpected for text files
    if [[ ! "${_save_as}" =~ (\.gz|.zip|.tar|.tgz) ]]; then
        _cmd="${_cmd} --compressed"
    fi
    if [ -s "${_save_as}" ] && ! file "${_save_as}" | grep -qwi "text"; then
        _cmd="${_cmd} -C -"
    fi
    if [ -z "${_save_as}" ]; then
        _cmd="${_cmd} -O"
    else
        [[ "${_no_backup}" =~ ^(y|Y) ]] || _backup "${_save_as}"
        _cmd="${_cmd} -o ${_save_as}"
    fi

    _log "INFO" "Downloading ${_url} ..."
    eval ${_cmd}
}

function _download_and_extract() {
    local _url="$1"
    local _extract_to="${2}"
    local _save_dir="${3:-"${_WORK_DIR%/}/downloads"}"
    local _file="$4"
    local _as_user="${5}"
    [ -z "${_file}" ] && _file="`basename "${_url}"`"
    if [ -d "${_save_dir}" ]; then
        mkdir -v -p "${_save_dir}" || return $?
        [ -n "${_as_user}" ] && chown ${_as_user}: "${_save_dir}"
    fi

    _download "${_url}" "${_save_dir%/}/${_file}" "Y" "Y" || return $?

    # If no extract directory, just download.
    if [ -n "${_extract_to}" ]; then
        if [ ! -d "${_extract_to}" ]; then
            mkdir -p "${_extract_to}" || return $?
            [ -n "${_as_user}" ] && chown ${_as_user}: "${_extract_to}"
        fi
        #local _extension="${_file##*.}"
        #if [[ "${_extension}" =~ \.(tar|gz|tgz|zip)$ ]]; then
        if [ -n "${_as_user}" ]; then
            sudo -u ${_as_user} tar -xf ${_save_dir%/}/${_file} -C ${_extract_to%/}/ || return $?
        else
            tar -xf ${_save_dir%/}/${_file} -C ${_extract_to%/}/ || return $?
        fi
        _log "INFO" "Extracted ${_file} into ${_extract_to}"; sleep 1
        #fi
    fi
}

function _upsert() {
    local __doc__="Modify the given file with given name and value."
    local _file_path="$1"
    local _name="$2"
    local _value="$3"
    local _if_not_exist_append_after="$4"    # This needs to be a beginning of a line, not search keyword
    local _between_char="${5-"="}"
    local _comment_char="${6-"#"}"
    # NOTE & TODO: Not sure why /\\\&/ works, should be /\\&/ ...
    local _name_esc_sed=`echo "${_name}" | _sed 's/[][+\.^$*\/"&-]/\\\&/g'`
    local _name_esc_sed_for_val=`echo "${_name}" | _sed 's/[\/]/\\\&/g'`
    #local _name_escaped=`printf %q "${_name}"`
    local _name_escaped=`echo "${_name}" | _sed 's/[][+\.^$*"-]/\\\&/g'`
    local _value_esc_sed=`echo "${_value}" | _sed 's/[\/]/\\\&/g'`
    local _value_escaped=`printf %q "${_value}"`

    [ ! -f "${_file_path}" ] && return 11
    # Make a backup
    local _file_name="`basename "${_file_path}"`"
    [ ! -f "${__TMP%/}/${_file_name}.orig" ] && cp -p "${_file_path}" "${__TMP%/}/${_file_name}.orig"

    # If name=value is already set, all good
    _grep -qP "^\s*${_name_escaped}\s*${_between_char}\s*${_value_escaped}\s*" "${_file_path}" && return 0

    # If name= is already set, replace all with /g
    if _grep -qP "^\s*${_name_escaped}\s*${_between_char}\s*" "${_file_path}"; then
        if [ -n "${_comment_char}" ] && _grep -qP "^\s*${_name_escaped}\s*${_between_char}.*${_comment_char}" "${_file_path}"; then
            _sed -i -r "s/^([[:space:]]*${_name_esc_sed})([[:space:]]*${_between_char}[[:space:]]*).+([[:space:]]*${_comment_char}.*)$/\1\2${_value_esc_sed} \3/g" "${_file_path}"
        else
            _sed -i -r "s/^([[:space:]]*${_name_esc_sed})([[:space:]]*${_between_char}[[:space:]]*).*$/\1\2${_value_esc_sed}/g" "${_file_path}"
        fi
        return $?
    fi

    # If name= is not set and no _if_not_exist_append_after, just append in the end of line
    if [ -z "${_if_not_exist_append_after}" ]; then
        if [ ! -s "${_file_path}" ] || [ -z "$(tail -c 1 "${_file_path}")" ]; then
            echo -e "${_name}${_between_char}${_value}" >> ${_file_path}
        else
            echo -e "\n${_name}${_between_char}${_value}" >> ${_file_path}
        fi
        return $?
    fi

    # If name= is not set and _if_not_exist_append_after is set, inserting
    if [ -n "${_if_not_exist_append_after}" ]; then
        local _if_not_exist_append_after_sed="`echo "${_if_not_exist_append_after}" | _sed 's/[][\.^$*\/"&]/\\\&/g'`"
        _sed -i -r "0,/^(${_if_not_exist_append_after_sed}.*)$/s//\1\n${_name_esc_sed_for_val}${_between_char}${_value_esc_sed}/" ${_file_path}
        return $?
    fi
}

function _socks5_proxy() {
    local _port="${1:-"48484"}"
    local _default_URL="${2}"   # optional: used in the usage.
    [[ "${_port}" =~ ^[0-9]+$ ]] || return 11

    local _hash="$(cat $HOME/.ssh/id_rsa.pub 2>/dev/null | awk '{print $2}')"
    if [ -z "${_hash}" ]; then
        _log "ERROR" "$FUNCNAME requires ssh password-less login."
        return 1
    fi
    if ! grep -q "${_hash}" $HOME/.ssh/authorized_keys; then
        cat $HOME/.ssh/id_rsa.pub >> $HOME/.ssh/authorized_keys || return $?
    fi

    local _cmd="ssh -4gC2TxnNf -D${_port} localhost 2>&1 >> ${_LOG_FILE_PATH:-"/dev/null"} &"
    local _host_ip="$(hostname -I 2>/dev/null | cut -d" " -f1)"

    local _pid="$(_pid_by_port "${_port}")"
    if [ -n "${_pid}" ]; then
        local _ps_comm="$(ps -o comm= -p ${_pid})"
        ps -Fwww -p ${_pid}
        if [ "${_ps_comm}" == "ssh" ]; then
            _log "INFO" "The Socks proxy might be already running (${_pid})"
        else
            _log "WARN" "The port:${_port} is used by PID:${_pid}. Please stop this PID or use different port."
            return 1
        fi
    else
        eval "${_cmd}" || return $?
        _log "INFO" "Started socks proxy on \"${_host_ip:-"xxx.xxx.xxx.xxx"}:${_port}\"."
    fi

    echo "NOTE: Below command starts Chrome with this Socks5 proxy:
# Mac:
open -na \"Google Chrome\" --args --user-data-dir=\$HOME/.chrome_pxy --proxy-server=socks5://${_host_ip:-"xxx.xxx.xxx.xxx"}:${_port} ${_default_URL}
# Win:
\"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe\" --user-data-dir=%USERPROFILE%\.chrome_pxy --proxy-server=socks5://${_host_ip:-"xxx.xxx.xxx.xxx"}:${_port}" ${_default_URL}
}

function _trust_ca() {
    local _ca_pem="$1"
    if [ ! -s "${_ca_pem}" ]; then
        if [ ! -s "${_WORK_DIR%/}/cert/rootCA_standalone.crt" ]; then
            [ ! -d "${_WORK_DIR%/}/cert" ] && mkdir -p "${_WORK_DIR%/}/cert"
            curl -s -f -m 7 --retry 2 --compressed -L "${_DL_URL%/}/misc/rootCA_standalone.crt" -o ${_WORK_DIR%/}/cert/rootCA_standalone.crt || return $?
        fi
        _ca_pem="${_WORK_DIR%/}/cert/rootCA_standalone.crt"
        _log "INFO" "No CA cert specified. Using ${_ca_pem}"
    fi

    # Test
    local _CN="$(openssl x509 -in "${_ca_pem}" -noout -subject | grep -oE "CN\s*=.+" | cut -d"=" -f2 | xargs)"  # somehow xargs trim spaces
    if [ -z "${_CN}" ]; then
        _log "ERROR" "No common name found from ${_ca_pem}"
        return 1
    fi
    local _file_name="$(basename "${_ca_pem}")"
    local _ca_dir=""
    local _ca_cmd=""
    # Took file to find the install command: apt-get install -y ca-certificates
    # If Ubuntu / CentOS 7
    if which update-ca-trust &>/dev/null; then
        _ca_cmd="update-ca-trust"
        _ca_dir="/etc/pki/ca-trust/source/anchors"
    # If RHEL / CentOS / Debian
    elif which update-ca-certificates &>/dev/null; then
        _ca_cmd="update-ca-certificates"
        _ca_dir="/usr/local/share/ca-certificates/extra"
    # If Mac
    elif which security &>/dev/null && [ -d $HOME/Library/Keychains ]; then
        # If we know the common name, and if exists, no change.
        security find-certificate -c "${_CN}" $HOME/Library/Keychains/login.keychain-db &>/dev/null && return 0
        # NOTE: -d for add to admin cert store (and not sure what this means)
        sudo -n true
        sudo security add-trusted-cert -d -r trustRoot -k $HOME/Library/Keychains/login.keychain-db "${_ca_pem}"
        return $?
    fi

    if [ ! -d "${_ca_dir}" ]; then
        if [ -d "$(dirname ${_ca_dir})" ]; then
            mkdir -v "${_ca_dir}" || return $?
        fi
        _log "ERROR" "Couldn't find 'update-ca-trust' or 'update-ca-certificates' command or directory to install CA cert."
        return 1
    fi
    if [ -s ${_ca_dir%/}/${_file_name} ]; then
        _log "DEBUG" "${_ca_dir%/}/${_file_name} already exists."
        return 0
    fi
    cp "${_ca_pem}" ${_ca_dir%/}/ || return $?
    _log "DEBUG" "Copied \"${_ca_pem}\" into ${_ca_dir%/}/"
    ${_ca_cmd} || return $?
    _log "DEBUG" "Executed ${_ca_cmd}"
}

function _postgresql_configure() {
    local __doc__="Update postgresql.conf and pg_hba.conf"
    local _verbose_logging="${1}"   # If Y, adds more logging configs which would work with pgbadger.
    local _wal_archive_dir="${2}"   # Automatically decided if empty
    local _postgresql_conf="${3}"   # Automatically detected if empty. "/var/lib/pgsql/data" or "/etc/postgresql/10/main" or /var/lib/pgsql/12/data/
    local _postgres="${4}"
    local _port="${5:-"5432"}"

    if [ -z "${_postgres}" ]; then
        if [ "`uname`" = "Darwin" ]; then
            _postgres="$USER"
        else
            _postgres="$(_user_by_port "${_port}" 2>/dev/null)"
            [ -z "${_postgres}" ] && _postgres="postgres"
        fi
    fi
    local _psql_as_admin="sudo -u ${_postgres} -i psql"
    if ! grep -q "^${_postgres}" /etc/passwd; then
        # This will ask the password everytime, but you can use PGPASSWORD
        _psql_as_admin="psql -U ${_postgres}"
    fi

    if [ ! -f "${_postgresql_conf}" ]; then
        _postgresql_conf="$(${_psql_as_admin} -tAc 'SHOW config_file')" || return $?
    fi

    if [ -z "${_postgresql_conf}" ] || [ ! -s "${_postgresql_conf}" ]; then
        _log "ERROR" "No postgresql config file specified."
        return 1
    fi

    [ ! -s "${__TMP%/}/postgresql.conf.orig" ] && cp -f "${_postgresql_conf}" "${__TMP%/}/postgresql.conf.orig"

    _log "INFO" "Updating ${_postgresql_conf} ..."
    # Performance tuning (so not mandatory). Expecting the server has at least 4GB
    # @see: https://pgtune.leopard.in.ua/#/
    _upsert ${_postgresql_conf} "shared_buffers" "1024MB"    # 4GB * 25%
    _upsert ${_postgresql_conf} "work_mem" "12MB" "#work_mem" # 4GB * 25% / max_connections (100) + extra
    _upsert ${_postgresql_conf} "effective_cache_size" "3072MB" "#effective_cache_size" # Physical mem (4GB) * 50% ~ 75%
    #_upsert ${_postgresql_conf} "wal_buffers" "16MB" "#wal_buffers" # Usually higher provides better write performance
    ### End of tuning ###
    _upsert ${_postgresql_conf} "max_connections" "400" "#max_connections"   # This is NXRM3 as it uses 100 per datastore...
    _upsert ${_postgresql_conf} "listen_addresses" "'*'" "#listen_addresses"
    [ ! -d /var/log/postgresql ] && mkdir -p -m 777 /var/log/postgresql
    _upsert ${_postgresql_conf} "log_directory" "'/var/log/postgresql' " "#log_directory"
    #_upsert ${_postgresql_conf} "ssl" "on" "#ssl"
    # NOTE: key file permission needs to be 0600
    #_upsert ${_postgresql_conf} "ssl_key_file" "'/var/lib/pgsql/12/standalone.localdomain.key'" "#ssl_key_file"
    #_upsert ${_postgresql_conf} "ssl_cert_file" "'/var/lib/pgsql/12/standalone.localdomain.crt'" "#ssl_cert_file"
    #_upsert ${_postgresql_conf} "ssl_ca_file" "'/var/tmp/share/cert/rootCA_standalone.crt'" "#ssl_ca_file"
    # pg_hba.conf: hostssl sonatype sonatype 0.0.0.0/0 md5

    if [ -z "${_wal_archive_dir}" ]; then
        _wal_archive_dir="${_WORK_DIR%/}/${_postgres}/backups/${_save_dir%/}/`hostname -s`_wal"
    fi
    if [ ! -d "${_wal_archive_dir}" ]; then
        sudo -u "${_postgres}" mkdir -v -p "${_wal_archive_dir}" || return $?
    fi

    # @see: https://www.postgresql.org/docs/current/continuous-archiving.html https://www.postgresql.org/docs/current/runtime-config-wal.html
    _upsert ${_postgresql_conf} "archive_mode" "on" "#archive_mode"
    _upsert ${_postgresql_conf} "archive_command" "'test ! -f ${_wal_archive_dir%/}/%f && cp %p ${_wal_archive_dir%/}/%f'" "#archive_command" # this is asynchronous
    #TODO: use recovery_min_apply_delay = '1h'
    # For wal/replication/pg_rewind, better save log files outside of _postgresql_conf

    _upsert ${_postgresql_conf} "log_error_verbosity" "default" "#log_error_verbosity"
    _upsert ${_postgresql_conf} "log_connections" "on" "#log_connections"
    _upsert ${_postgresql_conf} "log_disconnections" "on" "#log_disconnections"
    _upsert ${_postgresql_conf} "log_lock_waits" "on" "#log_lock_waits"
    _upsert ${_postgresql_conf} "log_temp_files" "0" "#log_temp_files"

    if [[ "${_verbose_logging}" =~ (y|Y) ]]; then
        # @see: https://github.com/darold/pgbadger#POSTGRESQL-CONFIGURATION (brew install pgbadger)
        # To log the SQL statements
        _upsert ${_postgresql_conf} "log_line_prefix" "'%m [%p-%l]: user=%u,db=%d,app=%a,client=%h '" "#log_line_prefix"
        _upsert ${_postgresql_conf} "log_min_duration_statement" "0" "#log_min_duration_statement"
        _upsert ${_postgresql_conf} "log_checkpoints" "on" "#log_checkpoints"
        _upsert ${_postgresql_conf} "log_autovacuum_min_duration" "0" "#log_autovacuum_min_duration"
    else
        _upsert ${_postgresql_conf} "log_line_prefix" "'%m [%p-%l]: user=%u,db=%d,vtid=%v '" "#log_line_prefix"
        _upsert ${_postgresql_conf} "log_statement" "'mod'" "#log_statement"
        _upsert ${_postgresql_conf} "log_min_duration_statement" "1000" "#log_min_duration_statement"
    fi
    # To check:
    # SELECT setting, pending_restart FROM pg_settings WHERE name = 'shared_preload_libraries';
    #CREATE EXTENSION IF NOT EXISTS pg_buffercache;
    local _shared_preload_libraries="auto_explain"
    if ${_psql_as_admin} -d template1 -c "CREATE EXTENSION IF NOT EXISTS pg_prewarm;"; then
        _shared_preload_libraries="${_shared_preload_libraries},pg_prewarm"
        # select pg_prewarm('<tablename>', 'buffer');
    fi
    _upsert ${_postgresql_conf} "shared_preload_libraries" "'${_shared_preload_libraries}'" "#shared_preload_libraries"
    #ALTER SYSTEM SET auto_explain.log_min_duration TO '0';
    #SELECT pg_reload_conf();
    #SELECT * FROM pg_settings WHERE name like 'auto_explain%';
    _upsert ${_postgresql_conf} "auto_explain.log_min_duration" "5000"

    diff -wu ${__TMP%/}/postgresql.conf.orig ${_postgresql_conf}
    _log "INFO" "Updated postgresql config. Please restart (or reload) the service."
}

function _postgresql_create_dbuser() {
    local __doc__="Create DB user/role/schema/database"
    local _dbusr="${1}"
    local _dbpwd="${2:-"${_dbusr}"}"
    local _dbname="${3:-"${_dbusr}"}"
    local _schema="${4}"
    local _postgres="${5}"
    local _port="${6:-"5432"}"

    if [ -z "${_postgres}" ]; then
        if [ "`uname`" = "Darwin" ]; then
            #psql template1 -c "create database $USER"
            _postgres="$USER"
        else
            _postgres="$(_user_by_port "${_port}" 2>/dev/null)"
            [ -z "${_postgres}" ] && _postgres="postgres"
        fi
    fi
    local _psql_as_admin="sudo -u ${_postgres} -i psql"
    if ! grep -q "^${_postgres}" /etc/passwd; then
        _log "WARN" "'${_postgres}' OS user does not exist. May require to set PGPASSWORD variable."
        # This will ask the password everytime, but you can use PGPASSWORD
        _psql_as_admin="psql -U ${_postgres}"
    fi

    local _pg_hba_conf="$(${_psql_as_admin} -tAc 'SHOW hba_file')"
    if [ ! -f "${_pg_hba_conf}" ]; then
        _log "WARN" "No pg_hba.conf file found."
        return 1
    fi

    # NOTE: Use 'hostssl all all 0.0.0.0/0 cert clientcert=1' for 2-way | client certificate authentication
    #       To do that, also need to utilise database.parameters.some_key:value in config.yml
    if ! grep -E "host\s+${_dbname}\s+${_dbusr}\s+" "${_pg_hba_conf}"; then
        echo "host ${_dbname} ${_dbusr} 0.0.0.0/0 md5" >> "${_pg_hba_conf}" || return $?
        ${_psql_as_admin} -tAc 'SELECT pg_reload_conf()' || return $?
    fi
    [ "${_dbusr}" == "all" ] && return 0

    _log "INFO" "Creating Role:${_dbusr} and Database:${_dbname} ..."
    # NOTE: need to be superuser and 'usename' is correct. options: -t --tuples-only, -A --no-align, -F --field-separator
    ${_psql_as_admin} -d template1 -tA -c "SELECT usename FROM pg_shadow" | grep -q "^${_dbusr}$" || ${_psql_as_admin} -c "CREATE ROLE ${_dbusr} WITH LOGIN PASSWORD '${_dbpwd}';"    # not SUPERUSER
    ${_psql_as_admin} -d template1 -ltA  -F',' | grep -q "^${_dbname}," || ${_psql_as_admin} -c "CREATE DATABASE ${_dbname} WITH OWNER ${_dbusr} ENCODING 'UTF8';"
    # Below two lines are not needed. for testing purpose to avoid unnecessary permission errors.
    ${_psql_as_admin} -d template1 -c "GRANT ALL ON DATABASE ${_dbname} TO ${_dbusr};"
    ${_psql_as_admin} -d ${_dbname} -c "GRANT ALL ON SCHEMA public TO ${_dbusr};"

    if [ -n "${_schema}" ]; then
        local _search_path="${_dbusr},public"
        for _s in ${_schema}; do
            ${_psql_as_admin} -d ${_dbname} -c "CREATE SCHEMA IF NOT EXISTS ${_s} AUTHORIZATION ${_dbusr};"
            _search_path="${_search_path},${_s}"
        done
        ${_psql_as_admin} -d template1 -c "ALTER ROLE ${_dbusr} SET search_path = ${_search_path};"
    fi

    # test
    local _host_name="$(hostname -f)"
    local _cmd="psql -U ${_dbusr} -h ${_host_name} -d ${_dbname} -c \"\l ${_dbname}\""
    _log "INFO" "Testing connection with ${_cmd} ..."
    eval "PGPASSWORD=\"${_dbpwd}\" ${_cmd}" || return $?
}

function _postgres_pitr() {
    local __doc__="Point In Time Recovery for PostgreSQL *12* (not tested with other versions)"
    # @see: https://www.postgresql.org/docs/12/continuous-archiving.html#BACKUP-PITR-RECOVERY
    # NOTE: this function doesn't do any assumption. almost all arguments need to be specified.
    local _data_dir="${1}"              # /var/lib/pgsql/data, /var/lib/pgsql/12/data or /usr/local/var/postgres (Mac)
    local _base_backup_tgz="${2}"       # File path. eg: .../node-nxiq1960_base_20201105T091218z/base.tar.gz
    local _wal_archive_dir="${3}"       # ${_WORK_DIR%/}/${_SERVICE%/}/backups/`hostname -s`_wal
    local _target_ISO_datetime="${4}"   # yyyy-mm-dd hh:mm:ss (optional)
    local _postgres="${5:-"postgres"}"  # DB OS user
    local _port="${6:-"5432"}"          # PostgreSQL port number

    if [ ! -d "${_data_dir}" ]; then
        _log "ERROR" "No PostgreSQL data dir provided: ${_data_dir}"
    fi
    if [ ! -s "${_base_backup_tgz}" ]; then
        _log "ERROR" "No base backup file: ${_base_backup_tgz}"
        return 1
    fi
    local _pid="$(_pid_by_port "${_port}")"
    if [ -n "${_pid}" ]; then
        _log "ERROR" "Please stop postgresql first: ${_pid}"
        return 1
    fi

    mv -v ${_data_dir%/} ${_data_dir%/}_$(date +"%Y%m%d%H%M%S") || return $?
    sudo -u ${_postgres} -i mkdir -m 700 -p ${_data_dir%/} || return $?
    tar -xvf "${_base_backup_tgz}" -C "${_data_dir%/}" || return $?
    sudo -u ${_postgres} -i touch ${_data_dir%/}/recovery.signal || return $?
    #mv -v ${_data_dir%/}/pg_wal/* ${_TMP%/}/ || return $?
    if [ -s "$(dirname "${_base_backup_tgz}")/pg_wal.tar.gz" ]; then
        tar -xvf "$(dirname "${_base_backup_tgz}")/pg_wal.tar.gz" -C "${_data_dir%/}/pg_wal"
    fi

    # NOTE: From PostgreSQL 12, no recovery.conf
    if [ ! -s ${_data_dir%/}/postgresql.conf.bak ]; then
        cp -p ${_data_dir%/}/postgresql.conf ${_data_dir%/}/postgresql.conf.bak || return $?
    fi
    _upsert ${_data_dir%/}/postgresql.conf "restore_command" "'cp ${_wal_archive_dir%/}/%f "%p"'" "#restore_command "
    _upsert ${_data_dir%/}/postgresql.conf "recovery_target_action" "'promote'" "#recovery_target_action "
    [ -n "${_target_ISO_datetime}" ] && _upsert ${_data_dir%/}/postgresql.conf "recovery_target_time" "'${_target_ISO_datetime}'" "#recovery_target_time "
    diff -u ${_data_dir%/}/postgresql.conf.bak ${_data_dir%/}/postgresql.conf
    _log "INFO" "postgresql.conf has been updated. Please start PostgreSQL for recovery then 'promote'."
    # Upon completion of the recovery process, the server will remove recovery.signal (to prevent accidentally re-entering recovery mode later) and then commence normal database operations.
}
