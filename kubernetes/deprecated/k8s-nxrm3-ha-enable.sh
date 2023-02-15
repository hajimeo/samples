#!/usr/bin/env bash
_SHARE_DIR="$1" # This is mainly for setting product license
_NODE_MEMBERS="${2-"nxrm3-ha1,nxrm3-ha2,nxrm3-ha3"}"
_POD_PREFIX="${3-"nxrm3-ha"}"   # empty string should be acceptable
#_HELM_NAME="${4-"nexus-repository-manager"}"

_SONATYPE_WORK=${_SONATYPE_WORK:-"/nexus-data"}
_DL_URL="${_DL_URL:-"https://raw.githubusercontent.com/hajimeo/samples/master"}"
_import() { [ ! -s "${_SHARE_DIR%/}/${1}" ] && curl -sfL --compressed "${_DL_URL%/}/bash/$1" -o "${_SHARE_DIR%/}/${1}";. "${_SHARE_DIR%/}/${1}"; }
_import "utils.sh"


function f_nexus_ha_config() {
    local _mount="$1"
    local _members="$2"
    local _work_dir="$3"
    _upsert "${_mount%/}/etc/nexus.properties" "nexus.clustered" "true" || return $?
    _upsert "${_mount%/}/etc/nexus.properties" "nexus.log.cluster.enabled" "false" || return $?
    _upsert "${_mount%/}/etc/nexus.properties" "nexus.hazelcast.discovery.isEnabled" "false" || return $?
    _log "INFO" "${_mount%/}/etc/nexus.properties was modified for enabling HA-C and for TCP/IP discovery."
    # NOTE: At this moment skip if exist (find . -name 'hazelcast*.xml*' -delete)
    [ -f "${_mount%/}/etc/fabric/hazelcast-network.xml" ] && return 0
    # NOTE: TCP/IP discovery somehow does not work with Service (with microk8s)
    [ ! -d "${_mount%/}/etc/fabric" ] && mkdir -p "${_mount%/}/etc/fabric"
    if [ -d "${_work_dir%/}" ]; then
        if [ ! -s "${_work_dir%/}/hazelcast-network.tmpl.xml" ]; then
            curl -s -f -m 7 --retry 2 -L "${_DL_URL%/}/misc/hazelcast-network.tmpl.xml" -o "${_work_dir%/}/hazelcast-network.tmpl.xml" || return $?
        fi
        cp -f "${_work_dir%/}/hazelcast-network.tmpl.xml" "${_mount%/}/etc/fabric/hazelcast-network.xml" || return $?
    else
        curl -s -f -m 7 --retry 2 -L "${_DL_URL%/}/misc/hazelcast-network.tmpl.xml" -o "${_mount%/}/etc/fabric/hazelcast-network.xml" || return $?
    fi
    local _domain="$(hostname -d)"
    for _m in $(_split "${_members}"); do
        sed -i "0,/<member>%HA_NODE_/ s/<member>%HA_NODE_.%<\/member>/<member>${_m}.${_domain#.}<\/member>/" "${_mount%/}/etc/fabric/hazelcast-network.xml" || return $?
    done
    _log "INFO" "${_mount%/}/etc/fabric/hazelcast-network.xml was (re)created."
}

function f_nexus_license_config() {
    local _mount="$1"
    local _license_file="$2"
    if [ -d "${_license_file}" ]; then
        _license_file="$(ls -1t ${_license_file%/}/sonatype-*.lic 2>/dev/null | head -n1)"
    fi
    if [ ! -s "${_license_file}" ]; then
        _log "ERROR" "No license file: ${_license_file}"
        return 1
    fi
    if ! grep -q "nexus.licenseFile" "${_mount%/}/etc/nexus.properties"; then
        _upsert "${_mount%/}/etc/nexus.properties" "nexus.licenseFile" "${_license_file}" || return $?
        _log "INFO" "License file is specified in ${_mount%/}/etc/nexus.properties"
    fi
}

function f_migrate_blobstores() {
    local _blobs_dir="${1:-"${_SONATYPE_WORK%/}/blobs"}"
    local _blobs_share_dir="${2:-"${_SHARE_DIR%/}/blobs"}"
    [ -L "${_blobs_dir}" ] && return 0
    [ ! -d "${_blobs_dir}" ] && return 11
    [ -d "${_blobs_dir%/}_orig" ] && return 12  # It's strange dir is not symlink but _orig exists.
    # If share "blobs" dir exist, not copying as this could be 2nd or 3rd node
    if [ ! -d "${_blobs_share_dir}" ]; then
        mkdir -m 777 -p "${_blobs_share_dir}" || return 13
        cp -v -pR ${_blobs_dir%/}/* ${_blobs_share_dir%/}/ || return $?
    fi
    mv -v "${_blobs_dir%/}" "${_blobs_dir%/}_orig" || return $?
    ln -s "${_blobs_share_dir}" "${_blobs_dir%/}"
}

function f_update_hosts() {
    local _merge_to="${1:-"/etc/hosts"}"
    sort | uniq | while read -r _l; do
        local _regex="$(echo "${_l}" | sed "s/\./\\\./g" | sed -E "s/ +/|/g")"
        local _txt="$(grep -vwE "(${_regex})" ${_merge_to} 2>/dev/null)" # NOTE: this grep does not work with Mac
        if [ -n "${_txt}" ]; then
            echo -e "${_txt}\n${_l}"
        else
            echo -e "${_l}"
        fi > "${_merge_to}" || return $?
    done
}

main() {
    f_nexus_license_config "${_SONATYPE_WORK%/}" "${_SHARE_DIR%/}"
    f_nexus_ha_config "${_SONATYPE_WORK%/}" "${_NODE_MEMBERS}" "${_SHARE_DIR%/}"

    if  [ "$(id -u)" == "0" ] && [ -d "${_SHARE_DIR%/}" ]; then
        echo "$(hostname -i) $(hostname -f) $(hostname -s)" | f_update_hosts "${_SHARE_DIR%/}/${_POD_PREFIX}_hosts"
        cat << EOF > /tmp/_update_hosts.sh
$(type f_update_hosts | grep -v '^f_update_hosts is a function')

while true; do
    sleep 6
    cat "${_SHARE_DIR%/}/${_POD_PREFIX}_hosts" | f_update_hosts
done
EOF
        /usr/bin/bash /tmp/_update_hosts.sh &>/tmp/_update_hosts.out &
        disown $!
    fi
    # finally migrate directories under "blobs"
    f_migrate_blobstores "${_SONATYPE_WORK%/}/blobs" "${_SHARE_DIR%/}/blobs"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main
fi