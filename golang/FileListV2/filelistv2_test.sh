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
# If File type blobstore:
#   export _TEST_WORKDIR="$HOME/Documents/tests/nxrm_3.70.3-01_rmfilelisttest/sonatype-work/nexus3"
#   export _TEST_BLOBSTORE="${_TEST_WORKDIR%/}/blobs/default"
#   $HOME/IdeaProjects/samples/golang/FileListV2/filelistv2_test.sh
#
# Prepare the test data using setup_nexus3_repos.sh:
#   _AUTO=true main
#   f_upload_dummies_all_hosted
#   f_delete_all_assets
#   #f_run_tasks_by_type "assetBlob.cleanup" # if Postgresql with nexus.assetBlobCleanupTask.blobCreatedDelayMinute=0

### Global variables
: ${_TEST_WORKDIR:=""}      #./sonatype-work/nexus3
: ${_TEST_BLOBSTORE:=""}    #./sonatype-work/nexus3/blobs/default
: ${_TEST_FILTER_PATH:="vol-"}
: ${_TEST_DB_CONN:=""}      #host=localhost user=nexus dbname=nxrm
: ${_TEST_DB_CONN_PWD:="nexus123"}
: ${_TEST_STOP_ERROR:=true}
: ${_TEST_REPO_NAME:=""}
: ${_TEST_BLOB_ID:=""}


### Test functions
function test_1_First10FilesForSpecificRepo() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    _find_sample_repo_name "${_b}" "${_p}" || return 1

    local _out_file="/tmp/test_finding-${_TEST_REPO_NAME}-n10.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -pRx '@Bucket\.repo-name=${_TEST_REPO_NAME},' -P -c 40" "${_out_file}"
    if [ "$?" == "0" ] && rg -q "${_TEST_BLOB_ID}" ${_out_file}; then
        echo "TEST=OK Found ${_TEST_BLOB_ID} in ${_out_file}"
    else
        echo "TEST=ERROR: Could not find ${_TEST_BLOB_ID} in ${_out_file} (check /tmp/test_last.*)"
        return 1
    fi
}

function test_2_ShouldNotFindAny() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    _find_sample_repo_name "${_b}" "${_p}" || return 1

    local _out_file="/tmp/test_not-finding-${_TEST_REPO_NAME}.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -pRx '@Bucket\.repo-name=${_TEST_REPO_NAME},' -pRxNot 'BlobStore\.blob-name=' -P -c 80" "${_out_file}"
    if [ "$?" == "0" ] && ! rg -q "${_TEST_BLOB_ID}" ${_out_file}; then
        echo "TEST=OK : Did not find ${_TEST_BLOB_ID} in ${_out_file}"
    else
        echo "TEST=ERR: Should not have found ${_TEST_BLOB_ID} in ${_out_file} (check /tmp/test_last.*)"
        return 1
    fi
}

function test_3_FindFromTextFile() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    _find_sample_repo_name "${_b}" "${_p}" || return 1

    local _out_file="/tmp/test_from-textfile.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -rF /tmp/test_finding-${_TEST_REPO_NAME}-n10.tsv -P -f '\.properties' " "${_out_file}"
    if [ "$?" == "0" ] && rg -q "${_TEST_BLOB_ID}" ${_out_file}; then
        #echo "TEST=OK : Found ${_TEST_BLOB_ID} in ${_out_file}"
        local _orig_num="$(wc -l /tmp/test_finding-${_TEST_REPO_NAME}-n10.tsv | awk '{print $1}')"
        local _result_num="$(wc -l ${_out_file} | awk '{print $1}')"
        if [ ${_result_num:-"0"} -gt 0 ] && [ "${_orig_num}" -eq "${_result_num}" ]; then
            echo "TEST=OK : The number of lines in the original file and the result file are the same (${_result_num})"
        else
            echo "TEST=ERR: The number of lines in /tmp/test_finding-${_TEST_REPO_NAME}-n10.tsv (${_orig_num}) and ${_out_file} (${_result_num}) are different"
            return 1
        fi
        rg -o "[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}" /tmp/test_finding-${_TEST_REPO_NAME}-n10.tsv | while read _id; do
            if ! rg -q "${_id}" ${_out_file}; then
                echo "TEST=ERR: Could not find ${_id} in ${_out_file} (check /tmp/test_last.*)"
                return 1
            fi
        done
    else
        echo "TEST=ERR: Could not find ${_TEST_BLOB_ID} in ${_out_file} (check /tmp/test_last.*)"
        return 1
    fi
}

function test_4_SizeAndCount() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"

    local _out_file="/tmp/test_count_size.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -f '.bytes'" "${_out_file}"
    local _result="$(rg "Listed.+ bytes" -o /tmp/test_last.err)"
    if [ -z "${_result}" ]; then
        echo "TEST=ERR: Could not find 'Listed.+ bytes' in /tmp/test_last.err"
        return 1
    fi

    # TODO: if not File type, return in here
    local _find="find"
    type gfind &>/dev/null && _find="gfind"
    # "c*2" is because the filelist2 checks both .properties and .bytes files
    local _expect="$(${_find} ${_b} -type f -name '*.bytes*' -path "*${_p}*" -printf '%s\n' | awk '{ c+=1;s+=$1 }; END { print "Listed: "c" (checked: "c*2"), Size: "s" bytes" }')"
    if [ "${_result}" == "${_expect}" ]; then
        echo "TEST=OK : ${_result}"
    else
        echo "TEST=ERR: ${_result} != ${_expect}"
        return 1
    fi
}

function test_5_Undelete() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    _find_sample_repo_name "${_b}" "${_p}" || return 1

    local _prep_file="/tmp/test_soft-deleted-${_TEST_REPO_NAME}-n10.tsv"
    # Find 10 NOT soft-deleted .properties files
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -pRx '@Bucket\.repo-name=${_TEST_REPO_NAME}' -pRxNot 'deleted=true' -n 10 -H -c 10" "${_prep_file}"
    if [ ! -s "${_prep_file}" ]; then
        echo "TEST=WARN: No non-soft-deleted (normal) files found for ${_TEST_REPO_NAME} in ${_prep_file}, so skipping ${FUNCNAME[0]}"
        return 0
    fi
    # Append 'deleted=true' in each file in the tsv file
    _exec_filelist "filelist2 -b '${_b}' -rF ${_prep_file} -wStr \"deleted=true\" -c 10" "/tmp/test_dummy-soft-deleted-${_TEST_REPO_NAME}.tsv"
    if [ "$?" != "0" ]; then
        echo "TEST=ERROR: Could not soft-delete ${_prep_file} (check /tmp/test_last.*)"
        return 1
    fi

    local _out_file="/tmp/test_undeleting-${_TEST_REPO_NAME}.tsv"
    _exec_filelist "filelist2 -b '${_b}' -rF ${_prep_file} -RDel -P -H -c 10" "${_out_file}"
    if [ "$?" == "0" ]; then
        if ! rg -q "deleted=true" ${_out_file}; then
            echo "TEST=ERROR: Not found 'deleted=true' in ${_out_file} (check /tmp/test_last.*)"
            return 1
        fi
        _out_file="/tmp/test_undeleted-${_TEST_REPO_NAME}.tsv"
        _exec_filelist "filelist2 -b '${_b}' -rF ${_prep_file} -P -H -c 10" "${_out_file}"
        if rg -q "deleted=true" ${_out_file}; then
            echo "TEST=ERROR: Found 'deleted=true' in ${_out_file} (check /tmp/test_last.*)"
            return 1
        fi
        echo "TEST=OK Found ${_TEST_BLOB_ID} in ${_out_file} (compare with ${_prep_file})"
    else
        echo "TEST=ERROR: Could not undelete ${_prep_file} result: /tmp/test_undeleted-${_TEST_REPO_NAME}.tsv (check /tmp/test_last.*)"
        return 1
    fi
}

function test_6_Orphaned() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    local _work_dir="${3:-"${_TEST_WORKDIR}"}"
    #local _blob_id="$(uuidgen)"
    #filelist2 -b "$BLOB_STORE" -p 'vol-' -c 10 -src BS -db "host=localhost user=nexus dbname=nexus" -s ./orphaned_blobs_Src-BS.tsv
    local _nexus_store="$(find ${_work_dir%/} -maxdepth 3 -name 'nexus-store.properties' -path '*/etc/fabric/*' -print | head -n1)"
    if [ -z "${_nexus_store}" ]; then
        echo "TEST=ERROR: Could not find nexus-store.properties in ${_work_dir}"
        return 1
    fi
    [ -n "${_TEST_DB_CONN_PWD}" ] && export PGPASSWORD="${_TEST_DB_CONN_PWD}"

    local _out_file="/tmp/test_orphaned.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -c 10 -src BS -db ${_nexus_store} -pRxNot \"deleted=true\"" "${_out_file}"
    if [ "$?" == "0" ]; then
        echo "TEST=OK (${_out_file})"
    else
        echo "TEST=ERROR: Could not generate ${_out_file} (check /tmp/test_last.*)"
        return 1
    fi
}

function test_7_TextFileToCheckBlobStore() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    local _work_dir="${3:-"${_TEST_WORKDIR}"}"

    find ${_b%/} -maxdepth 4 -name '*.properties' -path '*/content/vol*' -print | head -n10 >/tmp/test_mock_blob_ids.txt
    if [ ! -s "/tmp/test_mock_blob_ids.txt" ]; then
        echo "TEST=ERROR: No mock .properties files found in ${_b}"
        return 1    # Environment issue but return 1
    fi

    local _out_file="/tmp/test_blobs_in_BS.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -c 10 -rF /tmp/test_mock_blob_ids.txt -H" "${_out_file}"
    if [ "$?" != "0" ]; then
        echo "TEST=ERROR: Could not generate ${_out_file} (check /tmp/test_last.*)"
        return 1
    fi
    local _expected_num="$(wc -l /tmp/test_mock_blob_ids.txt | awk '{print $1}')"
    local _result_num="$(wc -l ${_out_file} | awk '{print $1}')"
    if [ ${_expected_num:-"0"} -gt 0 ] && [ "$((_expected_num * 2))" -eq "${_result_num}" ]; then
        echo "TEST=OK (${_out_file})"
    else
        echo "TEST=ERROR: [ expected:${_expected_num}*2 -eq result:${_result_num} ] is false"
        return 1
    fi

    local _out_file="/tmp/test_blobs_in_BS2.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -c 10 -rF /tmp/test_mock_blob_ids.txt -H -P -f '\.properties'" "${_out_file}"
    if [ "$?" != "0" ]; then
        echo "TEST=ERROR: Could not generate ${_out_file} (check /tmp/test_last.*)"
        return 1
    fi
    local _expected_num="$(wc -l /tmp/test_mock_blob_ids.txt | awk '{print $1}')"
    local _result_num="$(wc -l ${_out_file} | awk '{print $1}')"
    if [ ${_expected_num:-"0"} -gt 0 ] && [ "${_expected_num}" -eq "${_result_num}" ]; then
        echo "TEST=OK (${_out_file})"
    else
        echo "TEST=ERROR: [ expected:${_expected_num} -eq result:${_result_num} ] is false"
        return 1
    fi
}


function test_8_TextFileToCheckDatabase() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    local _work_dir="${3:-"${_TEST_WORKDIR}"}"
    local _nexus_store="$(find ${_work_dir%/} -maxdepth 3 -name 'nexus-store.properties' -path '*/etc/fabric/*' -print | head -n1)"
    if [ -z "${_nexus_store}" ]; then
        echo "TEST=ERROR: Could not find nexus-store.properties in ${_work_dir}"
        return 1
    fi
    [ -n "${_TEST_DB_CONN_PWD}" ] && export PGPASSWORD="${_TEST_DB_CONN_PWD}"

    find ${_b%/} -maxdepth 4 -name '*.properties' -path '*/content/vol*' -print | head -n10 >/tmp/test_mock_blob_ids.txt
    if [ ! -s "/tmp/test_mock_blob_ids.txt" ]; then
        echo "TEST=WARN: No mock .properties files found in ${_b}, so skipping"
        return 0
    fi

    local _out_file="/tmp/test_assets_from_db.tsv"
    _exec_filelist "filelist2 -db ${_nexus_store} -bsName $(basename "${_b}") -c 10 -rF /tmp/test_mock_blob_ids.txt -H" "${_out_file}"
    local _expected_num="$(wc -l /tmp/test_mock_blob_ids.txt | awk '{print $1}')"
    local _result_num="$(wc -l ${_out_file} | awk '{print $1}')"
    if [ ${_result_num:-"0"} -gt 0 ]; then
        echo "TEST=OK (${_out_file}) expected:${_expected_num}, result:${_result_num}"
    else
        echo "TEST=ERROR: [ expected:${_expected_num} -eq result:${_result_num} ] is false (check /tmp/test_last.*)"
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
    if [ -s "${_out_file}" ]; then
        rm -v -f "${_out_file}" || return $?
    fi
    local _cmd="${_cmd_without_s} -s ${_out_file}"
    _log "INFO" "Running: ${_cmd}"
    eval "${_cmd}" >/tmp/test_last.out 2>/tmp/test_last.err
}
function _find_sample_repo_name() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    [ -z "${_TEST_BLOBSTORE}" ] && export _TEST_BLOBSTORE="${_b}"
    [ -z "${_TEST_FILTER_PATH}" ] && export _TEST_FILTER_PATH="${_p}"
    [ -n "${_TEST_REPO_NAME}" ] && return 0

    # Found _rn (repository name) which has at lest 10 .properties files
    local _rn="$(rg --no-filename -d 4 -g '*.properties' "^@Bucket.repo-name=(\S+)$" -o -r '$1' ${_b%/} | head -n100 | sort | uniq -c | sort -nr | head -n1 | rg -o '^\s*\d+\s+(\S+)$' -r '$1')"
    if [ -z "${_rn}" ]; then
        _log "WARN" "No repo-name found in ${_prop}"
        return 1
    fi
    export _TEST_REPO_NAME="${_rn}"

    _log "INFO" "Found a sample .properties file: ${_prop}"
    local _prop="$(rg -l -d 4 -g '*.properties' "^@Bucket.repo-name=${_TEST_REPO_NAME}$" ${_b%/} | head -n1)"
    local _blob_id="$(basename "${_prop}" ".properties")"
    if [ -z "${_blob_id}" ]; then
        _log "WARN" "No blob-id found in ${_prop}"
        return 1
    fi
    export _TEST_BLOB_ID="${_blob_id}"
}



# TODO: currently only works with File type blobstore
function main() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"   # blobstore
    local _p="${2:-"${_TEST_FILTER_PATH}"}" # path/prefix TODO: If S3, also should support an empty prefix?

    _find_sample_repo_name "${_b}" "${_p}" || return 1

    local _pfx="test_"
    local _tmp="$(mktemp -d)"
    # The function names should start with 'test_', and sorted
    for _t in $(typeset -F | grep "^declare -f ${_pfx}" | cut -d' ' -f3 | sort); do
        local _started="$(date +%s)"
        _log "INFO" "Started ${_t} (${_started}) ..."

        if ! eval "${_t} && _log_duration \"${_started}\"" && ${_TEST_STOP_ERROR}; then
            return $?
        fi
    done
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
