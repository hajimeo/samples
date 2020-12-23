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
: ${_JAVA_DIR:="${_WORK_DIR%/}/java"}

function f_search_blobs() {
    local _content_dir="${1:-"."}"    # /var/tmp/share/sonatype/blobs/default/content/vol-*
    local _grep_args="${2}"   # eg: -lPz "(?s)^deleted=true.*^@Bucket.repo-name="
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
    # TODO: utilse 'blobpath' command
}

# TODO: search and sum the size per repo / per blob store, from file and/or DB.