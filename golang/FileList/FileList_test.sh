#!/usr/bin/env bash

# Specify your nexus version
_FILE_LIST="${1}"   # If not specified, will try from the PATH
_DBUSER="${2:-"nxrm"}"
_DBPWD="${3:-"${_DBUSER}123"}"
_DBNAME="${4:-"${_DBUSER}test"}"    # Use some unique name (lowercase)
_VER="${5:-"3.40.1-01"}"
_NEXUS_TGZ_DIR="${6:-"$HOME/.nexus_executable_cache"}"
#_FORCE=""

function main() {
    local _os="linux"
    [ "`uname`" = "Darwin" ] && _os="mac"

    if [ -z "${_FILE_LIST}" ]; then
        if type file-list &>/dev/null; then
            _FILE_LIST="file-list"
        else
            echo "No file-list binary found." >&2;
            return 1
        fi
    fi

    # Not perfect test but better than not checking...
    if psql -l | grep -q "^ ${_DBNAME} "; then
        echo "Database ${_DBNAME} exists." >&2
        if [[ ! "${_FORCE}" =~ ^[yY] ]]; then
            echo "To force, set _FORCE=\"Y\" env variable (but may not start due to Nuget repository)." >&2
            return 1
        fi
    fi

    if [ -d "nxrm-${_VER}" ]; then
        echo "nxrm-${_VER} exists." >&2
        if [[ ! "${_FORCE}" =~ ^[yY] ]]; then
            echo "To force, set _FORCE=\"Y\" env variable." >&2
            return 1
        fi
    else
        mkdir -v nxrm-${_VER} || return $?
    fi
    cd nxrm-${_VER} || return $?

    if [ ! -s "${_NEXUS_TGZ_DIR%/}/nexus-${_VER}-${_os}.tgz" ]; then
        echo "${_NEXUS_TGZ_DIR%/}/nexus-${_VER}-${_os}.tgz does not exist." >&2
        return 1
    fi

    if [ ! -s "nexus-${_VER}/bin/nexus" ]; then
        tar -xvf "${_NEXUS_TGZ_DIR%/}/nexus-${_VER}-${_os}.tgz" || return $?
    fi
    mkdir -v -p ./sonatype-work/nexus3/etc/fabric || return $?
    echo "nexus.security.randompassword=false" >>"./sonatype-work/nexus3/etc/nexus.properties"
    echo "nexus.onboarding.enabled=false" >>"./sonatype-work/nexus3/etc/nexus.properties"
    echo "nexus.scripts.allowCreation=true" >>"./sonatype-work/nexus3/etc/nexus.properties"
    echo "nexus.datastore.enabled=true" >>"./sonatype-work/nexus3/etc/nexus.properties"

    # Download some automate script to create repositories and dummy assets
    source /dev/stdin <<<"$(curl "https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_nexus3_repos.sh" --compressed)" || return $?
    source /dev/stdin <<<"$(curl "https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils_db.sh" --compressed)"
    _postgresql_create_dbuser "${_DBUSER}" "${_DBPWD}" "${_DBNAME}" || return $?
    cat <<EOF > ./sonatype-work/nexus3/etc/fabric/nexus-store.properties
name=nexus
type=jdbc
jdbcUrl=jdbc\:postgresql\://$(hostname -f)\:5432/${_DBNAME}
username=${_DBUSER}
password=${_DBPWD}
maximumPoolSize=40
advanced=maxLifetime\=600000
EOF

    # Start your nexus. You can also use "nexus run"
    ./nexus-${_VER}/bin/nexus run &> ./nexus_run.out &
    local _wpid=$!
    #tail -f ./sonatype-work/nexus3/log/nexus.log

    # Wait until port is ready
    export _NEXUS_URL='http://localhost:8081/'
    echo "Waiting ${_NEXUS_URL} ..." >&2
    _wait_url "${_NEXUS_URL}" || return $?
    _AUTO=true main

    sleep 3
    # Delete all dummy assets as we are going to restore with this KB:
    f_delete_all_assets "Y"

    echo "Stopping Nexus (${_wpid}) ..." >&2
    kill ${_wpid}
    local _line_num="$(cat /tmp/f_delete_all_assets_$$.out | wc -l | tr -d '[:space:]')"

    # For measuring the time of your restoring command, delete Linux (file) cache
    #sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
    time ${_FILE_LIST} -b ./sonatype-work/nexus3/blobs/default/content -p vol- -c 10 -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -RF -RDel > ./file-list.out
     2> ./file-list.log
     local _file_list_ln="$(cat ./file-list.out | wc -l | tr -d '[:space:]')"
     if [ "${_line_num}" != "${_file_list_ln}" ]; then
         # TODO: at this moment this test fails because no record in <format>_asset but exist in <format>_asset_blob
         echo "ERROR Test failed. file-list.out line number is not ${_line_num}" >&2
         return 11
     fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main
fi