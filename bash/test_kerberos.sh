#!/usr/bin/env bash

function set_java_envs() {
    local _port="${1}"
    JAVA_PID=`lsof -ti:${_port}`
    if [ -z "${JAVA_PID}" ]; then
        echo "Nothing running on port ${_port}" >&2
        if [ -s /etc/hadoop/conf/hadoop-env.sh ]; then
            echo "Using hadoop-env.sh instead ..." >&2
            source /etc/hadoop/conf/hadoop-env.sh
            return $?
        else
            return 1
        fi
    fi
    local _dir="$(dirname `readlink /proc/${JAVA_PID}/exe` 2>/dev/null)"
    JAVA_HOME="$(dirname $_dir)"
    JAVA_USER="`stat -c '%U' /proc/${JAVA_PID}`"
}

function check_java_flags() {
    local _port="${1}"
    set_java_envs "${_port}" || return $?
    [ -z "$JAVA_USER" ] && return 1

    sudo -u $JAVA_USER $JAVA_HOME/bin/jcmd $JAVA_PID VM.system_properties | grep ^java.security
}

function test_jce_by_port() {
    local _port="${1}"
    set_java_envs "${_port}" || return $?
    echo "Checking JCE under $JAVA_HOME ..." >&2
    $JAVA_HOME/bin/jrunscript -e 'print (javax.crypto.Cipher.getMaxAllowedKeyLength("RC5") >= 256);'
}

function test_kvno() {
    local _keytab="$1"

    klist -kte "${_keytab}" || return $?

    local _principal="`klist -k ${_keytab} | grep -m1 '@' | awk '{print $2}'`"
    echo "Using principal ${_principal} ..." >&2

    if ! kinit -kt ${_keytab} ${_principal}; then
        KRB5_TRACE=/dev/stdout kinit -kt ${_keytab} ${_principal} || return $?
    fi

    # kvno [-c ccache] [-e etype] [-q] [-h] [-P] [-S sname] [-U for_user] service1 service2 ...
    if ! kvno -k ${_keytab} ${_principal}; then
        KRB5_TRACE=/dev/stdout kvno -k ${_keytab} ${_principal} || return $?
    fi
    echo "Success" >&2
}

function test_spnego() {    # a.k.a. gssapi
    local _url="$1" # eg http://`hostname -f`:8188/
    local _keytab="$2"

    if [ -s ${_keytab} ]; then
        local _principal="`klist -k ${_keytab} | grep -m1 '@' | awk '{print $2}'`"
        echo "Using principal ${_principal} ..." >&2
        kinit -kt ${_keytab} ${_principal}
    fi
    if ! curl -s --negotiate -u : -k -f "${_url}"; then #--trace-ascii -
        curl -v --negotiate -u : -k -f "${_url}" || return $?
    fi
    echo "Success" >&2
}

function test_dns_reverse_lookup() {
    if ! python -c "import socket;print socket.gethostbyaddr('`hostname -i`')" | grep -F "'`hostname -f`'"; then
        echo "Reverse lookup doesn't match with the hostname" >&2
        return 1
    fi
}

function test_with_ldapsearch() {
    local __doc__="Test groups with ldapsearch (can use KRB5_CONFIG)"
    local _search="$1"      # uid=testuser
    local _binddn="$2"      # uid=admin,cn=users,cn=accounts,dc=ubuntu,dc=localdomain
    local _searchbase="$3"  # cn=accounts,dc=ubuntu,dc=localdomain
    local _prot="${4:-"ldaps"}"
    local _port="${5:-"636"}"

    local _conf="${KRB5_CONFIG:-"/etc/krb5.conf"}"
    local _princ="`klist | grep '^Default principal' | awk '{print $3}'`"
    local _uid="`echo $_princ | cut -d'@' -f 1`"
    local _realm="`echo $_princ | cut -d'@' -f 2`"
    local _host="`grep -Pzo '(?s)'${_realm}'\s*=[\s\S]*?\}' ${_conf} | grep -w 'kdc' | cut -d '=' -f 2 | tr -d '[:space:]'`"

    if [ -n "${_binddn}" ]; then
        [ -z "${_searchbase}" ] && _searchbase="`echo ${_binddn} | grep -oP 'dc=.+'`"
        [ -z "${_search}" ] && _search="dn=${_binddn}"

        LDAPTLS_REQCERT=never ldapsearch -x -H ${_prot}://${_host}:${_port} -D "${_binddn}" -W -b "${_searchbase}" "${_search}" | grep 'memberOf'
    else
        [ -z "${_search}" ] && _search="uid=${_uid}"
        LDAPTLS_REQCERT=never ldapsearch -Y GSSAPI -H ${_prot}://${_host}:${_port} "${_search}"
    fi
}

### main ########################
if [ "$0" = "$BASH_SOURCE" ]; then
    echo "source $BASH_SOURCE"
fi