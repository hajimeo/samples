#!/usr/bin/env bash
_DL_URL="${_DL_URL:-"https://raw.githubusercontent.com/hajimeo/samples/master"}"
_import() { [ ! -s /tmp/${1} ] && curl -sf --compressed "${_DL_URL%/}/bash/$1" -o /tmp/${1};. /tmp/${1}; }
_import "utils.sh"

_SHARE_DIR="$1" # Just for checking product license
_NODE_MEMBERS="${2-"nxrm3-ha1,nxrm3-ha2,nxrm3-ha3"}"
_NAME_SUFFIX="${3-"-nexus-repository-manager"}"
_SONATYPE_WORK=${_SONATYPE_WORK:-"/nexus-data"}

_HELM3=${_HELM3:-"helm3"}
_KUBECTL=${_KUBECTL:-"kubectl"}

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
    # TODO: TCP IP discover somehow does not work with microk8s.
    [ ! -d "${_mount%/}/etc/fabric" ] && mkdir -p "${_mount%/}/etc/fabric"
    curl -s -f -m 7 --retry 2 -L "${_DL_URL%/}/misc/hazelcast-network.tmpl.xml" -o "${_mount%/}/etc/fabric/hazelcast-network.xml" || return $?
    #local _domain="$(hostname -d)"
    for _m in $(_split "${_members}"); do
        sed -i "0,/<member>%HA_NODE_/ s/<member>%HA_NODE_.%<\/member>/<member>${_m}${_NAME_SUFFIX}<\/member>/" "${_mount%/}/etc/fabric/hazelcast-network.xml" || return $?
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

# Please delete if already exists
#helm3 list -n sonatype
#helm3 delete -n sonatype nxrm3-ha{1..3}
function _build() {
    local _share_dir="${1:-"${_SHARE_DIR}"}"
    local _chart="${2:-"sonatype/nexus-repository-manager"}"
    local _name_prefix="${3:-"nxrm3-ha"}"
    local _name_space="${4:-"sonatype"}" # create namespace first

    [ -z "${_share_dir%/}" ] && return 12
    export _SHARE_DIR="${_share_dir}"
    export _NODE_MEMBERS="${_name_prefix}1,${_name_prefix}2,${_name_prefix}3"

    if [ -f "/tmp/helm-nxrm3-values.yaml" ]; then
        _log "INFO" "/tmp/helm-nxrm3-values.yaml exists. Reusing...";sleep 1
    else
        curl -sf -o/tmp/helm-nxrm3-values.yaml -L "https://raw.githubusercontent.com/hajimeo/samples/master/misc/helm-nxrm3-values.yaml"
    fi
    if [ -f "/tmp/${_name_prefix}-dep-patch.yml" ]; then
        _log "INFO" "/tmp/${_name_prefix}-dep-patch.yml exists. Reusing...";sleep 1
    else
        curl -sf -o/tmp/${_name_prefix}-dep-patch.yml -L "https://raw.githubusercontent.com/hajimeo/samples/master/misc/k8s-nxrm3-ha-deployment-patch.yaml"
    fi
    if [ -f "/tmp/${_name_prefix}-svc-patch.yml" ]; then
        _log "INFO" "/tmp/${_name_prefix}-svc-patch.yml exists. Reusing...";sleep 1
    else
        curl -sf -o/tmp/${_name_prefix}-svc-patch.yml -L "https://raw.githubusercontent.com/hajimeo/samples/master/misc/k8s-nxrm3-ha-service-patch.yaml"
    fi

    if [ -n "${_chart%/}" ] && [ "${_chart%/}" != "." ]; then
        if ! ${_HELM3} search repo "${_chart}"; then
            _log "INFO" "Didn't find chart:${_chart} so adding the repo 'sonatype'..."; sleep 1
            ${_HELM3} repo add sonatype https://sonatype.github.io/helm3-charts/ || return $?
        fi
    fi

    for _i in {1..3}; do
        local _name="${_name_prefix}${_i}"
        if ${_HELM3} status -n ${_name_space} ${_name} &>/dev/null; then
            _log "INFO" "${_name} already exists. Not installing but just Patching ..."; sleep 5
        else
            _log "INFO" "install -n ${_name_space} ${_name} ${_chart} ..."; sleep 5
            ${_HELM3} ${_HELM3_OPTS} install -n ${_name_space} ${_name} ${_chart} -f /tmp/helm-nxrm3-values.yaml || return $?
        fi

        for _j in {1..30}; do
            sleep 12
            ${_KUBECTL} get -n ${_name_space} pods --field-selector=status.phase=Running -l app.kubernetes.io/instance=${_name} | grep -E "${_name_prefix}.-nexus-repository-manager[^ ]+ +1/1" && break
        done
        sleep 10

        local _name="${_name_prefix}${_i}"
        export _POD_NAME="${_name}"

        _log "INFO" "patch service -n ${_name_space} ${_name}-nexus-repository-manager ..."
        ${_KUBECTL} patch service -n ${_name_space} ${_name}-nexus-repository-manager --patch "$(eval "echo \"$(cat /tmp/${_name_prefix}-svc-patch.yml)\"")" || return $?

        _log "INFO" "patch deployment -n ${_name_space} ${_name}-nexus-repository-manager ..."
        ${_KUBECTL} patch deployment -n ${_name_space} ${_name}-nexus-repository-manager --patch "$(eval "echo \"$(cat /tmp/${_name_prefix}-dep-patch.yml)\"")" || return $?

        for _k in {1..30}; do
            sleep 12
            ${_KUBECTL} get -n ${_name_space} pods --field-selector=status.phase=Running -l app.kubernetes.io/instance=${_name} | grep -E "${_name_prefix}.-nexus-repository-manager[^ ]+ +1/1" && break
        done
        #${_KUBECTL} describe -n ${_name_space} deployment ${_name}-nexus-repository-manager
        ${_KUBECTL} describe -n ${_name_space} pods -l app.kubernetes.io/instance=${_name} | grep -E '^Events:' -A7
    done
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