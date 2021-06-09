#!/usr/bin/env bash
_SHARE_DIR="$1" # This is mainly for setting product license
_NODE_MEMBERS="${2-"nxrm3-ha1,nxrm3-ha2,nxrm3-ha3"}"
_HELM_NAME="${3-"nexus-repository-manager"}"

_SONATYPE_WORK=${_SONATYPE_WORK:-"/nexus-data"}
_DL_URL="${_DL_URL:-"https://raw.githubusercontent.com/hajimeo/samples/master"}"
_import() { [ ! -s "${_SHARE_DIR%/}/${1}" ] && curl -sfL --compressed "${_DL_URL%/}/bash/$1" -o "${_SHARE_DIR%/}/${1}";. "${_SHARE_DIR%/}/${1}"; }
_import "utils.sh"


# Edit nexus.properties to enable HA-C and TCP/IP discovery, and modify hazelcast-network.xml if does NOT exist.
function f_nexus_ha_config() {
    local _mount="$1"
    local _members="$2"
    _upsert "${_mount%/}/etc/nexus.properties" "nexus.clustered" "true" || return $?
    _upsert "${_mount%/}/etc/nexus.properties" "nexus.log.cluster.enabled" "false" || return $?
    _upsert "${_mount%/}/etc/nexus.properties" "nexus.hazelcast.discovery.isEnabled" "false" || return $?
    _log "INFO" "${_mount%/}/etc/nexus.properties was modified for enabling HA-C and for TCP/IP discovery."
    # NOTE: At this moment skip if exist (find . -name 'hazelcast*.xml*' -delete)
    [ -f "${_mount%/}/etc/fabric/hazelcast-network.xml" ] && return 0
    #[ -f "${_mount%/}/etc/fabric/hazelcast-network.xml" ] && mv -f ${_mount%/}/etc/fabric/hazelcast-network.xml{,.bak}
    # TODO: TCP IP discover somehow does not work with Service and with microk8s.
    [ ! -d "${_mount%/}/etc/fabric" ] && mkdir -p "${_mount%/}/etc/fabric"
    curl -s -f -m 7 --retry 2 -L "${_DL_URL%/}/misc/hazelcast-network.tmpl.xml" -o "${_mount%/}/etc/fabric/hazelcast-network.xml" || return $?
    #local _domain="$(hostname -d)"
    local _fqdn="$(hostname -f)"
    for _m in $(_split "${_members}"); do
        [[ "${_fqdn}" =~ ^${_m} ]] || _m="${_m}-${_HELM_NAME}"
        sed -i "0,/<member>%HA_NODE_/ s/<member>%HA_NODE_.%<\/member>/<member>${_m}<\/member>/" "${_mount%/}/etc/fabric/hazelcast-network.xml" || return $?
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