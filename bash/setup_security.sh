#!/usr/bin/env bash
#
# DOWNLOAD:
#   curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_security.sh
#
#
# This script contains functions which help to set up Ambari/HDP security (SSL,LDAP,Kerberos etc.)
# This script requires below:
#   curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/start_hdp.sh
#
# *NOTE*: because it uses start_hdp.sh, can't use same function name in this script
#
# Example 1: How to set up Kerberos
#   source ./setup_security.sh && f_loadResp
#   f_kdc_install_on_host
#   f_ambari_kerberos_setup
#
# If Sandbox (after KDC setup):
# NOTE: sandbox.hortonworks.com needs to be resolved to a proper IP, also password less scp/ssh required
#   f_ambari_kerberos_setup "$g_KDC_REALM" "172.17.0.1" "" "sandbox.hortonworks.com" "sandbox.hortonworks.com"
#
# Example 2: How to set up HTTP Authentication (SPNEGO) on hadoop component
#   source ./setup_security.sh && f_loadResp
#   f_hadoop_spnego_setup
#
# If Sandbox (after KDC/kerberos setup):
# NOTE sandbox.hortonworks.com needs to be resolved to a proper IP, also password less scp/ssh required
#   f_hadoop_spnego_setup "$g_KDC_REALM" "hortonworks.com" "sandbox.hortonworks.com" "8080" "sandbox.hortonworks.com"
#
# Example 3: How to set up SSL on hadoop component (requires JRE/JDK for keytool command)
#   source ./setup_security.sh && f_loadResp
#   mkdir ssl_setup; cd ssl_setup
#   f_hadoop_ssl_setup
#
# If Sandbox:
# NOTE sandbox.hortonworks.com needs to be resolved to a proper IP, also password less scp/ssh required
#   mkdir ssl_setup; cd ssl_setup
#   f_hadoop_ssl_setup "" "" "sandbox.hortonworks.com" "8080" "sandbox.hortonworks.com"
#

### OS/shell settings
shopt -s nocasematch
#shopt -s nocaseglob
set -o posix
#umask 0000

# Global variables
g_SERVER_KEY_LOCATION="/etc/security/serverKeys/"
g_CLIENT_KEY_LOCATION="/etc/security/clientKeys/"
g_CLIENT_TRUST_LOCATION="/etc/security/clientKeys/"
g_KEYSTORE_FILE="server.keystore.jks"
g_TRUSTSTORE_FILE="server.truststore.jks"
g_CLIENT_KEYSTORE_FILE="client.keystore.jks"
g_CLIENT_TRUSTSTORE_FILE="all.jks"
g_CLIENT_TRUSTSTORE_PASSWORD="changeit"
g_KDC_REALM="`hostname -s`" && g_KDC_REALM=${g_KDC_REALM^^}
g_admin="${_ADMIN_USER-admin}"
g_admin_pwd="${_ADMIN_PASS-admin}"

function f_kdc_install_on_ambari_node() {
    local __doc__="(Deprecated) Install KDC/kadmin service to $r_AMBARI_HOST. May need UDP port forwarder https://raw.githubusercontent.com/hajimeo/samples/master/python/udp_port_forwarder.py"
    local _realm="${1-$g_KDC_REALM}"
    local _password="${2-$g_DEFAULT_PASSWORD}"
    local _server="${3-$r_AMBARI_HOST}"

    if [ -z "$_server" ]; then
        _error "KDC installing hostname is missing"
        return 1
    fi

    ssh root@$_server -t "yum install krb5-server krb5-libs krb5-workstation -y"
    # this doesn't work with docker though
    ssh root@$_server -t "chkconfig  krb5kdc on; chkconfig kadmin on"
    ssh root@$_server -t "mv /etc/krb5.conf /etc/krb5.conf.orig; echo \"[libdefaults]
 default_realm = $_realm
[realms]
 $_realm = {
   kdc = $_server
   admin_server = $_server
 }\" > /etc/krb5.conf"
    ssh root@$_server -t "kdb5_util create -s -P $_password"
    # chkconfig krb5kdc on;chkconfig kadmin on; doesn't work with docker
    ssh root@$_server -t "echo '*/admin *' > /var/kerberos/krb5kdc/kadm5.acl;service krb5kdc restart;service kadmin restart;kadmin.local -q \"add_principal -pw $_password admin/admin\""
    #ssh -2CNnqTxfg -L88:$_server:88 $_server # TODO: UDP does not work. and need 749 and 464
}

function f_kdc_install_on_host() {
    local __doc__="Install KDC server packages on Ubuntu (takes long time)"
    local _realm="${1-$g_KDC_REALM}"
    local _password="${2-$g_DEFAULT_PASSWORD}"
    local _server="${3-`hostname -i`}"

    if [ ! `which apt-get` ]; then
        _warn "No apt-get"
        return 1
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y krb5-kdc krb5-admin-server || return $?

    if [ -s /etc/krb5kdc/kdc.conf ] && [ -s /var/lib/krb5kdc/principal_${_realm} ]; then
        if grep -qE '^\s*'${_realm}'\b' /etc/krb5kdc/kdc.conf; then
            _info "Realm: ${_realm} may already exit in /etc/krb5kdc/kdc.conf. Not try creating..."
            return 0
        fi
    fi
    echo '    '${_realm}' = {
        database_name = /var/lib/krb5kdc/principal_'${_realm}'
        admin_keytab = FILE:/etc/krb5kdc/kadm5_'${_realm}'.keytab
        acl_file = /etc/krb5kdc/kadm5_'${_realm}'.acl
        key_stash_file = /etc/krb5kdc/stash_'${_realm}'
        kdc_ports = 750,88
        max_life = 10h 0m 0s
        max_renewable_life = 7d 0h 0m 0s
        master_key_type = des3-hmac-sha1
        supported_enctypes = aes256-cts:normal arcfour-hmac:normal des3-hmac-sha1:normal des-cbc-crc:normal des:normal des:v4 des:norealm des:onlyrealm des:afs3
        default_principal_flags = +preauth
    }
'  > /tmp/f_kdc_install_on_host_kdc_$$.tmp
    sed -i "/\[realms\]/r /tmp/f_kdc_install_on_host_kdc_$$.tmp" /etc/krb5kdc/kdc.conf

    # KDC process seems to use default_realm, and sed needs to escape + somehow
    sed -i_$(date +"%Y%m%d").bak -e 's/^\s*default_realm.\+$/  default_realm = '${_realm}'/' /etc/krb5.conf
    # With 'sed', append/insert multiple lines
    if ! grep -qE '^\s*'${_realm}'\b' /etc/krb5.conf; then
        echo '  '${_realm}' = {
   kdc = '${_server}'
   admin_server = '${_server}'
 }
' > /tmp/f_kdc_install_on_host_krb5_$$.tmp
        sed -i "/\[realms\]/r /tmp/f_kdc_install_on_host_krb5_$$.tmp" /etc/krb5.conf
    fi

    kdb5_util create -r ${_realm} -s -P ${_password} || return $?  # or krb5_newrealm
    mv /etc/krb5kdc/kadm5_${_realm}.acl /etc/krb5kdc/kadm5_${_realm}.orig &>/dev/null
    echo '*/admin *' > /etc/krb5kdc/kadm5_${_realm}.acl
    service krb5-kdc restart && service krb5-admin-server restart
    sleep 3
    kadmin.local -r ${_realm} -q "add_principal -pw ${_password} admin/admin@${_realm}"
}

function _ambari_kerberos_generate_service_config() {
    local __doc__="Output (return) service config for Ambari APIs. TODO: MIT KDC only by created by f_kdc_install_on_host"
    # https://cwiki.apache.org/confluence/display/AMBARI/Automated+Kerberizaton#AutomatedKerberizaton-EnablingKerberos
    local _realm="${1-$g_KDC_REALM}"
    local _server="${2-`hostname -f`}"
    #local _kdc_type="${3}" # TODO: Not using and MIT KDC only
    local _version="version`date +%s`000" #TODO: not sure if always using version 1 is OK

    # TODO: 'kdc = {{kdc_host}}' may have some issue. "domains.split(\',\')" (single quotes) is not working
    cat << KERBEROS_CONFIG
[
  {
    "Clusters": {
      "desired_config": [
        {
          "type": "kerberos-env",
          "tag": "${_version}",
          "properties": {
            "ad_create_attributes_template": "\n{\n  \"objectClass\": [\"top\", \"person\", \"organizationalPerson\", \"user\"],\n  \"cn\": \"\$principal_name\",\n  #if( \$is_service )\n  \"servicePrincipalName\": \"\$principal_name\",\n  #end\n  \"userPrincipalName\": \"\$normalized_principal\",\n  \"unicodePwd\": \"\$password\",\n  \"accountExpires\": \"0\",\n  \"userAccountControl\": \"66048\"\n}",
            "admin_server_host": "${_server}",
            "case_insensitive_username_rules": "false",
            "container_dn": "",
            "create_ambari_principal": "true",
            "encryption_types": "aes des3-cbc-sha1 rc4 des-cbc-md5",
            "executable_search_paths": "/usr/bin, /usr/kerberos/bin, /usr/sbin, /usr/lib/mit/bin, /usr/lib/mit/sbin",
            "group": "ambari-managed-principals",
            "install_packages": "true",
            "kdc_create_attributes": "",
            "kdc_hosts": "${_server}",
            "kdc_type": "mit-kdc",
            "ldap_url": "",
            "manage_auth_to_local": "true",
            "manage_identities": "true",
            "password_chat_timeout": "5",
            "password_length": "20",
            "password_min_digits": "1",
            "password_min_lowercase_letters": "1",
            "password_min_punctuation": "1",
            "password_min_uppercase_letters": "1",
            "password_min_whitespace": "0",
            "realm": "${_realm}",
            "service_check_principal_name": "\${cluster_name|toLower()}-\${short_date}",
            "set_password_expiry": "false"
          },
          "service_config_version_note": "This is the kerberos configuration created by _ambari_kerberos_generate_service_config."
        },
        {
          "type": "krb5-conf",
          "tag": "${_version}",
          "properties": {
            "conf_dir": "/etc",
            "content": "\n[libdefaults]\n  renew_lifetime = 7d\n  forwardable = true\n  default_realm = {{realm}}\n  ticket_lifetime = 24h\n  dns_lookup_realm = false\n  dns_lookup_kdc = false\n  default_ccache_name = /tmp/krb5cc_%{uid}\n  #default_tgs_enctypes = {{encryption_types}}\n  #default_tkt_enctypes = {{encryption_types}}\n{% if domains %}\n[domain_realm]\n{%- for domain in domains.split(\",\") %}\n  {{domain|trim()}} = {{realm}}\n{%- endfor %}\n{% endif %}\n[logging]\n  default = FILE:/var/log/krb5kdc.log\n  admin_server = FILE:/var/log/kadmind.log\n  kdc = FILE:/var/log/krb5kdc.log\n\n[realms]\n  {{realm}} = {\n{%- if kdc_hosts > 0 -%}\n{%- set kdc_host_list = kdc_hosts.split(\",\")  -%}\n{%- if kdc_host_list and kdc_host_list|length > 0 %}\n    admin_server = {{admin_server_host|default(kdc_host_list[0]|trim(), True)}}\n{%- if kdc_host_list -%}\n{% for kdc_host in kdc_host_list %}\n    kdc = {{kdc_host|trim()}}\n{%- endfor -%}\n{% endif %}\n{%- endif %}\n{%- endif %}\n  }\n\n{# Append additional realm declarations below #}",
            "domains": "",
            "manage_krb5_conf": "true"
          },
          "service_config_version_note": "This is the kerberos configuration created by _ambari_kerberos_generate_service_config."
        }
      ]
    }
  }
]
KERBEROS_CONFIG
}

function f_ambari_kerberos_setup() {
    local __doc__="Setup Kerberos with Ambari APIs. TODO: MIT KDC only and it needs to be created by f_kdc_install_on_host"
    # https://cwiki.apache.org/confluence/display/AMBARI/Automated+Kerberizaton#AutomatedKerberizaton-EnablingKerberos
    local _realm="${1-$g_KDC_REALM}"
    local _kdc_server="${2-$r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}"
    local _password="${3}"
    local _ambari_host="${4-$r_AMBARI_HOST}"
    local _how_many="${5-$r_NUM_NODES}"
    local _start_from="${6-$r_NODE_START_NUM}"
    local _domain_suffix="${7-$r_DOMAIN_SUFFIX}"

    if [ -z "$_password" ]; then
        _password=${g_DEFAULT_PASSWORD-hadoop}
    fi

    if ! which python &>/dev/null; then
        _error "Please install python (eg: apt-get install -y python)"
        return 1
    fi

    local _cluster_name="`f_get_cluster_name $_ambari_host`" || return 1
    local _api_uri="http://$_ambari_host:8080/api/v1/clusters/$_cluster_name"
    local _stack_name="HDP"
    local _stack_version="`_ambari_query_sql "select s.stack_version from clusters c join stack s on c.desired_stack_id = s.stack_id where c.cluster_name='$_cluster_name';" "$_ambari_host"`"
    local _request_context="Stop Service with f_ambari_kerberos_setup"
    local _version="version`date +%s`000"

    #local _kdc_type="${3}" # TODO: Not using and MIT KDC only
    # Test GET method
    #response=$(curl --write-out %{http_code} -s -o /dev/null "${_api_uri}/configurations/service_config_versions?service_name=KERBEROS")

    _info "Storing KDC admin credential temporarily"
    curl -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X PUT "${_api_uri}/credentials/kdc.admin.credential" -d '{ "Credential" : { "principal" : "admin/admin@'$_realm'", "key" : "'$_password'", "type" : "temporary" } }' &>/dev/null

    _info "Delete existing KERBEROS service (if exists)"
    curl -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X PUT "${_api_uri}" -d '{"Clusters":{"security_type":"NONE"}}' &>/dev/null
    curl -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X DELETE "${_api_uri}/services/KERBEROS" &>/dev/null
    sleep 3

    _info "register Kerberos service and component"
    curl -si -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X POST "${_api_uri}/services" -d '{"ServiceInfo": { "service_name": "KERBEROS"}}' | grep -E '^HTTP/1.1 2' || return 11
    sleep 3
    curl -si -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X POST "${_api_uri}/services?ServiceInfo/service_name=KERBEROS" -d '{"components":[{"ServiceComponentInfo":{"component_name":"KERBEROS_CLIENT"}}]}' | grep -E '^HTTP/1.1 2' || return 12
    sleep 3

    if ! [[ "$_how_many" =~ ^[0-9]+$ ]]; then
        local _hostnames="$_how_many"
        _info "Adding Kerberos client to $_hostnames"
        for _h in `echo $_hostnames | sed 's/ /\n/g'`; do
            curl -si -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X POST -d '{"host_components" : [{"HostRoles" : {"component_name":"KERBEROS_CLIENT"}}]}' "${_api_uri}/hosts?Hosts/host_name=${_h}" | grep -E '^HTTP/1.1 2' || return 21
            sleep 1
        done
    else
        _info "Adding Kerberos client on all nodes"
        for i in `_docker_seq "$_how_many" "$_start_from"`; do
            curl -si -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X POST -d '{"host_components" : [{"HostRoles" : {"component_name":"KERBEROS_CLIENT"}}]}' "${_api_uri}/hosts?Hosts/host_name=node$i${_domain_suffix}" | grep -E '^HTTP/1.1 2' || return 22
            sleep 1
        done
    fi
     #-d '{"RequestInfo":{"query":"Hosts/host_name=node1.localdomain|Hosts/host_name=node2.localdomain|..."},"Body":{"host_components":[{"HostRoles":{"component_name":"KERBEROS_CLIENT"}}]}}'

    _info "Add/Upload the KDC configuration"
    _ambari_kerberos_generate_service_config "$_realm" "$_kdc_server" > /tmp/${_cluster_name}_kerberos_service_conf.json
    curl -si -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X PUT "${_api_uri}" -d @/tmp/${_cluster_name}_kerberos_service_conf.json | grep -E '^HTTP/1.1 2' || return 31
    sleep 3

    _info "Starting (installing) Kerberos"
    curl -si -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X PUT "${_api_uri}/services?ServiceInfo/state=INSTALLED&ServiceInfo/service_name=KERBEROS" -d '{"RequestInfo":{"context":"Install Kerberos Service with f_ambari_kerberos_setup","operation_level":{"level":"CLUSTER","cluster_name":"'$_cluster_name'"}},"Body":{"ServiceInfo":{"state":"INSTALLED"}}}' | grep -E '^HTTP/1.1 2' || return 32
    sleep 5

    #_info "Get the default kerberos descriptor and upload (assuming no current)"
    curl -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X GET "http://$_ambari_host:8080/api/v1/stacks/$_stack_name/versions/${_stack_version}/artifacts/kerberos_descriptor" -o /tmp/${_cluster_name}_kerberos_descriptor.json
    #curl -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X GET "${_api_uri}/artifacts/kerberos_descriptor" -o /tmp/${_cluster_name}_kerberos_descriptor.json

    # For ERROR "The properties [Artifacts/stack_version, href, Artifacts/stack_name] specified in the request or predicate are not supported for the resource type Artifact."
    python -c "import sys,json
with open('/tmp/${_cluster_name}_kerberos_descriptor.json') as jd:
    a=json.load(jd)
a.pop('href', None)
a.pop('Artifacts', None)
with open('/tmp/${_cluster_name}_kerberos_descriptor.json', 'w') as jd:
    json.dump(a, jd)"

    # This fails if it's already posted and ignorable
    curl -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X POST "${_api_uri}/artifacts/kerberos_descriptor" -d @/tmp/${_cluster_name}_kerberos_descriptor.json
    sleep 3

    _info "Stopping all services...."
    #curl -si -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X PUT "${_api_uri}" -d '{"Clusters":{"security_type":"NONE"}}'
    curl -si -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X PUT -d "{\"RequestInfo\":{\"context\":\"$_request_context\"},\"Body\":{\"ServiceInfo\":{\"state\":\"INSTALLED\"}}}" "${_api_uri}/services" | grep -E '^HTTP/1.1 2' || return 33
    sleep 3
    # confirming if it's stopped
    for _i in {1..9}; do
        _n="`_ambari_query_sql "select count(*) from request where request_context = '$_request_context' and end_time < start_time" "$_ambari_host"`"
        [ 0 -eq $_n ] && break;
        sleep 15
    done

    # occasionally gets "Cannot run program "kadmin": error=2, No such file or directory"
    ssh -q root@$_ambari_host -t which kadmin &>/dev/null || sleep 10

    _info "Set up Kerberos for $_realm..."
    curl -si -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X PUT "${_api_uri}" -d '{"session_attributes" : {"kerberos_admin" : {"principal" : "admin/admin@'$_realm'", "password" : "'$_password'"}}, "Clusters": {"security_type" : "KERBEROS"}}' | grep -E '^HTTP/1.1 2' || return 34
    sleep 3

    # wait until it's set up
    for _i in {1..9}; do
        _n="`_ambari_query_sql "select count(*) from request where request_context = 'Preparing Operations' and end_time < start_time" "$_ambari_host"`"
        [ 0 -eq $_n ] && break;
        sleep 15
    done

    _info "Completed! Starting all services"
    curl -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X PUT -d "{\"RequestInfo\":{\"context\":\"Start Service with f_ambari_kerberos_setup\"},\"Body\":{\"ServiceInfo\":{\"state\":\"STARTED\"}}}" ${_api_uri}/services
}

function f_hadoop_ssl_setup() {
    local __doc__="Setup SSL for hadoop https://community.hortonworks.com/articles/92305/how-to-transfer-file-using-secure-webhdfs-in-distc.html"
    local _dname_extra="$1"
    local _password="$2"
    local _ambari_host="${3-$r_AMBARI_HOST}"
    local _ambari_port="${4-8080}"
    local _how_many="${5-$r_NUM_NODES}"
    local _start_from="${6-$r_NODE_START_NUM}"
    local _domain_suffix="${7-$r_DOMAIN_SUFFIX}"
    local _use_wildcard_cert="${8-N}" # TODO: getting "hostname mismatch"
    local _no_updating_ambari_config="${9-$r_NO_UPDATING_AMBARI_CONFIG}"
    local _work_dir="${8-./}"

    cd ${_work_dir%/} || return $?

    if [ -z "$_password" ]; then
        _password=${g_DEFAULT_PASSWORD-hadoop}
    fi
    if [ -z "$_dname_extra" ]; then
        _dname_extra="OU=Support, O=Hortonworks, L=Brisbane, ST=QLD, C=AU"
    fi

    if [ -s ./rootCA.key ]; then
        _info "rootCA.key exists. Reusing..."
    else
        # Step1: create my root CA (key) TODO: -aes256
        openssl genrsa -out rootCA.key 4096 || return $?
        # Step2: create root CA's cert (pem)
        openssl req -x509 -new -key ./rootCA.key -days 1095 -out ./rootCA.pem -subj "/C=AU/ST=QLD/O=Hortonworks/CN=RootCA.`hostname -s`.hortonworks.com" -passin "pass:$_password" || return $?
        chmod 600 ./rootCA.key
    fi

    mv -f ./$g_CLIENT_TRUSTSTORE_FILE ./$g_CLIENT_TRUSTSTORE_FILE.$$.bak &>/dev/null
    # Step3: Create a truststore file used by all clients/nodes
    keytool -keystore ./$g_CLIENT_TRUSTSTORE_FILE -alias CARoot -import -file ./rootCA.pem -storepass ${g_CLIENT_TRUSTSTORE_PASSWORD} -noprompt || return $?

    # Note: using wildcard certificate doesn't work via Apache2 proxy
    if [[ "$_use_wildcard_cert" =~ (^y|^Y) ]]; then
        # Step4: Generate a wildcard key/cert
        _hadoop_ssl_use_wildcard "$_domain_suffix" "./rootCA.key" "./rootCA.pem" "selfsinged-wildcard" "$_password" || return $?
        if [ ! -s ./selfsinged-wildcard.jks ]; then
            _error "Couldn't generate ./selfsinged-wildcard.jks"
            return 1
        fi
        cp -p ./selfsinged-wildcard.jks ./$g_KEYSTORE_FILE
    fi

    local _javahome="`ssh -q root@$_ambari_host "grep java.home /etc/ambari-server/conf/ambari.properties | cut -d \"=\" -f2"`"
    local _cacerts="${_javahome%/}/jre/lib/security/cacerts"

    if ! [[ "$_how_many" =~ ^[0-9]+$ ]]; then
        local _hostnames="$_how_many"
        _info "Copying jks to $_hostnames ..."
        for i in  `echo $_hostnames | sed 's/ /\n/g'`; do
            _hadoop_ssl_per_node "$i" "$_cacerts" "./$g_KEYSTORE_FILE" || return $?
        done
    else
        _info "Copying jks to all nodes..."
        for i in `_docker_seq "$_how_many" "$_start_from"`; do
            _hadoop_ssl_per_node "node${i}${_domain_suffix}" "$_cacerts" "./$g_KEYSTORE_FILE" || return $?
        done
    fi

    [[ "$_no_updating_ambari_config" =~ (^y|^Y) ]] && return $?
    _hadoop_ssl_config_update "$_ambari_host" "$_ambari_port" "$_password"
}

function _hadoop_ssl_config_update() {
    local _ambari_host="${1-$r_AMBARI_HOST}"
    local _ambari_port="${2-8080}"
    local _password="$3"
    local _c="`f_get_cluster_name $_ambari_host`" || return $?

    _info "Updating Ambari configs for HDFS..."
    f_ambari_configs "core-site" "{\"hadoop.rpc.protection\":\"privacy\",\"hadoop.ssl.require.client.cert\":\"false\",\"hadoop.ssl.hostname.verifier\":\"DEFAULT\",\"hadoop.ssl.keystores.factory.class\":\"org.apache.hadoop.security.ssl.FileBasedKeyStoresFactory\",\"hadoop.ssl.server.conf\":\"ssl-server.xml\",\"hadoop.ssl.client.conf\":\"ssl-client.xml\"}" "$_ambari_host" "$_ambari_port"
    f_ambari_configs "ssl-client" "{\"ssl.client.truststore.location\":\"${g_CLIENT_TRUST_LOCATION%/}/${g_CLIENT_TRUSTSTORE_FILE}\",\"ssl.client.truststore.password\":\"${g_CLIENT_TRUSTSTORE_PASSWORD}\",\"ssl.client.keystore.location\":\"${g_CLIENT_KEY_LOCATION%/}/${g_KEYSTORE_FILE}\",\"ssl.client.keystore.password\":\"$_password\"}" "$_ambari_host" "$_ambari_port"
    f_ambari_configs "ssl-server" "{\"ssl.server.truststore.location\":\"${g_CLIENT_TRUST_LOCATION%/}/${g_CLIENT_TRUSTSTORE_FILE}\",\"ssl.server.truststore.password\":\"${g_CLIENT_TRUSTSTORE_PASSWORD}\",\"ssl.server.keystore.location\":\"${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE}\",\"ssl.server.keystore.password\":\"$_password\",\"ssl.server.keystore.keypassword\":\"$_password\"}" "$_ambari_host" "$_ambari_port"
    f_ambari_configs "hdfs-site" "{\"dfs.encrypt.data.transfer\":\"true\",\"dfs.encrypt.data.transfer.algorithm\":\"3des\",\"dfs.http.policy\":\"HTTPS_ONLY\"}" "$_ambari_host" "$_ambari_port" # or HTTP_AND_HTTPS
    f_ambari_configs "mapred-site" "{\"mapreduce.jobhistory.http.policy\":\"HTTPS_ONLY\",\"mapreduce.jobhistory.webapp.https.address\":\"0.0.0.0:19888\"}" "$_ambari_host" "$_ambari_port"
    f_ambari_configs "yarn-site" "{\"yarn.http.policy\":\"HTTPS_ONLY\",\"yarn.nodemanager.webapp.https.address\":\"0.0.0.0:8044\"}" "$_ambari_host" "$_ambari_port"
    f_ambari_configs "tez-site" "{\"tez.runtime.shuffle.keep-alive.enabled\":\"true\"}" "$_ambari_host" "$_ambari_port"

    # If Ambari is 2.4.x or higher below works
    _info "TODO: Please manually update:
    yarn.resourcemanager.webapp.https.address=RM_HOST:8090
    mapreduce.shuffle.ssl.enabled=true (mapreduce.shuffle.port)
    tez.runtime.shuffle.ssl.enable=true"

    _info "Run the below command to restart *ALL* required components:"
    echo "curl -si -u ${g_admin}:${g_admin_pwd} -H 'X-Requested-By:ambari' 'http://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_c}/requests' -X POST --data '{\"RequestInfo\":{\"command\":\"RESTART\",\"context\":\"Restart all required services\",\"operation_level\":\"host_component\"},\"Requests/resource_filters\":[{\"hosts_predicate\":\"HostRoles/stale_configs=true\"}]}'"
}

function _hadoop_ssl_per_node() {
    local _node="$1"
    local _java_default_truststore_path="$2"
    local _local_keystore_path="$3"

    ssh -q root@${_node} "mkdir -m 750 -p ${g_SERVER_KEY_LOCATION%/}; chown root:hadoop ${g_SERVER_KEY_LOCATION%/}; mkdir -m 755 -p ${g_CLIENT_KEY_LOCATION%/}"
    scp ./$g_CLIENT_TRUSTSTORE_FILE root@${_node}:${g_CLIENT_TRUST_LOCATION%/}/ || return $?

    if [ ! -s "$_local_keystore_path" ]; then
        _info "$_local_keystore_path doesn't exist in local, so that recreate and push to nodes..."
        _hadoop_ssl_per_node_inner "$_node" "$_java_default_truststore_path"
    else
        scp ./rootCA.pem $_local_keystore_path root@${_node}:${g_SERVER_KEY_LOCATION%/}/ || return $?
    fi

    # TODO: For ranger. if file exist, need to import the certificate. Also if not kerberos, two way SSL won't work because of non 'usr_client' extension
    ssh -q root@${_node} 'for l in `ls -d /usr/hdp/current/*/conf`; do ln -s '${g_CLIENT_TRUST_LOCATION%/}'/'${g_CLIENT_TRUSTSTORE_FILE}' ${l%/}/ranger-plugin-truststore.jks 2>/dev/null; done'
    ssh -q root@${_node} 'for l in `ls -d /usr/hdp/current/*/conf`; do ln -s '${g_CLIENT_KEY_LOCATION%/}/${g_CLIENT_KEYSTORE_FILE}' ${l%/}/ranger-plugin-keystore.jks 2>/dev/null; done'
    ssh -q root@${_node} "chown root:hadoop ${g_SERVER_KEY_LOCATION%/}/*;chmod 640 ${g_SERVER_KEY_LOCATION%/}/*;"
}

function _hadoop_ssl_per_node_inner() {
    local _node="$1"
    local _java_default_truststore_path="$2"
    # TODO: assuming rootCA.xxx file names

    # Step4: On each node, create a privatekey for the node
    ssh -q root@${_node} "mv -f ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE} ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE}.$$.bak &>/dev/null; keytool -genkey -alias ${_node} -keyalg RSA -keystore ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE} -keysize 2048 -dname \"CN=${_node}, ${_dname_extra}\" -noprompt -storepass ${_password} -keypass ${_password}"
    ssh -q root@${_node} "mv -f ${g_CLIENT_KEY_LOCATION%/}/${g_CLIENT_KEYSTORE_FILE} ${g_CLIENT_KEY_LOCATION%/}/${g_CLIENT_KEYSTORE_FILE}.$$.bak &>/dev/null; keytool -genkey -alias ${_node} -keyalg RSA -keystore ${g_CLIENT_KEY_LOCATION%/}/${g_CLIENT_KEYSTORE_FILE} -keysize 2048 -dname \"CN=${_node}, ${_dname_extra}\" -noprompt -storepass ${_password} -keypass ${_password}"
    # Step5: On each node, create a CSR
    ssh -q root@${_node} "keytool -certreq -alias ${_node} -keystore ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE} -file ${g_SERVER_KEY_LOCATION%/}/${_node}-keystore.csr -storepass ${_password}"
    ssh -q root@${_node} "keytool -certreq -alias ${_node} -keystore ${g_CLIENT_KEY_LOCATION%/}/${g_CLIENT_KEYSTORE_FILE} -file ${g_CLIENT_KEY_LOCATION%/}/${_node}-client-keystore.csr -storepass ${_password}"
    scp root@${_node}:${g_SERVER_KEY_LOCATION%/}/${_node}-keystore.csr ./ || return $?
    scp root@${_node}:${g_CLIENT_KEY_LOCATION%/}/${_node}-client-keystore.csr ./ || return $?
    # Step6: Sign the CSR with the root CA
    openssl x509 -sha256 -req -in ./${_node}-keystore.csr -CA ./rootCA.pem -CAkey ./rootCA.key -CAcreateserial -out ${_node}-keystore.crt -days 730 -passin "pass:$_password" || return $?
    openssl x509 -extensions usr_cert -sha256 -req -in ./${_node}-client-keystore.csr -CA ./rootCA.pem -CAkey ./rootCA.key -CAcreateserial -out ${_node}-client-keystore.crt -days 730 -passin "pass:$_password"
    scp ./rootCA.pem ./${_node}-keystore.crt root@${_node}:${g_SERVER_KEY_LOCATION%/}/ || return $?
    scp ./${_node}-client-keystore.crt root@${_node}:${g_CLIENT_KEY_LOCATION%/}/
    # Step7: On each node, import root CA's cert and the signed cert
    ssh -q root@${_node} "keytool -keystore ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE} -alias rootCA -import -file ${g_SERVER_KEY_LOCATION%/}/rootCA.pem -noprompt -storepass ${_password};keytool -keystore ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE} -alias ${_node} -import -file ${g_SERVER_KEY_LOCATION%/}/${_node}-keystore.crt -noprompt -storepass ${_password}" || return $?
    ssh -q root@${_node} "keytool -keystore ${g_CLIENT_KEY_LOCATION%/}/${g_CLIENT_KEYSTORE_FILE} -alias rootCA -import -file ${g_SERVER_KEY_LOCATION%/}/rootCA.pem -noprompt -storepass ${_password};keytool -keystore ${g_CLIENT_KEY_LOCATION%/}/${g_CLIENT_KEYSTORE_FILE} -alias ${_node} -import -file ${g_CLIENT_KEY_LOCATION%/}/${_node}-client-keystore.crt -noprompt -storepass ${_password}"
    # Step8 (optional): if the java default truststore (cacerts) path is given, also import the cert (and doesn't care if cert already exists)
    if [ ! -z "/etc/pki/java/cacerts" ]; then
        ssh -q root@${_node} "keytool -keystore /etc/pki/java/cacerts -alias hadoopRootCA -import -file ${g_SERVER_KEY_LOCATION%/}/rootCA.pem -noprompt -storepass changeit"
    fi
    if [ ! -z "$_java_default_truststore_path" ]; then
        ssh -q root@${_node} "keytool -keystore $_java_default_truststore_path -alias hadoopRootCA -import -file ${g_SERVER_KEY_LOCATION%/}/rootCA.pem -noprompt -storepass changeit"
    fi
}

function _hadoop_ssl_use_wildcard() {
    local __doc__="Create a self-signed wildcard certificate with openssl command."
    local _domain_suffix="${1-$r_DOMAIN_SUFFIX}"
    local _CA_key="${2}"
    local _CA_cert="${3}"
    local _base_name="${4-selfsignwildcard}"
    local _password="$5"
    local _key_strength="${6-2048}"
    local _work_dir="${7-./}"

    local _subject="/C=AU/ST=QLD/L=Brisbane/O=Hortonworks/OU=Support/CN=*.${_domain_suffix#.}"
    local _subj=""

    [ -z "$_domain_suffix" ] && _domain_suffix=".`hostname`"
    [ -z "$_password" ] && _password=${g_DEFAULT_PASSWORD-hadoop}
    [ -n "$_subject" ] && _subj="-subj ${_subject}"

    # Create a private key with wildcard CN and a CSR file. NOTE: -aes256 to encrypt
    openssl req -nodes -newkey rsa:$_key_strength -keyout ${_work_dir%/}/${_base_name}.key -out ${_work_dir%/}/${_base_name}.csr $_subj
    # Signing a cert with two years expiration
    if [ ! -s "$_CA_key" ]; then
        _info "TODO: No root CA key file ($_CA_key), so signing by itself (not sure if works)..."
        openssl x509 -sha256 -req -in ${_work_dir%/}/${_base_name}.csr -signkey ${_work_dir%/}/${_base_name}.key -out ${_work_dir%/}/${_base_name}.crt -days 730 -passin "pass:$_password" || return $?
    else
        openssl x509 -sha256 -req -in ${_work_dir%/}/${_base_name}.csr -CA ${_CA_cert} -CAkey ${_CA_key} -CAcreateserial -out ${_work_dir%/}/${_base_name}.crt -days 730 -passin "pass:$_password" || return $?
    fi

    # Combine a wildcard key and cert, and convert to p12, so that can convert to a jks file
    openssl pkcs12 -export -in ${_work_dir%/}/${_base_name}.crt -inkey ${_work_dir%/}/${_base_name}.key -out ${_work_dir%/}/${_base_name}.p12 -name ${_base_name} -passout pass:$_password || return $?
    # Convert p12 to jks
    keytool -importkeystore -deststorepass $_password -destkeypass $_password -destkeystore ${_work_dir%/}/${_base_name}.jks -srckeystore ${_work_dir%/}/${_base_name}.p12 -srcstoretype PKCS12 -srcstorepass $_password -alias ${_base_name} || return $?

    if [ ! -s "$_CA_cert" ]; then
        keytool -keystore ${_work_dir%/}/${_base_name}.jks -alias rootCA -import -file "$_CA_cert" -noprompt -storepass ${_password}
    fi

    chmod 600 ${_work_dir%/}/${_base_name}.{key,jks}
    # NOTE: a truststore needs to import this cert or root CA cert.
}

function f_hadoop_spnego_setup() {
    local __doc__="set up HTTP Authentication for HDFS, YARN, MapReduce2, HBase, Oozie, Falcon and Storm"
    # http://docs.hortonworks.com/HDPDocuments/Ambari-2.4.2.0/bk_ambari-security/content/configuring_http_authentication_for_HDFS_YARN_MapReduce2_HBase_Oozie_Falcon_and_Storm.html
    local _realm="${1-$g_KDC_REALM}"
    local _domain="${2-${r_DOMAIN_SUFFIX#.}}"
    local _ambari_host="${3-$r_AMBARI_HOST}"
    local _ambari_port="${4-8080}"
    local _how_many="${5-$r_NUM_NODES}"
    local _start_from="${6-$r_NODE_START_NUM}"

    local _c="`f_get_cluster_name $_ambari_host`" || return 1
    local _cmd="[ ! -s /etc/security/http_secret ] && dd if=/dev/urandom of=/etc/security/http_secret bs=1024 count=1; chown hdfs:hadoop /etc/security/http_secret; chmod 440 /etc/security/http_secret"

    if ! [[ "$_how_many" =~ ^[0-9]+$ ]]; then
        local _hostnames="$_how_many"
        _info "Creating http_secret on $_hostnames ..."
        for i in  `echo $_hostnames | sed 's/ /\n/g'`; do
            ssh -q "$i" "$_cmd" || return $?
        done
    else
        _info "Creating http_secret on all nodes ..."
        f_run_cmd_on_nodes "$_cmd" "$_how_many" "$_start_from" || return $?
    fi

    f_ambari_configs "core-site" "{\"hadoop.http.authentication.simple.anonymous.allowed\":\"false\",\"hadoop.http.authentication.signature.secret.file\":\"/etc/security/http_secret\",\"hadoop.http.authentication.type\":\"kerberos\",\"hadoop.http.authentication.kerberos.keytab\":\"/etc/security/keytabs/spnego.service.keytab\",\"hadoop.http.authentication.kerberos.principal\":\"HTTP/_HOST@${_realm}\",\"hadoop.http.filter.initializers\":\"org.apache.hadoop.security.AuthenticationFilterInitializer\",\"hadoop.http.authentication.cookie.domain\":\"${_domain}\"}" "$_ambari_host"

    # If Ambari is 2.4.x or higher below works
    _info "Run the below command to restart *ALL* required components:"
    echo "curl -si -u ${g_admin}:${g_admin_pwd} -H 'X-Requested-By:ambari' 'http://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_c}/requests' -X POST --data '{\"RequestInfo\":{\"command\":\"RESTART\",\"context\":\"Restart all required services\",\"operation_level\":\"host_component\"},\"Requests/resource_filters\":[{\"hosts_predicate\":\"HostRoles/stale_configs=true\"}]}'"
}

function f_kerberos_crossrealm_setup() {
    local __doc__="TODO: Setup cross realm (MIT only). Requires Password-less SSH login"
    local _remote_kdc="$1"
    local _remote_ambari="$2"

    local _local_kdc="`hostname -i`"
    if [[ "$_local_kdc" =~ ^"127" ]]; then
        _local_kdc="`ifconfig ens3 | grep -oP 'inet addr:\d+\.\d+\.\d+\.\d+' | cut -d":" -f2`"
        [ -z "$_local_kdc" ] && return 11
        _warn "hostname -i doesn't work so that using IP of 'ens3' $_local_kdc"
    fi

    nc -z ${_remote_kdc} 88 || return 12
    nc -z ${_remote_ambari} 8080 || return 13

    local _local_realm="`sed -n -e 's/^ *default_realm *= *\b\(.\+\)\b/\1/p' /etc/krb5.conf`"
    [ -z  "${_local_realm}" ] && return 21
    local _remote_realm="`ssh -q root@${_remote_kdc} sed -n -e 's/^ *default_realm *= *\b\(.\+\)\b/\1/p' /etc/krb5.conf`"
    [ -z  "${_remote_realm}" ] && return 22

    kadmin.local -q "add_principal -pw $_password krbtgt/${_remote_realm}@${_local_realm}" || return 31
    ssh -q root@${_remote_kdc} kadmin.local -q "add_principal -pw $_password krbtgt/${_local_realm}@${_remote_realm}" || return 32
    # - set hadoop.security.auth_to_local for both clusters
    # - set [capaths] in both clusters
    # - set dfs.namenode.kerberos.principal.pattern = *
}


function f_ldap_server_install_on_host() {
    local __doc__="Install LDAP server packages on Ubuntu (need to test setup)"
    local _shared_domain="$1"
    local _password="${2-$g_DEFAULT_PASSWORD}"

    if [ ! `which apt-get` ]; then
        _warn "No apt-get"
        return 1
    fi

    [ -z "$_shared_domain" ] && _shared_domain="example.com"

cat << EOF | debconf-set-selections
slapd slapd/internal/adminpw password ${_password}
slapd slapd/internal/generated_adminpw password ${_password}
slapd slapd/password2 password ${_password}
slapd slapd/password1 password ${_password}
slapd slapd/dump_database_destdir string /var/backups/slapd-VERSION
slapd slapd/domain string ${_shared_domain}
slapd shared/organization string Support
slapd slapd/backend string HDB
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/allow_ldap_v2 boolean true
slapd slapd/no_configuration boolean false
slapd slapd/dump_database string when needed
EOF

    DEBIAN_FRONTEND=noninteractive apt-get install -y slapd ldap-utils

    if [ "$_shared_domain" == "example.com" ]; then
        curl curl -H "accept-encoding: gzip" https://raw.githubusercontent.com/hajimeo/samples/master/misc/example.ldif -o /tmp/example.ldif || return $?
        ldapadd -x -D cn=admin,dc=example,dc=com -w hadoop -f /tmp/example.ldif
    fi
}

function f_ldap_server_install_on_ambari_node() {
    local __doc__="TODO: CentOS6 only: Install LDAP server packages for sssd (security lab)"
    local _ldap_domain="$1"
    local _password="${2-$g_DEFAULT_PASSWORD}"
    local _server="${3-$r_AMBARI_HOST}"

    if [ -z "$_ldap_domain" ]; then
        _warn "No LDAP Domain, so using dc=example,dc=com"
        _ldap_domain="dc=example,dc=com"
    fi

    # slapd ldapsearch install TODO: chkconfig slapd on wouldn't do anything on docker container
    ssh root@$_server -t "yum install openldap openldap-servers openldap-clients -y" || return $?
    ssh root@$_server -t "cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG ; chown ldap. /var/lib/ldap/DB_CONFIG && /etc/rc.d/init.d/slapd start" || return $?
}

function f_ldap_server_configure() {
    local __doc__="TODO: Configure LDAP server via SSH (requires password-less ssh)"
    local _ldap_domain="$1"
    local _password="${2-$g_DEFAULT_PASSWORD}"
    local _server="${3-localhost}"

    if [ -z "$_ldap_domain" ]; then
        _ldap_domain="dc=example,dc=com"
        _warn "No LDAP Domain, so using ${_ldap_domain}"
    fi

    local _md5="`ssh root@$_server -t "slappasswd -s ${_password}"`" || return $?

    if [ -z "$_md5" ]; then
        _error "Couldn't generate hashed password"
        return 1
    fi

    _info "Updating password"
    ssh -q root@$_server -t 'echo "dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: '${_md5}'
" > /tmp/chrootpw.ldif && ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/chrootpw.ldif' || return $?

    _info "Updating domain"
    ssh -q root@$_server -t 'echo "dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth"
  read by dn.base="cn=Manager,'${_ldap_domain}'" read by * none

dn: olcDatabase={2}bdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: '${_ldap_domain}'

dn: olcDatabase={2}bdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=Manager,'${_ldap_domain}'

dn: olcDatabase={2}bdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: '${_md5}'

dn: olcDatabase={2}bdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by
  dn="cn=Manager,'${_ldap_domain}'" write by anonymous auth by self write by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to * by dn="cn=Manager,'${_ldap_domain}'" write by * read
" > /tmp/chdomain.ldif && ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/chdomain.ldif' || return $?

    _info "Updating base domain"
    ssh root@$_server -t 'echo "dn: '${_ldap_domain}'
objectClass: top
objectClass: dcObject
objectclass: organization
o: Server World
dc: Srv

dn: cn=Manager,'${_ldap_domain}'
objectClass: organizationalRole
cn: Manager
description: Directory Manager

dn: ou=People,'${_ldap_domain}'
objectClass: organizationalUnit
ou: People

dn: ou=Group,'${_ldap_domain}'
objectClass: organizationalUnit
ou: Group
" > /tmp/basedomain.ldif && ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/basedomain.ldif' || return $?
}

function f_ldap_client_install() {
    local __doc__="TODO: CentOS6 only: Install LDAP client packages for sssd (security lab)"
    # somehow having difficulty to install openldap in docker so using dockerhost1
    local _ldap_server="${1}"
    local _ldap_basedn="${2}"
    local _how_many="${3-$r_NUM_NODES}"
    local _start_from="${4-$r_NODE_START_NUM}"

    if [ -z "$_ldap_server" ]; then
        _warn "No LDAP server hostname. Using ${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}"
        _ldap_server="${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}"
    fi
    if [ -z "$_ldap_basedn" ]; then
        _warn "No LDAP Base DN, so using dc=example,dc=com"
        _ldap_basedn="dc=example,dc=com"
    fi

    for i in `_docker_seq "$_how_many" "$_start_from"`; do
        ssh root@node$i${r_DOMAIN_SUFFIX} -t "yum -y erase nscd;yum -y install sssd sssd-client sssd-ldap openldap-clients"
        if [ $? -eq 0 ]; then
            ssh root@node$i${r_DOMAIN_SUFFIX} -t "authconfig --enablesssd --enablesssdauth --enablelocauthorize --enableldap --enableldapauth --disableldaptls --ldapserver=ldap://${_ldap_server} --ldapbasedn=${_ldap_basedn} --update" || _warn "node$i failed to setup ldap client"
            # test
            #authconfig --test
            # getent passwd admin
        else
            _warn "node$i failed to install ldap client"
        fi
    done
}

function f_sssd_setup() {
    local __doc__="setup SSSD on each node (security lab) If /etc/sssd/sssd.conf exists, skip"
    # https://github.com/HortonworksUniversity/Security_Labs#install-solrcloud
    local ad_user="$1"    #registersssd
    local ad_pwd="$2"
    local ad_domain="$3"  #lab.hortonworks.net
    local ad_dc="$4"      #ad01.lab.hortonworks.net
    local ad_root="$5"    #dc=lab,dc=hortonworks,dc=net
    local ad_ou_name="$6" #HadoopNodes

    local ad_ou="ou=${ad_ou_name},${ad_root}"
    local ad_realm=${ad_domain^^}

    f_run_cmd_on_nodes 'which adcli || ( yum makecache fast && yum -y install epel-release; yum -y install sssd oddjob-mkhomedir authconfig sssd-krb5 sssd-ad sssd-tools adcli )'

    local _cmd="echo -n '"${ad_pwd}"' | kinit ${ad_user}

sudo adcli join -v \
  --domain-controller=${ad_dc} \
  --domain-ou=\"${ad_ou}\" \
  --login-ccache=\"/tmp/krb5cc_0\" \
  --login-user=\"${ad_user}\" \
  -v \
  --show-details

tee /etc/sssd/sssd.conf > /dev/null <<EOF
[sssd]
## master & data nodes only require nss. Edge nodes require pam.
services = nss, pam, ssh, autofs, pac
config_file_version = 2
domains = ${ad_realm}
override_space = _

[domain/${ad_realm}]
id_provider = ad
ad_server = ${ad_dc}
#ad_server = ad01, ad02, ad03
#ad_backup_server = ad-backup01, 02, 03
auth_provider = ad
chpass_provider = ad
access_provider = ad
enumerate = False
krb5_realm = ${ad_realm}
ldap_schema = ad
ldap_id_mapping = True
cache_credentials = True
ldap_access_order = expire
ldap_account_expire_policy = ad
ldap_force_upper_case_realm = true
fallback_homedir = /home/%d/%u
default_shell = /bin/false
ldap_referrals = false

[nss]
memcache_timeout = 3600
override_shell = /bin/bash
EOF

chmod 0600 /etc/sssd/sssd.conf
service sssd restart
authconfig --enablesssd --enablesssdauth --enablemkhomedir --enablelocauthorize --update

#chkconfig oddjobd on
#service oddjobd restart
#chkconfig sssd on
service sssd restart

kdestroy"

    # To test: id yourusername && groups yourusername

    f_run_cmd_on_nodes "[ -s /etc/sssd/sssd.conf ] || ( $_cmd )"

    #refresh user and group mappings
    local _c="`f_get_cluster_name`" || return $?
    local _hdfs_client_node="`_ambari_query_sql "select h.host_name from hostcomponentstate hcs join hosts h on hcs.host_id=h.host_id where component_name='HDFS_CLIENT' and current_state='INSTALLED' limit 1" $r_AMBARI_HOST`"
    if [ -z "$_hdfs_client_node" ]; then
        _error "No node found for HDFS command"
        return 1
    fi
    ssh root@$_hdfs_client_node -t "sudo -u hdfs bash -c \"kinit -kt /etc/security/keytabs/hdfs.headless.keytab hdfs-${_c}; hdfs dfsadmin -refreshUserToGroupsMappings\""

    local _yarn_rm_node="`_ambari_query_sql "select h.host_name from hostcomponentstate hcs join hosts h on hcs.host_id=h.host_id where component_name='RESOURCEMANAGER' and current_state='STARTED' limit 1" $r_AMBARI_HOST`"
    if [ -z "$_yarn_rm_node" ]; then
        _error "No node found for YARN command"
        return 1
    fi
    ssh root@$_yarn_rm_node -t "sudo -u yarn bash -c \"kinit -kt /etc/security/keytabs/yarn.service.keytab yarn/$(hostname -f); yarn rmadmin -refreshUserToGroupsMappings\""
}

function f_ssl_self_signed_cert() {
    local __doc__="Setup a self-signed certificate with openssl command. See: http://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.5.3/bk_security/content/set_up_ssl_for_ambari.html"
    local _subject="$1" # "/C=AU/ST=QLD/O=Hortonworks/CN=*.hortonworks.com"
    local _base_name="${2-selfsign}"
    local _password="$3"
    local _key_strength="${4-2048}"
    local _work_dir="${5-./}"
    local _subj=""

    if [ -z "$_password" ]; then
        _password="${g_DEFAULT_PASSWORD-hadoop}"
    fi
    if [ -n "$_subject" ]; then
        _subj="-subj ${_subject}"
    fi

    # Create a private key NOTE: -aes256 to encrypt
    openssl genrsa -out ${_work_dir%/}/${_base_name}.key $_key_strength || return $?
    # Generate cert from above key
    openssl req -new -x509 -nodes -days 3650 -key ${_work_dir%/}/${_base_name}.key -out ${_work_dir%/}/${_base_name}.crt $_subj || return $?
    # or Create a CSR
    #openssl req -new -key ${_work_dir%/}/${_base_name}.key -out ${_work_dir%/}/${_base_name}.csr $_subj || return $?
    # Signing a cert by itself TODO: -extensions v3_ca -extfile openssl.cfg
    #openssl x509 -req -days 3650 -in ${_work_dir%/}/${_base_name}.csr -signkey ${_work_dir%/}/${_base_name}.key -out ${_work_dir%/}/${_base_name}.crt || return $?
    #openssl x509 -in cert.crt -inform der -outform pem -out cert.pem

    # Convert pem to p12, then jks
    openssl pkcs12 -export -in ${_work_dir%/}/${_base_name}.crt -inkey ${_work_dir%/}/${_base_name}.key -out ${_work_dir%/}/${_base_name}.p12 -name ${_base_name} -passout pass:$_password || return $?
    keytool -importkeystore -deststorepass $_password -destkeypass $_password -destkeystore "${_work_dir%/}/${g_KEYSTORE_FILE}" -srckeystore ${_work_dir%/}/${_base_name}.p12 -srcstoretype PKCS12 -srcstorepass $_password -alias ${_base_name}

    # trust store for service (eg.: hiveserver2)
    keytool -keystore ${_work_dir%/}/${g_TRUSTSTORE_FILE} -alias ${_base_name} -import -file ${_work_dir%/}/${_base_name}.crt -noprompt -storepass "${g_CLIENT_TRUSTSTORE_PASSWORD}" || return $?
    # trust store for client (eg.: beeline)
    keytool -keystore ${_work_dir%/}/${g_CLIENT_TRUSTSTORE_FILE} -alias ${_base_name} -import -file ${_work_dir%/}/${_base_name}.crt -noprompt -storepass "${g_CLIENT_TRUSTSTORE_PASSWORD}" || return $?
    chmod a+r ${_work_dir%/}/${g_CLIENT_TRUSTSTORE_FILE}
}

function f_ssl_internal_CA_setup() {
    local __doc__="(not in use) Setup Internal CA for generating self-signed certificate"
    local _dname="$1"
    local _password="$2"
    local _domain_suffix="${3-$r_DOMAIN_SUFFIX}"
    local _ca_dir="${4-./}"
    local _work_dir="${5-./}"

    if [ -z "$_domain_suffix" ]; then
        _domain_suffix=".`hostname -d`"
    fi
    if [ -z "$_dname" ]; then
        _dname="CN=internalca${_domain_suffix}, OU=Support, O=Hortonworks, L=Brisbane, ST=QLD, C=AU"
    fi
    if [ -z "$_password" ]; then
        _password="${g_DEFAULT_PASSWORD-hadoop}"
    fi

    openssl genrsa -out ${_work_dir%/}/ca.key 4096 #8192
    # Generating CA certificate
    _ssl_openssl_cnf_generate "$_dname" "$_password" "$_domain_suffix" "$_work_dir" || return $?
    openssl req -new -x509 -key ${_work_dir%/}/ca.key -out ${_work_dir%/}/ca.crt -days 3650 -config "${_work_dir%/}/openssl.cnf" -passin pass:$_password || return $?

    chmod 0400 ${_work_dir%/}/private/ca.key

    # Set up the CA directory structure
    mkdir -m 0700 ${_ca_dir%/} ${_ca_dir%/}/certs ${_ca_dir%/}/crl ${_ca_dir%/}/newcerts ${_ca_dir%/}/private
    mv ${_work_dir%/}/ca.key ${_ca_dir%/}/private
    mv ${_work_dir%/}/ca.crt ${_ca_dir%/}/certs
    touch ${_ca_dir%/}/index.txt
    echo 1000 >> ${_ca_dir%/}/serial
}

function _ssl_openssl_cnf_generate() {
    local __doc__="(not in use) Generate openssl config file (openssl.cnf) for self-signed certificate (default is for wildcard)"
    # _ssl_openssl_cnf_generate "$_dname" "$_password" "$_domain_suffix" "$_work_dir"
    local _dname="$1"
    local _password="$2"
    local _domain_suffix="${3-.`hostname -d`}"
    local _work_dir="${4-./}"

    if [ -s "${_work_dir%/}/openssl.cnf" ]; then
        _warn "${_work_dir%/}/openssl.cnf exists. Skipping..."
        return
    fi

    [ -z "$_domain_suffix" ] && _domain_suffix=".`hostname`"
    [ -z "$_dname" ] && _dname="CN=*.${_domain_suffix#.}, OU=Support, O=Hortonworks, L=Brisbane, ST=QLD, C=AU"
    [ -z "$_password" ] && _password=${g_DEFAULT_PASSWORD-hadoop}

    echo [ req ] > "${_work_dir%/}/openssl.cnf"
    echo input_password = $_password >> "${_work_dir%/}/openssl.cnf"
    echo output_password = $_password >> "${_work_dir%/}/openssl.cnf"
    echo distinguished_name = req_distinguished_name >> "${_work_dir%/}/openssl.cnf"
    echo req_extensions = v3_req  >> "${_work_dir%/}/openssl.cnf"
    echo prompt=no >> "${_work_dir%/}/openssl.cnf"
    echo [req_distinguished_name] >> "${_work_dir%/}/openssl.cnf"
    for _a in `echo "$_dname" | sed 's/,/\n/g'`; do
        echo ${_a} >> "${_work_dir%/}/openssl.cnf"
    done
    echo [EMAIL PROTECTED] >> "${_work_dir%/}/openssl.cnf"
    echo [EMAIL PROTECTED] >> "${_work_dir%/}/openssl.cnf"
    echo [ v3_req ] >> "${_work_dir%/}/openssl.cnf"
    echo basicConstraints = critical,CA:FALSE >> "${_work_dir%/}/openssl.cnf"
    echo keyUsage = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment, keyAgreement >> "${_work_dir%/}/openssl.cnf"
    echo extendedKeyUsage=emailProtection,clientAuth >> "${_work_dir%/}/openssl.cnf"
    echo [ ${_domain_suffix#.} ] >> "${_work_dir%/}/openssl.cnf"
    echo subjectAltName = DNS:${_domain_suffix#.},DNS:*${_domain_suffix} >> "${_work_dir%/}/openssl.cnf"
}

function f_ambari_configs() {
    local __doc__="Wrapper function to update configs with configs.sh"
    local _type="$1"
    local _dict="$2"
    local _ambari_host="${3-$r_AMBARI_HOST}"
    local _ambari_port="${4-8080}"
    local _c="`f_get_cluster_name $_ambari_host`" || return $?

    scp -q root@$_ambari_host:/var/lib/ambari-server/resources/scripts/configs.sh ./ || return $?
    bash ./configs.sh -u "${g_admin}" -p "${g_admin_pwd}" -port ${_ambari_port} get $_ambari_host $_c $_type /tmp/${_type}_${__PID}.json || return $?

    echo "import json
a=json.loads('{'+open('/tmp/${_type}_${__PID}.json','r').read()+'}')
n=json.loads('"${_dict}"')
a['properties'].update(n)
s=json.dumps(a['properties'])
f=open('/tmp/${_type}_updated_${__PID}.json','w')
f.write('\"properties\":'+s)
f.close()" > /tmp/configs_${__PID}.py

    python /tmp/configs_${__PID}.py || return $?
    bash ./configs.sh -u "${g_admin}" -p "${g_admin_pwd}" -port ${_ambari_port} set $_ambari_host $_c $_type /tmp/${_type}_updated_${__PID}.json
}

function f_etc_hosts_update() {
    local __doc__="TODO: maintain /etc/hosts for security (distcp)"
    local _how_many="${1-$r_NUM_NODES}"
    local _start_from="${2-$r_NODE_START_NUM}"
    local _ip_network="${3}"
    local _node="${4-$g_NODE_HOSTNAME_PREFIX}"
    local _domain_suffix="${5-$r_DOMAIN_SUFFIX}"
    local _last_num=$(( $_start_from + $_how_many - 1 ))
    local _f=/etc/hosts

    local _bak="_$(date +"%Y%m%d%").bak"
    for i in {$_start_from..$_last_num}; do
        if [ ! -z "$_bak" ] && [ -s $_f$_bak ]; then
            _bak=""
        fi

        if grep -qE "^[1-9]+.+\s${_node}${i}.${_domain_suffix#.}\b" $_f; then
            sed -i"$_bak" -e "s/^[1-9]+.+\s${_node}${i}.${_domain_suffix#.}.+$/${_ip_network%.}.${i} ${_node}${i}.${_domain_suffix#.} ${_node}${i}.${_domain_suffix#.}. ${_node}${i}/" $_f && _bak=""
        else
            if [ ! -z "$_bak" ]; then
                cp -p $_f $_f$_bak
                _bak=""
            fi
            echo '${_ip_network%.}.${i} ${_node}${i}.${_domain_suffix#.} ${_node}${i}.${_domain_suffix#.} ${_node}${i}.${_domain_suffix#.}. ${_node}${i}' >> $_f
        fi
    done
}

### main ########################
# TODO: at this moment, only when this script is directly used, do update check.
if [ "$0" = "$BASH_SOURCE" ]; then
    f_update_check
    echo "Usage:
    source $BASH_SOURCE
    f_loadResp 'path/to/your/resp/file'
    f_xxxxx # or type 'help'
    "
else
    g_START_HDP_SH="start_hdp.sh"
    # TODO: assuming g_SCRIPT_NAME contains a right filename or can be empty
    if [ ! -s "./$g_START_HDP_SH" ]; then
        echo "start_hdp.sh is missing. Downloading..."
        curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/$g_START_HDP_SH -o "./$g_START_HDP_SH"
    fi
    source "./$g_START_HDP_SH"
fi