#!/usr/bin/env bash
# curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/patch_scala.sh


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
    local _p=`lsof -ti:${_port}`
    if [ -z "${_p}" ]; then
        echo "Nothing running on port ${_port}"
        return 11
    fi
    local _user="`stat -c '%U' /proc/${_p}`"
    local _dir="$(dirname `readlink /proc/${_p}/exe` 2>/dev/null)"
    export JAVA_HOME="$(dirname $_dir)"
    export CLASSPATH=".:`sudo -u ${_user} $JAVA_HOME/bin/jcmd ${_p} VM.system_properties | sed -nr 's/^java.class.path=(.+$)/\1/p' | sed 's/[\]:/:/g'`"
}

function f_jargrep() {
    local _class="${1}"
    local _path="${2:-.}"
    local _cmd="jar -tf"
    which jar &>/dev/null || _cmd="less"
    find -L ${_path%/} -type f -name '*.jar' -print0 | xargs -0 -n1 -I {} bash -c "${_cmd} {} | grep -w '${_class}' >&2 && echo {}"
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

    if [ ! -d "${_compiled_dir_or_class_name}" ]; then
        local _class_fullpath="`find . -name "${_compiled_dir_or_class_name}.class" -print`"
        _compiled_dir_or_class_name="`dirname ${_class_fullpath}`"
    fi
    echo "Updating ${_jar_filepath} ..."
    $JAVA_HOME/bin/jar -uvf ${_jar_filepath} ${_compiled_dir_or_class_name%/}/*.class || exit $?
    cp -f ${_jar_filepath} ${_jar_filename}.patched
}

### Main ###############################
if [ "$0" = "$BASH_SOURCE" ]; then
    _PORT="$1"
    _CLASS_NAME="$2"
    _APP_LIB_DIR_OR_JAR="$3"

    if [ -z "$_PORT" ]; then
        echo "At this moment, a port number (1st arg) is required to use this script (used to find a PID)"
        exit 1
    fi
    if [ ! -s "${_CLASS_NAME}.scala" ]; then
        echo "At this moment, a scala class name (2nd arg) is required to use this script"
        exit 1
    fi
    if [ ! -e "${_APP_LIB_DIR_OR_JAR}" ]; then
        echo "An application lib dir or a jar path (3rd arg) is required to use this script"
        exit 1
    fi

    f_setup_scala
    f_javaenvs "$_PORT" || exit $?
    scalac "${_CLASS_NAME}.scala" || exit $?

    if [ -d "${_APP_LIB_DIR_OR_JAR}" ]; then
        for _j in `f_jargrep "${_CLASS_NAME}.class" "${_APP_LIB_DIR_OR_JAR}"`; do
            f_update_jar "${_j}" "${_CLASS_NAME}"
        done
    else
        f_update_jar "${_APP_LIB_DIR_OR_JAR}" "${_CLASS_NAME}"
    fi
fi