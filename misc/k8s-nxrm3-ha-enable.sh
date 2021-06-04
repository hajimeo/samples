#!/usr/bin/env bash
_DL_URL="${_DL_URL:-"https://raw.githubusercontent.com/hajimeo/samples/master"}"
_import() { [ ! -s /tmp/${1} ] && curl -sf --compressed "${_DL_URL%/}/bash/$1" -o /tmp/${1};. /tmp/${1}; }
_import "utils.sh"

_SHARE_DIR="$1" # Just for checking product license
_NODE_MEMBERS="${2-"nxrm3-ha1 nxrm3-ha2 nxrm3-ha3"}"
_SONATYPE_WORK=${_SONATYPE_WORK:-"/nexus-data"}
_HELM_NAME="nexus-repository-manager"

function f_nexus_ha_config() {
    local _mount="$1"
    local _members="$2"
    _upsert "${_mount%/}/etc/nexus.properties" "nexus.clustered" "true" || return $?
    _upsert "${_mount%/}/etc/nexus.properties" "nexus.log.cluster.enabled" "false" || return $?
    _upsert "${_mount%/}/etc/nexus.properties" "nexus.hazelcast.discovery.isEnabled" "false" || return $?
    [ -f "${_mount%/}/etc/fabric/hazelcast-network.xml" ] && mv -f ${_mount%/}/etc/fabric/hazelcast-network.xml{,.bak}
    # TODO: TCP IP discover somehow does not work
    #[ ! -d "${_mount%/}/etc/fabric" ] && mkdir -p "${_mount%/}/etc/fabric"
    #curl -s -f -m 7 --retry 2 -L "${_DL_URL%/}/misc/hazelcast-network.tmpl.xml" -o "${_mount%/}/etc/fabric/hazelcast-network.xml" || return $?
    #local _my_hostname="$(hostname -f)"
    #local _my_ipaddress="$(hostname -i)"    # this may not be accurate but should be OK for NXRM3 Pod
    #local _member=""
    #for _m in ${_members}; do
    #    _member="${_m}-${_HELM_NAME}"
    #    if [[ "${_my_hostname}" =~ ^${_m} ]]; then
    #        _member="${_my_ipaddress}"
    #    fi
    #    sed -i "0,/<member>%HA_NODE_/ s/<member>%HA_NODE_.%<\/member>/<member>${_member}<\/member>/" "${_mount%/}/etc/fabric/hazelcast-network.xml" || return $?
    #done
    cp -v -f /opt/sonatype/nexus/etc/fabric/hazelcast-network-default.xml ${_mount%/}/etc/fabric/hazelcast-network.xml || return $?
    sed -i 's/<multicast enabled="false"/<multicast enabled="true"/' "${_mount%/}/etc/fabric/hazelcast-network.xml" || return $?
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
    if ! grep -q "nexus.licenseFile" "${_mount%/}/etc/nexus.properties"; then
        _upsert "${_mount%/}/etc/nexus.properties" "nexus.licenseFile" "${_license_file}" || return $?
        _log "INFO" "License file is specified in ${_mount%/}/etc/nexus.properties"
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