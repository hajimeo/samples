#!/usr/bin/env bash
# DOWNLOAD:
#   curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/nexus_diag.sh
#
# This script is only for Linux|Mac with BASH.
#

function usage() {
    cat << EOS
Contain source-able and copy&paste-able functions, which are executed on the Nexus server, for troubleshooting various issues.
EOS
}


# Overridable global variables
: ${_WORK_DIR:="/var/tmp/share"}
: ${_JAVA_DIR:="${_WORK_DIR%/}/java"}

# NOTE: the attribute order is not consistent. also with -z, ^ or $ does not work.
#find ./vol-* -type f -name '*.properties' -print0 | xargs -0 -I{} -P3 grep -lPz "(?s)deleted=true.*@Bucket.repo-name=npm-proxy\b" {}
function f_search_blobs() {
    local _content_dir="${1:-"."}"    # /var/tmp/share/sonatype/blobs/default/content/vol-*
    local _grep_args="${2}"   # eg: -lPz "(?s)deleted=true.*@Bucket.repo-name=" NOTE: with -z, ^ or $ does not work.
    [ -z "${_grep_args}" ] && return 1
    # find + xargs is faster than grep with --include
    #grep -H --include='*.properties' -IRs ${_grep_args} ${_content_dir}    # -H or -l
    # NOTE: find -L makes this command a bit slower, and -P would be helpful onlly for slow store.
    #       Also, redirecting to a file is faster in the console.
    find ${_content_dir} -type f -name '*.properties' -print0 | xargs -0 -P 2 grep ${_grep_args} > /tmp/$FUNCNAME.out
    cat /tmp/$FUNCNAME.out
}

function f_search_soft_deleted_blobs() {
    local _content_dir="${1:-"./vol-*"}"    # /var/tmp/share/sonatype/blobs/default/content/vol-*
    local _repo_name="${2}"
    if [ -n "${_repo_name}" ]; then
        # NOTE: intentionally, not using double quotes for _content_dir, in case it contains "*"
        #grep -l --include='*.properties' -IRs "^deleted=true" ${_content_dir} --null | xargs -0 -P2 grep -l -E '^@BlobStore.blob-name=(name1|name2)$'
        grep -l --include='*.properties' -IRs "^deleted=true" ${_content_dir} --null | xargs -0 -P2 grep -l -E '^@Bucket.repo-name=maven-group$'
    else
        grep -l --include='*.properties' -IRs "^deleted=true" ${_content_dir} --null
    fi
    #grep -E '^(size=|deletedDateTime=|deletedReason=|@BlobStore.blob-name=)' `cat soft-deleted.list`
    # TODO: utilise 'blobpath' command
}
# TODO: search and sum the size per repo / per blob store, from file and/or DB.

alias sum_cols="paste -sd+ - | bc"
function f_orientdb_checks() {
    local _db="$1"
    local _find="$(which gfind || echo "find")"
    echo "# Finding wal files ..."
    ${_find} ${_db%/} -type f -name '*.wal' -printf '%k\t%P\t%t\n'
    echo "# Checking size (KB) of index files ..."
    ${_find} ${_db%/} -type f -name '*_idx.sbt' -printf '%k\t%P\n' | sort -k2 | tee /tmp/$FUNCNAME.out
    echo "Total: $(cat /tmp/$FUNCNAME.out | wc -l)"
    echo "# Estimating table sizes (KB) from pcl files ..."
    ${_find} ${_db%/} -type f -name '*.pcl' -printf '%k\t%P\n' | sort -k2 | sed -E 's/_?[0-9]*\.pcl//' > /tmp/$FUNCNAME.out
    cat /tmp/$FUNCNAME.out | uniq -f1 | while read -r _l; do
        # NOTE: matching space in bash is a bit tricky
        if [[ "${_l}" =~ ^[[:space:]]*[0-9]+[[:space:]]+(.+) ]]; then
            local _table="${BASH_REMATCH[1]}"
            local _total="$(grep -E "\s+${_table}$" /tmp/$FUNCNAME.out | awk '{print $1}' | sum_cols)"
            echo -e "${_total}\t${_table}"
        fi
    done
}

# draft
function f_find_open_bytes_files() {
    # TODO: Not perfect but there is no way to link Java TID / HEX nid with FD or iNode
    local _blobs="$1"   # /opt/sonatype/sonatype-work/nexus3/blobs/default
    netstat -topen | grep 8081  # pick inode or port and pid
    # Usually +1 or a few of above fd and the FD ends with 'w'
    lsof -nPp $PID | grep -w $INODE -A 100 | grep -m1 "$(realpath "${_blobs}")/content/tmp/tmp"
}

# troubleshoot mount related issue such as startup fails with strange mount option.
function f_mount_file() {
    local _mount_to="${1}"
    local _extra_opts="${2}"
    local _file_type="${3:-"ext3"}"
    local _file="${4:-"/var/tmp/loop_file"}"
    if [ ! -f "${_file}" ]; then
        dd if=/dev/zero of="${_file}" bs=1 count=0 seek=10737418240 || return $?
        # If xfs "apt-get install xfsprogs"
        mkfs -t ${_file_type} "${_file}" || return $?
    fi
    if [ ! -d "${_mount_to}" ]; then
        mkdir -m 777 -p "${_mount_to}" || return $?
    fi
    local _opts="loop"
    [ -n "${_extra_opts}" ] && _opts="${_opts},${_extra_opts#,}"
    mount -t ${_file_type} -o "${_opts}" "${_file}" "${_mount_to}"
}

#find /opt/sonatype/sonatype-work/clm-server/report -mindepth 2 -maxdepth 2 -type d -print | while read -r _p; do grep -qw totalArtifactCount ${_p}/report.cache/summary.json || echo "${_p}/report.cache/summary.json: No totalArtifactCount"; done
function f_find_missing() {
    local _start_dir="$1"
    local _finding="$1"
    local _depth="$2"
    find ${_start_dir%/} -mindepth ${_depth} -maxdepth ${_depth} -type d -print | while read -r _p; do [ -f "${_p}/${_finding}" ] || echo "${_p} is missing ${_finding}"; done
}