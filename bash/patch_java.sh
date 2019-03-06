#!/usr/bin/env bash
# curl -o /var/tmp/share/patch_java.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/patch_java.sh
# bash /var/tmp/share/patch_java.sh <port> <ClassName>.[java|scala] </some/path/to/filename.jar>
#
# Or
# . /var/tmp/share/patch_java.sh
# f_setup_scala
#
# TODO: currently the script filename needs to be "ClassName.scala" or "ClassName.java" (case sensitive)
#

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

function f_jargrep() {
    local _class="${1}"
    local _path="${2:-.}"
    local _cmd="less"
    if [ -e $JAVA_HOME/bin/jar ]; then
        _cmd="$JAVA_HOME/bin/jar -tf"
    elif which jar &>/dev/null; then
        _cmd="jar -tf"
    fi
    find -L ${_path%/} -type f -name '*.jar' -print0 | xargs -0 -n1 -I {} bash -c "${_cmd} {} | grep -w '${_class}' >&2 && echo '^ Jar: {}'"
}

function f_update_jar() {
    local _jar_filepath="$1"
    local _compiled_dir_or_class_name="$2"

    if [ ! -d "$JAVA_HOME" ]; then
        echo "JAVA_HOME is not set"
        return 1
    fi

    local _jar_filename="$(basename ${_jar_filepath})"
    if [ ! -s "${_jar_filename}.orig" ]; then
        cp -p ${_jar_filepath} ${_jar_filename}.orig || return $?
    fi

    local _class_file_path="${_compiled_dir_or_class_name%/}/*.class"
    if [ ! -d "${_compiled_dir_or_class_name}" ]; then
        _class_file_path="`find . -name "${_compiled_dir_or_class_name}.class" -print`"
        local _dir_path="`dirname ${_class_file_path}`"
        if [ "${_dir_path}" = "." ] || [ -z "${_dir_path}" ]; then
            echo "Please check 'package' of ${_compiled_dir_or_class_name} and make dir."
            return 1
        fi
    fi
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

    _CLASS_FILENAME="$(basename "${_CLASS_FILEPATH}")"
    _CLASS_NAME="${_CLASS_FILENAME%.*}"
    _EXT="${_CLASS_FILENAME##*.}"

    if [ -z "$_PORT" ]; then
        echo "At this moment, a port number (1st arg) is required to use this script (used to find a PID)."
        exit 1
    fi
    if [ ! -s "${_CLASS_FILEPATH}" ]; then
        echo "At this moment, a java/scala class name (3rd arg) is required to patch a class."
        exit 1
    fi
    if [ ! -e "${_JAR_FILEPATH}" ]; then
        echo "A jar path (3rd arg) is required to patch a class."
        exit 1
    fi

    f_javaenvs "$_PORT" || exit $?

    if [ -d "${_JAR_FILEPATH}" ]; then
        f_jargrep "${_CLASS_NAME}.class" "${_JAR_FILEPATH}"
        echo "Please pick a jar file from above, and re-run the script."
        exit 0
    fi

    if [ "${_EXT}" = "scala" ]; then
        f_setup_scala

        # to avoid Java heap space error (default seems to be set to 256m)
        JAVA_OPTS=-Xmx1024m scalac "${_CLASS_FILENAME}" || exit $?
    else
        _DIR_PATH="$(dirname $($JAVA_HOME/bin/jar -tvf ${_JAR_FILEPATH} | grep -oE "[^ ]+${_CLASS_NAME}.class"))"
        if [ ! -d "${_DIR_PATH}" ]; then
            mkdir -p "${_DIR_PATH}" || exit $?
        fi
        mv -f ${_CLASS_FILEPATH} ${_DIR_PATH%/}/ || exit $?
        _CLASS_FILEPATH=${_DIR_PATH%/}/${_CLASS_FILENAME}

        # to avoid Java heap space error (default seems to be set to 256m)
        JAVA_OPTS=-Xmx1024m $JAVA_HOME/bin/javac "${_CLASS_FILENAME}" || exit $?
    fi

    f_update_jar "${_JAR_FILEPATH}" "${_CLASS_NAME}" || exit $?
    echo "Completed. Please restart the process (current PID=`lsof -ti:${_PORT} -s TCP:LISTEN`)."
fi