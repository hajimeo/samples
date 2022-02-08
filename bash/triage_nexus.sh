#!/usr/bin/env bash
function usage() {
    cat << EOS
$(basename "$BASH_SOURCE") contains functions which are:
 - copy & paste-able, means no dependency to other functions (may still download external file with curl)
 - should work on the Nexus server (Linux)
for troubleshooting various issues.

DOWNLOAD LATEST and SOURCE:
    curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/nexus_diag.sh
    source ./nexus_diag.sh
EOS
}


# Overridable global variables
: ${_WORK_DIR:="/var/tmp/share"}
: ${_JAVA_DIR:="${_WORK_DIR%/}/java"}


#curl -X PUT -T<(echo "test") localhost:2424
function f_start_web() {
    local __doc__="To check network connectivity and transfer speed"
    local _port="${1:-"2424"}"
    if type php &>/dev/null; then
        curl -O "https://raw.githubusercontent.com/hajimeo/samples/master/php/index.php" && php -S 0.0.0.0:${_port} ./index.php
    #elif type python; then
        # Expecting python3
        #python -m http.server ${_port} &>/dev/null &
        # if python2.x: python -m SimpleHTTPServer ${_port} &>/dev/null &
    elif type nc; then
        while true; do nc -v -nlp "${_port}" &>/dev/null; done
    else
        echo "No php or nc (netcat)"
        return 1
    fi
}

function f_verify_install() {
    local __doc__="Compare files with the original tar installer file"
    local _tar="$1"
    local _extracted="$2"
    tar --diff -f "${_tar}" -C "${_extracted}" | grep -vE '(Uid|Gid|Mod time) differs'
}

#find . -type f -printf '%s\n' | awk '{ c+=1;s+=$1/1024/1024 }; END { print "count:"c", size:"s" MB" }'
function f_size_count() {
    local __doc__="Count how many kilobytes file and sum size (NOT considering 'deleted=true' files)"
    local _dir="$1" # blobs/defaut/content/
    local _chk_soft_del="$2"
    local _P="${3}"
    if [[ "${_chk_soft_del}" =~ ^(y|Y) ]]; then
        # sed -nE "s/^size=([0-9]+)$/\1/p"
        find ${_dir%/} -type f -name '*.properties' -print0 | xargs -0 -P${_P:-"3"} -I {} sh -c 'grep -q "deleted=true" {} || (_f="{}";find ${_f%.*}.bytes -printf "%k\n")' 2>/dev/null
        echo ""
    else
        find ${_dir%/} -type f -name '*.bytes' -printf '%s\n'
    fi | awk '{ c+=1;s+=$1/1024/1024 }; END { print "{\"count\":"c", \"size\":"s", \"unit\":\"MB\"}" }'
}

#grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ./suspicious_blobs.json | sort > suspicious_blob_refs.list
#grep 'Asset{metadata=AttachedEntityMetadata' deadBlobResult-*.json | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' > deadblobs_blob_refs.list
#diff -wy --suppress-common-lines suspicious_blob_refs.list deadblobs_blob_refs.list
#comm -12 suspicious_blob_refs.list deadblobs_blob_refs.list > more_suspicious_blob_refs.list
function f_blobs_csv() {
    local __doc__="Generate CSV for Key,LastModified,Size + properties"
    local _dir="$1"         # "blobs/default/content/vol-*"
    local _with_props="$2"  # Y to check properties file, but extremely slow
    local _filter="${3}"    # "*.properties"
    local _P="${4}"         #
    printf "Key,LastModified,Size"
    local _find="find ${_dir%/} -type f"
    [ -n "${_filter}" ] && _find="${_find} -name '${_filter}'"
    if [[ "${_with_props}" =~ ^(y|Y) ]]; then
        printf ",Properties\n"
        # without _o=, it may output empty "" line.
        eval "${_find} -print0" | xargs -0 -P${_P:-"3"} -I {} sh -c '[ -f {} ] && _o="$(find {} -printf "\"%p\",\"%t\",%s," && printf "\"%s\"\n" "$(echo "{}" | grep -q ".properties" && cat {} | tr "\n" "," | sed "s/,$//")")" && echo ${_o}'
    else
        printf "\n"
        eval "${_find} -printf '\"%p\",\"%t\",%s\n'"
    fi
}

function f_blob_refs_from_dump() {
    local __doc__="List blob_ref from pg_dump .gz file"
    # PGPASSWORD="${_DB_PWD}" pg_dump -U ${_DB_USER} -h ${_DB_HOSTNAME} -f ${_dump_dest_filename} -Z 6 ${_DB_NAME}
    local _blobstore="$1"
    local _dump_file="$2"
    # default:1e8fa82e-de1d-4077-a000-87519667c480@543737FB-31D9E760-58122A7D-1203FD17-A4855E39 (assuming it starts with *correct* blobstore name)
    zgrep -oE "\s+${_blobstore}:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" "${_dump_file}" | sed -E "s/\s+${_blobstore}://g"
}
function f_blob_refs_from_bak() {
    local __doc__="List blob_ref from OrientDB .bak file"
    local _blobstore="$1"
    local _bak_file="$2"
    if [ ! -s /tmp/orient-console.jar ]; then
        curl -o/tmp/orient-console.jar -L "https://github.com/hajimeo/samples/raw/master/misc/orient-console.jar" || return $?
    fi
    echo "SELECT blob_ref FROM asset WHERE blob_ref LIKE '${_blobstore}@%'" | java -DexportPath=/tmp/result.json -jar ./orient-console.jar "${_bak_file}" || return $?
    grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' /tmp/result.json
}

#f_upload_dummies "http://localhost:8081/repository/raw-s3-hosted/manyfiles" "1432 10000" 8
function f_upload_dummies() {
    local __doc__="Upload text files into (raw) hosted repository"
    local _repo_url="${1:-"http://localhost:8081/repository/raw-hosted/test"}"
    local _how_many="${2:-"10"}"
    local _parallel="${3:-"4"}"
    local _file_prefix="${4:-"test_"}"
    local _file_suffix="${5:-".txt"}"
    local _usr="${6:-"admin"}"
    local _pwd="${7:-"admin123"}"
    local _seq="seq 1 ${_how_many}"
    [[ "${_how_many}" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]] && _seq="seq ${_how_many}"
    # -T<(echo "aaa") may not work with some old bash, so creating a file
    echo "test by f_upload_dummies started at $(date +'%Y-%m-%d %H:%M:%S')" > /tmp/f_upload_dummies.tmp || return $?
    for i in $(eval "${_seq}"); do
      echo "${_file_prefix}${i}${_file_suffix}"
    done | xargs -I{} -P${_parallel} curl -s -f -u "${_usr}:${_pwd}" -w '%{http_code} {}\n' -T /tmp/f_upload_dummies.tmp -L -k "${_repo_url%/}/{}"
    # TODO: xargs only stops if exit code is 255
}

function f_mvn_copy_local() {
    local __doc__="Copy/upload local maven repository to hosted repository"
    local _repo_url="${1:-"http://localhost:8081/repository/maven-hosted"}"
    local _local_dir="${2:-"${HOME%/}/.m2/repository"}"
    local _filter="${3}"
    local _parallel="${4:-"4"}"
    local _usr="${5:-"admin"}"
    local _pwd="${6:-"admin123"}"
    # at this moment, limiting to pom, jar and sha1 files only
    local _find="find \"${_local_dir%/}\" -type f \( -iname \*.pom -o -iname \*.jar -o -iname \*.sha1 \)"
    [ -n "${_filter}" ] && _find="${_find} -path \"${_filter}\""
    eval "${_find} -print" | sed -nE 's@.*'${_local_dir%/}'/(.+)$@\1@p' | xargs -I{} -P${_parallel} curl -s -f -u "${_usr}:${_pwd}" -w '%{http_code} {}\n' -T ${_local_dir%/}/{} -L -k "${_repo_url%/}/{}"
}

# NOTE: filter the output before passing function would be faster
#zgrep "2021:10:1" request-2021-01-08.log.gz | f_replay_gets "http://localhost:8081/repository/maven-central" "/nexus/content/(repositories|groups)/[^/]+/([^ ]+)"
#rg -z "2021:\d\d:\d.+ \"GET /repository/maven-central/.+HTTP/[0-9.]+" 2\d\d" request-2021-01-08.log.gz | sort | uniq | f_replay_gets "http://dh1:8081/repository/maven-central/"
function f_replay_gets() {
    local __doc__="Replay GET requests in the request.log"
    local _url_path="$1"    # http://localhost:8081/repository/maven-central
    local _path_match="${2:-"/repository/[^/]+/([^ ]+)"}"   # or NXRM2: "/nexus/content/(repositories|groups)/[^/]+/([^ ]+)"
    local _curl_opt="${3}"  # -u admin:admin123
    local _c="${4:-"1"}"    # concurrency. Use 1 if order is important
    [[ "${_url_path}" =~ ^http ]] || return 1
    [[ "${_path_match}" =~ .*\(.+\).* ]] || return 2
    local _n="$(echo "${_path_match}" | tr -cd ')' | wc -c | tr -d "[:space:]")"
    # TODO: sed is too difficult to handle multiple parentheses
    # Not sorting as order might be important. Also, --head -o/dev/null is intentional
    rg "\bGET ${_path_match} HTTP/\d" -o -r "$"${_n} | xargs -n1 -P${_c} -I{} curl -sf --connect-timeout 2 --head -o/dev/null -w '%{http_code} {}\n' ${_curl_opt} "${_url_path%/}/{}"
}
#rg -m300 '03/Aug/2021:0[789].+GET /content/groups/npm-all/(.+/-/.+-[0-9.]+\.tgz)' -o -r '${1}' ./work/logs/request.log | xargs -I{} curl -sf --connect-timeout 2 --head -o/dev/null -w '%{http_code} {}\n' -u admin:admin123 "http://localhost:8081/nexus/content/groups/npm-all/{}" | tee result.out
#npm cache clean --force
#rg -m300 'GET /content/groups/npm-all/([^/]+)/-/.+-([0-9.]+)\.tgz' -o -r 'npm pack --registry=http://localhost:8081/nexus/content/groups/npm-all/ ${1}@${2}' ./work/logs/request.log | while read -r _c; do sh -x -c "${_c}"; done


# NOTE: the attribute order is not consistent. also with -z, ^ or $ does not work.
#find ./vol-* -type f -name '*.properties' -print0 | xargs -0 -I{} -P3 grep -lPz "(?s)deleted=true.*@Bucket.repo-name=npm-proxy\b" {}
# Find not deleted (last updated) grunt metadata asset
#rg -l -g '*.properties' '@BlobStore.blob-name=grunt' | xargs -I {} rg 'Bucket.repo-name=npm-group' -l {} | xargs -I {} ggrep -L '^deleted=true' {}
function f_blob_search() {
    local __doc__="find + grep is faster than grep --include, and using xargs -P2"
    local _content_dir="${1:-"."}"    # /var/tmp/share/sonatype/blobs/default/content/vol-*
    local _2nd_arg="${2}"
    [ -z "${_2nd_arg}" ] && return 1
    #grep -H --include='*.properties' -IRs "${@:2}" ${_content_dir}    # -H or -l
    # NOTE: find -L makes this command a bit slower, and -P would be helpful onlly for slow store.
    #       Also, redirecting to a file is faster in the console (but not doing so that more intructive)
    if type rg &>/dev/null; then
        rg -g '*.properties' "${@:2}"
    else
        find ${_content_dir%/} -type f -name '*.properties' -print0 | xargs -0 -P 2 grep "${@:2}"
    fi # > /tmp/$FUNCNAME.out;cat /tmp/$FUNCNAME.out
}
# Not perfect
function f_blob_list_from_pom() {
    local __doc__="NOTE: using f_blob_search"
    local _content_dir="${1:-"."}"    # /var/tmp/share/sonatype/blobs/default/content/vol-*
    local _artifactId="${2}"  # eg "log4j-core"
    local _is_dependency="${3}"
    f_blob_search "${_content_dir}" -l '^@BlobStore.blob-name=.+pom$' | while read -r _f; do
        local _tmp_lines="$(grep -B3 -A2 "<artifactId>${_artifactId}</artifactId>" "${_f%.*}.bytes")"
        if [ -n "${_tmp_lines}" ]; then
            # Find dependencies only
            if [[ "${_is_dependency}" =~ ^(y|Y) ]]; then
                if ! echo "${_tmp_lines}" | grep -q "<dependency>"; then
                    continue
                fi
                if echo "${_tmp_lines}" | grep -q "<scope>test</scope>"; then
                    continue
                fi
            fi
            grep -H '^@BlobStore.blob-name=' "${_f}"
        fi
    done
}

function f_search_soft_deleted_blobs() {
    local __doc__="find deleted=true blobs"
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

function f_missing_check() {
    # To check 'exists in metadata, but is missing from the blobstore'
    # https://issues.sonatype.org/browse/NEXUS-27145 stops maven-metadata rebuild, so deleting multiple maven-metadata.xml files
    local _comp_bak="$1"
    local _blobstore="${2:-"default"}"
    local _path2content="${2:-"./content"}"
    # NOTE: May need to modify 'where' part for deleting specifics:
    local _sql="select bucket.repository_name as repo_name, name, blob_ref from asset where attributes.maven2.asset_kind = 'REPOSITORY_METADATA' and blob_ref like '${_blobstore}@%' LIMIT 2;"
    if [ ! -s orient-console.jar ]; then
        curl -o ./orient-console.jar -L "https://github.com/hajimeo/samples/raw/master/misc/orient-console.jar" || return $?
    fi
    if ! type blobpath &>/dev/null && [ ! -s blobpath ]; then
        curl -o ./blobpath -L "https://github.com/hajimeo/samples/raw/master/misc/blobpath_$(uname)" || return $?
        chmod u+x ./blobpath || return $?
    fi
    echo "${_sql}" | java -DexportPath=./result.json -jar orient-console.jar ${_comp_bak} || return $?
    cat ./result.json | while read -r _l; do
        if [[ "${_l}" =~ \"repo_name\":\"([^\"]+)\".+\"name\":\"([^\"]+)\".+\"blob_ref\":\"${_blobstore}@[^:]+:([^\"]+)\" ]]; then
            local _repo_name="${BASH_REMATCH[1]}"
            local _name="${BASH_REMATCH[2]}"
            local _blobId="${BASH_REMATCH[3]}"
            local _path="${_path2content%/}/$(blobpath "${_blobId}")"
            if [ ! -f "${_path}" ]; then    # Change this with aws cli if S3
                echo "${_name} ${_path} does not exist."
                #echo curl -u admin:admin123 "${_NXRM3_BASEURL%/}/repository/${_repo_name}/${_name#/}"
            fi
        fi
    done
}

function f_orientdb_checks() {
    local __doc__="Check index number/size and pcl file size"
    local _db="$1"  # Directory or ls -l output
    local _size_col="${2:-5}"
    local _file_col="${2:-9}"
    if [ -d "${_db%/}" ]; then
        ls -l "${_db%/}" > /tmp/f_orientdb_checks_ls.out
        _db=/tmp/f_orientdb_checks_ls.out
    fi
    echo "# Finding wal files (should be small) ..."
    grep 'wal' "${_db}"
    echo ""
    echo "# Checking size (Bytes) of index files (alphabetical order) ..."
    grep '_idx.sbt' "${_db}" | awk '{printf("%12s %s\n",$'${_size_col}',$'${_file_col}')}' | sort -k2 | tee /tmp/f_orientdb_checks.out
    echo "Total: $(awk '{print $1}' /tmp/f_orientdb_checks.out | paste -sd+ - | bc) bytes / $(cat /tmp/f_orientdb_checks.out | wc -l) indexes (expecting 15)"
    echo ""
    echo "# Estimating table sizes (Bytes) from pcl files ..."
    grep '.pcl' "${_db}" | awk '{print $'${_size_col}'" "$'${_file_col}'}' | sort -k2 | sed -E 's/_?[0-9]*\.pcl//' > /tmp/f_orientdb_checks.out
    cat /tmp/f_orientdb_checks.out | uniq -f1 | while read -r _l; do
        # NOTE: matching space in bash is a bit tricky
        if [[ "${_l}" =~ ^[[:space:]]*[0-9]+[[:space:]]+(.+) ]]; then
            local _table="${BASH_REMATCH[1]}"
            local _total="$(grep -E "\s+${_table}$" /tmp/f_orientdb_checks.out | awk '{print $1}' | paste -sd+ - | bc)"
            printf "%12s %s\n" ${_total} ${_table}
        fi
    done | sort -k2
    echo "Total: $(awk '{print $1}' /tmp/f_orientdb_checks.out | paste -sd+ - | bc) bytes"
}
#local _find="$(which gfind || echo "find")"
#${_find} ${_db%/} -type f -name '*.wal' -printf '%k\t%P\t%t\n'
#${_find} ${_db%/} -type f -name '*_idx.sbt' -printf '%k\t%P\n' | sort -k2 | tee /tmp/f_orientdb_checks.out
#${_find} ${_db%/} -type f -name '*.pcl' -printf '%k\t%P\n' | sort -k2 | sed -E 's/_?[0-9]*\.pcl//' > /tmp/f_orientdb_checks.out

# DRAFT: trying to find which blob_ref.bytes files are open.
function f_find_open_bytes_files() {
    local __doc__="Not perfect but there is no way to link Java TID / HEX nid with FD or iNode"
    local _blobs="$1"   # /opt/sonatype/sonatype-work/nexus3/blobs/default
    netstat -topen | grep 8081  # pick inode or port and pid
    # Usually +1 or a few of above fd and the FD ends with 'w'
    lsof -nPp $PID | grep -w $INODE -A 100 | grep -m1 "$(realpath "${_blobs}")/content/tmp/tmp"
}

function f_check_filesystems() {
    local __doc__="Elastic Search checks all file systems with getFileStores() -> getFileStore() and if a FS is slow or hang, Nexus hangs"
    # NOTE: Mac doesn't have df --output
    df --output=target | grep -v '^Mounted on' | while read -r _m
    do
        echo "# Checking ${_m} ..."
        timeout 3 stat "${_m}" || echo "ERROR: 'stat ${_m}' failed" >&2;
    done
}

function f_mount_file() {
    local __doc__="To test mounting issue, mount a file as some (eg:ext3) file system with mount options"
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

function f_count_dirs() {
    local __doc__="sometimes having many files in a dir causes performance issue, so finding number of objects per directory"
    local _dir="$1"
    # ls -f is better than ls -1 for this purpose
    find ${_dir%/} -type d -exec sh -c 'echo "$(ls -f {} | wc -l)\t{}"' \;    #\t$(date +"%H:%M:%S") # this is for checking performance
}

#find /opt/sonatype/sonatype-work/clm-server/report -mindepth 2 -maxdepth 2 -type d -print | while read -r _p; do grep -qw totalArtifactCount ${_p}/report.cache/summary.json || echo "${_p}/report.cache/summary.json: No totalArtifactCount"; done
function f_find_missing() {
    local __doc__="find directory, which does not have the expecting file."
    local _start_dir="$1"
    local _expecting="$1"
    local _depth="$2"
    find ${_start_dir%/} -mindepth ${_depth} -maxdepth ${_depth} -type d -print | while read -r _p; do [ -f "${_p}/${_expecting}" ] || echo "${_p} is missing ${_expecting}"; done
}


if [ "$0" = "$BASH_SOURCE" ]; then
    usage
fi