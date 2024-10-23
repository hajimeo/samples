#!/usr/bin/env bash
# Simple tests by just executing the commands and check the exit code.
# REQUIREMENTS:
#   'filelist2' in the $PATH
#   rg

# TODO: currently only works with File type blobstore
function main() {
    local _b="$1"   # blobstore
    local _p="${2:-"vol-"}"   # path TODO: prefix if S3, also support empty prefix?
    echo "[INFO] Finding a sample .properties file in the blobstore: ${_b} ..."
    local _prop="$(find ${_b%/} -maxdepth 4 -name '*.properties' -path '*'${_p}'*' -print | head -n1)"
    if [ -z "${_prop}" ]; then
        echo "[ERROR] No .properties file found in ${_b} and ${_p}"
        return 1
    fi
    local _blob_id="$(basename "${_prop}" ".properties")"
    local _repo_name="$(rg '^@Bucket\.repo-name=(.+)' -o -r '$1' ${_prop})"
    if [ -z "${_repo_name}" ]; then
        echo "[ERROR] No repo-name found in ${_prop}"
        return 1
    fi

    local _out_file="/tmp/test_finding-${_repo_name}-n10.tsv"
    runner "filelist2 -b '${_b}' -p '${_p}' -pRx '@Bucket\.repo-name=${_repo_name},' -n 10 -P -c 10" "${_out_file}"
    if [ "$?" == "0" ] && rg -q "${_blob_id}" ${_out_file}; then
        echo "TEST=OK Found ${_blob_id} in ${_out_file}"
    else
        echo "TEST=ERROR: Could not find ${_blob_id} in ${_out_file} (check /tmp/test_last.*)"
        return 1
    fi

    local _out_file="/tmp/test_not-finding-${_repo_name}.tsv"
    runner "filelist2 -b '${_b}' -p '${_p}' -pRx '@Bucket\.repo-name=${_repo_name},' -pRxNot 'BlobStore\.blob-name=' -P -c 80" "${_out_file}"
    if [ "$?" == "0" ] && ! rg -q "${_blob_id}" ${_out_file}; then
        echo "TEST=OK Did not find ${_blob_id} in ${_out_file}"
    else
        echo "TEST=ERROR: May find ${_blob_id} in ${_out_file} (check /tmp/test_last.*)"
        return 1
    fi

    local _out_file="/tmp/test_from-textfile.tsv"
    runner "filelist2 -b '${_b}' -p '${_p}' -rF /tmp/test_finding-${_repo_name}-n10.tsv -P" "${_out_file}"
    if [ "$?" == "0" ] && rg -q "${_blob_id}" ${_out_file}; then
        echo "TEST=OK Found ${_blob_id} in ${_out_file}"
        local _orig_num="$(wc -l /tmp/test_finding-${_repo_name}-n10.tsv | awk '{print $1}')"
        local _result_num="$(wc -l ${_out_file} | awk '{print $1}')"
        if [ ${_result_num:-"0"} -le 11 ] && [ "${_orig_num}" -eq "${_result_num}" ]; then
            echo "TEST=OK The number of lines in the original file and the result file are the same (${_result_num})"
        else
            echo "TEST=ERROR: The number of lines in the original file (${_orig_num}) and the result file (${_result_num}) are different."
            return 1
        fi
        rg -o "[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}" /tmp/test_finding-${_repo_name}-n10.tsv | while read _id; do
            if ! rg -q "${_id}" ${_out_file}; then
                echo "TEST=ERROR: Could not find ${_id} in ${_out_file} (check /tmp/test_last.*)"
                return 1
            fi
        done
    else
        echo "TEST=ERROR: Could not find ${_blob_id} in ${_out_file} (check /tmp/test_last.*)"
        return 1
    fi
}

function runner() {
    local _cmd_without_s="$1"
    local _out_file="$2"
    if [ -s "${_out_file}" ]; then
        rm -v -f "${_out_file}" || return $?
    fi
    local _cmd="${_cmd_without_s} -s ${_out_file}"
    echo "[INFO] Running: ${_cmd}"
    eval "${_cmd}" >/tmp/test_last.out 2>/tmp/test_last.err
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$1" "$2"
fi
