#!/usr/bin/env bash
# curl -o /var/tmp/share/test_https.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/test_https.sh
#
# Useful Java flags (NOTE: based on java 8)
#   -Dcom.sun.net.ssl.checkRevocation=false                         # to avoid hostname error (not same as curl -k)
#
#   -Dcom.sun.jndi.ldap.object.disableEndpointIdentification=true   # for LDAPS
#   -Djavax.net.ssl.trustStoreType=WINDOWS-ROOT                     # to use Windows OS truststore
#   ‑Djdk.tls.client.protocols="TLSv1,TLSv1.1,TLSv1.2"              # to specify client protocol
#
#   -Dhttps.proxyHost=<proxy_hostname> -Dhttps.proxyPort=
#   -Djava.net.useSystemProxies=true
#
# To DEBUG:
#   -Djavax.net.debug=ssl,keymanager
#   -Djavax.net.debug=ssl:handshake:verbose
#

# port number used by a test web server
_TEST_PORT=34443

# List supported ciphers of a web server
# NOTE: If unexpected result, may want to check "jdk.tls.disabledAlgorithms" in $JAVA_HOME/jre/lib/security/java.security
function get_ciphers() {
    # @see http://superuser.com/questions/109213/how-do-i-list-the-ssl-tls-cipher-suites-a-particular-website-offers
    local _host="${1:-`hostname -f`}"
    local _port="${2:-443}"
    local _use_nmap="${3}"
    local _host_port=$_host:$_port
    local _delay=1

    if [[ "${_use_nmap}" =~ ^(y|Y) ]] && which nmap &>/dev/null; then
        # TODO: this doesn't work with TLSv1.3
        nmap --script +ssl-enum-ciphers -p ${_port} ${_host}
        return $?
    fi

    ciphers=$(openssl ciphers 'ALL:eNULL' | sed -e 's/:/ /g')
    echo "Obtaining cipher list from ${_host_port} with $(openssl version)..." >&2

    for cipher in ${ciphers[@]}; do
        sleep ${_delay}
        result=$(echo -n | openssl s_client -cipher "$cipher" -connect ${_host_port} 2>&1)
        if [[ "$result" =~ ":error:" ]] ; then
            error=$(echo -n $result | cut -d':' -f6)
            echo -e "$cipher\tNO ($error)" >&2
        elif [[ "$result" =~ Cipher[[:space:]]is[[:space:]]${cipher} || "$result" =~ Cipher[[:space:]]+: ]] ; then
            echo -e "$cipher\tYES"
        else
            echo -e "$cipher\tUNKNOWN RESPONSE" >&2
            echo $result >&2
        fi
    done
}

# Get (actually testing) enabled and not supported TLS protocols
# NOTE: If unexpected result, may want to check "jdk.tls.disabledAlgorithms" in $JAVA_HOME/jre/lib/security/java.security
function get_tls_versions() {
    local _host="${1:-`hostname -f`}"
    local _port="${2:-443}"
    local _head="${3:-10}"
    local _delay=1
    local _host_port=$_host:$_port

    #curl -h | sed -ne '/--tlsv/p'
    # -1, --tlsv1         Use >= TLSv1 (SSL)
    #     --tlsv1.0       Use TLSv1.0 (SSL)
    #     --tlsv1.1       Use TLSv1.1 (SSL)
    #     --tlsv1.2       Use TLSv1.2 (SSL)
    #     --tlsv1.3       Use TLSv1.3 (SSL)
    #curl -h | sed -ne '/--sslv/p'
    # -2, --sslv2         Use SSLv2 (SSL)
    # -3, --sslv3         Use SSLv3 (SSL)

    for _v in {0..3}; do  # 'ssl2' no longer works with openssl
        sleep ${_delay}
        #local _output="`echo -n | openssl s_client -connect ${_host_port} -${_v} 2>/dev/null`"
        local _output="$(curl -k -v -o/dev/null -f "https://${_host_port}/" --tlsv1.${_v} 2>&1)"
        if ! curl -k -v -o/dev/null -f "https://${_host_port}/" --tlsv1.${_v} &> /tmp/get_tls_versions_tlsv1.${_v}.out; then
            echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] WARN: 'TLS v1.${_v}' failed." >&2
        else
            echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] INFO: 'TLS v1.${_v}' worked"
            grep '* SSL connection using' /tmp/get_tls_versions_tlsv1.${_v}.out
        fi
    done

    if [ -x "${JAVA_HOME%/}/bin/jrunscript" ]; then
        #"${JAVA_HOME%/}/bin/jrunscript" -e 'var e=javax.net.ssl.SSLContext.getDefault().createSSLEngine(); e.setEnabledProtocols(["TLSv1","TLSv1.1","TLSv1.2"]); sp=e.getEnabledProtocols(); for (var i in sp) println(sp[i])'
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] INFO: Java client side Supported protocols"
        "${JAVA_HOME%/}/bin/jrunscript" -e 'var ps = javax.net.ssl.SSLContext.getDefault().createSSLEngine().getSupportedProtocols(); for (var i in ps) println(ps[i])'
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] INFO: Java client side Enabled protocols"
        "${JAVA_HOME%/}/bin/jrunscript" -e 'var ps = javax.net.ssl.SSLContext.getDefault().createSSLEngine().getEnabledProtocols(); for (var i in ps) println(ps[i])'
        # TODO: "${JAVA_HOME%/}/bin/jrunscript" -e 'var ni = java.net.NetworkInterface.getNetworkInterfaces();for (var i in ni) println(ni[i].getInetAddresses().toString())'
    fi
}

# extract/export rsa private key and certificateS from pem file
function extract_key_certs_from_pem() {
    # https://serverfault.com/questions/391396/how-to-split-a-pem-file
    local _file="$1"
    local _base_name="$(basename ${_file} .pem)"
    if [ -s "${_base_name}.pkey.pem" ]; then
        echo "${_base_name}.pkey.pem exists."
    else
        openssl pkey -in ${_file} -out ${_base_name}.pkey.pem && chmod 400 ${_base_name}.pkey.pem
    fi
    if [ -s "${_base_name}.certs.pem" ]; then
        echo "${_base_name}.certs.pem exists."
    else
        openssl crl2pkcs7 -nocrl -certfile ${_file} | openssl pkcs7 -print_certs -out ${_base_name}.certs.pem
    fi
}

# convert .jks or .pkcs8 file to .key (and .crt if possible)
function export_key() {
    local _file="$1"
    local _pass="${2:-"password"}"
    local _alias="${3:-"$(hostname -f)"}"
    local _type="$4"

    local _basename="$(basename "${_file%.*}")"
    local _out_key="${_basename}.${_alias}.key"
    local _out_crt="${_basename}.${_alias}.pem"
    [ -z "$_type" ] && _type="${_file##*.}"

    if [ "$_type" = "pkcs8" ]; then
        openssl pkcs8 -outform PEM -in key.pkcs8 -out ${_out_key} -nocrypt
    elif [ "$_type" = "jks" ] || [ "$_type" = "p12" ]; then
        if [ ! -x "${JAVA_HOME%/}/bin/keytool" ]; then
            echo "This function requires 'keytool' command in \$JAVA_HOME/bin." >&2
            return 1
        fi
        if [ "$_type" != "p12" ]; then  # if not p12, convert to p12
            ${JAVA_HOME%/}/bin/keytool -importkeystore -noprompt -srckeystore ${_file} -srcstorepass "${_pass}" -srcalias ${_alias} \
             -destkeystore ${_basename}.p12 -deststoretype PKCS12 -deststorepass "${_pass}" -destkeypass "${_pass}" || return $?
        fi
        # Generating tge key, and convert to RSA format
        openssl pkcs12 -in ${_basename}.p12 -passin "pass:${_pass}" -nodes -nocerts -out ${_out_key}.tmp && openssl rsa -in ${_out_key}.tmp -out ${_out_key}
        # Generating certs. 'sed' to remove "Bag Attributes" and "Key Attributes" lines
        openssl pkcs12 -in ${_basename}.p12 -passin "pass:${_pass}" -nokeys -chain | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > ${_out_crt}
        rm -f ${_basename}*.tmp
    fi
    chmod 600 ${_out_key}
    ls -l ${_basename}.*
    # NOTE: for the connection test, you do not need to split:
    #curl -L "<URL>" --cert-type P12 --cert "./<file>.p12:<password>"
}

# Another example to export certificate from jks/p12 as PEM format
function export_cert() {
    local _file="$1"
    local _pass="${2:-"password"}"
    local _out_crt="${_basename}.${_alias}.pem"

    ${JAVA_HOME%/}/bin/keytool -export -noprompt -keystore ${_file} -storepass "${_pass}" | openssl x509 -inform der -text | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > ${_out_crt} || return $?
}

# generate .p12 (pkcs12|pfx) and .jks files from server cert/key (and CA cert)
function gen_p12_jks() {
    local _srv_key="$1"
    local _srv_crt="$2"
    local _full_ca_crt="$3"
    local _pass="${4-"password"}" # in file password can be empty
    local _store_pass="${5:-"password"}"
    local _name="$6"
    if [ -z "${_name}" ]; then
        local _basename="$(basename ${_srv_crt})"
        _name="${_basename%.*}"
    fi

    local _pass_arg=""
    [ -n "${_pass}" ] && _pass_arg="-passin \"pass:${_pass}\""
    local _chain=""
    [ -n "${_full_ca_crt}" ] && _chain="-chain -CAfile ${_full_ca_crt}"
    # NOTE: If intermediate CA is used, cat root.cer intermediate.cer > full_ca.cer (TODO: does order matter?)
    # TODO: at this moment, the password sets on .key file will be lost.
    local _cmd="openssl pkcs12 -export ${_chain} -in ${_srv_crt} -inkey ${_srv_key} -name ${_name} -out ${_name}.p12 ${_pass_arg} -passout \"pass:${_store_pass}\""
    eval "${_cmd}" || return $?
    if ! which keytool &>/dev/null; then
        echo "To generate JKS, require keytool"
        return 1
    fi

    # Test / verify P12:
    keytool -list -keystore ${_name}.p12 -storetype PKCS12 -storepass "${_store_pass}" || return $?
    # Also, if .jks is needed, converting p12 to jks with importkeystore:
    keytool -importkeystore -srckeystore ${_name}.p12 -srcstoretype PKCS12 -srcstorepass "${_store_pass}" -destkeystore ${_name}.jks -deststoretype JKS -deststorepass "${_store_pass}"
    # NOTE: to convert from .jks to .p12
    #keytool -importkeystore -srckeystore ${_name}.jks -deststoretype JKS -srcstorepass "${_store_pass}" -destkeystore ${_name}.p12 -deststoretype PKCS12 -srcstorepass "${_store_pass}"
    # Test / verify JKS:
    keytool -list -keystore ${_name}.jks -storetype JKS -storepass "${_store_pass}" -keypass "${_pass:-${_store_pass}}" # -alias <value_of_certAlias>
}

# NOTE: this will ask a store password
function rename_alias() {
    local _keystore="$1"
    local _crt_alias="$2"
    local _new_alias="$3"
    keytool -changealias -keystore "${_keystore}" -alias "${_crt_alias}" -destalias "${_new_alias}"
}

function change_storepassword() {
    local _keystore="$1"
    local _crt_pwd="$2"
    local _new_pwd="$3"
    # TODO: does this work with keypass?
    keytool -storepasswd -keystore "${_keystore}" -storepass "${_crt_pwd}" -new "${_new_pwd}"
}

function change_rsa_key_password() {
    local _rsa_pem_file="$1"
    local _new_file="$2"
    local _crt_pwd="$3"
    local _new_pwd="$4"
    local _pass_arg=""
    [ -n "${_crt_pwd}" ] && _pass_arg="-passin 'pass:${_crt_pwd}'"
    openssl rsa -aes256 -in "${_rsa_pem_file}" -out "${_new_file}" ${_pass_arg} -passout "pass:${_new_pwd}"
    # test
    ls -l ${_new_file}
    openssl rsa -in "${_new_file}" -passin "pass:${_new_pwd}"
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
    local _cert_with_pwd="$3"
    local _cert_type="${4:-"p12"}"

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
        if ! curl -vIf --cacert "${_ca_cert}" -L "https://${_host_port}"; then
            echo "WARN: Can't connect to https://${_host_port} with cacert:${_ca_cert}" >&2
        else
            echo "INFO: Can connect to https://${_host_port} with cacert:${_ca_cert}" >&2
        fi
    fi
    # 2-way SSL (client certificate authentication) with --cert with p12 file
    if [ -n "${_cert_with_pwd}" ];then
        curl -vIf --cert "${_cert_with_pwd}" --cert-type ${_cert_type} "https://${_host_port}"
    fi
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
        #openssl x509 -noout -fingerprint -sha1 -inform pem -in "$_file"
        openssl x509 -noout -fingerprint -sha256 -inform pem -in "$_file"
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

# TODO: read keytool list -v to check/verify certificate chain, subject, common name, valid from / to
function check_keytool_v_output() {
    local _keytool="$(which keytool 2>/dev/null)"
    [ -x "${JAVA_HOME%/}/bin/keytool" ] && _keytool="${JAVA_HOME%/}/bin/keytool"
    echo "TODO
    ${_keytool} -list -v -keystore <value_of_KeyStorePath> -storetype JKS -storepass <value_of_KeyStorePassword> -keypass <value_of_KeyManagerPassword> -alias <value_of_certAlias>
    "
}

function get_certificate_from_https() {
    local _host="$1"
    local _port="${2:-443}"
    local _dest_filepath="$3"
    local _proxy="$4"
    local _truststore="$5"
    [ -z "${_dest_filepath}" ] && _dest_filepath=./${_host}_${_port}.pem
    local _keytool="$(which keytool 2>/dev/null)"
    [ -x "${JAVA_HOME%/}/bin/keytool" ] && _keytool="${JAVA_HOME%/}/bin/keytool"

    if [ -n "${_proxy}" ]; then
        if [ -n "${_keytool}" ]; then
            local _proxy_host="${_proxy}"
            local _proxy_port="443"
            if [[ "${_proxy}" =~ ^([^:]+):([0-9]+)$ ]]; then
                _proxy_host="${BASH_REMATCH[1]}"
                _proxy_port="${BASH_REMATCH[2]}"
            fi
            # To DEBUG, -J-Djavax.net.debug=ssl,keymanager or -Djavax.net.debug=ssl:handshake:verbose, and without system proxy: -J-Djava.net.useSystemProxies=true
            # To pass proxyuser and proxypwd, -J-Dhttps.proxyHost=proxyuser:proxypwd@${_proxy_host}
            keytool -J-Dhttps.proxyHost=${_proxy_host} -J-Dhttps.proxyPort=${_proxy_port} -printcert -sslserver ${_host}:${_port} # -rfc
        else
            # very old openssl version may fail with -proxy (Mac and modern Linux works) TODO: username and password
            echo -n | openssl s_client -showcerts -proxy ${_proxy} -connect ${_host}:${_port}
        fi || echo "curl -sfv -p -x ${_proxy} --proxy-basic -U proxyuser:proxypwd -k -L https://${_host}:${_port}/ 2>&1 | grep 'Server certificate:' -A10"
        # Curl example in case above openssl or keytool doesn't work.
    else
        # Trying keytool first as some https server doesn't return cert with openssl (CONNECT_CR_SRVR_HELLO:wrong version number)
        if [ -n "${_keytool}" ]; then
            # NOTE: It seems exporting cert with keytool may not work in Windows PowerShell
            keytool -printcert -rfc -sslserver ${_host}:${_port}  # -rfc to get PEM format
        else
            # NOTE: openssl is better than keytool as it shows cert and more information
            echo -n | openssl s_client -showcerts -connect ${_host}:${_port}
        fi
    fi > /tmp/${_host}_${_port}.tmp || return $?
    #gcsplit -f cert -s /tmp/${_host}_${_port}.tmp '/BEGIN CERTIFICATE/' '{*}'
    sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' /tmp/${_host}_${_port}.tmp > ${_dest_filepath} || return $?
    if [ -n "${_truststore}" ]; then
        echo "${_keytool} -import -alias \"${_host}_${_port}\" -keystore \"${_truststore}\" -file \"${_dest_filepath}\""
        ${_keytool} -import -alias "${_host}_${_port}" -keystore "${_truststore}" -file "${_dest_filepath}"
    fi
}

# for SAML X509Certificate
function gen_cert_from_str() {
    local _str="$1"
    local _filename="$2"
    local _tmp_file=$(mktemp)
    echo "-----BEGIN CERTIFICATE-----" > ${_tmp_file}
    fold -w 64 -s <(echo "${_str}" | tr -d "\n") >> ${_tmp_file}
    echo -e "\n-----END CERTIFICATE-----" >> ${_tmp_file}
    if [ -z "${_filename}" ]; then
        cat ${_tmp_file}
    else
        cat ${_tmp_file} > ${_filename}
    fi
}

# example of how to generate a wildcard certificate
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

function gen_wildcard_cert_with_keytool() {
    local _name="$1"
    local _domain="${2:-`hostname -d`}"
    local _pass="${3:-"password"}"
    local _keystore_file="${4:-"keystore.jks"}"
    # TODO: do I need to specify SAN=DNS:<FQDN>?
    keytool -genkeypair -keystore "${_keystore_file}" -storepass "${_pass}" -alias "${_name}" -keyalg RSA -keysize 2048 -validity 3650 -keypass "${_pass}" -dname "CN=*.${_domain#.}, O=HajimeTest, ST=QLD, C=AU" -ext "BC=ca:true" -ext "SAN=DNS:${_name}.${_domain#.}" || return $?
    keytool -exportcert -keystore "${_keystore_file}" -alias "${_name}" -storepass "${_pass}" -file "${_name}.crt"
    ls -l "${_keystore_file}" "${_name}.crt"
}

# To support Mac...
function _sed() {
    local _cmd="sed"; which gsed &>/dev/null && _cmd="gsed"
    ${_cmd} "$@"
}

### main ########################
if [ "$0" = "$BASH_SOURCE" ]; then
    echo "source $BASH_SOURCE"
fi