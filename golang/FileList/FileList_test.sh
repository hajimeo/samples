#!/usr/bin/env bash

# Download automate scripts
source /dev/stdin <<<"$(curl -sf "https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils.sh" --compressed)" || return $?
source /dev/stdin <<<"$(curl -sf "https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils_db.sh" --compressed)" || return $?
source /dev/stdin <<<"$(curl -sf "https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_nexus3_repos.sh" --compressed)" || return $?

# Global variables
_FILE_LIST="${1}"   # If not specified, will try from the PATH
_DBUSER="${2:-"nxrm"}"
_DBPWD="${3:-"${_DBUSER}123"}"
_DBNAME="${4:-"${_DBUSER}test"}"    # Use some unique name (lowercase)
_VER="${5:-"3.40.1-01"}"            # Specify your nexus version
_NEXUS_TGZ_DIR="${6:-"$HOME/.nexus_executable_cache"}"

_TEST_REPO_NAME="raw-hosted"
_ASSET_CREATE_NUM=1000
_PID=""
_AWS_S3_BUCKET="apac-support-bucket"
_AWS_S3_PREFIX="filelist_test"
#_FORCE="N"
#_IS_S3="N"

function TestFileList() {
    local _expected_num="${1:-0}"
    local _bsName="${2:-"default"}"

    if [ 10 -gt ${_expected_num} ]; then
        _log "WARN" "_expected_num (${_expected_num}) might be incorrect"
    fi

    local _opt="-b ./sonatype-work/nexus3/blobs/${_bsName}/content -p vol-"
    [[ "${_IS_S3}" =~ ^[yY] ]] && _opt="-b ${_AWS_S3_BUCKET} -p ${_AWS_S3_PREFIX%/}/content/vol- -S3"
    _log "INFO" "Executing '${_FILE_LIST} ${_opt} -c 10 -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -RF -bsName ${_bsName}'"
    time ${_FILE_LIST} ${_opt} -c 10 -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -RF -bsName ${_bsName} -X >./file-list.out 2>./file-list.log || return $?
     local _file_list_ln="$(cat ./file-list.out | wc -l | tr -d '[:space:]')"

     if [ 0 -eq ${_file_list_ln} ]; then
         _log "ERROR" "Test failed. file-list didn't find any blobs (${_file_list_ln})"
     fi

     if [ ${_file_list_ln} -gt ${_expected_num} ] || [ ${_file_list_ln} -lt ${_ASSET_CREATE_NUM} ]; then
         _log "ERROR" "Test failed. file-list.out line number ${_file_list_ln} is not between ${_ASSET_CREATE_NUM} and ${_expected_num}"
     fi

     if type rg &>/dev/null; then
         if [[ ! "${_IS_S3}" =~ ^[yY] ]] && rg -g '*.properties' -l '^deleted=true' ./sonatype-work/nexus3/blobs/${_bsName}/content/vol-*; then
             _log "ERROR" "Test failed. with '-RDel', rg shouldn't find any file."
         fi
     fi

     # Some metadata can not be deleted with API so actual_file_sorted would have more
     #find ./sonatype-work/nexus3/blobs/${_bsName}/content/vol-* -name '*.properties' | rg '[0-9a-f\-]{20,}' -o | sort > actual_file_sorted.out

     _log "INFO" "${_file_list_ln} of ${_expected_num} are found by file-list"
     echo "Manual test: "
     echo "    Start this nexus and wait or run *all* 'Cleanup unused asset blob' tasks."
     echo "    Re-run file-list command to make sure 'deleted=true' is removed."
     echo "    ${_FILE_LIST} ${_opt} -c 10 -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -RF -bsName ${_bsName} -dF $(date '+%Y-%m-%d') -RDel -X > ./file-list_del.out 2> ./file-list_del.log"
     echo "    Run the Reconcile with Since 1 days and with file-list.out."
}

function main() {
    local _os="linux"
    [ "`uname`" = "Darwin" ] && _os="mac"

    if [ -z "${_FILE_LIST}" ]; then
        if type file-list &>/dev/null; then
            _FILE_LIST="file-list"
        else
            _log "ERROR" "No file-list binary found."
            return 1
        fi
    fi

    # Not perfect test but better than not checking...
    if psql -l | grep -q "^ ${_DBNAME} "; then
        _log "WARN" "Database ${_DBNAME} exists (_FORCE = ${_FORCE})"
        if [[ ! "${_FORCE}" =~ ^[yY] ]]; then
            echo "To force, set _FORCE=\"Y\" env variable (but may not start due to Nuget repository)." >&2
            return 1
        else
            sleep 3
            PGPASSWORD="${_DBPWD}" psql -U ${_DBUSER} -h $(hostname -f) -p 5432 -d template1 -c "DROP DATABASE ${_DBNAME}" || return $?
        fi
    fi

    if [ -d "nxrm-${_VER}" ]; then
        _log "WARN" "nxrm-${_VER} exists (_FORCE = ${_FORCE})"
        if [[ ! "${_FORCE}" =~ ^[yY] ]]; then
            echo "To force, set _FORCE=\"Y\" env variable." >&2
            return 1
        else
            sleep 3
            rm -rf "nxrm-${_VER}" || return $?
        fi
    fi

    mkdir -v nxrm-${_VER} || return $?
    cd nxrm-${_VER} || return $?

    if [ ! -s "nexus-${_VER}/bin/nexus" ]; then
        if [ ! -s "${_NEXUS_TGZ_DIR%/}/nexus-${_VER}-${_os}.tgz" ]; then
            _log "ERROR" "${_NEXUS_TGZ_DIR%/}/nexus-${_VER}-${_os}.tgz does not exist."
            return 1
        fi
        _log "INFO" "Extracting ${_NEXUS_TGZ_DIR%/}/nexus-${_VER}-${_os}.tgz ..."
        tar -xf "${_NEXUS_TGZ_DIR%/}/nexus-${_VER}-${_os}.tgz" || return $?
    fi

    _postgresql_create_dbuser "${_DBUSER}" "${_DBPWD}" "${_DBNAME}" || return $?

    if [ ! -d "./sonatype-work/nexus3/etc/fabric" ]; then
        mkdir -v -p ./sonatype-work/nexus3/etc/fabric || return $?
    fi
    if [ ! -s "./sonatype-work/nexus3/etc/nexus.properties" ]; then
        touch "./sonatype-work/nexus3/etc/nexus.properties"
    fi
    local _port="$(_find_port "18081")"
    _upsert "./sonatype-work/nexus3/etc/nexus.properties" "application-port" "${_port}" || return $?
    _upsert "./sonatype-work/nexus3/etc/nexus.properties" "nexus.datastore.enabled" "true" || return $?
    _upsert "./sonatype-work/nexus3/etc/nexus.properties" "nexus.security.randompassword" "false" || return $?
    _upsert "./sonatype-work/nexus3/etc/nexus.properties" "nexus.onboarding.enabled" "false" || return $?
    _upsert "./sonatype-work/nexus3/etc/nexus.properties" "nexus.scripts.allowCreation" "true" || return $?

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
    _PID=$!
    #tail -f ./sonatype-work/nexus3/log/nexus.log

    # Wait until port is ready
    export _NEXUS_URL="http://localhost:${_port}/"
    _log "INFO" "Waiting ${_NEXUS_URL} ..."
    _wait_url "${_NEXUS_URL}" || return $?

    # Below line creates various repositories with a few dummy assets, but not using as this is not for testing Reconcile
    #_AUTO=true main

    if [[ "${_IS_S3}" =~ ^[yY] ]]; then
        export _BLOBTORE_NAME="s3-test"
        _log "INFO" "Creating ${_BLOBTORE_NAME} (this also creates 'raw-s3-hosted' repo)..."
        f_create_s3_blobstore "${_BLOBTORE_NAME}" "${_AWS_S3_PREFIX}" "${_AWS_S3_BUCKET}" || return $?    # other params use AWS_XXXX env variables
        _TEST_REPO_NAME="raw-s3-hosted"
    else
        f_setup_raw || return $?
    fi
    f_upload_dummies "${_NEXUS_URL%/}/repository/${_TEST_REPO_NAME}/test" "${_ASSET_CREATE_NUM}" || return $?

    f_delete_all_assets "Y"
    local _expected_num=$(cat /tmp/f_delete_all_assets_$$.out | wc -l | tr -d '[:space:]')

    # For measuring the time of your restoring command, delete Linux (file) cache
    #sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'

    TestFileList "${_expected_num}" "${_BLOBTORE_NAME}"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main
    if [ -n "${_PID}" ]; then
        _log "INFO" "Stopping Nexus (${_PID}) ..."
        sleep 3
        kill ${_PID}
    fi
fi