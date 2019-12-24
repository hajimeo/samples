#!/usr/bin/env bash
usage() {
    echo "PURPOSE OF THIS SCRIPT:
    Visualise *.log files under current directory ($PWD).

HOW TO INSTALL:
    Copy this script under a directory in the PATH (eg:/usr/local/bin/)
    Then 'chmod u+x /usr/local/bin/$(basename ${0})'

HOW TO EXECUTE:
    $(basename ${0}) [start_ISO_datetime] [end_ISO_datetime] [elapsed_milliseconds]

All arguments to filter data, and optional.
    start_ISO_datetime (YYYY-MM-DD hh:mm:ss)
        If sets, date&time older than this time will be ignored.
    end_ISO_datetime (YYYY-MM-DD hh:mm:ss)
        If sets, date&time newer than this time will be ignored.
    elapsed_milliseconds (default:100)
        If sets, elapsedTime smaller than this value will be ignored from request.log.

REQUIRED:
    python3
    pip3 install pandas sqlalchemy matplotlib

GLOBAL VARIABLES:
Please overwrite (or edit this script) to change the value.
    _INSTALL_DIR='${_INSTALL_DIR}'
"
    echo "FUNCTIONS:"
    _list
}

_INSTALL_DIR="$HOME/.log_visualiser"



function f_validate() {
    local __doc__="Check if python3 and required modules are installed"
    local _py_mods="pandas sqlalchemy matplotlib"
    local _all_good=0
    local _missing_pymods=""
    if ! which python3 &>/dev/null; then
        _log "ERROR" "'python3' is required."
        return 1
    fi
    for _m in ${_py_mods}; do
        _missing_pymods="${_missing_pymods% } `_validate_py_mods "${_m}"`"
        [ $? -ne 0 ] && _all_good=$(($_all_good +1))
    done
    if [ ${_all_good} -ne 0 ] && [ -n "${_missing_pymods}" ]; then
        _log "ERROR" "run 'pip3 install ${_missing_pymods}'"
    fi
    return ${_all_good}
}
_validate_py_mods() {
    local _py_mod="$1"
    if ! python3 -c "import ${_py_mod}" &>/dev/null; then
        echo "${_py_mod}"
        return 1
    fi
}

function f_setup() {
    local __doc__="Update necessary script and set environment variable"
    if [ ! -d "${_INSTALL_DIR%/}" ]; then
        mkdir -p "${_INSTALL_DIR%/}" || return $?
    fi
    _update "${_INSTALL_DIR%/}/jn_utils.py" || return $?
    if [ -z "$PYTHONPATH" ]; then
        export PYTHONPATH=${_INSTALL_DIR%/}
    elif [[ ":$PYTHONPATH:" != *":${_INSTALL_DIR%/}:"* ]]; then
        export PYTHONPATH=${_INSTALL_DIR%/}:${PYTHONPATH#:}
    fi
}

function f_run() {
    local __doc__="Execute jn_utils:analyse_logs()"
    local _start_isotime="$1"   # YYYY-MM-DD hh:mm:ss
    local _end_isotime="$2"     # YYYY-MM-DD hh:mm:ss
    local _elapsed_time="${3:-100}"
    python3 -c 'import jn_utils as ju; ju.analyse_logs(start_isotime="'${_start_isotime}'", end_isotime="'${_end_isotime}'", elapsed_time='${_elapsed_time}')'
}


_update() {
    local _target="${1}"
    local _remote_repo="${2:-"https://raw.githubusercontent.com/hajimeo/samples/master/python/"}"

    local _file_name="`basename ${_target}`"
    local _backup_file="/tmp/${_file_name}_$(date +"%Y%m%d%H%M%S")"
    if [ -f "${_target}" ]; then
        local _remote_length=`curl -m 4 -s -k -L --head "${_remote_repo%/}/${_file_name}" | grep -i '^Content-Length:' | awk '{print $2}' | tr -d '\r'`
        local _local_length=`wc -c <${_target}`
        if [ -z "${_remote_length}" ] || [ "${_remote_length}" -lt $(( ${_local_length} / 2 )) ] || [ ${_remote_length} -eq ${_local_length} ]; then
            #_log "INFO" "Not updating ${_target}"
            return 0
        fi

        cp "${_target}" "${_backup_file}" || return $?
    fi

    curl -s -f --retry 3 "${_remote_repo%/}/${_file_name}" -o "${_target}"
    if [ $? -ne 0 ]; then
        # Restore from backup
        mv -f "${_backup_file}" "${_target}"
        return 1
    fi
    if [ -f "${_backup_file}" ]; then
        local _length=`wc -c <${_target}`
        local _old_length=`wc -c <${_backup_file}`
        if [ ${_length} -lt $(( ${_old_length} / 2 )) ]; then
            mv -f "${_backup_file}" "${_target}"
            return 1
        fi
    fi
    _log "INFO" "${_target} has been updated. Backup: ${_backup_file}"
}
_log() {
    # At this moment, outputting to STDERR
    if [ -n "${_LOG_FILE_PATH}" ]; then
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $@" | tee -a ${_LOG_FILE_PATH} 1>&2
    else
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $@" 1>&2
    fi
}
_help() {
    local _function_name="$1"
    local _show_code="$2"
    local _doc_only="$3"

    if [ -z "$_function_name" ]; then
        # The workd "help" is already taken in bash
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
            _output="No help information in function name '$_function_name'.\n"
        else
            _output="$__doc__"
            if [[ "${_doc_only}" =~ (^y|^Y) ]]; then
                echo -e "${_output}"; return
            fi
        fi

        local _params="$(type $_function_name 2>/dev/null | grep -iE '^\s*local _[^_].*?=.*?\$\{?[1-9]' | grep -v awk)"
        if [ -n "$_params" ]; then
            _output="${_output}Parameters:\n"
            _output="${_output}${_params}\n"
        fi
        if [[ "${_show_code}" =~ (^y|^Y) ]] ; then
            _output="${_output}\n${_code}\n"
            echo -e "${_output}" | less
        elif [ -n "$_output" ]; then
            echo -e "${_output}"
            echo "(\"_help $_function_name y\" to show code)"
        fi
    else
        echo "Unsupported Function name '$_function_name'."
        return 1
    fi
}
_list() {
    local _name="$1"
    #local _width=$(( $(tput cols) - 2 ))
    local _tmp_txt=""
    # TODO: restore to original posix value
    set -o posix

    if [[ -z "$_name" ]]; then
        (for _f in `typeset -F | grep -E '^declare -f [fp]_' | cut -d' ' -f3`; do
            #eval "echo \"--[ $_f ]\" | _sed -e :a -e 's/^.\{1,${_width}\}$/&-/;ta'"
            _tmp_txt="`_help "$_f" "" "Y"`"
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



main() {
    f_validate || return $?
    f_setup || return $?
    f_run "$@"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ]; then
        usage | less
        exit
    fi
    main "$@"
fi
