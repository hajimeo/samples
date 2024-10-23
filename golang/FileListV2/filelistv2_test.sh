#!/usr/bin/env bash
# Simple tests by just executing the commands and check the exit code.
# REQUIREMENTS:
#   'filelist2' in the $PATH
#   rg

function main() {
    local _b="$1"   # blobstore
    local _p="${2-"vol-"}"   # path TODO: or prefix if S3
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

    local _out_file="/tmp/test_finding-${_repo_name}.tsv"
    if [ -s "${_out_file}" ]; then
        rm -v -f "${_out_file}" || return $?
    fi
    local _cmd="filelist2 -b '${_b}' -p '${_p}' -pRx '@Bucket\.repo-name=${_repo_name},' -P -c 80 -s ${_out_file}"
    echo "[INFO] Running: ${_cmd}"
    eval "${_cmd}" >/tmp/test_last.out 2>/tmp/test_last.err || return $?
    if rg -q "${_blob_id}" ${_out_file}; then
        echo "TEST=OK Found ${_blob_id} in ${_out_file}"
    else
        echo "TEST=ERROR: Could not find ${_blob_id} in ${_out_file} (check /tmp/test_last.*)"
        return 1
    fi
}


if [ "$0" = "$BASH_SOURCE" ]; then
    main "$1" "$2"
fi
