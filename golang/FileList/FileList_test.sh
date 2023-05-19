#!/usr/bin/env bash
# FileList system testing
#   _FORCE=Y _WITH_S3=Y ./FileList_test.sh

# Download automate scripts
source /dev/stdin <<<"$(curl -sfL "https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils.sh" --compressed)" || return $?
source /dev/stdin <<<"$(curl -sfL "https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils_db.sh" --compressed)" || return $?
source /dev/stdin <<<"$(curl -sfL "https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_nexus3_repos.sh" --compressed)" || return $?

# Script arguments & Global variables
_FILE_LIST="${1}" # If not specified, will try from the PATH
_DBUSER="${2:-"nxrm"}"
_DBPWD="${3:-"${_DBUSER}123"}"
_DBNAME="${4:-"${_DBUSER}filelisttest"}" # Use some unique name (lowercase)
_VER="${5:-"3.53.0-01"}"         # Specify your nexus version
_NEXUS_TGZ_DIR="${6:-"$HOME/.nexus_executable_cache"}"

_NEXUS_DEFAULT_PORT="18081"
_TEST_REPO_NAME="raw-hosted"
_ASSET_CREATE_NUM=1000
_PID=""
_AWS_S3_BUCKET="apac-support-bucket"
_AWS_S3_PREFIX="filelist_test"
_S3_BLOBTORE_NAME="s3-test"
#_FORCE="N"
#_WITH_S3="N"

function TestFileList() {
    local _expected_num="${1:-0}"
    local _bsName="${2:-"default"}"
    local _is_s3="${3}"

    if [ 10 -gt ${_expected_num} ]; then
        _log "WARN" "_expected_num (${_expected_num}) might be incorrect"
    fi

    local _opt="-b ./sonatype-work/nexus3/blobs/${_bsName}/content -p vol-"
    [[ "${_is_s3}" =~ ^[yY] ]] && _opt="-b ${_AWS_S3_BUCKET} -p ${_AWS_S3_PREFIX%/}/content/vol- -S3"
    if [ -s ./sonatype-work/nexus3/etc/fabric/nexus-store.properties ]; then
        _opt="${_opt} -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties"
    fi

    local _cmd="${_FILE_LIST} -c 10 -RF -bsName ${_bsName} ${_opt}"
    _log "INFO" "Executing '${_cmd}' ..."
    time ${_cmd} -X >./file-list.out 2>./file-list.log || return $?
    local _file_list_ln="$(cat ./file-list.out | wc -l | tr -d '[:space:]')"

    if [ 0 -eq ${_file_list_ln} ]; then
        _log "ERROR" "Test failed. file-list didn't find any blobs (${_file_list_ln})"
    fi

    if [ ${_file_list_ln} -gt ${_expected_num} ] || [ ${_file_list_ln} -lt ${_ASSET_CREATE_NUM} ]; then
        _log "ERROR" "Test failed. file-list.out line number ${_file_list_ln} is not between ${_ASSET_CREATE_NUM} and ${_expected_num}"
    fi

    # File type only test/check:
    if [[ ! "${_is_s3}" =~ ^[yY] ]]; then
        local _grep="grep --include=\"*.properties\" -E"
        type rg &>/dev/null && _grep="rg -g \"*.properties\""
        if ${_grep} -l '^deleted=true' ./sonatype-work/nexus3/blobs/${_bsName}/content/vol-*; then
            _log "ERROR" "Test failed. with '-RDel', rg shouldn't find any 'deleted=true' file."
        fi
    fi

    # NOTE: Some metadata can not be deleted with API so actual_file_sorted would have more
    #find ./sonatype-work/nexus3/blobs/${_bsName}/content/vol-* -name '*.properties' | rg '[0-9a-f\-]{20,}' -o | sort > actual_file_sorted.out
    _log "INFO" "${_file_list_ln} of ${_expected_num} are found by file-list"
}

function main() {
    local _os="linux"
    [ "$(uname)" = "Darwin" ] && _os="mac"

    if [ -z "${_FILE_LIST}" ]; then
        if type file-list &>/dev/null; then
            _FILE_LIST="file-list"
        else
            _log "ERROR" "No file-list binary found in the \$PATH."
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
            _log "WARN" "As _FORCE = ${_FORCE}, will execute 'DROP DATABASE ${_DBNAME}' in 5 seconds..."
            sleep 5
            PGPASSWORD="${_DBPWD}" psql -U ${_DBUSER} -h $(hostname -f) -p 5432 -d template1 -c "DROP DATABASE ${_DBNAME}" || return $?
        fi
    fi

    if [ -d "./nxrm-${_VER}" ]; then
        _log "WARN" "./nxrm-${_VER} exists (_FORCE = ${_FORCE})"
        if [[ ! "${_FORCE}" =~ ^[yY] ]]; then
            echo "To force, set _FORCE=\"Y\" env variable." >&2
            return 1
        else
            _log "WARN" "As _FORCE = ${_FORCE}, will execute 'rm -rf \"./nxrm-${_VER}\"' in 5 seconds..."
            sleep 5
            rm -rf "./nxrm-${_VER}" || return $?
        fi
    fi

    mkdir -v ./nxrm-${_VER} || return $?
    cd ./nxrm-${_VER} || return $?

    if [ ! -s "nexus-${_VER}/bin/nexus" ]; then
        if [ ! -s "${_NEXUS_TGZ_DIR%/}/nexus-${_VER}-${_os}.tgz" ]; then
            _log "ERROR" "${_NEXUS_TGZ_DIR%/}/nexus-${_VER}-${_os}.tgz does not exist."
            return 1
        fi
        _log "INFO" "Extracting ${_NEXUS_TGZ_DIR%/}/nexus-${_VER}-${_os}.tgz ..."
        tar -xf "${_NEXUS_TGZ_DIR%/}/nexus-${_VER}-${_os}.tgz" || return $?
    fi

    _log "INFO" "Creating DB and DB user (${_DBNAME}, ${_DBUSER}) ..."
    _postgresql_create_dbuser "${_DBUSER}" "${_DBPWD}" "${_DBNAME}" || return $?

    _log "INFO" "Creating ./sonatype-work/nexus3/etc/nexus.properties and ./sonatype-work/nexus3/etc/fabric/nexus-store.properties ..."
    if [ ! -d "./sonatype-work/nexus3/etc/fabric" ]; then
        mkdir -v -p ./sonatype-work/nexus3/etc/fabric || return $?
    fi
    if [ ! -s "./sonatype-work/nexus3/etc/nexus.properties" ]; then
        touch "./sonatype-work/nexus3/etc/nexus.properties"
    fi
    local _port="$(_find_port "${_NEXUS_DEFAULT_PORT}")"
    _upsert "./sonatype-work/nexus3/etc/nexus.properties" "application-port" "${_port}" || return $?
    _upsert "./sonatype-work/nexus3/etc/nexus.properties" "nexus.datastore.enabled" "true" || return $?
    _upsert "./sonatype-work/nexus3/etc/nexus.properties" "nexus.security.randompassword" "false" || return $?
    _upsert "./sonatype-work/nexus3/etc/nexus.properties" "nexus.onboarding.enabled" "false" || return $?
    _upsert "./sonatype-work/nexus3/etc/nexus.properties" "nexus.scripts.allowCreation" "true" || return $?

    cat <<EOF >./sonatype-work/nexus3/etc/fabric/nexus-store.properties
name=nexus
type=jdbc
jdbcUrl=jdbc\:postgresql\://$(hostname -f)\:5432/${_DBNAME}
username=${_DBUSER}
password=${_DBPWD}
maximumPoolSize=40
advanced=maxLifetime\=600000
EOF

    # Start your nexus. Not using 'start' so that stopping is easier (i think)
    ./nexus-${_VER}/bin/nexus run &>./nexus_run.out &
    _PID=$!
    _log "INFO" "Executing './nexus-${_VER}/bin/nexus run &> ./nexus_run.out &' (PID: ${_PID}) ..."
    #tail -f ./sonatype-work/nexus3/log/nexus.log

    # Wait until port is ready
    export _NEXUS_URL="http://localhost:${_port}/"
    _log "INFO" "Waiting ${_NEXUS_URL} ..."
    _wait_url "${_NEXUS_URL}" || return $?

    # Below line creates various repositories with a few dummy assets, but not using because this test is not for testing the Reconcile task.
    #_AUTO=true main

    # always creating 'raw-hosted'
    _log "INFO" "Executing 'f_setup_raw' (creating 'raw-hosted') ..."
    f_setup_raw || return $?
    _log "INFO" "Executing 'f_upload_dummies \"${_NEXUS_URL%/}/repository/raw-hosted/test\" \"${_ASSET_CREATE_NUM}\"' ..."
    f_upload_dummies "${_NEXUS_URL%/}/repository/raw-hosted/test" "${_ASSET_CREATE_NUM}" || return $?
    if [[ "${_WITH_S3}" =~ ^[yY] ]]; then
        _log "INFO" "Creating '${_S3_BLOBTORE_NAME}' (this also creates 'raw-s3-hosted' repo)..."
        if ! f_create_s3_blobstore "${_S3_BLOBTORE_NAME}" "${_AWS_S3_PREFIX}" "${_AWS_S3_BUCKET}"; then
            # other params use AWS_XXXX env variables
            _log "WARN" "Not testing S3 as f_create_s3_blobstore failed. Please make sure the AWS_ env variables are set."
            _WITH_S3=""
        else
            _log "INFO" "Executing 'f_upload_dummies \"${_NEXUS_URL%/}/repository/raw-s3-hosted/test\" \"${_ASSET_CREATE_NUM}\"' ..."
            if ! f_upload_dummies "${_NEXUS_URL%/}/repository/raw-s3-hosted/test" "${_ASSET_CREATE_NUM}"; then
                _log "WARN" "Not testing S3 as f_upload_dummies failed. Please investigate nexus.log."
                _WITH_S3=""
            fi
        fi
    fi

    f_delete_all_assets "Y"
    local _expected_num=$(cat /tmp/f_delete_all_assets_$$.out | wc -l | tr -d '[:space:]')

    # For measuring the time of your restoring command, delete Linux (file) cache
    #sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'

    _log "INFO" "Executing 'TestFileList \"${_expected_num}\" \"${_BLOBTORE_NAME}\"' ..."
    TestFileList "${_expected_num}" "${_BLOBTORE_NAME}"
    if [[ "${_WITH_S3}" =~ ^[yY] ]]; then
        _log "INFO" "Executing 'TestFileList \"${_expected_num}\" \"${_S3_BLOBTORE_NAME}\"' ..."
        TestFileList "${_expected_num}" "${_S3_BLOBTORE_NAME}" "${_WITH_S3}"
    fi

    echo "Extra manual test: "
    echo "    Start this nexus and wait or run *all* 'Cleanup unused asset blob' tasks."
    echo "    Re-run file-list command to make sure 'deleted=true' is removed."
    echo "    ${_FILE_LIST} ${_opt} -c 10 -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -RF -bsName ${_bsName} -dF $(date '+%Y-%m-%d') -RDel -X > ./file-list_del.out 2> ./file-list_del.log"
    echo "    Run the Reconcile with Since 1 days and with file-list.out."
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main
    if [ -n "${_PID}" ]; then
        _log "INFO" "Stopping Nexus (${_PID}) ..."
        sleep 3
        kill ${_PID}
    fi
fi
