#!/usr/bin/env bash
#
# REQUIREMENTS:
#   Assuming the asset-dupe-checker.jar was already used and fixed.
#   java (v8), python3
#

#: ${_CHECK_LIST:=""}   # Check all
: ${_CHECK_LIST:="NEXUS-29594_1 NEXUS-28621"}

function f_gen_sqls_per_bucket() {
    local _json_file="$1"
    local _base_sql="$2"
    local _replace="${3:-"%REPO_NAME_VALUE%"}"
    local _repo_col="${4:-"repo_name"}"
    cat "${_json_file}" | while read -r _l; do
        if [[ "${_l}" =~ \"${_repo_col}\":\"([^\"]+)\" ]]; then
            echo "${_base_sql}" | sed "s/${_replace}/${BASH_REMATCH[1]}/g"
        fi
    done
}

function _get_xmx() {
    local _max_c="${1:-0}"
    local _xmx_gb="$(( ${_max_c} * 3 / 1024 / 1024 + 1))"
    if [ 6 -gt ${_xmx_gb:-0} ]; then
        _xmx_gb=6
    fi
    echo "${_xmx_gb}g"
}

function _run_check() {
    local _keyword="$1"
    if [ -z "${_CHECK_LIST}" ] || echo "${_CHECK_LIST}" | grep -qE "\b${_keyword}\b"; then
        echo "# [INFO] Checking ${_keyword} ..."
        return 0
    fi
    return 1
}

main() {
    local _component="${1}"
    local _xmx="${2}"
    local _orient_console="${3}"
    local _sql=""
    local _result="result_$(date +%s).sql"

    if [ ! -d "${_component%/}" ]; then
        echo "Provide a path to the component directory"
        return 1
    fi

    if [ -z "${_orient_console}" ]; then
        _orient_console="./orient-console.jar"
        if [ ! -s "${_orient_console}" ]; then
            curl -o "${_orient_console}" -L "https://github.com/hajimeo/samples/raw/master/misc/orient-console.jar" || return $?
        fi
    fi

    if [ -n "${_xmx}" ]; then
        _sql="SELECT @rid as rid, repository_name as repo_name FROM bucket ORDER BY repository_name limit -1;"
    else
        _sql="SELECT bucket, bucket.repository_name as repo_name, count(*) as c FROM asset GROUP BY bucket ORDER BY c DESC limit -1;"
    fi
    echo "${_sql}" | java -Xms${_xmx:-"4g"} -Xmx${_xmx:-"4g"} -DexportPath=./bkt_names.json -jar ${_orient_console} "${_component}" || return $?
    if [ -z "${_xmx}" ]; then
        local _max_c="0"
        if [[ "$(grep -m1 '"c":' ./bkt_names.json)" =~ \"c\":([0-9]+) ]]; then
            _max_c="${BASH_REMATCH[1]}"
        fi
        _xmx="$(_get_xmx "${_max_c}")"
        echo "# [INFO] Using -Xmx${_xmx} ..."
    fi

    if _run_check "NEXUS-29594_1"; then
        # NOTE: not using 'like' as expecting index is no broken (Use asset-dupe-checker.jar)
        _sql="SELECT * FROM (SELECT list(@rid) as rids, bucket, name, format, list(component) as comps, count(*) as c from asset WHERE bucket.repository_name = '%REPO_NAME_VALUE%' group by name) where c > 1;"
        f_gen_sqls_per_bucket "./bkt_names.json" "${_sql}" | java -Xms${_xmx} -Xmx${_xmx} -DexportPath=./result_NEXUS-29594_1.json -jar ${_orient_console} "${_component}" || return $?
        if [ -s ./result_NEXUS-29594_1.json ]; then
            cat ./result_NEXUS-29594_1.json | python3 -c 'import sys, json
jsList = json.loads(sys.stdin.read())
for js in jsList:
    for rid in js["rids"]:
        print("DELETE FROM asset WHERE @rid = %s AND component.@rid IS NULL;" % rid)' >> "${_result}"
        fi
    fi

    if _run_check "NEXUS-29594_2"; then
        _sql="SELECT @rid as rid, bucket, name, blob_ref FROM asset WHERE bucket.repository_name = '%REPO_NAME_VALUE%' AND format = 'docker' AND name like '%/manifests/sha256:%' AND @rid IN (SELECT rids FROM (SELECT list(@rid) as rids, COUNT(*) as c FROM asset where bucket.repository_name = '%REPO_NAME_VALUE%' AND format = 'docker' GROUP BY blob_ref) WHERE c > 1);"
        f_gen_sqls_per_bucket "./bkt_names.json" "${_sql}" | java -Xms${_xmx} -Xmx${_xmx} -DexportPath=./result_NEXUS-29594_2.json -jar ${_orient_console} "${_component}" || return $?
        if [ -s ./result_NEXUS-29594_2.json ]; then
            echo "-- [TODO] Investigate ./result_NEXUS-29594_2.json and decide which one to delete." | tee -a "${_result}"
        fi
    fi

    if _run_check "NEXUS-28621"; then
        # This query should be fast (as long as index is healthy)
        _sql="SELECT @rid as rid, bucket, component, name, format, size, blob_ref FROM asset WHERE name = '';"
        echo "${_sql}" | java -Xms${_xmx} -Xmx${_xmx} -DexportPath=./result_NEXUS-28621.json -jar ${_orient_console} "${_component}" || return $?
        if [ -s ./result_NEXUS-28621.json ]; then
            cat ./result_NEXUS-28621.json | python3 -c 'import sys, json
jsList = json.loads(sys.stdin.read())
for js in jsList:
    for rid in js["rid"]:
        print("DELETE FROM asset WHERE @rid = %s AND component.@rid IS NULL;" % rid)' >> "${_result}"
        fi
    fi

    if _run_check "NEXUS-33290"; then
        # NOTE: not using 'like' as expecting index is no broken (Use asset-dupe-checker.jar)
        _sql="SELECT @rid as rid, bucket, name, format FROM asset WHERE bucket.repository_name = '%REPO_NAME_VALUE%' AND attributes.content.last_modified.asLong() = 0;"
        f_gen_sqls_per_bucket "./bkt_names.json" "${_sql}" | java -Xms${_xmx} -Xmx${_xmx} -DexportPath=./result_NEXUS-33290.json -jar ${_orient_console} "${_component}" || return $?
        if [ -s ./result_NEXUS-33290.json ]; then
            cat ./result_NEXUS-33290.json | python3 -c 'import sys, json
jsList = json.loads(sys.stdin.read())
for js in jsList:
    for rid in js["rid"]:
        print("UPDATE asset SET attributes.content.last_modified = date() WHERE @rid = %s AND attributes.content.last_modified.asLong() = 0;" % rid)' >> "${_result}"
        fi
    fi

    # NEXUS-31032 fixed in 3.38.0 migrator
    echo "Completed."
    if [ -s "${_result}" ]; then
        echo "Please review ${_result}."
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi