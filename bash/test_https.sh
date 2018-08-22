#!/usr/bin/env bash

function get_ciphers() {
    # @see http://superuser.com/questions/109213/how-do-i-list-the-ssl-tls-cipher-suites-a-particular-website-offers
    # OpenSSL requires the port number.
    local _host="${1:-`hostname -f`}"
    local _port="${2:-443}"
    local _server=$_host:$_port
    local _delay=1
    ciphers=$(openssl ciphers 'ALL:eNULL' | sed -e 's/:/ /g')
    echo "Obtaining cipher list from $_server with $(openssl version)..."

    for cipher in ${ciphers[@]}; do
        result=$(echo -n | openssl s_client -cipher "$cipher" -connect $_server 2>&1)
        if [[ "$result" =~ ":error:" ]] ; then
            error=$(echo -n $result | cut -d':' -f6)
            echo -e "$cipher\tNO ($error)" >&2
        elif [[ "$result" =~ "Cipher is ${cipher}" || "$result" =~ "Cipher    :" ]] ; then
            echo -e "$cipher\tYES"
        else
            echo -e "$cipher\tUNKNOWN RESPONSE" >&2
            echo $result >&2
        fi
        sleep $_delay
    done
}

function export_key() {
    local _file="$1"
    local _pass="$2"
    local _alias="$3"
    local _type="$4"
    local _out="`basename $_file`.key"
    [ -z "$_type" ] && _type="${_file##*.}"

    if [ "$_type" = "pkcs8" ]; then
        openssl pkcs8 -outform PEM -in key.pkcs8 -out ${_out} -nocrypt
    elif [ "$_type" = "jks" ]; then
        keytool -importkeystore -noprompt -srckeystore ${_file} -srcstorepass "${_pass}" -srcalias ${_alias} \
         -destkeystore /tmp/tmpkeystore_$$.jks -deststoretype PKCS12 -deststorepass ${_pass} -destkeypass ${_pass} || return $?
        openssl pkcs12 -in /tmp/tmpkeystore_$$.jks -passin "pass:${_pass}" -nodes -nocerts -out ${_out} || return $?
        rm -f /tmp/tmpkeystore_$$.jks
    fi
    chmod 600 ${_out}
}

function start_https() {
    # @see https://docs.python.org/2/library/ssl.html#ssl.SSLContext.wrap_socket
    local _key="$1"
    local _crt="$2"
    local _doc_root="${3:-./}"
    local _host="${4:-0.0.0.0}"
    local _port="${5:-443}"
    which python &>/dev/null || return $?
    _key="`realpath "$_key"`"
    _crt="`realpath "$_crt"`"

    cd "$_doc_root" || return $?
    nohup python -c "import BaseHTTPServer,SimpleHTTPServer,ssl
httpd = BaseHTTPServer.HTTPServer(('${_host}', ${_port}), SimpleHTTPServer.SimpleHTTPRequestHandler)
try:
  httpd.socket = ssl.wrap_socket(httpd.socket, keyfile='${_key}', certfile='${_crt}', server_side=True, ssl_version=ssl.PROTOCOL_TLSv1_2)
except AttributeError:
  httpd.socket = ssl.wrap_socket(httpd.socket, keyfile='${_key}', certfile='${_crt}', server_side=True, ssl_version=ssl.PROTOCOL_TLS)
httpd.serve_forever()" &
    sleep 1
    cd - &>/dev/null
}

function check_pem_file() {
    local _file=$1
    file "$_file"

    if grep -qE "BEGIN.* PRIVATE KEY" "$_file"; then
        openssl rsa -noout -modulus -in "$_file" | openssl md5
    else
        openssl x509 -noout -modulus -in "$_file" | openssl md5
        openssl x509 -noout -text -in "$_file"
    fi
}

### main ########################
if [ "$0" = "$BASH_SOURCE" ]; then
    echo "source $BASH_SOURCE"
fi