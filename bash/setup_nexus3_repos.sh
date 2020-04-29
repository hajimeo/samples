#!/usr/bin/env bash

function usage() {
    echo "Main purpose of this script is injecting components into various repositories.
This script should be safe to run multiple times.
Ref: https://github.com/sonatype/nexus-toolbox/tree/master/prime-repos

Repository Naming Rules:
    <format>_(proxy|hosted|group)
    Except, <format> for 'maven2' is 'maven'.

REQIOREMENTS / DEPENDENCY:
    If Mac, 'gsed' is required.
"
}

# Global variables
_DEFAULT_USER="${_DEFAULT_USER:-"admin"}"
_DEFAULT_PWD="${_DEFAULT_PWD:-"admin123"}"
_NEXUS_URL="${_NEXUS_URL:-"http://`hostname -f`:8081"}"
_TID="${_TID:-80}"
_TMP="${_TMP:-"/tmp"}"

function f_setup_maven() {
    local _prefix="${1:-"maven"}"
    # If no xxxx-proxy, create it
    if ! _does_repo_exist "${_prefix}-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"MIXED","layoutPolicy":"PERMISSIVE"},"proxy":{"remoteUrl":"https://repo1.maven.org/maven2/","contentMaxAge":-1,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"maven2-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    _get_test "${_prefix}-proxy" "junit/junit/4.12/junit-4.12.jar" "${_TMP%/}/junit-4.12.jar" || return $?

    # If no xxxx-hosted, create it
    if ! _does_repo_exist "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"MIXED","layoutPolicy":"PERMISSIVE"},"storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"maven2-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    _upload_test "${_prefix}-hosted" -F maven2.groupId=junit -F maven2.artifactId=junit -F maven2.version=4.21 -F maven2.asset1=@${_TMP%/}/junit-4.12.jar -F maven2.asset1.extension=jar

    # If no xxxx-group, create it
    if ! _does_repo_exist "${_prefix}-group"; then
        # Hosted first
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"maven2-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group ("." in groupdId should be changed to "/")
    _get_test "${_prefix}-group" "org/apache/httpcomponents/httpclient/4.5.12/httpclient-4.5.12.jar" || return $?
}

function f_setup_pypi() {
    local _prefix="${1:-"pypi"}"
    # If no xxxx-proxy, create it
    if ! _does_repo_exist "${_prefix}-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://pypi.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"pypi-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    _get_test "${_prefix}-proxy" "packages/unit/0.2.2/Unit-0.2.2.tar.gz" "${_TMP%/}/Unit-0.2.2.tar.gz" || return $?

    # If no xxxx-hosted, create it
    if ! _does_repo_exist "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"pypi-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    _upload_test "${_prefix}-hosted" -F "pypi.asset=@${_TMP%/}/Unit-0.2.2.tar.gz"

    # If no xxxx-group, create it
    if ! _does_repo_exist "${_prefix}-group"; then
        # Hosted first
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"pypi-group"}],"type":"rpc"}'
    fi
    # add some data for xxxx-group ("." in groupdId should be changed to "/")
    _get_test "${_prefix}-group" "packages/pyyaml/5.3.1/PyYAML-5.3.1.tar.gz" || return $?
}



function _get_test() {
    local _repo="$1"
    local _path="$2"
    local _out_path="${3:-"/dev/null"}"
    local _base_url="${_NEXUS_URL}"
    curl -sf -D ${_TMP%/}/_proxy_test_header_$$.out -o ${_out_path} -u ${_DEFAULT_USER}:${_DEFAULT_PWD} -k "${_base_url%/}/repository/${_repo%/}/${_path#/}"
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        _log "ERROR" "Failed to get ${_base_url%/}/repository/${_repo%/}/${_path#/} (${_rc})"
        cat ${_TMP%/}/_proxy_test_header_$$.out >&2
        return ${_rc}
    fi
}

function _upload_test() {
    local _repo="$1"
        local _forms=${@:2} #-F maven2.groupId=junit -F maven2.artifactId=junit -F maven2.version=4.21 -F maven2.asset1=@${_TMP%/}/junit-4.12.jar -F maven2.asset1.extension=jar
    local _base_url="${_NEXUS_URL}"
    curl -sf -D ${_TMP%/}/_upload_test_header_$$.out -u ${_DEFAULT_USER}:${_DEFAULT_PWD} -H "accept: application/json" -H "Content-Type: multipart/form-data" -X POST -k "${_base_url%/}/service/rest/v1/components?repository=${_repo}" ${_forms}
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        if grep -qE '^HTTP/1.1 [45]' ${_TMP%/}/_upload_test_header_$$.out; then
            _log "ERROR" "Failed to post to ${_base_url%/}/service/rest/v1/components?repository=${_repo} (${_rc})"
            cat ${_TMP%/}/_upload_test_header_$$.out >&2
            return ${_rc}
        else
            _log "WARN" "May failed to post to ${_base_url%/}/service/rest/v1/components?repository=${_repo} (${_rc})"
            cat ${_TMP%/}/_upload_test_header_$$.out >&2
        fi
    fi
}

function _does_repo_exist() {
    local _repo_name="$1"
    # At this moment, not always checking
    find ${_TMP%/}/ -type f -name 'f_get_repo_names_*.out' -mmin +5 -delete
    if [ ! -s ${_TMP%/}/f_get_repo_names_$$.out ]; then
        _api "/service/rest/v1/repositories" | grep '"name":' > ${_TMP%/}/f_get_repo_names_$$.out
    fi
    if [ -n "${_repo_name}" ]; then
        # case insensitive
        grep -iq "\"${_repo_name}\"" ${_TMP%/}/f_get_repo_names_$$.out
    fi
}

function _log() {
    # At this moment, outputting to STDERR
    if [ -n "${_LOG_FILE_PATH}" ]; then
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%Sz')] $@" | tee -a ${_LOG_FILE_PATH} 1>&2
    else
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%Sz')] $@" 1>&2
    fi
}



function f_add_nxrm_repos() {
    local __doc__="Add/populate NXRM repositories"
    local _usr="${1:-${_USER}}"
    # npm (group is added later)
    _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://registry.npmjs.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"npm-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"npm-proxy"}],"type":"rpc"}'
    _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"npm-hosted","format":"","type":"","url":"","online":true,"recipe":"npm-hosted"}],"type":"rpc"}'
    # pypi
    _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"group":{"memberNames":["pypi-hosted","pypi-proxy"]}},"name":"pypi-group","format":"","type":"","url":"","online":true,"recipe":"pypi-group"}],"type":"rpc"}'
    # docker
    _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"forceBasicAuth":false,"v1Enabled":true},"proxy":{"remoteUrl":"https://registry-1.docker.io","contentMaxAge":1440,"metadataMaxAge":1440},"dockerProxy":{"indexType":"HUB","cacheForeignLayers":false,"useTrustStoreForIndexAccess":false},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"docker-proxy","format":"","type":"","url":"","online":true,"undefined":[false,false],"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"docker-proxy"}],"type":"rpc"}'
    _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"forceBasicAuth":true,"v1Enabled":true},"storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW"},"cleanup":{"policyName":[]}},"name":"docker-hosted","format":"","type":"","url":"","online":true,"undefined":[false,false],"recipe":"docker-hosted"}],"type":"rpc"}'
    # yum
    _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"http://mirror.centos.org/centos/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false},"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"yum-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"yum-proxy"}],"type":"rpc"}'
    _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"yum":{"repodataDepth":1,"deployPolicy":"STRICT"},"storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"yum-hosted","format":"","type":"","url":"","online":true,"recipe":"yum-hosted"}],"type":"rpc"}'
    _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"group":{"memberNames":["yum-hosted","yum-proxy"]}},"name":"yum-group","format":"","type":"","url":"","online":true,"recipe":"yum-group"}],"type":"rpc"}'
    # gems
    _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://rubygems.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"gems-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"rubygems-proxy"}],"type":"rpc"}'
    _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"gems-hosted","format":"","type":"","url":"","online":true,"recipe":"rubygems-hosted"}],"type":"rpc"}'
    _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"group":{"memberNames":["gems-hosted","gems-proxy"]}},"name":"gems-group","format":"","type":"","url":"","online":true,"recipe":"rubygems-group"}],"type":"rpc"}'
    # raw
    _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"default","strictContentTypeValidation":false,"writePolicy":"ALLOW"},"cleanup":{"policyName":[]}},"name":"raw-hosted","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}'
}

function _b64_url_enc() {
    python -c "import base64, urllib; print(urllib.quote(base64.urlsafe_b64encode('$1')))"
    #python3 -c "import base64, urllib.parse; print(urllib.parse.quote(base64.urlsafe_b64encode('$1'.encode('utf-8')), safe=''))"
}

function _apiS() {
    local __doc__="NXRM (not really API but) API wrapper with session"
    local _data="${1}"
    local _method="${2}"
    local _usr="${3:-${_DEFAULT_USER}}"
    local _pwd="${4-${_DEFAULT_PWD}}"   # Accept an empty password
    local _nexus_url="${5:-${_NEXUS_URL}}"

    local _usr_b64="$(_b64_url_enc "${_usr}")"
    local _pwd_b64="$(_b64_url_enc "${_pwd}")"
    local _user_pwd="username=${_usr_b64}&password=${_pwd_b64}"
    [ -n "${_data}" ] && [ -z "${_method}" ] && _method="POST"
    [ -z "${_method}" ] && _method="GET"

    # Mac's /tmp is symlink so without the ending "/", would needs -L but does not work with -delete
    find ${_TMP%/}/ -type f -name '.nxrm_c_*' -mmin +10 -delete
    local _c="${_TMP%/}/.nxrm_c_$$"
    if [ ! -s ${_c} ]; then
        curl -sf -D ${_TMP%/}/_apiS_header_$$.out -b ${_c} -c ${_c} -o/dev/null -k "${_nexus_url%/}/service/rapture/session" -d "${_user_pwd}"
        local _rc=$?
        if [ "${_rc}" != "0" ] ; then
            rm -f ${_c}
            return ${_rc}
        fi
    fi
    # TODO: not sure if this is needed. seems cookie works with 3.19.1 but not sure about older version
    local _H="NXSESSIONID: $(_sed -nr 's/.+\sNXSESSIONID\s+([0-9a-f]+)/\1/p' ${_c})"
    local _content_type="Content-Type: application/json"
    if [ "${_data:0:1}" != "{" ]; then
        _content_type="Content-Type: text/plain"
    elif [[ ! "${_data}" =~ "tid" ]]; then
        _data="${_data%\}},\"tid\":${_TID}}"
        _TID=$(( ${_TID} + 1 ))
    fi

    if [ -z "${_data}" ]; then
        # GET and DELETE *can not* use Content-Type json
        curl -sf -D ${_TMP%/}/_apiS_header_$$.out -b ${_c} -c ${_c} -k "${_nexus_url%/}/service/extdirect" -X ${_method} -H "${_H}" || return $?
    else
        curl -sf -D ${_TMP%/}/_apiS_header_$$.out -b ${_c} -c ${_c} -k "${_nexus_url%/}/service/extdirect" -X ${_method} -H "${_H}" -H "${_content_type}" -d ${_data} || return $?
    fi > ${_TMP%/}/_apiS_nxrm$$.out
    if ! cat ${_TMP%/}/_apiS_nxrm$$.out | python -m json.tool 2>/dev/null; then
        cat ${_TMP%/}/_apiS_nxrm$$.out
    fi
}

function _api() {
    local __doc__="NXRM3 API wrapper"
    local _path="${1}"
    local _data="${2}"
    local _method="${3}"
    local _usr="${4:-${_DEFAULT_USER}}"
    local _pwd="${5-${_DEFAULT_PWD}}"   # If explicitly empty string, curl command will ask password (= may hang)
    local _nexus_url="${6:-${_NEXUS_URL}}"

    local _user_pwd="${_usr}"
    [ -n "${_pwd}" ] && _user_pwd="${_usr}:${_pwd}"
    [ -n "${_data}" ] && [ -z "${_method}" ] && _method="POST"
    [ -z "${_method}" ] && _method="GET"
    # TODO: check if GET and DELETE *can not* use Content-Type json?
    local _content_type="Content-Type: application/json"
    [ "${_data:0:1}" != "{" ] && _content_type="Content-Type: text/plain"

    if [ -z "${_data}" ]; then
        # GET and DELETE *can not* use Content-Type json
        curl -sf -D ${_TMP%/}/_api_header_$$.out -u "${_user_pwd}" -k "${_nexus_url%/}/${_path#/}" -X ${_method} || return $?
    else
        curl -sf -D ${_TMP%/}/_api_header_$$.out -u "${_user_pwd}" -k "${_nexus_url%/}/${_path#/}" -X ${_method} -H "${_content_type}" -d "${_data}" || return $?
    fi > ${_TMP%/}/f_api_nxrm_$$.out
    if ! cat ${_TMP%/}/f_api_nxrm_$$.out | python -m json.tool 2>/dev/null; then
        echo -n `cat ${_TMP%/}/f_api_nxrm_$$.out`
        echo ""
    fi
}

# To support Mac...
function _sed() {
    local _cmd="sed"; which gsed &>/dev/null && _cmd="gsed"
    ${_cmd} "$@"
}

# pypi
# https://files.pythonhosted.org/packages/24/44/38f25717a71df9992d5bd065fa3e7f85a2673af2ccee56caedf60386de5e/Unit-0.2.2.tar.gz
# https://files.pythonhosted.org/packages/cf/43/977e6d6f0d59449e77407bf4fa01b4d97c59136cdc615663256e78e9af74/Unit-0.2.2-py3-none-any.whl



main() {
    f_setup_maven
    f_setup_pypi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main
fi