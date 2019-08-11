#!/usr/bin/env bash
# curl -o /var/tmp/share/patch_java.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/patch_java.sh
#
# TODO: currently the script filename needs to be "ClassName.scala" or "ClassName.java" (case sensitive)
#

function usage() {
    cat << EOS
Patch one class file by compiling and updating one jar

\$ bash $0 <port> <ClassName>.[java|scala] <some.jar> [specific_ClassName] [not_compile]

    <port>: Port number to get a PID
    <ClassName>.[java|scala]: A file path of your java or scala file
    <some.jar>: A file path to your jar file which will be updated
    [specific_ClassName]: Sometimes filename is not equal to actual classname
    [not_compile]: If 'Y', not compiling

Or, to start scala console (REPL):
\$ source /var/tmp/share/patch_java.sh
\$ f_scala [<port>]
EOS
}

function f_setup_scala() {
    local _ver="${1:-2.12.3}"
    local _extract_dir="${2:-/var/tmp/share}"
    local _inst_dir="${3:-/usr/local/scala}"

    if [ -d "$SCALA_HOME" ]; then
        echo "SCALA_HOME is already set so that skipping setup scala"
        return
    fi

    if [ ! -x ${_inst_dir%/}/bin/scala ]; then
        if [ ! -d "${_extract_dir%/}/scala-${_ver}" ]; then
            if [ ! -s "${_extract_dir%/}/scala-${_ver}.tgz" ]; then
                curl --retry 3 -C - -o "${_extract_dir%/}/scala-${_ver}.tgz" "https://downloads.lightbend.com/scala/${_ver}/scala-${_ver}.tgz" || return $?
            fi
            tar -xf "${_extract_dir%/}/scala-${_ver}.tgz" -C "${_extract_dir%/}/" || return $?
            chmod a+x ${_extract_dir%/}/scala-${_ver}/bin/*
        fi
        [ -d "${_inst_dir%/}" ] || ln -s "${_extract_dir%/}/scala-${_ver}" "${_inst_dir%/}"
    fi
    export SCALA_HOME=${_inst_dir%/}
    export PATH=$PATH:$SCALA_HOME/bin
}

function f_javaenvs() {
    local _port="${1}"
    local _p=`lsof -ti:${_port} -s TCP:LISTEN`
    if [ -z "${_p}" ]; then
        echo "Nothing running on port ${_port}"
        return 11
    fi
    local _user="`stat -c '%U' /proc/${_p}`"
    local _dir="$(dirname `readlink /proc/${_p}/exe` 2>/dev/null)"
    export JAVA_HOME="$(dirname $_dir)"
    if [ -z "$CLASSPATH" ]; then
        export CLASSPATH=".:`sudo -u ${_user} $JAVA_HOME/bin/jcmd ${_p} VM.system_properties | sed -nr 's/^java.class.path=(.+$)/\1/p' | sed 's/[\]:/:/g'`"
    else
        export CLASSPATH="${CLASSPATH%:}:`sudo -u ${_user} $JAVA_HOME/bin/jcmd ${_p} VM.system_properties | sed -nr 's/^java.class.path=(.+$)/\1/p' | sed 's/[\]:/:/g'`"
    fi
}

function f_scala() {
    local _port="${1}"
    f_setup_scala
    if [[ "${_port}" =~ ^[0-9]+$ ]]; then
        f_javaenvs "${_port}"
    else
        echo "No port, so not detecting/setting JAVA_HOME and CLASSPATH...";slee 3
    fi
    scala
}

function f_jargrep() {
    local _class="${1}"
    local _path="${2:-.}"
    local _cmd="less"
    if [ -e $JAVA_HOME/bin/jar ]; then
        _cmd="$JAVA_HOME/bin/jar -tf"
    elif which jar &>/dev/null; then
        _cmd="jar -tf"
    fi
    find -L ${_path%/} -type f \( -name '*.jar' -or -name '*.war' \) -print0 | xargs -0 -n1 -I {} bash -c "${_cmd} {} | grep -w '${_class}' >&2 && echo '^ Jar: {}'"
}

function f_update_jar() {
    local _jar_filepath="$1"
    local _compiled_dir="$2"
    local _class_name="$3"

    if [ ! -d "$JAVA_HOME" ]; then
        echo "JAVA_HOME is not set. Use 'f_javaenvs <port>'."
        return 1
    fi

    local _jar_filename="$(basename ${_jar_filepath})"
    if [ ! -s "${_jar_filename}.orig" ]; then
        cp -p ${_jar_filepath} ${_jar_filename}.orig || return $?
    fi

    if [ ! -d "${_compiled_dir}" ]; then
        _compiled_dir="`dirname "$(find . -name "${_compiled_dir}.class" -print | tail -n1)"`"
        if [ "${_compiled_dir}" = "." ] || [ -z "${_compiled_dir}" ]; then
            echo "Please check 'package' of ${_compiled_dir} and make dir."
            return 1
        fi
    fi

    local _class_file_path="${_compiled_dir%/}/*.class"
    [ -n "${_class_name}" ] && _class_file_path="${_compiled_dir%/}/${_class_name}[.$]*class"

    echo "Updating ${_jar_filepath} with ${_class_file_path} ..."
    $JAVA_HOME/bin/jar -uvf ${_jar_filepath} ${_class_file_path} || return $?
    cp -f ${_jar_filepath} ${_jar_filename}.patched
    return 0
}

### Main ###############################
if [ "$0" = "$BASH_SOURCE" ]; then
    _PORT="$1"
    _CLASS_FILEPATH="$2"
    _JAR_FILEPATH="$3"
    _UPDATING_CLASSNAME="$4"
    _NOT_COMPILING="$5"

    if [ -z "$_PORT" ]; then
        echo "A port number (1st arg) to find PID is required."
        usage
        exit 1
    fi

    f_javaenvs "$_PORT" || exit $?

    # If _CLASS_FILEPATH is given, compiling.
    if [ -n "${_CLASS_FILEPATH}" ]; then
        _CLASS_FILENAME="$(basename "${_CLASS_FILEPATH}")"
        if [ -z "${_UPDATING_CLASSNAME}" ]; then
            _CLASS_NAME="${_CLASS_FILENAME%.*}"
        else
            _CLASS_NAME="${_UPDATING_CLASSNAME}"
        fi
        _EXT="${_CLASS_FILENAME##*.}"

        if [ -n "${_JAR_FILEPATH}" ] && [ -d "${_JAR_FILEPATH}" ]; then
            f_jargrep "${_CLASS_NAME}.class" "${_JAR_FILEPATH}"
            [ -n "${_UPDATING_CLASSNAME}" ]  && f_jargrep "${_UPDATING_CLASSNAME}.class" "${_JAR_FILEPATH}"
            echo "Please pick a jar file from above, and re-run the script:
$0 '$1' '$2' '<jar path from above>' '$4' 'Y'"
            exit 0
        fi

        if [ "${_EXT}" = "scala" ]; then
            f_setup_scala
            _CMD="scalac"
        elif [ "${_EXT}" = "java" ]; then
            if [ -n "${_JAR_FILEPATH}" ]; then
                _DIR_PATH="$(dirname $($JAVA_HOME/bin/jar -tvf ${_JAR_FILEPATH} | grep -oE "[^ ]+${_CLASS_NAME}.class"))"
                if [ ! -d "${_DIR_PATH}" ]; then
                    mkdir -p "${_DIR_PATH}" || exit $?
                fi
                mv -f ${_CLASS_FILEPATH} ${_DIR_PATH%/}/ || exit $?
                _CLASS_FILEPATH=${_DIR_PATH%/}/${_CLASS_FILENAME}
            fi

            _CMD="$JAVA_HOME/bin/javac"
        fi

        if [ -z "${_NOT_COMPILING}" ]; then
            # to avoid Java heap space error (default seems to be set to 256m)
            JAVA_OPTS=-Xmx1024m ${_CMD} "${_CLASS_FILEPATH}" || exit $?
        fi
    fi

    # If _JAR_FILEPATH is given, updating the jar
    if [ -n "${_JAR_FILEPATH}" ] && [ -n "${_CLASS_NAME}" ]; then
        f_update_jar "${_JAR_FILEPATH}" "${_CLASS_NAME}" "${_UPDATING_CLASSNAME}" || exit $?
        echo "Completed. Please restart the process (current PID=`lsof -ti:${_PORT} -s TCP:LISTEN`)."
    else
        echo "No jar filepath or class name to update."
    fi
fi