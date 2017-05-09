#!/usr/bin/env bash
# curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_security.sh
#
# This script contains functions which help to set up Ambari/HDP security (SSL,LDAP,Kerberos etc.)
# This script requires below:
#   curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/start_hdp.sh
#
# *NOTE*: because it uses start_hdp.sh, can't use same function name in this script
#

### OS/shell settings
shopt -s nocasematch
#shopt -s nocaseglob
set -o posix
#umask 0000


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
    kadmin.local -q "add_principal -pw $_password admin/admin"
}

function f_ambari_kerberos_generate_service_config() {
    local __doc__="Output (return) service config for Ambari APIs. TODO: MIT KDC only by created by f_kdc_install_on_host"
    # https://cwiki.apache.org/confluence/display/AMBARI/Automated+Kerberizaton#AutomatedKerberizaton-EnablingKerberos
    local _realm="${1-EXAMPLE.COM}"
    local _server="${2-`hostname -i`}"
    local _kdc_type="${3}" # TODO: Not using and MIT KDC only

    local _version="version1" #TODO: not sure if always using version 1 is OK

    # service configuration
    echo '[
  {
    "Clusters": {
      "desired_config": {
        "type": "krb5-conf",
        "tag": "'$_version'",
        "properties": {
          "domains":"",
          "manage_krb5_conf": "true",
          "conf_dir":"/etc",
          "content" : "[libdefaults]\n  renew_lifetime = 7d\n  forwardable= true\n  default_realm = {{realm|upper()}}\n  ticket_lifetime = 24h\n  dns_lookup_realm = false\n  dns_lookup_kdc = false\n  #default_tgs_enctypes = {{encryption_types}}\n  #default_tkt_enctypes ={{encryption_types}}\n\n{% if domains %}\n[domain_realm]\n{% for domain in domains.split(',') %}\n  {{domain}} = {{realm|upper()}}\n{% endfor %}\n{%endif %}\n\n[logging]\n  default = FILE:/var/log/krb5kdc.log\nadmin_server = FILE:/var/log/kadmind.log\n  kdc = FILE:/var/log/krb5kdc.log\n\n[realms]\n  {{realm}} = {\n    admin_server = {{admin_server_host|default(kdc_host, True)}}\n    kdc = {{kdc_host}}\n }\n\n{# Append additional realm declarations below #}\n"
        }
      }
    }
  },
  {
    "Clusters": {
      "desired_config": {
        "type": "kerberos-env",
        "tag": "'$_version'",
        "properties": {
          "kdc_type": "mit-kdc",
          "manage_identities": "true",
          "install_packages": "true",
          "encryption_types": "aes des3-cbc-sha1 rc4 des-cbc-md5",
          "realm" : "'$_realm'",
          "kdc_host" : "'$_server'",
          "admin_server_host" : "'$_server'",
          "executable_search_paths" : "/usr/bin, /usr/kerberos/bin, /usr/sbin, /usr/lib/mit/bin, /usr/lib/mit/sbin",
          "password_length": "20",
          "password_min_lowercase_letters": "1",
          "password_min_uppercase_letters": "1",
          "password_min_digits": "1",
          "password_min_punctuation": "1",
          "password_min_whitespace": "0",
          "service_check_principal_name" : "${cluster_name}-${short_date}",
          "case_insensitive_username_rules" : "false"
        }
      }
    }
  }
]'
}

function f_ambari_kerberos_setup() {
    local __doc__="TODO: Setup Kerberos with Ambari APIs. TODO: MIT KDC only by created by f_kdc_install_on_host"
    # https://cwiki.apache.org/confluence/display/AMBARI/Automated+Kerberizaton#AutomatedKerberizaton-EnablingKerberos
    local _realm="${1-EXAMPLE.COM}"
    local _server="${2-`hostname -i`}"
    local _kdc_type="${3}" # TODO: Not using and MIT KDC only
    local _password="${4-$g_DEFAULT_PASSWORD}"
    local _how_many="${5-$r_NUM_NODES}"
    local _start_from="${6-$r_NODE_START_NUM}"
    local _ambari_host="${7-$r_AMBARI_HOST}"
    local _cluster_name="${8-$r_CLUSTER_NAME}"

    if [ -z "$_cluster_name" ]; then
        _cluster_name="`f_get_cluster_name $_ambari_host`" || return 1
    fi

    for i in `_docker_seq "$_how_many" "$_start_from"`; do
        curl -H "X-Requested-By:ambari" -u admin:admin -i -X POST -d '{"host_components" : [{"HostRoles" : {"component_name":"KERBEROS_CLIENT"}}]}' "http://$_ambari_host:8080/api/v1/clusters/$_cluster_name/hosts?Hosts/host_name=node$i${r_DOMAIN_SUFFIX}"
    done
    curl -H "X-Requested-By:ambari" -u admin:admin -i -X PUT -d '{"ServiceInfo": {"state" : "INSTALLED"}}' "http://$_ambari_host:8080/api/v1/clusters/$_cluster_name/services/KERBEROS"
    curl -H "X-Requested-By:ambari" -u admin:admin -i -X PUT -d  '{"RequestInfo":{"context":"Stop Service"},"Body":{"ServiceInfo":{"state":"INSTALLED"}}}' "http://$_ambari_host:8080/api/v1/clusters/$_cluster_name/services"

    curl -H "X-Requested-By:ambari" -u admin:admin -i -X GET http://$_ambari_host:8080/api/v1/stacks/HDP/versions/${r_HDP_STACK_VERSION}/artifacts/kerberos_descriptor
    curl -H "X-Requested-By:ambari" -u admin:admin -i -X GET http://$_ambari_host:8080/api/v1/clusters/$_cluster_name/artifacts/kerberos_descriptor

    curl -H "X-Requested-By:ambari" -u admin:admin -i -X POST -d @./payload http://$_ambari_host:8080/api/v1/clusters/$_cluster_name/artifacts/kerberos_descriptor
    curl -H "X-Requested-By:ambari" -u admin:admin -i -X PUT -d @./payload http://$_ambari_host:8080/api/v1/clusters/$_cluster_name
    echo 'Payload
{
  "session_attributes" : {
    "kerberos_admin" : {
      "principal" : "admin/admin@'$_realm'",
      "password" : "'$_password'"
    }
  },
  "Clusters": {
    "security_type" : "KERBEROS"
  }
}'
    #Start all services
    curl -H "X-Requested-By:ambari" -u admin:admin -i -X PUT -d '{"ServiceInfo": {"state" : "STARTED"}}' http://$_ambari_host:8080/api/v1/clusters/$_cluster_name/services
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
    local __doc__="TODO: setup SSSD on each node (security lab)"
    return
    # https://github.com/HortonworksUniversity/Security_Labs#install-solrcloud

    local ad_user="registersssd"
    local ad_domain="lab.hortonworks.net"
    local ad_dc="ad01.lab.hortonworks.net"
    local ad_root="dc=lab,dc=hortonworks,dc=net"
    local ad_ou="ou=HadoopNodes,${ad_root}"
    local ad_realm=${ad_domain^^}

    sudo kinit ${ad_user}

    # yum makecache fast
    yum -y install sssd oddjob-mkhomedir authconfig sssd-krb5 sssd-ad sssd-tools adcli

    sudo adcli join -v \
      --domain-controller=${ad_dc} \
      --domain-ou="${ad_ou}" \
      --login-ccache="/tmp/krb5cc_0" \
      --login-user="${ad_user}" \
      -v \
      --show-details

    sudo tee /etc/sssd/sssd.conf > /dev/null <<EOF
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

    sudo chmod 0600 /etc/sssd/sssd.conf
    sudo service sssd restart
    sudo authconfig --enablesssd --enablesssdauth --enablemkhomedir --enablelocauthorize --update

    sudo chkconfig oddjobd on
    sudo service oddjobd restart
    sudo chkconfig sssd on
    sudo service sssd restart

    # sudo kdestroy

    #detect name of cluster
    output=`curl -k -u hadoopadmin:$PASSWORD -i -H 'X-Requested-By: ambari'  https://localhost:8443/api/v1/clusters`
    cluster=`echo $output | sed -n 's/.*"cluster_name" : "\([^\"]*\)".*/\1/p'`  # TODO: may need to convert to lower

    #refresh user and group mappings
    sudo sudo -u hdfs kinit -kt /etc/security/keytabs/hdfs.headless.keytab hdfs-"${cluster}"
    sudo sudo -u hdfs hdfs dfsadmin -refreshUserToGroupsMappings

    sudo sudo -u yarn kinit -kt /etc/security/keytabs/yarn.service.keytab yarn/$(hostname -f)@LAB.HORTONWORKS.NET
    sudo sudo -u yarn yarn rmadmin -refreshUserToGroupsMappings
}

function f_ssl_openssl_cnf_generate() {
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

    # Create a private key
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
    keytool -keystore ${_work_dir%/}/${g_TRUSTSTORE_FILE} -alias ${_base_name} -import -file ${_work_dir%/}/${_base_name}.crt -noprompt -storepass "changeit" -keypass "changeit" || return $?
    # trust store for client (eg.: beeline)
    keytool -keystore ${_work_dir%/}/${g_CLIENT_TRUSTSTORE_FILE} -alias ${_base_name} -import -file ${_work_dir%/}/${_base_name}.crt -noprompt -storepass "changeit" -keypass "changeit" || return $?
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
    f_ssl_openssl_cnf_generate "$_dname" "$_password" "$_domain_suffix" "$_work_dir" || return $?
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
    keytool -keystore ${_work_dir%/}/${g_TRUSTSTORE_FILE} -alias CARoot -import -file ${_ca_dir%/}/certs/ca.crt -noprompt -storepass "changeit" -keypass "changeit" || return $?
    # trust store for client (eg.: beeline), but at this moment, save content as above
    keytool -keystore ${_work_dir%/}/${g_CLIENT_TRUSTSTORE_FILE} -alias CARoot -import -file ${_ca_dir%/}/certs/ca.crt -noprompt -storepass "changeit" -keypass "changeit" || return $?
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
        ssh root@node$i${_domain_suffix} -t "mkdir -p ${g_SERVER_KEY_LOCATION%/}"
        scp ${_work_dir%/}/*.jks root@node$i${_domain_suffix}:${g_SERVER_KEY_LOCATION%/}/
        ssh root@node$i${_domain_suffix} -t "chmod 755 $g_SERVER_KEY_LOCATION
chown root:hadoop ${g_SERVER_KEY_LOCATION%/}/*.jks
chmod 440 ${g_SERVER_KEY_LOCATION%/}/$g_KEYSTORE_FILE
chmod 440 ${g_SERVER_KEY_LOCATION%/}/$g_TRUSTSTORE_FILE
chmod 444 ${g_SERVER_KEY_LOCATION%/}/$g_CLIENT_TRUSTSTORE_FILE"
    done
}

function f_ssl_ambari_config_set_for_hadoop() {
    local __doc__="Update configs via Ambari for HDFS/YARN/MR2 (and tez). Not auomating, but asking questions"
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

    _configs["hdfs-site:dfs.namenode.https-address"]="sandbox.hortonworks.com:50470"
    _configs["yarn-site:yarn.log.server.url"]="https://sandbox.hortonworks.com:19889/jobhistory/logs"
    _configs["yarn-site:yarn.resourcemanager.webapp.https.address"]="sandbox.hortonworks.com:8090"
    _configs["ssl-server:ssl.server.keystore.location"]="${g_SERVER_KEY_LOCATION%/}/$g_KEYSTORE_FILE"
    _configs["ssl-server:ssl.server.keystore.password"]="$g_DEFAULT_PASSWORD"
    _configs["ssl-server:ssl.server.truststore.location"]="${g_SERVER_KEY_LOCATION%/}/$g_TRUSTSTORE_FILE"
    _configs["ssl-server:ssl.server.truststore.password"]="changeit"
    _configs["ssl-client:ssl.client.truststore.location"]="${g_SERVER_KEY_LOCATION%/}/$g_CLIENT_TRUSTSTORE_FILE"
    _configs["ssl-client:ssl.client.truststore.password"]="changeit"

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
        ssh root@${_ambari_host} "/var/lib/ambari-server/resources/scripts/configs.sh $_opts set $_ambari_host "$_cluster_name" ${_type_prop[0]} ${_type_prop[1]} \"${_configs[$_k]}\""
    done
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
        ssh root@${_ambari_host} "/var/lib/ambari-server/resources/scripts/configs.sh $_opts set $_ambari_host "$_cluster_name" ${_type_prop[0]} ${_type_prop[1]} \"${_configs[$_k]}\""
    done
}


### main ########################
g_START_HDP_SH="start_hdp.sh"
# TODO: assuming g_SCRIPT_NAME contains a right filename
if [ "$g_SCRIPT_NAME" != "$g_START_HDP_SH" ]; then
    if [ ! -s "$g_CURRENT_DIR/$g_START_HDP_SH" ]; then
        echo "start_hdp.sh is missing. Downloading..."
        curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/$g_START_HDP_SH -o "$g_CURRENT_DIR/$g_START_HDP_SH"
    fi
    source "$g_CURRENT_DIR/$g_START_HDP_SH"
fi

# TODO: at this moment, only when this script is directly used, do update check.
if [ "$0" = "$BASH_SOURCE" ]; then
    f_update_check
    echo "Usage:
    source $BASH_SOURCE
    f_loadResp 'path/to/your/resp/file'
    f_xxxxx # or type 'help'
    "
fi