#!/usr/bin/env bash

function f_setup_scala() {
    local _ver="${1:-2.12.3}"
    local _extract_dir="${2:-/opt}"
    local _inst_dir="${3:-/usr/local/scala}"

    if [ -d "$SCALA_HOME" ]; then
        echo "SCALA_HOME is already set so that skipping setup scala"
        return
    fi

    if [ ! -d "${_extract_dir%/}/scala-${_ver}" ]; then
        if [ ! -s "${_extract_dir%/}/scala-${_ver}.tgz" ]; then
            curl --retry 3 -C - -o "${_extract_dir%/}/scala-${_ver}.tgz" "https://downloads.lightbend.com/scala/${_ver}/scala-${_ver}.tgz" || return $?
        fi
        tar -xf "${_extract_dir%/}/scala-${_ver}.tgz" -C "${_extract_dir%/}/" || return $?
        chmod a+x ${_extract_dir%/}/bin/*
    fi
    [ -d "${_inst_dir%/}" ] || ln -s "${_extract_dir%/}/scala-${_ver}" "${_inst_dir%/}"
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
    find -L ${_path%/} -type f -name '*.jar' -print0 | xargs -0 -n1 -I {} bash -c ''${_cmd}' {} | grep -qw '${_class}' && echo {}'
}


### Main ###############################
if [ "$0" = "$BASH_SOURCE" ]; then
    _PORT="$1"
    _CLASS_NAME="$2"
    _APP_LIB_DIR="$3"

    if [ -z "$_PORT" ]; then
        echo "At this moment, a port number (1st arg) is required to use this script (used to find a PID)"
        exit 1
    fi
    if [ ! -s "${_CLASS_NAME}.scala" ]; then
        echo "At this moment, a scala class name (2nd arg) is required to use this script"
        exit 1
    fi
    if [ ! -d "${_APP_LIB_DIR}" ]; then
        echo "At this moment, a application lib dir path (3rd arg) is required to use this script"
        exit 1
    fi

    f_setup_scala
    f_javaenvs "$_PORT" || exit $?
    scalac "${_CLASS_NAME}.scala" || exit $?

    for _j in `f_jargrep "${_CLASS_NAME}.class" "${_APP_LIB_DIR}"`; do
        _JAR_FILENAME="$(basename ${_j})"
        if [ ! -s "${_JAR_FILENAME}.orig" ]; then
            cp -p ${_j} ${_JAR_FILENAME}.orig || exit $?
        fi
        _CLASS_FULL_PATH="`find . -name "${_CLASS_NAME}.class" -print`"
        _CLASS_FULL_PATH_DIR="`dirname ${_CLASS_FULL_PATH}`"
        echo "Updating ${_j} ..."
        $JAVA_HOME/bin/jar -uvf ${_j} ${_CLASS_FULL_PATH_DIR%/}/*.class
    done
fi