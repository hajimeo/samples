#!/usr/bin/env bash
#
# Demo script: setup Group Mapping with Knox Demo LDAP
#

if ! which python &>/dev/null; then
    echo "Python is required"
    exit
fi

_CLUSTER=Sandbox
_ADMIN=admin
_ADM_PWD=admin

# Always download the latest one
curl -O https://raw.githubusercontent.com/hajimeo/samples/master/misc/configs.py
python ./configs.py -a set -l localhost -n ${_CLUSTER} -u ${_ADMIN} -p ${_ADM_PWD} -c core-site -k "hadoop.security.group.mapping.ldap.bind.password" -v "admin-password" -z "PASSWORD"

python ./configs.py -a set -l localhost -n ${_CLUSTER} -u ${_ADMIN} -p ${_ADM_PWD} -c core-site -k "hadoop.security.group.mapping" -v "org.apache.hadoop.security.LdapGroupsMapping"
python ./configs.py -a set -l localhost -n ${_CLUSTER} -u ${_ADMIN} -p ${_ADM_PWD} -c core-site -k "hadoop.security.group.mapping.ldap.bind.user" -v "uid=admin,ou=people,dc=hadoop,dc=apache,dc=org"
python ./configs.py -a set -l localhost -n ${_CLUSTER} -u ${_ADMIN} -p ${_ADM_PWD} -c core-site -k "hadoop.security.group.mapping.ldap.url" -v "ldap://sandbox-hdp.hortonworks.com:33389/dc=hadoop,dc=apache,dc=org"
python ./configs.py -a set -l localhost -n ${_CLUSTER} -u ${_ADMIN} -p ${_ADM_PWD} -c core-site -k "hadoop.security.group.mapping.ldap.base" -v ""
python ./configs.py -a set -l localhost -n ${_CLUSTER} -u ${_ADMIN} -p ${_ADM_PWD} -c core-site -k "hadoop.security.group.mapping.ldap.search.filter.user" -v "(uid={0})"
python ./configs.py -a set -l localhost -n ${_CLUSTER} -u ${_ADMIN} -p ${_ADM_PWD} -c core-site -k "hadoop.security.group.mapping.ldap.search.filter.group" -v "(objectclass=groupOfNames)"
python ./configs.py -a set -l localhost -n ${_CLUSTER} -u ${_ADMIN} -p ${_ADM_PWD} -c core-site -k "hadoop.security.group.mapping.ldap.search.attr.member" -v "member"
python ./configs.py -a set -l localhost -n ${_CLUSTER} -u ${_ADMIN} -p ${_ADM_PWD} -c core-site -k "hadoop.security.group.mapping.ldap.search.attr.group.name" -v "cn"

# To test, after restarting services, run "sudo -u hdfs -i hdfs groups sam"
