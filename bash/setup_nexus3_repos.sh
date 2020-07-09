#!/usr/bin/env bash
# BASH script to setup NXRM3 repositories.
# Based on functions in start_hdp.sh from 'samples' and install_sonatype.sh from 'work'.
#

function usage() {
    local _filename="$(basename $BASH_SOURCE)"
    echo "Main purpose of this script is to create repositories with some sample components.
Also functions in this script can be used for testing downloads and uploads.

DOWNLOADS:
    curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_nexus3_repos.sh \\
         -o ${_WORK_DIR%/}/setup_nexus3_repos.sh

REQUIREMENTS / DEPENDENCIES:
    If Mac, 'gsed' and 'ggrep' are required.
    brew install gnu-sed ggrep

COMMAND OPTIONS:
    -A
        Automatically setup Nexus (best effort)
    -r <response_file_path>
        Specify your saved response file. Without -a, you can review your responses.
    -f <format1,format2,...>
        Comma separated repository formats.
        Default: ${_REPO_FORMATS}
    -v <nexus version>
        Create Nexus container if version number (eg: 3.24.0) is given and 'docker' command is available.

EXAMPLE COMMANDS:
Start script with interview mode:
    ${_filename}

Using default values and NO interviews:
    ${_filename} -a

Create Nexus 3.24.0 container and setup available formats:
    ${_filename} -v 3.24.0 [-a]

Setup docker repositories only (and populate some data if 'docker' command is available):
    ${_filename} -f docker [-a]

Setup maven,npm repositories only:
    ${_filename} -f maven,npm [-a]

Using previously saved response file and review your answers:
    ${_filename} -r ./my_saved_YYYYMMDDhhmmss.resp

Using previously saved response file and NO interviews:
    ${_filename} -a -r ./my_saved_YYYYMMDDhhmmss.resp

NOTE:
For fresh install with same container name:
    docker rm -f <container>
    sudo mv ${_WORK_DIR%/}/<mounting-volume> /tmp/  # or rm -rf

To upgrade, if /nexus-data is a mounted volume, just reuse same response file but with newer Nexus version.
If HA-C, edit nexus.properties for all nodes, then remove 'db' directory from node-2 and node-3.
"
}


# Global variables
_ADMIN_USER="admin"
_ADMIN_PWD="admin123"
_REPO_FORMATS="maven,pypi,npm,docker,yum,rubygem,raw,conan"
## Updatable variables
_NEXUS_URL=${_NEXUS_URL:-"http://localhost:8081/"}
_DOCKER_NETWORK_NAME=${_DOCKER_NETWORK_NAME:-"nexus"}
_IS_NXRM2=${_IS_NXRM2:-"N"}
_NO_DATA=${_NO_DATA:-"N"}
_TID="${_TID:-80}"
## Misc.
_DOMAIN="standalone.localdomain"
_UTIL_DIR="$HOME/.bash_utils"
if [ "`uname`" = "Darwin" ]; then
    _WORK_DIR="$HOME/share/sonatype"
else
    _WORK_DIR="/var/tmp/share/sonatype"
fi
_TMP="$(mktemp -d)"  # for downloading/uploading assets
_LOG_FILE_PATH="/tmp/setup_nexus3_repos.log"
# Variables which used by command arguments
_AUTO=false
_DEBUG=false
_RESP_FILE=""


### Repository setup functions ################################################################################
function f_setup_maven() {
    local _prefix="${1:-"maven"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"MIXED","layoutPolicy":"PERMISSIVE"},"proxy":{"remoteUrl":"https://repo1.maven.org/maven2/","contentMaxAge":-1,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"maven2-proxy"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # add some data for xxxx-proxy
    # If NXRM2: _get_asset_NXRM2 "${_prefix}-proxy" "junit/junit/4.12/junit-4.12.jar"
    _get_asset "${_prefix}-proxy" "junit/junit/4.12/junit-4.12.jar" "${_TMP%/}/junit-4.12.jar" || return $?

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"MIXED","layoutPolicy":"PERMISSIVE"},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"maven2-hosted"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # add some data for xxxx-hosted
    #mvn deploy:deploy-file -DgroupId=junit -DartifactId=junit -Dversion=4.21 -DgeneratePom=true -Dpackaging=jar -DrepositoryId=nexus -Durl=${r_NEXUS_URL}/repository/${_prefix}-hosted -Dfile=${_TMP%/}/junit-4.12.jar
    f_upload_asset "${_prefix}-hosted" -F maven2.groupId=junit -F maven2.artifactId=junit -F maven2.version=4.21 -F maven2.asset1=@${_TMP%/}/junit-4.12.jar -F maven2.asset1.extension=jar

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        # Hosted first
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"maven2-group"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # add some data for xxxx-group ("." in groupdId should be changed to "/")
    _get_asset "${_prefix}-group" "org/apache/httpcomponents/httpclient/4.5.12/httpclient-4.5.12.jar" || return $?

    # Another test for get from proxy, then upload to hosted, then get from hosted
    #_get_asset "${_prefix}-proxy" "org/apache/httpcomponents/httpclient/4.5.12/httpclient-4.5.12.jar" "${_TMP%/}/httpclient-4.5.12.jar"
    #_upload_asset "${_prefix}-hosted" -F maven2.groupId=org.apache.httpcomponents -F maven2.artifactId=httpclient -F maven2.version=4.5.12 -F maven2.asset1=@${_TMP%/}/httpclient-4.5.12.jar -F maven2.asset1.extension=jar
    #_get_asset "${_prefix}-hosted" "org/apache/httpcomponents/httpclient/4.5.12/httpclient-4.5.12.jar"
}

function f_setup_pypi() {
    local _prefix="${1:-"pypi"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://pypi.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"pypi-proxy"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # add some data for xxxx-proxy
    _get_asset "${_prefix}-proxy" "packages/unit/0.2.2/Unit-0.2.2.tar.gz" "${_TMP%/}/Unit-0.2.2.tar.gz" || return $?

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"pypi-hosted"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # add some data for xxxx-hosted
    f_upload_asset "${_prefix}-hosted" -F "pypi.asset=@${_TMP%/}/Unit-0.2.2.tar.gz"

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        # Hosted first
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"pypi-group"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # add some data for xxxx-group
    _get_asset "${_prefix}-group" "packages/pyyaml/5.3.1/PyYAML-5.3.1.tar.gz" || return $?
}

function f_setup_npm() {
    local _prefix="${1:-"npm"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://registry.npmjs.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"npm-proxy"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # add some data for xxxx-proxy
    _get_asset "${_prefix}-proxy" "lodash/-/lodash-4.17.4.tgz" "${_TMP%/}/lodash-4.17.15.tgz" || return $?

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"npm-hosted"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # add some data for xxxx-hosted
    f_upload_asset "${_prefix}-hosted" -F "npm.asset=@${_TMP%/}/lodash-4.17.15.tgz"

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        # Hosted first
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"npm-group"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # add some data for xxxx-group
    _get_asset "${_prefix}-group" "grunt/-/grunt-1.1.0.tgz" || return $?
}

function f_setup_docker() {
    local _prefix="${1:-"docker"}"
    local _tag_name="${2:-"alpine:3.7"}"
    local _blob_name="${3:-"${r_BLOB_NAME:-"default"}"}"
    #local _opts="--tls-verify=false"    # TODO: only for podman. need an *easy* way to use http for 'docker'

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        # "httpPort":18178 - 18179
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":18178,"httpsPort":18179,"forceBasicAuth":false,"v1Enabled":true},"proxy":{"remoteUrl":"https://registry-1.docker.io","contentMaxAge":1440,"metadataMaxAge":1440},"dockerProxy":{"indexType":"HUB","cacheForeignLayers":false,"useTrustStoreForIndexAccess":false},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"undefined":[false,false],"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"docker-proxy"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # add some data for xxxx-proxy
    f_populate_docker_proxy

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        # Using "httpPort":18181 - 18182,
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":18181,"httpsPort":18182,"forceBasicAuth":true,"v1Enabled":true},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"undefined":[false,false],"recipe":"docker-hosted"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # add some data for xxxx-hosted
    f_populate_docker_hosted

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        # Using "httpPort":18174 - 18175
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":18184,"httpsPort":18185,"forceBasicAuth":true,"v1Enabled":true},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":false},"group":{"memberNames":["docker-hosted","docker-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"undefined":[false,false],"recipe":"docker-group"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # add some data for xxxx-group
    f_populate_docker_proxy "hello-world" "${r_DOCKER_GROUP}" "18185 18184"
}
function f_docker_login() {
    local _host_port="${1}"
    local _backup_ports="${2}"
    local _user="${3:-"${r_ADMIN_USER:-"${_ADMIN_USER}"}"}"
    local _pwd="${4:-"${r_ADMIN_PWD:-"${_ADMIN_PWD}"}"}"
    local _cmd="${5:-"${r_DOCKER_CMD:-"docker"}"}"

    if [ -z "${_cmd}" ] || ! which ${_cmd} &>/dev/null; then
        _log "WARN" "No docker command specified (docker or podman) for $FUNCNAME, so exiting"
        return 0
    fi

    if [ -z "${_host_port}" ] && [ -n "${_backup_ports}" ]; then
        for __p in ${_backup_ports}; do
            nc -w1 -z localhost ${__p} && _host_port="localhost:${__p}" 2>/dev/null && break
        done
        if [ -n "${_host_port}" ]; then
            _log "INFO" "No hostname:port for $FUNCNAME is set, so try with ${_host_port}"
        fi
    fi
    if [ -z "${_host_port}" ]; then
        _log "WARN" "No hostname:port for $FUNCNAME, so exiting"
        return 0
    fi

    _log "DEBUG" "${_cmd} login ${_host_port} --username ${_user} --password ********"
    ${_cmd} login ${_host_port} --username ${_user} --password ${_pwd} &>/dev/null || return $?
    echo "${_host_port}"
}
function f_populate_docker_proxy() {
    local _tag_name="${1:-"alpine:3.7"}"
    local _host_port="${2:-"${r_DOCKER_PROXY}"}"
    local _backup_ports="${3:-"18179 18178"}"
    local _cmd="${4:-"${r_DOCKER_CMD:-"docker"}"}"
    _host_port="$(f_docker_login "${_host_port}" "${_backup_ports}")" || return $?

    for _imn in $(${_cmd} images --format "{{.Repository}}" | grep -w "${_tag_name}"); do
        _log "WARN" "Deleting ${_imn} (wait for 5 secs)";sleep 5
        if ! ${_cmd} rmi ${_imn}; then
            _log "WARN" "Deleting ${_imn} failed but keep continuing..."
        fi
    done
    _log "DEBUG" "${_cmd} pull ${_host_port}/${_tag_name}"
    ${_cmd} pull ${_host_port}/${_tag_name} || return $?
}
function f_populate_docker_hosted() {
    local _tag_name="${1:-"alpine:3.7"}"
    local _host_port="${2:-"${r_DOCKER_HOSTED}"}"
    local _backup_ports="${3:-"18182 18181"}"
    local _cmd="${4:-"${r_DOCKER_CMD:-"docker"}"}"
    _host_port="$(f_docker_login "${_host_port}" "${_backup_ports}")" || return $?

    # In _docker_proxy, the image might be already pulled.
    if ! ${_cmd} tag ${_host_port:-"localhost"}/${_tag_name} ${_host_port}/${_tag_name}; then
        # "FROM alpine:3.7\nRUN apk add --no-cache mysql-client\nENTRYPOINT [\"mysql\"]"
        # NOTE docker build -f does not work (bug?)
        local _build_dir="$(mktemp -d)" || return $?
        cd ${_build_dir} || return $?
        echo -e "FROM ${_tag_name}\n" > Dockerfile && ${_cmd} build --rm -t ${_tag_name} .
        cd -    # should check the previous return code.
        if ! ${_cmd} tag localhost/${_tag_name} ${_host_port}/${_tag_name}; then
            ${_cmd} tag ${_tag_name} ${_host_port}/${_tag_name} || return $?
        fi
    fi
    _log "DEBUG" "${_cmd} push ${_host_port}/${_tag_name}"
    ${_cmd} push ${_host_port}/${_tag_name} || return $?
}

function f_setup_yum() {
    local _prefix="${1:-"yum"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"http://mirror.centos.org/centos/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"yum-proxy"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # add some data for xxxx-proxy
    if which yum &>/dev/null; then
        f_generate_yum_repo_file "${_prefix}-proxy"
        yum --disablerepo="*" --enablerepo="nexusrepo" install --downloadonly --downloaddir=${_TMP%/} dos2unix || return $?
    else
        _get_asset "${_prefix}-proxy" "7/os/x86_64/Packages/dos2unix-6.0.3-7.el7.x86_64.rpm" "${_TMP%/}/dos2unix-6.0.3-7.el7.x86_64.rpm" || return $?
    fi

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"yum":{"repodataDepth":1,"deployPolicy":"PERMISSIVE"},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":false,"writePolicy":"ALLOW"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"yum-hosted"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # add some data for xxxx-hosted
    local _upload_file="$(find ${_TMP%/} -type f -size +1k -name "dos2unix-*.el7.x86_64.rpm" 2>/dev/null | tail -n1)"
    if [ -s "${_upload_file}" ]; then
        f_upload_asset "${_prefix}-hosted" -F "yum.asset=@${_upload_file}" -F "yum.asset.filename=$(basename ${_upload_file})" -F "yum.directory=/7/os/x86_64/Packages" || return $?
    else
        _log "WARN" "No rpm file for upload test."
    fi
    #curl -u 'admin:admin123' --upload-file /etc/pki/rpm-gpg/RPM-GPG-KEY-pmanager ${r_NEXUS_URL%/}/repository/yum-hosted/RPM-GPG-KEY-pmanager

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"yum-group"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # add some data for xxxx-group
    _get_asset "${_prefix}-group" "7/os/x86_64/Packages/$(basename ${_upload_file})" || return $?
}
function f_generate_yum_repo_file() {
    local _repo="${1:-"yum-group"}"
    local _out_file="${2:-"/etc/yum.repos.d/nexus-yum-test.repo"}"
    local _blob_name="${3:-"${r_BLOB_NAME:-"default"}"}"
    local _base_url="${r_NEXUS_URL:-"${_NEXUS_URL}"}"

    local _repo_url="${_base_url%/}/repository/${_repo}"
echo '[nexusrepo]
name=Nexus Repository
baseurl='${_repo_url%/}'/$releasever/os/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
priority=1' > ${_out_file}
}

function f_setup_rubygem() {
    local _prefix="${1:-"rubygem"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://rubygems.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"rubygems-proxy"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # TODO: add some data for xxxx-proxy

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"rubygems-hosted"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # TODO: add some data for xxxx-hosted

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["gems-hosted","gems-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"rubygems-group"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # TODO: add some data for xxxx-group
    #_get_asset "${_prefix}-group" "7/os/x86_64/Packages/$(basename ${_upload_file})" || return $?
}

function f_setup_raw() {
    local _prefix="${1:-"raw"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # TODO: If no xxxx-proxy, create it
    # TODO: add some data for xxxx-proxy

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":false,"writePolicy":"ALLOW"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # TODO: add some data for xxxx-hosted

    # TODO: If no xxxx-group, create it
    # TODO: add some data for xxxx-group
}

function f_setup_conan() {
    local _prefix="${1:-"conan"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"
    # NOTE: If you disabled Anonymous access, then it is needed to enable the Conan Bearer Token Realm (via Administration > Security > Realms):

    # If no xxxx-proxy, create it (No HA, but seems to work with HA???)
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://conan.bintray.com","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"conan-proxy"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    # TODO: add some data for xxxx-proxy

    # TODO: If no xxxx-hosted, create it (Not implemented yet: https://issues.sonatype.org/browse/NEXUS-23629)
    #if ! _does_repo_exist "${_prefix}-hosted"; then
    #fi
    # TODO: add some data for xxxx-hosted

    # TODO: If no xxxx-group, create it (As no hosted, probably no group)
    #if ! _does_repo_exist "${_prefix}-group"; then
    #fi
    # TODO: add some data for xxxx-group
    #_get_asset "${_prefix}-group" "7/os/x86_64/Packages/$(basename ${_upload_file})" || return $?
}


### Misc. functions / utility type functions #################################################################
# Create a test user and test role
function f_testuser() {
    f_apiS '{"action":"coreui_Role","method":"create","data":[{"version":"","source":"default","id":"test-role","name":"testRole","description":"test role","privileges":["nx-repository-admin-*-*-*"],"roles":[]}],"type":"rpc"}'
    f_apiS '{"action":"coreui_User","method":"create","data":[{"userId":"testuser","version":"","firstName":"test","lastName":"user","email":"testuser@example.com","status":"active","roles":["test-role"],"password":"testuser"}],"type":"rpc"}'
}

function f_trust_ca() {
    local _ca_pem="$1"
    if [ -z "${_ca_pem}" ]; then
        _ca_pem="${_WORK_DIR%/}/rootCA_standalone.crt"
        if [ ! -s "${_ca_pem}" ]; then
            curl -s -f -m 7 --retry 2 -L "https://raw.githubusercontent.com/hajimeo/samples/master/misc/rootCA_standalone.crt" -o ${_WORK_DIR%/}/rootCA_standalone.crt || return $?
        fi
    fi
    # Test
    local _CN="$(openssl x509 -in "${_ca_pem}" -noout -subject | grep -oE "CN\s*=.+" | cut -d"=" -f2 | xargs)"  # somehow xargs trim spaces
    if [ -z "${_CN}" ]; then
        _log "ERROR" "No common name found from ${_ca_pem}"
        return 1
    fi
    local _file_name="$(basename "${_ca_pem}")"
    local _ca_dir=""
    local _ca_cmd=""
    if which update-ca-trust &>/dev/null; then
        _ca_cmd="update-ca-trust"
        _ca_dir="/etc/pki/ca-trust/source/anchors"
    elif which update-ca-certificates &>/dev/null; then
        _ca_cmd="update-ca-certificates"
        _ca_dir="/usr/local/share/ca-certificates/extra"
    elif which security &>/dev/null && [ -d $HOME/Library/Keychains ]; then
        # If we know the common name, and if exists, no change.
        security find-certificate -c "${_CN}" $HOME/Library/Keychains/login.keychain-db && return 0
        # NOTE: -d for add to admin cert store (and not sure what this means)
        sudo security add-trusted-cert -d -r trustRoot -k $HOME/Library/Keychains/login.keychain-db "${_ca_pem}"
        return $?
    fi

    if [ ! -d "${_ca_dir}" ]; then
        _log "ERROR" "Couldn't find 'update-ca-trust' or 'update-ca-certificates' command or directory to install CA cert."
        return 1
    fi

    if [ -s ${_ca_dir%/}/${_file_name} ]; then
        _log "DEBUG" "${_ca_dir%/}/${_file_name} already exists."
        return 0
    fi

    cp "${_ca_pem}" ${_ca_dir%/}/ || return $?
    _log "DEBUG" "Copied \"${_ca_pem}\" into ${_ca_dir%/}/"
    ${_ca_cmd} || return $?
    _log "DEBUG" "Executed ${_ca_cmd}"
}

# f_get_and_upload_jars "maven" "junit" "junit" "3.8 4.0 4.1 4.2 4.3 4.4 4.5 4.6 4.7 4.8 4.9 4.10 4.11 4.12"
function f_get_and_upload_jars() {
    local _prefix="${1:-"maven"}"
    local _group_id="$2"
    local _artifact_id="$3"
    local _versions="$4"
    local _base_url="${5:-"${r_NEXUS_URL:-"${_NEXUS_URL}"}"}"

    for _v in ${_versions}; do
        # TODO: currently only maven / maven2, and doesn't work with non usual filenames
        #local _path="$(echo "${_path_with_VAR}" | sed "s/<VAR>/${_v}/g")"  # junit/junit/<VAR>/junit-<VAR>.jar
        local _path="${_group_id%/}/${_artifact_id%/}/${_v}/${_artifact_id%/}-${_v}.jar"
        local _out_path="${_TMP%/}/$(basename ${_path})"
        _log "INFO" "Downloading \"${_path}\" from \"${_prefix}-proxy\" ..."
        f_get_asset "${_prefix}-proxy" "${_path}" "${_out_path}" "${_base_url}"

        _log "INFO" "Uploading \"${_out_path}\" to \"${_prefix}-hosted\" ..."
        f_upload_asset "${_prefix}-hosted" -F maven2.groupId=${_group_id%/} -F maven2.artifactId=${_artifact_id%/} -F maven2.version=${_v} -F maven2.asset1=@${_out_path} -F maven2.asset1.extension=jar
    done
}

# f_move_jars "maven-hosted" "maven-releases" "junit"
function f_move_jars() {
    local _from_repo="$1"
    local _to_repo="$2"
    local _group="$3"
    local _artifact="${4:-"*"}"
    local _version="${5:-"*"}"
    [ -z "${_group}" ] && return 11
    f_api "/service/rest/v1/staging/move/${_to_repo}?repository=${_from_repo}&group=${_group}&name=${_artifact}&version=${_version}" "" "POST"
}

function f_get_asset() {
    if [[ "${_IS_NXRM2}" =~ ^[yY] ]]; then
        _get_asset_NXRM2 $@
    else
        _get_asset $@
    fi
}
function _get_asset() {
    local _repo="$1"
    local _path="$2"
    local _out_path="${3:-"/dev/null"}"
    local _base_url="${4:-"${r_NEXUS_URL:-"${_NEXUS_URL}"}"}"
    local _user="${5:-"${r_ADMIN_USER:-"${_ADMIN_USER}"}"}"
    local _pwd="${6:-"${r_ADMIN_PWD:-"${_ADMIN_PWD}"}"}"
    if [[ "${_NO_DATA}" =~ ^[yY] ]]; then
        _log "INFO" "_NO_DATA is set so no action."; return 0
    fi
    if [ -d "${_out_path}" ]; then
        _out_path="${_out_path%/}/$(basename ${_path})"
    fi
    curl -sf -D ${_TMP%/}/_proxy_test_header_$$.out -o ${_out_path} -u ${_user}:${_pwd} -k "${_base_url%/}/repository/${_repo%/}/${_path#/}"
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        _log "ERROR" "Failed to get ${_base_url%/}/repository/${_repo%/}/${_path#/} (${_rc})"
        cat ${_TMP%/}/_proxy_test_header_$$.out >&2
        return ${_rc}
    fi
}
# For NXRM2. TODO: may not work with some repo
function _get_asset_NXRM2() {
    local _repo="$1"
    local _path="$2"
    local _out_path="${3:-"/dev/null"}"
    local _base_url="${4:-"${r_NEXUS_URL:-"${_NEXUS_URL%/}/nexus/"}"}"
    local _usr="${4:-${r_ADMIN_USER:-"${_ADMIN_USER}"}}"
    local _pwd="${5-${r_ADMIN_PWD:-"${_ADMIN_PWD}"}}"   # If explicitly empty string, curl command will ask password (= may hang)

    if [[ "${_NO_DATA}" =~ ^[yY] ]]; then
        _log "INFO" "_NO_DATA is set so no action."; return 0
    fi
    curl -sf -D ${_TMP%/}/_proxy_test_header_$$.out -o ${_out_path} -u ${_usr}:${_pwd} -k "${_base_url%/}/content/repositories/${_repo%/}/${_path#/}"
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        _log "ERROR" "Failed to get ${_base_url%/}/content/repository/${_repo%/}/${_path#/} (${_rc})"
        cat ${_TMP%/}/_proxy_test_header_$$.out >&2
        return ${_rc}
    fi
}

function f_upload_asset() {
    local _repo="$1"
    local _forms=${@:2} #-F maven2.groupId=junit -F maven2.artifactId=junit -F maven2.version=4.21 -F maven2.asset1=@${_TMP%/}/junit-4.12.jar -F maven2.asset1.extension=jar
    # NOTE: Because _forms takes all arguments except first one, can't assign any other arguments
    local _usr="${r_ADMIN_USER:-"${_ADMIN_USER}"}"
    local _pwd="${r_ADMIN_PWD:-"${_ADMIN_PWD}"}"   # If explicitly empty string, curl command will ask password (= may hang)
    local _base_url="${r_NEXUS_URL:-"${_NEXUS_URL}"}"
    if [[ "${_NO_DATA}" =~ ^[yY] ]]; then
        _log "INFO" "_NO_DATA is set so no action."; return 0
    fi
    curl -sf -D ${_TMP%/}/_upload_test_header_$$.out -u ${_usr}:${_pwd} -H "accept: application/json" -H "Content-Type: multipart/form-data" -X POST -k "${_base_url%/}/service/rest/v1/components?repository=${_repo}" ${_forms}
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        if grep -qE '^HTTP/1.1 [45]' ${_TMP%/}/_upload_test_header_$$.out; then
            _log "ERROR" "Failed to post to ${_base_url%/}/service/rest/v1/components?repository=${_repo} (${_rc})"
            cat ${_TMP%/}/_upload_test_header_$$.out >&2
            return ${_rc}
        else
            _log "WARN" "Post to ${_base_url%/}/service/rest/v1/components?repository=${_repo} might have been failed (${_rc})"
            cat ${_TMP%/}/_upload_test_header_$$.out >&2
        fi
    fi
    # If going to migrate from NXRM2 or some exported repository
    #_sample=maven-hosted/com/example/nexus-proxy/1.0.1-SNAPSHOT/maven-metadata.xml
    #if [[ "${_sample}" =~ ^\.?/?([^/]+)/(.+)/([^/]+)/([^/]+)/(.+)$ ]]; then
    #    echo ${BASH_REMATCH[1]}   # repo name
    #    echo ${BASH_REMATCH[2]} | sed 's|/|.|g'   # group id
    #    echo ${BASH_REMATCH[3]}   # artifact id
    #    echo ${BASH_REMATCH[4]}   # version string
    #    echo ${BASH_REMATCH[5]}   # filename
    #fi
}

function _is_repo_available() {
    local _repo_name="$1"
    # At this moment, not always checking
    find ${_TMP%/}/ -type f -name '_does_repo_exist*.out' -mmin +5 -delete 2>/dev/null
    if [ ! -s ${_TMP%/}/_does_repo_exist$$.out ]; then
        f_api "/service/rest/v1/repositories" | grep '"name":' > ${_TMP%/}/_does_repo_exist$$.out
    fi
    if [ -n "${_repo_name}" ]; then
        # case insensitive
        grep -iq "\"${_repo_name}\"" ${_TMP%/}/_does_repo_exist$$.out
    fi
}
function _is_blob_available() {
    local _blob_name="$1"
    # At this moment, not always checking
    find ${_TMP%/}/ -type f -name '_does_blob_exist*.out' -mmin +5 -delete 2>/dev/null
    if [ ! -s ${_TMP%/}/_does_blob_exist$$.out ]; then
        f_api "/service/rest/beta/blobstores" | grep '"name":' > ${_TMP%/}/_does_blob_exist$$.out
    fi
    if [ -n "${_blob_name}" ]; then
        # case insensitive
        grep -iq "\"${_blob_name}\"" ${_TMP%/}/_does_blob_exist$$.out
    fi
}

function f_apiS() {
    local __doc__="NXRM (not really API but) API wrapper with session"
    local _data="${1}"
    local _method="${2}"
    local _usr="${3:-${r_ADMIN_USER:-"${_ADMIN_USER}"}}"
    local _pwd="${4-${r_ADMIN_PWD:-"${_ADMIN_PWD}"}}"   # Accept an empty password
    local _nexus_url="${5:-${r_NEXUS_URL:-"${_NEXUS_URL}"}}"

    local _usr_b64="$(_b64_url_enc "${_usr}")"
    local _pwd_b64="$(_b64_url_enc "${_pwd}")"
    local _user_pwd="username=${_usr_b64}&password=${_pwd_b64}"
    [ -n "${_data}" ] && [ -z "${_method}" ] && _method="POST"
    [ -z "${_method}" ] && _method="GET"

    # Mac's /tmp is symlink so without the ending "/", would needs -L but does not work with -delete
    find ${_TMP%/}/ -type f -name '.nxrm_c_*' -mmin +10 -delete 2>/dev/null
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
        curl -sf -D ${_TMP%/}/_apiS_header_$$.out -b ${_c} -c ${_c} -k "${_nexus_url%/}/service/extdirect" -X ${_method} -H "${_H}"
    else
        curl -sf -D ${_TMP%/}/_apiS_header_$$.out -b ${_c} -c ${_c} -k "${_nexus_url%/}/service/extdirect" -X ${_method} -H "${_H}" -H "${_content_type}" -d "${_data}"
    fi > ${_TMP%/}/_apiS_nxrm$$.out
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        cat ${_TMP%/}/_apiS_header_$$.out >&2
        return ${_rc}
    fi
    if ! cat ${_TMP%/}/_apiS_nxrm$$.out | python -m json.tool 2>/dev/null; then
        cat ${_TMP%/}/_apiS_nxrm$$.out
    fi
}
function f_api() {
    local __doc__="NXRM3 API wrapper"
    local _path="${1}"
    local _data="${2}"
    local _method="${3}"
    local _usr="${4:-${r_ADMIN_USER:-"${_ADMIN_USER}"}}"
    local _pwd="${5-${r_ADMIN_PWD:-"${_ADMIN_PWD}"}}"   # If explicitly empty string, curl command will ask password (= may hang)
    local _nexus_url="${6:-"${r_NEXUS_URL:-"${_NEXUS_URL}"}"}"

    local _user_pwd="${_usr}"
    [ -n "${_pwd}" ] && _user_pwd="${_usr}:${_pwd}"
    [ -n "${_data}" ] && [ -z "${_method}" ] && _method="POST"
    [ -z "${_method}" ] && _method="GET"
    # TODO: check if GET and DELETE *can not* use Content-Type json?
    local _content_type="Content-Type: application/json"
    [ "${_data:0:1}" != "{" ] && _content_type="Content-Type: text/plain"

    if [ -z "${_data}" ]; then
        # GET and DELETE *can not* use Content-Type json
        curl -sf -D ${_TMP%/}/_api_header_$$.out -u "${_user_pwd}" -k "${_nexus_url%/}/${_path#/}" -X ${_method}
    else
        curl -sf -D ${_TMP%/}/_api_header_$$.out -u "${_user_pwd}" -k "${_nexus_url%/}/${_path#/}" -X ${_method} -H "${_content_type}" -d "${_data}"
    fi > ${_TMP%/}/f_api_nxrm_$$.out
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        cat ${_TMP%/}/_api_header_$$.out >&2
        return ${_rc}
    fi
    if ! cat ${_TMP%/}/f_api_nxrm_$$.out | python -m json.tool 2>/dev/null; then
        echo -n `cat ${_TMP%/}/f_api_nxrm_$$.out`
        echo ""
    fi
}

# NOTE: To test name resolution as no nslookup,ping,nc, docker exec -ti nexus3240-1 curl -v -I http://nexus3240-3.standalone.localdomain:8081/
function f_update_hosts_for_container() {
    local _container_name="${1}"
    local _hostname="${2}"  # Optional
    local _cmd="${3:-"${r_DOCKER_CMD:-"docker"}"}"

    [ -z "${_container_name}" ] && _container_name="`echo "${_hostname}" | cut -d"." -f1`"
    [ -z "${_container_name}" ] && return 1
    [ -z "${_hostname}" ] && _hostname="${_container_name}.${_DOMAIN#.}"

    local _container_ip="`f_get_container_ip "${_container_name}" "${_cmd}"`"
    if [ -z "${_container_ip}" ]; then
        _log "WARN" "${_container_name} is not returning IP. Please update hosts file manually."
        return 1
    fi

    if ! _update_hosts_file "${_hostname}" "${_container_ip}"; then
        _log "WARN" "Please update hosts file to add '${_container_ip} ${_hostname}'"
        return 1
    fi
    _log "DEBUG" "Updated hosts file with '${_container_ip} ${_hostname}'"
}

function f_socks5_proxy() {
    local _port="${1:-"48484"}"
    [[ "${_port}" =~ ^[0-9]+$ ]] || return 11

    local _cmd="ssh -4gC2TxnNf -D${_port} localhost &>/dev/null &"
    local _host_ip="$(hostname -I 2>/dev/null | cut -d" " -f1)"

    local _pid="$(_pid_by_port "${_port}")"
    if [ -n "${_pid}" ]; then
        local _ps_comm="$(ps -o comm= -p ${_pid})"
        ps -Fwww -p ${_pid}
        if [ "${_ps_comm}" == "ssh" ]; then
            _log "INFO" "The Socks proxy might be already running (${_pid})"
        else
            _log "WARN" "The port:${_port} is used by PID:${_pid}. Please stop this PID or use different port."
            return 1
        fi
    else
        eval "${_cmd}" || return $?
        _log "INFO" "Started socks proxy on \"${_host_ip:-"xxx.xxx.xxx.xxx"}:${_port}\"."
    fi

    echo "NOTE: Below command starts Chrome with this Socks5 proxy:
# Mac:
open -na \"Google Chrome\" --args --user-data-dir=\$HOME/.chrome_pxy --proxy-server=socks5://${_host_ip:-"xxx.xxx.xxx.xxx"}:${_port} ${r_NEXUS_URL}
# Win:
\"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe\" --user-data-dir=%USERPROFILE%\.chrome_pxy --proxy-server=socks5://${_host_ip:-"xxx.xxx.xxx.xxx"}:${_port}" ${r_NEXUS_URL}
}

function f_docker_run_or_start() {
    local _name="$1"
    local _mount="$2"
    local _ext_opts="$3"
    local _cmd="${4:-"${r_DOCKER_CMD:-"docker"}"}"

    if ${_cmd} ps --format "{{.Names}}" | grep -qE "^${_name}$"; then
        _log "WARN" "Container:'${_name}' already exists. So that starting instead of docker run...";sleep 3
        ${_cmd} start ${_name} || return $?
    else
        _log "DEBUG" "Creating Container with \"${_name}\" \"${_mount}\" \"${_ext_opts}\""
        # TODO: normally container fails after a few minutes, so checking the exit code of docker run is useless
        f_docker_run "${_name}" "${_mount}" "${_ext_opts}" || return $?
        _log "INFO" "\"${_cmd} run\" executed. Check progress with \"${_cmd} logs -f ${_name}\""
    fi
    sleep 3
    # Even specifying --ip, get IP from the container in below function
    f_update_hosts_for_container "${_name}"
}

function f_docker_run() {
    # TODO: shouldn't use any global variables in a function.
    local _name="$1"
    local _mount="$2"
    local _ext_opts="$3"
    local _cmd="${4:-"${r_DOCKER_CMD:-"docker"}"}"

    local _p=""
    if ! _isYes "${r_NEXUS_INSTALL_HAC}"; then
        [ -n "${r_NEXUS_CONTAINER_PORT1}" ] && _p="${_p% } -p ${r_NEXUS_CONTAINER_PORT1}:8081"
        [ -n "${r_NEXUS_CONTAINER_PORT2}" ] && _p="${_p% } -p ${r_NEXUS_CONTAINER_PORT2}:8443"
        if [[ "${r_DOCKER_PROXY}" =~ :([0-9]+)$ ]]; then
            _pid_by_port "${BASH_REMATCH[1]}" &>/dev/null || _p="${_p% } -p ${BASH_REMATCH[1]}:${BASH_REMATCH[1]}"
        fi
        if [[ "${r_DOCKER_HOSTED}" =~ :([0-9]+)$ ]]; then
            _pid_by_port "${BASH_REMATCH[1]}" &>/dev/null || _p="${_p% } -p ${BASH_REMATCH[1]}:${BASH_REMATCH[1]}"
        fi
        if [[ "${r_DOCKER_GROUP}" =~ :([0-9]+)$ ]]; then
            _pid_by_port "${BASH_REMATCH[1]}" &>/dev/null || _p="${_p% } -p ${BASH_REMATCH[1]}:${BASH_REMATCH[1]}"
        fi
    fi

    # Nexus specific config update/creation
    local _v_opt="-v ${_WORK_DIR%/}:${_WORK_DIR%/}"
    if _isYes "${r_NEXUS_MOUNT}"; then
        if [ -n "${_mount}" ]; then
            _v_opt="${_v_opt% } -v ${_mount%/}:/nexus-data"
            if _isYes "${r_NEXUS_INSTALL_HAC}" && [ -n "${r_NEXUS_MOUNT_DIR_SHARED}" ]; then
                if [ ! -d "${r_NEXUS_MOUNT_DIR_SHARED}" ]; then
                    mkdir -m 777 -p ${r_NEXUS_MOUNT_DIR_SHARED%/} || return $?
                fi
                _v_opt="${_v_opt% } -v ${r_NEXUS_MOUNT_DIR_SHARED%/}:/nexus-data/blobs"
            fi

            if [ ! -d "${_mount%/}/etc/jetty" ]; then
                mkdir -p ${_mount%/}/etc/jetty || return $?
                chmod -R a+w ${_mount%/}
            else
                _log "WARN" "Mount directory:${_mount%/} already exists. Reusing...";sleep 3
            fi

            # If the file exists, at this moment, not adding misc. nexus properties
            if [ ! -s "${_mount%/}/etc/nexus.properties" ]; then
                echo 'nexus.onboarding.enabled=false
nexus.scripts.allowCreation=true' > ${_mount%/}/etc/nexus.properties || return $?
            fi

            # HTTPS/SSL/TLS setup
            f_nexus_https_config "${_mount%/}" || return $?
            # HA-C related setup
            if _isYes "${r_NEXUS_INSTALL_HAC}"; then
                f_nexus_ha_config "${_mount%/}" || return $?
            fi

            local _license="${r_NEXUS_LICENSE_FILE}"
            [ -z "${_license}" ] && _license="$(ls -1t ${_WORK_DIR%/}/sonatype-*.lic 2>/dev/null | head -n1)"
            if [ -n "${_license}" ]; then
                _upsert ${_mount%/}/etc/nexus.properties "nexus.licenseFile" "${_license}" || return $?
            elif _isYes "${r_NEXUS_INSTALL_HAC}"; then
                _log "ERROR" "HA-C is requested but no license."
                return 1
            fi
        fi
    fi

    #[ -z "${_INTERNAL_DNS}" ] && _INTERNAL_DNS="$(docker inspect bridge | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['IPAM']['Config'][0]['Subnet'])" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+').1"
    [ -z "${INSTALL4J_ADD_VM_PARAMS}" ] && INSTALL4J_ADD_VM_PARAMS="-Xms1g -Xmx2g -XX:MaxDirectMemorySize=1g"
    local _full_cmd="${_cmd} run -t -d ${_p} --name=${_name} --hostname=${_name}.${_DOMAIN#.} \\
        ${_v_opt} \\
        --network=${_DOCKER_NETWORK_NAME} ${_ext_opts} \\
        -e INSTALL4J_ADD_VM_PARAMS=\"${INSTALL4J_ADD_VM_PARAMS}\" \\
        sonatype/nexus3:${r_NEXUS_VERSION}"
    _log "DEBUG" "${_full_cmd}"
    eval "${_full_cmd}" || return $?
}

function f_nexus_https_config() {
    local _mount="$1"
    _upsert ${_mount%/}/etc/nexus.properties "ssl.etc" "\${karaf.data}/etc/jetty" || return $?
    _upsert ${_mount%/}/etc/nexus.properties "nexus-args" "\${jetty.etc}/jetty.xml,\${jetty.etc}/jetty-http.xml,\${jetty.etc}/jetty-requestlog.xml,\${ssl.etc}/jetty-https.xml" || return $?
    _upsert ${_mount%/}/etc/nexus.properties "application-port-ssl" "8443" || return $?

    if [ ! -s "${_mount%/}/etc/jetty/jetty-https.xml" ]; then
        curl -s -f -L -o "${_mount%/}/etc/jetty/jetty-https.xml" "https://raw.githubusercontent.com/hajimeo/samples/master/misc/nexus-jetty-https.xml" || return $?
    fi
    if [ ! -s "${_mount%/}/etc/jetty/keystore.jks" ]; then
        curl -s -f -L -o "${_mount%/}/etc/jetty/keystore.jks" "https://raw.githubusercontent.com/hajimeo/samples/master/misc/standalone.localdomain.jks" || return $?
    fi
    f_trust_ca || return $?
    _log "DEBUG" "HTTPS configured against config files under ${_mount}"
}

function f_nexus_ha_config() {
    local _mount="$1"
    _upsert ${_mount%/}/etc/nexus.properties "nexus.clustered" "true" || return $?
    _upsert ${_mount%/}/etc/nexus.properties "nexus.log.cluster.enabled" "false" || return $?
    _upsert ${_mount%/}/etc/nexus.properties "nexus.hazelcast.discovery.isEnabled" "false" || return $?
    [ -f "${_mount%/}/etc/fabric/hazelcast-network.xml" ] && mv -f ${_mount%/}/etc/fabric/hazelcast-network.xml{,bak}
    [ ! -d "${_mount%/}/etc/fabric" ] && mkdir -p "${_mount%/}/etc/fabric"
    curl -s -f -m 7 --retry 2 -L "https://raw.githubusercontent.com/hajimeo/samples/master/misc/hazelcast-network.tmpl.xml" -o "${_mount%/}/etc/fabric/hazelcast-network.xml" || return $?
    for _i in {1..3}; do
        local _tmp_v_name="r_NEXUS_CONTAINER_NAME_${_i}"
        _sed -i "0,/<member>%HA_NODE_/ s/<member>%HA_NODE_.%<\/member>/<member>${!_tmp_v_name}.${_DOMAIN#.}<\/member>/" "${_mount%/}/etc/fabric/hazelcast-network.xml" || return $?
    done
    _log "DEBUG" "HA-C configured against config files under ${_mount}"
}

function f_docker_network() {
    local _network_name="${1:-"${_DOCKER_NETWORK_NAME}"}"
    local _subnet_16="${2:-"172.100"}"
    local _cmd="${3:-"${r_DOCKER_CMD:-"docker"}"}"

    ${_cmd} network ls --format "{{.Name}}" | grep -qE "^${_network_name}$" && return 0
    # TODO: add validation if subnet is already taken. --subnet is required to specify IP.
    ${_cmd} network create --driver=bridge --subnet=${_subnet_16}.0.0/16 --gateway=${_subnet_16}.0.1 ${_network_name} || return $?
    _log "DEBUG" "${_cmd} network '${_network_name}' created with subnet:${_subnet_16}.0.0"
}

function f_get_available_container_ip() {
    local _hostname="${1}"  # optional
    local _check_file="${2}"  # /etc/hosts or /etc/banner_add_hosts
    local _subnet="${3}"    # 172.18.0.0
    local _network_name="${4:-${_DOCKER_NETWORK_NAME:-"bridge"}}"
    local _cmd="${5:-"${r_DOCKER_CMD:-"docker"}"}"

    local _ip=""
    [ -z "${_subnet}" ] && _subnet="$(${_cmd} inspect ${_network_name} | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['IPAM']['Config'][0]['Subnet'])" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')"
    local _subnet_24="$(echo "${_subnet}" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')"
    ${_cmd} network inspect ${_network_name} | grep '"IPv4Address"' > ${_TMP%/}/${_cmd}_network_${_network_name}_IPs.out

    if [ -n "${_hostname}" ]; then
        local _short_name="`echo "${_hostname}" | cut -d"." -f1`"
        [ "${_short_name}" == "${_hostname}" ] && _hostname="${_short_name}.${_DOMAIN#.}"

        # Not perfect but... if the IP is in the /etc/hosts, then reuse it
        _ip="$(grep -E "^${_subnet_24%.}\.[0-9]+\s+${_hostname}\s*" ${_check_file} | awk '{print $1}' | tail -n1)"
    fi

    if [ -z "${_ip}" ]; then
        # Using the range 101 - 199
        for _i in {101..199}; do
            if [ -s "${_check_file}" ] && grep -qE "^${_subnet_24%.}\.${_i}\s+" ${_check_file}; then
                _log "DEBUG" "${_subnet_24%.}\.${_i} exists in ${_check_file}. Skipping..."
                continue
            fi
            if ! grep -q "\"${_subnet_24%.}.${_i}/" ${_TMP%/}/${_cmd}_network_${_network_name}_IPs.out; then
                _log "DEBUG" "Using ${_subnet_24%.}\.${_i} as it does not exist in ${_cmd}_network_${_network_name}_IPs.out."
                _ip="${_subnet_24%.}.${_i}"
                break
            fi
        done
    fi
    [ -z "${_ip}" ] && return 111

    if [ -n "${_hostname}" ] && [ -s "${_check_file}" ]; then
        # To reserve this IP, updating the check_file
        if _update_hosts_file "${_hostname}" "${_ip}" "${_check_file}"; then
            _log "DEBUG" "Updated ${_check_file} with \"${_hostname}\" \"${_ip}\""
        fi
    fi
    _log "DEBUG" "IP:${_ip} ($@)"
    echo "${_ip}"
}

function f_get_container_ip() {
    local _container_name="$1"
    local _cmd="${2:-"${r_DOCKER_CMD:-"docker"}"}"
    ${_cmd} exec -it ${_container_name} hostname -i | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' -m1 -o | tr -cd "[:print:]"   # remove unnecessary control characters
}


### Interview / questions related functions ###################################################################
function interview() {
    _log "INFO" "Ask a few questions to setup this Nexus.
You can stop this interview anytime by pressing 'Ctrl+c' (except while typing secret/password).
"
    trap 'interview_cancel_handler' SIGINT
    while true; do
        questions
        echo "=================================================================="
        _ask "Interview completed.
Would you like to save your response?" "Y"
        if _isYes; then
            _save_resp "" "${r_NEXUS_CONTAINER_NAME}"
            break
        else
            _ask "Would you like to re-do the interview?" "Y"
            if ! _isYes; then
                echo "Continuing without saving..."
                break
            fi
        fi
    done
    trap - SIGINT
}
function interview_cancel_handler() {
    echo ""
    echo ""
    _ask "Before exiting, would you like to save your current responses?" "N"
    if _isYes; then
        _save_resp
    fi
    # To get out from the trap, it seems I need to use exit.
    echo "Exiting ... (NOTE: -h or --help for help/usage)"
    exit
}

function questions() {
    if [ -z "${r_DOCKER_CMD}" ]; then
        if which docker &>/dev/null; then
            r_DOCKER_CMD="docker"
        elif which podman &>/dev/null; then
            r_DOCKER_CMD="podman"
        fi
    fi

    # Ask if install nexus docker container if docker command is available
    if [ -n "${r_DOCKER_CMD}" ]; then
        _ask "Would you like to install Nexus in a docker container?" "Y" "r_NEXUS_INSTALL" "N" "N"
        if _isYes "${r_NEXUS_INSTALL}"; then
            echo "NOTE: sudo password may be required."; sleep 2
            local _nexus_version=""
            _ask "Nexus version" "latest" "r_NEXUS_VERSION" "N" "Y"
            local _ver_num=$(echo "${r_NEXUS_VERSION}" | sed 's/[^0-9]//g')
            _ask "Would you like to build HA-C?" "N" "r_NEXUS_INSTALL_HAC" "N" "N"
            if _isYes "${r_NEXUS_INSTALL_HAC}"; then
                echo "NOTE: You may also need to set up a reverse proxy."; sleep 2
                # NOTE: mounting a volume to sonatype-work is mandatory for HA-C
                r_NEXUS_MOUNT="Y"
                for _i in {1..3}; do
                    _ask "Nexus container name ${_i}" "nexus${_ver_num}-${_i}" "r_NEXUS_CONTAINER_NAME_${_i}" "N" "N" "_is_container_name"
                    local _tmp_v_name="r_NEXUS_CONTAINER_NAME_${_i}"
                    _ask "Mount to container:/nexus-data" "${_WORK_DIR%/}/nexus-data_${!_tmp_v_name}" "r_NEXUS_MOUNT_DIR_${_i}" "N" "Y" "_is_existed"
                done
                _ask "Mount path for shared blobstore" "${_WORK_DIR%/}/nexus-data_nexus${_ver_num}_shared_blobs" "r_NEXUS_MOUNT_DIR_SHARED" "N" "Y" "_is_existed"
                _ask "Would you like to start a Socks proxy (if you do not have a reverse proxy)" "N" "r_SOCKS_PROXY"
                if _isYes "${r_SOCKS_PROXY}"; then
                    _ask "Socks proxy port" "48484" "r_SOCKS_PROXY_PORT"
                fi
            else
                _ask "Nexus container name" "nexus${_ver_num}" "r_NEXUS_CONTAINER_NAME" "N" "N" "_is_container_name"
                _ask "Would you like to mount SonatypeWork directory?" "Y" "r_NEXUS_MOUNT" "N" "N"
                if _isYes "${r_NEXUS_MOUNT}"; then
                    _ask "Mount to container:/nexus-data" "${_WORK_DIR%/}/nexus-data_${r_NEXUS_CONTAINER_NAME%/}" "r_NEXUS_MOUNT_DIR" "N" "Y" "_is_existed"
                fi
                _ask "Nexus container exposing port for HTTP (for 8081)" "8081" "r_NEXUS_CONTAINER_PORT1" "N" "Y" "_is_port_available"
                _ask "Nexus container exposing port for HTTPS (for 8443)" "8443" "r_NEXUS_CONTAINER_PORT2" "N" "N" "_is_port_available"
            fi
            _ask "Nexus license file path if you have:
If empty, it will try finding from ${_WORK_DIR%/}/sonatype-*.lic" "" "r_NEXUS_LICENSE_FILE" "N" "N" "_is_license_path"
        fi
    fi

    if _isYes "${r_NEXUS_INSTALL}"; then
        if _isYes "${r_NEXUS_INSTALL_HAC}"; then
            _ask "Nexus base URL (normally reverse proxy)" "http://${r_NEXUS_CONTAINER_NAME_1}.${_DOMAIN#.}:8081/" "r_NEXUS_URL" "N" "Y"
        else
            _ask "Nexus base URL" "http://localhost:${r_NEXUS_CONTAINER_PORT1:-"8081"}/" "r_NEXUS_URL" "N" "Y"
        fi
    else
        _ask "Nexus base URL" "" "r_NEXUS_URL" "N" "Y" "_is_url_reachable"
    fi
    local _host="$(hostname -f)"
    [[ "${r_NEXUS_URL}" =~ ^https?://([^:/]+).+$ ]] && _host="${BASH_REMATCH[1]}"
    _ask "Blob store name" "default" "r_BLOB_NAME" "N" "Y"
    _ask "Admin username" "${_ADMIN_USER}" "r_ADMIN_USER" "N" "Y"
    _ask "Admin password" "${_ADMIN_PWD}" "r_ADMIN_PWD" "Y" "Y"
    _ask "Formats to setup (comma separated)" "${_REPO_FORMATS}" "r_REPO_FORMATS" "N" "Y"

    ## for f_setup_docker()
    if [ -n "${r_DOCKER_CMD}" ]; then
        _ask "Docker command for pull/push sample ('docker' or 'podman')" "${r_DOCKER_CMD}" "r_DOCKER_CMD" "N" "N"
        r_DOCKER_PROXY="$(questions_docker_repos "Proxy" "${_host}" "18179")"
        r_DOCKER_HOSTED="$(questions_docker_repos "Hosted" "${_host}" "18182")"
        r_DOCKER_GROUP="$(questions_docker_repos "Group" "${_host}" "18185")"
        # NOTE: Above would require insecure-registry settings by editing daemon.json, but Mac doesn't have (=can't automate)
    fi
}
function questions_docker_repos() {
    local _repo_type="$1"
    local _def_host="$2"
    local _def_port="$3"
    local _is_installing="${4:-"${r_NEXUS_INSTALL}"}"
    local _repo_CAP="$( echo ${_repo_type} | awk '{print toupper($0)}' )"

    local _q="Docker ${_repo_type} repo hostname:port"
    while true; do
        local _tmp_host_port=""
        _ask "${_q}" "${_def_host}:${_def_port}" "_tmp_host_port" "N" "N"
        if [[ "${_tmp_host_port}" =~ ^\s*([^:]+):([0-9]+)\s*$ ]]; then
            _def_host="${BASH_REMATCH[1]}"
            _def_port="${BASH_REMATCH[2]}"
            if _isYes "${_is_installing}" && nc -w1 -z ${_def_host} ${_def_port} 2>/dev/null; then
                _ask "The port in ${_def_host}:${_def_port} might be in use. Is this OK?" "Y"
                if _isYes ; then break; fi
            elif ! _isYes "${_is_installing}" && ! nc -w1 -z ${_def_host} ${_def_port} 2>/dev/null; then
                _ask "The port in ${_def_host}:${_def_port} might not be reachable. Is this OK?" "Y"
                if _isYes ; then break; fi
            else
                break
            fi
        else
            # hmm, actually the regex always should match..
            break
        fi
    done
    echo "${_def_host}:${_def_port}"
}

# Validate functions for interview/questions. NOTE: needs to start with _is.
function _is_container_name() {
    if ${r_DOCKER_CMD} ps --format "{{.Names}}" | grep -qE "^${1}$"; then
        echo "Container:'${1}' already exists." >&2
        return 1
    fi
}
function _is_license_path() {
    if [ -n "$1" ] && [ ! -s "$1" ]; then
        echo "$1 does not exist." >&2
        return 1
    elif _isYes "${r_NEXUS_INSTALL_HAC}"; then
        _license="$(ls -1t ${_WORK_DIR%/}/sonatype-*.lic 2>/dev/null | head -n1)"
        if [ -z "${_license}" ]; then
            echo "HA-C is requested but no license with 'ls ${_WORK_DIR%/}/sonatype-*.lic'." >&2
            return 1
        fi
    fi
}
function _is_url_reachable() {
    if [ -n "$1" ]; then
        curl -f -s -I -L -k -m1 --retry 0 "$1"
        echo "$1 is not reachable." >&2
        return 1
    fi
}
function _is_port_available() {
    if [ -n "$1" ] && _pid_by_port "$1" &>/dev/null; then
        echo "Port $1 is already in use." >&2
        return 1
    fi
}
function _is_existed() {
    if [ -n "$1" ] && [ -e "$1" ]; then
        echo "$1 already exists." >&2
        return 1
    fi
}


### Main #######################################################################################################
bootstrap() {
    local _no_update="${1-${_AUTO}}"
    # NOTE: if _AUTO, not checking updates to be safe.
    if [ ! -d "${_UTIL_DIR%/}" ]; then
        mkdir -p "${_UTIL_DIR%/}" || exit $?
    fi
    if [ ! -f "${_UTIL_DIR%/}/utils.sh" ]; then
        if [ ! -f "${_WORK_DIR%/}/utils.sh" ]; then
            curl -s -f -m 3 --retry 0 -L "https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils.sh" -o "${_UTIL_DIR%/}/utils.sh" || return $?
        else
            # At this moment, not updating _WORK_DIR one for myself
            #_check_update "${_WORK_DIR%/}/utils.sh"
            source "${_WORK_DIR%/}/utils.sh"
            return $?
        fi
    else
        source "${_UTIL_DIR%/}/utils.sh"
        _log "DEBUG" "_check_update ${_UTIL_DIR%/}/utils.sh with"
        ${_no_update} || _check_update "${_UTIL_DIR%/}/utils.sh"
    fi
    source "${_UTIL_DIR%/}/utils.sh"
    _log "DEBUG" "_check_update $BASH_SOURCE with force:N"
    ${_no_update} || _check_update "$BASH_SOURCE" "" "N"
}

main() {
    # Clear the log file if not empty
    [ -s "${_LOG_FILE_PATH}" ] && cat /dev/null > "${_LOG_FILE_PATH}" &>/dev/null

    # Checking requirements (so far only a few commands)
    if [ "`uname`" = "Darwin" ]; then
        if which gsed &>/dev/null && which ggrep &>/dev/null; then
            _log "DEBUG" "gsed and ggrep are available."
        else
            _log "ERROR" "gsed and ggrep are required (brew install gnu-sed ggrep)"
            return 1
        fi
    fi

    # If _RESP_FILE is popurated by -r xxxxx.resp, load it
    if [ -s "${_RESP_FILE}" ];then
        _load_resp "${_RESP_FILE}"
    elif ! ${_AUTO}; then
        _ask "Would you like to load your response file?" "Y" "" "N" "N"
        _isYes && _load_resp
    fi

    if ! ${_AUTO}; then
        interview
        _ask "Interview completed. Would like you like to setup?" "Y" "" "N" "N"
        if ! _isYes; then
            echo 'Bye!'
            exit 0
        fi
    fi

    if _isYes "${r_NEXUS_INSTALL}"; then
        echo "If 'password' is asked, please type 'sudo' password." >&2;sleep 2
        sudo echo "Starting Nexus installation..." >&2
        f_docker_network || return $?
        if _isYes "${r_NEXUS_INSTALL_HAC}"; then
            local _ip_1="$(f_get_available_container_ip "${r_NEXUS_CONTAINER_NAME_1}.${_DOMAIN#.}" "/etc/hosts")" || return $?
            local _ip_2="$(f_get_available_container_ip "${r_NEXUS_CONTAINER_NAME_2}.${_DOMAIN#.}" "/etc/hosts")" || return $?
            local _ip_3="$(f_get_available_container_ip "${r_NEXUS_CONTAINER_NAME_3}.${_DOMAIN#.}" "/etc/hosts")" || return $?
            local _ext_opts="--add-host ${r_NEXUS_CONTAINER_NAME_1}.${_DOMAIN#.}:${_ip_1}"
            _ext_opts="${_ext_opts} --add-host ${r_NEXUS_CONTAINER_NAME_2}.${_DOMAIN#.}:${_ip_2}"
            _ext_opts="${_ext_opts} --add-host ${r_NEXUS_CONTAINER_NAME_3}.${_DOMAIN#.}:${_ip_3}"
            # TODO: it should exclude own host:ip, otherwise, container's hosts file has two lines for own host:ip
            _log "DEBUG" "_add_hosts: ${_ext_opts}"

            for _i in {1..3}; do
                local _v_name="r_NEXUS_CONTAINER_NAME_${_i}"
                local _v_name_m="r_NEXUS_MOUNT_DIR_${_i}"
                local _v_name_ip="_ip_${_i}"
                local _tmp_ext_opts="${_ext_opts}"
                [ -n "${!_v_name_ip}" ] && _tmp_ext_opts="--ip=${!_v_name_ip} ${_ext_opts}"
                f_docker_run_or_start "${!_v_name}" "${!_v_name_m}" "${_tmp_ext_opts}" || return $?
                if [ "${!_v_name}" == "${r_NEXUS_CONTAINER_NAME_1}" ]; then
                    _log "INFO" "Waiting for ${r_NEXUS_CONTAINER_NAME_1} started ..."
                    # If HA-C, needs to wait the first node starts (TODO: what if not 8081?)
                    if ! _wait_url "http://${!_v_name}.${_DOMAIN#.}:8081/"; then
                        _log "ERROR" "${!_v_name}.${_DOMAIN#.} is unreachable"
                        return 1
                    fi
                fi
            done
            r_NEXUS_MOUNT_DIR="${r_NEXUS_MOUNT_DIR_1}"
        else
            f_docker_run_or_start "${r_NEXUS_CONTAINER_NAME}" "${r_NEXUS_MOUNT_DIR}"
            # 'main' requires "r_NEXUS_URL"
            if [ -z "${r_NEXUS_URL}" ] || ! _wait_url "${r_NEXUS_URL}"; then
                _log "ERROR" "${r_NEXUS_URL} is unreachable"
                return 1
            fi
        fi
    fi

    # If admin.password is accessible from this host, update with the default password.
    if [ -n "${r_NEXUS_MOUNT_DIR:-${r_NEXUS_MOUNT_DIR_1}}" ] && [ -s "${r_NEXUS_MOUNT_DIR:-${r_NEXUS_MOUNT_DIR_1}}/admin.password" ]; then
        # I think it's ok to type 'admin' in here
        _log "INFO" "Updating 'admin' user's password..."
        f_api "/service/rest/beta/security/users/admin/change-password" "${r_ADMIN_PWD:-"${_ADMIN_PWD}"}" "PUT" "admin" "$(cat "${r_NEXUS_MOUNT_DIR:-${r_NEXUS_MOUNT_DIR_1}}/admin.password")"
    fi

    _log "INFO" "Creating 'testuser' if it hasn't been created."
    f_testuser &>/dev/null  # it's OK if this fails

    if ! _is_blob_available "${r_BLOB_NAME}"; then
        if ! f_apiS '{"action":"coreui_Blobstore","method":"create","data":[{"type":"File","name":"'${r_BLOB_NAME}'","isQuotaEnabled":false,"attributes":{"file":{"path":"'${r_BLOB_NAME}'"}}}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out; then
            _log "ERROR" "Blobstore ${r_BLOB_NAME} does not exist."
            _log "ERROR" "$(cat ${_TMP%/}/f_apiS_last.out)"
            return 1
        fi
        _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    fi
    for _f in `echo "${r_REPO_FORMATS:-"${_REPO_FORMATS}"}" | sed 's/,/ /g'`; do
        _log "INFO" "Executing f_setup_${_f} ..."
        if ! f_setup_${_f}; then
            _log "ERROR" "Executing setup for format:${_f} failed."
        fi
    done

    if _isYes "${r_SOCKS_PROXY}"; then
        f_socks5_proxy "${r_SOCKS_PROXY_PORT}"
    fi
    _log "INFO" "Setup completed. (log:${_LOG_FILE_PATH})"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || [[ "$1" == "help" ]]; then
        usage | less
        exit 0
    fi

    # TODO: check if update is available if current file is older than X hours

    # parsing command options
    while getopts "ADf:r:v:" opts; do
        case $opts in
            A)
                _AUTO=true
                ;;
            D)
                _DEBUG=true
                ;;
            f)
                r_REPO_FORMATS="$OPTARG"
                ;;
            r)
                _RESP_FILE="$OPTARG"
                ;;
            v)
                r_NEXUS_VERSION="$OPTARG"
                ;;
        esac
    done

    bootstrap   # at this moment, if bootstrap fails, keeps going.
    main
else
    bootstrap true
fi