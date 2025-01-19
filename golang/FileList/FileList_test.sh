#!/usr/bin/env bash
# FileList system testing
#   # Do not forget to build the latest binary with `goBuild ./FileList.go`. then
#   ./FileList_test.sh
#
#   # Delete RM3 & DB and start from scratch
#   _FORCE=Y ./FileList_test.sh
#   # Delete RM3 & DB and start from scratch, and won't stop RM3 after testing
#   _FORCE=Y _NO_RM3_STOP_AFTER_TEST=Y _EXIT_AT_FIRST_TEST_ERROR=Y ./FileList_test.sh
#   # Delete RM3 & DB and use S3, and won't stop RM3 after testing
#   _FORCE=Y _NO_RM3_STOP_AFTER_TEST=Y _EXIT_AT_FIRST_TEST_ERROR=Y _WITH_S3=Y ./FileList_test.sh
#   # Delete RM3 & DB and use S3, and with dry run (to just generate deleted assets)
#   _FORCE=Y _WITH_DRY_RUN=Y _EXIT_AT_FIRST_TEST_ERROR=Y _WITH_S3=Y ./FileList_test.sh
#
#   # Execute test function only (not preparing RM3 and DB)
#   source ./FileList_test.sh
#   #_FORCE=Y cleanIfForce && prepareRM3 && createAssets
#   [ -d "${_WORKING_DIR}" ] || export _WORKING_DIR="./nxrm-3-61.0-02/sonatype-work/nexus3"
#   _WITH_S3="Y" test_Xxxxxxxx
#
#   TODO: test with UndeleteFileV3.groovy
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
_VER="${5:-"3.70.1-02"}"         # Specify your nexus version (NOTE: 3.62 and 3.63 are not suitable as NEXUS-40708)
_NEXUS_TGZ_DIR="${6:-"$HOME/.nexus_executable_cache"}"

# Global variables
#_FORCE="N"
#_NO_RM3_STOP_AFTER_TEST="N"
#_EXIT_AT_FIRST_TEST_ERROR="N"
#_WITH_S3="N"
#_WITH_DRY_RUN="N"
_NEXUS_DEFAULT_PORT="18081"
_ASSET_CREATE_NUM=100
_PID=""
_WORKING_DIR=""

_S3_BUCKET="apac-support-bucket"
_S3_PREFIX="filelist-test"
_S3_BLOBSTORE="s3-test"
# NOTE: Can't change repo names, always $(genRepoName) and raw-s3-hosted

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
    local _bsName="$(genBsName)"
    local _repo_name="$(genRepoName)"
    # Below line creates various repositories with a few dummy assets, but not using because this test is not for testing the Reconcile task.
    #_AUTO=true main
    if [[ "${_WITH_S3}" =~ ^[yY] ]]; then
        _log "INFO" "Creating S3 '${_S3_BLOBSTORE}' (this also creates 'raw-s3-hosted' repo)..."
        if ! _NO_DATA=Y f_create_s3_blobstore "${_S3_BLOBSTORE}" "${_S3_PREFIX}" "${_S3_BUCKET}"; then
            # other params use AWS_XXXX env variables
            _log "ERROR" "Failed. Please make sure the AWS_ env variables are set."
            return 1
        fi
        _repo_name="raw-s3-hosted"
    else
        f_create_file_blobstore "${_bsName}"
        _log "INFO" "Executing 'f_setup_raw' (creating 'raw-hosted') and f_setup_maven ..."
        _NO_DATA=Y f_setup_raw || return $?
        f_setup_maven
    fi
    _log "INFO" "Executing 'f_upload_dummies_raw \"${_repo_name}\" \"${_ASSET_CREATE_NUM}\"' (${_NEXUS_URL%/}) ..."
    f_upload_dummies_raw "${_repo_name}" "${_ASSET_CREATE_NUM}" &>/dev/null || return $?
    sleep 5 # sometimes blobs are not ready
}

function deleteAssets() {
    local _repo_name="$1"
    _log "INFO" "Deleting ${_repo_name:-"all"} assets (${_NEXUS_URL%/}) ..."
    sleep 3
    cat /dev/null > /tmp/f_get_all_assets_$$.out
    f_delete_all_assets "${_repo_name}" "Y" &>/dev/null || return $?
    local _deleted_num=$(cat /tmp/f_get_all_assets_$$.out | wc -l | tr -d '[:space:]')
    _log "INFO" "Deleted ${_deleted_num}"
    sleep 5
    _log "INFO" "Running assetBlob.cleanup (${_NEXUS_URL%/}) ..."
    f_run_tasks_by_type "assetBlob.cleanup" &>/dev/null || return $?
    sleep 5
    while f_api "/service/rest/v1/tasks?type=assetBlob.cleanup" | grep '"currentState"' | grep -v '"WAITING"'; do
        sleep 3
    done
    # Just in case, one more time, like if S3, somehow not instant...
    sleep 5;
    f_run_tasks_by_type "assetBlob.cleanup" &>/dev/null
    while f_api "/service/rest/v1/tasks?type=assetBlob.cleanup" | grep '"currentState"' | grep -v '"WAITING"'; do
        sleep 3
    done
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
    _upsert "${_etc%/}/nexus.properties" "nexus.blobstore.s3.ownership.check.disabled" "true" || return $?
    _upsert "${_etc%/}/nexus.properties" "nexus.assetBlobCleanupTask.blobCreatedDelayMinute" "0" || return $?

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

function genBsName() {
    if [[ "${_WITH_S3}" =~ ^[yY] ]]; then
        echo "${_S3_BLOBSTORE}"
    else
        echo "${_BLOBTORE_NAME:-"default"}"
    fi
}

function genRepoName() {
    if [[ "${_WITH_S3}" =~ ^[yY] ]]; then
        echo "raw-s3-hosted"
    else
        echo "raw-hosted"
    fi
}

function genCmdBase() {
    local _b="${1}"
    if [[ "${_WITH_S3}" =~ ^[yY] ]]; then
        local _cmd="${_FILE_LIST:-"file-list"} -S3 -b \"${_S3_BUCKET}\" -p \"${_S3_PREFIX}/content/vol-\""
    else
        local _cmd="${_FILE_LIST:-"file-list"} -b \"${_b}\" -p \"vol-\""
    fi
    # S3 uses UTC time probably?
    echo "${_cmd} -bsName $(genBsName) -c 10 -H"
}

function _exec() {
    local _cmd="$1"
    local _tsv="$2"
    if [ -s "${_tsv}" ]; then
        rm -f "${_tsv}" >&2  # this function shouldn't output anything to STDOUT, except the last line
    fi
    _cmd="${_cmd} -s ${_tsv}"
    _log "INFO" "Executing '${_cmd}' ..."
    time eval "${_cmd} 2>/tmp/${FUNCNAME[1]}.err" || return $?
    awk 'END { print NR }' "${_tsv}"
}


function test_FileList() {
    # run FileList against the specified blobstore but only modified files today
    local _working_dir="${1:-"${_WORKING_DIR}"}"
    local _bsName="$(genBsName)"
    local _repo_name="$(genRepoName)"

    local _tsv="${FUNCNAME[0]}_${_bsName}"
    rm -v -f /tmp/${_tsv}*.tsv || return $?

    _log "INFO" "Getting .properties and .bytes files modified today ..."
    local _cmd="$(genCmdBase "${_working_dir%/}/blobs/${_bsName}/content") -mF \"$(date -u +%Y-%m-%d)\""
    local _file_list_ln="$(_exec "${_cmd}" "/tmp/${_tsv}_all-files_for_today.tsv")"
    if [ ${_file_list_ln:-0} -le 1 ] || [ ${_ASSET_CREATE_NUM} -gt $(( ${_file_list_ln} / 2 )) ]; then
        _log "ERROR" "Test failed. file-list didn't find newly created ${_ASSET_CREATE_NUM} blobs ${_file_list_ln} / 2"
        [[ "${_EXIT_AT_FIRST_TEST_ERROR}" =~ ^[yY] ]] && return 1
    fi

    _log "INFO" "Getting .properties files modified today ..."
    local _file_list_ln="$(_exec "${_cmd} -P -f .properties" "/tmp/${_tsv}_all-props_for_today.tsv")"
    if [ ${_file_list_ln:-0} -le 1 ] || [ ${_ASSET_CREATE_NUM} -gt ${_file_list_ln} ]; then
        _log "ERROR" "Test failed. file-list didn't find newly created ${_ASSET_CREATE_NUM} blobs ${_file_list_ln}"
        [[ "${_EXIT_AT_FIRST_TEST_ERROR}" =~ ^[yY] ]] && return 1
    fi

    if [ -s "/tmp/${_tsv}_all-props_for_today.tsv" ] && [ ${_file_list_ln:-0} -gt 2 ]; then
        local _file_list_ln2="$(_exec "${_cmd} -P -f .properties -src \"\" -bF /tmp/${_tsv}_all-props_for_today.tsv" "/tmp/${_tsv}_all-props_for_today2.tsv")"
        if [ ${_file_list_ln} -ne ${_file_list_ln2:-0} ]; then
            _log "ERROR" "Test failed. '-bF' option should generate same number (${_file_list_ln} vs. ${_file_list_ln2})"
            [[ "${_EXIT_AT_FIRST_TEST_ERROR}" =~ ^[yY] ]] && return 1
        fi
    fi
}

function test_DeadBlobsFind() {
    local _working_dir="${1:-"${_WORKING_DIR}"}"
    local _bsName="$(genBsName)"
    local _repo_name="$(genRepoName)"
    local _cmd="$(genCmdBase "${_working_dir%/}/blobs/${_bsName}/content") -mF \"$(date -u +%Y-%m-%d)\""
    local _tsv="${FUNCNAME[0]}_${_bsName}"
    local _how_many=10

    # File type only test/check:
    if [[ ! "${_WITH_S3}" =~ ^[yY] ]]; then
        # Randomly moving blobs ... TODO: `-mtime -1` may not be perfect.
        _log "INFO" "Picking random ${_how_many} blobs for dead blobs test ..."
        time find ${_working_dir%/}/blobs/${_bsName}/content -maxdepth 1 -type d -name 'vol-*' -print0 | xargs -0 -I @@ -P3 find @@ -name '*.properties' -mtime -1 -exec grep -l '^@Bucket.repo-name='${_repo_name}'$' {} \; | head -n${_ASSET_CREATE_NUM:-50} | sort -R | head -n${_how_many} >/tmp/dead_blobs_${_how_many}_samples.txt

        if [ ! -s /tmp/dead_blobs_${_how_many}_samples.txt ]; then
            _log "ERROR" "'${_working_dir%/}/blobs/${_bsName}/content/vol-*' does not contain enough properties file to test"
            [[ "${_EXIT_AT_FIRST_TEST_ERROR}" =~ ^[yY] ]] && return 1
        else
            cat /tmp/dead_blobs_${_how_many}_samples.txt | xargs -I{} mv {} {}.test || return $?
            _log "INFO" "Finding dead blobs for ${_repo_name} (should be at least ${_how_many}) ..."
            local _file_list_ln="$(_exec "${_cmd} -db ${_working_dir%/}/etc/fabric/nexus-store.properties -src DB -repos ${_repo_name} -P -f .properties" "/tmp/${_tsv}_dead.tsv")"
            if [ ${_file_list_ln:-0} -le 1 ] || [ ${_how_many:-10} -gt ${_file_list_ln:-0} ]; then
                _log "ERROR" "Test failed. file-list didn't find expected dead ${_how_many} blobs ${_file_list_ln}"
                [[ "${_EXIT_AT_FIRST_TEST_ERROR}" =~ ^[yY] ]] && return 1
            fi
            # moving back
            cat /tmp/dead_blobs_${_how_many}_samples.txt | xargs -I{} mv {}.test {} || return $?
        fi
    fi
    # TODO: add S3 test
}

function test_SoftDeletedThenUndeleteThenOrphaned() {
    local _working_dir="${1:-"${_WORKING_DIR}"}"
    local _bsName="$(genBsName)"
    local _repo_name="$(genRepoName)"
    local _cmd_base="$(genCmdBase "${_working_dir%/}/blobs/${_bsName}/content")"
    local _tsv="${FUNCNAME[0]}_${_bsName}"

    local _is_undeleted=false
    local _cmd="${_cmd_base} -P -fP \"@Bucket\.repo-name=${_repo_name}.+deleted=true\" -R"
    # Count how many soft-delete already
    local _soft_deleted="$(_exec "${_cmd}" "/tmp/${_tsv}_deleted_before_test.tsv")"
    _soft_deleted=$((_ASSET_CREATE_NUM + _soft_deleted))
    # deleting all and restore only raw-hosted (not maven-hosted)
    if ! deleteAssets; then
        [[ "${_EXIT_AT_FIRST_TEST_ERROR}" =~ ^[yY] ]] && return 1
    fi

    if [[ "${_WITH_S3}" =~ ^[yY] ]]; then
        _log "INFO" "As S3, adding extra 10 seconds for the soft-deleting ..."
        sleep 10
    fi

    _log "INFO" "Finding soft deleted blobs for ${_repo_name} which modified today ..."
    local _file_list_ln="$(_exec "${_cmd} -mF \"$(date -u +%Y-%m-%d)\"" "/tmp/${_tsv}_deleted_modified_today.tsv")"
    if [ ${_file_list_ln:-0} -lt ${_soft_deleted} ]; then
        _log "WARN" "/tmp/${_tsv}_deleted_modified_today.tsv contains only ${_file_list_ln:-0} lines. Retrying after 10 seconds with -XX ..."; sleep 10
        _file_list_ln="$(_exec "${_cmd} -mF \"$(date -u +%Y-%m-%d)\" -XX" "/tmp/${_tsv}_deleted_modified_today.tsv")"
    fi
    if [ ${_file_list_ln:-0} -le 1 ] || [ ${_file_list_ln:-0} -lt ${_ASSET_CREATE_NUM} ]; then
        _log "ERROR" "Test might be failed. file-list didn't find expected soft-deleted (${_ASSET_CREATE_NUM}) blobs but ${_file_list_ln} blobs"
        if [[ ! "${_WITH_S3}" =~ ^[yY] ]]; then
            ${_GREP} -l '^deleted=true' ${_working_dir%/}/blobs/${_bsName}/content/vol-* | wc -l
        fi
        [[ "${_EXIT_AT_FIRST_TEST_ERROR}" =~ ^[yY] ]] && return 1
    fi

    _log "INFO" "Finding blobs which were *deleted* (not modified) today ..."
    local _deleted_today="$(_exec "${_cmd} -dF $(date -u +%Y-%m-%d)" "/tmp/${_tsv}_deleted_today.tsv")"

    _log "INFO" "Un-soft-deleting blobs by using /tmp/${_tsv}_deleted_today.tsv (bF) with _WITH_DRY_RUN="${_WITH_DRY_RUN}" ..."
    local _dry_run=""
    [[ "${_WITH_DRY_RUN}" =~ ^[yY] ]] && _dry_run="-Dry"
    _file_list_ln="$(_exec "${_cmd} -dF $(date -u +%Y-%m-%d) -RDel ${_dry_run} -bF /tmp/${_tsv}_deleted_today.tsv" "/tmp/${_tsv}_deleted_today_undelete.tsv")"
    if [ ${_file_list_ln:-0} -le 1 ] || [ ${_file_list_ln} -ne ${_deleted_today} ]; then
        _log "ERROR" "Test failed. file-list didn't find expected un-soft-deleted ${_deleted_today} blobs but ${_file_list_ln}"
        [[ "${_EXIT_AT_FIRST_TEST_ERROR}" =~ ^[yY] ]] && return 1
    fi
    [[ "${_WITH_DRY_RUN}" =~ ^[yY] ]] || _is_undeleted=true
    # File type only test/check:
    if [[ ! "${_WITH_S3}" =~ ^[yY] ]]; then
        if ${_GREP} -l '^deleted=true' ${_working_dir%/}/blobs/${_bsName}/content/vol-*; then
            _log "ERROR" "Test failed. After '-RDel', grep/rg shouldn't find any 'deleted=true' file."
            [[ "${_EXIT_AT_FIRST_TEST_ERROR}" =~ ^[yY] ]] && return 1
        fi
    fi

    if ${_is_undeleted}; then
        if [ -s "${_working_dir%/}/etc/fabric/nexus-store.properties" ] ; then
            sleep 5
            # Default -src (truth) is 'BS', so adding -db should be enough
            _file_list_ln="$(_exec "${_cmd_base} -mF \"$(date -u +%Y-%m-%d)\" -fP \"@Bucket\.repo-name=${_repo_name},\" -R -src BS -db ${_working_dir%/}/etc/fabric/nexus-store.properties -P -f .properties" "/tmp/${_tsv}_orphaned.tsv")"
            if [ ${_file_list_ln:-0} -le 1 ] || [ ${_file_list_ln} -lt ${_ASSET_CREATE_NUM} ]; then
                _log "ERROR" "Test failed. file-list didn't find expected minimum un-soft-deleted ${_ASSET_CREATE_NUM} blobs but ${_file_list_ln} blobs"
                [[ "${_EXIT_AT_FIRST_TEST_ERROR}" =~ ^[yY] ]] && return 1
            fi

            if [[ ! "${_WITH_S3}" =~ ^[yY] ]]; then
                #rg '/([0-9a-f\-]+)\..+(\d\d\d\d.\d\d.\d\d.\d\d:\d\d:\d\d)' -o -r '$2,$1' test_SoftDeletedThenUndeleteThenOrphaned_default_orphaned.tsv
                sed -n -E 's/.+([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\..+([0-9]{4}.[0-9]{2}.[0-9]{2}.[0-9]{2}:[0-9]{2}:[0-9]{2}).+/\2,\1/p' /tmp/${_tsv}_orphaned.tsv > "${_working_dir%/}/blobs/${_bsName}/reconciliation/$(date '+%Y-%m-%d')"
                if [ ! -s "${_working_dir%/}/blobs/${_bsName}/reconciliation/$(date '+%Y-%m-%d')" ]; then
                    _log "ERROR" "Test failed. '${_working_dir%/}/blobs/${_bsName}/reconciliation/$(date '+%Y-%m-%d')' is empty"
                    [[ "${_EXIT_AT_FIRST_TEST_ERROR}" =~ ^[yY] ]] && return 1
                fi
            fi
            if [[ "${_WITH_S3}" =~ ^[yY] ]] || [ -s "${_working_dir%/}/blobs/${_bsName}/reconciliation/$(date '+%Y-%m-%d')" ]; then
                if [ -s "$HOME/IdeaProjects/work/nexus-groovy/templates/UndeleteFileAPI.groovy" ]; then
                    f_register_script "$HOME/IdeaProjects/work/nexus-groovy/templates/UndeleteFileAPI.groovy" || return $?
                else
                    _log "NEXT" "Access ${_NEXUS_URL%/}/ and make sure no asset in ${_repo_name} and maven-hosted. Run the Reconcile task for '$(genBsName)' blob store and with 'Since 0 day' (If S3, 1 day) and 'Restore blob metadata', then confirm ${_repo_name} has ${_ASSET_CREATE_NUM} assets."
                fi
                # The diff of below should be 100:
                #   rg -c 'Restored asset' blobstore.rebuildComponentDB-*.log
                #   rg -c 'Deleting asset' blobstore.rebuildComponentDB-*.log
            fi
        fi
    fi
}

function test_UndeleteRepository() {
    local _working_dir="${1:-"${_WORKING_DIR}"}"
    local _bsName="$(genBsName)"
    local _repo_name="$(genRepoName)-undelete"
    local _cmd="$(genCmdBase "${_working_dir%/}/blobs/${_bsName}/content") -mF \"$(date -u +%Y-%m-%d)\""
    local _tsv="${FUNCNAME[0]}_${_bsName}"

    if ! _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bsName}'","writePolicy":"ALLOW","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"raw-s3-hosted","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}'; then
        [[ "${_EXIT_AT_FIRST_TEST_ERROR}" =~ ^[yY] ]] && return 1
    fi
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

    cleanIfForce || return $?
    prepareRM3 || return $?
    createAssets || return $?

    test_FileList || return $?
    test_DeadBlobsFind || return $?
    test_SoftDeletedThenUndeleteThenOrphaned || return $?

    # NOTE: Some metadata can not be deleted with API so below actual_file_sorted would have more:
    #find ./sonatype-work/nexus3/blobs/${_bsName}/content/vol-* -name '*.properties' | rg '[0-9a-f\-]{20,}' -o | sort > actual_file_sorted.out
    echo "Completed."
}


if [ "$0" = "$BASH_SOURCE" ]; then
    main
    if [[ ! "${_NO_RM3_STOP_AFTER_TEST}" =~ ^[yY] ]]; then
        if [ -z "${_PID}" ]; then
            _log "WARN" "Could not stop Nexus as no PID found."
        else
            _log "INFO" "Stopping Nexus (${_PID}) ..."
            sleep 3
            kill ${_PID}
        fi
    fi
fi
