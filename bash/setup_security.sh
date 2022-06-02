#!/usr/bin/env bash
#
# DOWNLOAD:
#   curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_security.sh
#
_DL_URL="${_DL_URL:-"https://raw.githubusercontent.com/hajimeo/samples/master"}"
type _import &>/dev/null || _import() { [ ! -s /tmp/${1}_$$ ] && curl -sf --compressed "${_DL_URL%/}/bash/$1" -o /tmp/${1}_$$; . /tmp/${1}_$$; }
_import "utils.sh"


# Global variables
g_KEYSTORE_FILE="server.keystore.jks"
g_KEYSTORE_FILE_P12="server.keystore.p12"
g_KDC_REALM="EXAMPLE.COM"   #$(hostname -s)" && g_KDC_REALM=${g_KDC_REALM^^}

g_admin="${_ADMIN_USER-"admin"}"    # not in use at this moment
g_admin_pwd="${_ADMIN_PASS-"admin123"}"
g_OTHER_DEFAULT_PWD="${g_admin_pwd}"
g_FREEIPA_DEFAULT_PWD="secret12"
g_SSL_DIR="/etc/ssl/local"

function f_ssl_setup() {
    local __doc__="Setup SSL (wildcard) certificate for f_ssl_hadoop"
    # f_ssl_setup "" ".standalone.localdomain"
    local _password="${1:-${g_OTHER_DEFAULT_PWD}}"
    local _domain_suffix="${2:-"`hostname -s`.localdomain"}"
    local _openssl_cnf="${3:-"./openssl.cnf"}"
    local _root_key="${4:-"./rootCA.key"}"

    if [ ! -s "${_openssl_cnf}" ]; then
        curl -s -f -o "${_openssl_cnf}" https://raw.githubusercontent.com/hajimeo/samples/master/misc/openssl.cnf || return $?
    echo "
[ alt_names ]
DNS.1 = ${_domain_suffix#.}
DNS.2 = *.${_domain_suffix#.}" >> ${_openssl_cnf}
    fi

    if [ -s "${_root_key}" ]; then
        _log "INFO" "${_root_key} exists. Reusing..."
    else
        # Step1: create my root CA (key) and cert (pem) TODO: -aes256 otherwise key is not protected
        openssl genrsa -passout "pass:${_password}" -out ${_root_key} 2048 || return $?
        # How to verify key: openssl rsa -in ${_root_key} -check

        # (Optional) For Ambari 2-way SSL
        [ -r ./ca.config ] || curl -O https://raw.githubusercontent.com/hajimeo/samples/master/misc/ca.config
        mkdir -p ./db/certs
        mkdir -p ./db/newcerts
        openssl req -passin pass:${_password} -new -key ${_root_key} -out ./rootCA.csr -batch
        openssl ca -out rootCA.crt -days 1095 -keyfile ${_root_key} -key ${_password} -selfsign -extensions jdk7_ca -config ./ca.config -subj "/C=AU/ST=QLD/O=Osakos/CN=RootCA.`hostname -s`.localdomain" -batch -infiles ./rootCA.csr
        openssl pkcs12 -export -in ./rootCA.crt -inkey ${_root_key} -certfile ./rootCA.crt -out ./keystore.p12 -password pass:${_password} -passin pass:${_password}
    fi

    if [ ! -s "./rootCA.pem" ]; then
        # ref: https://stackoverflow.com/questions/50788043/how-to-trust-self-signed-localhost-certificates-on-linux-chrome-and-firefox
        openssl req -x509 -new -sha256 -days 3650 -key ${_root_key} -out ./rootCA.pem \
            -config ${_openssl_cnf} -extensions v3_ca \
            -subj "/CN=RootCA.${_domain_suffix#.}" \
            -passin "pass:${_password}" || return $?
        chmod 600 ${_root_key}
        if [ -d /usr/local/share/ca-certificates ]; then
            which update-ca-certificates && cp -v -f ./rootCA.pem /usr/local/share/ca-certificates/ && update-ca-certificates
            #openssl x509 -in /etc/ssl/certs/ca-certificates.crt -noout -subject
        fi
    fi

    # Step2: create server key and certificate
    openssl genrsa -out ./wild.${_domain_suffix#.}.key 2048 || return $?
    openssl req -subj "/C=AU/ST=QLD/O=HajimeTest/CN=*.${_domain_suffix#.}" -extensions v3_req -sha256 -new -key ./wild.${_domain_suffix#.}.key -out ./wild.${_domain_suffix#.}.csr -config ${_openssl_cnf} || return $?
    openssl x509 -req -extensions v3_req -days 3650 -sha256 -in ./wild.${_domain_suffix#.}.csr -CA ./rootCA.pem -CAkey ${_root_key} -CAcreateserial -out ./wild.${_domain_suffix#.}.crt -extfile ${_openssl_cnf} -passin "pass:$_password"

    # Step3: Create .p12 file, then .jks file
    openssl pkcs12 -export -in ./wild.${_domain_suffix#.}.crt -inkey ./wild.${_domain_suffix#.}.key -certfile ./wild.${_domain_suffix#.}.crt -out ./wild.${_domain_suffix#.}.p12 -passin "pass:${_password}" -passout "pass:${_password}" || return $?
    [ -s ./wild.${_domain_suffix#.}.jks ] && mv -v -f ./wild.${_domain_suffix#.}.jks ./wild.${_domain_suffix#.}.jks.$$.bak
    keytool -importkeystore -srckeystore ./wild.${_domain_suffix#.}.p12 -srcstoretype pkcs12 -srcstorepass ${_password} -destkeystore ./wild.${_domain_suffix#.}.jks -deststoretype JKS -deststorepass ${_password} || return $?
}

function f_kdc_install() {
    local __doc__="Install KDC server packages on Ubuntu (may take long time)"
    local _realm="${1:-"${g_KDC_REALM}"}"
    local _password="${2:-"${g_OTHER_DEFAULT_PWD}"}"
    local _server="${3:-$(hostname -I | awk '{print $1}')}"
    local _ldap_password="${4-"${g_OTHER_DEFAULT_PWD}"}"

    if [ -z "${_realm}" ]; then
        _realm="$(hostname -s)" && _realm="${_realm^^}"
        _log "INFO" "Using ${_realm} for realm"
    fi
    if [ -z "${_server}" ]; then
        _log "ERROR" "No server IP/name for KDC"
        return 1
    fi
    if [ ! "$(which apt-get)" ]; then
        _log "WARN" "No apt-get"
        return 1
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y krb5-kdc krb5-admin-server libapache2-mod-auth-kerb || return $?

    if [ -z "${_ldap_password}" ]; then
        if [ -s /etc/krb5kdc/kdc.conf ] && [ -s /var/lib/krb5kdc/principal_${_realm} ]; then
            if grep -qE '^\s*'${_realm}'\b' /etc/krb5kdc/kdc.conf; then
                _log "INFO" "Realm: ${_realm} may already exit in /etc/krb5kdc/kdc.conf. Not try creating..."
                return 0
            fi
        fi

        cat << EOF >/tmp/f_kdc_install_on_host_kdc_$$.tmp
    ${_realm} = {
        database_name = /var/lib/krb5kdc/principal_${_realm}
        admin_keytab = FILE:/etc/krb5kdc/kadm5_${_realm}.keytab
        #acl_file = /etc/krb5kdc/kadm5_${_realm}.acl
        key_stash_file = /etc/krb5kdc/stash_${_realm}
        kdc_ports = 750,88
        max_life = 10h 0m 0s
        max_renewable_life = 7d 0h 0m 0s
        master_key_type = des3-hmac-sha1
        supported_enctypes = aes256-cts:normal arcfour-hmac:normal des3-hmac-sha1:normal des-cbc-crc:normal des:normal des:v4 des:norealm des:onlyrealm des:afs3
        default_principal_flags = +preauth
    }
EOF
        sed -i "/\[realms\]/r /tmp/f_kdc_install_on_host_kdc_$$.tmp" /etc/krb5kdc/kdc.conf
    fi

    cp -p /etc/krb5.conf /etc/krb5.conf.$(date +"%Y%m%d%H%M%S") || return $?

    local _realm_extra=""
    if [ -n "${_ldap_password}" ] && f_ldap_config_for_kdc "${_ldap_password}"; then
        _realm_extra="database_module = openldap_ldapconf"
    else
        _log "WARN" "Not using local LDAP as backend."
        _ldap_password=""
    fi

    cat << EOF > /etc/krb5.conf
[libdefaults]
  default_realm = ${_realm}
  dns_lookup_realm = false
  dns_lookup_kdc = false

[realms]
  ${_realm} = {
    kdc = ${_server}
    admin_server = ${_server}
    default_domain = ${_realm,,}
    ${_realm_extra}
  }
EOF

    if [ -z "${_ldap_password}" ]; then
        kdb5_util create -r ${_realm} -s -P ${_password} || return $? # or krb5_newrealm
    else
        local _dcs="dc=$(echo "${_realm,,}" | sed 's/\./,dc=/g')"
        if [ -s /etc/krb5.conf ] && ! grep -qw 'ldap_kerberos_container_dn' /etc/krb5.conf; then
            cat << EOF >> /etc/krb5.conf
[dbdefaults]
  ldap_kerberos_container_dn = cn=krbContainer,${_dcs}

[dbmodules]
  openldap_ldapconf = {
    db_library = kldap
    disable_last_success = true
    disable_lockout  = true
    ldap_kdc_dn = "uid=kdc-service,${_dcs}"
    ldap_kadmind_dn = "uid=kadmin-service,${_dcs}"
    ldap_service_password_file = /etc/krb5kdc/ldap_service.keyfile
    ldap_servers = ldapi:///
    ldap_conns_per_server = 5
  }
EOF
        fi

        kdb5_ldap_util -D cn=admin,${_dcs} -w "${_ldap_password}" create -subtrees ${_dcs} -r ${_realm} -s -H ldapi:/// -P "${_password}" || return $?
        _log "NOTE" "stashsrvpw may ask the passwords for service accounts..."
        echo -e "${_ldap_password}\n${_ldap_password}" | kdb5_ldap_util -D cn=admin,${_dcs} -w "${_ldap_password}" stashsrvpw -f /etc/krb5kdc/ldap_service.keyfile uid=kdc-service,${_dcs}
        echo -e "${_ldap_password}\n${_ldap_password}" | kdb5_ldap_util -D cn=admin,${_dcs} -w "${_ldap_password}" stashsrvpw -f /etc/krb5kdc/ldap_service.keyfile uid=kadmin-service,${_dcs}
    fi

    mv /etc/krb5kdc/kadm5.acl /etc/krb5kdc/.orig &>/dev/null
    echo '*/admin *' >/etc/krb5kdc/kadm5.acl
    service krb5-kdc restart && service krb5-admin-server restart
    sleep 3
    kadmin.local -r ${_realm} -q "add_principal -pw ${_password} admin/admin@${_realm}"
    kadmin.local -r ${_realm} -q "add_principal -pw ${_password} kadmin/${_server}@${_realm}"   # AMBARI-24869
    kadmin.local -r ${_realm} -q "add_principal -pw ${_password} kadmin/admin@${_realm}" &>/dev/null # this should exist already
    _log "INFO" "Testing ..."
    kadmin -p admin/admin@${_realm} -w "${_password}" -q "get_principal admin/admin@${_realm}"
}

function f_ldap_config_for_kdc() {
    local __doc__="(Re)configure *local* ldap server(slapd) for KDC server"
    # @see: https://ubuntu.com/server/docs/service-kerberos-with-openldap-backend
    #       https://github.com/nugaon/docker-kerberos-with-ldap#bind-ldap-user-to-kerberos-db
    local _ldap_password="${1-${g_OTHER_DEFAULT_PWD}}"
    local _realm="${2:-"${g_KDC_REALM}"}"
    local _dcs="dc=$(echo "${_realm,,}" | sed 's/\./,dc=/g')"

    # This 'excludes' file prevent to install docs
    if [ -s /etc/dpkg/dpkg.cfg.d/excludes ]; then
        mv -v /etc/dpkg/dpkg.cfg.d/excludes /var/tmp/excludes
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y krb5-kdc-ldap schema2ldif || return $?
    if [ ! -f /etc/dpkg/dpkg.cfg.d/excludes ] && [ -s /var/tmp/excludes ]; then
        mv -v /var/tmp/excludes /etc/dpkg/dpkg.cfg.d/excludes
    fi
    cp -v /usr/share/doc/krb5-kdc-ldap/kerberos.schema.gz /etc/ldap/schema/ || return $?
    gunzip /etc/ldap/schema/kerberos.schema.gz || return $?
    ldap-schema-manager -i kerberos.schema || return $?
    ldapmodify -Q -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
add: olcDbIndex
olcDbIndex: krbPrincipalName eq,pres,sub
EOF
    #ldapdelete -x -D cn=admin,dc=example,dc=com -w "${_ldap_password}" uid=kdc-service,dc=example,dc=com
    #ldapdelete -x -D cn=admin,dc=example,dc=com -w "${_ldap_password}" uid=kadmin-service,dc=example,dc=com
    # NOTE: this is not recommended way, and only for demo
    ldapadd -x -D cn=admin,${_dcs} -w "${_ldap_password}" <<EOF
dn: uid=kdc-service,${_dcs}
uid: kdc-service
objectClass: account
objectClass: simpleSecurityObject
userPassword: ${_ldap_password}
description: Account used for the Kerberos KDC

dn: uid=kadmin-service,${_dcs}
uid: kadmin-service
objectClass: account
objectClass: simpleSecurityObject
userPassword: ${_ldap_password}
description: Account used for the Kerberos Admin server
EOF
    # Next step is confusing, so taking a backup
    slapcat -b cn=config -l /tmp/ldap-config_before.ldif || return $?
    if ! grep -qF 'olcAccess: {2}to attrs=krbPrincipalKey' /tmp/ldap-config_before.ldif; then
        ldapmodify -Q -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
add: olcAccess
olcAccess: {2}to attrs=krbPrincipalKey
  by anonymous auth
  by dn.exact="uid=kdc-service,${_dcs}" read
  by dn.exact="uid=kadmin-service,${_dcs}" write
  by self write
  by * none
-
add: olcAccess
olcAccess: {3}to dn.subtree="cn=krbContainer,${_dcs}"
  by dn.exact="uid=kdc-service,${_dcs}" read
  by dn.exact="uid=kadmin-service,${_dcs}" write
  by * none
EOF
        slapcat -b cn=config -l /tmp/ldap-config_after.ldif || return $?
        diff -wu /tmp/ldap-config_before.ldif /tmp/ldap-config_after.ldif
        _log "INFO" "Please review above diff. then restart slapd."; sleep 3
    fi
}

function f_kerberos_crossrealm_setup() {
    local __doc__="TODO: Setup cross realm (MIT only). Requires Password-less SSH login"
    local _remote_kdc="$1"
    local _remote_ambari="$2"

    local _local_kdc="`hostname -i`"
    if [[ "$_local_kdc" =~ ^"127" ]]; then
        _local_kdc="`ifconfig ens3 | grep -oP 'inet addr:\d+\.\d+\.\d+\.\d+' | cut -d":" -f2`"
        [ -z "$_local_kdc" ] && return 11
        _log "WARN" "hostname -i doesn't work so that using IP of 'ens3' $_local_kdc"
    fi

    nc -z ${_remote_kdc} 88 || return 12
    nc -z ${_remote_ambari} 8080 || return 13

    local _local_realm="`sed -n -e 's/^ *default_realm *= *\b\(.\+\)\b/\1/p' /etc/krb5.conf`"
    [ -z  "${_local_realm}" ] && return 21
    local _remote_realm="`ssh -q root@${_remote_kdc} sed -n -e 's/^ *default_realm *= *\b\(.\+\)\b/\1/p' /etc/krb5.conf`"
    [ -z  "${_remote_realm}" ] && return 22

    # TODO: expecting run this function from KDC server
    kadmin.local -q "add_principal -pw $_password krbtgt/${_remote_realm}@${_local_realm}" || return 31
    ssh -q root@${_remote_kdc} kadmin.local -q "add_principal -pw $_password krbtgt/${_local_realm}@${_remote_realm}" || return 32
    # - set hadoop.security.auth_to_local for both clusters
    # - set [capaths] in both clusters
    # - set dfs.namenode.kerberos.principal.pattern = *
}

function f_ldap_server_install() {
    local __doc__="Install LDAP server packages on Ubuntu (need to test setup)"
    local _shared_domain="$1"
    local _password="${2-${g_OTHER_DEFAULT_PWD}}"

    if [ ! `which apt-get` ]; then
        _log "WARN" "No apt-get"
        return 1
    fi

    [ -z "$_shared_domain" ] && _shared_domain="example.com"
    local _dcs="dc=$(echo "${_shared_domain}" | sed 's/\./,dc=/g')"

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

    DEBIAN_FRONTEND=noninteractive apt-get install -y slapd ldap-utils || return $?
    service slapd start
    DEBIAN_FRONTEND=noninteractive apt-get install -y phpldapadmin
    service apache2 start

    if [ "$_shared_domain" == "example.com" ]; then
        curl -sf -L --compressed https://raw.githubusercontent.com/hajimeo/samples/master/misc/example.ldif -o /tmp/example.ldif || return $?
        ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/example.ldif
    fi

    # setting up ldaps (SSL)    @see: https://ubuntu.com/server/docs/service-ldap-with-tls
    if [ ! -d "${g_SSL_DIR%/}" ]; then
        mkdir -v "${g_SSL_DIR%/}" || return $?
    fi
    curl -o ${g_SSL_DIR%/}/slapd.key -sf -L https://raw.githubusercontent.com/hajimeo/samples/master/misc/standalone.localdomain.key
    curl -o ${g_SSL_DIR%/}/slapd.crt -sf -L https://raw.githubusercontent.com/hajimeo/samples/master/misc/standalone.localdomain.crt
    chown -v openldap:openldap ${g_SSL_DIR%/}/slapd.* || return $?
    chmod -v 400 ${g_SSL_DIR%/}/slapd.* || return $?
    _trust_ca || return $?
    cat << EOF > /tmp/certinfo.ldif
dn: cn=config
add: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/ssl/certs/rootCA_standalone.pem
-
add: olcTLSCertificateFile
olcTLSCertificateFile: ${g_SSL_DIR%/}/slapd.crt
-
add: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: ${g_SSL_DIR%/}/slapd.key
EOF
    ldapadd -x -D cn=admin,${_dcs} -w "${_password}" -f /tmp/example.ldif
    #ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/certinfo.ldif || return $?
    # NOTE: as per doc, ldaps is deprecated but enabling for now...
    _upsert "/etc/default/slapd" "SLAPD_SERVICES" '"ldap:/// ldapi:/// ldaps:///"'
    service slapd restart || return $?
    # test
    echo | openssl s_client -connect localhost:636 -showcerts | head
}

function f_ldap_client_install() {
    local __doc__="TODO: CentOS6 only: Install LDAP client packages *for sssd* (security lab)"
    # somehow having difficulty to install openldap in docker so using dockerhost1
    local _ldap_server="${1}"
    local _ldap_basedn="${2}"

    if [ -z "$_ldap_server" ]; then
        _log "WARN" "No LDAP server hostname. Using $(hostname -f)"; sleep 5
        _ldap_server="$(hostname -f)"
    fi
    if [ -z "$_ldap_basedn" ]; then
        _log "WARN" "No LDAP Base DN, so using dc=example,dc=com"
        _ldap_basedn="dc=example,dc=com"
    fi

    yum -y erase nscd
    yum -y install sssd sssd-client sssd-ldap openldap-clients || return $?
    authconfig --enablesssd --enablesssdauth --enablelocauthorize --enableldap --enableldapauth --disableldaptls --ldapserver=ldap://${_ldap_server} --ldapbasedn=${_ldap_basedn} --update || return $?
    # test
    #authconfig --test
    # getent passwd admin
}

function f_freeipa_install() {
    local __doc__="Install freeIPA (may better create a dedicated container)"
    #p_node_create node99${r_DOMAIN_SUFFIX} 99 # Intentionally no Ambari install
    local _ipa_server_fqdn="${1:-"$(hostname -f)"}" # Used to replace the certificate
    local _password="${2:-$g_FREEIPA_DEFAULT_PWD}"  # password need to be 8 or longer
    local _force="${3}"

    #The GPG keys listed for the "MySQL Connectors Community" repository are already installed but they are not correct for this package.
    rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022
    # Used ports https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/linux_domain_identity_authentication_and_policy_guide/installing-ipa
    yum update -y || return $?
    yum install freeipa-server -y || return $?

    # seems FreeIPA needs ipv6 for loopback
    grep -q "^net.ipv6.conf.all.disable_ipv6" /etc/sysctl.conf || (echo "net.ipv6.conf.all.disable_ipv6 = 0" >> /etc/sysctl.conf;sysctl -w net.ipv6.conf.all.disable_ipv6=0);grep -q "^net.ipv6.conf.lo.disable_ipv6" /etc/sysctl.conf || (echo "net.ipv6.conf.lo.disable_ipv6 = 0" >> /etc/sysctl.conf;sysctl -w net.ipv6.conf.lo.disable_ipv6=0)
    sysctl -a 2>/dev/null | grep "^net.ipv6.conf.lo.disable_ipv6 = 1" && return $?
    # https://bugzilla.redhat.com/show_bug.cgi?id=1677027
    sysctl -w fs.protected_regular=0

    #_log "WARN" " YOU MIGHT WANT TO RESTART OS/CONTAINTER NOW (sleep 10)  "
    #sleep 10

    # TODO: got D-bus error when freeIPA calls systemctl (service dbus restart makes install works but makes docker slow/unstable)
    # May need to add -v /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket in docker run ?
    [[ "${_force}" =~ ^(y|Y) ]] && ipa-server-install --uninstall --ignore-topology-disconnect --ignore-last-of-role
    local _domain="${_ipa_server_fqdn#*.}"
    if [ -z "${_domain}" ]; then
        _log "ERROR" "_ipa_server_fqdn may not be FQDN"
        return 1
    fi
    ipa-server-install -a "${_password}" --hostname="${_ipa_server_fqdn}" -r "${_domain^^}" -p "${_password}" -n "${_domain}" -U
    if [ $? -ne 0 ]; then
        _log "ERROR" "ipa-server-install failed. You might want to run 'service dbus restart' and/or restart the OS (container), and uninstall then re-install"
        return 1
    fi
    [ ! -s /etc/rc.lcoal ] && echo -e "#!/bin/bash\nexit 0" > /etc/rc.local
    grep -q "ipactl start" /etc/rc.local || echo -e "\n`which ipactl` start" >> /etc/rc.local

    if [ "${_domain}" == "standalone.localdomain" ]; then
        _log "INFO" "Updating SSL certificate for standalone.localdomain ..."
        f_freeipa_cert_update "${_ipa_server_fqdn}"

        _log "INFO" "Setting up SAML ..."
        f_simplesamlphp "${_ipa_server_fqdn}:389"
    fi

    #ipactl status
    #ipa ping
    #ipa config-show --all
    _log "WARN" "TODO: Update Password global_policy Max lifetime (days) to unlimited or 3650 days"
    # TODO: create dummy users and groups
    #echo -n "'${_adm_pwd}'" | kinit admin
    #ipa user-add ffffff --random --first=user --last=test --password-expiration=$(date -u +%Y%m%d000000Z -d "89 days")
    #LDAPTLS_REQCERT=never ldappasswd -Y GSSAPI -U 'admin@STANDALONE.LOCALDOMAIN' -s 'ffffff' uid=ffffff,cn=users,cn=accounts,dc=standalone,dc=localdomain -H ldap://$(hostname -f)
    # This will anyway ask to change the password at next login...
}

function f_freeipa_client_install() {
    local __doc__="Install freeIPA client on one node"
    # ref: https://www.digitalocean.com/community/tutorials/how-to-configure-a-freeipa-client-on-centos-7
    local _client_host="$1"
    local _ipa_server_fqdn="$2"
    local _adm_pwd="${3:-$g_FREEIPA_DEFAULT_PWD}"    # password need to be 8 or longer
    local _force_reinstall="${4}"

    local _domain="${_ipa_server_fqdn#*.}"
    local _uninstall=""
    [[ "${_force_reinstall}" =~ y|Y ]] && _uninstall="service dbus restart; ipa-client-install --unattended --uninstall"

    # Avoid installing client on IPA server (best effort)
    [ "`hostname -f`" = "'${_ipa_server_fqdn}'" ] && exit
    echo -n "'${_adm_pwd}'" | kinit admin
    yum install ipa-client -y
    ${_uninstall}
    ipa-client-install --unattended --hostname=`hostname -f` --server=${_ipa_server_fqdn} --domain=${_domain} --realm=${_domain^^} -p admin -w ${_adm_pwd} --mkhomedir --force-join
}

function f_freeipa_cert_update() {
    local __doc__="Update/renew certificate (TODO: haven't tested)"
    # @see https://www.powerupcloud.com/freeipa-server-and-client-installation-on-ubuntu-16-04-part-i/
    local _ipa_server_fqdn="${1}"
    local _p12_file="${2}"
    local _full_ca="${3}"   # If intermediate is used, concatenate first
    local _p12_pass="${4:-${g_OTHER_DEFAULT_PWD}}"
    local _adm_pwd="${5:-$g_FREEIPA_DEFAULT_PWD}"
    # example of generating p12.
    #openssl pkcs12 -export -chain -CAfile rootCA_standalone.crt -in standalone.localdomain.crt -inkey standalone.localdomain.key -name standalone.localdomain -out standalone.localdomain.p12 -passout pass:${_p12_pass}

    if [ -z "${_p12_file}" ]; then
        if [ ! -s /var/tmp/share/cert/standalone.localdomain.p12 ]; then
            curl -f -o /var/tmp/share/cert/standalone.localdomain.p12 -L "https://github.com/hajimeo/samples/raw/master/misc/standalone.localdomain.p12" || return $?
        fi
        _p12_file="/var/tmp/share/cert/standalone.localdomain.p12"
        _p12_pass="password"
        if [ -z ${_full_ca} ]; then
            if [ ! -s /var/tmp/share/cert/rootCA_standalone.crt ]; then
                curl -f -o /var/tmp/share/cert/rootCA_standalone.crt -L "https://github.com/hajimeo/samples/raw/master/misc/rootCA_standalone.crt" || return $?
            fi
            _full_ca=/var/tmp/share/cert/rootCA_standalone.crt
        fi
    fi
    if [ -s ${_full_ca} ]; then
        ipa-cacert-manage install ${_full_ca} && echo -n "${_adm_pwd}" | kinit admin && ipa-certupdate #|| return $?
        _log "INFO" "TODO: Run 'ipa-certupdate' on each node."
    fi

    # Should update only web server cert (no -d)?
    ipa-server-certinstall -v -w -d "${_p12_file}" --pin="${_p12_pass}" -p "${_adm_pwd}" && ipactl restart
}

function f_simplesamlphp() {
    local __doc__="No installation, but setup Simple SAML PHP"
    local _local_ldap="${1-"localhost:389"}"    # node-freeipa.standalone.localdomain:389
    local _base_dc="${2:-"dc=standalone,dc=localdomain"}"
    local _admin="${3:-"${g_admin}"}"
    local _admin_pwd="${3:-"${g_FREEIPA_DEFAULT_PWD}"}"
    local _version="${3:-"1.19.1"}" # 1.19.5 causes https://github.com/simplesamlphp/simplesamlphp/issues/1592

    local _apache2="apache2"
    local _conf="/etc/apache2/sites-enabled/saml.conf"
    local _server_name="$(hostname -f)"
    local _port="8444"
    local _saml_dir="/var/www/simplesaml"

    # https://simplesamlphp.org/docs/stable/simplesamlphp-install#section_1
    # Requires PHP 7.1.0 or higher. Ubuntu 20.04 is OK but not CentOS 7
    # TODO: correctly detect OS type and version
    if type apt-get &>/dev/null; then
        # https://www.digitalocean.com/community/tutorials/how-to-install-and-configure-simplesamlphp-for-saml-authentication-on-ubuntu-18-04
        apt-get install -y php-xml php-mbstring php-curl php-memcache php-ldap memcached || return $?
    else
        # https://computingforgeeks.com/how-to-install-php-on-centos-fedora/
        # Below two may fail with "does not update installed package" so not checking return code.
        yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
        yum install -y http://rpms.remirepo.net/enterprise/remi-release-7.rpm

        yum install -y httpd mod_ssl && \
        yum install -y epel-release yum-utils && \
        yum-config-manager --disable remi-php54 && yum-config-manager --enable remi-php73 || return $?
        yum install -y php php-mbstring php-xml php-curl php-memcache php-ldap || return $?
        _apache2="httpd"
        _conf="/etc/httpd/conf.d/saml.conf"
    fi

    if [ -s "${_conf}" ]; then
        #[ ! -s ${_conf}.orig ] && mv ${_conf} ${_conf}.orig;
        _log "WARN" "${_conf} exists, so not re-creating conf file and not re-configuring ${_apache2}."
    else
        if [ ! -d "${g_SSL_DIR%/}" ]; then
            mkdir -v "${g_SSL_DIR%/}" || return $?
        fi
        curl -o ${g_SSL_DIR%/}/saml.crt -L https://raw.githubusercontent.com/hajimeo/samples/master/misc/standalone.localdomain.crt || return $?
        curl -o ${g_SSL_DIR%/}/saml.key -L https://raw.githubusercontent.com/hajimeo/samples/master/misc/standalone.localdomain.key || return $?
        chmod 600 ${g_SSL_DIR%/}/saml.key || return $?
        cat << EOF > ${_conf}
Listen ${_port} https
<VirtualHost _default_:${_port}>
  SetEnv SIMPLESAMLPHP_CONFIG_DIR ${_saml_dir%/}/config
  DocumentRoot ${_saml_dir%/}/www
  Alias /simplesaml ${_saml_dir%/}/www
  ServerName ${_server_name}:${_port}
  <Directory ${_saml_dir%/}/www>
    Require all granted
  </Directory>
  ErrorLog ${_saml_dir%/}/log/saml_error_log
  TransferLog ${_saml_dir%/}/log/saml_access_log
  CustomLog ${_saml_dir%/}/log/saml_request_log "%t %h %{SSL_PROTOCOL}x %{SSL_CIPHER}x \"%r\" %b"
  SSLCertificateFile ${g_SSL_DIR%/}/saml.crt
  SSLCertificateKeyFile ${g_SSL_DIR%/}/saml.key
</VirtualHost>
EOF
        systemctl enable ${_apache2} && systemctl restart ${_apache2} || return $?
    fi
    if [ -s "${_saml_dir%/}/config/config.php" ]; then
        _log "WARN" "${_saml_dir%/}/config/config.php exists. Not downloading Simple SAML PHP and not re-configuring config.php."
    else
        local _tmpdir="$(mktemp -d)"
        cd "${_tmpdir}" || return $?
        curl -O -J -L https://github.com/simplesamlphp/simplesamlphp/releases/download/v${_version}/simplesamlphp-${_version}.tar.gz || return $?
        tar -xvf "$(ls -1t simplesamlphp-*.tar.gz | head -n1)" || return $?
        mv "$(find ./* -maxdepth 0 -type d)" ${_saml_dir%/} || return $?
        cd -

        _log "INFO" "Updating ${_saml_dir%/}/config/config.php ..."
        if [ ! -f ${_saml_dir%/}/config/config.php.orig ]; then
            cp -p ${_saml_dir%/}/config/config.php ${_saml_dir%/}/config/config.php.orig || return $?
        fi
        sed -i.bak "s/'defaultsecretsalt'/'60a37e26dc9b5cf7321b'/;s/'123'/'admin123'/;s/'enable.saml20-idp' => false/'enable.saml20-idp' => true/" ${_saml_dir%/}/config/config.php
        if [ -n "${_local_ldap}" ]; then
            _log "INFO" "Updating ${_saml_dir%/}/config/authsources.php ..."
            if [ ! -f "${_saml_dir%/}/config/authsources.php.orig" ]; then
                cp -p "${_saml_dir%/}/config/authsources.php" "${_saml_dir%/}/config/authsources.php.orig" || return $?
            fi
            cat ${_saml_dir%/}/config/authsources.php | grep -v '^];$' > /tmp/authsources.php
            echo "'local_ldap'=>['ldap:LDAP','hostname'=>'${_local_ldap}','enable_tls'=>FALSE,'attributes'=>NULL,'dnpattern'=>'uid=%username%,cn=users,cn=accounts,${_base_dc}','search.enable'=>FALSE,'search.base'=>'cn=users,cn=accounts,${_base_dc}','search.scope'=>'subtree','search.attributes'=>array('uid', 'gecos', 'krbPrincipalName', 'mail'),'search.filter'=>'(&(objectClass=person)(uid=*))','search.username'=>'${_admin},cn=users,cn=accounts,${_base_dc}','search.password'=>'${_admin_pwd}']," >> /tmp/authsources.php
            echo "];" >> /tmp/authsources.php
            mv -v -f /tmp/authsources.php ${_saml_dir%/}/config/authsources.php
        fi
        _log "INFO" "Updating ${_saml_dir%/}/metadata/saml20-idp-hosted.php ..."
        sed -i.bak -r "s/\s+'auth' => .+$/    'auth' => 'local_ldap',\n    'NameIDFormat'               => 'urn:oasis:names:tc:SAML:1.1:nameid-format:persistent',\n    'simplesaml.nameidattribute' => 'uid',\n    'SingleSignOnServiceBinding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST',\n    'SingleLogoutServiceBinding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST',/" ${_saml_dir%/}/metadata/saml20-idp-hosted.php
    fi
    _log "INFO" "Done. Insert SP metadata into"
    _log "TODO" "May need to remove /etc/httpd/conf.d/ssl.conf"
}

function f_sssd_setup() {
    local __doc__="setup SSSD on each node (security lab) If /etc/sssd/sssd.conf exists, skip. Kerberos is required."
    # https://github.com/HortonworksUniversity/Security_Labs#install-solrcloud
    # f_sssd_setup administrator '******' 'hdp.localdomain' 'adhost.hdp.localdomain' 'dc=hdp,dc=localdomain' '${_password}' 'sandbox-hdp.hortonworks.com' 'sandbox-hdp.hortonworks.com'
    local ad_user="$1"    #registersssd
    local ad_pwd="$2"
    local ad_domain="$3"  #lab.hortonworks.net
    local ad_dc="$4"      #ad01.lab.hortonworks.net
    local ad_root="$5"    #dc=lab,dc=hortonworks,dc=net
    local ad_ou_name="$6" #HadoopNodes
    local _target_host="$7"
    local _ambari_host="${8-$r_AMBARI_HOST}"

    local ad_ou="ou=${ad_ou_name},${ad_root}"
    local ad_realm=${ad_domain^^}

    # TODO: CentOS7 causes "The name com.redhat.oddjob_mkhomedir was not provided by any .service files" if oddjob and oddjob-mkhomedir is installed due to some messagebus issue
    local _cmd="which adcli &>/dev/null || ( yum makecache fast && yum -y install epel-release; yum -y install sssd authconfig sssd-krb5 sssd-ad sssd-tools adcli oddjob-mkhomedir; yum erase -y nscd )"
    if [ -z "$_target_host" ]; then
        f_run_cmd_on_nodes "$_cmd" || return $?
    else
        ssh -q root@${_target_host} -t "$_cmd" || return $?
    fi

    # TODO: bellow requires Kerberos has been set up, also only for CentOS6 (CentOS7 uses realm command)
    local _krbcc="/tmp/krb5cc_sssd"
    _cmd="echo -e '${ad_pwd}' | kinit -c ${_krbcc} ${ad_user}"
    if [ -z "$_target_host" ]; then
        f_run_cmd_on_nodes "$_cmd" || return $?
    else
        ssh -q root@${_target_host} -t "$_cmd" || return $?
    fi

    _cmd="adcli join -v --domain-controller=${ad_dc} --domain-ou=\"${ad_ou}\" --login-ccache=\"${_krbcc}\" --login-user=\"${ad_user}\" -v --show-details"
    if [ -z "$_target_host" ]; then
        f_run_cmd_on_nodes "$_cmd" || return $?
    else
        ssh -q root@${_target_host} -t "$_cmd" || return $?
    fi

    _cmd="tee /etc/sssd/sssd.conf > /dev/null <<EOF
[sssd]
## master & data nodes only require nss. Edge nodes require pam.
services = nss, pam, ssh, autofs, pac
config_file_version = 2
domains = ${ad_realm}
override_space = _

[domain/${ad_realm}]
id_provider = ad
ad_server = ${ad_dc}
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

systemctl enable sssd &>/dev/null
service sssd restart
service messagebus restart &>/dev/null
systemctl enable oddjobd &>/dev/null
service oddjobd restart &>/dev/null

authconfig --enablesssd --enablesssdauth --enablemkhomedir --enablelocauthorize --update
kdestroy -c ${_krbcc}"

    # To test: id yourusername && groups yourusername
    if [ -z "$_target_host" ]; then
        f_run_cmd_on_nodes "[ -s /etc/sssd/sssd.conf ] || ( $_cmd )"
    else
        ssh -q root@${_target_host} -t "[ -s /etc/sssd/sssd.conf ] || ( $_cmd )"
    fi

    #refresh user and group mappings if ambari host is given
    if [ -n "${_ambari_host}" ]; then
        local _c="`f_get_cluster_name ${_ambari_host}`" || return $?
        local _hdfs_client_node="`_ambari_query_sql "select h.host_name from hostcomponentstate hcs join hosts h on hcs.host_id=h.host_id where component_name='HDFS_CLIENT' and current_state='INSTALLED' limit 1" ${_ambari_host}`"
        if [ -z "$_hdfs_client_node" ]; then
            _log "WARN" "No hdfs client node found to execute 'hdfs dfsadmin -refreshUserToGroupsMappings'"
            return 1
        fi
        ssh -q root@$_hdfs_client_node -t "sudo -u hdfs bash -c \"kinit -kt /etc/security/keytabs/hdfs.headless.keytab hdfs-${_c}; hdfs dfsadmin -refreshUserToGroupsMappings\""

        local _yarn_rm_node="`_ambari_query_sql "select h.host_name from hostcomponentstate hcs join hosts h on hcs.host_id=h.host_id where component_name='RESOURCEMANAGER' and current_state='STARTED' limit 1" ${_ambari_host}`"
        if [ -z "$_yarn_rm_node" ]; then
            _log "ERROR" "No yarn client node found to execute 'yarn rmadmin -refreshUserToGroupsMappings'"
            return 1
        fi
        ssh -q root@$_yarn_rm_node -t "sudo -u yarn bash -c \"kinit -kt /etc/security/keytabs/yarn.service.keytab yarn/\$(hostname -f); yarn rmadmin -refreshUserToGroupsMappings\""
    fi
}

function _ssl_openssl_cnf_generate() {
    local __doc__="(not in use) Generate openssl config file (openssl.cnf) for self-signed certificate (default is for wildcard)"
    # _ssl_openssl_cnf_generate "$_dname" "$_password" "$_domain_suffix" "$_work_dir"
    local _dname="$1"
    local _password="$2"
    local _domain_suffix="${3-.`hostname -d`}"
    local _work_dir="${4-./}"

    if [ -s "${_work_dir%/}/openssl.cnf" ]; then
        _log "WARN" "${_work_dir%/}/openssl.cnf exists. Skipping..."
        return
    fi

    [ -z "$_domain_suffix" ] && _domain_suffix=".`hostname`"
    [ -z "$_dname" ] && _dname="CN=*.${_domain_suffix#.}, OU=Lab, O=Osakos, L=Brisbane, ST=QLD, C=AU"
    [ -z "$_password" ] && _password=${g_OTHER_DEFAULT_PWD}

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
    #echo [EMAIL PROTECTED] >> "${_work_dir%/}/openssl.cnf"   # can't remember why put twice
    echo [ v3_ca ] >> "${_work_dir%/}/openssl.cnf"
    echo "subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
basicConstraints = critical, CA:TRUE, pathlen:3
keyUsage = critical, cRLSign, keyCertSign
nsCertType = sslCA, emailCA" >> "${_work_dir%/}/openssl.cnf"
    echo [ v3_req ] >> "${_work_dir%/}/openssl.cnf"
    echo "basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
#extendedKeyUsage=serverAuth
subjectAltName = @alt_names" >> "${_work_dir%/}/openssl.cnf"
    # Need this for Chrome
    echo "[ alt_names ]
DNS.1 = ${_domain_suffix#.}
DNS.2 = *.${_domain_suffix#.}" >> "${_work_dir%/}/openssl.cnf"
}

function f_dnsmasq() {
    local __doc__="Install and set up dnsmasq. Mini version of _setup_host.sh one"
    local _domain_suffix="${1-"$(hostname -d)"}"
    apt-get -y install dnsmasq || return $?

    # For Ubuntu 18.04 name resolution slowness (ssh and sudo too).
    # Also local hostname needs to be resolved @see: https://linuxize.com/post/how-to-change-hostname-on-ubuntu-18-04/
    grep -q '^no-resolv' /etc/dnsmasq.conf || echo 'no-resolv' >>/etc/dnsmasq.conf
    grep -q '^server=' /etc/dnsmasq.conf || echo 'server=1.1.1.1' >>/etc/dnsmasq.conf
    if [ -n "${_domain_suffix}" ]; then
        grep -q '^local=' /etc/dnsmasq.conf || echo 'local=/'${_domain_suffix#.}'/' >>/etc/dnsmasq.conf
    fi
    grep -q '^addn-hosts=' /etc/dnsmasq.conf || echo 'addn-hosts=/etc/banner_add_hosts' >>/etc/dnsmasq.conf
    grep -q '^resolv-file=' /etc/dnsmasq.conf || (
        echo 'resolv-file=/etc/resolv.dnsmasq.conf' >>/etc/dnsmasq.conf
        echo 'nameserver 1.1.1.1' >/etc/resolv.dnsmasq.conf
    )

    touch /etc/banner_add_hosts || return $?
    chmod 666 /etc/banner_add_hosts
    # To avoid "Ignoring query from non-local network" message:
    if ps aux | grep -w 'dnsmasq' | grep -q 'local-service'; then
        sed -i 's/ --local-service//g' /etc/init.d/dnsmasq
    fi
    # TODO: Also may need to add below in dnsmasq.conf
    #listen-address=127.0.0.1
    #listen-address=$(hostname -I | awk '{print $1}')

    # @see https://bugs.launchpad.net/ubuntu/+source/systemd/+bug/1624320
    if [ -L /etc/resolv.conf ] && grep -q '^nameserver 127.0.0.53' /etc/resolv.conf; then
        systemctl stop systemd-resolved
        systemctl disable systemd-resolved
        rm -f /etc/resolv.conf
        _log "WARN" "systemctl disable systemd-resolved was run. Please reboot"
    fi
    # NOTE: this won't work if container (if so, may need --dns=127.0.0.1)
    echo 'nameserver 127.0.0.1' >/etc/resolv.conf
    if ! grep -qw dnsmasq /etc/sudoers; then
        # NOT RECOMMENDED but for this service, allow everyone to reload
        echo 'ALL ALL=NOPASSWD: /etc/init.d/dnsmasq force-reload' >> /etc/sudoers
    fi
    service dnsmasq restart
}

function f_useradd() {
    local _user="$1"
    local _pwd="${2:-"${_user}123"}"

    [ -z "${_user}" ] && return 1
    if ! id -u ${_user} &>/dev/null; then
        # should specify home directory just in case?
        useradd -d "/home/${_user}/" -s "$(which bash)" -p "$(echo "${_pwd}" | openssl passwd -1 -stdin)" "${_user}"
        mkdir "/home/${_user}/" && chown "${_user}":"${_user}" "/home/${_user}/"
    fi
}