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

type python &>/dev/null || alias python=python3  # For M1 Mac workaround


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
    local _depth="${6:-"6"}"
    if [ ! -d "${_dir}" ]; then
        if [[ "${_follow_symlink}" =~ ^(y|Y) ]]; then
            _dir="$(realpath $(find -L ${_base_dir%/} -maxdepth ${_depth} -type d \( -name log -o -name logs \) 2>/dev/null | tr '\n' ' ') | sort | uniq | tr '\n' ' ' | tail -n1)"
        else
            _dir="$(find ${_base_dir%/} -maxdepth ${_depth} -type d \( -name log -o -name logs \)| tr '\n' ' ' 2>/dev/null | tail -n1)"
        fi
    fi
    [ -n "${_mmin}" ] && _mmin="-mmin ${_mmin}"
    if [[ "${_follow_symlink}" =~ ^(y|Y) ]]; then
        local _files_oneline="$(find -L ${_dir} -maxdepth ${_depth} -type f -name "${_file_glob}" ${_mmin} | tr '\n' ' ')"
        [ -n "${_files_oneline}" ] && realpath ${_files_oneline} | sort | uniq | tr '\n' ' '
    else
        find ${_dir} -maxdepth ${_depth} -type f -name "${_file_glob}" ${_mmin} | tr '\n' ' '
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

        local _params="$(type $_function_name 2>/dev/null | _grep -iP '^\s*local _[^_].*?=.*?\$\{?[1-9]' | grep -v "awk")"
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
        (for _f in `typeset -F | grep -E '^declare -f [fp]_' | cut -d' ' -f3`; do
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
# Another way with 'for'
#IFS="," read -ra repos <<< "$_string"
#for repo in "${repos[@]}"; do echo "Processing repository: $repo"; done

function _escape() {
    local _string="$1"
    printf %q "${_string}"
}

function _sed() {
    local _cmd="sed"; which gsed &>/dev/null && _cmd="gsed"
    ${_cmd} "$@"
}

function _gunzip() {
    if type unpigz &>/dev/null; then
        unpigz "$@"
    else
        gunzip "$@"
    fi
}

function _grep() {
    local _cmd="grep"; which ggrep &>/dev/null && _cmd="ggrep"
    ${_cmd} "$@"
}

function _sortjson() {
    if type sortjson &>/dev/null; then
        sortjson
    else
        if [ ! -e /tmp/sortjson ]; then
            curl -sSf -o /tmp/sortjson -L "https://github.com/hajimeo/samples/raw/master/misc/sortjson_$(uname)_$(uname -m)" && chmod a+x /tmp/sortjson
        fi
        /tmp/sortjson
    fi
}

# eval "$(_load_yaml ./test.yml)"
function _load_yaml() {
    local _yaml_file="${1}"
    local _name_space="${2}"
    _sed -n -r 's/^[[:space:]]*([^=:]+)[[:space:]]*[=:][[:space:]]+(.+)/'${_name_space}'\1\t"\2"/p' ${_yaml_file} | awk -F "\t" '{gsub(/[^0-9a-zA-Z_]/,"_",$1); print $1"="$2}' > "${__TMP}/_load_yaml_$$.out" || return $?
    source "${__TMP}/_load_yaml_$$.out"
    cat ${__TMP}/_load_yaml_$$.out
}

function _pid_by_port() {
    local _port="$1"
    [ -z "${_port}" ] && return 1
    # Some Linux doesn't have 'lsof' + no root user can't see all, but Mac's netstat is very different so using only if Mac...
    if [ "`uname`" = "Darwin" ]; then
        lsof -ti:${_port} -sTCP:LISTEN | head -n1   # should be tail?
    else
        netstat -t4lnp 2>/dev/null | grep -wE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:${_port}" | awk '{print $7}' | grep -m1 -oE '[0-9-]+' | head -n1
    fi
}

function _user_by_port() {
    local _port="$1"
    [ -z "${_port}" ] && return 1
    if [ "`uname`" = "Darwin" ]; then
        lsof -i:${_port} | grep -v '^COMMAND' | awk '{print $3}' | head -n1
    else
        netstat -t4le 2>/dev/null | grep -w "0.0.0.0:${_port}" | awk '{print $7}' | head -n1
    fi
}

function _find_port() {
    local _starting_port="${1}"
    local _how_many_try="${2:-10}"
    local _skip_regex="${3}"
    for i in $(seq 0 ${_how_many_try}); do
        local _port=$((${_starting_port} + ${i}))
        [ -n "${_skip_regex}" ] && [[ "${_port}" =~ ${_skip_regex} ]] && continue
        local _pid=$(_pid_by_port "${_port}") || return $?
        if [ -z "${_pid}" ]; then
            echo "${_port}"
            return 0
        fi
    done
    return 1
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
            [ -n "${_pid}" ] && ! ps -o pid= -p ${_pid} &>/dev/null && return 1
            if [ -n "${_tmp_pid}" ]; then
                sleep 1 # just in case...
                return 0
            fi
        # Stopping ...
        else
            [ -n "${_pid}" ] && ! ps -o pid= -p ${_pid} &>/dev/null && return 0
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
        # Using 'ps' as '/proc' works with only Linux
        if [[ "${_is_stopping}" =~ ^(y|Y) ]] && ! ps -o pid= -p ${_pid} &>/dev/null; then
            sleep 1 # just in case...
            return 0
        fi
        if [[ ! "${_is_stopping}" =~ ^(y|Y) ]] && ps -o pid= -p ${_pid} &>/dev/null; then
            sleep 1 # just in case...
            return 0
        fi
        sleep ${_interval}
    done
    return 1
}

function _parallel() {
    local _cmds_list="$1"   # File or strings of commands
    local _num_process="${2:-3}"
    local _prefix_cmd="$3"  # eg: '(date;'
    local _suffix_cmd="$4"  # eg: ';date) &> test_$$.out'
    if [ -f "${_cmds_list}" ]; then
        cat "${_cmds_list}"
    else
        echo ${_cmds_list}
    fi | sed '/^$/d' | tr ';' '\0' | tr '\n' '\0' | xargs -t -0 -n1 -P${_num_process} -I @@ bash -c "${_prefix_cmd}@@${_suffix_cmd}"
    # Somehow " | sed 's/"/\\"/g'" does not need... why?
    # TODO: xargs has command length limit, probably 255 chars
}

function _parallel2() {
    local _cmds_list="$1"   # File or strings of commands
    local _num_process="${2:-3}"
    local _prefix_cmd="$3"  # eg: '(date;'
    local _suffix_cmd="$4"  # eg: ';date) &> test_$$.out'
    local _tmp="$(mktemp -d)"
    if [ -f "${_cmds_list}" ]; then
        cat "${_cmds_list}"
    else
        echo ${_cmds_list}
    fi | sed '/^$/d' | tr ';' '\0' | tr '\n' '\0' | while read -r _t; do
        if ! _wait_jobs "${_num_process}"; then
            _log "ERROR" "${FUNCNAME[0]} _wait_jobs failed."
            return 1
        fi
        local _started="$(date +%s)"
        echo "[$(date +"%Y-%m-%d %H:%M:%S %z")] Starting ${_prefix_cmd}${_t}${_suffix_cmd}" > ${_tmp}/${_pfx}.out
        eval "${_prefix_cmd}${_t}${_suffix_cmd} > ${_tmp}/${_t}.out;" &
    done
    _wait_jobs 0
    cat ${_tmp}/${_pfx}*.out
    _LOG "INFO" "Completed ${FUNCNAME[1]}->${FUNCNAME[0]}."
}

function _wait_jobs() {
    local _until_how_many="${1:-2}" # Running two is OK
    local _timeout_sec="${2:-180}"
    local _sp="0.2"
    local _loop_num="$(echo "${_timeout_sec}/${_sp}" | bc)"
    for _i in $(seq 0 ${_loop_num}); do
        local _num="$(jobs -l | grep -iw "Running" | wc -l | tr -d '[:space:]')"
        if [ -z "${_num}" ] || [ ${_num} -le ${_until_how_many} ]; then
            return 0
        fi
        #echo "${_num} background jobs are still running" >&2
        sleep ${_sp}
    done
}

function _defer() {
    trap "trap \"$@\" RETURN" RETURN
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
    [ -n "$(ls -A ${_dir_path})" ]
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
    local _no_tmp="${5:-"${_NO_TMP_FOR_DOWNLOAD}"}"

    if [[ "${_skip_if_exist}" =~ ^(y|Y) ]] && [ -s "${_save_as}" ]; then
        _log "INFO" "Not downloading as ${_save_as} exists."
        return
    fi

    local _tmp_dl_path="${_save_as}"
    if [[ ! "${_no_tmp}" =~ ^(y|Y) ]]; then
        _tmp_dl_path="${__TMP%/}/$(basename "${_save_as}")"
    fi
    # should do this? rm -v -f "${_tmp_dl_path}" || return $?

    local _cmd="curl -s -f --retry 3 -L -k '${_url}'"
    # NOTE: if the file already exists, "-C -" may do something unexpected for text files
    if [[ ! "${_save_as}" =~ (\.gz|.zip|.tar|.tgz) ]]; then
        _cmd="${_cmd} --compressed"
    fi
    # if partially downloaded in the tmp location
    if [ -s "${_tmp_dl_path}" ] && ! file "${_tmp_dl_path}" | grep -qwi "text"; then
        _cmd="${_cmd} -C -"
    fi
    if [ -z "${_save_as}" ]; then
        _cmd="${_cmd} -O"
    else
        [[ "${_no_backup}" =~ ^(y|Y) ]] || _backup "${_save_as}"
        _cmd="${_cmd} -o ${_tmp_dl_path}"
    fi

    _log "INFO" "Downloading ${_url} ..."
    eval "${_cmd}" || return $?
    if [[ ! "${_no_tmp}" =~ ^(y|Y) ]]; then
        mv -v -f "${_tmp_dl_path}" "${_save_as}" || return $?
    fi
}

function _download_and_extract() {
    local _url="$1"
    local _extract_to="${2}"
    local _save_dir="${3:-"${_WORK_DIR%/}/downloads"}"
    local _file="$4"
    local _as_user="${5}"
    local _no_tmp="${6:-"${_NO_TMP_FOR_DOWNLOAD}"}"
    [ -z "${_file}" ] && _file="`basename "${_url}"`"
    if [ -d "${_save_dir}" ]; then
        mkdir -v -p "${_save_dir}" || return $?
        [ -n "${_as_user}" ] && chown ${_as_user}:${_as_user} "${_save_dir}"
    fi

    _download "${_url}" "${_save_dir%/}/${_file}" "Y" "Y" "${_no_tmp}" || return $?

    # If no extract directory, just download.
    if [ -n "${_extract_to}" ]; then
        if [ ! -d "${_extract_to}" ]; then
            mkdir -p "${_extract_to}" || return $?
            [ -n "${_as_user}" ] && chown ${_as_user}:${_as_user} "${_extract_to}"
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

function _prepare_install() {
    local __doc__="Prepare application installation. _LICENSE_PATH is also set."
    local _extract_path="$1"
    local _url="$2"
    local _license_path="${3}"
    local _download_dir="${4}"

    local _tgz_name="$(basename "${_url}")"
    if [ -z "${_download_dir%/}" ]; then
        if [ -d "${HOME%/}/.nexus_executable_cache" ]; then
            _download_dir="${HOME%/}/.nexus_executable_cache"
        elif [ -d "${_SHARE_DIR%/}/sonatype" ]; then
            _download_dir="${_SHARE_DIR%/}/sonatype"
        fi
    fi
    local _tgz="${_download_dir:-"."}/${_tgz_name}"
    local _extractTar=true
    if [ -d "${_extract_path}" ]; then
        echo "WARN ${_extract_path} exists, so not extracting ${_tgz}"
        return
    fi
    # In case the path contains wildcards
    local _local_tgz="$(ls -1 ${_tgz} | tail -n1)"
    if [ -z "${_local_tgz}" ]; then
        # This will fail if it contains wildcards but it's ok
        echo "no ${_tgz}. Downloading from ${_url} ..."
        curl -sf -o "/tmp/${_tgz_name}" -L "${_url}" || return $?
        [ -s "/tmp/${_tgz_name}" ] || return 101
        mv -v -f /tmp/${_tgz_name} ${_tgz} || return $?
    elif [ "${_local_tgz}" != "${_tgz}" ]; then
        echo "Extracting ${_local_tgz} ..."
        _tgz="${_local_tgz}"
    fi
    mkdir -v -p "${_extract_path}" || return $?
    tar -C ${_extract_path%/} -xf ${_tgz} || return $?

    # NOTE: can't use 'echo' as there are other outputs in this function, so using export
    if [ -f "${_license_path}" ]; then
        export _LICENSE_PATH="${_license_path}"
    elif [ ! -s "${_LICENSE_PATH}" ]; then
        if [ -f "${HOME%/}/.nexus_executable_cache/license/nexus.lic" ]; then
            export _LICENSE_PATH="${HOME%/}/.nexus_executable_cache/license/nexus.lic"
        else
            export _LICENSE_PATH="$(find ${_SHARE_DIR%/}/sonatype -maxdepth 1 -name '*.lic' -print | head -n1)"
        fi
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
    # If RHEL / CentOS / Debian / Ubuntu 22
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