#!/usr/bin/env bash
# Simple tests by just executing the commands and check the exit code.
#
# REQUIREMENTS:
#   'filelist2' in the $PATH
#   rg
#
# HOW TO RUN EXAMPLE:
#   ./filelistv2_test.sh <blobstore> <path/prefix>
#   $HOME/IdeaProjects/samples/golang/FileListV2/filelistv2_test.sh $HOME/Documents/tests/nxrm_3.70.1-02_nxrm3791ha/sonatype-work/nexus3/blobs/default
#

### Global variables
: ${_TEST_BLOBSTORE:=""} #./sonatype-work/nexus3/blobs/default
: ${_TEST_FILTER_PATH:="vol-"}
: ${_TEST_STOP_ERROR:=true}
: ${_TEST_REPO_NAME:=""}
: ${_TEST_BLOB_ID:=""}


### Test functions
function test_1_First10FilesForSpecificRepo() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    _find_sample_repo_name "${_b}" "${_p}" || return 1

    local _out_file="/tmp/test_finding-${_TEST_REPO_NAME}-n10.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -pRx '@Bucket\.repo-name=${_TEST_REPO_NAME},' -n 10 -P -c 10" "${_out_file}"
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
        echo "TEST=ERR: May find ${_TEST_BLOB_ID} in ${_out_file} (check /tmp/test_last.*)"
        return 1
    fi
}

function test_3_FindFromTextFile() {
    local _b="${1:-"${_TEST_BLOBSTORE}"}"
    local _p="${2:-"${_TEST_FILTER_PATH}"}"
    _find_sample_repo_name "${_b}" "${_p}" || return 1

    local _out_file="/tmp/test_from-textfile.tsv"
    _exec_filelist "filelist2 -b '${_b}' -p '${_p}' -rF /tmp/test_finding-${_TEST_REPO_NAME}-n10.tsv -P" "${_out_file}"
    if [ "$?" == "0" ] && rg -q "${_TEST_BLOB_ID}" ${_out_file}; then
        echo "TEST=OK : Found ${_TEST_BLOB_ID} in ${_out_file}"
        local _orig_num="$(wc -l /tmp/test_finding-${_TEST_REPO_NAME}-n10.tsv | awk '{print $1}')"
        local _result_num="$(wc -l ${_out_file} | awk '{print $1}')"
        if [ ${_result_num:-"0"} -le 11 ] && [ "${_orig_num}" -eq "${_result_num}" ]; then
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
    local _expect="$(${_find} ${_b} -type f -name '*.bytes*' -path "*${_p}*" -printf '%s\n' | awk '{ c+=1;s+=$1 }; END { print "Listed: "c" (checked: "c"), Size: "s" bytes" }')"
    if [ "${_result}" == "${_expect}" ]; then
        echo "TEST=OK : ${_result}"
    else
        echo "TEST=ERR: ${_result} != ${_expect}"
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
    if [ ${_diff} -ge ${_threshold} ]; then
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

    _log "INFO" "Finding a sample .properties file in the blobstore: ${_b} ..."
    local _prop="$(find ${_b%/} -maxdepth 4 -name '*.properties' -path '*'${_p}'*' -print | head -n1)"
    if [ -z "${_prop}" ]; then
        _log "WARN" "No .properties file found in ${_b} and ${_p}"
        return 1
    fi
    local _blob_id="$(basename "${_prop}" ".properties")"
    if [ -z "${_blob_id}" ]; then
        _log "WARN" "No blob-id found in ${_prop}"
        return 1
    fi
    export _TEST_BLOB_ID="${_blob_id}"
    local _rn="$(rg '^@Bucket\.repo-name=(.+)' -o -r '$1' ${_prop})"
    if [ -z "${_rn}" ]; then
        _log "WARN" "No repo-name found in ${_prop}"
        return 1
    fi
    export _TEST_REPO_NAME="${_rn}"
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
