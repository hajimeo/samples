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
# Example 0: source
#   source ./setup_security.sh
#   f_loadResp  # If not Sandbox
#
# Example 1: How to set up Kerberos
#   f_kdc_install_on_host
#   f_ambari_kerberos_setup
#
#   If Sandbox (after KDC setup):
#   NOTE: sandbox.hortonworks.com needs to be resolved to a proper IP, also password less scp/ssh required
#   f_ambari_kerberos_setup "$g_KDC_REALM" "172.17.0.1" "" "sandbox-hdp.hortonworks.com" "sandbox-hdp.hortonworks.com"
#
# Example 2: How to set up HTTP Authentication (SPNEGO) on hadoop component
#   f_spnego_hadoop
#
#   If Sandbox (after KDC/kerberos setup):
#   NOTE: sandbox.hortonworks.com needs to be resolved to a proper IP, also password less scp/ssh required
#   f_spnego_hadoop "$g_KDC_REALM" "hortonworks.com" "sandbox.hortonworks.com" "8080" "sandbox.hortonworks.com"
#
# Example 3: How to set up SSL on hadoop component (requires JRE/JDK for keytool command)
#   mkdir ssl_setup; cd ssl_setup
#   r_NO_UPDATING_AMBARI_CONFIG=Y f_ssl_hadoop
#
#   If Sandbox:
#   NOTE: sandbox-hdp.hortonworks.com needs to be resolved to a proper IP, also password less scp/ssh required
#   mkdir ssl_setup; cd ssl_setup
#   f_ssl_hadoop "" "sandbox-hdp.hortonworks.com" "8080" "sandbox-hdp.hortonworks.com"
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
g_KEYSTORE_FILE_P12="server.keystore.p12"
g_TRUSTSTORE_FILE="server.truststore.jks"
g_CLIENT_KEYSTORE_FILE="client.keystore.jks"
g_CLIENT_TRUSTSTORE_FILE="all.jks"
g_CLIENT_TRUSTSTORE_PASSWORD="changeit"
g_FREEIPA_DEFAULT_PWD="secret12"
g_KDC_REALM="`hostname -s`" && g_KDC_REALM=${g_KDC_REALM^^}
g_admin="${_ADMIN_USER-admin}"
g_admin_pwd="${_ADMIN_PASS-admin}"

function f_kdc_install_on_ambari_node() {
    local __doc__="(Deprecated) Install KDC/kadmin service to $r_AMBARI_HOST. May need UDP port forwarder https://raw.githubusercontent.com/hajimeo/samples/master/python/udp_port_forwarder.py"
    local _realm="${1-$g_KDC_REALM}"
    local _password="${2-${g_DEFAULT_PASSWORD:-"hadoop"}}"
    local _server="${3-$r_AMBARI_HOST}"

    if [ -z "$_server" ]; then
        _error "KDC installing hostname is missing"
        return 1
    fi

    ssh -q root@$_server -t "yum install krb5-server krb5-libs krb5-workstation -y"
    # this doesn't work with docker though
    ssh -q root@$_server -t "chkconfig  krb5kdc on; chkconfig kadmin on"
    ssh -q root@$_server -t "mv /etc/krb5.conf /etc/krb5.conf.orig; echo \"[libdefaults]
 default_realm = $_realm
[realms]
 $_realm = {
   kdc = $_server
   admin_server = $_server
 }\" > /etc/krb5.conf"
    ssh -q root@$_server -t "kdb5_util create -s -P $_password"
    # chkconfig krb5kdc on;chkconfig kadmin on; doesn't work with docker
    ssh -q root@$_server -t "echo '*/admin *' > /var/kerberos/krb5kdc/kadm5.acl;service krb5kdc restart;service kadmin restart;kadmin.local -q \"add_principal -pw $_password admin/admin\";kadmin.local -q \"add_principal -pw $_password kadmin/admin\""
    #ssh -2CNnqTxfg -L88:$_server:88 $_server # TODO: UDP does not work. and need 749 and 464
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
    local _realm="${1:-$g_KDC_REALM}"
    local _kdc_server="${2:-"${r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}"}"
    local _password="${3}"
    local _ambari_host="${4:-$r_AMBARI_HOST}"
    local _how_many="${5:-$r_NUM_NODES}"
    local _start_from="${6:-$r_NODE_START_NUM}"
    local _domain_suffix="${7:-$r_DOMAIN_SUFFIX}"
    local _kdc_type="${8:-"mit-kdc"}" # TODO: Not using and MIT KDC only

    if [ -z "$_password" ]; then
        _password="${g_DEFAULT_PASSWORD:-"hadoop"}"
    fi

    if ! which python &>/dev/null; then
        _error "Please install python (eg: apt-get install -y python)"
        return 1
    fi

    # Test admin principal before proceeding
    #echo -e "${_password}" | kinit -l 5m -c /tmp/krb5cc_test_$$ admin/admin@${_realm} >/dev/null || return $?
    kadmin -s ${_kdc_server} -p admin/admin@${_realm} -w ${_password} -r ${_realm} -q "get_principal kadmin/admin@${_realm}" || return $?

    local _cluster_name="`f_get_cluster_name $_ambari_host`" || return 1
    local _api_uri="http://$_ambari_host:8080/api/v1/clusters/$_cluster_name"
    local _stack_name="HDP"
    local _stack_version="`_ambari_query_sql "select s.stack_version from clusters c join stack s on c.desired_stack_id = s.stack_id where c.cluster_name='$_cluster_name';" "$_ambari_host"`"
    local _request_context="Stop Service with f_ambari_kerberos_setup"
    local _version="version`date +%s`000"

    # Test GET method
    #response=$(curl --write-out %{http_code} -s -o /dev/null "${_api_uri}/configurations/service_config_versions?service_name=KERBEROS")

    _info "Storing KDC admin credential temporarily"
    curl -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X POST "${_api_uri}/credentials/kdc.admin.credential" -d '{ "Credential" : { "principal" : "admin/admin@'$_realm'", "key" : "'$_password'", "type" : "temporary" } }' &>/dev/null

    _info "Delete existing KERBEROS service (if exists)"
    curl -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X PUT "${_api_uri}" -d '{"Clusters":{"security_type":"NONE"}}'
    # TODO: if above failed, should not execute blow two. If AD is used, may get The 'krb5-conf' configuration is not available error
    curl -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X DELETE "${_api_uri}/services/KERBEROS"
    curl -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} -X DELETE "${_api_uri}/artifacts/kerberos_descriptor"
    echo ""
    # NOTE: for Web UI, ambari-server restart might be needed
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

function f_ambari_kerberos_with_ad_setup() {
    local __doc__="TODO: Setup Kerberos with Windows AD via Ambari APIs."
    return

    local _realm="${1-$g_KDC_REALM}"
    local _kdc_server="${2-$r_DOCKER_PRIVATE_HOSTNAME}${r_DOMAIN_SUFFIX}"
    local _password="${3}"
    local _ambari_host="${4-$r_AMBARI_HOST}"
    local _how_many="${5-$r_NUM_NODES}"
    local _start_from="${6-$r_NODE_START_NUM}"
    local _domain_suffix="${7-$r_DOMAIN_SUFFIX}"

    local _cluster_name="`f_get_cluster_name $_ambari_host`" || return 1
    local _api_uri="http://$_ambari_host:8080/api/v1/clusters/$_cluster_name"

    curl -f -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} "${_api_uri}/services/KERBEROS" -X DELETE    # It's OK to fail (404)
    curl -f -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} "${_api_uri}/services" --data '{"ServiceInfo": { "service_name": "KERBEROS"}}' || return $?
    curl -f -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} "${_api_uri}/services?ServiceInfo/service_name=KERBEROS" --data '{"components":[{"ServiceComponentInfo":{"component_name":"KERBEROS_CLIENT"}}]}' || return $?
    curl -f -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} "${_api_uri}/hosts" --data '{"RequestInfo":{"query":"Hosts/host_name=node6.ubuntu.localdomain"},"Body":{"host_components":[{"HostRoles":{"component_name":"KERBEROS_CLIENT"}}]}}' || return $?
    curl -f -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} "${_api_uri}" -X PUT --data $'[{"Clusters":{"desired_config":[{"type":"kerberos-env","properties":{"ad_create_attributes_template":"\\n{\\n  \\"objectClass\\": [\\"top\\", \\"person\\", \\"organizationalPerson\\", \\"user\\"],\\n  \\"cn\\": \\"$principal_name\\",\\n  #if( $is_service )\\n  \\"servicePrincipalName\\": \\"$principal_name\\",\\n  #end\\n  \\"userPrincipalName\\": \\"$normalized_principal\\",\\n  \\"unicodePwd\\": \\"$password\\",\\n  \\"accountExpires\\": \\"0\\",\\n  \\"userAccountControl\\": \\"66048\\"\\n}","admin_server_host":"WIN-59T24EHPKJN.hdp.localdomain","case_insensitive_username_rules":"false","container_dn":"OU=Hadoop,DC=HDP,DC=LOCALDOMAIN","create_ambari_principal":"true","encryption_types":"aes des3-cbc-sha1 rc4 des-cbc-md5","executable_search_paths":"/usr/bin, /usr/kerberos/bin, /usr/sbin, /usr/lib/mit/bin, /usr/lib/mit/sbin","install_packages":"true","ipa_user_group":"","kdc_create_attributes":"","kdc_hosts":"WIN-59T24EHPKJN.hdp.localdomain","kdc_type":"active-directory","ldap_url":"ldaps://WIN-59T24EHPKJN.hdp.localdomain","manage_auth_to_local":"true","manage_identities":"true","master_kdc":"","password_length":"20","password_min_digits":"1","password_min_lowercase_letters":"1","password_min_punctuation":"1","password_min_uppercase_letters":"1","password_min_whitespace":"0","preconfigure_services":"DEFAULT","realm":"HDP.LOCALDOMAIN","service_check_principal_name":"${cluster_name|toLower()}-${short_date}"},"service_config_version_note":"This is the initial configuration created by Enable Kerberos wizard."},{"type":"krb5-conf","properties":{"conf_dir":"/etc","content":"{#\\n# Licensed to the Apache Software Foundation (ASF) under one\\n# or more contributor license agreements.  See the NOTICE file\\n# distributed with this work for additional information\\n# regarding copyright ownership.  The ASF licenses this file\\n# to you under the Apache License, Version 2.0 (the\\n# \\"License\\"); you may not use this file except in compliance\\n# with the License.  You may obtain a copy of the License at\\n#\\n#   http://www.apache.org/licenses/LICENSE-2.0\\n#\\n# Unless required by applicable law or agreed to in writing, software\\n# distributed under the License is distributed on an \\"AS IS\\" BASIS,\\n# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.\\n# See the License for the specific language governing permissions and\\n# limitations under the License.\\n#}\\n[libdefaults]\\n  renew_lifetime = 7d\\n  forwardable = true\\n  default_realm = {{realm}}\\n  ticket_lifetime = 24h\\n  dns_lookup_realm = false\\n  dns_lookup_kdc = false\\n  default_ccache_name = /tmp/krb5cc_%{uid}\\n  #default_tgs_enctypes = {{encryption_types}}\\n  #default_tkt_enctypes = {{encryption_types}}\\n  {%- if force_tcp %}\\n  udp_preference_limit = 1\\n  {%- endif -%}\\n{% if domains %}\\n[domain_realm]\\n{%- for domain in domains.split(\',\') %}\\n  {{domain|trim()}} = {{realm}}\\n{%- endfor %}\\n{% endif %}\\n[logging]\\n  default = FILE:/var/log/krb5kdc.log\\n  admin_server = FILE:/var/log/kadmind.log\\n  kdc = FILE:/var/log/krb5kdc.log\\n\\n[realms]\\n  {{realm}} = {\\n{%- if master_kdc %}\\n    master_kdc = {{master_kdc|trim()}}\\n{%- endif -%}\\n{%- if kdc_hosts > 0 -%}\\n{%- set kdc_host_list = kdc_hosts.split(\',\')  -%}\\n{%- if kdc_host_list and kdc_host_list|length > 0 %}\\n    admin_server = {{admin_server_host|default(kdc_host_list[0]|trim(), True)}}\\n{%- if kdc_host_list -%}\\n{%- if master_kdc and (master_kdc not in kdc_host_list) %}\\n    kdc = {{master_kdc|trim()}}\\n{%- endif -%}\\n{% for kdc_host in kdc_host_list %}\\n    kdc = {{kdc_host|trim()}}\\n{%- endfor -%}\\n{% endif %}\\n{%- endif %}\\n{%- endif %}\\n  }\\n\\n{# Append additional realm declarations below #}","domains":"","force_tcp":"false","manage_krb5_conf":"true"},"service_config_version_note":"This is the initial configuration created by Enable Kerberos wizard."}]}}]' || return $?
    curl -f -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} "${_api_uri}/credentials/kdc.admin.credential" --data '{"Credential":{"principal":"administrator@hdp.localdomain","key":"'${_password}'","type":"temporary"}}' || return $?
    curl -f -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} "${_api_uri}/services?ServiceInfo/state=INSTALLED&ServiceInfo/service_name=KERBEROS" -X PUT --data '{"RequestInfo":{"context":"Install Kerberos Service","operation_level":{"level":"CLUSTER","cluster_name":"ubuntu6"}},"Body":{"ServiceInfo":{"state":"INSTALLED"}}}' || return $?
    # Service check
    #curl -f -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} "${_api_uri}/requests" --data '{"RequestInfo":{"context":"Kerberos Service Check","command":"KERBEROS_SERVICE_CHECK","operation_level":{"level":"CLUSTER","cluster_name":"ubuntu6"}},"Requests/resource_filters":[{"service_name":"KERBEROS"}]}' || return $?
    #curl -f -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} "${_api_uri}/artifacts/kerberos_descriptor" --data $'{"artifact_data":{"identit...Lower()}","realm":"HDP.LOCALDOMAIN"}}}' || return $?
    # ????
    #curl -f -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} "${_api_uri}" -X PUT --data '{"Clusters":{"security_type":"NONE"}}' || return $?
    curl -f -s -H "X-Requested-By:ambari" -u ${g_admin}:${g_admin_pwd} "${_api_uri}/services?" -X PUT --data '{"RequestInfo":{"context":"Stop services","operation_level":{"level":"CLUSTER","cluster_name":"ubuntu6"}},"Body":{"ServiceInfo":{"state":"INSTALLED"}}}' || return $?

    #curl 'http://node6:8080/api/v1/clusters/ubuntu6/services?' -X PUT -H 'Pragma: no-cache' -H 'Origin: http://node6:8080' -H 'Accept-Encoding: gzip, deflate' -H 'Accept-Language: en-AU,en;q=0.9,ja;q=0.8' -H 'X-Requested-By: X-Requested-By' -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/72.0.3626.121 Safari/537.36' -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' -H 'Accept: application/json, text/javascript, */*; q=0.01' -H 'Cache-Control: no-cache' -H 'X-Requested-With: XMLHttpRequest' -H 'Cookie: gsScrollPos-742=0; AMBARISESSIONID=node02bfv7fhc3r8413o9kjd6jkdhf4.node0' -H 'Connection: keep-alive' -H 'Referer: http://node6:8080/' --data '{"RequestInfo":{"context":"Stop services","operation_level":{"level":"CLUSTER","cluster_name":"ubuntu6"}},"Body":{"ServiceInfo":{"state":"INSTALLED"}}}' --compressed
}

function f_ssl_setup() {
    local __doc__="Setup SSL (wildcard) certificate for f_ssl_hadoop"
    # f_ssl_setup "" ".standalone.localdomain"
    local _password="${1:-${g_DEFAULT_PASSWORD:-hadoop}}"
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

    # Step3: Create a client truststore file used by all clients/nodes and a server keystore
    mv -f ./$g_CLIENT_TRUSTSTORE_FILE ./$g_CLIENT_TRUSTSTORE_FILE.$$.bak &>/dev/null
    keytool -keystore ./$g_CLIENT_TRUSTSTORE_FILE -alias hadoopAllCert -import -file ./server.${_domain_suffix#.}.crt -storepass ${g_CLIENT_TRUSTSTORE_PASSWORD} -noprompt || return $?
    openssl pkcs12 -export -in ./server.${_domain_suffix#.}.crt -inkey ./server.${_domain_suffix#.}.key -certfile ./server.${_domain_suffix#.}.crt -out ./${g_KEYSTORE_FILE_P12} -passin "pass:${_password}" -passout "pass:${_password}" || return $?
    [ -s ./${g_KEYSTORE_FILE} ] && mv -f ./${g_KEYSTORE_FILE} ./${g_KEYSTORE_FILE}.$$.bak
    keytool -importkeystore -srckeystore ./${g_KEYSTORE_FILE_P12} -srcstoretype pkcs12 -srcstorepass ${_password} -destkeystore ./${g_KEYSTORE_FILE} -deststoretype JKS -deststorepass ${_password} || return $?
}

function f_ssl_hadoop() {
    local __doc__="Setup SSL for hadoop https://community.hortonworks.com/articles/92305/how-to-transfer-file-using-secure-webhdfs-in-distc.html"
    # f_ssl_hadoop "" "" "" "cdh5101.standalone.localdomain" "" ".standalone.localdomain"
    local _password="${1:-${g_DEFAULT_PASSWORD:-hadoop}}"
    local _ambari_host="${2-$r_AMBARI_HOST}"
    local _ambari_port="${3:-8080}"
    local _how_many="${4:-$r_NUM_NODES}"    # Integer or a hostname
    local _start_from="${5:-$r_NODE_START_NUM}"
    local _domain_suffix="${6:-${r_DOMAIN_SUFFIX:-.`hostname -s`.localdomain}}"
    local _openssl_cnf="${7:-./openssl.cnf}"
    local _no_updating_ambari_config="${8:-$r_NO_UPDATING_AMBARI_CONFIG}"

    f_ssl_setup "${_password}" "${_domain_suffix}" "${_openssl_cnf}"

    # This is for keytool
    local _java_home=""
    [ -n "${_ambari_host}" ] && _java_home="`ssh -q root@${_ambari_host} "sed -n -r 's/^java\.home=(.+)/\1/p' /etc/ambari-server/conf/ambari.properties"`"

    if ! [[ "${_how_many}" =~ ^[0-9]+$ ]]; then
        local _hostnames="${_how_many}"
        _info "Copying jks to ${_hostnames} ..."
        for i in  `echo ${_hostnames} | sed 's/ /\n/g'`; do
            _hadoop_ssl_per_node "$i" "${_java_home}" "./${g_KEYSTORE_FILE}" "${_domain_suffix}" || return $?
        done
    else
        _info "Copying jks to all nodes..."
        for i in `_docker_seq "$_how_many" "$_start_from"`; do
            _hadoop_ssl_per_node "node${i}${_domain_suffix}" "${_java_home}" "./${g_KEYSTORE_FILE}" "${_domain_suffix}" || return $?
        done
    fi

    if [[ "$_no_updating_ambari_config" =~ (^y|^Y) ]] || [ -z "${_ambari_host}" ]; then
        return $?
    fi
    _hadoop_ssl_config_update "$_ambari_host" "$_ambari_port" "$_password"
}

function f_export_key() {
    local __doc__="Export private key from keystore"
    local _keystore="${1}"
    local _in_pass="${2}"
    local _alias="${3}"
    local _private_key="${4}"
    local _tmp_keystore="`basename "${_keystore}"`.tmp.jks"

    [ -z "${_alias}" ] &&  _alias="`hostname -f`"
    [ -z "${_private_key}" ] &&  _private_key="${_alias}.key"

    keytool -importkeystore -noprompt -srckeystore ${_keystore} -srcstorepass "${_in_pass}" -srcalias ${_alias} \
     -destkeystore ${_tmp_keystore} -deststoretype PKCS12 -deststorepass ${_in_pass} -destkeypass ${_in_pass} || return $?
    openssl pkcs12 -in ${_tmp_keystore} -passin "pass:${_in_pass}" -nodes -nocerts -out ${_private_key} || return $?
    chmod 640  ${_private_key} && chown root:hadoop ${_private_key}
    rm -f ${_tmp_keystore}

    if [ -s "${_alias}.crt" ] && [ -s "rootCA.pem" ] && [ -s "${_alias}.key" ]; then
        cat ${_alias}.crt rootCA.pem ${_alias}.key > certificate.pem
        chmod 640 certificate.pem; chown root:hadoop certificate.pem
    fi
}

function _hadoop_ssl_config_update() {
    local _ambari_host="${1-$r_AMBARI_HOST}"
    local _ambari_port="${2-8080}"
    local _password="$3"

    _info "Updating Ambari configs for HDFS (to use SSL and SASL)..."
    f_ambari_configs "core-site" "{\"hadoop.rpc.protection\":\"privacy\",\"hadoop.ssl.require.client.cert\":\"false\",\"hadoop.ssl.hostname.verifier\":\"DEFAULT\",\"hadoop.ssl.keystores.factory.class\":\"org.apache.hadoop.security.ssl.FileBasedKeyStoresFactory\",\"hadoop.ssl.server.conf\":\"ssl-server.xml\",\"hadoop.ssl.client.conf\":\"ssl-client.xml\"}" "$_ambari_host" "$_ambari_port"
    f_ambari_configs "ssl-client" "{\"ssl.client.truststore.location\":\"${g_CLIENT_TRUST_LOCATION%/}/${g_CLIENT_TRUSTSTORE_FILE}\",\"ssl.client.truststore.password\":\"${g_CLIENT_TRUSTSTORE_PASSWORD}\",\"ssl.client.keystore.location\":\"${g_CLIENT_KEY_LOCATION%/}/${g_KEYSTORE_FILE}\",\"ssl.client.keystore.password\":\"$_password\"}" "$_ambari_host" "$_ambari_port"
    f_ambari_configs "ssl-server" "{\"ssl.server.truststore.location\":\"${g_CLIENT_TRUST_LOCATION%/}/${g_CLIENT_TRUSTSTORE_FILE}\",\"ssl.server.truststore.password\":\"${g_CLIENT_TRUSTSTORE_PASSWORD}\",\"ssl.server.keystore.location\":\"${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE}\",\"ssl.server.keystore.password\":\"$_password\",\"ssl.server.keystore.keypassword\":\"$_password\"}" "$_ambari_host" "$_ambari_port"
    f_ambari_configs "hdfs-site" "{\"dfs.encrypt.data.transfer\":\"true\",\"dfs.encrypt.data.transfer.algorithm\":\"3des\",\"dfs.http.policy\":\"HTTPS_ONLY\"}" "$_ambari_host" "$_ambari_port" # or HTTP_AND_HTTPS
    f_ambari_configs "mapred-site" "{\"mapreduce.jobhistory.http.policy\":\"HTTPS_ONLY\",\"mapreduce.jobhistory.webapp.https.address\":\"0.0.0.0:19888\"}" "$_ambari_host" "$_ambari_port"
    f_ambari_configs "yarn-site" "{\"yarn.http.policy\":\"HTTPS_ONLY\",\"yarn.nodemanager.webapp.https.address\":\"0.0.0.0:8044\"}" "$_ambari_host" "$_ambari_port"
    f_ambari_configs "tez-site" "{\"tez.runtime.shuffle.keep-alive.enabled\":\"true\"}" "$_ambari_host" "$_ambari_port"
    #f_ambari_configs "hive-site" '{"hive.server2.use.SSL":"true", "hive.server2.keystore.path":"'${g_SERVER_KEY_LOCATION%/}'/'${g_KEYSTORE_FILE}'", "hive.server2.keystore.password":"'${_password}'"}' "$_ambari_host" "$_ambari_port" # Don't need to specify the truststore? also hive 1.x does not work with kerberos. HIVE-10048

    # TODO: https://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.6.2/bk_hdfs-administration/content/configuring_datanode_sasl.html for not using jsvc
    # If Ambari is 2.4.x or higher below works
    echo ""
    _info "TODO: Please manually update:
    yarn.resourcemanager.webapp.https.address=RM_HOST:8090
    mapreduce.shuffle.ssl.enabled=true (mapreduce.shuffle.port)
    tez.runtime.shuffle.ssl.enable=true"

    f_echo_restart_command "$_ambari_host" "$_ambari_port"
}

function _hadoop_ssl_per_node() {
    local _hostname="$1"
    local _java_home="$2"   # For ambari, using non OS java
    local _local_keystore_path="$3"
    local _domain_suffix="${4:-${r_DOMAIN_SUFFIX:-.`hostname -s`.localdomain}}"
    local _group="${5:-hadoop}"

    local _ssh="ssh -q root@${_hostname}"
    local _keytool="keytool"
    [ -n "${_java_home}" ] && _keytool="${_java_home%/}/bin/keytool"

    ${_ssh} "mkdir -m 750 -p ${g_SERVER_KEY_LOCATION%/}; groupadd ${_group}; chown root:${_group} ${g_SERVER_KEY_LOCATION%/}" || return $?
    ${_ssh} "mkdir -m 755 -p ${g_CLIENT_KEY_LOCATION%/}"
    scp ./${g_KEYSTORE_FILE} ./server.${_domain_suffix#.}.{crt,key} ./rootCA.pem root@${_hostname}:${g_SERVER_KEY_LOCATION%/}/ || return $?
    scp ./${g_CLIENT_TRUSTSTORE_FILE} root@${_hostname}:${g_CLIENT_TRUST_LOCATION%/}/ || return $?

    # Step8 (optional): if the java default truststore (cacerts) path is given, also import the cert (and doesn't care if cert already exists)
    ${_ssh} "${_keytool} -delete -keystore /etc/pki/java/cacerts -alias hadoopRootCA -noprompt -storepass changeit &>/dev/null
${_keytool} -import -keystore /etc/pki/java/cacerts -alias hadoopRootCA -file ${g_SERVER_KEY_LOCATION%/}/rootCA.pem -noprompt -storepass changeit"
    if [ -n "${_java_home}" ]; then
        ${_ssh} "${_keytool} -delete -keystore ${_java_home%/}/jre/lib/security/cacerts -alias hadoopRootCA -noprompt -storepass changeit &>/dev/null
${_keytool} -import -keystore ${_java_home%/}/jre/lib/security/cacerts -alias hadoopRootCA -file ${g_SERVER_KEY_LOCATION%/}/rootCA.pem -noprompt -storepass changeit"
    fi

    # TODO: For ranger. if file exist, need to import the certificate. Also if not kerberos, two way SSL won't work because of non 'usr_client' extension
    ${_ssh} 'for l in `ls -d /usr/hdp/current/*/conf`; do ln -s '${g_CLIENT_TRUST_LOCATION%/}'/'${g_CLIENT_TRUSTSTORE_FILE}' ${l%/}/ranger-plugin-truststore.jks 2>/dev/null; done'
    ${_ssh} 'for l in `ls -d /usr/hdp/current/*/conf`; do ln -s '${g_CLIENT_KEY_LOCATION%/}/${g_CLIENT_KEYSTORE_FILE}' ${l%/}/ranger-plugin-keystore.jks 2>/dev/null; done'
    ${_ssh} "chown root:${_group} ${g_SERVER_KEY_LOCATION%/}/*;chmod 640 ${g_SERVER_KEY_LOCATION%/}/*;"
    #yum install ca-certificates -y
    ${_ssh} "which update-ca-trust && cp -f ${g_SERVER_KEY_LOCATION%/}/rootCA.pem /etc/pki/ca-trust/source/anchors/ && update-ca-trust force-enable && update-ca-trust extract && update-ca-trust check;"
    # ls -l /etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt
}

function _hadoop_ssl_commands_per_node() {
    local _node="$1"
    local _java_home="$2"
    local _password="${3:-${g_DEFAULT_PASSWORD:-hadoop}}"
    local _dname_extra="${4:-OU=Lab, O=Osakos, L=Brisbane, ST=QLD, C=AU}"

    # TODO: assuming rootCA.xxx file names
    # TODO: convert server.keystore.jks to .p12
    #keytool -importkeystore -srckeystore /etc/security/serverKeys/server.keystore.jks -destkeystore /etc/security/serverKeys/server.keystore.p12 -deststoretype pkcs12

    local _keytool="keytool"
    if [ -n "${_java_home}" ]; then
        _keytool="${_java_home%/}/bin/keytool"
    fi
    local _ssh="ssh -q root@${_node}"

    # Taking a backup
    ${_ssh} "mv -f ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE} ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE}.$$.bak &>/dev/null"
    ${_ssh} "mv -f ${g_CLIENT_KEY_LOCATION%/}/${g_CLIENT_KEYSTORE_FILE} ${g_CLIENT_KEY_LOCATION%/}/${g_CLIENT_KEYSTORE_FILE}.$$.bak &>/dev/null"
    # Step4: On each node, create private keys for this node (one is as server key, another is as client key)
    ${_ssh} "${_keytool} -genkey -alias ${_node} -keyalg RSA -keystore ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE} -keysize 2048 -dname \"CN=${_node}, ${_dname_extra}\" -noprompt -storepass ${_password} -keypass ${_password}" || return $?
    ${_ssh} "${_keytool} -genkey -alias ${_node} -keyalg RSA -keystore ${g_CLIENT_KEY_LOCATION%/}/${g_CLIENT_KEYSTORE_FILE} -keysize 2048 -dname \"CN=${_node}, ${_dname_extra}\" -noprompt -storepass ${_password} -keypass ${_password}"
    # Step5: On each node, create CSRs
    # TODO: https://stackoverflow.com/questions/33827789/self-signed-certificate-dnsname-components-must-begin-with-a-letter , hence *expecting* ${_node} is FQDN
    ${_ssh} "${_keytool} -certreq -alias ${_node} -keystore ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE} -file ${g_SERVER_KEY_LOCATION%/}/${_node}.csr -storepass ${_password} -ext SAN=DNS:${_node}" || return $?
    ${_ssh} "${_keytool} -certreq -alias ${_node} -keystore ${g_CLIENT_KEY_LOCATION%/}/${g_CLIENT_KEYSTORE_FILE} -file ${g_CLIENT_KEY_LOCATION%/}/${_node}-client.csr -storepass ${_password}"
    # Download into (Ubuntu) host node
    scp root@${_node}:${g_SERVER_KEY_LOCATION%/}/${_node}.csr ./ || return $?
    scp root@${_node}:${g_CLIENT_KEY_LOCATION%/}/${_node}-client.csr ./ || return $?
    # Step6: Sign the CSR with the root CA
    openssl x509 -sha256 -req -in ./${_node}.csr -CA ./rootCA.pem -CAkey ./rootCA.key -CAcreateserial -out ${_node}.crt -days 730 -passin "pass:$_password" || return $?
    openssl x509 -extensions usr_cert -sha256 -req -in ./${_node}-client.csr -CA ./rootCA.pem -CAkey ./rootCA.key -CAcreateserial -out ${_node}-client.crt -days 730 -passin "pass:$_password"
    scp ./rootCA.pem ./${_node}.crt root@${_node}:${g_SERVER_KEY_LOCATION%/}/ || return $?
    scp ./${_node}-client.crt root@${_node}:${g_CLIENT_KEY_LOCATION%/}/
    # Step7: On each node, import root CA's cert and the signed cert
    ${_ssh} "${_keytool} -keystore ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE} -alias rootCA -import -file ${g_SERVER_KEY_LOCATION%/}/rootCA.pem -noprompt -storepass ${_password};${_keytool} -keystore ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE} -alias ${_node} -import -file ${g_SERVER_KEY_LOCATION%/}/${_node}.crt -noprompt -storepass ${_password}" || return $?
    ${_ssh} "${_keytool} -keystore ${g_CLIENT_KEY_LOCATION%/}/${g_CLIENT_KEYSTORE_FILE} -alias rootCA -import -file ${g_SERVER_KEY_LOCATION%/}/rootCA.pem -noprompt -storepass ${_password};${_keytool} -keystore ${g_CLIENT_KEY_LOCATION%/}/${g_CLIENT_KEYSTORE_FILE} -alias ${_node} -import -file ${g_CLIENT_KEY_LOCATION%/}/${_node}-client.crt -noprompt -storepass ${_password}"
}

function f_spnego_hadoop() {
    local __doc__="set up HTTP Authentication for HDFS, YARN, MapReduce2, HBase, Oozie, Falcon and Storm"
    # http://docs.hortonworks.com/HDPDocuments/Ambari-2.4.2.0/bk_ambari-security/content/configuring_http_authentication_for_HDFS_YARN_MapReduce2_HBase_Oozie_Falcon_and_Storm.html
    local _realm="${1-$g_KDC_REALM}"
    local _domain="${2-${r_DOMAIN_SUFFIX#.}}"
    local _ambari_host="${3-$r_AMBARI_HOST}"
    local _ambari_port="${4-8080}"
    local _how_many="${5-$r_NUM_NODES}"
    local _start_from="${6-$r_NODE_START_NUM}"

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

    f_echo_restart_command "$_ambari_host" "$_ambari_port"
}

function f_ssl_ambari_2way() {
    local __doc__="TODO: Setup two way SSL (run f_ssl_hadoop first)"
    local _ambari_host="$1"
    local _password=${g_DEFAULT_PASSWORD:-hadoop}
    local _keys_dir="/var/lib/ambari-server/keys"
    local _node="${_ambari_host}"

    # 0. BACKUP and CLEANUP! Do not overwrite existing backup
    ssh -q root@${_ambari_host} "[ -d ${_keys_dir%/}.bak ]" && return $?
    ssh -q root@${_ambari_host} "cp -pr ${_keys_dir} ${_keys_dir%/}.bak" || return $?
    ssh -q root@${_ambari_host} "rm -f ${_keys_dir%/}/ca.key && rm -f ${_keys_dir%/}/*.{csr,crt} && rm -f ${_keys_dir%/}/keystore.p12 && rm -rf ${_keys_dir%/}/db/* && echo '00' > ${_keys_dir%/}/db/serial && > ${_keys_dir%/}/db/index.txt && > ${_keys_dir%/}/db/index.txt.attr && mkdir -m 700 ${_keys_dir%/}/db/newcerts && mkdir -m 700 ${_keys_dir%/}/db/certs" || return $?
    ssh -q root@${_ambari_host} "mkdir -m 700 ${_keys_dir}"
    ssh -q root@${_ambari_host} "echo "$_password" > ${_keys_dir%/}/pass.txt"

    # 1. cp (root) CA key and generate keystore.p12
    if [ ! -r ./rootCA.key ]; then
        echo "WARN: ./rootCA.key is not readable. Did you run f_ssl_hadoop?"
        echo "WARN: After 10 seconds, it will use ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE}"
        sleep 10

        # This ca.crt doesn't work as CA cert to generate new agent cert, however agent download this crt and use as truststore
        scp ./rootCA.pem root@${_ambari_host}:${_keys_dir%/}/ca.crt || return $?

        # 1.1. If keystore.p12 doesn't exist, convert .jks to .p12
        ssh -q root@${_ambari_host} "[ -f ${_keys_dir%/}/keystore.p12 ] || keytool -importkeystore -srckeystore ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE} -srcstorepass $_password -destkeystore ${_keys_dir%/}/keystore.p12 -deststoretype pkcs12 -deststorepass $_password" || return $?
        # 1.2. Export .key from .p12 , and this ca.key doesn't work to generate .csr, keystore.p12 etc. Probably don't need?
        ssh -q root@${_ambari_host} "openssl pkcs12 -in ${_keys_dir%/}/keystore.p12 -nocerts -out ${_keys_dir%/}/${_ambari_host}.key -passin pass:$_password -passout pass:$_password && cp ${_keys_dir%/}/${_ambari_host}.key ${_keys_dir%/}/ca.key" || return $?
        # 1.3. Export .crt from .p12
        ssh -q root@${_ambari_host} "openssl pkcs12 -in ${_keys_dir%/}/keystore.p12 -clcerts -nokeys -out ${_keys_dir%/}/${_ambari_host}.crt -passin pass:$_password" || return $?
        # 1.4. Add rootCA.pem into keystore.p12
        # NOTE: if Intermediate, merge the root CA and intermediate CA to one file (cat rootCA.crt interCA.crt > ca.crt)
        # NOTE: ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE_P12} should have rootCA already
    else
        # 1.1. copy local root ca key file to remote ambari-server node as ca.key
        scp ./rootCA.key root@${_ambari_host}:${_keys_dir%/}/ca.key || return $?
        # 1.2. generate ca.csr
        ssh -q root@${_ambari_host} "openssl req -passin pass:${_password} -new -key ${_keys_dir%/}/ca.key -out ${_keys_dir%/}/ca.csr -batch" || return $?
        # 1.3. generate ca.crt
        ssh -q root@${_ambari_host} "openssl ca -out ${_keys_dir%/}/ca.crt -days 1095 -keyfile ${_keys_dir%/}/ca.key -key ${_password} -selfsign -extensions jdk7_ca -config ${_keys_dir%/}/ca.config -subj '/C=AU/ST=QLD/O=Osakos/CN=RootCA.${_ambari_host}' -batch -infiles ${_keys_dir%/}/ca.csr" || return $?
        # 1.4. generate keystore.p12 which ambari uses as keystore and truststore if not specified
        ssh -q root@${_ambari_host} "openssl pkcs12 -export -in ${_keys_dir%/}/ca.crt -inkey ${_keys_dir%/}/ca.key -certfile ${_keys_dir%/}/ca.crt -out ${_keys_dir%/}/keystore.p12 -password pass:${_password} -passin pass:${_password}" || return $?
    fi
    # 1.5 Set correct permission
    ssh -q root@${_ambari_host} "chmod 600 ${_keys_dir%/}/*.{key,p12}"

    # 2. Update ambari.properties and restart
    ssh -q root@${_ambari_host} "grep -q '^security.server.two_way_ssl=true' /etc/ambari-server/conf/ambari.properties || echo -e '\nsecurity.server.two_way_ssl=true' >> /etc/ambari-server/conf/ambari.properties"
    ssh -q root@${_ambari_host} -t "ambari-server restart --skip-database-check"

    # 3. Clear agent's old certificate (and generate) TODO: Do this for all other agents
    ssh -q root@${_node} -t "rm -f /var/lib/ambari-agent/keys/*" || return $?
    if [ ! -r ./rootCA.key ]; then
        # 3.2. Same as ambair-server node, create .p12 from .jks file
        ssh -q root@${_node} "[ -f ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE_P12} ] || keytool -importkeystore -srckeystore ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE} -srcstorepass $_password -destkeystore ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE_P12} -deststoretype pkcs12 -deststorepass $_password && chmod 600 ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE_P12}" || return $?
        # 3.3. Export .key from .p12 and saved in to agent's keys dir (also removing passphrase as agent python can't read)
        ssh -q root@${_node} "openssl pkcs12 -in ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE_P12} -nocerts -out /var/lib/ambari-agent/keys/${_node}.tmp.key -passin pass:$_password -passout pass:$_password" || return $?
        ssh -q root@${_node} "openssl rsa -in /var/lib/ambari-agent/keys/${_node}.tmp.key -out /var/lib/ambari-agent/keys/${_node}.key -passin pass:$_password && rm -f /var/lib/ambari-agent/keys/${_node}.tmp.key" || return $?
        # 3.4. Export .crt from .p12 and saved in to agent's keys dir
        ssh -q root@${_node} "openssl pkcs12 -in ${g_SERVER_KEY_LOCATION%/}/${g_KEYSTORE_FILE_P12} -clcerts -nokeys -out /var/lib/ambari-agent/keys/${_node}.crt -passin pass:$_password" || return $?
    fi
    #for _i in {1..9}; do sleep 5; nc -z ${_ambari_host} 8080 && break; done
    ssh -q root@${_node} -t "ambari-agent restart" || return $?

    echo "Completed! To test, run below command on each node"
    echo 'echo -n | openssl s_client -connect '${_ambari_host}':8441 -CAfile /var/lib/ambari-agent/keys/ca.crt -cert /var/lib/ambari-agent/keys/`hostname -f`.crt -certform PEM -key /var/lib/ambari-agent/keys/`hostname -f`.key'
}

function f_ldap_ranger() {
    local __doc__="TODO: Setup ranger admin/usersync with LDAP (TODO: currently only tested with AD)"
    #f_ldap_ranger "ldap://winad.hdp.localdomain" "HDP.LOCALDOMAIN" "dc=hdp,dc=localdomain" "ldap@hdp.localdomain" '******' 'AD' 'sandbox-hdp.hortonworks.com'
    local _ldap_url="${1}"
    local _domain="${2}"
    local _basedn="${3}"
    local _binddn="${4}"
    local _binddn_pwd="${5:-${g_DEFAULT_PASSWORD:-hadoop}}" # TODO: password should be stoed in jceks file
    local _ad_or_ldap="${6:-AD}"
    local _ambari_host="${7:-${r_AMBARI_HOST}}"
    [ -z "${_ambari_host}" ] && return 1

    # NOTE: grep -E 'ranger\..*(\.usersync\..+attribute|\.objectclass|\.ldap\.|\.usersync\.source\.impl\.class|\.authentication\.method|enabled)' -A1 -IRs ./*-site.xml
    # TODO "ranger.ldap.user.dnpattern": "CN={0},CN=Users,'${_basedn}'"
    local ranger_admin_site='{
        "ranger.authentication.method": "ACTIVE_DIRECTORY",
        "ranger.ldap.ad.base.dn": "'${_basedn}'",
        "ranger.ldap.ad.domain": "'${_domain}'"
    }'
    f_ambari_configs "ranger-admin-site" "${ranger_admin_site}" "$_ambari_host"

    # NOTE: for AD, without setting 'ranger.usersync.ldap.searchBase', it seems to work, but just in case.
    local ranger_ugsync_site='{
        "ranger.usersync.group.memberattributename": "member",
        "ranger.usersync.group.nameattribute": "cn",
        "ranger.usersync.group.objectclass": "group",
        "ranger.usersync.group.search.first.enabled": "true",
        "ranger.usersync.group.searchbase": "'${_basedn}'",
        "ranger.usersync.group.searchfilter": "(objectClass=group)",
        "ranger.usersync.ldap.binddn": "'${_binddn}'",
        "ranger.usersync.ldap.ldapbindpassword": "'${_binddn_pwd}'",
        "ranger.usersync.ldap.searchBase": "'${_basedn}'",
        "ranger.usersync.ldap.url": "'${_ldap_url}'",
        "ranger.usersync.ldap.user.nameattribute": "sAMAccountName",
        "ranger.usersync.ldap.user.objectclass": "person",
        "ranger.usersync.ldap.user.searchbase": "cn=users,'${_basedn}'",
        "ranger.usersync.source.impl.class": "org.apache.ranger.ldapusersync.process.LdapUserGroupBuilder"
    }'

    # TODO: change attributes for LDAP
    if [ "LDAP" = "${_ad_or_ldap^^}" ]; then
        ranger_admin_site='{
            "ranger.authentication.method": "LDAP",
            "ranger.ldap.user.dnpattern": "uid={0},ou=users,'${_basedn}'",
            "ranger.ldap.group.searchfilter": "(member=uid={0},ou=Users,'${_basedn}')"
        }'
        local ranger_ugsync_site='{
            "ranger.usersync.group.memberattributename": "member",
            "ranger.usersync.group.nameattribute": "cn",
            "ranger.usersync.group.objectclass": "ipausergroup",
            "ranger.usersync.group.search.first.enabled": "true",
            "ranger.usersync.group.searchbase": "'${_basedn}'",
            "ranger.usersync.group.searchfilter": "(objectClass=group)",
            "ranger.usersync.ldap.binddn": "'${_binddn}'",
            "ranger.usersync.ldap.ldapbindpassword": "'${_binddn_pwd}'",
            "ranger.ldap.base.dn": "'${_basedn}'",
            "ranger.usersync.ldap.searchBase": "'${_basedn}'",
            "ranger.usersync.ldap.url": "'${_ldap_url}'",
            "ranger.usersync.ldap.user.nameattribute": "uid",
            "ranger.usersync.ldap.user.objectclass": "person",
            "ranger.usersync.ldap.user.searchbase": "ou=Users,'${_basedn}'",
            "ranger.usersync.source.impl.class": "org.apache.ranger.ldapusersync.process.LdapUserGroupBuilder"
        }'
    fi
    f_ambari_configs "ranger-ugsync-site" "${ranger_ugsync_site}" "$_ambari_host"

    _info 'ranger.truststore.alia, ranger.truststore.file, ranger.usersync.truststore.file, xasecure.policymgr.clientssl.truststore, xasecure.policymgr.clientssl.truststore may need to be changed'
    f_echo_restart_command "$_ambari_host"
}

function f_ldap_zeppelin() {
    local __doc__="TODO: Setup Zeppelin with (Knox Demo) LDAP or AD"
    # Ref: https://zeppelin.apache.org/docs/0.7.3/security/shiroauthentication.html#configure-realm-optional
    local _ldap_url="${1}"      # ldap://sandbox-hdp.hortonworks.com:33389
    local _search_base="${2}"   # ou=people,dc=hadoop,dc=apache,dc=org
    local _ad_or_ldap="${3}"    # If empty, LDAP
    local _ambari_host="${4-$r_AMBARI_HOST}"
    [ -z "${_ambari_host}" ] && return 1

    # ./configs.py -a get -l localhost -n Sandbox -u admin -p admin -c zeppelin-shiro-ini -k shiro_ini_content
    f_ambari_configs "zeppelin-shiro-ini" "" "$_ambari_host" || return $?
    if [ ! -s /tmp/zeppelin-shiro-ini_${__PID}.json ]; then
        _error "Couldn't get zeppelin-shiro-ini from ${_ambari_host}"
        return 1
    fi

    python -c "import json
a=json.load(open('/tmp/zeppelin-shiro-ini_${__PID}.json', 'r'))
print a['properties']['shiro_ini_content']" > /tmp/zeppelin-shiro-ini_${__PID}.ini || return $?

    # upserting in opposite order as it will be inserted after [main] if not exist
    _upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "shiro.loginUrl" "/api/login" "[main]" || return $?
    _upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "securityManager.sessionManager.globalSessionTimeout" "86400000" "[main]" || return $?
    _upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "securityManager.sessionManager" "\$sessionManager" "[main]" || return $?
    _upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "securityManager.cacheManager" "\$cacheManager" "[main]" || return $?
    _upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "cacheManager" "org.apache.shiro.cache.MemoryConstrainedCacheManager" "[main]" || return $?
    _upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "sessionManager" "org.apache.shiro.web.session.mgt.DefaultWebSessionManager" "[main]" || return $?
    if [ "${_ad_or_ldap^^}" = "AD" ]; then
        # TODO: need to test AD (also without below, gets NPE)
        #_upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "activeDirectoryRealm.groupRolesMap" "\"CN=Administrators,CN=Builtin,DC=hdp,DC=localdomain\":admin" "[main]" || return $?
        _upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "activeDirectoryRealm.searchBase" "${_search_base}" "[main]" || return $?
        _upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "activeDirectoryRealm.url" "${_ldap_url}" "[main]" || return $?
        _upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "activeDirectoryRealm" "org.apache.zeppelin.realm.ActiveDirectoryGroupRealm" "[main]" || return $?
        # no authenticationMechanism so need to use ldaps?
        #activeDirectoryRealm.systemUsername
        #activeDirectoryRealm.systemPassword
    else
        _upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "ldapRealm.contextFactory.authenticationMechanism" "simple" "[main]" || return $?
        _upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "ldapRealm.contextFactory.url" "${_ldap_url}" "[main]" || return $?
        _upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "ldapRealm.userDnTemplate" "uid={0},${_search_base}" "[main]" || return $?
        _upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "ldapRealm.contextFactory.environment[ldap.searchBase]" "${_search_base}" "[main]" || return $?
        _upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "ldapRealm" "org.apache.zeppelin.realm.LdapGroupRealm" "[main]" || return $?  # should use LdapRealm?
        #_upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "ldapRealm" "org.apache.shiro.realm.ldap.JndiLdapRealm" "[main]" # for older version (2.5)

        # TODO: adding system user enable LDAP pool as per org.apache.shiro.realm.ldap.JndiLdapContextFactory#isPoolingConnections
        #ldapRealm.contextFactory.systemUsername=uid=admin,,ou=people,dc=hadoop,dc=apache,dc=org
        #ldapRealm.contextFactory.systemPassword=admin-password
    fi
    _upsert "/tmp/zeppelin-shiro-ini_${__PID}.ini" "/**" "authc" "[urls]" || return $?

    if [ ! -s ./configs.py ]; then
        curl -s -O https://raw.githubusercontent.com/hajimeo/samples/master/misc/configs.py || return $?
    fi
    local _c="`f_get_cluster_name $_ambari_host`" || return $?

    #sed '{:q;N;s/\n/\\n/g;t q}' /tmp/zeppelin-shiro-ini_${__PID}.ini
    python ./configs.py -u "${g_admin}" -p "${g_admin_pwd}" -l ${_ambari_host} -t 8080 -a set -n ${_c} -c "zeppelin-shiro-ini" -k "shiro_ini_content" -v "`cat /tmp/zeppelin-shiro-ini_${__PID}.ini`" /tmp/zeppelin-shiro-ini_${__PID}.ini || return $?
    python ./configs.py -u "${g_admin}" -p "${g_admin_pwd}" -l ${_ambari_host} -t 8080 -a set -n ${_c} -c "zeppelin-config" -k "zeppelin.anonymous.allowed" -v "false" /tmp/zeppelin-shiro-ini_${__PID}.ini || return $?
    rm -f ./doSet_version*.json

    f_echo_restart_command "$_ambari_host"
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

function f_ldap_hadoop_groupmapping() {
    local __doc__="Setup Hadoop Group Mapping with LDAP/AD"
    #f_ldap_hadoop_groupmapping "ldap://winad.hdp.localdomain" "HDP.LOCALDOMAIN" "dc=hdp,dc=localdomain" "ldap@hdp.localdomain" '******' 'AD' 'sandbox-hdp.hortonworks.com'
    local _ldap_url="${1}"
    local _domain="${2}"
    local _basedn="${3}"    # dc=hadoop,dc=apache,dc=org
    local _bind_user="${4}"    # uid=admin,ou=people,${_basedn}
    local _bind_pass="${5:-${g_DEFAULT_PASSWORD:-hadoop}}" # admin-password
    local _ad_or_ldap="${6:-AD}"
    local _ambari_host="${7:-${r_AMBARI_HOST}}"

    [ -z "${_ambari_host}" ] && return 1
    [ -z "${_ldap_url}" ] && _ldap_url="ldap://${_ambari_host}:33389/"

    local _final_ldap_url="${_ldap_url%/}/"
    local _final_basedn="${_basedn}"
    local _filter_user="(&(objectclass=person)(sAMAccountName={0}))"
    local _filter_group="(objectClass=group)"
    local _test_user="administrator"
    local _attr_member="member"
    local _attr_group_name="cn"

    if [ "LDAP" = "${_ad_or_ldap^^}" ]; then
        _final_ldap_url="${_ldap_url%/}/${_basedn}"  # NOTE/TODO: somehow base need to be empty and need to use basedn in ldap URL
        _final_basedn=""
        _filter_user="(&(objectclass=person)(uid={0}))"
        _filter_group="(objectclass=ipausergroup)"
        _test_user="admin"
    fi

    if which ldapsearch &>/dev/null; then
        local _filter_user_test="`echo ${_filter_user} | sed 's/{0}/'${_test_user}'/'`"
        LDAPTLS_REQCERT=never ldapsearch -x -H ${_ldap_url} -D "${_bind_user}" -w "${_bind_pass}" -b "${_basedn}" "${_filter_user_test}" || return $?
        LDAPTLS_REQCERT=never ldapsearch -x -H ${_ldap_url} -D "${_bind_user}" -w "${_bind_pass}" -b "${_basedn}" "${_filter_group}" ${_attr_member} ${_attr_group_name} || return $?
    fi

    # TODO: encrypt password (on both NamdeNode and ... all nodes which use ranger plugin?)
    # hadoop credential create hadoop.security.group.mapping.ldap.bind.password -value admin-password -provider jceks://file/etc/hadoop/hadoop/conf/core-site.jceks; chmod a+r /etc/hadoop/hadoop/conf/core-site.jceks
    #    "hadoop.security.credential.provider.path":"/etc/hadoop/hadoop/conf/core-site.jceks",
    local core_site='{
        "hadoop.security.group.mapping":"org.apache.hadoop.security.CompositeGroupsMapping",
        "hadoop.security.group.mapping.providers":"shell4services,ldap4users",
        "hadoop.security.group.mapping.provider.shell4services":"org.apache.hadoop.security.ShellBasedUnixGroupsMapping",
        "hadoop.security.group.mapping.provider.ldap4users":"org.apache.hadoop.security.LdapGroupsMapping",
        "hadoop.security.group.mapping.provider.ldap4users.ldap.url":"'${_final_ldap_url}'",
        "hadoop.security.group.mapping.provider.ldap4users.ldap.bind.user":"'${_bind_user}'",
        "hadoop.security.group.mapping.provider.ldap4users.ldap.base":"'${_final_basedn}'",
        "hadoop.security.group.mapping.provider.ldap4users.ldap.search.filter.user":"'${_filter_user}'",
        "hadoop.security.group.mapping.provider.ldap4users.ldap.search.filter.group":"'${_filter_group}'",
        "hadoop.security.group.mapping.provider.ldap4users.ldap.search.attr.member":"'${_attr_member}'",
        "hadoop.security.group.mapping.provider.ldap4users.ldap.search.attr.group.name":"'${_attr_group_name}'"
    }'

    f_ambari_configs "core-site" "${core_site}" "${_ambari_host}" || return $?
    # NOTE: 'properties_attributes' is like below:
    # "properties_attributes":{"final":{"fs.defaultFS":"true"},"password":{"hadoop.security.group.mapping.provider.ldap4users.ldap.bind.password":"true"},"user":{},"group":{},"text":{},"additional_user_property":{},"not_managed_hdfs_path":{},"value_from_property_file":{}}
    f_ambari_configs_py_password "core-site" "hadoop.security.group.mapping.provider.ldap4users.ldap.bind.password" "${_bind_pass}" "${_ambari_host}" || return $?

    f_echo_restart_command "$_ambari_host"
    #echo "sudo -u hdfs -i hdfs dfsadmin -refreshUserToGroupsMappings"
    #echo "sudo -u yarn -i yarn rmadmin -refreshUserToGroupsMappings"
}

function f_ldap_ambari() {
    local __doc__="Setup Ambari Server with LDAP (for Knox SSO) (TODO: currently works only with Knox demo LDAP)"
    # r_AMBARI_HOST="sandbox-hdp.hortonworks.com" f_ldap_ambari
    local _ldap_host="$1"
    local _ldap_port="$2"
    local _ambari_host="${3-$r_AMBARI_HOST}"
    [ -z "${_ambari_host}" ] && return 1

    [ -z "${_ldap_host}" ] && _ldap_host="${_ambari_host}"
    [ -z "${_ldap_port}" ] && _ldap_port="33389"    # TODO: currently default is knox demo ldap

    ssh -q root@${_ambari_host} -t "ambari-server setup-ldap --ldap-url=${_ldap_host}:${_ldap_port} --ldap-user-class=person --ldap-user-attr=uid --ldap-group-class=ipausergroup --ldap-ssl=false --ldap-secondary-url="" --ldap-referral="" --ldap-group-attr=cn --ldap-member-attr=member --ldap-dn=dn --ldap-base-dn=dc=hadoop,dc=apache,dc=org --ldap-bind-anonym=false --ldap-manager-dn=uid=admin,ou=people,dc=hadoop,dc=apache,dc=org --ldap-manager-password=admin-password　--ldap-sync-username-collisions-behavior=skip --ldap-save-settings && echo 'authentication.ldap.pagination.enabled=false' >> /etc/ambari-server/conf/ambari.properties && ambari-server restart --skip-database-check"

    _info "Once Ambari Server is ready, run the following command"
    f_echo_start_demoldap "${_ldap_host}" "${_ambari_host}"
    echo "ssh -q root@${_ambari_host} -t 'ambari-server sync-ldap --ldap-sync-admin-name=admin --ldap-sync-admin-password=admin --all'"
    # NOTE: --verbose outputs below
    # Calling API http://127.0.0.1:8080/api/v1/ldap_sync_events : [{'Event': {'specs': [{'principal_type': 'users', 'sync_type': 'all'}, {'principal_type': 'groups', 'sync_type': 'all'}]}}]
}

function f_ldap_server_install_on_host() {
    local __doc__="Install LDAP server packages on Ubuntu (need to test setup)"
    local _shared_domain="$1"
    local _password="${2-${g_DEFAULT_PASSWORD:-"hadoop"}}"

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
        curl -H "accept-encoding: gzip" https://raw.githubusercontent.com/hajimeo/samples/master/misc/example.ldif -o /tmp/example.ldif || return $?
        ldapadd -x -D cn=admin,dc=example,dc=com -w hadoop -f /tmp/example.ldif
    fi
}

function f_ldap_server_install_on_ambari_node() {
    local __doc__="TODO: CentOS6 only: Install LDAP server packages for sssd (security lab)"
    local _ldap_domain="$1"
    local _password="${2-${g_DEFAULT_PASSWORD:-"hadoop"}}"
    local _server="${3-$r_AMBARI_HOST}"

    if [ -z "$_ldap_domain" ]; then
        _warn "No LDAP Domain, so using dc=example,dc=com"
        _ldap_domain="dc=example,dc=com"
    fi

    # slapd ldapsearch install TODO: chkconfig slapd on wouldn't do anything on docker container
    ssh -q root@$_server -t "yum install openldap openldap-servers openldap-clients -y" || return $?
    ssh -q root@$_server -t "cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG ; chown ldap. /var/lib/ldap/DB_CONFIG && /etc/rc.d/init.d/slapd start" || return $?
}

function f_ldap_server_configure() {
    local __doc__="TODO: Configure LDAP server via SSH (requires password-less ssh)"
    local _ldap_domain="$1"
    local _password="${2-${g_DEFAULT_PASSWORD:-"hadoop"}}"
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
    local _how_many="${3-$r_NUM_NODES}"    # Integer or client hostname
    local _start_from="${4-$r_NODE_START_NUM}"
    local _force="${5}"

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
    if [[ "$_how_many" =~ ^[0-9]+$ ]]; then
        for i in `_docker_seq "$_how_many" "$_start_from"`; do
            f_freeipa_client_install node${i} "${_ipa_server_fqdn}" "${_password}" "${_force}"
        done
    elif [ -n "${_how_many}" ]; then
        local _client_hostname="${_how_many}"
        f_freeipa_client_install "${_client_hostname}" "${_ipa_server_fqdn}" "${_password}" "${_force}"
    fi

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
    local _p12_pass="${4:-${g_DEFAULT_PASSWORD:-"hadoop"}}"
    local _adm_pwd="${5:-$g_FREEIPA_DEFAULT_PWD}"
    # example of generating p12.
    #openssl pkcs12 -export -chain -CAfile rootCA_standalone.crt -in standalone.localdomain.crt -inkey standalone.localdomain.key -name standalone.localdomain -out standalone.localdomain.p12 -passout pass:hadoop

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
    # f_sssd_setup administrator '******' 'hdp.localdomain' 'adhost.hdp.localdomain' 'dc=hdp,dc=localdomain' 'hadoop' 'sandbox-hdp.hortonworks.com' 'sandbox-hdp.hortonworks.com'
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

function f_ssl_self_signed_cert() {
    local __doc__="DEPRECATED: Setup a self-signed certificate with openssl command. See: http://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.5.3/bk_security/content/set_up_ssl_for_ambari.html"
    local _subject="$1" # "/C=AU/ST=QLD/O=Osakos/CN=*.`hostname -s`.localdomain"
    local _base_name="${2-selfsign}"
    local _password="$3"
    local _key_strength="${4-2048}"
    local _work_dir="${5-./}"
    local _subj=""

    if [ -z "$_password" ]; then
        _password="${g_DEFAULT_PASSWORD:-hadoop}"
    fi
    if [ -n "$_subject" ]; then
        _subj="-subj ${_subject}"
    fi

    # Create a private key NOTE: -aes256 to encrypt
    openssl genrsa -out ${_work_dir%/}/${_base_name}.key $_key_strength || return $?
    # Generate cert from above key (TODO: need SAN for chrome)
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
        _dname="CN=internalca${_domain_suffix}, OU=Lab, O=Osakos, L=Brisbane, ST=QLD, C=AU"
    fi
    if [ -z "$_password" ]; then
        _password="${g_DEFAULT_PASSWORD:-hadoop}"
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
    [ -z "$_dname" ] && _dname="CN=*.${_domain_suffix#.}, OU=Lab, O=Osakos, L=Brisbane, ST=QLD, C=AU"
    [ -z "$_password" ] && _password=${g_DEFAULT_PASSWORD:-hadoop}

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

function f_ambari_configs_py_password() {
    local __doc__="Wrapper function of configs.py for updating one PASSWORD type property"
    local _type="$1"
    local _key="$2"
    local _value="$3"
    local _ambari_host="${4-$r_AMBARI_HOST}"
    local _ambari_port="${5-8080}"
    local _c="${6}"
    [ -z "$_c" ] && _c="`f_get_cluster_name $_ambari_host`" || return $?

    if [ ! -s ./configs.py ]; then
        curl -s -O https://raw.githubusercontent.com/hajimeo/samples/master/misc/configs.py || return $?
    fi

    python ./configs.py -u "${g_admin}" -p "${g_admin_pwd}" -l ${_ambari_host} -t ${_ambari_port} -a set -n ${_c} -c ${_type} -k "${_key}" -v "${_value}" -z "PASSWORD" || return $?
    rm -f ./doSet_version*.json
}

function f_ambari_configs() {
    local __doc__="Wrapper function to get and update *multiple* configs with configs.py"
    local _type="$1"
    local _dict="$2"
    local _ambari_host="${3-$r_AMBARI_HOST}"
    local _ambari_port="${4-8080}"
    local _c="${5}"
    [ -z "$_c" ] && _c="`f_get_cluster_name $_ambari_host`" || return $?

    if [ ! -s ./configs.py ]; then
        curl -s -O https://raw.githubusercontent.com/hajimeo/samples/master/misc/configs.py || return $?
    fi

    python ./configs.py -u "${g_admin}" -p "${g_admin_pwd}" -l ${_ambari_host} -t ${_ambari_port} -a get -n ${_c} -c ${_type} -f /tmp/${_type}_${__PID}.json || return $?

    if [ -z "${_dict}" ]; then
        _info "No _dict given, so that exiting in here (just get/download)"
        return 0
    fi

    echo "import json
a=json.load(open('/tmp/${_type}_${__PID}.json', 'r'))
n=json.loads('"${_dict}"')
a['properties'].update(n)
f=open('/tmp/${_type}_updated_${__PID}.json','w')
json.dump(a, f)
f.close()" > /tmp/configs_${__PID}.py

    python /tmp/configs_${__PID}.py || return $?
    python ./configs.py -u "${g_admin}" -p "${g_admin_pwd}" -l ${_ambari_host} -t ${_ambari_port} -a set -n ${_c} -c $_type -f /tmp/${_type}_updated_${__PID}.json || return $?
    rm -f ./doSet_version*.json
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

function f_echo_restart_command() {
    local __doc__="Output stale config restart API command"
    local _ambari_host="${1-$r_AMBARI_HOST}"
    local _ambari_port="${2-8080}"
    local _c="`f_get_cluster_name $_ambari_host`" || return $?

    # If Ambari is 2.4.x or higher below works
    _info "Run the below command to restart *ALL* required components (AMBARI-18450 doesn't work as expected)"
    echo "curl -si -u ${g_admin}:${g_admin_pwd} -H 'X-Requested-By:ambari' 'http://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_c}/requests' -X POST --data '{\"RequestInfo\":{\"command\":\"RESTART\",\"context\":\"Restart all required services\",\"operation_level\":\"host_component\"},\"Requests/resource_filters\":[{\"hosts_predicate\":\"HostRoles/stale_configs=true\"}]}'"
}

function f_echo_start_demoldap() {
    local __doc__="Output Knox Demo LDAP start command"
    local _knox_host="${1}"
    local _ambari_host="${2-$r_AMBARI_HOST}"
    local _ambari_port="${3-8080}"
    local _c="`f_get_cluster_name $_ambari_host`" || return $?

    echo "curl -si -u ${g_admin}:${g_admin_pwd} -H 'X-Requested-By:ambari' 'http://${_ambari_host}:${_ambari_port}/api/v1/clusters/${_c}/requests' -X POST --data '{\"RequestInfo\":{\"context\":\"Start Demo LDAP\",\"command\":\"STARTDEMOLDAP\"},\"Requests/resource_filters\":[{\"service_name\":\"KNOX\",\"component_name\":\"KNOX_GATEWAY\",\"hosts\":\"${_knox_host}\"}]}'"
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
    g_SETUP_HOST="_setup_host.sh"
    # sourcing required script
    if [ ! -s "./${g_SETUP_HOST}" ]; then
        echo "${g_SETUP_HOST} is missing. Downloading..."
        curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/${g_SETUP_HOST} -o ./${g_SETUP_HOST}
    fi
    source ./${g_SETUP_HOST}

    g_START_HDP_SH="start_hdp.sh"
    # TODO: assuming g_SCRIPT_NAME contains a right filename or can be empty
    if [ ! -s "./$g_START_HDP_SH" ]; then
        echo "start_hdp.sh is missing. Downloading..."
        curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/$g_START_HDP_SH -o "./$g_START_HDP_SH"
    fi
    source "./$g_START_HDP_SH"
fi