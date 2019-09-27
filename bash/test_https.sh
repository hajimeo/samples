#!/usr/bin/env bash
# curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/test_https.sh
_TEST_PORT=34443

function get_ciphers() {
    # @see http://superuser.com/questions/109213/how-do-i-list-the-ssl-tls-cipher-suites-a-particular-website-offers
    # OpenSSL requires the port number.
    local _host="${1:-`hostname -f`}"
    local _port="${2:-443}"
    local _server=$_host:$_port
    local _delay=1

    if which nmap &>/dev/null; then
        nmap --script +ssl-enum-ciphers -p ${_port} ${_host}
        return $?
    fi

    ciphers=$(openssl ciphers 'ALL:eNULL' | sed -e 's/:/ /g')
    echo "Obtaining cipher list from $_server with $(openssl version)..." >&2

    for cipher in ${ciphers[@]}; do
        sleep ${_delay}
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
    done
}

function get_tls_versions() {
    local _host_port="$1"
    local _head="${2:-10}"
    local _delay=1

    for _v in ssl3 tls1 tls1_1 tls1_2; do  # 'ssl2' no longer works with openssl
        sleep ${_delay}
        local _output="`echo -n | openssl s_client -connect ${_host_port} -${_v} 2>/dev/null`"
        if echo "${_output}" | grep -qE '^ *Cipher *: *0000$'; then
            echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] WARN: '${_v}' failed." >&2
        else
            echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] INFO: '${_v}' worked"
            echo "${_output}" | head -n ${_head} | sed -nr 's/^(.+)$/    \1/gp'
        fi
    done
}

# convert .jks or .pkcs8 file to .key (and .crt if possible)
function export_key() {
    local _file="$1"
    local _pass="${2:-password}"
    local _alias="${3:-$(hostname -f)}"
    local _type="$4"

    local _basename="`basename $_file`"
    local _out_key="${_basename}.exported.key"
    local _out_crt="${_basename}.exported.crt"
    [ -z "$_type" ] && _type="${_file##*.}"

    if [ "$_type" = "pkcs8" ]; then
        openssl pkcs8 -outform PEM -in key.pkcs8 -out ${_out_key} -nocrypt
    elif [ "$_type" = "jks" ]; then
        if [ ! -x "${JAVA_HOME%/}/bin/keytool" ]; then
            echo "This function requires 'keytool' command in \$JAVA_HOME/bin." >&2
            return 1
        fi
        ${JAVA_HOME%/}/bin/keytool -importkeystore -noprompt -srckeystore ${_file} -srcstorepass "${_pass}" -srcalias ${_alias} \
         -destkeystore ${_basename}.p12.tmp -deststoretype PKCS12 -deststorepass "${_pass}" -destkeypass "${_pass}" || return $?
        openssl pkcs12 -in ${_basename}.p12.tmp -passin "pass:${_pass}" -nodes -nocerts -out ${_out_key}.tmp || return $?
        openssl rsa -in ${_out_key}.tmp -out ${_out_key}
        # 'sed' to remove Bag Attributes
        openssl pkcs12 -in ${_basename}.p12.tmp -passin "pass:${_pass}" -nokeys -chain | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > ${_out_crt} || return $?
        rm -f ${_basename}.*.tmp
    fi
    chmod 600 ${_out_key}
    ls -l ${_basename}.*
}

# generate .p12 (pkcs12) file
function gen_p12() {
    local _ca_crt="$1"
    local _srv_crt="$2"
    local _srv_key="$3"
    local _pass="${4:-password}"
    local _name="$5"
    if [ -z "${_name}" ]; then
        local _basename="$(basename ${_srv_crt})"
        _name="${_basename%.*}"
    fi
    # NOTE: If intermediate CA is used (TODO: does order matter?)
    #cat root.cer intermediate.cer > full_ca.cer
    openssl pkcs12 -export -chain -CAfile ${_ca_crt} -in ${_srv_crt} -inkey ${_srv_key} -name ${_name} -out ${_name}.p12 -passout "pass:${_pass}"
    # Verify
    if which keytool &>/dev/null; then
        keytool -list -keystore ${_name}.p12 -storetype PKCS12 -storepass "${_pass}"
    fi
}

function start_https() {
    # @see https://docs.python.org/2/library/ssl.html#ssl.SSLContext.wrap_socket
    local _key="$1"
    local _crt="$2"
    local _doc_root="${3:-./}"
    local _host="${4:-0.0.0.0}"
    local _port="${5:-$_TEST_PORT}"    # NOTE: port number lower than 1024 requires root privilege
    which python &>/dev/null || return $?
    if [ ! -s "${_key}" ]; then
        echo "ERROR: No key file specified or unreadable" >&2
        return 1
    fi
    if [ ! -s "${_crt}" ]; then
        echo "ERROR: No crt file specified or unreadable" >&2
        return 1
    fi
    _key="`realpath "$_key"`"
    _crt="`realpath "$_crt"`"

    echo "Starting ${_host}:${_port} in background, and redirecting outputs to /tmp/start_https.out" >&2
    cd "$_doc_root" || return $?
    nohup python -c "import BaseHTTPServer,SimpleHTTPServer,ssl
httpd = BaseHTTPServer.HTTPServer(('${_host}', ${_port}), SimpleHTTPServer.SimpleHTTPRequestHandler)
try:
  httpd.socket = ssl.wrap_socket(httpd.socket, keyfile='${_key}', certfile='${_crt}', server_side=True, ssl_version=ssl.PROTOCOL_TLSv1_2)
except AttributeError:
  httpd.socket = ssl.wrap_socket(httpd.socket, keyfile='${_key}', certfile='${_crt}', server_side=True, ssl_version=ssl.PROTOCOL_TLS)
httpd.serve_forever()" &>/tmp/start_https.out &
    sleep 1
    cd - &>/dev/null
}

function test_https() {
    local _host_port="${1:-"`hostname -f`:$_TEST_PORT"}"
    local _ca_cert="$2"

    if curl -sf -L "http://${_host_port}" > /dev/null; then
        echo "INFO: http (not https) works on ${_host_port}" >&2
    fi
    if ! curl -sf -L "https://${_host_port}" > /dev/null; then
        echo "INFO: Can't connect to https://${_host_port} without -k" >&2
    fi
    if ! curl -sSf -L -k "https://${_host_port}" > /dev/null; then
        echo "ERROR: Can't connect to https://${_host_port} even *with* -k" >&2
        return 1
    else
        echo "INFO: Can connect to https://${_host_port} with -k" >&2
    fi

    if [ -n "${_ca_cert}" ]; then
        if ! curl -sSf --cacert "${_ca_cert}" -f -L "https://${_host_port}" > /dev/null; then
            echo "WARN: Can't connect to https://${_host_port} with cacert:${_ca_cert}" >&2
        else
            echo "INFO: Can connect to https://${_host_port} with cacert:${_ca_cert}" >&2
        fi
    fi
    # TODO: 2 way SSL with --cert and --key
}

# output md5 hash of .key or .crt file
function check_pem_file() {
    local _file=$1
    local _use_pyasn1=$2

    file "$_file"
    if grep -qE "BEGIN.* PRIVATE KEY" "$_file"; then
        openssl rsa -noout -modulus -in "$_file" | openssl md5
    else
        openssl x509 -noout -modulus -in "$_file" | openssl md5
        openssl x509 -noout -text -in "$_file" | grep -E "Issuer:|Not Before|Not After|Subject:"
        openssl x509 -noout -fingerprint -sha1 -inform pem -in "$_file"
    fi

    # ref: https://stackoverflow.com/questions/16899247/how-can-i-decode-a-ssl-certificate-using-python
    if [[ "${_use_pyasn1}" =~ ^(y|Y) ]]; then
        python -c "from pyasn1_modules import pem, rfc2459
from pyasn1.codec.der import decoder
substrate = pem.readPemFromFile(open('${_file}'))
cert = decoder.decode(substrate, asn1Spec=rfc2459.Certificate())[0]
print(cert.prettyPrint())"
    fi
}

function get_certificate_from_https() {
    local _host="$1"
    local _port="${2:-443}"
    local _dest_filepath="$3"
    [ -z "${_dest_filepath}" ] && _dest_filepath=./${_host}_${_port}.crt
    echo -n | openssl s_client -connect ${_host}:${_port} -showcerts > /tmp/${_host}_${_port}.tmp || return $?
    sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' /tmp/${_host}_${_port}.tmp > ${_dest_filepath}
}

function gen_wildcard_cert() {
    local _domain="${1:-`hostname -d`}"
    [ -z "${_domain}" ] && _domain="standalone.localdomain"

    local _openssl_conf="./openssl.cnf"
    if [ -s "${_openssl_conf}" ]; then
        echo "INFO: ${_openssl_conf} exists, so not recreating...." >&2; sleep 3
    else
        curl -s -f -o "${_openssl_conf}" https://raw.githubusercontent.com/hajimeo/samples/master/misc/openssl.cnf
        echo "
        [ alt_names ]
        DNS.1 = ${_domain}
        DNS.2 = *.${_domain}" >> "${_openssl_conf}"
    fi

    # Create a root key file named “rootCA.key”
    if [ -s "./rootCA.key" ]; then
        echo "INFO: ./rootCA.key exists, so not creating..." >&2; sleep 3
    else
        openssl genrsa -out ./rootCA.key 2048
        # Create certificate of rootCA.key
        openssl req -x509 -new -sha256 -days 3650 -key ./rootCA.key -out ./rootCA.pem \
            -config "${_openssl_conf}" -extensions v3_ca \
            -subj "/CN=RootCA.${_domain}"
        # make sure only root user can access the key
        chmod 600 ./rootCA.key
        echo "INFO: Created ./rootCA.key" >&2
    fi

    # Always re-create a server (wildcard) key
    openssl genrsa -out ./wildcard.${_domain}.key 2048
    # Create CSR (Certificate Signed Request)
    openssl req -subj "/C=AU/ST=QLD/O=HajimeTest/CN=*.${_domain}" -extensions v3_req -sha256 -new -key ./wildcard.${_domain}.key -out ./wildcard.${_domain}.csr -config ${_openssl_conf}
    # Sign the server key (csr) to generate a server certificate
    openssl x509 -req -extensions v3_req -days 3650 -sha256 -in ./wildcard.${_domain}.csr -CA ./rootCA.pem -CAkey ./rootCA.key -CAcreateserial -out ./wildcard.${_domain}.crt -extfile ${_openssl_conf}
    # make sure server certificate and key is readable by particular user
    #chown $USER: ./wildcard.${_domain}.{key,crt}
    ls -ltr *.${_domain}.{key,crt,csr}
}

### main ########################
if [ "$0" = "$BASH_SOURCE" ]; then
    echo "source $BASH_SOURCE"
fi