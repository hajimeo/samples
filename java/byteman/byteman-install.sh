#!/usr/bin/env bash
# Ref: https://github.com/myllynen/byteman-automation-tutorial/tree/master/byteman-automation-tool
#

_VER="${1:-"4.0.7"}"
_WORD_DIR="/var/tmp/share"

function f_setup() {
    local _ver="${1:-"${_VER}"}"
    local _dir="${2:-"${_WORD_DIR}"}"

    which bmjava && return 0

    if [ ! -d "${_dir}" ]; then
        mkdir -p -m 777 "${_dir}" || return $?
    fi
    curl -o "${_dir%/}/byteman-download-${_ver}-bin.zip" -C - --retry 3 "https://downloads.jboss.org/byteman/${_ver}/byteman-download-${_ver}-bin.zip"
    unzip "${_dir%/}/byteman-download-${_ver}-bin.zip" -d ${_dir%/} || return $?
    export BYTEMAN_HOME=${_dir%/}/byteman-download-${_ver}
    export PATH=$BYTEMAN_HOME/bin:$PATH
}

function f_jarp() {
    local _jarfile="$1"

    classes=$(unzip -l "${_jarfile}" | awk '/\.class$/ {print $4}' | sed -e 's,/,.,g' -e 's,\.class,,g' | sort)

    javap -classpath "${_jarfile}" -p $classes | grep -v lambda | while IFS= read -r line; do
        line=" $line"
        method=
        case $line in
            *\ class\ *) class=${line/* class }; class=${class/ *}; ;;
            *\(*) method=${line/(*}; method=${method/* } ; method=${method/*.} ;;
        esac
        if [ -n "$class" -a -n "$method" ]; then
            echo $class\#$method
        fi
    done
}

if [ "$0" = "$BASH_SOURCE" ]; then
    f_setup
fi