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
#   f_kdc_install_on_host && f_ambari_kerberos_setup
#
# If Sandbox (after KDC setup):
# NOTE: sandbox.hortonworks.com needs to be resolved to a proper IP, also password less scp/ssh required
#   f_ambari_kerberos_setup "EXAMPLE.COM" "172.17.0.1" "" "sandbox.hortonworks.com" "sandbox.hortonworks.com"
#
# Example 2: How to set up SSL on hadoop component (requires JRE/JDK for keytool command)
#   source ./setup_security.sh && f_loadResp
#   f_hadoop_ssl_setup
#
# If Sandbox:
# NOTE sandbox.hortonworks.com needs to be resolved to a proper IP, also password less scp/ssh required
#   f_hadoop_ssl_setup "" "" "sandbox.hortonworks.com" "8080" "sandbox.hortonworks.com"
#

### OS/shell settings
shopt -s nocasematch
#shopt -s nocaseglob
set -o posix
#umask 0000

# Global variables
g_SERVER_KEY_LOCATION="/etc/hadoop/secure/serverKeys/"
g_CLIENT_TRUST_LOCATION="/etc/hadoop/secure/clientKeys/"
g_KEYSTORE_FILE="server.keystore.jks"
g_TRUSTSTORE_FILE="server.truststore.jks"
g_CLIENT_TRUSTSTORE_FILE="all.jks"
g_CLIENT_TRUSTSTORE_PASSWORD="changeit"

function f_kdc_install_on_ambari_node() {
    local __doc__="(Deprecated) Install KDC/kadmin service to $r_AMBARI_HOST. May need UDP port forwarder https://raw.githubusercontent.com/hajimeo/samples/master/python/udp_port_forwarder.py"
    local _realm="${1-EXAMPLE.COM}"
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
    local _realm="${1-EXAMPLE.COM}"
    local _password="${2-$g_DEFAULT_PASSWORD}"
    local _server="${3-`hostname -i`}"

    if [ ! `which apt-get` ]; then
        _warn "No apt-get"
        return 1
    fi

    DEBIAN_FRONTEND=noninteractive apt-get install -y krb5-kdc krb5-admin-server || return $?

    if [ -s /var/lib/krb5kdc/principal ]; then
        _info "/var/lib/krb5kdc/principal already exists. Not try creating..."
        return 0
    fi

    mv /etc/krb5.conf /etc/krb5.conf.orig
    echo "[libdefaults]
 default_realm = $_realm
[realms]
 $_realm = {
   kdc = $_server
   admin_server = $_server
 }" > /etc/krb5.conf
    kdb5_util create -s -P $_password || return $?  # or krb5_newrealm
    echo '*/admin *' > /etc/krb5kdc/kadm5.acl
    service krb5-kdc restart
    service krb5-admin-server restart
    sleep 3
    kadmin.local -q "add_principal -pw $_password admin/admin"
}

function _ambari_kerberos_generate_service_config() {
    local __doc__="Output (return) service config for Ambari APIs. TODO: MIT KDC only by created by f_kdc_install_on_host"
    # https://cwiki.apache.org/confluence/display/AMBARI/Automated+Kerberizaton#AutomatedKerberizaton-EnablingKerberos
    local _realm="${1-EXAMPLE.COM}"
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
    local _realm="${1-EXAMPLE.COM}"
    local _kdc_server="${2-$r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}"
    local _password="${3}"
    local _ambari_host="${4-$r_AMBARI_HOST}"
    local _how_many="${5-$r_NUM_NODES}"
    local _start_from="${6-$r_NODE_START_NUM}"

    if [ -z "$_password" ]; then
        _password=${g_DEFAULT_PASSWORD-hadoop}
    fi

    local _cluster_name="`f_get_cluster_name $_ambari_host`" || return 1
    local _api_uri="http://$_ambari_host:8080/api/v1/clusters/$_cluster_name"
    local _stack_name="HDP"
    local _stack_version"`_ambari_query_sql "select s.stack_version from clusters c join stack s on c.desired_stack_id = s.stack_id where c.cluster_name='$_cluster_name';" "$_ambari_host"`"
    local _request_context="Stop Service with f_ambari_kerberos_setup"
    local _version="version`date +%s`000"

    #local _kdc_type="${3}" # TODO: Not using and MIT KDC only
    # Test GET method
    #response=$(curl --write-out %{http_code} -s -o /dev/null "${_api_uri}/configurations/service_config_versions?service_name=KERBEROS")

    #_info "Delete existing KERBEROS service"
    #_api_uri="http://node1.localdomain:8080/api/v1/clusters/c1"
    #curl -si -H "X-Requested-By:ambari" -u admin:admin -i -X PUT "${_api_uri}" -d '{"Clusters":{"security_type":"NONE"}}'
    #curl -si -H "X-Requested-By:ambari" -u admin:admin -i -X DELETE "${_api_uri}/services/KERBEROS"

    _info "register Kerberos service and component"
    curl -si -H "X-Requested-By:ambari" -u admin:admin -X POST "${_api_uri}/services" -d '{"ServiceInfo": { "service_name": "KERBEROS"}}'
    sleep 3;
    curl -si -H "X-Requested-By:ambari" -u admin:admin -X POST "${_api_uri}/services?ServiceInfo/service_name=KERBEROS" -d '{"components":[{"ServiceComponentInfo":{"component_name":"KERBEROS_CLIENT"}}]}'
    sleep 3;

    if ! [[ "$_how_many" =~ ^[0-9]+$ ]]; then
        local _hostnames="$_how_many"
        _info "Adding Kerberos client to $_hostnames"
        for _h in `echo $_hostnames | sed 's/ /\n/g'`; do
            curl -si -H "X-Requested-By:ambari" -u admin:admin -X POST -d '{"host_components" : [{"HostRoles" : {"component_name":"KERBEROS_CLIENT"}}]}' "${_api_uri}/hosts?Hosts/host_name=${_h}"
            sleep 1;
        done
    else
        _info "Adding Kerberos client on all nodes"
        for i in `_docker_seq "$_how_many" "$_start_from"`; do
            curl -si -H "X-Requested-By:ambari" -u admin:admin -X POST -d '{"host_components" : [{"HostRoles" : {"component_name":"KERBEROS_CLIENT"}}]}' "${_api_uri}/hosts?Hosts/host_name=node$i${r_DOMAIN_SUFFIX}"
            sleep 1;
        done
    fi
     #-d '{"RequestInfo":{"query":"Hosts/host_name=node1.localdomain|Hosts/host_name=node2.localdomain|..."},"Body":{"host_components":[{"HostRoles":{"component_name":"KERBEROS_CLIENT"}}]}}'

    _info "Add/Upload the KDC configuration"
    _ambari_kerberos_generate_service_config "$_realm" "$_kdc_server" > /tmp/${_cluster_name}_kerberos_service_conf.json
    curl -si -H "X-Requested-By:ambari" -u admin:admin -X PUT "${_api_uri}" -d @/tmp/${_cluster_name}_kerberos_service_conf.json
    sleep 3;

    #_info "Storing KDC admin credential temporarily"
    #curl -si -H "X-Requested-By:ambari" -u admin:admin -X PUT "${_api_uri}/credentials/kdc.admin.credential" -d "{\"Credential\":{\"principal\":\"admin/admin@${_realm}\",\"key\":\"${_password}\",\"type\":\"temporary\"}}"

    _info "Starting (installing) Kerberos"
    curl -si -H "X-Requested-By:ambari" -u admin:admin -X PUT "${_api_uri}/services?ServiceInfo/state=INSTALLED&ServiceInfo/service_name=KERBEROS" -d '{"RequestInfo":{"context":"Install Kerberos Service with f_ambari_kerberos_setup","operation_level":{"level":"CLUSTER","cluster_name":"'$_cluster_name'"}},"Body":{"ServiceInfo":{"state":"INSTALLED"}}}'
    sleep 5;

    #_info "Get the default kerberos descriptor and upload (assuming no current)"
    curl -s -H "X-Requested-By:ambari" -u admin:admin -X GET "http://$_ambari_host:8080/api/v1/stacks/$_stack_name/versions/${_stack_version}/artifacts/kerberos_descriptor" -o /tmp/${_cluster_name}_kerberos_descriptor.json
    #curl -s -H "X-Requested-By:ambari" -u admin:admin -X GET "${_api_uri}/artifacts/kerberos_descriptor" -o /tmp/${_cluster_name}_kerberos_descriptor.json

    # For ERROR "The properties [Artifacts/stack_version, href, Artifacts/stack_name] specified in the request or predicate are not supported for the resource type Artifact."
    python -c "import sys,json
with open('/tmp/${_cluster_name}_kerberos_descriptor.json') as jd:
    a=json.load(jd)
a.pop('href', None)
a.pop('Artifacts', None)
with open('/tmp/${_cluster_name}_kerberos_descriptor.json', 'w') as jd:
    json.dump(a, jd)"

    curl -si -H "X-Requested-By:ambari" -u admin:admin -X POST "${_api_uri}/artifacts/kerberos_descriptor" -d @/tmp/${_cluster_name}_kerberos_descriptor.json
    sleep 3;

    _info "Stopping all services...."
    #curl -si -H "X-Requested-By:ambari" -u admin:admin -X PUT "${_api_uri}" -d '{"Clusters":{"security_type":"NONE"}}'
    curl -si -H "X-Requested-By:ambari" -u admin:admin -X PUT -d "{\"RequestInfo\":{\"context\":\"$_request_context\"},\"Body\":{\"ServiceInfo\":{\"state\":\"INSTALLED\"}}}" "${_api_uri}/services"
    sleep 3;
    # confirming if it's stopped
    for _i in {1..9}; do
        _n="`_ambari_query_sql "select count(*) from request where request_context = '$_request_context' and end_time < start_time" "$_ambari_host"`"
        [ 0 -eq $_n ] && break;
        sleep 15;
    done

    # occationaly gets "Cannot run program "kadmin": error=2, No such file or directory"
    ssh -q root@$_ambari_host -t which kadmin &>/dev/null || sleep 10

    _info "Set up Kerberos..."
    curl -si -H "X-Requested-By:ambari" -u admin:admin -X PUT "${_api_uri}" -d "{
  \"session_attributes\" : {
    \"kerberos_admin\" : {
      \"principal\" : \"admin/admin@$_realm\",
      \"password\" : \"$_password\"
    }
  },
  \"Clusters\": {
    \"security_type\" : \"KERBEROS\"
  }
}"
    sleep 3;
    # wait until it's set up
    for _i in {1..9}; do
        _n="`_ambari_query_sql "select count(*) from request where request_context = 'Preparing Operations' and end_time < start_time" "$_ambari_host"`"
        [ 0 -eq $_n ] && break;
        sleep 15;
    done

    _info "Start all services"
    curl -si -H "X-Requested-By:ambari" -u admin:admin -X PUT -d "{\"RequestInfo\":{\"context\":\"Start Service with f_ambari_kerberos_setup\"},\"Body\":{\"ServiceInfo\":{\"state\":\"STARTED\"}}}" ${_api_uri}/services
}

function f_hadoop_spnego_setup() {
    local __doc__="set up HTTP Authentication for HDFS, YARN, MapReduce2, HBase, Oozie, Falcon and Storm"
    # http://docs.hortonworks.com/HDPDocuments/Ambari-2.4.2.0/bk_ambari-security/content/configuring_http_authentication_for_HDFS_YARN_MapReduce2_HBase_Oozie_Falcon_and_Storm.html
    local _ambari_host="${1}"
    local _ambari_port="${2-8080}"
    local _ambari_ssl="${3}"
    local _cluster_name="${4-$r_CLUSTER_NAME}"
    local _realm="${5-EXAMPLE.COM}"
    local _domain="${6-${r_DOMAIN_SUFFIX#.}}"
    local _opts=""
    local _http="http"

    if _isYes "$_ambari_ssl"; then
        _opts="$_opts -s"
        _http="https"
    fi
    if [ -z "$_ambari_host" ]; then
        if [ -z "$r_AMBARI_HOST" ]; then
            _ambari_host="hostname -f"
        else
            _ambari_host="$r_AMBARI_HOST"
        fi
        _info "Using $_ambari_hsot for Ambari server hostname..."
    fi

    if [ -z "$_cluster_name" ]; then
        _cluster_name="`f_get_cluster_name $_ambari_host`" || return 1
    fi

    f_run_cmd_on_nodes "dd if=/dev/urandom of=/etc/security/http_secret bs=1024 count=1 && chown hdfs:hadoop /etc/security/http_secret && chmod 440 /etc/security/http_secret"

    local _type_prop=""
    declare -A _configs # NOTE: this should be a local variable automatically

    _configs["hadoop.http.authentication.simple.anonymous.allowed"]="false"
    _configs["hadoop.http.authentication.signature.secret.file"]="/etc/security/http_secret"
    _configs["hadoop.http.authentication.type"]="kerberos"
    _configs["hadoop.http.authentication.kerberos.keytab"]="/etc/security/keytabs/spnego.service.keytab"
    _configs["hadoop.http.authentication.kerberos.principal"]="HTTP/_HOST@${_realm}"
    _configs["hadoop.http.filter.initializers"]="org.apache.hadoop.security.AuthenticationFilterInitializer"
    _configs["hadoop.http.authentication.cookie.domain"]="${_domain}"

	for _k in "${!_configs[@]}"; do
        ssh root@${_ambari_host} "/var/lib/ambari-server/resources/scripts/configs.sh -u admin -p admin -port ${_ambari_port} $_opts set $_ambari_host "$_cluster_name" core-site "$_k" \"${_configs[$_k]}\""
    done

    # If Ambari is 2.4.x or higher below works
    _info "Run the below command to restart required components"
    echo curl -u admin:admin -sk "${_http}://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_cluster_name}/requests" -H 'X-Requested-By: Ambari' --data '{"RequestInfo":{"command":"RESTART","context":"Restart all required services","operation_level":"host_component"},"Requests/resource_filters":[{"hosts_predicate":"HostRoles/stale_configs=true"}]}'
}

function f_ldap_server_install_on_host() {
    local __doc__="Install LDAP server packages on Ubuntu (need to test setup)"
    local _ldap_domain="$1"
    local _password="${2-$g_DEFAULT_PASSWORD}"

    if [ ! `which apt-get` ]; then
        _warn "No apt-get"
        return 1
    fi

    if [ -z "$_ldap_domain" ]; then
        _warn "No LDAP Domain, so using dc=example,dc=com"
        _ldap_domain="dc=example,dc=com"
    fi

    local _set_noninteractive=false
    if [ -z "$DEBIAN_FRONTEND" ]; then
        export DEBIAN_FRONTEND=noninteractive
        _set_noninteractive=true
    fi
    debconf-set-selections <<EOF
slapd slapd/internal/generated_adminpw password ${_password}
slapd slapd/password2 password ${_password}
slapd slapd/internal/adminpw password ${_password}
slapd slapd/password1 password ${_password}
slapd slapd/domain string ${_ldap_domain}
slapd shared/organization string ${_ldap_domain}
EOF
    apt-get install -y slapd ldap-utils
    if $_set_noninteractive ; then
        unset DEBIAN_FRONTEND
    fi

    # test
    ldapsearch -x -D "cn=admin,${_ldap_domain}" -w "${_password}" # -h ${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}
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
    local _md5=""
    _md5="`ssh root@$_server -t "slappasswd -s ${_password}"`" || return $?

    if [ -z "$_md5" ]; then
        _error "Couldn't generate hashed password"
        return 1
    fi

    ssh root@$_server -t 'cat "dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: '${_md5}'
" > /tmp/chrootpw.ldif && ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/chrootpw.ldif' || return $?

    ssh root@$_server -t 'cat "dn: olcDatabase={1}monitor,cn=config
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

    ssh root@$_server -t 'dn: '${_ldap_domain}'
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

function f_hadoop_ssl_setup() {
    local __doc__="Setup SSL for hadoop https://community.hortonworks.com/articles/92305/how-to-transfer-file-using-secure-webhdfs-in-distc.html"
    local _dname_extra="$1"
    local _password="$2"
    local _ambari_host="${3-$r_AMBARI_HOST}"
    local _ambari_port="${4-8080}"
    local _how_many="${5-$r_NUM_NODES}"
    local _start_from="${6-$r_NODE_START_NUM}"
    local _domain_suffix="${7-$r_DOMAIN_SUFFIX}"
    local _work_dir="${8-./}"
    local _c="`f_get_cluster_name $_ambari_host`" || return $?

    if [ ! -d "$_work_dir" ]; then
        mkdir ${_work_dir%/} || return $?
    fi
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
        openssl req -x509 -new -key ./rootCA.key -days 1095 -out ./rootCA.pem -subj "/C=AU/ST=QLD/O=Hortonworks/CN=RootCA.support.hortonworks.com" -passin "pass:$_password" || return $?
    fi

    mv -f ./$g_CLIENT_TRUSTSTORE_FILE ./$g_CLIENT_TRUSTSTORE_FILE.$$.bak &>/dev/null
    # Step3: Create a truststore file used by clients
    keytool -keystore ./$g_CLIENT_TRUSTSTORE_FILE -alias CARoot -import -file ./rootCA.pem -storepass ${g_CLIENT_TRUSTSTORE_PASSWORD} -noprompt || return $?

    local _javahome="`ssh -q root@$_ambari_host "grep java.home /etc/ambari-server/conf/ambari.properties | cut -d \"=\" -f2"`"
    local _cacerts="${_javahome%/}/jre/lib/security/cacerts"

    if ! [[ "$_how_many" =~ ^[0-9]+$ ]]; then
        local _hostnames="$_how_many"
        _info "Copying jks to $_hostnames ..."
        for i in  `echo $_hostnames | sed 's/ /\n/g'`; do
            _hadoop_ssl_per_node "$i" "$_cacerts" || return $?
        done
    else
        _info "Copying jks to all nodes..."
        for i in `_docker_seq "$_how_many" "$_start_from"`; do
            _hadoop_ssl_per_node "node${i}${_domain_suffix}" "$_cacerts" || return $?
        done
    fi

    _info "Updating Ambari configs for HDFS..."
    f_ambari_configs "core-site" "{\"hadoop.rpc.protection\":\"privacy\",\"hadoop.ssl.require.client.cert\":\"false\",\"hadoop.ssl.hostname.verifier\":\"DEFAULT\",\"hadoop.ssl.keystores.factory.class\":\"org.apache.hadoop.security.ssl.FileBasedKeyStoresFactory\",\"hadoop.ssl.server.conf\":\"ssl-server.xml\",\"hadoop.ssl.client.conf\":\"ssl-client.xml\"}" "$_ambari_host"
    f_ambari_configs "ssl-client" "{\"ssl.client.truststore.location\":\"${g_CLIENT_TRUST_LOCATION%/}/${g_CLIENT_TRUSTSTORE_FILE}\",\"ssl.client.truststore.password\":\"${g_CLIENT_TRUSTSTORE_PASSWORD}\",\"ssl.client.keystore.location\":\"${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE}\",\"ssl.client.keystore.password\":\"$_password\"}" "$_ambari_host"
    f_ambari_configs "ssl-server" "{\"ssl.server.truststore.location\":\"${g_CLIENT_TRUST_LOCATION%/}/${g_CLIENT_TRUSTSTORE_FILE}\",\"ssl.server.truststore.password\":\"${g_CLIENT_TRUSTSTORE_PASSWORD}\",\"ssl.server.keystore.location\":\"${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE}\",\"ssl.server.keystore.password\":\"$_password\",\"ssl.server.keystore.keypassword\":\"$_password\"}" "$_ambari_host"
    f_ambari_configs "hdfs-site" "{\"dfs.encrypt.data.transfer\":\"true\",\"dfs.encrypt.data.transfer.algorithm\":\"3des\",\"dfs.http.policy\":\"HTTPS_ONLY\"}" "$_ambari_host" # or HTTP_AND_HTTPS
    f_ambari_configs "mapred-site" "{\"mapreduce.jobhistory.http.policy\":\"HTTPS_ONLY\",\"mapreduce.jobhistory.webapp.https.address\":\"0.0.0.0:19888\"}" "$_ambari_host"
    f_ambari_configs "yarn-site" "{\"yarn.http.policy\":\"HTTPS_ONLY\",\"yarn.nodemanager.webapp.https.address\":\"0.0.0.0:8044\"}" "$_ambari_host"
    #f_ambari_configs "tez-site" "{\"tez.runtime.shuffle.ssl.enable\":\"true\",\"tez.runtime.shuffle.keep-alive.enabled\":\"true\"}" "$_ambari_host"

    # If Ambari is 2.4.x or higher below works
    _info "TODO: Please manually update: yarn.resourcemanager.webapp.https.address"
    _info "Run the below command to restart *ALL* required components:"
    echo curl -u admin:admin -sk "${_http}://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_c}/requests" -H 'X-Requested-By: Ambari' --data '{"RequestInfo":{"command":"RESTART","context":"Restart all required services","operation_level":"host_component"},"Requests/resource_filters":[{"hosts_predicate":"HostRoles/stale_configs=true"}]}'
}

function _hadoop_ssl_per_node() {
    local _node="$1"
    local _cacerts="$2"

    ssh -q root@${_node} "mkdir -m 750 -p ${g_SERVER_KEY_LOCATION%/}; chown root:hadoop ${g_SERVER_KEY_LOCATION%/}; mkdir -m 755 -p ${g_CLIENT_TRUST_LOCATION%/}"
    scp ./$g_CLIENT_TRUSTSTORE_FILE root@${_node}:${g_CLIENT_TRUST_LOCATION%/}/ || return $?
    # Step4: On each node, create a privatekey for the node
    ssh -q root@${_node} "mv -f ${g_SERVER_KEY_LOCATION%/}/$g_KEYSTORE_FILE ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE}.$$.bak &>/dev/null; keytool -genkey -alias ${_node} -keyalg RSA -keystore ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE} -keysize 2048 -dname \"CN=${_node}, ${_dname_extra}\" -noprompt -storepass ${_password} -keypass ${_password}"
    # Step5: On each node, create a CSR
    ssh -q root@${_node} "keytool -certreq -alias ${_node} -keystore ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE} -file ${g_SERVER_KEY_LOCATION%/}/${_node}-keystore.csr -storepass ${_password}"
    scp root@${_node}:${g_SERVER_KEY_LOCATION%/}/${_node}-keystore.csr ./ || return $?
    # Step6: Sign the CSR with the root CA
    openssl x509 -sha256 -req -in ./${_node}-keystore.csr -CA ./rootCA.pem -CAkey ./rootCA.key -CAcreateserial -out ${_node}-keystore.crt -days 730 -passin "pass:$_password" || return $?
    scp ./rootCA.pem ./${_node}-keystore.crt root@${_node}:${g_SERVER_KEY_LOCATION%/}/ || return $?
    # Step7: On each node, import root CA's cert and the signed cert
    ssh -q root@${_node} "keytool -keystore ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE} -alias rootCA -import -file ${g_SERVER_KEY_LOCATION%/}/rootCA.pem -noprompt -storepass ${_password};keytool -keystore ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE} -alias ${_node} -import -file ${g_SERVER_KEY_LOCATION%/}/${_node}-keystore.crt -noprompt -storepass ${_password}" || return $?

    if [ ! -z "$_cacerts" ]; then
        ssh -q root@${_node} "keytool -keystore $_cacerts -alias hadoopRootCA -import -file ${g_SERVER_KEY_LOCATION%/}/rootCA.pem -noprompt -storepass ${g_CLIENT_TRUSTSTORE_PASSWORD}"
    fi

    ssh -q root@${_node} "chown root:hadoop ${g_SERVER_KEY_LOCATION%/}/*;chmod 640 ${g_SERVER_KEY_LOCATION%/}/*;"
}

function _ssl_openssl_cnf_generate() {
    local __doc__="Generate openssl config file (openssl.cnf) for self-signed certificate"
    local _dname="$1"
    local _password="$2"
    local _domain_suffix="${3-.`hostname -d`}"
    local _work_dir="${4-./}"

    if [ -e "${_work_dir%/}/openssl.cnf" ]; then
        _warn "${_work_dir%/}/openssl.cnf exists. Skipping..."
        return
    fi

    if [ -z "$_domain_suffix" ]; then
        _domain_suffix=".`hostname`"
    fi
    if [ -z "$_dname" ]; then
        _dname="CN=*${_domain_suffix}, OU=Support, O=Hortonworks, L=Brisbane, ST=QLD, C=AU"
    fi
    if [ -z "$_password" ]; then
        _password=${g_DEFAULT_PASSWORD-hadoop}
    fi

    local _a
    local _tmp=""
    _split "_a" "$_dname"

    echo [ req ] > "${_work_dir%/}/openssl.cnf"
    echo input_password = $_password >> "${_work_dir%/}/openssl.cnf"
    echo output_password = $_password >> "${_work_dir%/}/openssl.cnf"
    echo distinguished_name = req_distinguished_name >> "${_work_dir%/}/openssl.cnf"
    echo req_extensions = v3_req  >> "${_work_dir%/}/openssl.cnf"
    echo prompt=no >> "${_work_dir%/}/openssl.cnf"
    echo [req_distinguished_name] >> "${_work_dir%/}/openssl.cnf"
    for (( idx=${#_a[@]}-1 ; idx>=0 ; idx-- )) ; do
        _tmp="`_trim "${_a[$idx]}"`"
        # If wildcard certficat, replace to some hostname. NOTE: nocasematch is already used
        #[[ "${_tmp}" =~ CN=\*\. ]] && _tmp="CN=internalca${_domain_suffix}"
        echo ${_tmp} >> "${_work_dir%/}/openssl.cnf"
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
    local __doc__="Setup Internal CA for generating self-signed certificate"
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

function f_ssl_self_signed_cert_with_internal_CA() {
    local __doc__="Generate self-signed certificate. Assuming f_ssl_internal_CA_setup is used."
    local _dname="$1"
    local _password="$2"
    local _common_name="${3}"
    local _ca_dir="${4-./}"
    local _work_dir="${5-./}"

    if [ -z "$_common_name" ]; then
        _common_name="`hostname -f`"
    fi
    if [ -z "$_dname" ]; then
        _dname="CN=${_common_name}, OU=Support, O=Hortonworks, L=Brisbane, ST=QLD, C=AU"
    fi
    if [ -z "$_password" ]; then
        _password=${g_DEFAULT_PASSWORD-hadoop}
    fi

    # Key store for service (same as self-signed at this moment)
    keytool -keystore "${_work_dir%/}/${g_KEYSTORE_FILE}" -alias localhost -validity 3650 -genkey -keyalg RSA -keysize 2048 -dname "$_dname" -noprompt -storepass "$_password" -keypass "$_password" || return $?
    # Generate CSR from above keystore
    keytool -keystore "${_work_dir%/}/${g_KEYSTORE_FILE}" -alias localhost -certreq -file ${_work_dir%/}/server.csr -storepass "$_password" -keypass "$_password" || return $?
    # Sign with internal CA (ca.crt, ca,key) and generate server.crt
    openssl x509 -req -CA ${_ca_dir%/}/certs/ca.crt -CAkey ${_ca_dir%/}/private/ca.key -in ${_work_dir%/}/server.csr -out ${_work_dir%/}/server.crt -days 3650 -CAcreateserial -passin "pass:$_password" || return $?
    # Import internal CA into keystore
    keytool -keystore "${_work_dir%/}/${g_KEYSTORE_FILE}" -alias CARoot -import -file ${_ca_dir%/}/certs/ca.crt -noprompt -storepass "$_password" -keypass "$_password" || return $?
    # Import internal CA signed cert (server.crt) int this keystore
    keytool -keystore "${_work_dir%/}/${g_KEYSTORE_FILE}" -alias localhost -import -file ${_work_dir%/}/server.crt -noprompt -storepass "$_password" -keypass "$_password" || return $?

    # trust store for service (eg.: hiveserver2), which contains internal CA cert only
    keytool -keystore ${_work_dir%/}/${g_TRUSTSTORE_FILE} -alias CARoot -import -file ${_ca_dir%/}/certs/ca.crt -noprompt -storepass "${g_CLIENT_TRUSTSTORE_PASSWORD}" || return $?
    # trust store for client (eg.: beeline), but at this moment, save content as above
    keytool -keystore ${_work_dir%/}/${g_CLIENT_TRUSTSTORE_FILE} -alias CARoot -import -file ${_ca_dir%/}/certs/ca.crt -noprompt -storepass "${g_CLIENT_TRUSTSTORE_PASSWORD}" || return $?
    chmod a+r ${_work_dir%/}/${g_CLIENT_TRUSTSTORE_FILE}
}

function f_ssl_distribute_jks() {
    local __doc__="Distribute JKS files generated by f_ssl_self_signed_cert_with_internal_CA to all nodes."
    local _work_dir="${1-./}"
    local _how_many="${2-$r_NUM_NODES}"
    local _start_from="${3-$r_NODE_START_NUM}"
    local _domain_suffix="${4-$r_DOMAIN_SUFFIX}"

    _info "copying jks files for $_how_many nodes from $_start_from ..."
    for i in `_docker_seq "$_how_many" "$_start_from"`; do
        ssh -q root@node$i${_domain_suffix} -t "mkdir -p ${g_SERVER_KEY_LOCATION%/};mkdir -p ${g_CLIENT_TRUST_LOCATION%/}"
        scp -q ${_work_dir%/}/*.jks root@node$i${_domain_suffix}:${g_SERVER_KEY_LOCATION%/}/
        scp -q ${_work_dir%/}/${g_CLIENT_TRUSTSTORE_FILE} root@node$i${_domain_suffix}:${g_CLIENT_TRUST_LOCATION%/}/
        ssh -q root@node$i${_domain_suffix} -t "chmod 755 $g_SERVER_KEY_LOCATION
chown root:hadoop ${g_SERVER_KEY_LOCATION%/}/*.jks
chmod 440 ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE}
chmod 440 ${g_SERVER_KEY_LOCATION%/}/${g_TRUSTSTORE_FILE}
chmod 444 ${g_CLIENT_TRUST_LOCATION%/}/${g_CLIENT_TRUSTSTORE_FILE}" || return $?
    done
}

function f_ssl_ambari_config_set_for_hadoop() {
    local __doc__="Update configs via Ambari for HDFS/YARN/MR2 (and tez). Not auomating, but asking questions"
    local _ambari_host="${1}"
    local _ambari_port="${2-8080}"
    local _ambari_ssl="${3}"
    local _cluster_name="${4-$r_CLUSTER_NAME}"
    local _opts=""
    local _http="http"

    if _isYes "$_ambari_ssl"; then
        _opts="$_opts -s"
        _http="https"
    fi
    if [ -z "$_ambari_host" ]; then
        if [ -z "$r_AMBARI_HOST" ]; then
            _ambari_host="hostname -f"
        else
            _ambari_host="$r_AMBARI_HOST"
        fi
        _info "Using $_ambari_hsot for Ambari server hostname..."
    fi

    if [ -z "$_cluster_name" ]; then
        _cluster_name="`f_get_cluster_name $_ambari_host`" || return 1
    fi

    local _type_prop=""
    declare -A _configs # NOTE: this should be a local variable automatically

    _configs["hdfs-site:dfs.namenode.https-address"]="sandbox.hortonworks.com:50470"
    _configs["yarn-site:yarn.log.server.url"]="https://sandbox.hortonworks.com:19889/jobhistory/logs"
    _configs["yarn-site:yarn.resourcemanager.webapp.https.address"]="sandbox.hortonworks.com:8090"
    _configs["ssl-server:ssl.server.keystore.location"]="${g_SERVER_KEY_LOCATION%/}/$g_KEYSTORE_FILE"
    _configs["ssl-server:ssl.server.keystore.password"]="$g_DEFAULT_PASSWORD"
    _configs["ssl-server:ssl.server.truststore.location"]="${g_SERVER_KEY_LOCATION%/}/$g_TRUSTSTORE_FILE"
    _configs["ssl-server:ssl.server.truststore.password"]="${g_CLIENT_TRUSTSTORE_PASSWORD}"
    _configs["ssl-client:ssl.client.keystore.location"]="${g_SERVER_KEY_LOCATION%/}/$g_KEYSTORE_FILE"
    _configs["ssl-client:ssl.client.keystore.password"]="$g_DEFAULT_PASSWORD"
    _configs["ssl-client:ssl.client.truststore.location"]="${g_CLIENT_TRUST_LOCATION%/}/$g_CLIENT_TRUSTSTORE_FILE"
    _configs["ssl-client:ssl.client.truststore.password"]="${g_CLIENT_TRUSTSTORE_PASSWORD}"

	for _k in "${!_configs[@]}"; do
        _split "_type_prop" "$_k" ":"
        _ask "${_type_prop[0]} ${_type_prop[1]}" "${_configs[$_k]}" "" "" "Y"
        _configs[$_k]="$__LAST_ANSWER"
    done

    _configs["core-site:hadoop.ssl.require.client.cert"]="false"    # TODO: should this be true?
    _configs["core-site:hadoop.ssl.hostname.verifier"]="DEFAULT"
    _configs["core-site:hadoop.ssl.keystores.factory.class"]="org.apache.hadoop.security.ssl.FileBasedKeyStoresFactory"
    _configs["core-site:hadoop.ssl.server.conf"]="ssl-server.xml"
    _configs["core-site:hadoop.ssl.client.conf"]="ssl-client.xml"

    _configs["hdfs-site:dfs.http.policy"]="HTTPS_ONLY"
    _configs["hdfs-site:dfs.client.https.need-auth"]="false"        # TODO: should this be true?
    _configs["hdfs-site:dfs.datanode.https.address"]="0.0.0.0:50475"

    _configs["mapred-site:mapreduce.jobhistory.http.policy"]="HTTPS_ONLY"
    _configs["mapred-site:mapreduce.jobhistory.webapp.https.address"]="0.0.0.0:19889"

    _configs["yarn-site:yarn.http.policy"]="HTTPS_ONLY"
    _configs["yarn-site:yarn.nodemanager.webapp.https.address"]="0.0.0.0:8044"

    _configs["ssl-server:ssl.server.keystore.type"]="jks"
    _configs["ssl-server:ssl.server.keystore.keypassword"]=${_configs["ssl-server:ssl.server.keystore.password"]}
    _configs["ssl-server:ssl.server.truststore.type"]="jks"

    _configs["tez-site:tez.runtime.shuffle.ssl.enable"]="true"
    _configs["tez-site:tez.runtime.shuffle.keep-alive.enabled"]="true"

	for _k in "${!_configs[@]}"; do
        _split "_type_prop" "$_k" ":"
        ssh root@${_ambari_host} "/var/lib/ambari-server/resources/scripts/configs.sh -u admin -p admin -port ${_ambari_port} $_opts set $_ambari_host "$_cluster_name" ${_type_prop[0]} ${_type_prop[1]} \"${_configs[$_k]}\"" || return $?
    done

    # If Ambari is 2.4.x or higher below works
    _info "Run the below command to restart required components"
    echo curl -u admin:admin -sk "${_http}://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_cluster_name}/requests" -H 'X-Requested-By: Ambari' --data '{"RequestInfo":{"command":"RESTART","context":"Restart all required services","operation_level":"host_component"},"Requests/resource_filters":[{"hosts_predicate":"HostRoles/stale_configs=true"}]}'
}

function f_ssl_ambari_config_disable_for_hadoop() {
    local __doc__="TODO: Update configs via Ambari for HDFS/YARN/MR2 (and tez) to disable SSH"
    local _ambari_host="${1}"
    local _ambari_port="${2-8080}"
    local _ambari_ssl="${3}"
    local _cluster_name="${4-$r_CLUSTER_NAME}"
    local _opts=""

    if _isYes "$_ambari_ssl"; then
        _opts="$_opts -s"
    fi
    if [ -z "$_ambari_host" ]; then
        if [ -z "$r_AMBARI_HOST" ]; then
            _ambari_host="hostname -f"
        else
            _ambari_host="$r_AMBARI_HOST"
        fi
        _info "Using $_ambari_hsot for Ambari server hostname..."
    fi

    if [ -z "$_cluster_name" ]; then
        _cluster_name="`f_get_cluster_name $_ambari_host`" || return 1
    fi

    local _type_prop=""
    declare -A _configs # NOTE: this should be a local variable automatically

    _configs["yarn-site:yarn.log.server.url"]="http://sandbox.hortonworks.com:19888/jobhistory/logs"

	for _k in "${!_configs[@]}"; do
        _split "_type_prop" "$_k" ":"
        _ask "${_type_prop[0]} ${_type_prop[1]}" "${_configs[$_k]}" "" "" "Y"
        _configs[$_k]="$__LAST_ANSWER"
    done

    _configs["hdfs-site:dfs.http.policy"]="HTTP_ONLY"
    _configs["mapred-site:mapreduce.jobhistory.http.policy"]="HTTP_ONLY"
    _configs["yarn-site:yarn.http.policy"]="HTTP_ONLY"
    _configs["tez-site:tez.runtime.shuffle.ssl.enable"]="false"

	for _k in "${!_configs[@]}"; do
        _split "_type_prop" "$_k" ":"
        ssh root@${_ambari_host} "/var/lib/ambari-server/resources/scripts/configs.sh -u admin -p admin -port ${_ambari_port} $_opts set $_ambari_host "$_cluster_name" ${_type_prop[0]} ${_type_prop[1]} \"${_configs[$_k]}\""
    done
}

### when source is used ########################
g_START_HDP_SH="start_hdp.sh"
# TODO: assuming g_SCRIPT_NAME contains a right filename or can be empty
if [ "$g_SCRIPT_NAME" != "$g_START_HDP_SH" ]; then
    if [ ! -s "./$g_START_HDP_SH" ]; then
        echo "start_hdp.sh is missing. Downloading..."
        curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/$g_START_HDP_SH -o "$g_CURRENT_DIR/$g_START_HDP_SH"
    fi
    source "./$g_START_HDP_SH"
fi

### main ########################
# TODO: at this moment, only when this script is directly used, do update check.
if [ "$0" = "$BASH_SOURCE" ]; then
    f_update_check
    echo "Usage:
    source $BASH_SOURCE
    f_loadResp 'path/to/your/resp/file'
    f_xxxxx # or type 'help'
    "
fi