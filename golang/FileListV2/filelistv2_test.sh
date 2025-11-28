#!/usr/bin/env bash
# Simple tests by just executing the commands and check the exit code.
#
# REQUIREMENTS:
#   'filelist2' in the $PATH
#   'blobpath' in the $PATH
#       curl -o /usr/local/bin/blobpath -L "https://github.com/hajimeo/samples/raw/master/misc/blobpath_$(uname)_$(uname -m)"
#       chmod a+x /usr/local/bin/blobpath
#   rg (ripgrep)
#   uuidgen
#
# HOW TO RUN EXAMPLE:
#   ./filelistv2_test.sh <blobstore> <path/prefix>
#
# Prepare the test data using setup_nexus3_repos.sh:
#   f_install_nexus3 3.77.1-01 filelistv2test
#   # After starting this Nexus, populate the data:
#   _AUTO=true main
#   f_upload_dummies_all_hosted
#   #f_backup_postgresql_component
#   f_delete_all_assets
#   #f_run_tasks_by_type "assetBlob.cleanup" # if Postgresql with nexus.assetBlobCleanupTask.blobCreatedDelayMinute=0
#
# For new blob store layout test:
#   f_install_nexus3 3.84.1-01 filelistv2test2
#   # After starting this Nexus, populate the data:
#   f_upload_dummies_raw "" "1000"
#   #f_backup_postgresql_component
#   f_delete_all_assets
#   #f_run_tasks_by_type "assetBlob.cleanup" # if Postgresql with nexus.assetBlobCleanupTask.blobCreatedDelayMinute=0
#
# Example environment variable (specify the workdir of the existing Nexus 3):
#   export _TEST_WORKDIR="./sonatype-work/nexus3"
#
# If File type blobstore:
#   $HOME/IdeaProjects/samples/golang/FileListV2/filelistv2_test.sh #"${_TEST_WORKDIR%/}/blobs/default"
# If S3 type blobstore:
#   export AWS_ACCESS_KEY_ID="..." AWS_SECRET_ACCESS_KEY="..." AWS_REGION="ap-southeast-2"
#   $HOME/IdeaProjects/samples/golang/FileListV2/filelistv2_test.sh "s3://apac-support-bucket/filelist-test"
# If Azure type blobstore:
#   export AZURE_STORAGE_ACCOUNT_NAME="..." AZURE_STORAGE_ACCOUNT_KEY="..."
#   $HOME/IdeaProjects/samples/golang/FileListV2/filelistv2_test.sh "az://filelist-test/"
#
### Global variables
: ${_TEST_WORKDIR:="./sonatype-work/nexus3"}      #./sonatype-work/nexus3
: ${_TEST_BLOBSTORE:="${_TEST_WORKDIR%/}/blobs/default"}    #./sonatype-work/nexus3/blobs/default (no content/)
: ${_TEST_FILTER_PATH:="/(vol-\d\d|20\d\d)/"}
: ${_TEST_DB_CONN:=""}      #host=localhost user=nexus dbname=nxrm
: ${_TEST_DB_CONN_PWD:="nexus123"}
: ${_TEST_STOP_ERROR:=true}
: ${_TEST_REPO_NAME:=""}
: ${_TEST_S3_REPO:="raw-s3-hosted"}
: ${_TEST_AZ_REPO:="raw-az-hosted"}
: ${_TEST_MAX_NUM:=100}


### Test functions
function test_1_First10FilesForSpecificRepo() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    _find_sample_repo_name "${_b}" "${_p}" || return 1

    local _out_file="/tmp/test_finding_${_TEST_REPO_NAME}-n10.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -pRx '@Bucket\.repo-name=${_TEST_REPO_NAME},' -P -H" "${_out_file}"
    if [ "$?" == "0" ] && [ -s "${_out_file}" ]; then
        echo "TEST=OK: out_file= ${_out_file}"
    else
        echo "TEST=ERROR (check /tmp/test_last.*)"
        return 1
    fi
}

function test_2_ShouldNotFindAny() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    if [[ "${_b}" =~ ^(s3|az):// ]]; then
        echo "TEST=WARN Skipped as this test can take long time with S3/Azure"
        return 0
    fi
    _find_sample_repo_name "${_b}" "${_p}" || return 1

    local _out_file="/tmp/test_not-finding_${_TEST_REPO_NAME}.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -pRx '@Bucket\.repo-name=${_TEST_REPO_NAME},' -pRxNot 'BlobStore\.blob-name=' -P -H" "${_out_file}"
    if [ "$?" == "0" ] && [ ! -s "${_out_file}" ]; then
        echo "TEST=OK : ${_out_file} is empty"
    else
        echo "TEST=ERROR: ${_out_file} should be empty (check /tmp/test_last.*)"
        return 1
    fi
}

function test_3_FindFromTextFile() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    _find_sample_repo_name "${_b}" "${_p}" || return 1

    local _out_file="/tmp/test_from-textfile.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -rF /tmp/test_finding_${_TEST_REPO_NAME}-n10.tsv -P -f '\.properties' -H" "${_out_file}"
    if [ "$?" == "0" ] && [ -s "${_out_file}" ]; then
        local _orig_num="$(_line_num /tmp/test_finding_${_TEST_REPO_NAME}-n10.tsv)"
        local _result_num="$(_line_num ${_out_file})"
        if [ ${_result_num:-"0"} -gt 0 ] && [ "${_orig_num}" -eq "${_result_num}" ]; then
            echo "TEST=OK : The number of lines in the original file and the result file are the same (${_result_num})"
        else
            echo "TEST=ERROR: The number of lines in /tmp/test_finding_${_TEST_REPO_NAME}-n10.tsv (${_orig_num}) and ${_out_file} (${_result_num}) are different"
            return 1
        fi
        rg -o "[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}" /tmp/test_finding_${_TEST_REPO_NAME}-n10.tsv | while read _id; do
            if ! rg -q "${_id}" ${_out_file}; then
                echo "TEST=ERROR: Could not find ${_id} in ${_out_file} (check /tmp/test_last.*)"
                return 1
            fi
        done
    else
        echo "TEST=ERROR: ${_out_file} might be empty (check /tmp/test_last.*)"
        return 1
    fi
}

function test_4_SizeAndCount() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"

    local _out_file="/tmp/test_count_size.tsv"
    _TEST_MAX_NUM=0 _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -f '.bytes' -H" "${_out_file}"
    local _result="$(rg "Listed.+ Size: (\d+) bytes" -o -r '$1' /tmp/test_last.err)"
    if [ -z "${_result}" ]; then
        echo "TEST=ERROR: Could not find 'Listed.+ bytes' in /tmp/test_last.err"
        return 1
    fi

    # If not File type, return in here (TODO: add other types)
    if [[ "${_b}" =~ ^(s3|az):// ]]; then
        echo "TEST=OK : ${_result}"
        return 0
    fi

    local _find="find"
    type gfind &>/dev/null && _find="gfind"
    # As the new blob store layout introduced the deletion marker files, can't count the files easily, so checking only the size.
    local _expect_cmd="${_find} ${_b} -type f -name '*.bytes*' \( -path '*content/vol-*' -o  -path '*content/20*' \) -printf '%s\n' | awk '{ s+=\$1 }; END { print s }'"
    echo "DEBUG: expect_cmd=${_expect_cmd}" >&2
    local _expect="$(eval "${_expect_cmd}")"

    if [ -n "${_expect}" ] && [ "${_result}" == "${_expect}" ]; then
        echo "TEST=OK : ${_result}"
    else
        echo "TEST=ERROR: '${_result}' != '${_expect}'"
        return 1
    fi
}

function test_5_Undelete() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    _find_sample_repo_name "${_b}" "${_p}" || return 1

    local _prep_file="/tmp/test_soft-deleted_${_TEST_REPO_NAME}-n10.tsv"
    local _out_file="/tmp/test_undeleting_${_TEST_REPO_NAME}.tsv"
    local _last_rc=""
    local _should_not_find_soft_delete=true

    # Find 10 NOT soft-deleted .properties files
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -pRx '@Bucket\.repo-name=${_TEST_REPO_NAME}' -pRxNot 'deleted=true' -n 10 -H" "${_prep_file}"
    if [ -s "${_prep_file}" ]; then
        # Append 'deleted=true' in each blob by reading the tsv file
        _exec_filelist "filelist2 -b '${_b}' -rF ${_prep_file} -wStr \"deleted=true\" -P -H" "/tmp/test_preparing-soft-deleted_${_TEST_REPO_NAME}.tsv"
        if [ "$?" != "0" ]; then
            echo "TEST=ERROR: Could not prepare soft-delete ${_prep_file} (check /tmp/test_last.*)"
            return 1
        fi
        _log "INFO" "Waiting 3 seconds to avoid 'Skipping path:xxxxxxx as recently modified' message ..."
        sleep 3
        _exec_filelist "filelist2 -b '${_b}' -rF ${_prep_file} -RDel -P -H" "${_out_file}"
        _last_rc="$?"
    else
        _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -pRx '@Bucket\.repo-name=${_TEST_REPO_NAME}' -pRx 'deleted=true' -n 10 -H" "${_prep_file}"
        if [ ! -s "${_prep_file}" ]; then
            echo "TEST=WARN: No soft-deleted files found for ${_TEST_REPO_NAME} in ${_prep_file}, so skipping ${FUNCNAME[0]}"
            return 0
        fi
        _exec_filelist "filelist2 -b '${_b}' -rF ${_prep_file} -RDel -P -H" "${_out_file}"
        _last_rc="$?"
        _log "INFO" "Restoring blob status by soft-deleting again (${_out_file}) ..."
        _exec_filelist "filelist2 -b '${_b}' -rF ${_out_file} -wStr \"deleted=true\" -P -H" "/tmp/test_restoring-soft-deleted_${_TEST_REPO_NAME}.tsv" "" "_restore_soft_delete"
        if [ "$?" != "0" ]; then
            echo "TEST=WARN: Restoring the soft-delete status failed ${_prep_file} (check /tmp/test_last_restore_soft_delete.*)"
        fi
        _should_not_find_soft_delete=false
    fi

    if [ "${_last_rc}" == "0" ]; then
        if ! rg -q "deleted=true" ${_out_file}; then
            echo "TEST=ERROR: Not found 'deleted=true' in ${_out_file} (check /tmp/test_last.*)"
            return 1
        fi
        if [[ "${_b}" =~ ^(s3|az):// ]]; then
            _log "INFO" "Waiting 3 seconds to wait for S3/Az to complete the writing ..."
            sleep 3
        fi
        _out_file="/tmp/test_check_undeleted_${_TEST_REPO_NAME}.tsv"
        _exec_filelist "filelist2 -b '${_b}' -rF ${_prep_file} -P -H" "${_out_file}" "_check"
        if ${_should_not_find_soft_delete} && rg -q "deleted=true" ${_out_file}; then
            echo "TEST=ERROR: Found 'deleted=true' in ${_out_file} (check /tmp/test_last_check*)"
            return 1
        fi
        if ! ${_should_not_find_soft_delete} && ! rg -q "deleted=true" ${_out_file}; then
            echo "TEST=WARN: Should find 'deleted=true' but didn't in ${_out_file} (check /tmp/test_last_check*)"
            return 1
        fi
        echo "TEST=OK : no 'deleted=true' in the first 10 lines of ${_out_file} (compare with ${_prep_file})"
    else
        echo "TEST=ERROR: Could not undelete ${_prep_file} result: /tmp/test_undeleted_${_TEST_REPO_NAME}.tsv (check /tmp/test_last.*)"
        return 1
    fi
}

function test_6_Orphaned() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    local _work_dir="${3:-"${_TEST_WORKDIR}"}"
    #local _blob_id="$(uuidgen)"
    #filelist2 -b "$BLOB_STORE" -p '/(vol-\d\d|20\d\d)/' -c 10 -src BS -db "host=localhost user=nexus dbname=nexus" -s ./orphaned_blobs_Src-BS.tsv
    local _nexus_store="$(find ${_work_dir%/} -maxdepth 3 -name 'nexus-store.properties' -path '*/etc/fabric/*' -print | head -n1)"
    if [ -z "${_nexus_store}" ]; then
        echo "TEST=ERROR: Could not find nexus-store.properties in workdir: ${_work_dir}"
        return 1
    fi
    [ -n "${_TEST_DB_CONN_PWD}" ] && export PGPASSWORD="${_TEST_DB_CONN_PWD}"

    local _out_file="/tmp/test_orphaned.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -src BS -db ${_nexus_store} -pRxNot \"deleted=true\" -BytesChk -H" "${_out_file}"
    if [ "$?" == "0" ]; then
        echo "TEST=OK (${_out_file})"
        echo "To remove: cat ${_out_file} | sed -n -E 's/^(.+)\.properties.+/\1/p' | xargs -P2 -t -I{} mv {}.{properties,bytes} /tmp/"
    else
        echo "TEST=ERROR: Could not generate ${_out_file} (check /tmp/test_last.*)"
        return 1
    fi

    local _out_file="/tmp/test_orphaned_should_find_some.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -src BS -db ${_nexus_store} -pRx \"deleted=true\" -P -H" "${_out_file}"
    if [ "$?" == "0" ]; then
        local _expected_num="$(_line_num ${_out_file})"
        if [ ${_expected_num:-"0"} -gt 0 ]; then
            echo "TEST=OK : ${_out_file}, expected:${_expected_num}"
        echo "To remove: cat ${_out_file} | sed -n -E 's/^(.+)\.properties.+/\1/p' | xargs -P2 -t -I{} mv {}.{properties,bytes} /tmp/"
        else
            echo "TEST=WARN: ${_out_file} should not be empty (or no soft-deleted blobs) (check /tmp/test_last.*)"
        fi
    else
        echo "TEST=ERROR: Could not generate ${_out_file} (check /tmp/test_last.*)"
        return 1
    fi
}

function test_7_DeadBlob() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    local _work_dir="${3:-"${_TEST_WORKDIR}"}"
    #local _blob_id="$(uuidgen)"
    #filelist2 -b "$BLOB_STORE" -p '/(vol-\d\d|20\d\d)/' -c 10 -src BS -db "host=localhost user=nexus dbname=nexus" -s ./orphaned_blobs_Src-BS.tsv
    local _nexus_store="$(find ${_work_dir%/} -maxdepth 3 -name 'nexus-store.properties' -path '*/etc/fabric/*' -print | head -n1)"
    if [ -z "${_nexus_store}" ]; then
        echo "TEST=ERROR: Could not find nexus-store.properties in ${_work_dir}"
        return 1
    fi
    [ -n "${_TEST_DB_CONN_PWD}" ] && export PGPASSWORD="${_TEST_DB_CONN_PWD}"

    rm -f /tmp/test8_prep_query.out || return $?
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -src BS -db ${_nexus_store} -query \"select blob_ref as blob_id from raw_asset_blob order by asset_blob_id desc limit 1\" -rF /tmp/test8_prep_query.out" ""
    if [ ! -s "/tmp/test8_prep_query.out" ]; then
        echo "TEST=WARN Skipped as could not prepare blob ids from DB (check /tmp/test_last.* and /tmp/test8_prep_query.out)"
        return 0
    fi
    cat /tmp/test8_prep_query.out | xargs -I{} blobpath {} | xargs -I{} mv "${_b%/}/content/{}" "${_b%/}/content/{}.bak"
    local _out_file="/tmp/test_deadblob.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -src BS -db ${_nexus_store} -query \"select blob_ref as blob_id from raw_asset_blob order by asset_blob_id desc limit 1\" -src DB -H" "${_out_file}"
    local _final_rc="$?"
    if [ "${_final_rc}" == "0" ]; then
        echo "TEST=OK (${_out_file})"
    else
        echo "TEST=ERROR: Could not generate ${_out_file} (check /tmp/test_last.*)"
    fi
    cat /tmp/test8_prep_query.out | xargs -I{} blobpath {} | xargs -I{} mv "${_b%/}/content/{}.bak" "${_b%/}/content/{}"
    return ${_final_rc}
}

function test_8_TextFileToCheckBlobStore() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    local _work_dir="${3:-"${_TEST_WORKDIR}"}"

    if [[ "${_b}" =~ ^(s3|az):// ]]; then
        echo "TEST=WARN Skipped as this test is not for S3/Az for now."
        return 0
    fi
    local _find="find"
    type gfind &>/dev/null && _find="gfind"

    ${_find} ${_b%/} -name '*.properties' \( -path '*content/vol-*' -o  -path '*content/20*' \) -print | head -n10 >/tmp/test_mock_blob_ids.txt
    if [ ! -s "/tmp/test_mock_blob_ids.txt" ]; then
        echo "TEST=ERROR: No mock .properties files found in ${_b}"
        return 1    # Environment issue but return 1
    fi

    local _out_file="/tmp/test_blobs_in_BS.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -rF /tmp/test_mock_blob_ids.txt -H" "${_out_file}"
    if [ "$?" != "0" ]; then
        echo "TEST=ERROR: Could not generate ${_out_file} (check /tmp/test_last.*)"
        return 1
    fi
    local _expected_num="$(_line_num /tmp/test_mock_blob_ids.txt)"
    local _result_num="$(_line_num ${_out_file})"
    if [ ${_expected_num:-"0"} -gt 0 ] && [ "$((${_expected_num} * 2))" -eq "${_result_num}" ]; then
        echo "TEST=OK (${_out_file})"
    else
        echo "TEST=ERROR: [ expected:${_expected_num} * 2 -eq result:${_result_num} ] is false"
        return 1
    fi

    local _out_file="/tmp/test_blobs_in_BS2.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -rF /tmp/test_mock_blob_ids.txt -H -P -f '\.properties'" "${_out_file}"
    if [ "$?" != "0" ]; then
        echo "TEST=ERROR: Could not generate ${_out_file} (check /tmp/test_last.*)"
        return 1
    fi
    local _expected_num="$(_line_num /tmp/test_mock_blob_ids.txt)"
    local _result_num="$(_line_num ${_out_file})"
    if [ ${_expected_num:-"0"} -gt 0 ] && [ "${_expected_num}" -eq "${_result_num}" ]; then
        echo "TEST=OK (${_out_file})"
    else
        echo "TEST=ERROR: [ expected:${_expected_num} -eq result:${_result_num} ] is false"
        return 1
    fi
}

function test_9_TextFileToCheckDatabase() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    local _work_dir="${3:-"${_TEST_WORKDIR}"}"

    if [[ "${_b}" =~ ^(s3|az):// ]]; then
        echo "TEST=WARN Skipped as no need to test if S3/Az."
        return 0
    fi

    local _nexus_store="$(find ${_work_dir%/} -maxdepth 3 -name 'nexus-store.properties' -path '*/etc/fabric/*' -print | head -n1)"
    if [ -z "${_nexus_store}" ]; then
        echo "TEST=ERROR: Could not find nexus-store.properties in workdir: ${_work_dir}"
        return 1
    fi
    [ -n "${_TEST_DB_CONN_PWD}" ] && export PGPASSWORD="${_TEST_DB_CONN_PWD}"

    #find ${_b%/} -maxdepth 4 -name '*.properties' -path '*/content/vol*' -print | head -n10 >/tmp/test_mock_blob_ids.txt
    # Assuming / hoping the newer files wouldn't be orphaned files.
    # Can not use -pRxNot 'deletedReason=' and '-n 1000' with the new blob store layout...
    _TEST_MAX_NUM=100000 _exec_filelist "filelist2 -b ${_b} -p '${_p}' -pRxNot 'deleted=true' -BytesChk" "/tmp/test_mock_blob_ids.tmp"
    #cat /tmp/test_mock_blob_ids.tmp | sort -k2r,3r | head -n10 > /tmp/test_mock_blob_ids.txt
    # Excluding BYTES_MISSING as probably deletion markers
    rg -v "BYTES_MISSING" /tmp/test_mock_blob_ids.tmp | rg '/([^/]+\.properties)' -o -r '$1' | sort | uniq -c | rg '^\s*1\s(\S+)' -o -r '$1' | head -n10 > /tmp/test_mock_blob_ids_maybeNotDeleted.tmp
    cat /tmp/test_mock_blob_ids_maybeNotDeleted.tmp | xargs -P2 -I{} rg "content/.*{}" -o -m1 /tmp/test_mock_blob_ids.tmp > /tmp/test_mock_blob_ids.txt
    if [ ! -s "/tmp/test_mock_blob_ids.txt" ]; then
        echo "TEST=WARN: No mock .properties files found in ${_b}, so skipping"
        return 0
    fi

    local _out_file="/tmp/test_assets_from_db.tsv"
    # [INFO] [main.setGlobals:206] BlobIDFIle is provided but no BaseDir and -src is missing. Assuming '-src BS' to find Orphaned blobs
    _exec_filelist "filelist2 -db ${_nexus_store} -bsName $(basename "${_b}") -rF /tmp/test_mock_blob_ids.txt -H" "${_out_file}"
    local _expected_num="$(_line_num /tmp/test_mock_blob_ids.txt)"
    local _result_num="$(_line_num ${_out_file})"
    if [ ${_result_num:-"0"} -gt 0 ]; then
        echo "TEST=OK (${_out_file}) expected:${_expected_num}, result:${_result_num}"
    else
        echo "TEST=ERROR: [ expected:${_expected_num} -eq result:${_result_num} ] is false (check /tmp/test_last.*)"
        return 1
    fi
}

function test_10_GenerateBlobIDsFileFromDB() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    local _work_dir="${3:-"${_TEST_WORKDIR}"}"

    if [[ "${_b}" =~ ^(s3|az):// ]]; then
        echo "TEST=WARN Skipped as no need to test if S3/Az."
        return 0
    fi

    local _nexus_store="$(find ${_work_dir%/} -maxdepth 3 -name 'nexus-store.properties' -path '*/etc/fabric/*' -print | head -n1)"
    if [ -z "${_nexus_store}" ]; then
        echo "TEST=ERROR: Could not find nexus-store.properties in the workdir: ${_work_dir}"
        return 1
    fi
    [ -n "${_TEST_DB_CONN_PWD}" ] && export PGPASSWORD="${_TEST_DB_CONN_PWD}"

    local _out_file="/tmp/test_blobIds_from_db.tsv"
    _exec_filelist "filelist2 -b '${_b}' -db ${_nexus_store} -bsName $(basename "${_b}") -query \"select blob_ref as blob_id from raw_asset_blob where blob_ref like '$(basename "${_b}")@%' limit 10\" -H" "${_out_file}"
    local _result_num="$(_line_num ${_out_file})"
    if [ ${_result_num:-"0"} -gt 0 ]; then
        echo "TEST=OK (${_out_file}) result:${_result_num}"
    else
        echo "TEST=ERROR: result:${_result_num} (check /tmp/test_last.*)"
        echo "May need to run f_setup_raw && f_upload_dummies_raw first"
        return 1
    fi
}


### Utility functions
function _log_duration() {
    local _started="$1"
    local _log_msg="${2:-"Completed ${FUNCNAME[1]}"}"
    [ -z "${_started}" ] && return
    local _ended="$(date +%s)"
    local _diff=$((${_ended} - ${_started}))
    local _log_level="DEBUG"
    if [ ${_diff:-0} -ge 3 ]; then
        _log_level="INFO"
    fi
    echo "[${_log_level}] ${_log_msg} in ${_diff}s" >&2
}
function _line_num() {
    local _file="$1"
    wc -l "${_file}" | awk '{print $1}'
}
function _log() {
    local _log_file="${_LOG_FILE_PATH:-"/dev/null"}"
    local _is_debug="${_DEBUG:-false}"
    if [ "$1" == "DEBUG" ] && ! ${_is_debug}; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >>${_log_file}
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a ${_log_file}
    fi 1>&2 # At this moment, outputting to STDERR
}
function _exec_filelist() {
    local _cmd_without_s="$1"
    local _out_file="$2"
    local _stdouterr_sfx="$3"
    if [ -s "${_out_file}" ]; then
        rm -f "${_out_file}" || return $?
    fi
    local _cmd="${_cmd_without_s}"
    if [ -n "${_out_file}" ]; then
        _cmd="${_cmd} -s '${_out_file}'"
    fi
    if rg -q ' -b +.?s3://' <<<"${_cmd_without_s}"; then    # this is S3 only (not Azure)
        _cmd="${_cmd} -c 2 -c2 8"
    else
        _cmd="${_cmd} -c 10"
    fi
    if [ ${_TEST_MAX_NUM:-0} -gt 0 ]; then
        _cmd="${_cmd} -n ${_TEST_MAX_NUM}"
    fi
    _log "INFO" "Running: ${_cmd}"
    eval "${_cmd}" >"/tmp/test_last${_stdouterr_sfx}.out" 2>"/tmp/test_last${_stdouterr_sfx}.err"
}
function _find_sample_repo_name() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    [ -n "${_b}" ] && export _TEST_BLOBSTORE="${_b}"
    [ -n "${_p}" ] && export _TEST_FILTER_PATH="${_p}"
    [ -n "${_TEST_REPO_NAME}" ] && return 0

    if [[ "${_b}" =~ ^s3:// ]]; then
        if [ -z "${_TEST_S3_REPO}" ]; then
            _log "WARN" "No _TEST_S3_REPO found"
            return 1
        fi
        export _TEST_REPO_NAME="${_TEST_S3_REPO}"
        return 0
    fi

    if [[ "${_b}" =~ ^az:// ]]; then
        if [ -z "${_TEST_AZ_REPO}" ]; then
            _log "WARN" "No _TEST_AZ_REPO found"
            return 1
        fi
        export _TEST_REPO_NAME="${_TEST_AZ_REPO}"
        return 0
    fi

    # Finding _rn (repository name) which has at lest 10 .properties files. NOTE: ` -d 4` does not work with the new blob store layout
    local _rn="$(rg --no-filename -g '*.properties' "^@Bucket.repo-name=(\S+)$" -o -r '$1' ${_b%/} | head -n100 | sort | uniq -c | sort -nr | head -n1 | rg -o '^\s*\d+\s+(\S+)$' -r '$1')"
    if [ -z "${_rn}" ]; then
        _log "WARN" "No repo-name found in path: ${_b}"
        return 1
    fi
    _log "INFO" "Using repo-name ${_rn}"
    export _TEST_REPO_NAME="${_rn}"
}



function main() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"   # blobstore
    local _p="${2:-"${_TEST_FILTER_PATH}"}" # path/prefix TODO: If S3, also should support an empty prefix?

    _find_sample_repo_name "${_b}" "${_p}" || return 1

    local _pfx="test_"
    local _tmp="$(mktemp -d)"
    # The function names should start with 'test_', and sorted
    for _t in $(typeset -F | grep "^declare -f ${_pfx}" | cut -d' ' -f3 | sort); do
        local _started="$(date +%s)"
        _log "INFO" "Starting TEST: ${_t} (${_started}) ..."

        if ! eval "${_t} && _log_duration \"${_started}\"" && ${_TEST_STOP_ERROR}; then
            return $?
        fi
    done
    _log "INFO" "Completed all tests."
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
