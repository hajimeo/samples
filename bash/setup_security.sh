#!/usr/bin/env bash
#
# DOWNLOAD:
#   curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_security.sh
#

### OS/shell settings
shopt -s nocasematch
#shopt -s nocaseglob
set -o posix
#umask 0000

# Global variables
g_KEYSTORE_FILE="server.keystore.jks"
g_KEYSTORE_FILE_P12="server.keystore.p12"
g_FREEIPA_DEFAULT_PWD="secret12"
g_admin="${_ADMIN_USER-"admin"}"    # not in use at this moment
g_admin_pwd="${_ADMIN_PASS-"admin123"}"


function f_ssl_setup() {
    local __doc__="Setup SSL (wildcard) certificate for f_ssl_hadoop"
    # f_ssl_setup "" ".standalone.localdomain"
    local _password="${1:-${g_admin_pwd}}"
    local _domain_suffix="${2:-"`hostname -s`.localdomain"}}"
    local _openssl_cnf="${3:-./openssl.cnf}"

    if [ ! -s "${_openssl_cnf}" ]; then
        curl -s -f -o "${_openssl_cnf}" https://raw.githubusercontent.com/hajimeo/samples/master/misc/openssl.cnf || return $?
    echo "
[ alt_names ]
DNS.1 = ${_domain_suffix#.}
DNS.2 = *.${_domain_suffix#.}" >> ${_openssl_cnf}
    fi

    if [ -s ./rootCA.key ]; then
        _info "rootCA.key exists. Reusing..."
    else
        # Step1: create my root CA (key) and cert (pem) TODO: -aes256 otherwise key is not protected
        openssl genrsa -passout "pass:${_password}" -out ./rootCA.key 2048 || return $?
        # How to verify key: openssl rsa -in rootCA.key -check

        # (Optional) For Ambari 2-way SSL
        [ -r ./ca.config ] || curl -O https://raw.githubusercontent.com/hajimeo/samples/master/misc/ca.config
        mkdir -p ./db/certs
        mkdir -p ./db/newcerts
        openssl req -passin pass:${_password} -new -key ./rootCA.key -out ./rootCA.csr -batch
        openssl ca -out rootCA.crt -days 1095 -keyfile rootCA.key -key ${_password} -selfsign -extensions jdk7_ca -config ./ca.config -subj "/C=AU/ST=QLD/O=Osakos/CN=RootCA.`hostname -s`.localdomain" -batch -infiles ./rootCA.csr
        openssl pkcs12 -export -in ./rootCA.crt -inkey ./rootCA.key -certfile ./rootCA.crt -out ./keystore.p12 -password pass:${_password} -passin pass:${_password}

        # ref: https://stackoverflow.com/questions/50788043/how-to-trust-self-signed-localhost-certificates-on-linux-chrome-and-firefox
        openssl req -x509 -new -sha256 -days 3650 -key ./rootCA.key -out ./rootCA.pem \
            -config ${_openssl_cnf} -extensions v3_ca \
            -subj "/CN=RootCA.${_domain_suffix#.}" \
            -passin "pass:${_password}" || return $?
        chmod 600 ./rootCA.key
        if [ -d /usr/local/share/ca-certificates ]; then
            which update-ca-certificates && cp -f ./rootCA.pem /usr/local/share/ca-certificates && update-ca-certificates
            #openssl x509 -in /etc/ssl/certs/ca-certificates.crt -noout -subject
        fi
    fi

    # Step2: create server key and certificate
    openssl genrsa -out ./server.${_domain_suffix#.}.key 2048 || return $?
    openssl req -subj "/C=AU/ST=QLD/O=HajimeTest/CN=*.${_domain_suffix#.}" -extensions v3_req -sha256 -new -key ./server.${_domain_suffix#.}.key -out ./server.${_domain_suffix#.}.csr -config ${_openssl_cnf} || return $?
    openssl x509 -req -extensions v3_req -days 3650 -sha256 -in ./server.${_domain_suffix#.}.csr -CA ./rootCA.pem -CAkey ./rootCA.key -CAcreateserial -out ./server.${_domain_suffix#.}.crt -extfile ${_openssl_cnf} -passin "pass:$_password"

    # Step3: Create .p12 file, then .jks file
    openssl pkcs12 -export -in ./server.${_domain_suffix#.}.crt -inkey ./server.${_domain_suffix#.}.key -certfile ./server.${_domain_suffix#.}.crt -out ./${g_KEYSTORE_FILE_P12} -passin "pass:${_password}" -passout "pass:${_password}" || return $?
    [ -s ./${g_KEYSTORE_FILE} ] && mv -f ./${g_KEYSTORE_FILE} ./${g_KEYSTORE_FILE}.$$.bak
    keytool -importkeystore -srckeystore ./${g_KEYSTORE_FILE_P12} -srcstoretype pkcs12 -srcstorepass ${_password} -destkeystore ./${g_KEYSTORE_FILE} -deststoretype JKS -deststorepass ${_password} || return $?
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
    local _password="${2-${g_admin_pwd}}"

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

    DEBIAN_FRONTEND=noninteractive apt-get install -y slapd ldap-utils || return $?
    service slapd start
    DEBIAN_FRONTEND=noninteractive apt-get install -y phpldapadmin
    service apache2 start

    if [ "$_shared_domain" == "example.com" ]; then
        curl -sf -L --compressed https://raw.githubusercontent.com/hajimeo/samples/master/misc/example.ldif -o /tmp/example.ldif || return $?
        ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/example.ldif
    fi

    # setting up ldaps (SSL)    @see: https://ubuntu.com/server/docs/service-ldap-with-tls
    mkdir -v /etc/ldap/ssl || return $?
    curl -o /etc/ldap/ssl/slapd.key -sf -L https://raw.githubusercontent.com/hajimeo/samples/master/misc/standalone.localdomain.key
    curl -o /etc/ldap/ssl/slapd.crt -sf -L https://raw.githubusercontent.com/hajimeo/samples/master/misc/standalone.localdomain.crt
    chown -v openldap:openldap /etc/ldap/ssl/slapd.* || return $?
    chmod -v 400 /etc/ldap/ssl/slapd.* || return $?
    cat << EOF > /tmp/certinfo.ldif
dn: cn=config
add: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/ssl/certs/rootCA_standalone.pem
-
add: olcTLSCertificateFile
olcTLSCertificateFile: /etc/ldap/ssl/slapd.crt
-
add: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/ldap/ssl/slapd.key
EOF
    ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/certinfo.ldif || return $?
    # NOTE: as per doc, ldaps is deprecated but enabling for now...
    _upsert "/etc/default/slapd" "SLAPD_SERVICES" '"ldap:/// ldapi:/// ldaps:///"'
    service slapd restart || return $?
    # test
    echo | openssl s_client -connect localhost:636 -showcerts | head
}

function _ldap_server_configure_external() {
    local __doc__="TODO: Configure LDAP server via SSH (requires password-less ssh)"
    local _ldap_domain="$1"
    local _password="${2-${g_admin_pwd}}"
    local _server="${3-localhost}"

    if [ -z "$_ldap_domain" ]; then
        _ldap_domain="dc=example,dc=com"
        _warn "No LDAP Domain, so using ${_ldap_domain}"
    fi

    local _md5="`ssh -q root@$_server -t "slappasswd -s ${_password}"`" || return $?

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
    ssh -q root@$_server -t 'echo "dn: '${_ldap_domain}'
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
        ssh -q root@node$i${r_DOMAIN_SUFFIX} -t "yum -y erase nscd;yum -y install sssd sssd-client sssd-ldap openldap-clients"
        if [ $? -eq 0 ]; then
            ssh -q root@node$i${r_DOMAIN_SUFFIX} -t "authconfig --enablesssd --enablesssdauth --enablelocauthorize --enableldap --enableldapauth --disableldaptls --ldapserver=ldap://${_ldap_server} --ldapbasedn=${_ldap_basedn} --update" || _warn "node$i failed to setup ldap client"
            # test
            #authconfig --test
            # getent passwd admin
        else
            _warn "node$i failed to install ldap client"
        fi
    done
}

function f_freeipa_install() {
    local __doc__="Install freeIPA (may better create a dedicated container)"
    #p_node_create node99${r_DOMAIN_SUFFIX} 99 # Intentionally no Ambari install
    local _ipa_server_fqdn="$1"
    local _password="${2:-$g_FREEIPA_DEFAULT_PWD}"    # password need to be 8 or longer
    local _force="${3}"

    # Used ports https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/linux_domain_identity_authentication_and_policy_guide/installing-ipa
    ssh -q root@${_node} -t "yum update -y"
    ssh -q root@${_ipa_server_fqdn} -t "yum install freeipa-server -y" || return $?

    # seems FreeIPA needs ipv6 for loopback
    ssh -q root@${_ipa_server_fqdn} -t 'grep -q "^net.ipv6.conf.all.disable_ipv6" /etc/sysctl.conf || (echo "net.ipv6.conf.all.disable_ipv6 = 0" >> /etc/sysctl.conf;sysctl -w net.ipv6.conf.all.disable_ipv6=0);grep -q "^net.ipv6.conf.lo.disable_ipv6" /etc/sysctl.conf || (echo "net.ipv6.conf.lo.disable_ipv6 = 0" >> /etc/sysctl.conf;sysctl -w net.ipv6.conf.lo.disable_ipv6=0)'
    ssh -q root@${_ipa_server_fqdn} -t 'sysctl -a 2>/dev/null | grep "^net.ipv6.conf.lo.disable_ipv6 = 1"' && return $?
    # https://bugzilla.redhat.com/show_bug.cgi?id=1677027
    ssh -q root@${_ipa_server_fqdn} -t 'sysctl -w fs.protected_regular=0'

    #_warn " YOU MIGHT WANT TO RESTART OS/CONTAINTER NOW (sleep 10)  "
    #sleep 10

    # TODO: got D-bus error when freeIPA calls systemctl (service dbus restart makes install works but makes docker slow/unstable)
    [[ "${_force}" =~ ^(y|Y) ]] && ssh -q root@${_ipa_server_fqdn} -t 'ipa-server-install --uninstall --ignore-topology-disconnect --ignore-last-of-role'
    # Adding -v /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket in dcoker run
    ssh -q root@${_ipa_server_fqdn} -t '_d=`hostname -d` && ipa-server-install -a "'${_password}'" --hostname=`hostname -f` -r ${_d^^} -p "'${_password}'" -n ${_d} -U'
    if [ $? -ne 0 ]; then
        _error "ipa-server-install failed. You might want to run 'service dbus restart' and/or restart the OS (container), and uninstall then re-install"
        return 1
    fi
    ssh -q root@${_ipa_server_fqdn} -t '[ ! -s /etc/rc.lcoal ] && echo -e "#!/bin/bash\nexit 0" > /etc/rc.local'
    ssh -q root@${_ipa_server_fqdn} -t 'grep -q "ipactl start" /etc/rc.local || echo -e "\n`which ipactl` start" >> /etc/rc.local'

    local _domain="${_ipa_server_fqdn#*.}"
    if [ "${_domain}" == "standalone.localdomain" ]; then
        f_freeipa_cert_update "${_ipa_server_fqdn}"
    fi

    #ipa ping
    #ipa config-show --all

    f_freeipa_cert_update "${_ipa_server_fqdn}"
    _warn "TODO: Update Password global_policy Max lifetime (days) to unlimited or 3650 days"
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
    ssh -q root@${_client_host} -t '[ "`hostname -f`" = "'${_ipa_server_fqdn}'" ] && exit
echo -n "'${_adm_pwd}'" | kinit admin
yum install ipa-client -y
'${_uninstall}'
ipa-client-install --unattended --hostname=`hostname -f` --server='${_ipa_server_fqdn}' --domain='${_domain}' --realm='${_domain^^}' -p admin -w '${_adm_pwd}' --mkhomedir --force-join'
}

function f_freeipa_cert_update() {
    local __doc__="Update/renew certificate (TODO: haven't tested)"
    # @see https://www.powerupcloud.com/freeipa-server-and-client-installation-on-ubuntu-16-04-part-i/
    local _ipa_server_fqdn="${1}"
    local _p12_file="${2}"
    local _full_ca="${3}"   # If intermediate is used, concatenate first
    local _p12_pass="${4:-${g_admin_pwd}}"
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
        ssh -q root@${_ipa_server_fqdn} -t "ipa-cacert-manage install ${_full_ca} && echo -n '${_adm_pwd}' | kinit admin && ipa-certupdate" #|| return $?
        _info "TODO: Run 'ipa-certupdate' on each node."
    fi

    scp ${_p12_file} root@${_ipa_server_fqdn}:/tmp/ || return $?
    # Should update only web server cert (no -d)?
    ssh -q root@${_ipa_server_fqdn} -t "ipa-server-certinstall -v -w -d /tmp/$(basename ${_p12_file}) --pin="${_p12_pass}" -p "${_adm_pwd}" && ipactl restart"
}

function f_simplesamlphp() {
    local __doc__="TODO: Setup Simple SAML PHP on a container"
    local _host="${1}"

    # TODO: Is it OK to use -y in the  yum install -y php as 5.6 is too old
    ssh -q root@${_host} -t "yum install -y httpd mod_ssl && \
yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm && \
yum install -y http://rpms.remirepo.net/enterprise/remi-release-7.rpm && \
yum install -y yum-utils && \
yum-config-manager --enable remi-php56 && \
yum install -y php php-mbstring php-xml php-curl php-memcache php-ldap" || return $?
    ssh -q root@${_host} -t "[ ! -s /etc/httpd/conf.d/saml.conf ] && cp -pf /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/saml.conf; \
[ ! -s /etc/httpd/conf.d/ssl.conf.orig ] && mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.orig; \
curl -o /etc/pki/tls/certs/localhost.crt -L https://raw.githubusercontent.com/hajimeo/samples/master/misc/standalone.localdomain.crt; \
curl -o /etc/pki/tls/private/localhost.key -L https://raw.githubusercontent.com/hajimeo/samples/master/misc/standalone.localdomain.key"
    ssh -q root@${_host} -t "patch /etc/httpd/conf.d/saml.conf <(echo '--- /etc/httpd/conf.d/ssl.conf  2020-11-16 14:44:03.000000000 +0000
+++ /etc/httpd/conf.d/saml.conf 2020-12-30 01:24:06.813189424 +0000
@@ -2,7 +2,7 @@
 # When we also provide SSL we have to listen to the
 # the HTTPS port in addition.
 #
-Listen 443 https
+Listen 8444 https

 ##
 ##  SSL Global Context
@@ -53,7 +53,18 @@
 ## SSL Virtual Host Context
 ##

-<VirtualHost _default_:443>
+<VirtualHost _default_:8444>
+  # changes for SimpleSamlPHP
+  SetEnv SIMPLESAMLPHP_CONFIG_DIR /var/www/simplesaml/config
+  DocumentRoot /var/www/simplesaml/www
+  Alias /simplesaml /var/www/simplesaml/www
+  Alias /sample /var/www/sample/
+  ServerName node-freeipa.standalone.localdomain:8444
+  <Directory /var/www/simplesaml/www>
+    <IfModule mod_authz_core.c>
+      Require all granted
+    </IfModule>
+  </Directory>

 # General setup for the virtual host, inherited from global configuration
 #DocumentRoot \"/var/www/html\"')"
    ssh -q root@${_host} -t "systemctl enable httpd && systemctl restart httpd" || return $?
    # TODO: configure Simple SAML PHP
#curl -O -J -L https://simplesamlphp.org/download?latest
#tar -xvf simplesamlphp-1.*.tar.gz
#mv simplesamlphp-1.18.8 /var/www/simplesaml
#vim /var/www/simplesaml/config/config.php ...
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
            _warn "No hdfs client node found to execute 'hdfs dfsadmin -refreshUserToGroupsMappings'"
            return 1
        fi
        ssh -q root@$_hdfs_client_node -t "sudo -u hdfs bash -c \"kinit -kt /etc/security/keytabs/hdfs.headless.keytab hdfs-${_c}; hdfs dfsadmin -refreshUserToGroupsMappings\""

        local _yarn_rm_node="`_ambari_query_sql "select h.host_name from hostcomponentstate hcs join hosts h on hcs.host_id=h.host_id where component_name='RESOURCEMANAGER' and current_state='STARTED' limit 1" ${_ambari_host}`"
        if [ -z "$_yarn_rm_node" ]; then
            _error "No yarn client node found to execute 'yarn rmadmin -refreshUserToGroupsMappings'"
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
        _warn "${_work_dir%/}/openssl.cnf exists. Skipping..."
        return
    fi

    [ -z "$_domain_suffix" ] && _domain_suffix=".`hostname`"
    [ -z "$_dname" ] && _dname="CN=*.${_domain_suffix#.}, OU=Lab, O=Osakos, L=Brisbane, ST=QLD, C=AU"
    [ -z "$_password" ] && _password=${g_admin_pwd}

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