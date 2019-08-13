#!/usr/bin/env bash
# Ref: https://github.com/myllynen/byteman-automation-tutorial/tree/master/byteman-automation-tool
#

_VER="${1:-"4.0.7"}"

function f_setup() {
    local _ver="${1:-"${_VER}"}"
    which bmjava && return 0
    curl -O -C - --retry 3 "https://downloads.jboss.org/byteman/${_ver}/byteman-download-${_ver}-bin.zip"
    unzip byteman-download-${_ver}-bin.zip
    export BYTEMAN_HOME=$(pwd)/byteman-download-${_ver}
    export PATH=$BYTEMAN_HOME/bin:$PATH
}

if [ "$0" = "$BASH_SOURCE" ]; then
    f_setup
fi