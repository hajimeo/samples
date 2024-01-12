#!/usr/bin/env bash
# FileList system testing
#   ./FileList_test.sh
#
#   # Delete RM3 & DB and start from scratch
#   _FORCE=Y ./FileList_test.sh
#   # Delete RM3 & DB and start from scratch, and won't stop RM3 after testing
#   _FORCE=Y _NOT_STOP_AFTER_TEST=Y ./FileList_test.sh
#   # Delete RM3 & DB and start from scratch, and use S3 instead of File blobstore
#   _FORCE=Y _WITH_S3=Y ./FileList_test.sh
#
#   # Execute test function only (not preparing RM3 and DB)
#   source ./FileList_test.sh
#   #_FORCE=Y cleanIfForce && prepareRM3 && createAssets
#   test_FileList
#

# Download automate scripts
source /dev/stdin <<<"$(curl -sfL "https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils.sh" --compressed)" || return $?
source /dev/stdin <<<"$(curl -sfL "https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils_db.sh" --compressed)" || return $?
source /dev/stdin <<<"$(curl -sfL "https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_nexus3_repos.sh" --compressed)" || return $?

# Script arguments
_FILE_LIST="${1}" # If not specified, will try from the PATH
_DBUSER="${2:-"nxrm"}"
_DBPWD="${3:-"${_DBUSER}123"}"
_DBNAME="${4:-"${_DBUSER}filelisttest"}" # Use some unique name (lowercase)
_VER="${5:-"3.61.0-02"}"         # Specify your nexus version (NOTE: 3.62 and 3.63 are not suitable as NEXUS-40708)
_NEXUS_TGZ_DIR="${6:-"$HOME/.nexus_executable_cache"}"

# Global variables
#_FORCE="N"
#_NOT_STOP_AFTER_TEST="N"
#_STOP_IF_TEST_ERROR="N"
#_WITH_S3="N"
_NEXUS_DEFAULT_PORT="18081"
_ASSET_CREATE_NUM=100
_PID=""
_WORKING_DIR=""
_AWS_S3_BUCKET="apac-support-bucket"
_AWS_S3_PREFIX="filelist_test"
_S3_BLOBTORE_NAME="s3-test" # Can't change repo names, always raw-hosted and raw-s3-hosted

_GREP="grep --include=\"*.properties\" -E"
type rg &>/dev/null && _GREP="rg -g \"*.properties\""

function cleanIfForce() {
    _PID="$(ps auxwww | grep -F 'org.sonatype.nexus.karaf.NexusMain' | grep -vw grep | awk '{print $2}' | tail -n1)"
    if [ -n "${_PID}" ]; then
        _log "WARN" "NexusMain is running wit PID=${_PID} (_FORCE = ${_FORCE})"
        if [[ ! "${_FORCE}" =~ ^[yY] ]]; then
            echo "As no _FORCE=\"Y\", reusing this NexusMain." >&2
            sleep 3
        else
            _log "WARN" "As _FORCE = ${_FORCE}, will execute 'kill ${_PID}\"' in 3 seconds..."
            sleep 3
            kill ${_PID} || return $?
            _PID=""
            sleep 5
        fi
    fi

    if [ -d "./nxrm-${_VER}" ]; then
        _log "WARN" "./nxrm-${_VER} exists (_FORCE = ${_FORCE})"
        if [[ ! "${_FORCE}" =~ ^[yY] ]]; then
            echo "As no _FORCE=\"Y\", reusing this installation." >&2
            sleep 3
        else
            _log "WARN" "As _FORCE = ${_FORCE}, will execute 'rm -rf \"./nxrm-${_VER}\"' in 3 seconds..."
            sleep 3
            rm -rf "./nxrm-${_VER}" || return $?
        fi
    fi

    # Not perfect check but better than not checking...
    if psql -l | grep -q "^ ${_DBNAME} "; then
        _log "WARN" "Database ${_DBNAME} exists (_FORCE = ${_FORCE})"
        if [[ ! "${_FORCE}" =~ ^[yY] ]]; then
            echo "As no _FORCE=\"Y\", reusing this database (but may not start due to Nuget repository)." >&2
            sleep 3
        else
            _log "WARN" "As _FORCE = ${_FORCE}, will execute 'DROP DATABASE ${_DBNAME}' in 3 seconds..."
            sleep 3
            PGPASSWORD="${_DBPWD}" psql -U ${_DBUSER} -h $(hostname -f) -p 5432 -d template1 -c "DROP DATABASE ${_DBNAME}" || return $?
        fi
    fi
}

function createAssets() {
    # TODO: currently can't change the repo name
    local _repo_name="raw-hosted"
    # Below line creates various repositories with a few dummy assets, but not using because this test is not for testing the Reconcile task.
    #_AUTO=true main
    if [[ "${_WITH_S3}" =~ ^[yY] ]]; then
        _log "INFO" "Creating S3 '${_S3_BLOBTORE_NAME}' (this also creates 'raw-s3-hosted' repo)..."
        if ! f_create_s3_blobstore "${_S3_BLOBTORE_NAME}" "${_AWS_S3_PREFIX}" "${_AWS_S3_BUCKET}"; then
            # other params use AWS_XXXX env variables
            _log "ERROR" "Failed. Please make sure the AWS_ env variables are set."
            return 1
        fi
        _repo_name="raw-s3-hosted"
    else
        f_create_file_blobstore "${_bsName}"
        _log "INFO" "Executing 'f_setup_raw' (creating 'raw-hosted') ..."
        f_setup_raw || return $?
    fi
    _log "INFO" "Executing 'f_upload_dummies_raw \"${_repo_name}\" \"${_ASSET_CREATE_NUM}\"' (${_NEXUS_URL%/}) ..."
    f_upload_dummies_raw "${_repo_name}" "${_ASSET_CREATE_NUM}" &>/dev/null || return $?
}

function deleteAssets() {
    local _repo_name="$1"
    _log "INFO" "Deleting ${_repo_name:-"all"} assets (${_NEXUS_URL%/}) ..."
    sleep 3
    cat /dev/null > /tmp/f_get_all_assets_$$.out
    f_delete_all_assets "${_repo_name}" "Y" &>/dev/null || return $?
    local _deleted_num=$(cat /tmp/f_get_all_assets_$$.out | wc -l | tr -d '[:space:]')
    sleep 5
    _log "INFO" "Running assetBlob.cleanup (${_NEXUS_URL%/}) ..."
    f_run_tasks_by_type "assetBlob.cleanup" &>/dev/null || return $?
    sleep 1
    # just in case...
    f_run_tasks_by_type "assetBlob.cleanup" &>/dev/null
    sleep 5
    while f_api "/service/rest/v1/tasks?type=assetBlob.cleanup" | grep '"currentState"' | grep -v '"WAITING"'; do
        sleep 3
    done
    #f_run_tasks_by_type "assetBlob.cleanup" &>/dev/null; sleep 5
}

function prepareRM3() {
    local _base_url="${1:-"./nxrm-${_VER}"}"
    local _os="linux"
    [ "$(uname)" = "Darwin" ] && _os="mac"
    
    if [ -n "${_PID}" ]; then
        if ps auxwww | grep -F 'org.sonatype.nexus.karaf.NexusMain' | grep -qw ${_PID}; then
            _log "WARN" "NexusMain is already running (${_PID})"
            return 1
        fi
    fi

    if [ ! -d "${_base_url%/}" ]; then
        mkdir -v -p "${_base_url%/}" || return $?
    fi
    if [ ! -s "${_base_url%/}/nexus-${_VER}/bin/nexus" ]; then
        if [ ! -s "${_NEXUS_TGZ_DIR%/}/nexus-${_VER}-${_os}.tgz" ]; then
            _log "ERROR" "${_NEXUS_TGZ_DIR%/}/nexus-${_VER}-${_os}.tgz does not exist."
            return 1
        fi
        _log "INFO" "Extracting ${_NEXUS_TGZ_DIR%/}/nexus-${_VER}-${_os}.tgz ..."
        tar -xf "${_NEXUS_TGZ_DIR%/}/nexus-${_VER}-${_os}.tgz" -C "${_base_url%/}" || return $?
    fi
    
    local _etc="${_base_url%/}/sonatype-work/nexus3/etc"
    _log "INFO" "Creating ${_etc%/}/nexus.properties and ${_etc%/}/fabric/nexus-store.properties ..."
    if [ ! -d "${_etc%/}/fabric" ]; then
        mkdir -v -p "${_etc%/}/fabric" || return $?
    fi
    if [ ! -s "${_etc%/}/nexus.properties" ]; then
        touch "${_etc%/}/nexus.properties"
    fi

    # If not reusing currently running RM3, find available port
    local _port="${_NEXUS_DEFAULT_PORT}"
    [ -z "${_PID}" ] && _port="$(_find_port "${_NEXUS_DEFAULT_PORT}")"
    _upsert "${_etc%/}/nexus.properties" "application-port" "${_port}" || return $?
    _upsert "${_etc%/}/nexus.properties" "nexus.datastore.enabled" "true" || return $?
    _upsert "${_etc%/}/nexus.properties" "nexus.security.randompassword" "false" || return $?
    _upsert "${_etc%/}/nexus.properties" "nexus.onboarding.enabled" "false" || return $?
    _upsert "${_etc%/}/nexus.properties" "nexus.scripts.allowCreation" "true" || return $?

    cat <<EOF > ${_etc%/}/fabric/nexus-store.properties
name=nexus
type=jdbc
jdbcUrl=jdbc\:postgresql\://$(hostname -f)\:5432/${_DBNAME}
username=${_DBUSER}
password=${_DBPWD}
maximumPoolSize=40
advanced=maxLifetime\=600000
EOF

    _log "INFO" "Creating DB and DB user (${_DBNAME}, ${_DBUSER}) ..."
    _postgresql_create_dbuser "${_DBUSER}" "${_DBPWD}" "${_DBNAME}" || return $?

    # Start your nexus. Not using 'start' so that stopping is easier (i think)
    ${_base_url%/}/nexus-${_VER}/bin/nexus run &> ${_base_url%/}/nexus_run.out &
    _PID=$!
    _log "INFO" "Executing '${_base_url%/}/nexus-${_VER}/bin/nexus run &> ${_base_url%/}/nexus_run.out &' (PID: ${_PID}) ..."

    export _NEXUS_URL="http://localhost:${_port}/"
    _log "INFO" "Waiting ${_NEXUS_URL} ..."
    _wait_url "${_NEXUS_URL}" || return $?
    # If everything is OK, set _WORKING_DIR
    export _WORKING_DIR="${_base_url%/}/sonatype-work/nexus3"
}

function _exec() {
    local _cmd="$1"
    local _tsv="$2"
    _log "INFO" "Executing '${_cmd} -s ${_tsv}' ..."
    eval "${_cmd} -s ${_tsv}" 2> ./${FUNCNAME[1]}.log || return $?
    cat ${_tsv} | wc -l | tr -d '[:space:]'
}

function test_FileList() {
    # run FileList against the specified blobstore but only modified files today
    local _working_dir="${1:-"${_WORKING_DIR}"}"
    local _bsName="${2:-"default"}"
    local _repo_name="raw-hosted"

    local _tsv="./${FUNCNAME[0]}_${_bsName}"
    rm -v -f ${_tsv}*.tsv || return $?

    _log "INFO" "Getting .properties and .bytes files modified today ..."
    local _cmd="${_FILE_LIST:-"file-list"} -b ${_working_dir%/}/blobs/${_bsName}/content -p vol- -mF $(date +%Y-%m-%d) -c 10 -bsName ${_bsName}"
    local _file_list_ln="$(_exec "${_cmd}" "${_tsv}_all-files_for_today.tsv")"
    if [ ${_file_list_ln:-0} -le 1 ] || [ ${_ASSET_CREATE_NUM} -gt $(( (${_file_list_ln} - 1) / 2 )) ]; then
        _log "ERROR" "Test failed. file-list didn't find newly created ${_ASSET_CREATE_NUM} blobs (${_file_list_ln} - 1) / 2"
        [[ "${_STOP_IF_TEST_ERROR}" =~ ^[yY] ]] || return 1
    fi

    _log "INFO" "Getting .properties files modified today ..."
    local _file_list_ln="$(_exec "${_cmd} -P -f .properties" "${_tsv}_all-props_for_today.tsv")"
    if [ ${_file_list_ln:-0} -le 1 ] || [ ${_ASSET_CREATE_NUM} -gt $(( ${_file_list_ln} - 1 )) ]; then
        _log "ERROR" "Test failed. file-list didn't find newly created ${_ASSET_CREATE_NUM} blobs (${_file_list_ln} - 1)"
        [[ "${_STOP_IF_TEST_ERROR}" =~ ^[yY] ]] || return 1
    fi
}

function test_DeadBlobsFind() {
    local _working_dir="${1:-"${_WORKING_DIR}"}"
    local _bsName="${2:-"default"}"
    local _repo_name="raw-hosted"
    local _cmd="${_FILE_LIST:-"file-list"} -b ${_working_dir%/}/blobs/${_bsName}/content -p vol- -mF $(date +%Y-%m-%d) -c 10 -bsName ${_bsName}"
    local _tsv="./${FUNCNAME[0]}_${_bsName}"
    local _how_many=10

    # File type only test/check:
    if [[ ! "${_WITH_S3}" =~ ^[yY] ]]; then
        # Randomly moving blobs ... TODO: `-mtime -1` may not be perfect.
        find ${_working_dir%/}/blobs/${_bsName}/content/vol-* -name '*.properties' -mtime -1 | head -n${_ASSET_CREATE_NUM:-50} | sort -R | head -n${_how_many} >./dead_blobs_${_how_many}_samples.txt
        if [ ! -s ./dead_blobs_${_how_many}_samples.txt ]; then
            _log "ERROR" "'${_working_dir%/}/blobs/${_bsName}/content/vol-*' does not contain enough properties file to test"
            [[ "${_STOP_IF_TEST_ERROR}" =~ ^[yY] ]] || return 1
        else
            _log "INFO" "Renaming ${_how_many} blobs ..."
            cat ./dead_blobs_${_how_many}_samples.txt | xargs -I{} mv {} {}.test || return $?
            _log "INFO" "Finding dead blobs (should be at least 10) ..."
            local _file_list_ln="$(_exec "${_cmd} -db ${_working_dir%/}/etc/fabric/nexus-store.properties -src DB -repos ${_repo_name} -P -f .properties" "${_tsv}_dead.tsv")"
            if [ ${_file_list_ln:-0} -le 1 ] || [ ${_how_many:-10} -gt $(( ${_file_list_ln} - 1 )) ]; then
                _log "ERROR" "Test failed. file-list didn't find expected dead ${_ASSET_CREATE_NUM} blobs (${_file_list_ln} - 1)"
                [[ "${_STOP_IF_TEST_ERROR}" =~ ^[yY] ]] || return 1
            fi
            # moving back
            cat ./dead_blobs_10_samples.txt | xargs -I{} mv {}.test {} || return $?
        fi
    fi
    # TODO: add S3 test
}

function test_SoftDeletedThenUndeleteThenOrphaned() {
    local _working_dir="${1:-"${_WORKING_DIR}"}"
    local _bsName="${2:-"default"}"
    local _repo_name="raw-hosted"
    local _cmd="${_FILE_LIST:-"file-list"} -b ${_working_dir%/}/blobs/${_bsName}/content -p vol- -mF $(date +%Y-%m-%d) -c 10 -bsName ${_bsName}"
    local _tsv="./${FUNCNAME[0]}_${_bsName}"

    local _is_undeleted=false
    deleteAssets "${_repo_name}" || return $?

    _log "INFO" "Finding soft deleted blobs which modified today ..."
    _file_list_ln="$(_exec "${_cmd} -P -fP \"@Bucket.repo-name=${_repo_name}.+deleted=true\" -R" "${_tsv}_deleted_modified_today.tsv")"
    if [ ${_file_list_ln:-0} -eq 1 ]; then
        _log "WARN" "${_tsv}_deleted_modified_today.tsv contains only one line. Retrying after 10 seconds with -XX ..."; sleep 10
        _file_list_ln="$(_exec "${_cmd} -P -fP \"@Bucket.repo-name=${_repo_name}.+deleted=true\" -R -XX" "${_tsv}_deleted_modified_today.tsv")"
    fi
    if [ ${_file_list_ln:-0} -le 1 ] || [ ${_ASSET_CREATE_NUM} -gt $(( ${_file_list_ln} - 1 )) ]; then
        _log "ERROR" "Test failed. file-list didn't find expected soft-deleted ${_ASSET_CREATE_NUM} blobs (${_file_list_ln} - 1) / 2"
        ${_GREP} -l '^deleted=true' ${_working_dir%/}/blobs/${_bsName}/content/vol-* | wc -l
        [[ "${_STOP_IF_TEST_ERROR}" =~ ^[yY] ]] || return 1
    fi

    _log "INFO" "Finding un-soft-delete blobs which modified today ..."
    _file_list_ln="$(_exec "${_cmd} -P -fP \"@Bucket\.repo-name=${_repo_name}.+deleted=true\" -R -dF $(date +%Y-%m-%d) -RDel" "${_tsv}_deleted_today_undelete.tsv")"
    if [ ${_file_list_ln:-0} -le 1 ] || [ ${_ASSET_CREATE_NUM} -gt $(( ${_file_list_ln} - 1 )) ]; then
        _log "ERROR" "Test failed. file-list didn't find expected un-soft-deleted ${_ASSET_CREATE_NUM} blobs (${_file_list_ln} - 1) / 2"
        [[ "${_STOP_IF_TEST_ERROR}" =~ ^[yY] ]] || return 1
    fi
    _is_undeleted=true
    # File type only test/check:
    if [[ ! "${_WITH_S3}" =~ ^[yY] ]]; then
        if ${_GREP} -l '^deleted=true' ${_working_dir%/}/blobs/${_bsName}/content/vol-*; then
            _log "ERROR" "Test failed. After '-RDel', grep/rg shouldn't find any 'deleted=true' file."
            [[ "${_STOP_IF_TEST_ERROR}" =~ ^[yY] ]] || return 1
        fi
    fi

    if ${_is_undeleted}; then
        if [ -s "${_working_dir%/}/etc/fabric/nexus-store.properties" ] ; then
            # Default -src (truth) is 'BS', so adding -db should be enough
            local _file_list_ln="$(_exec "${_cmd} -db ${_working_dir%/}/etc/fabric/nexus-store.properties -P -f .properties" "${_tsv}_orphaned.tsv")"
            if [ ${_file_list_ln:-0} -le 1 ] || [ ${_ASSET_CREATE_NUM} -gt $(( ${_file_list_ln} - 1 )) ]; then
                _log "ERROR" "Test failed. file-list didn't find expected un-soft-deleted ${_ASSET_CREATE_NUM} blobs (${_file_list_ln} - 1)"
                [[ "${_STOP_IF_TEST_ERROR}" =~ ^[yY] ]] || return 1
            fi
        fi
    fi
    _log "INFO" "Please run the Reconcile task against '${_bsName}' blob store."
}


function main() {
    if [ -z "${_FILE_LIST}" ]; then
        if type file-list &>/dev/null; then
            _FILE_LIST="file-list"
        else
            _log "ERROR" "No file-list binary found in the \$PATH."
            return 1
        fi
    fi

    cleanIfForce
    prepareRM3 || return $?
    createAssets

    test_FileList
    test_DeadBlobsFind
    test_SoftDeletedThenUndeleteThenOrphaned

    # NOTE: Some metadata can not be deleted with API so below actual_file_sorted would have more:
    #find ./sonatype-work/nexus3/blobs/${_bsName}/content/vol-* -name '*.properties' | rg '[0-9a-f\-]{20,}' -o | sort > actual_file_sorted.out
}


if [ "$0" = "$BASH_SOURCE" ]; then
    main
    if [ -n "${_PID}" ] && [[ ! "${_NOT_STOP_AFTER_TEST}" =~ ^[yY] ]]; then
        _log "INFO" "Stopping Nexus (${_PID}) ..."
        sleep 3
        kill ${_PID}
    fi
fi
