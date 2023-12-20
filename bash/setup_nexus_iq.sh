#!/usr/bin/env bash
# BASH script to setup Nexus IQ configs
#   bash <(curl -sSfL https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_nexus_iq.sh --compressed) -A
#
# For local test:
#   _import() { source /var/tmp/share/sonatype/$1; } && export -f _import
#
# How to source:
#   source /dev/stdin <<< "$(curl -sSfL https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_nexus_iq.sh --compressed)"
#   #export _NEXUS_URL="http://localhost:8070/"
#   _AUTO=true main
#
# TODO: some of functions uses python, which does not exist in the image
#
_DL_URL="${_DL_URL:-"https://raw.githubusercontent.com/hajimeo/samples/master"}"
type _import &>/dev/null || _import() { [ ! -s /tmp/${1} ] && curl -sf --compressed "${_DL_URL%/}/bash/$1" -o /tmp/${1}; . /tmp/${1}; }

_import "utils.sh"
_import "utils_db.sh"

function usage() {
    local _filename="$(basename $BASH_SOURCE)"
    echo "Main purpose of this script is to create repositories with some sample components.
Also functions in this script can be used for testing downloads and uploads.

#export _NEXUS_URL='http://SOME_REMOTE_IQ:8070/'
./${_filename} -A

DOWNLOADS:
    curl ${_DL_URL%/}/bash/${_filename} -o ${_WORK_DIR%/}/sonatype/${_filename}

REQUIREMENTS / DEPENDENCIES:
    If Mac, 'gsed' and 'ggrep' are required.
    brew install gnu-sed grep

COMMAND OPTIONS:
    -A
        Automatically setup repositories against _NEXUS_URL Nexus (best effort)
    -r <response_file_path>
        Specify your saved response file. Without -A, you can review your responses.
    -f <format1,format2,...>
        Comma separated repository formats.
        Default: ${_REPO_FORMATS}
    -v <nexus version>
        Install Nexus with this version number (eg: 1.170.0)
    -d <dbname>
        Existing PostgreSQL DB name or 'h2'

    -h list
        List all functions
    -h <function name>
        Show help of the function

EXAMPLE COMMANDS:
Start script with interview mode:
    sudo ${_filename}

Using default values and NO interviews:
    sudo ${_filename} -A

Create IQ 1.170.0 and setup available formats:
    sudo ${_filename} -v 1.170.0 [-A]

Using previously saved response file and review your answers:
    sudo ${_filename} -r ./my_saved_YYYYMMDDhhmmss.resp

Using previously saved response file and NO interviews:
    sudo ${_filename} -A -r ./my_saved_YYYYMMDDhhmmss.resp
"
}

# TODO: Direct / Transitive example for Java and NPM
# TODO: SCM setup

function f_install_iq() {
    local __doc__="Install specific IQ version"
    local _ver="${1}"     # 'latest'
    local _dbname="${2}"
    local _dbusr="${3:-"nxrm"}"     # Specifying default as do not want to create many users/roles
    local _dbpwd="${4:-"${_dbusr}123"}"
    local _port="${5:-"${_IQ_INSTALL_PORT}"}"      # If not specified, checking from 8070
    local _dirpath="${6}"    # If not specified, create a new dir under current dir
    local _download_dir="${7}"
    local _starting="${_NEXUS_START}"
    if [ -z "${_ver}" ] || [ "${_ver}" == "latest" ]; then
        local _location="$(curl -sSf -I "https://download.sonatype.com/clm/server/latest.tar.gz" | grep -i '^location:')"
        if [[ "${_location}" =~ nexus-iq-server-([0-9.]+-[0-9]+)-bundle.tar.gz ]]; then
            _ver="${BASH_REMATCH[1]}"
        fi
    fi
    [ -z "${_ver}" ] && return 1
    if [ -z "${_port}" ]; then
        _port="$(_find_port "8070" "" "^8071$")"
        [ -z "${_port}" ] && return 1
        _log "INFO" "Using port: ${_port}" >&2
    fi
    if [ -n "${_dbname}" ]; then
        if [[ "${_dbname}" =~ _ ]]; then
            _log "WARN" "PostgreSQL allows '_' but not this function, so removing"
            _dbname="$(echo "${_dbname}" | tr -d '_')"
        fi
        # I think PostgreSQL doesn't work with mixed case.
        _dbname="$(echo "${_dbname}" | tr '[:upper:]' '[:lower:]')"
    fi
    if [ -z "${_dirpath}" ]; then
        _dirpath="./nxiq_${_ver}"
        [ -n "${_dbname}" ] && _dirpath="${_dirpath}_${_dbname}"
        [ "${_port}" != "8070" ] && _dirpath="${_dirpath}_${_port}"
    fi
    _prepare_install "${_dirpath}" "https://download.sonatype.com/clm/server/nexus-iq-server-${_ver}-bundle.tar.gz" "${r_NEXUS_LICENSE_FILE}" || return $?
    local _license_path="${_LICENSE_PATH}"

    local _jar_file="$(find ${_dirpath%/} -maxdepth 2 -type f -name 'nexus-iq-server*.jar' 2>/dev/null | sort | tail -n1)"
    [ -z "${_jar_file}" ] && return 11
    local _cfg_file="$(find ${_dirpath%/} -maxdepth 2 -type f -name 'config.yml' 2>/dev/null | sort | tail -n1)"
    [ -z "${_cfg_file}" ] && return 12

    if [ ! -f "${_cfg_file}.orig" ]; then
        cp -p "${_cfg_file}" "${_cfg_file}.orig"
    fi
    # TODO: From v138, most of configs need to use API: https://help.sonatype.com/iqserver/automating/rest-apis/configuration-rest-api---v2
    grep -qE '^hdsUrl:' "${_cfg_file}" || echo -e "hdsUrl: https://clm-staging.sonatype.com/\n$(cat "${_cfg_file}")" > "${_cfg_file}"
    grep -qE '^licenseFile' "${_cfg_file}" || echo -e "licenseFile: ${_license_path%/}\n$(cat "${_cfg_file}")" > "${_cfg_file}"
    grep -qE '^\s*port: 8070' "${_cfg_file}" && sed -i.tmp 's/port: 8070/port: '${_port}'/g' "${_cfg_file}"
    grep -qE '^\s*port: 8071' "${_cfg_file}" && sed -i.tmp 's/port: 8071/port: '$((${_port} + 1))'/g' "${_cfg_file}"

    if [ -n "${_dbname}" ]; then
        # NOTE: currently assuming "database:" is the end of file
        cat << EOF > ${_cfg_file}
$(sed -n '/^database:/q;p' ${_cfg_file})
database:
  type: postgresql
  hostname: $(hostname -f)
  port: 5432
  name: ${_dbname}
  username: ${_dbusr}
  password: ${_dbpwd}
EOF
        if ! _postgresql_create_dbuser "${_dbusr}" "${_dbpwd}" "${_dbname}"; then
            _log "WARN" "Failed to create ${_dbusr} or ${_dbname}"
        fi
    fi

    [ ! -d ./log ] && mkdir -m 777 ./log
    if _isYes "${_starting}"; then
        echo "Starting with: java -jar ${_jar_file} server ${_cfg_file} >./log/iq-server.out 2>./log/iq-server.err &"; sleep 3
        eval "java -jar ${_jar_file} server ${_cfg_file} >./log/iq-server.out 2>./log/iq-server.err &"
    else
        cd "${_dirpath%/}" || return $?
        echo "To start: java -jar ${_jar_file} server ${_cfg_file} 2>./log/iq-server.err"
        type iqStart &>/dev/null && echo "      Or: iqStart"
    fi
}






### Main #######################################################################################################
main() {
    # Clear the log file if not empty
    [ -s "${_LOG_FILE_PATH}" ] && gzip -S "_$(date +'%Y%m%d%H%M%S').gz" "${_LOG_FILE_PATH}" &>/dev/null
    [ -n "${_LOG_FILE_PATH}" ] && touch ${_LOG_FILE_PATH} && chmod a+w ${_LOG_FILE_PATH}
    # Just in case, creating the work directory
    [ -n "${_WORK_DIR}" ] && [ ! -d "${_WORK_DIR}/sonatype" ] && mkdir -p -m 777 ${_WORK_DIR}/sonatype

    # Checking requirements (so far only a few commands)
    if [ "`uname`" = "Darwin" ]; then
        if which gsed &>/dev/null && which ggrep &>/dev/null; then
            _log "DEBUG" "gsed and ggrep are available."
        else
            _log "ERROR" "gsed and ggrep are required (brew install gnu-sed ggrep)"
            return 1
        fi
    fi

    if ! ${_AUTO}; then
        _log "DEBUG" "_check_update $BASH_SOURCE with force:N"
        _check_update "$BASH_SOURCE" "" "N"
    fi

    # If _RESP_FILE is populated by -r xxxxx.resp, load it
    if [ -s "${_RESP_FILE}" ];then
        _load_resp "${_RESP_FILE}"
    elif ! ${_AUTO}; then
        _ask "Would you like to load your response file?" "N" "" "N" "N"
        _isYes && _load_resp
    fi
    # Command line arguments are stronger than response file
    [ -n "${_REPO_FORMATS_FROM_ARGS}" ] && r_REPO_FORMATS="${_REPO_FORMATS_FROM_ARGS}"
    [ -n "${_NEXUS_VERSION_FROM_ARGS}" ] && r_NEXUS_VERSION="${_NEXUS_VERSION_FROM_ARGS}"
    [ -n "${_NEXUS_DBNAME_FROM_ARGS}" ] && r_NEXUS_DBNAME="${_NEXUS_DBNAME_FROM_ARGS}"

    if ! ${_AUTO}; then
        interview
        _ask "Interview completed. Would like you like to start configuring?" "Y" "" "N" "N"
        if ! _isYes; then
            echo 'Bye!'
            return
        fi
    fi

    if _isYes "${r_NEXUS_INSTALL}"; then
        #echo "NOTE: If 'password' is asked, please type 'sudo' password." >&2
        echo "Starting IQ installation..." >&2
        _NEXUS_START="Y" f_install_iq || return $?
    fi
    if [ -z "${r_NEXUS_URL:-"${_NEXUS_URL}"}" ] || ! _wait_url "${r_NEXUS_URL:-"${_NEXUS_URL}"}"; then
        _log "ERROR" "${r_NEXUS_URL:-"${_NEXUS_URL}"} is unreachable"
        return 1
    fi

    _log "INFO" "Setup completed. (log:${_LOG_FILE_PATH})"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || [[ "$1" == "help" ]]; then
        if [[ "$2" =~ ^f_ ]] && type _help &>/dev/null; then
            _help "$2" | less
        elif [ "$2" == "list" ] && type _list &>/dev/null; then
            _list | less
        else
            usage | less
        fi
        exit 0
    fi

    # parsing command options (help is handled before calling 'main')
    _REPO_FORMATS_FROM_ARGS=""
    _NEXUS_VERSION_FROM_ARGS=""
    _NEXUS_DBNAME_FROM_ARGS=""
    while getopts "ADf:r:v:d:" opts; do
        case $opts in
            A)
                _AUTO=true
                ;;
            D)
                _DEBUG=true
                ;;
            r)
                _RESP_FILE="$OPTARG"
                ;;
            f)
                _REPO_FORMATS_FROM_ARGS="$OPTARG"
                ;;
            v)
                _NEXUS_VERSION_FROM_ARGS="$OPTARG"
                ;;
            d)
                _NEXUS_DBNAME_FROM_ARGS="$OPTARG"
                ;;
			*)
				echo "Unsupported command line argument: $opts"
				exit 1
				;;
        esac
    done

    main
fi