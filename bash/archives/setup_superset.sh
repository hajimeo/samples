#!/usr/bin/env bash

# Expecting CentOS 7
# https://superset.incubator.apache.org/installation.html
#
# To create a container
#   . ./setup_standalone.sh
#   f_docker_run superset.standalone.localdomain


function f_install_required() {
    # Superset required
    sudo yum install -y gcc gcc-c++ libffi-devel openssl-devel libsasl2-devel openldap-devel || return $?
}

function f_install_python3() {
    sudo yum install -y https://centos7.iuscommunity.org/ius-release.rpm
    #yum search python36
    sudo yum install -y python36u python36u-libs python36u-devel python36u-pip python36u-setuptools || return $?
    #ln -sf /usr/bin/python2 /usr/bin/python
    #ln -sf /usr/bin/python36 /usr/bin/python
}

function p_install_superset() {
    f_install_required || return $?
    f_install_python3 || return $?
    # After installing python 3.6, no pip, but pip3.6. Aftter --upgrade pip, it will create 'pip'
    pip3.6 install --upgrade setuptools pip

    pip install superset || return $?

    # Create an admin user (you will be prompted to set username, first and last name before setting a password)
    fabmanager create-admin --app superset --username "admin" --firstname "admin" --lastname "user" --email "root@localhost" --password "admin" || return $?
    # Initialize the database
    superset db upgrade || return $?
    # Load some data to play with
    superset load_examples || return $?
    # Create default roles and permissions
    superset init || return $?
}



if [ "$0" = "$BASH_SOURCE" ]; then
    if ! which superset &>/dev/null; then
        p_install_superset
    fi

    _PORT="${1:-8088}"
    nohup superset runserver -d -p $_PORT &> /tmp/superset.out &
    sleep 3
    grep -m 1 -w $_PORT /tmp/superset.out
fi