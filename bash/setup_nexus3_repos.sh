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
    If Mac, 'gsed' is required.

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
An example of creating a docker container *manually*:
    # NOTE: To expose sonatype-work directory, add -v ${_WORK_DIR%/}/nexus-data:/nexus-data
    docker run -d -p 8081:8081 --name=nexus-3240 -v ${_WORK_DIR%/}:${_WORK_DIR%/} \\
        -e INSTALL4J_ADD_VM_PARAMS='-Dnexus.licenseFile=${_WORK_DIR%/}/sonatype-license.lic' \\
        sonatype/nexus3:3.24.0
"
}

# Global variables
_REPO_FORMATS="maven,pypi,npm,docker,yum,rubygem,raw,conan"

## Misc.
_IS_NXRM2=${_IS_NXRM2:-"N"}
_NO_DATA=${_NO_DATA:-"N"}
_TID="${_TID:-80}"
_UTIL_DIR="$HOME/.bash_utils"
if [ "`uname`" = "Darwin" ]; then
    _WORK_DIR="$HOME/share/sonatype"
else
    _WORK_DIR="/var/tmp/share/sonatype"
fi
__TMP="/tmp"

# Variables which used by command arguments
_AUTO=false
_DEBUG=false


function f_setup_maven() {
    local _prefix="${1:-"maven"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it
    if ! _does_repo_exist "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"MIXED","layoutPolicy":"PERMISSIVE"},"proxy":{"remoteUrl":"https://repo1.maven.org/maven2/","contentMaxAge":-1,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"maven2-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    # If NXRM2: _get_asset_NXRM2 "${_prefix}-proxy" "junit/junit/4.12/junit-4.12.jar"
    _get_asset "${_prefix}-proxy" "junit/junit/4.12/junit-4.12.jar" "${__TMP%/}/junit-4.12.jar" || return $?

    # If no xxxx-hosted, create it
    if ! _does_repo_exist "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"MIXED","layoutPolicy":"PERMISSIVE"},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"maven2-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    #mvn deploy:deploy-file -DgroupId=junit -DartifactId=junit -Dversion=4.21 -DgeneratePom=true -Dpackaging=jar -DrepositoryId=nexus -Durl=${r_NEXUS_URL}/repository/${_prefix}-hosted -Dfile=${__TMP%/}/junit-4.12.jar
    f_upload_asset "${_prefix}-hosted" -F maven2.groupId=junit -F maven2.artifactId=junit -F maven2.version=4.21 -F maven2.asset1=@${__TMP%/}/junit-4.12.jar -F maven2.asset1.extension=jar

    # If no xxxx-group, create it
    if ! _does_repo_exist "${_prefix}-group"; then
        # Hosted first
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"maven2-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group ("." in groupdId should be changed to "/")
    _get_asset "${_prefix}-group" "org/apache/httpcomponents/httpclient/4.5.12/httpclient-4.5.12.jar" || return $?

    # Another test for get from proxy, then upload to hosted, then get from hosted
    #_get_asset "${_prefix}-proxy" "org/apache/httpcomponents/httpclient/4.5.12/httpclient-4.5.12.jar" "${__TMP%/}/httpclient-4.5.12.jar"
    #_upload_asset "${_prefix}-hosted" -F maven2.groupId=org.apache.httpcomponents -F maven2.artifactId=httpclient -F maven2.version=4.5.12 -F maven2.asset1=@${__TMP%/}/httpclient-4.5.12.jar -F maven2.asset1.extension=jar
    #_get_asset "${_prefix}-hosted" "org/apache/httpcomponents/httpclient/4.5.12/httpclient-4.5.12.jar"
}

function f_setup_pypi() {
    local _prefix="${1:-"pypi"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it
    if ! _does_repo_exist "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://pypi.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"pypi-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    _get_asset "${_prefix}-proxy" "packages/unit/0.2.2/Unit-0.2.2.tar.gz" "${__TMP%/}/Unit-0.2.2.tar.gz" || return $?

    # If no xxxx-hosted, create it
    if ! _does_repo_exist "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"pypi-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    f_upload_asset "${_prefix}-hosted" -F "pypi.asset=@${__TMP%/}/Unit-0.2.2.tar.gz"

    # If no xxxx-group, create it
    if ! _does_repo_exist "${_prefix}-group"; then
        # Hosted first
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"pypi-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    _get_asset "${_prefix}-group" "packages/pyyaml/5.3.1/PyYAML-5.3.1.tar.gz" || return $?
}

function f_setup_npm() {
    local _prefix="${1:-"npm"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it
    if ! _does_repo_exist "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://registry.npmjs.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"npm-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    _get_asset "${_prefix}-proxy" "lodash/-/lodash-4.17.4.tgz" "${__TMP%/}/lodash-4.17.15.tgz" || return $?

    # If no xxxx-hosted, create it
    if ! _does_repo_exist "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"npm-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    f_upload_asset "${_prefix}-hosted" -F "npm.asset=@${__TMP%/}/lodash-4.17.15.tgz"

    # If no xxxx-group, create it
    if ! _does_repo_exist "${_prefix}-group"; then
        # Hosted first
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"npm-group"}],"type":"rpc"}' || return $?
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
    if ! _does_repo_exist "${_prefix}-proxy"; then
        # "httpPort":18078 - 18079
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":18078,"httpsPort":18079,"forceBasicAuth":false,"v1Enabled":true},"proxy":{"remoteUrl":"https://registry-1.docker.io","contentMaxAge":1440,"metadataMaxAge":1440},"dockerProxy":{"indexType":"HUB","cacheForeignLayers":false,"useTrustStoreForIndexAccess":false},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"undefined":[false,false],"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"docker-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    _docker_proxy

    # If no xxxx-hosted, create it
    if ! _does_repo_exist "${_prefix}-hosted"; then
        # Using "httpPort":18081 - 18082,
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":18081,"httpsPort":18082,"forceBasicAuth":true,"v1Enabled":true},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"undefined":[false,false],"recipe":"docker-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    _docker_hosted

    # If no xxxx-group, create it
    if ! _does_repo_exist "${_prefix}-group"; then
        # Using "httpPort":18074 - 18075
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":18084,"httpsPort":18085,"forceBasicAuth":true,"v1Enabled":true},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":false},"group":{"memberNames":["docker-hosted","docker-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"undefined":[false,false],"recipe":"docker-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    _docker_proxy "hello-world" "${r_DOCKER_GROUP}" "18085 18084"
}
function _docker_login() {
    local _host_port="${1}"
    local _backup_ports="${2}"
    local _user="${3:-"${r_ADMIN_USER:-"admin"}"}"
    local _pwd="${4:-"${r_ADMIN_PWD:-"admin123"}"}"
    local _cmd="${5:-"${r_DOCKER_CMD:-"docker"}"}"

    if [ -z "${_cmd}" ] || ! which ${_cmd} &>/dev/null; then
        _log "WARN" "No docker command specified (docker or podman) for $FUNCNAME, so exiting"
        return 0
    fi

    if [ -z "${_host_port}" ] && [ -n "${_backup_ports}" ]; then
        for __p in ${_backup_ports}; do
            nc -vz localhost ${__p} && _host_port="localhost:${__p}" && break
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
    ${_cmd} login ${_host_port} --username ${_user} --password ${_pwd} || return $?
    echo "${_host_port}"
}
function _docker_proxy() {
    local _tag_name="${1:-"alpine:3.7"}"
    local _host_port="${2:-"${r_DOCKER_PROXY}"}"
    local _backup_ports="${3:-"18079 18078"}"
    local _cmd="${4:-"${r_DOCKER_CMD:-"docker"}"}"
    _host_port="$(_docker_login "${_host_port}" "${_backup_ports}")" || return $?

    local _image_name="$(${_cmd} images --format "{{.Repository}}" | grep -w "${_tag_name}")"
    if [ -n "${_image_name}" ]; then
        _log "WARN" "Deleting ${_image_name} (wait for 5 secs)";sleep 5
        ${_cmd} rmi ${_image_name} || return $?
    fi
    _log "DEBUG" "${_cmd} pull ${_host_port}/${_tag_name}"
    ${_cmd} pull ${_host_port}/${_tag_name} || return $?
}
function _docker_hosted() {
    local _tag_name="${1:-"alpine:3.7"}"
    local _host_port="${2:-"${r_DOCKER_HOSTED}"}"
    local _backup_ports="${3:-"18082 18081"}"
    local _cmd="${4:-"${r_DOCKER_CMD:-"docker"}"}"
    _host_port="$(_docker_login "${_host_port}" "${_backup_ports}")" || return $?

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
    if ! _does_repo_exist "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"http://mirror.centos.org/centos/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"yum-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    if which yum &>/dev/null; then
        _nexus_yum_repo "${_prefix}-proxy"
        yum --disablerepo="*" --enablerepo="nexusrepo" install --downloadonly --downloaddir=${__TMP%/} dos2unix || return $?
    else
        _get_asset "${_prefix}-proxy" "7/os/x86_64/Packages/dos2unix-6.0.3-7.el7.x86_64.rpm" "${__TMP%/}/dos2unix-6.0.3-7.el7.x86_64.rpm" || return $?
    fi

    # If no xxxx-hosted, create it
    if ! _does_repo_exist "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"yum":{"repodataDepth":1,"deployPolicy":"PERMISSIVE"},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":false,"writePolicy":"ALLOW"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"yum-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    local _upload_file="$(find ${__TMP%/} -type f -size +1k -name "dos2unix-*.el7.x86_64.rpm" | tail -n1)"
    if [ -s "${_upload_file}" ]; then
        f_upload_asset "${_prefix}-hosted" -F "yum.asset=@${_upload_file}" -F "yum.asset.filename=$(basename ${_upload_file})" -F "yum.directory=/7/os/x86_64/Packages" || return $?
    else
        _log "WARN" "No rpm file for upload test."
    fi
    #curl -u 'admin:admin123' --upload-file /etc/pki/rpm-gpg/RPM-GPG-KEY-pmanager ${r_NEXUS_URL%/}/repository/yum-hosted/RPM-GPG-KEY-pmanager

    # If no xxxx-group, create it
    if ! _does_repo_exist "${_prefix}-group"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"yum-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    _get_asset "${_prefix}-group" "7/os/x86_64/Packages/$(basename ${_upload_file})" || return $?
}
function _nexus_yum_repo() {
    local _repo="${1:-"yum-group"}"
    local _out_file="${2:-"/etc/yum.repos.d/nexus-yum-test.repo"}"
    local _blob_name="${3:-"${r_BLOB_NAME:-"default"}"}"
    local _base_url="${r_NEXUS_URL:-"http://localhost:8081/"}"

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
    if ! _does_repo_exist "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://rubygems.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"rubygems-proxy"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-proxy

    # If no xxxx-hosted, create it
    if ! _does_repo_exist "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"rubygems-hosted"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-hosted

    # If no xxxx-group, create it
    if ! _does_repo_exist "${_prefix}-group"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["gems-hosted","gems-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"rubygems-group"}],"type":"rpc"}' || return $?
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
    if ! _does_repo_exist "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":false,"writePolicy":"ALLOW"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}'
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
    if ! _does_repo_exist "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://conan.bintray.com","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"conan-proxy"}],"type":"rpc"}' || return $?
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
# f_get_and_upload_jars "maven" "junit" "junit" "3.8 4.0 4.1 4.2 4.3 4.4 4.5 4.6 4.7 4.8 4.9 4.10 4.11 4.12"
function f_get_and_upload_jars() {
    local _prefix="${1:-"maven"}"
    local _group_id="$2"
    local _artifact_id="$3"
    local _versions="$4"
    local _base_url="${5:-"${r_NEXUS_URL:-"http://localhost:8081/"}"}"

    for _v in ${_versions}; do
        # TODO: currently only maven / maven2, and doesn't work with non usual filenames
        #local _path="$(echo "${_path_with_VAR}" | sed "s/<VAR>/${_v}/g")"  # junit/junit/<VAR>/junit-<VAR>.jar
        local _path="${_group_id%/}/${_artifact_id%/}/${_v}/${_artifact_id%/}-${_v}.jar"
        local _out_path="${__TMP%/}/$(basename ${_path})"
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
    local _base_url="${4:-"${r_NEXUS_URL:-"http://localhost:8081/"}"}"
    local _user="${5:-"${r_ADMIN_USER:-"admin"}"}"
    local _pwd="${6:-"${r_ADMIN_PWD:-"admin123"}"}"
    if [[ "${_NO_DATA}" =~ ^[yY] ]]; then
        _log "INFO" "_NO_DATA is set so no action."; return 0
    fi
    if [ -d "${_out_path}" ]; then
        _out_path="${_out_path%/}/$(basename ${_path})"
    fi
    curl -sf -D ${__TMP%/}/_proxy_test_header_$$.out -o ${_out_path} -u ${_user}:${_pwd} -k "${_base_url%/}/repository/${_repo%/}/${_path#/}"
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        _log "ERROR" "Failed to get ${_base_url%/}/repository/${_repo%/}/${_path#/} (${_rc})"
        cat ${__TMP%/}/_proxy_test_header_$$.out >&2
        return ${_rc}
    fi
}
# For NXRM2
function _get_asset_NXRM2() {
    local _repo="$1"
    local _path="$2"
    local _out_path="${3:-"/dev/null"}"
    local _base_url="${4:-"${r_NEXUS_URL:-"http://localhost:8081/"}"}"
    local _usr="${4:-${r_ADMIN_USER:-"admin"}}"
    local _pwd="${5-${r_ADMIN_PWD:-"admin123"}}"   # If explicitly empty string, curl command will ask password (= may hang)

    if [[ "${_NO_DATA}" =~ ^[yY] ]]; then
        _log "INFO" "_NO_DATA is set so no action."; return 0
    fi
    curl -sf -D ${__TMP%/}/_proxy_test_header_$$.out -o ${_out_path} -u ${_usr}:${_pwd} -k "${_base_url%/}/content/repository/${_repo%/}/${_path#/}"
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        _log "ERROR" "Failed to get ${_base_url%/}/content/repository/${_repo%/}/${_path#/} (${_rc})"
        cat ${__TMP%/}/_proxy_test_header_$$.out >&2
        return ${_rc}
    fi
}

function f_upload_asset() {
    local _repo="$1"
    local _forms=${@:2} #-F maven2.groupId=junit -F maven2.artifactId=junit -F maven2.version=4.21 -F maven2.asset1=@${__TMP%/}/junit-4.12.jar -F maven2.asset1.extension=jar
    # NOTE: Because _forms takes all arguments except first one, can't assign any other arguments
    local _usr="${r_ADMIN_USER:-"admin"}"
    local _pwd="${r_ADMIN_PWD:-"admin123"}"   # If explicitly empty string, curl command will ask password (= may hang)
    local _base_url="${r_NEXUS_URL:-"http://localhost:8081/"}"
    if [[ "${_NO_DATA}" =~ ^[yY] ]]; then
        _log "INFO" "_NO_DATA is set so no action."; return 0
    fi
    curl -sf -D ${__TMP%/}/_upload_test_header_$$.out -u ${_usr}:${_pwd} -H "accept: application/json" -H "Content-Type: multipart/form-data" -X POST -k "${_base_url%/}/service/rest/v1/components?repository=${_repo}" ${_forms}
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        if grep -qE '^HTTP/1.1 [45]' ${__TMP%/}/_upload_test_header_$$.out; then
            _log "ERROR" "Failed to post to ${_base_url%/}/service/rest/v1/components?repository=${_repo} (${_rc})"
            cat ${__TMP%/}/_upload_test_header_$$.out >&2
            return ${_rc}
        else
            _log "WARN" "Post to ${_base_url%/}/service/rest/v1/components?repository=${_repo} might have been failed (${_rc})"
            cat ${__TMP%/}/_upload_test_header_$$.out >&2
        fi
    fi
}

function _does_repo_exist() {
    local _repo_name="$1"
    # At this moment, not always checking
    find ${__TMP%/}/ -type f -name '_does_repo_exist*.out' -mmin +5 -delete
    if [ ! -s ${__TMP%/}/_does_repo_exist$$.out ]; then
        f_api "/service/rest/v1/repositories" | grep '"name":' > ${__TMP%/}/_does_repo_exist$$.out
    fi
    if [ -n "${_repo_name}" ]; then
        # case insensitive
        grep -iq "\"${_repo_name}\"" ${__TMP%/}/_does_repo_exist$$.out
    fi
}
function _does_blob_exist() {
    local _blob_name="$1"
    # At this moment, not always checking
    find ${__TMP%/}/ -type f -name '_does_blob_exist*.out' -mmin +5 -delete
    if [ ! -s ${__TMP%/}/_does_blob_exist$$.out ]; then
        f_api "/service/rest/beta/blobstores" | grep '"name":' > ${__TMP%/}/_does_blob_exist$$.out
    fi
    if [ -n "${_blob_name}" ]; then
        # case insensitive
        grep -iq "\"${_blob_name}\"" ${__TMP%/}/_does_blob_exist$$.out
    fi
}

function f_apiS() {
    local __doc__="NXRM (not really API but) API wrapper with session"
    local _data="${1}"
    local _method="${2}"
    local _usr="${3:-${r_ADMIN_USER:-"admin"}}"
    local _pwd="${4-${r_ADMIN_PWD:-"admin123"}}"   # Accept an empty password
    local _nexus_url="${5:-${r_NEXUS_URL:-"http://localhost:8081/"}}"

    local _usr_b64="$(_b64_url_enc "${_usr}")"
    local _pwd_b64="$(_b64_url_enc "${_pwd}")"
    local _user_pwd="username=${_usr_b64}&password=${_pwd_b64}"
    [ -n "${_data}" ] && [ -z "${_method}" ] && _method="POST"
    [ -z "${_method}" ] && _method="GET"

    # Mac's /tmp is symlink so without the ending "/", would needs -L but does not work with -delete
    find ${__TMP%/}/ -type f -name '.nxrm_c_*' -mmin +10 -delete
    local _c="${__TMP%/}/.nxrm_c_$$"
    if [ ! -s ${_c} ]; then
        curl -sf -D ${__TMP%/}/_apiS_header_$$.out -b ${_c} -c ${_c} -o/dev/null -k "${_nexus_url%/}/service/rapture/session" -d "${_user_pwd}"
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
        curl -sf -D ${__TMP%/}/_apiS_header_$$.out -b ${_c} -c ${_c} -k "${_nexus_url%/}/service/extdirect" -X ${_method} -H "${_H}"
    else
        curl -sf -D ${__TMP%/}/_apiS_header_$$.out -b ${_c} -c ${_c} -k "${_nexus_url%/}/service/extdirect" -X ${_method} -H "${_H}" -H "${_content_type}" -d ${_data}
    fi > ${__TMP%/}/_apiS_nxrm$$.out
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        cat ${__TMP%/}/_apiS_header_$$.out >&2
        return ${_rc}
    fi
    if ! cat ${__TMP%/}/_apiS_nxrm$$.out | python -m json.tool 2>/dev/null; then
        cat ${__TMP%/}/_apiS_nxrm$$.out
    fi
}
function f_api() {
    local __doc__="NXRM3 API wrapper"
    local _path="${1}"
    local _data="${2}"
    local _method="${3}"
    local _usr="${4:-${r_ADMIN_USER}}"
    local _pwd="${5-${r_ADMIN_PWD}}"   # If explicitly empty string, curl command will ask password (= may hang)
    local _nexus_url="${6:-"${r_NEXUS_URL:-"http://localhost:8081/"}"}"

    local _user_pwd="${_usr}"
    [ -n "${_pwd}" ] && _user_pwd="${_usr}:${_pwd}"
    [ -n "${_data}" ] && [ -z "${_method}" ] && _method="POST"
    [ -z "${_method}" ] && _method="GET"
    # TODO: check if GET and DELETE *can not* use Content-Type json?
    local _content_type="Content-Type: application/json"
    [ "${_data:0:1}" != "{" ] && _content_type="Content-Type: text/plain"

    if [ -z "${_data}" ]; then
        # GET and DELETE *can not* use Content-Type json
        curl -sf -D ${__TMP%/}/_api_header_$$.out -u "${_user_pwd}" -k "${_nexus_url%/}/${_path#/}" -X ${_method}
    else
        curl -sf -D ${__TMP%/}/_api_header_$$.out -u "${_user_pwd}" -k "${_nexus_url%/}/${_path#/}" -X ${_method} -H "${_content_type}" -d "${_data}"
    fi > ${__TMP%/}/f_api_nxrm_$$.out
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        cat ${__TMP%/}/_api_header_$$.out >&2
        return ${_rc}
    fi
    if ! cat ${__TMP%/}/f_api_nxrm_$$.out | python -m json.tool 2>/dev/null; then
        echo -n `cat ${__TMP%/}/f_api_nxrm_$$.out`
        echo ""
    fi
}

function _nexus_docker_run() {
    # TODO: shouldn't use any global variables in a function.
    local _p=""
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

    if [ ! -d "${_WORK_DIR%/}/nexus-data_${r_NEXUS_CONTAINER_NAME%/}/etc/jetty" ]; then
        mkdir -p ${_WORK_DIR%/}/nexus-data_${r_NEXUS_CONTAINER_NAME%/}/etc/jetty || return $?
    else
        _log "INFO" "SonatypeWork: ${_WORK_DIR%/}/nexus-data_${r_NEXUS_CONTAINER_NAME} already exists. Reusing..."
    fi

    if [ ! -s ${_WORK_DIR%/}/nexus-data_${r_NEXUS_CONTAINER_NAME%/}/etc/nexus.properties ]; then
        # default: nexus-args=${jetty.etc}/jetty.xml,${jetty.etc}/jetty-http.xml,${jetty.etc}/jetty-requestlog.xml
        echo 'ssl.etc=${karaf.data}/etc/jetty
nexus-args=${jetty.etc}/jetty.xml,${jetty.etc}/jetty-http.xml,${jetty.etc}/jetty-requestlog.xml,${ssl.etc}/jetty-https.xml
application-port-ssl=8443' > ${_WORK_DIR%/}/nexus-data_${r_NEXUS_CONTAINER_NAME%/}/etc/nexus.properties || return $?

        local _license="${r_NEXUS_LICENSE_FILE}"
        [ -z "${_license}" ] && _license="$(ls -1t ${_WORK_DIR%/}/sonatype*.lic 2>/dev/null | head -n1)"
        [ -n "${_license}" ] && echo "nexus.licenseFile=${_license}" >> ${_WORK_DIR%/}/nexus-data_${r_NEXUS_CONTAINER_NAME%/}/etc/nexus.properties

        [ ! -s "${_WORK_DIR%/}/nexus-data_${r_NEXUS_CONTAINER_NAME%/}/etc/jetty/jetty-https.xml" ] && curl -s -f -L -o "${_WORK_DIR%/}/nexus-data_${r_NEXUS_CONTAINER_NAME%/}/etc/jetty/jetty-https.xml" "https://raw.githubusercontent.com/hajimeo/samples/master/misc/nexus-jetty-https.xml"
        [ ! -s "${_WORK_DIR%/}/nexus-data_${r_NEXUS_CONTAINER_NAME%/}/etc/jetty/keystore.jks" ] && curl -s -f -L -o "${_WORK_DIR%/}/nexus-data_${r_NEXUS_CONTAINER_NAME%/}/etc/jetty/keystore.jks" "https://raw.githubusercontent.com/hajimeo/samples/master/misc/standalone.localdomain.jks"
    fi

    [ -z "${INSTALL4J_ADD_VM_PARAMS}" ] && INSTALL4J_ADD_VM_PARAMS="-Xms1g -Xmx2g -XX:MaxDirectMemorySize=1g"
    docker run -d ${_p} --name=${r_NEXUS_CONTAINER_NAME} --hostname=${r_NEXUS_CONTAINER_NAME}.standalone.localdomain \
        -v ${_WORK_DIR%/}:${_WORK_DIR%/} \
        -v ${_WORK_DIR%/}/nexus-data_${r_NEXUS_CONTAINER_NAME}:/nexus-data \
        -e INSTALL4J_ADD_VM_PARAMS="${INSTALL4J_ADD_VM_PARAMS}" \
        sonatype/nexus3:${r_NEXUS_VERSION}
}


interview() {
    _log "INFO" "Ask a few questions to setup this Nexus.
You can stop this interview anytime by pressing 'Ctrl+c' (except while typing secret/password).
"
    _ask "Would you like to load a saved response file?" "Y" "" "N" "N"
    _isYes && _load_resp

    trap '_cancelInterview' SIGINT
    while true; do
        _questions
        echo "=================================================================="
        _ask "Interview completed.
Would you like to save your response?" "Y"
        if ! _isYes; then
            _ask "Would you like to re-do the interview?" "Y"
            if ! _isYes; then
                _echo "Continuing without saving..."
                break
            fi
        else
            break
        fi
    done
    trap - SIGINT
    _save_resp
}
_questions() {
    if [ -z "${r_DOCKER_CMD}" ]; then
        # I prefer podman, so checking podman first
        if which podman &>/dev/null; then
            r_DOCKER_CMD="podman"
        elif which docker &>/dev/null; then
            r_DOCKER_CMD="docker"
        fi
    fi

    # Ask if install nexus docker container if docker command is available
    if [ -n "${r_DOCKER_CMD}" ]; then
        _ask "Would you like to install Nexus in a docker container?" "Y" "r_NEXUS_INSTALL" "N" "N"
        if _isYes "${r_NEXUS_INSTALL}"; then
            local _nexus_version=""
            _ask "Nexus version" "latest" "r_NEXUS_VERSION" "N" "Y"
            local _ver_num=$(echo "${r_NEXUS_VERSION}" | sed 's/[^0-9]//g')
            _ask "Nexus container name" "nexus${_ver_num}" "r_NEXUS_CONTAINER_NAME" "N" "N"
            if ${r_DOCKER_CMD} ps --format "{{.Names}}" | grep -qE "^${r_NEXUS_CONTAINER_NAME}$"; then
                _ask "Container name '${r_NEXUS_CONTAINER_NAME}' already exists. Would you like to reuse this one?" "Y" "r_NEXUS_START" "N" "N"
                _isYes && r_NEXUS_INSTALL="N"
            fi
            _ask "Nexus license file path if you have:
If empty, it will try finding from ${_WORK_DIR%/}/sonatype*.lic" "" "r_NEXUS_LICENSE_FILE" "N" "N"
            if [ -n "${r_NEXUS_LICENSE_FILE}" ] && [ ! -s "${r_NEXUS_LICENSE_FILE}" ]; then
                while true; do
                    _ask "${r_NEXUS_LICENSE_FILE} does not exist. Would you like to re-type?" "Y"
                    if ! _isYes ; then break; fi
                    _ask "Nexus license file path" "" "r_NEXUS_LICENSE_FILE" "N" "N"
                 done
            fi
        fi

        if _isYes "${r_NEXUS_INSTALL}"; then
            local _port1=""
            for _p in 8081 8181 8082; do
                if ! _pid_by_port "${_p}" &>/dev/null; then
                    _port1=${_p}
                    break
                fi
            done
            local _port2=""
            for _p in 8443 8543 8444; do
                if ! _pid_by_port "${_p}" &>/dev/null; then
                    _port2=${_p}
                    break
                fi
            done
            _ask "Nexus container exposing port1 (for 8081)" "${_port1}" "r_NEXUS_CONTAINER_PORT1" "N" "Y"
            _ask "Nexus container exposing port2 (for 8443)" "${_port2}" "r_NEXUS_CONTAINER_PORT2" "N" "N"
        fi
    fi

    _ask "Nexus base URL" "http://`hostname -f`:${r_NEXUS_CONTAINER_PORT1:-"8081"}/" "r_NEXUS_URL" "N" "Y"
    _ask "Blob store name" "default" "r_BLOB_NAME" "N" "Y"
    _ask "Admin username" "admin" "r_ADMIN_USER" "N" "Y"
    _ask "Admin password" "admin" "r_ADMIN_PWD" "Y" "Y"
    _ask "Formats to setup (comma separated)" "${_REPO_FORMATS}" "r_REPO_FORMATS" "N" "Y"

    ## for f_setup_docker()
    if [ -n "${r_DOCKER_CMD}" ]; then
        #r_DOCKER_PROXY="node-nxrm-ha1.standalone.localdomain:18079"
        #r_DOCKER_HOSTED="node-nxrm-ha1.standalone.localdomain:18082"
        #r_DOCKER_GROUP="node-nxrm-ha1.standalone.localdomain:18085"
        _ask "Docker Command for pulling/pushing sample images" "${r_DOCKER_CMD}" "r_DOCKER_CMD" "N" "N"
        _ask "Docker Proxy repo hostname:port" "$(hostname -f):18079" "r_DOCKER_PROXY" "N" "N"
        _ask "Docker Hosted repo hostname:port" "$(hostname -f):18082" "r_DOCKER_HOSTED" "N" "N"
        _ask "Docker Group repo hostname:port" "$(hostname -f):18085" "r_DOCKER_GROUP" "N" "N"
    fi
}
_cancelInterview() {
    echo ""
    echo ""
    _ask "Before exiting, would you like to save your current responses?" "N"
    if _isYes; then
        _save_resp
    fi
    # To get out from the trap, it seems I need to use exit.
    echo "Exiting ..."
    exit
}

prepare() {
    if [ ! -d "${_UTIL_DIR%/}" ]; then
        mkdir -p "${_UTIL_DIR%/}" || exit $?
    fi
    if [ ! -f "${_UTIL_DIR%/}/utils.sh" ]; then
        if [ ! -f "${_WORK_DIR%/}/utils.sh" ]; then
            curl -s -f -m 3 --retry 0 -L "https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils.sh" -o "${_UTIL_DIR%/}/utils.sh" || return $?
        else
            #_check_update "${_WORK_DIR%/}/utils.sh"
            source "${_WORK_DIR%/}/utils.sh"
            return $?
        fi
    else
        _check_update "${_UTIL_DIR%/}/utils.sh"
    fi
    source "${_UTIL_DIR%/}/utils.sh"
}

main() {
    # If no arguments, at this moment, display usage(), then main()
    if ! ${_AUTO}; then
        interview
        _ask "Interview completed. Would like you like to setup?" "Y" "_would_u_like_2_setup" "N" "Y"
        if ! _isYes; then
            echo 'Bye!'
            exit 0
        fi
    fi

    if _isYes "${r_NEXUS_INSTALL}"; then
        _nexus_docker_run || return $?
    elif _isYes "${r_NEXUS_START}" && [ -n "${r_DOCKER_CMD}" ] && [ -n "${r_NEXUS_CONTAINER_NAME}" ]; then
        ${r_DOCKER_CMD} start ${r_NEXUS_CONTAINER_NAME} || return $?
    fi

    local _base_url="${r_NEXUS_URL:-"http://localhost:8081/"}"
    if ! _wait_url "${_base_url}"; then
        _log "ERROR" "${_base_url} is unreachable"
        return 1
    fi

    if ! _does_blob_exist "${r_BLOB_NAME}"; then
        if [ -s ${__TMP%/}/_does_blob_exist$$.out ]; then
            _log "ERROR" "Blobstore ${r_BLOB_NAME} does not exist."
            return 1
        else
            _log "WARN" "Blobstore ${r_BLOB_NAME} *may* not exist, but keep continuing..."
            sleep 5
        fi
    fi
    for _f in `echo "${r_REPO_FORMATS}" | sed 's/,/\n/g'`; do
        f_setup_${_f}
    done
}

prepare
if [ "$0" = "$BASH_SOURCE" ]; then
    _check_update "" "" "N"
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
                _load_resp "$OPTARG"
                ;;
            v)
                r_NEXUS_VERSION="$OPTARG"
                ;;
        esac
    done

    main
fi