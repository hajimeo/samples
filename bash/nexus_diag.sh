#!/usr/bin/env bash
# DOWNLOAD:
#   curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/nexus_diag.sh
#
# This script is only for Linux|Mac with BASH.
#

function usage() {
    cat << EOS
TODO: update usage.
EOS
}


# Overridable global variables
: ${_WORK_DIR:="/var/tmp/share"}
: ${_BASE_DIR:="${_WORK_DIR%/}/java"}

function f_search_blobs() {
    local _content_dir="${1:-"./vol-*"}"    # /var/tmp/share/sonatype/blobs/default/content/vol-*
    local _grep_opts="$2"   # eg: -Pz "(?s)^deleted=true.*^@Bucket.repo-name="
    # -H or -l
    grep -H --include='*.properties' -IRs ${_grep_opts} ${_content_dir}
}

function f_search_soft_deleted_blobs() {
    local _content_dir="${1:-"./vol-*"}"    # /var/tmp/share/sonatype/blobs/default/content/vol-*
    local _repo_name="${2}"
    if [ -n "${_repo_name}" ]; then
        # NOTE: intentionally, not using double quotes for _content_dir, in case it contains "*"
        grep -l --include='*.properties' -IRs "^deleted=true" ${_content_dir} --null | xargs -0 -P2 grep -l -E '^@Bucket.repo-name=maven-group$'
    else
        grep -l --include='*.properties' -IRs "^deleted=true" ${_content_dir} --null
    fi
    #grep -E '^(size=|deletedDateTime=|deletedReason=|@BlobStore.blob-name=)' `cat soft-deleted.list`
}

# TODO: search and sum the size per repo / per blob store, from file and/or DB.