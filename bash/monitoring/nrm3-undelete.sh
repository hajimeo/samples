#!/usr/bin/env bash
usage() {
    cat <<EOF
bash <(curl -sfL https://raw.githubusercontent.com/sonatype-nexus-community/nexus-monitoring/main/scripts/nrm3-undelete.sh --compressed)

PURPOSE:
    Undelete one specific file (call this script multiple times for many files)

REQUIREMENTS:
    curl
    python to handle JSON string.

EXAMPLES:
    cd /some/workDir
    curl --compressed -O -L https://raw.githubusercontent.com/sonatype-nexus-community/nexus-monitoring/main/scripts/nrm3-undelete.sh
    export _ADMIN_USER="admin" _ADMIN_PWD="admin123" _NEXUS_URL="http://localhost:8081/"
    bash ./nrm3-undelete.sh -I                      # To install the necessary script into first time
    bash ./nrm3-undelete.sh -b <blobId/blobRef>     # TODO: should add repository to make it faster?

OPTIONS:
    -I  Installing the groovy script for undeleting
    -b  blobId or blobRef
EOF
}


### Global variables #################
: "${_ADMIN_USER:="admin"}"
: "${_ADMIN_PWD:="admin123"}"
: "${_NEXUS_URL:="http://localhost:8081/"}"
: "${_BLOB_ID:=""}"
: "${_INSTALL:=""}"
: "${_TMP:="/tmp"}"
_SCRIPT_NAME="undelete"


### Functions ########################
function f_api() {
    local __doc__="NXRM3 API wrapper"
    local _path="${1}"
    local _data="${2}"
    local _method="${3}"
    local _usr="${4:-"${_ADMIN_USER}"}"
    local _pwd="${5-"${_ADMIN_PWD}"}"   # If explicitly empty string, curl command will ask password (= may hang)
    local _nexus_url="${6:-"${_NEXUS_URL}"}"

    local _user_pwd="${_usr}"
    [ -n "${_pwd}" ] && _user_pwd="${_usr}:${_pwd}"
    [ -n "${_data}" ] && [ -z "${_method}" ] && _method="POST"
    [ -z "${_method}" ] && _method="GET"
    local _content_type="Content-Type: application/json"
    [ "${_data:0:1}" != "{" ] && [ "${_data:0:1}" != "[" ] && _content_type="Content-Type: text/plain"
    local _curl="curl -sSf"
    ${_DEBUG} && _curl="curl -vf"
    if [ -z "${_data}" ]; then
        # GET and DELETE *can not* use Content-Type json
        ${_curl} -D ${_TMP%/}/_api_header_$$.out -u "${_user_pwd}" -k "${_nexus_url%/}/${_path#/}" -X ${_method}
    else
        ${_curl} -D ${_TMP%/}/_api_header_$$.out -u "${_user_pwd}" -k "${_nexus_url%/}/${_path#/}" -X ${_method} -H "${_content_type}" -d "${_data}"
    fi > ${_TMP%/}/f_api_nxrm_$$.out
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        cat ${_TMP%/}/_api_header_$$.out >&2
        return ${_rc}
    fi
    if ! cat ${_TMP%/}/f_api_nxrm_$$.out | python -m json.tool 2>/dev/null; then
        echo -n "$(cat ${_TMP%/}/f_api_nxrm_$$.out)"
        echo ""
    fi
}

function f_register_script() {
    local _script_file="$1"
    local _script_name="$2"
    [ -s "${_script_file%/}" ] || return 1
    [ -z "${_script_name}" ] && _script_name="$(basename ${_script_file} .groovy)"
    python -c "import sys,json;print(json.dumps(open('${_script_file}').read()))" > ${_TMP%/}/${_script_name}_$$.out || return $?
    echo "{\"name\":\"${_script_name}\",\"content\":$(cat ${_TMP%/}/${_script_name}_$$.out),\"type\":\"groovy\"}" > ${_TMP%/}/${_script_name}_$$.json
    # Delete if exists
    f_api "/service/rest/v1/script/${_script_name}" "" "DELETE"
    f_api "/service/rest/v1/script" "$(cat ${_TMP%/}/${_script_name}_$$.json)" || return $?
    #curl -u admin -X POST -H 'Content-Type: text/plain' '${_NEXUS_URL%/}/service/rest/v1/script/${_script_name}/run' -d'{arg:value}'
}

function genScript() {
    local __doc__="Generate the script file"
    local _saveTo="${1:-"${_TMP%/}/${_SCRIPT_NAME}.groovy"}"
    # TODO: replace below
    cat <<'EOF' >"${_saveTo}"
import org.postgresql.*
import groovy.sql.Sql
import java.time.Duration
import java.time.Instant

def elapse(Instant start, String word) {
    Instant end = Instant.now()
    Duration d = Duration.between(start, end)
    System.err.println("# Elapsed ${d}${word.take(200)}")
}

def p = new Properties()
if (args.length > 1 && !args[1].empty) {
    def pf = new File(args[1])
    pf.withInputStream { p.load(it) }
} else {
    p = System.getenv()  //username, password, jdbcUrl
}
def query = (args.length > 0 && !args[0].empty) ? args[0] : "SELECT 'ok' as test"
def driver = Class.forName('org.postgresql.Driver').newInstance() as Driver
def dbP = new Properties()
dbP.setProperty("user", p.username)
dbP.setProperty("password", p.password)
def start = Instant.now()
def conn = driver.connect(p.jdbcUrl, dbP)
elapse(start, " - connect")
def sql = new Sql(conn)
try {
    def queries = query.split(";")
    queries.each { q ->
        q = q.trim()
        System.err.println("# Querying: ${q.take(100)} ...")
        start = Instant.now()
        sql.eachRow(q) { println(it) }
        elapse(start, "")
    }
} finally {
    sql.close()
    conn.close()
}
EOF
}


main() {
    local _blobId="${1:-"${_BLOB_ID}"}"
    local _install="${2:-"${_INSTALL}"}"

    if [[ "${_install}" =~ ^[yY] ]]; then
        genScript "${_TMP%/}/${_SCRIPT_NAME}.groovy"
        f_register_script "${_TMP%/}/${_SCRIPT_NAME}.groovy"
    fi

    if [ -z "${_blobId}" ]; then
        echo "No blobId"
        return
    fi

    f_api "/service/rest/v1/script/${_SCRIPT_NAME}/run" -d'{"blobId":"'${_blobId}'"}'
}


if [ "$0" = "${BASH_SOURCE[0]}" ]; then
    if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ]; then
        usage
        exit 0
    fi

    while getopts "Ib:" opts; do
        case $opts in
        I)
            _INSTALL="Y"
            ;;
        b)
            [ -n "$OPTARG" ] && _BLOB_ID="$OPTARG"
            ;;
        *)
            echo "$opts $OPTARG is not supported. Ignored." >&2
            ;;
        esac
    done

    main
    echo "Completed."
fi
