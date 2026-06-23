: "${_INSTALL_DIR:=""}"
: "${_WORK_DIR:=""}"
: "${_LIB_EXTRACT_DIR:=""}"
: "${_PID:=""}"
: "${_TIMEOUT:="30"}"
_GROOVY_CLASSPATH=""

function usage() {
    echo "
USAGE:
    sh ./nrm378-groovy-launcher.sh /path/to/script.groovy [script_args]

PURPOSE:
    Invoke Groovy command using the library from Nexus 3.78 or higher jar file.

ENVIRONMENT VARIABLES:
    _INSTALL_DIR: Optional. Nexus installation directory. Best effort to auto-detect if not provided.
    _WORK_DIR: Optional. Nexus work directory. Best effort to auto-detect if not provided.
    _LIB_EXTRACT_DIR: Optional. A temp directory to extract the groovy and postgres jar files if needed. Default to ${_WORK_DIR%/}/tmp.
    _PID: Optional. Process ID of the Nexus instance. Best effort to auto-detect if not provided.
    _TIMEOUT: Optional. Timeout in seconds for Groovy script execution. Default is ${_TIMEOUT}.

REQUIREMENTS:
    'unzip' needs to be installed and in the PATH
"
}

function setGlobals() { # Best effort. may not return accurate dir path
    local __doc__="Populate PID and directory path global variables etc."
    local _pid="${1:-"${_PID}"}"
    if [ -z "${_pid}" ]; then
        _pid="$(ps auxwww | grep -w -e 'NexusMain' -e 'sonatype-nexus-repository' | grep -vw grep | awk '{print $2}' | tail -n1)"
        _PID="${_pid}"
        [ -z "${_pid}" ] && return 1
    fi
    if [ ! -d "${_INSTALL_DIR}" ]; then
        if [ -n "${_pid}" ]; then
            _INSTALL_DIR="$(ps wwwp ${_pid} | sed -n -E 's/.+-Dexe4j.moduleName=([^ ]+)\/bin\/nexus .+/\1/p' | head -1)"
            if [ -z "${_INSTALL_DIR}" ]; then
                # from 3.80+, this could be `-(jar|classpath) /path/to/sonatype-nexus-repository-{ver}.jar`
                _INSTALL_DIR="$(ps wwwp ${_pid} | sed -n -E 's/.+ ([^ ]+)\/bin\/sonatype-nexus-repository\-[0-9.]+\-[0-9]+\.jar.*/\1/p' | head -1)"
            fi
        fi
        [ -d "${_INSTALL_DIR}" ] || return 1
    fi
    if [ ! -d "${_WORK_DIR}" ] && [ -d "${_INSTALL_DIR%/}" ]; then
        _WORK_DIR="$(ps wwwp ${_pid} | sed -n -E 's/.+-Dkaraf.data=([^ ]+) .+/\1/p' | head -n1)"
        case "${_WORK_DIR}" in
            /*) ;;
            *) _WORK_DIR="${_INSTALL_DIR%/}/${_WORK_DIR}" ;;
        esac
        [ -d "${_WORK_DIR}" ] || return 1
    fi
}

function prepareLibForSingleJar() {
    local __doc__="Prepare the lib directory for single jar"
    local _single_jar="${1}"
    local _lib_extract_dir="${2:-"${_LIB_EXTRACT_DIR:-"${_WORK_DIR%/}/tmp"}"}"
    if [ ! -s "${_single_jar}" ]; then
        echo "ERROR:No single jar file provided." >&2
        return 1
    fi
    if ! command -v unzip >/dev/null 2>&1; then
        echo "ERROR:unzip not found, please install it." >&2
        return 1
    fi
    local _groovy_ver="$(unzip -l "${_single_jar}" | sed -n -E 's/.+ BOOT-INF\/lib\/groovy-(3\..+)\.jar/\1/p')"
    if [ -z "${_groovy_ver}" ]; then
        echo "ERROR:No groovy jar file found in ${_single_jar}." >&2
        return 1
    fi
    if [ -s "${_lib_extract_dir%/}/BOOT-INF/lib/groovy-${_groovy_ver}.jar" ]; then
        # Assuming all good
        return 0
    fi
    local _postgres_ver="$(unzip -l "${_single_jar}" | sed -n -E 's/.+ BOOT-INF\/lib\/postgresql-(.+)\.jar/\1/p')"
    if [ ! -d "${_lib_extract_dir%/}" ]; then
        mkdir -v -p "${_lib_extract_dir%/}" || return $?
    fi
    if [ ! -s "${_lib_extract_dir%/}/BOOT-INF/lib/groovy-${_groovy_ver}.jar" ]; then
        unzip -q -d "${_lib_extract_dir%/}" "${_single_jar}" "BOOT-INF/lib/groovy-${_groovy_ver}.jar"
        unzip -q -d "${_lib_extract_dir%/}" "${_single_jar}" "BOOT-INF/lib/groovy-sql-${_groovy_ver}.jar"
        unzip -q -d "${_lib_extract_dir%/}" "${_single_jar}" "BOOT-INF/lib/postgresql-${_postgres_ver}.jar"
    fi
    if [ ! -s "${_lib_extract_dir%/}/BOOT-INF/lib/groovy-${_groovy_ver}.jar" ]; then
        echo "ERROR:Failed to unzip libs from ${_single_jar}." >&2
        return 1
    fi
}

function main() {
    # Only for 3.78+
    if [ ! -s "${1}" ]; then
        echo "ERROR:Groovy script file not found at ${1}." >&2
        return 1
    fi

    setGlobals || return $?
    
    local _single_jar="$(find "${_INSTALL_DIR%/}/bin" -type f -name 'sonatype-nexus-repository-3.*.jar' 2>/dev/null | head -n1)"
    if [ ! -s "${_single_jar}" ]; then
        echo "ERROR:No single jar file found under ${_INSTALL_DIR%/}/bin." >&2
        return 1
    fi
    prepareLibForSingleJar "${_single_jar}" "${_WORK_DIR%/}/tmp" || return $?

    local _groovy_jar="$(find "${_WORK_DIR%/}/tmp" -type f -name 'groovy-3.*.jar' 2>/dev/null | head -n1)"
    if [ ! -s "${_groovy_jar}" ]; then
        echo "ERROR:No groovy jar file under ${_INSTALL_DIR%/}." >&2
        return 1
    fi

    # Optional jars
    local _pgJar="$(find "${_WORK_DIR%/}/tmp" -type f -name 'postgresql-*.jar' 2>/dev/null | tail -n1)"
    if [ -s "${_pgJar}" ]; then
        if [ -z "${_GROOVY_CLASSPATH}" ]; then
            _GROOVY_CLASSPATH="${_pgJar}"
        else
            _GROOVY_CLASSPATH="${_GROOVY_CLASSPATH}:${_pgJar}"
        fi
    fi
    local _groovySqlJar="$(find "${_WORK_DIR%/}/tmp" -type f -name 'groovy-sql-3.*.jar' 2>/dev/null | tail -n1)"
    if [ -s "${_groovySqlJar}" ]; then
        if [ -z "${_GROOVY_CLASSPATH}" ]; then
            _GROOVY_CLASSPATH="${_groovySqlJar}"
        else
            _GROOVY_CLASSPATH="${_GROOVY_CLASSPATH}:${_groovySqlJar}"
        fi
    fi

    local _java="java"
    [ -d "${JAVA_HOME%/}" ] && _java="${JAVA_HOME%/}/bin/java"
    timeout ${_TIMEOUT:-30}s ${_java} -Dgroovy.classpath="${_GROOVY_CLASSPATH}" -jar "${_groovy_jar}" "$@"
    local _rc=$?
    if [ "${_rc}" -ne 0 ]; then
        echo "ERROR: Groovy execution failed with ${_rc} (timeout=${_TIMEOUT:-30}s)" >&2
    fi
    return "${_rc}"
}

if [ -z "$1" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ]; then
    usage
    exit 0
fi
main "$@"
