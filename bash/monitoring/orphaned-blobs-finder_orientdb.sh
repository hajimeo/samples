#!/usr/bin/env bash
# HOW TO:
#   NOTE: Start OrientDB in another terminal first: java -Dserver=true -jar ./orient-console.jar ./component
#   bash ./dead-blobs-finder_orientdb.sh "/path/to/blob_store/content/vol-*" | tee -a ./orphaned_result.txt

### Global variables ######################################################
# If you would like to check par 'vol-<n>' for multi-processing, change this path
_FILE_BLOB_STORE_VOL_PATH="$1" # eg. /opt/sonatype/nexus3/blobs/default/content/vol-*
_PARALLELISM="${2:-"3"}"       # Number of parallel processes in xargs
_ORIENT_DB_API_URL="${3:-"http://localhost:2480/command/component/sql"}"
_MTIME="${4:-"1"}"
###########################################################################

function f_query_db {
    local _file_path="$1"
    local _repo_name="$(sed -n 's/^@Bucket\.repo-name=//p' "${_file_path}")"
    if [ -z "${_repo_name}" ]; then
        echo "Invalid file: ${_file_path}"
        return 1
    fi
    if grep -q '^deleted=true' "${_file_path}"; then
        echo "[DEBUG] Skipping soft-deleted blob: ${_file_path} (${_repo_name})" >&2
        return 0
    fi
    local _blob_id="$(basename "${_file_path}" ".properties")"
    # Somehow '%' needs to be url-encoded to '%25' in the query. Without specifying repository_name, it takes twice longer.
    local _result_json="$(curl -sSf -u "admin:admin" -X POST "${_ORIENT_DB_API_URL}" -d "SELECT blob_ref FROM asset WHERE bucket.repository_name = '${_repo_name}' AND blob_ref like '%25${_blob_id}' LIMIT 1")"
    local _rc="$?"
    if [ "${_rc}" -ne 0 ] || [ -z "${_result_json}" ]; then
        echo "[ERROR] querying the database for blob ID: ${_blob_id} failed (${_rc})" >&2
        return ${_rc}
    fi
    if [[ ! "${_result_json}" =~ ${_blob_id} ]]; then
        echo "Orphaned blob: ${_file_path}"
    fi
}
export -f f_query_db
export _ORIENT_DB_API_URL

# To avoid checking the newly created/modified files
#touch /tmp/until_$$.tmp; ... -not -newer /tmp/until_$$.tmp
find ${_FILE_BLOB_STORE_VOL_PATH%/} -maxdepth 2 -mtime +${_MTIME} -name '*.properties' -print0 | head -n1 | xargs -0 -I @@ -P${_PARALLELISM} bash -c 'f_query_db "@@"'
