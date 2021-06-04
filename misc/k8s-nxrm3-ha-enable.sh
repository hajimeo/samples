#!/usr/bin/env bash
_DL_URL="${_DL_URL:-"https://raw.githubusercontent.com/hajimeo/samples/master"}"
_import() { [ ! -s /tmp/${1} ] && curl -sf --compressed "${_DL_URL%/}/bash/$1" -o /tmp/${1};. /tmp/${1}; }
_import "utils.sh"

_NODE_MEMBERS="${1:-"nxrm3-ha1 nxrm3-ha2 nxrm3-ha3"}"
_SHARE_DIR="$2" # Just for checking product license
_SONATYPE_WORK=${_SONATYPE_WORK:-"/nexus-data"}
_HELM_NAME="nexus-repository-manager"

function f_nexus_ha_config() {
    local _mount="$1"
    local _members="$2"
    _upsert "${_mount%/}/etc/nexus.properties" "nexus.clustered" "true" || return $?
    _upsert "${_mount%/}/etc/nexus.properties" "nexus.log.cluster.enabled" "false" || return $?
    _upsert "${_mount%/}/etc/nexus.properties" "nexus.hazelcast.discovery.isEnabled" "false" || return $?
    [ -f "${_mount%/}/etc/fabric/hazelcast-network.xml" ] && mv -f ${_mount%/}/etc/fabric/hazelcast-network.xml{,bak}
    [ ! -d "${_mount%/}/etc/fabric" ] && mkdir -p "${_mount%/}/etc/fabric"
    curl -s -f -m 7 --retry 2 -L "${_DL_URL%/}/misc/hazelcast-network.tmpl.xml" -o "${_mount%/}/etc/fabric/hazelcast-network.xml" || return $?
    for _m in ${_members}; do
        sed -i "0,/<member>%HA_NODE_/ s/<member>%HA_NODE_.%<\/member>/<member>${_m}-${_HELM_NAME}<\/member>/" "${_mount%/}/etc/fabric/hazelcast-network.xml" || return $?
    done
    _log "INFO" "HA-C configured against config files under ${_mount}"
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
    if ! grep -q "${_mount%/}/etc/nexus.properties" "${_license_file}"; then
        _upsert "${_license_file}" "${_mount%/}/etc/nexus.properties" "${_license_file}" || return $?
        _log "INFO" "License file is specified in  ${_mount}"
    fi
}

main() {
    if [ ! -s "${_SONATYPE_WORK%/}/etc/nexus.properties" ]; then
        echo "No nexus.properties file: ${_SONATYPE_WORK%/}/etc/nexus.properties"; return 1
    fi
    if [ -d "${_SHARE_DIR%/}" ]; then
        f_nexus_license_config "${_SONATYPE_WORK%/}" "${_SHARE_DIR%/}"
    fi
    f_nexus_ha_config "${_SONATYPE_WORK%/}" "${_NODE_MEMBERS}"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main
fi