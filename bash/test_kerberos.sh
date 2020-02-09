#!/usr/bin/env bash
# curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/test_kerberos.sh

function _set_java_envs() {
    local _port="${1}"
    JAVA_PID=`lsof -ti:${_port}`
    if [ -z "${JAVA_PID}" ]; then
        echo "ERROR: Nothing running on port ${_port}" >&2
        return 1
    fi
    local _dir="$(dirname `readlink /proc/${JAVA_PID}/exe` 2>/dev/null)"
    JAVA_HOME="$(dirname $_dir)"
    JAVA_USER="`stat -c '%U' /proc/${JAVA_PID}`"
}

function check_java_flags() {
    local _port="${1}"
    _set_java_envs "${_port}" || return $?
    [ -z "$JAVA_USER" ] && return 1
    sudo -u $JAVA_USER $JAVA_HOME/bin/jcmd $JAVA_PID VM.system_properties | tee /tmp/_java_flags_${_port}.out | grep -E '^(java|javax)\.security'
}

function check_jce() {
    local _port="${1}"
    _set_java_envs "${_port}" || return $?
    echo "INFO: Checking JCE under $JAVA_HOME ..." >&2
    $JAVA_HOME/bin/jrunscript -e 'print(javax.crypto.Cipher.getMaxAllowedKeyLength("RC5") >= 256);'
}

function test_reverse_dns_lookup() {
    local _fqdn="$1"
    [ -z "${_fqdn}" ] && _fqdn="`hostname -f`"
    local _resolved=1
    for _ip in `hostname -I`; do
        if ! python -c "import socket;print socket.gethostbyaddr('${_ip}')" | grep -qF "'${_fqdn}'"; then
            echo "DEBUG: ${_ip} is not resolved to ${_fqdn}" >&2
        else
            echo "INFO: ${_ip} is resolved to ${_fqdn}" >&2
            _resolved=0
        fi
    done
    # one hostname to IP addresses
    # language=JavaScript
    [ -n "$JAVA_HOME" ] && $JAVA_HOME/bin/jrunscript -e "var ips = java.net.InetAddress.getAllByName('`hostname -f`'); for (var i in ips) println(ips[i]);"
    return ${_resolved}
}

function test_keytab() {
    local _keytab="$1"
    local _principal="$2"

    ls -l ${_keytab} || return $?
    klist -kte "${_keytab}" || return $?

    [ -z "${_principal}" ] && _principal="`klist -k ${_keytab} | grep -m1 '@' | awk '{print $2}'`"
    echo "principal = ${_principal}" >&2

    if ! kinit -kt ${_keytab} ${_principal}; then
        KRB5_TRACE=/dev/stdout kinit -kt ${_keytab} ${_principal} || return $?
    fi

    # kvno [-c ccache] [-e etype] [-q] [-h] [-P] [-S sname] [-U for_user] service1 service2 ...
    if ! kvno -k ${_keytab} ${_principal}; then
        KRB5_TRACE=/dev/stdout kvno -k ${_keytab} ${_principal} || return $?
    fi
    return 0
}

# TODO: Start web server by using JAAS or keytab/principal for SPNEGO test
function test_spnego() {    # a.k.a. gssapi
    local _url_or_port="$1" # eg http://`hostname -f`:8188/
    local _keytab="$2"
    if [[ "${_url_or_port}" =~ ^[0-9]+$ ]]; then
        # NOTE: if port, currently only using HTTP (no TLS/SSL)
        _url_or_port="http://`hostname -f`:${_url_or_port}/"
    fi

    if [ -s ${_keytab} ]; then
        local _principal="`klist -k ${_keytab} | grep -m1 '@' | awk '{print $2}'`"
        echo "principal = ${_principal}" >&2
        kinit -kt ${_keytab} ${_principal} || return $?
    fi
    echo "url = ${_url_or_port}" >&2
    if ! curl -s --negotiate -u : -L -k -f "${_url_or_port}"; then #--trace-ascii -
        curl -v --negotiate -u : -L -k -f "${_url_or_port}" || return $?
    fi
    return 0
}

function check_with_ldapsearch() {
    local __doc__="Check groups with ldapsearch (can use KRB5_CONFIG)"
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
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        echo "# Java security flags of a process which is listening on port ${1}"
        check_java_flags "$1"
        echo ""
        check_jce "$1"
        echo ""

        echo "# Test this hostname's reverse lookup"
        test_reverse_dns_lookup || echo " failed!"
        echo ""

        _JAAS="$(cat /tmp/_java_flags_${1}.out | grep '^java.security.auth.login.config' | cut -d "=" -f 2)"
        if [ -s "${_JAAS}" ]; then
            echo "# Test Keytab(s) in ${_JAAS}"
            for _kt_p in $(cat "${_JAAS}" | sed -n -r "N;s/\n/,/;s/\s*\b(keyTab|principal) ?= ?['\"]?([^'\"]+)['\"]?/\2/gpI" | sort | uniq); do
                [[ ! "${_kt_p}" =~ ^([^,]+),(.+) ]] && continue
                _KEYTAB="${BASH_REMATCH[1]}"
                _PRINCIPAL="${BASH_REMATCH[2]}"

                echo "## ${_kt_p}"
                test_keytab "${_KEYTAB}" "${_PRINCIPAL}" || echo " failed!"
            done
            echo ""

            _CLIENT_KEYTAB="$(cat "${_JAAS}" | grep -Pzio "(?s)^Client ?\{[^}]+\}" | sed -n -r "s/^\s*(keyTab) ?= ?['\"]?([^'\"]+)['\"]?/\2/pI")"
            if [ -s "${_CLIENT_KEYTAB}" ]; then
                echo "# Test SPNEGO with ${_CLIENT_KEYTAB}"
                test_spnego $1 "${_CLIENT_KEYTAB}" || echo " failed!"
                echo ""
            fi
        fi

        # TODO: add check_with_ldapsearch
    else
        echo "source $BASH_SOURCE"
        # typeset -F | grep -E '^declare -f (check|test)_' | cut -d' ' -f3
    fi
fi