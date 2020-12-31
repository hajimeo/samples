#!/usr/bin/env bash
# BASH script to setup NXRM3 repositories.
# Based on functions in start_hdp.sh from 'samples' and install_sonatype.sh from 'work'.
#
# For local test:
#   _import() { source /var/tmp/share/sonatype/$1; } && export -f _import
#
_DL_URL="${_DL_URL:-"https://raw.githubusercontent.com/hajimeo/samples/master"}"
type _import &>/dev/null || _import() { [ ! -s /tmp/${1}_$$ ] && curl -sf --compressed "${_DL_URL%/}/bash/$1" -o /tmp/${1}_$$; . /tmp/${1}_$$; }

_import "utils.sh"
_import "utils_container.sh"


function usage() {
    local _filename="$(basename $BASH_SOURCE)"
    echo "Main purpose of this script is to create repositories with some sample components.
Also functions in this script can be used for testing downloads and uploads.

DOWNLOADS:
    curl ${_DL_URL%/}/bash/setup_nexus3_repos.sh -o ${_WORK_DIR%/}/sonatype/setup_nexus3_repos.sh

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

    -C [-r /path/to/existing/response-file.resp]
        *DANGER*
        Cleaning/deleting a container and sonatype-work directory for fresh installation.

EXAMPLE COMMANDS:
Start script with interview mode:
    sudo ${_filename}

Using default values and NO interviews:
    sudo ${_filename} -a

Create Nexus 3.24.0 container and setup available formats:
    sudo ${_filename} -v 3.24.0 [-a]

Setup docker repositories only (and populate some data if 'docker' command is available):
    sudo ${_filename} -f docker [-a]

Setup maven,npm repositories only:
    sudo ${_filename} -f maven,npm [-a]

Using previously saved response file and review your answers:
    sudo ${_filename} -r ./my_saved_YYYYMMDDhhmmss.resp

Using previously saved response file and NO interviews:
    sudo ${_filename} -a -r ./my_saved_YYYYMMDDhhmmss.resp

NOTE:
For fresh install with same container name:
    docker rm -f <container>
    sudo mv ${_WORK_DIR%/}/sonatype/<mounting-volume> /tmp/  # or rm -rf

To upgrade, if /nexus-data is a mounted volume, just reuse same response file but with newer Nexus version.
If HA-C, edit nexus.properties for all nodes, then remove 'db' directory from node-2 and node-3.
"
}


## Global variables
_ADMIN_USER="admin"
_ADMIN_PWD="admin123"
_REPO_FORMATS="maven,pypi,npm,nuget,docker,helm,yum,rubygem,conan,conda,cocoapods,bower,go,apt,raw"
## Updatable variables
_NEXUS_URL=${_NEXUS_URL:-"http://localhost:8081/"}
_IQ_CLI_VER="${_IQ_CLI_VER-"1.95.0-01"}"    # If empty, not download CLI jar
_DOCKER_NETWORK_NAME=${_DOCKER_NETWORK_NAME:-"nexus"}
_DOCKER_CONTAINER_SHARE_DIR=${_DOCKER_CONTAINER_SHARE_DIR:-"/var/tmp/share"}
_DOMAIN="${_DOMAIN:-"standalone.localdomain"}"
_IS_NXRM2=${_IS_NXRM2:-"N"}
_NO_DATA=${_NO_DATA:-"N"}
_TID="${_TID:-80}"
## Misc.
_LOG_FILE_PATH="/tmp/setup_nexus3_repos.log"
_TMP="$(mktemp -d)"  # for downloading/uploading assets
## Variables which used by command arguments
_AUTO=false
_DEBUG=false
_CLEAN=false
_RESP_FILE=""


### Repository setup functions ################################################################################
# Eg: r_NEXUS_URL="http://dh1.standalone.localdomain:8081/" f_setup_xxxxx
function f_setup_maven() {
    local _prefix="${1:-"maven"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"MIXED","layoutPolicy":"PERMISSIVE"},"proxy":{"remoteUrl":"https://repo1.maven.org/maven2/","contentMaxAge":-1,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"maven2-proxy"}],"type":"rpc"}' || return $?
        # NOTE: if IQ: Audit and Quarantine is needed to be setup
        #f_iq_quarantine "${_prefix}-proxy"
        # NOTE: com.fasterxml.jackson.core:jackson-databind:2.9.3 should be quarantined if IQ is configured. May need to delete the component first
        #f_get_asset "maven-proxy" "com/fasterxml/jackson/core/jackson-databind/2.9.3/jackson-databind-2.9.3.jar" "test.jar"
        #_get_asset_NXRM2 central "com/fasterxml/jackson/core/jackson-databind/2.9.3/jackson-databind-2.9.3.jar" "test.jar"
    fi
    # add some data for xxxx-proxy
    # If NXRM2: _get_asset_NXRM2 "${_prefix}-proxy" "junit/junit/4.12/junit-4.12.jar"
    f_get_asset "${_prefix}-proxy" "junit/junit/4.12/junit-4.12.jar" "${_TMP%/}/junit-4.12.jar"

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"MIXED","layoutPolicy":"PERMISSIVE"},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"maven2-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    #mvn deploy:deploy-file -DgroupId=junit -DartifactId=junit -Dversion=4.21 -DgeneratePom=true -Dpackaging=jar -DrepositoryId=nexus -Durl=${r_NEXUS_URL}/repository/${_prefix}-hosted -Dfile=${_TMP%/}/junit-4.12.jar
    f_upload_asset "${_prefix}-hosted" -F maven2.groupId=junit -F maven2.artifactId=junit -F maven2.version=4.21 -F maven2.asset1=@${_TMP%/}/junit-4.12.jar -F maven2.asset1.extension=jar

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        # Hosted first
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"maven2-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group ("." in groupdId should be changed to "/")
    f_get_asset "${_prefix}-group" "org/apache/httpcomponents/httpclient/4.5.12/httpclient-4.5.12.jar"
}

function f_setup_pypi() {
    local _prefix="${1:-"pypi"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://pypi.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"pypi-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    f_get_asset "${_prefix}-proxy" "packages/unit/0.2.2/Unit-0.2.2.tar.gz" "${_TMP%/}/Unit-0.2.2.tar.gz"

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"pypi-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    f_upload_asset "${_prefix}-hosted" -F "pypi.asset=@${_TMP%/}/Unit-0.2.2.tar.gz"

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        # Hosted first
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"pypi-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    f_get_asset "${_prefix}-group" "packages/pyyaml/5.3.1/PyYAML-5.3.1.tar.gz"
}

function f_setup_npm() {
    local _prefix="${1:-"npm"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://registry.npmjs.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"npm-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    f_get_asset "${_prefix}-proxy" "lodash/-/lodash-4.17.19.tgz" "${_TMP%/}/lodash-4.17.19.tgz"

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"npm-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    f_upload_asset "${_prefix}-hosted" -F "npm.asset=@${_TMP%/}/lodash-4.17.19.tgz"

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        # Hosted first
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"npm-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    f_get_asset "${_prefix}-group" "grunt/-/grunt-1.1.0.tgz"
}

function f_setup_nuget() {
    local _prefix="${1:-"nuget"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"nugetProxy":{"queryCacheItemMaxAge":3600},"proxy":{"remoteUrl":"https://www.nuget.org/api/v2/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"nuget-proxy"}],"type":"rpc"}' || return $?
    fi
    # Even older version, just creating V3 repo should work
    # TODO: check if HA with curl -u admin:admin123 -X GET http://localhost:8081/service/rest/v1/nodes
    if ! _is_repo_available "${_prefix}-v3-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"nugetProxy":{"queryCacheItemMaxAge":3600},"proxy":{"remoteUrl":"https://api.nuget.org/v3/index.json","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-v3-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"nuget-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    f_get_asset "${_prefix}-v3-proxy" "Test/2.0.1.1" "${_TMP%/}/test.2.0.1.1.nupkg"  # This one may fail on some Nexus version
    f_get_asset "${_prefix}-proxy" "Test/2.0.1.1" "${_TMP%/}/test.2.0.1.1.nupkg"

    # Nexus should have nuget-group and nuget-hosted, so creating only v3 one
    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-v3-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-v3-hosted","format":"","type":"","url":"","online":true,"recipe":"nuget-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    f_upload_asset "${_prefix}-hosted" -F "nuget.asset=@${_TMP%/}/test.2.0.1.1.nupkg"


    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-v3-group"; then
        # Hosted first
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-v3-hosted","'${_prefix}'-v3-proxy"]}},"name":"'${_prefix}'-v3-group","format":"","type":"","url":"","online":true,"recipe":"nuget-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    f_get_asset "${_prefix}-v3-group" "jQuery/3.5.1" "${_TMP%/}/jquery.3.5.1.nupkg"  # this one may fail on some Nexus version
    f_get_asset "${_prefix}-group" "jQuery/3.5.1" "${_TMP%/}/jquery.3.5.1.nupkg"
}

#_NEXUS_URL=http://node3281.standalone.localdomain:8081/ f_setup_docker
function f_setup_docker() {
    local _prefix="${1:-"docker"}"
    local _tag_name="${2:-"alpine:3.7"}"
    local _blob_name="${3:-"${r_BLOB_NAME:-"default"}"}"
    #local _opts="--tls-verify=false"    # TODO: only for podman. need an *easy* way to use http for 'docker'

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        # "httpPort":18178 - 18179
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":18178,"httpsPort":18179,"forceBasicAuth":false,"v1Enabled":true},"proxy":{"remoteUrl":"https://registry-1.docker.io","contentMaxAge":1440,"metadataMaxAge":1440},"dockerProxy":{"indexType":"HUB","cacheForeignLayers":false,"useTrustStoreForIndexAccess":false},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"undefined":[false,false],"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"docker-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    f_populate_docker_proxy

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        # Using "httpPort":18181 - 18182,
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":18181,"httpsPort":18182,"forceBasicAuth":true,"v1Enabled":true},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"undefined":[false,false],"recipe":"docker-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    f_populate_docker_hosted

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        # Using "httpPort":18174 - 18175
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":18184,"httpsPort":18185,"forceBasicAuth":true,"v1Enabled":true},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["docker-hosted","docker-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"undefined":[false,false],"recipe":"docker-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    f_populate_docker_proxy "hello-world" "${r_DOCKER_GROUP}" "18185 18184"
}

function f_populate_docker_proxy() {
    local _tag_name="${1:-"alpine:3.7"}"
    local _host_port="${2:-"${r_DOCKER_PROXY:-"${_NEXUS_URL}"}"}"
    local _backup_ports="${3-"18179 18178"}"
    local _cmd="${4-"${r_DOCKER_CMD}"}"
    [ -z "${_cmd}" ] && _cmd="$(_docker_cmd)"
    [ -z "${_cmd}" ] && return 0    # If no docker command, just exist
    _host_port="$(_docker_login "${_host_port}" "${_backup_ports}" "${r_ADMIN_USER:-"${_ADMIN_USER}"}" "${r_ADMIN_PWD:-"${_ADMIN_PWD}"}")" || return $?

    for _imn in $(${_cmd} images --format "{{.Repository}}" | grep -w "${_tag_name}"); do
        _log "WARN" "Deleting ${_imn} (wait for 5 secs)";sleep 5
        if ! ${_cmd} rmi ${_imn}; then
            _log "WARN" "Deleting ${_imn} failed but keep continuing..."
        fi
    done
    _log "DEBUG" "${_cmd} pull ${_host_port}/${_tag_name}"
    ${_cmd} pull ${_host_port}/${_tag_name} || return $?
}
#ssh -2CNnqTxfg -L18182:localhost:18182 node3250    #ps aux | grep 2CNnqTxfg
#f_populate_docker_hosted "" "localhost:18182"
function f_populate_docker_hosted() {
    local _tag_name="${1:-"alpine:3.7"}"
    local _host_port="${2:-"${r_DOCKER_PROXY:-"${_NEXUS_URL}"}"}"
    local _backup_ports="${3-"18182 18181"}"
    local _cmd="${4-"${r_DOCKER_CMD}"}"
    [ -z "${_cmd}" ] && _cmd="$(_docker_cmd)"
    [ -z "${_cmd}" ] && return 0    # If no docker command, just exist
    _host_port="$(_docker_login "${_host_port}" "${_backup_ports}" "${r_ADMIN_USER:-"${_ADMIN_USER}"}" "${r_ADMIN_PWD:-"${_ADMIN_PWD}"}")" || return $?

    # In _docker_proxy, the image might be already pulled.
    if ! ${_cmd} tag ${_host_port:-"localhost"}/${_tag_name} ${_host_port}/${_tag_name} 2>/dev/null; then
        # Example commands to create layers
        # "FROM alpine:3.7\nCMD echo 'hello world'"
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
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"http://mirror.centos.org/centos/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"yum-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy (Ubuntu has "yum" command)
    if which yum &>/dev/null && [ -d /etc/yum.repos.d ]; then
        f_echo_yum_repo_file "${_prefix}-proxy" > /etc/yum.repos.d/nexus-yum-test.repo
        yum --disablerepo="*" --enablerepo="nexusrepo" install --downloadonly --downloaddir=${_TMP%/} dos2unix
    else
        # NOTE: due to the known limitation, not sure below get works, as yum repo works with anonymous.
        # https://support.sonatype.com/hc/en-us/articles/213464848-Authenticated-Access-to-Nexus-from-Yum-Doesn-t-Work
        f_get_asset "${_prefix}-proxy" "7/os/x86_64/Packages/dos2unix-6.0.3-7.el7.x86_64.rpm" "${_TMP%/}/dos2unix-6.0.3-7.el7.x86_64.rpm"
    fi

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"yum":{"repodataDepth":1,"deployPolicy":"PERMISSIVE"},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"yum-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    local _upload_file="$(find ${_TMP%/} -type f -size +1k -name "dos2unix-*.el7.x86_64.rpm" 2>/dev/null | tail -n1)"
    if [ -s "${_upload_file}" ]; then
        f_upload_asset "${_prefix}-hosted" -F "yum.asset=@${_upload_file}" -F "yum.asset.filename=$(basename ${_upload_file})" -F "yum.directory=/7/os/x86_64/Packages"
    else
        _log "WARN" "No rpm file for upload test."
    fi
    #curl -u 'admin:admin123' --upload-file /etc/pki/rpm-gpg/RPM-GPG-KEY-pmanager ${r_NEXUS_URL%/}/repository/yum-hosted/RPM-GPG-KEY-pmanager

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"yum-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    f_get_asset "${_prefix}-group" "7/os/x86_64/Packages/$(basename ${_upload_file})"
}
function f_echo_yum_repo_file() {
    local _repo="${1:-"yum-group"}"
    local _base_url="${2:-"${r_NEXUS_URL:-"${_NEXUS_URL}"}"}"
    # At this moment, Nexus yum repositories require anonymous, so not modifying the url with "https://admin:admin123@HOST:PORT/repository/..."
    local _repo_url="${_base_url%/}/repository/${_repo}"
echo '[nexusrepo]
name=Nexus Repository
baseurl='${_repo_url%/}'/$releasever/os/$basearch/
enabled=1
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
priority=1'
}

function f_setup_rubygem() {
    local _prefix="${1:-"rubygem"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://rubygems.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"rubygems-proxy"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-proxy

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"rubygems-hosted"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-hosted

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["gems-hosted","gems-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"rubygems-group"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
    fi
    # TODO: add some data for xxxx-group
    #f_get_asset "${_prefix}-group" "7/os/x86_64/Packages/$(basename ${_upload_file})" || return $?
}

function f_setup_helm() {
    local _prefix="${1:-"helm"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://sonatype.github.io/helm3-charts/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"helm-proxy"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-proxy (also not supported with HA-C)
}

function f_setup_bower() {
    local _prefix="${1:-"raw"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"bower":{"rewritePackageUrls":true},"proxy":{"remoteUrl":"https://registry.bower.io","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"bower-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    f_get_asset "${_prefix}-proxy" "/jquery/versions.json" "${_TMP%/}/bowser_jquery_versions.json"
    # TODO: hosted and group
}

function f_setup_conan() {
    local _prefix="${1:-"conan"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"
    # NOTE: If you disabled Anonymous access, then it is needed to enable the Conan Bearer Token Realm (via Administration > Security > Realms):

    # If no xxxx-proxy, create it (NOTE: No HA, but seems to work with HA???)
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://conan.bintray.com","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"conan-proxy"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-proxy
}

function f_setup_conda() {
    local _prefix="${1:-"conda"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"
    # NOTE: If you disabled Anonymous access, then it is needed to enable the Conan Bearer Token Realm (via Administration > Security > Realms):

    # If no xxxx-proxy, create it (NOTE: No HA)
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://repo.continuum.io/pkgs/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"conda-proxy"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-proxy
}

function f_setup_cocoapods() {
    local _prefix="${1:-"cocoapods"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"
    # NOTE: If you disabled Anonymous access, then it is needed to enable the Conan Bearer Token Realm (via Administration > Security > Realms):

    # If no xxxx-proxy, create it (NOTE: No HA, but seems to work with HA???)
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://cdn.cocoapods.org/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"cocoapods-proxy"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-proxy
}

function f_setup_go() {
    local _prefix="${1:-"go"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it (NOTE: No HA support)
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://gonexus.dev/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"go-proxy"}],"type":"rpc"}' || return $?
    fi
    # Workaround for https://issues.sonatype.org/browse/NEXUS-21642
    if ! _is_repo_available "gosum-raw-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"raw":{"contentDisposition":"ATTACHMENT"},"proxy":{"remoteUrl":"https://sum.golang.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"gosum-raw-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"raw-proxy"}],"type":"rpc"}' || return $?
        _log "INFO" "May need to set 'GOSUMDB=\"sum.golang.org ${r_NEXUS_URL:-"${_NEXUS_URL}"}/repository/gosum-raw-proxy\"'"
    fi
    # TODO: add some data for xxxx-proxy
}

function f_setup_apt() {
    local _prefix="${1:-"apt"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it (NOTE: No HA support)
    if ! _is_repo_available "${_prefix}-proxy"; then
        # distribution should be focal, bionic, etc, but it seems any string is OK.
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"apt":{"distribution":"ubuntu","flat":false},"proxy":{"remoteUrl":"http://archive.ubuntu.com/ubuntu/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"apt-proxy"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-proxy
    # TODO: add hosted
}

function f_setup_raw() {
    local _prefix="${1:-"raw"}"
    local _blob_name="${2:-"${r_BLOB_NAME:-"default"}"}"

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-jenkins-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"raw":{"contentDisposition":"ATTACHMENT"},"proxy":{"remoteUrl":"https://updates.jenkins.io/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-jenkins-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"raw-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    #f_get_asset "${_prefix}-jenkins-proxy" "download/plugins/nexus-jenkins-plugin/3.9.20200722-164144.e3a1be0/nexus-jenkins-plugin.hpi"

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}' || return $?
    fi
    dd if=/dev/zero of=${_TMP%/}/test_1k.img bs=1 count=0 seek=1024
    if [ -s "${_TMP%/}/test_1k.img" ]; then
        f_upload_asset "${_prefix}-hosted" -F raw.directory=test -F raw.asset1=@${_TMP%/}/test_1k.img -F raw.asset1.filename=test_1k.img
    fi

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_blob_name}'","strictContentTypeValidation":true},"group":{"memberNames":["raw-hosted"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"raw-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    f_get_asset "${_prefix}-group" "test/test_1k.img"
}


### Nexus related Misc. functions #################################################################
function f_create_file_blobstore() {
    local _blob_name="$1"
    if ! f_apiS '{"action":"coreui_Blobstore","method":"create","data":[{"type":"File","name":"'${_blob_name}'","isQuotaEnabled":false,"attributes":{"file":{"path":"'${_blob_name}'"}}}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out; then
        _log "ERROR" "Blobstore ${_blob_name} does not exist."
        _log "ERROR" "$(cat ${_TMP%/}/f_apiS_last.out)"
        return 1
    fi
    _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
}

function f_create_s3_blobstore() {
    local _blob_name="${1:-"s3-test"}"
    local _bucket="${2:-"apac-support-bucket"}"
    local _region="${3:-"ap-southeast-2"}"
    local _ak="${4:-${_AWS_ACCESS_KEY}}"
    local _sk="${5:-${_AWS_SECRET_KEY}}"
    local _prefix="${6:-$(hostname -s)}"    # cat /etc/machine-id is not perfect if docker container
    # NOTE 3.27 has ',"state":""'
    if ! f_apiS '{"action":"coreui_Blobstore","method":"create","data":[{"type":"S3","name":"'${_blob_name}'","isQuotaEnabled":false,"property_region":"'${_region}'","property_bucket":"'${_bucket}'","property_prefix":"'${_prefix}'","property_expiration":1,"authEnabled":true,"property_accessKeyId":"'${_ak}'","property_secretAccessKey":"'${_sk}'","property_assumeRole":"","property_sessionToken":"","encryptionSettingsEnabled":false,"advancedConnectionSettingsEnabled":false,"attributes":{"s3":{"region":"'${_region}'","bucket":"'${_bucket}'","prefix":"'${_prefix}'","expiration":"2","accessKeyId":"'${_ak}'","secretAccessKey":"'${_sk}'","assumeRole":"","sessionToken":""}}}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out; then
        _log "ERROR" "Blobstore ${_blob_name} does not exist."
        _log "ERROR" "$(cat ${_TMP%/}/f_apiS_last.out)"
        return 1
    fi
    _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    # As an example, creating docker-hosted-s3 repo
    #f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"forceBasicAuth":true,"v1Enabled":true},"storage":{"blobStoreName":"s3-test","strictContentTypeValidation":false,"writePolicy":"ALLOW","latestPolicy":false},"cleanup":{"policyName":[]}},"name":"docker-hosted-s3","format":"","type":"","url":"","online":true,"undefined":[false,false],"recipe":"docker-hosted"}],"type":"rpc"}'
    _log "INFO" "To browse / search:
aws s3 ls s3://${_bucket}/${_prefix}/content/ # --recursive
aws s3api list-objects --bucket ${_bucket} --query \"Contents[?contains(Key, 'f062f002-88f0-4b53-aeca-7324e9609329.properties')]\"
aws s3api get-object-tagging --bucket ${_bucket} --key \"${_prefix}/content/vol-42/chap-31/f062f002-88f0-4b53-aeca-7324e9609329.properties\"
aws s3 cp s3://${_bucket}/${_prefix}/content/vol-42/chap-31/f062f002-88f0-4b53-aeca-7324e9609329.properties -
"
}

function f_iq_quarantine() {
    local _repo_name="$1"
    if [ -n "${_IQ_HOST}" ] && nc -z ${_IQ_HOST} ${_IQ_PORT:-"8070"}; then
        _log "INFO" "Setting up IQ capability ..."
        f_apiS '{"action":"clm_CLM","method":"update","data":[{"enabled":true,"url":"'${_HTTP:-"http"}'://'${_IQ_HOST}':'${_IQ_PORT}'","authenticationType":"USER","username":"admin","password":"admin123","timeoutSeconds":null,"properties":"","showLink":true}],"type":"rpc"}' || return $?
    fi
    # To create IQ: Audit and Quarantine for this repository:
    f_apiS '{"action":"capability_Capability","method":"create","data":[{"id":"NX.coreui.model.Capability-1","typeId":"firewall.audit","notes":"","enabled":true,"properties":{"repository":"'${_repo_name}'","quarantine":"true"}}],"type":"rpc"}' || return $?
    _log "INFO" "IQ: Audit and Quarantine for ${_repo_name} completed."
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
        _get_asset_NXRM2 "$@"
    else
        _get_asset "$@"
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
    local _curl="curl -sf"
    ${_DEBUG} && _curl="curl -fv"
    ${_curl} -D ${_TMP%/}/_proxy_test_header_$$.out -o ${_out_path} -u ${_user}:${_pwd} -k "${_base_url%/}/repository/${_repo%/}/${_path#/}"
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
    local _curl="curl -sf"
    ${_DEBUG} && _curl="curl -fv"
    ${_curl} -D ${_TMP%/}/_proxy_test_header_$$.out -o ${_out_path} -u ${_usr}:${_pwd} -k "${_base_url%/}/content/repositories/${_repo%/}/${_path#/}"
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
    local _curl="curl -sf"
    ${_DEBUG} && _curl="curl -fv"
    ${_curl} -D ${_TMP%/}/_upload_test_header_$$.out -u ${_usr}:${_pwd} -H "accept: application/json" -H "Content-Type: multipart/form-data" -X POST -k "${_base_url%/}/service/rest/v1/components?repository=${_repo}" ${_forms}
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


### Utility/Misc. functions #################################################################
function f_apiS() {
    # NOTE: may require nexus.security.anticsrftoken.enabled=false (NEXUS-23735)
    local __doc__="NXRM (not really API but) API wrapper with session against /service/extdirect"
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
    find ${_TMP%/}/ -type f -name '.nxrm_c_*' -mmin +1 -delete 2>/dev/null
    local _c="${_TMP%/}/.nxrm_c_$$"
    if [ ! -s ${_c} ]; then
        curl -sf -D ${_TMP%/}/_apiS_header_$$.out -b ${_c} -c ${_c} -o ${_TMP%/}/_apiS_$$.out -k "${_nexus_url%/}/service/rapture/session" -d "${_user_pwd}"
        local _rc=$?
        if [ "${_rc}" != "0" ] ; then
            rm -f ${_c}
            return ${_rc}
        fi
    fi
    local _H_sess="NXSESSIONID: $(_sed -nr 's/.+\sNXSESSIONID\s+([0-9a-f]+)/\1/p' ${_c})"
    local _H_anti="NX-ANTI-CSRF-TOKEN: test"
    local _C="Cookie: NX-ANTI-CSRF-TOKEN=test; NXSESSIONID=$(_sed -nr 's/.+\sNXSESSIONID\s+([0-9a-f]+)/\1/p' ${_c})"
    local _content_type="Content-Type: application/json"
    if [ "${_data:0:1}" != "{" ]; then
        _content_type="Content-Type: text/plain"
    elif [[ ! "${_data}" =~ "tid" ]]; then
        _data="${_data%\}},\"tid\":${_TID}}"
        _TID=$(( ${_TID} + 1 ))
    fi

    if [ -z "${_data}" ]; then
        # GET and DELETE *can not* use Content-Type json
        curl -sf -D ${_TMP%/}/_apiS_header_$$.out -k "${_nexus_url%/}/service/extdirect" -X ${_method} -H "${_H_anti}" -H "${_H_sess}" -H "${_C}"
    else
        curl -sf -D ${_TMP%/}/_apiS_header_$$.out -k "${_nexus_url%/}/service/extdirect" -X ${_method} -H "${_H_anti}" -H "${_H_sess}" -H "${_C}" -H "${_content_type}" -d "${_data}"
    fi > ${_TMP%/}/_apiS_nxrm$$.out
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        cat ${_TMP%/}/_apiS_header_$$.out >&2
        rm -f ${_c}
        return ${_rc}
    fi
    if [ "${_method}" == "GET" ]; then
        if ! cat ${_TMP%/}/_apiS_nxrm$$.out | python -m json.tool 2>/dev/null; then
            cat ${_TMP%/}/_apiS_nxrm$$.out
        fi
    else
        _log "DEBUG" "$(cat ${_TMP%/}/_apiS_nxrm$$.out)"
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

    local _curl="curl -sf"
    ${_DEBUG} && _curl="curl -fv"
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
        echo -n `cat ${_TMP%/}/f_api_nxrm_$$.out`
        echo ""
    fi
}

# Create a container which installs python, npm, mvn, nuget, etc.
#usermod -a -G docker $USER (then relogin)
#docker rm -f nexus-client; p_client_container "http://dh1.standalone.localdomain:8081/"
#shellcheck disable=SC2120
function p_client_container() {
    local __doc__="Create / start a docker container to install various client commands. Also calls f_reset_client_configs"
    local _base_url="${1:-"${r_NEXUS_URL:-"${_NEXUS_URL}"}"}"
    local _name="${2:-"nexus-client"}"
    local _centos_ver="${3:-"7.6.1810"}"
    local _cmd="${4:-"${r_DOCKER_CMD:-"docker"}"}"

    local _image_name="${_name}:latest"
    local _existing_id="`${_cmd} images -q ${_image_name}`"
    if [ -n "${_existing_id}" ]; then
        _log "INFO" "Image ${_image_name} (${_existing_id}) already exists. Running / Starting a container..."
    else
        local _build_dir="$(mktemp -d)" || return $?
        local _dockerfile="${_build_dir%/}/Dockerfile"

        # Expecting f_setup_yum and f_setup_docker have been run
        curl -s -f -m 7 --retry 2 "${_DL_URL%/}/docker/DockerFile_Nexus" -o ${_dockerfile} || return $?

        local _os_and_ver="centos:${_centos_ver}"
        # If docker-group or docker-proxy host:port is provided, trying to use it.
        if [ -n "${r_DOCKER_GROUP:-"${r_DOCKER_PROXY}"}" ]; then
            if ! _docker_login "${r_DOCKER_GROUP}" "" "${r_ADMIN_USER:-"${_ADMIN_USER}"}" "${r_ADMIN_PWD:-"${_ADMIN_PWD}"}"; then
                if _docker_login "${r_DOCKER_PROXY}" "" "${r_ADMIN_USER:-"${_ADMIN_USER}"}" "${r_ADMIN_PWD:-"${_ADMIN_PWD}"}"; then
                    _os_and_ver="${r_DOCKER_PROXY}/centos:${_centos_ver}"
                fi
            else
                _os_and_ver="${r_DOCKER_GROUP}/centos:${_centos_ver}"
            fi
        fi
        _sed -i -r "s@^FROM centos.*@FROM ${_os_and_ver}@1" ${_dockerfile} || return $?
        if [ -s $HOME/.ssh/id_rsa ]; then
            local _pkey="`_sed ':a;N;$!ba;s/\n/\\\\\\\n/g' $HOME/.ssh/id_rsa`"
            _sed -i "s@_REPLACE_WITH_YOUR_PRIVATE_KEY_@${_pkey}@1" ${_dockerfile} || return $?
        fi
        _log "DEBUG" "$(cat ${_dockerfile})"

        cd ${_build_dir} || return $?
        _log "INFO" "Building ${_image_name} ... (outputs:${_LOG_FILE_PATH:-"/dev/null"})"
        ${_cmd} build --rm -t ${_image_name} . 2>&1 >>${_LOG_FILE_PATH:-"/dev/null"} || return $?
        cd -
    fi

    if [ -n "${_cmd}" ] && ! ${_cmd} network list --format "{{.Name}}" | grep -q "^${_DOCKER_NETWORK_NAME}$"; then
        _docker_add_network "${_DOCKER_NETWORK_NAME}" "" "${_cmd}" || return $?
    fi

    local _ext_opts="-v /sys/fs/cgroup:/sys/fs/cgroup:ro --privileged=true -v ${_WORK_DIR%/}:${_DOCKER_CONTAINER_SHARE_DIR}"
    [ -n "${_DOCKER_NETWORK_NAME}" ] && _ext_opts="--network=${_DOCKER_NETWORK_NAME} ${_ext_opts}"
    _log "INFO" "Running or Starting '${_name}'"
    # TODO: not right way to use 3rd and 4th arguments.
    _docker_run_or_start "${_name}" "${_ext_opts}" "${_image_name} /sbin/init" "${_cmd}" || return $?
    _container_add_NIC "${_name}" "bridge" "Y" "${_cmd}"

    # Create a test user if hasn't created (testuser:testuser123)
    _container_useradd "${_name}" "testuser" "" "Y" "${_cmd}"

    # Trust default CA certificate
    if [[ "${_base_url}" =~ \.standalone\.localdomain ]] && [ -s "${_WORK_DIR%/}/cert/rootCA_standalone.crt" ]; then
        ${_cmd} cp ${_WORK_DIR%/}/cert/rootCA_standalone.crt ${_name}:/etc/pki/ca-trust/source/anchors/ && \
        ${_cmd} exec -it ${_name} update-ca-trust
    fi

    # Setup clients' config files
    _log "INFO" "Setting up various client commands (outputs:${_LOG_FILE_PATH:-"/dev/null"})"
    f_reset_client_configs "${_name}" "testuser" "${_base_url}"
    _log "INFO" "Completed $FUNCNAME .
To save : docker stop ${_name}; docker commit ${_name} ${_name}
To login: ssh testuser@${_name}"
}

# Setup (reset) client configs against a CentOS container
#f_reset_client_configs "nexus-client" "testuser" "http://dh1.standalone.localdomain:8081/"
function f_reset_client_configs() {
    local _name="${1}"
    local _user="${2:-"$USER"}"
    local _base_url="${3:-"${r_NEXUS_URL:-"${_NEXUS_URL}"}"}"
    local _usr="${4:-"${r_ADMIN_USER:-"${_ADMIN_USER}"}"}"
    local _pwd="${5:-"${r_ADMIN_PWD:-"${_ADMIN_PWD}"}"}"
    local _cmd="${6:-"${r_DOCKER_CMD:-"docker"}"}"

    f_container_iq_cli "${_name}" "${_user}" "${_IQ_CLI_VER}" "${_cmd}"

    # Using Nexus yum repository if available
    local _repo_url="${_base_url%/}/repository/yum-group"
    local _yum_install="yum install -y"
    f_echo_yum_repo_file "yum-group" "${_base_url}" > ${_TMP%/}/nexus-yum-test.repo
    if ${_cmd} cp ${_TMP%/}/nexus-yum-test.repo ${_name}:/etc/yum.repos.d/nexus-yum-test.repo && _is_url_reachable "${_repo_url}"; then
        _yum_install="yum --disablerepo=base --enablerepo=nexusrepo install -y"
    fi
    ${_cmd} exec -it ${_name} bash -c "${_yum_install} epel-release && curl -sL https://rpm.nodesource.com/setup_10.x | bash -;rpm -Uvh https://packages.microsoft.com/config/centos/7/packages-microsoft-prod.rpm;yum install -y centos-release-scl-rh centos-release-scl;${_yum_install} python3 maven nodejs rh-ruby23 rubygems aspnetcore-runtime-3.1 golang" >>${_LOG_FILE_PATH:-"/dev/null"}
    #yum-config-manager --add-repo=https://copr.fedorainfracloud.org/coprs/carlwgeorge/ripgrep/repo/epel-7/carlwgeorge-ripgrep-epel-7.repo && ${_yum_install} ripgrep
    if [ $? -ne 0 ]; then
        _log "ERROR" "installing packages with yum failed. Check ${_LOG_FILE_PATH}"
        return 1
    fi

    # Skopeo (instead of podman) https://github.com/containers/skopeo/blob/master/install.md
    # NOTE: may need Deployment policy = allow redeployment
    # skopeo --debug copy --src-creds=admin:admin123 --dest-creds=admin:admin123 docker://dh1.standalone.localdomain:18082/alpine:3.7 docker://dh1.standalone.localdomain:18082/alpine:test
    ${_cmd} exec -it ${_name} bash -c "curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_7/devel:kubic:libcontainers:stable.repo && yum -y install skopeo" >>${_LOG_FILE_PATH:-"/dev/null"}

    # Using Nexus npm repository if available
    _repo_url="${_base_url%/}/repository/npm-group"
    local _cred="$(python -c "import sys, base64; print(base64.b64encode('${_usr}:${_pwd}'))")"
    echo "strict-ssl=false
registry=${_repo_url%/}
_auth=\"${_cred}\"" > ${_TMP%/}/npmrc
    if ${_cmd} cp ${_TMP%/}/npmrc ${_name}:/root/.npmrc &&
        ${_cmd} cp ${_TMP%/}/npmrc ${_name}:/home/${_user}/.npmrc &&
        ${_cmd} exec -it ${_name} chown ${_user}: /home/${_user}/.npmrc &&
        _is_url_reachable "${_repo_url}";
    then
        ${_cmd} exec -it ${_name} bash -l -c "npm install -g yarn;npm install -g bower" 2>&1 >> ${_LOG_FILE_PATH:-"/dev/null"}
    fi

    # Using Nexus pypi repository if available, also install conan
    _repo_url="${_base_url%/}/repository/pypi-group"
    echo "[distutils]
index-servers =
  nexus-group

[nexus-group]
repository: ${_repo_url%/}
username: ${_usr}
password: ${_pwd}" > ${_TMP%/}/pypirc
    if ${_cmd} cp ${_TMP%/}/pypirc ${_name}:/root/.pypirc &&
        ${_cmd} cp ${_TMP%/}/pypirc ${_name}:/home/${_user}/.pypirc &&
        ${_cmd} exec -it ${_name} chown ${_user}: /home/${_user}/.pypirc &&
        _is_url_reachable "${_repo_url}";
    then
        ${_cmd} exec -it ${_name} bash -l -c "pip3 install conan" 2>&1 >> ${_LOG_FILE_PATH:-"/dev/null"}
    fi

    # Using Nexus rubygem/cocoapods(pod) repository if available (not sure if rubygem-group is supported in some versions, so using proxy)
    _repo_url="${_base_url%/}/repository/rubygem-proxy"
    # @see: https://www.server-world.info/en/note?os=CentOS_7&p=ruby23
    #       Also need git newer than 1.8.8, but https://github.com/iusrepo/git216/issues/5
    ${_cmd} exec -it ${_name} bash -c "yum remove -y git*; yum -y install https://packages.endpoint.com/rhel/7/os/x86_64/endpoint-repo-1.7-1.x86_64.rpm && ${_yum_install} git" 2>&1 >> ${_LOG_FILE_PATH:-"/dev/null"}
    echo '#!/bin/bash
source /opt/rh/rh-ruby23/enable
export X_SCLS="`scl enable rh-ruby23 \"echo $X_SCLS\"`"' > ${_TMP%/}/rh-ruby23.sh
    ${_cmd} cp ${_TMP%/}/rh-ruby23.sh ${_name}:/etc/profile.d/rh-ruby23.sh
    # If rubygem repo is reachable, install cocoapods *first* (Note: as of today, newest cocoapods fails with "Failed to build gem native extension")
    if _is_url_reachable "${_repo_url}"; then
        local _protocol="http"
        local _repo_url_without_http="${_repo_url}"
        if [[ "${_repo_url}" =~ ^(https?)://(.+)$ ]]; then
            _protocol="${BASH_REMATCH[1]}"
            _repo_url_without_http="${BASH_REMATCH[2]}"
        fi
        echo ":verbose: :really
:disable_default_gem_server: true
:sources:
    - ${_protocol}://${_usr}:${_pwd}@${_repo_url_without_http%/}/" > ${_TMP%/}/gemrc
        ${_cmd} cp ${_TMP%/}/gemrc ${_name}:/root/.gemrc && ${_cmd} cp ${_TMP%/}/gemrc ${_name}:/home/${_user}/.gemrc && ${_cmd} exec -it ${_name} chown ${_user}: /home/${_user}/.gemrc;
    fi
    ${_cmd} exec -it ${_name} bash -l -c "gem install cocoapods -v 1.8.4" 2>&1 >> ${_LOG_FILE_PATH:-"/dev/null"}
    # Need Xcode on Mac?: https://download.developer.apple.com/Developer_Tools/Xcode_10.3/Xcode_10.3.xip (or https://developer.apple.com/download/more/)
    curl -s -f -o ${_TMP%/}/cocoapods-test.tgz -L https://github.com/hajimeo/samples/raw/master/misc/cocoapods-test.tgz && \
    ${_cmd} cp ${_TMP%/}/cocoapods-test.tgz ${_name}:/home/${_user}/cocoapods-test.tgz && \
    ${_cmd} exec -it ${_name} chown ${_user}: /home/${_user}/cocoapods-test.tgz
    # TODO: cocoapods is installed but not configured properly
    #https://raw.githubusercontent.com/hajimeo/samples/master/misc/cocoapods-Podfile
    # (probably) how to retry pod install: cd $HOME/cocoapods-test && rm -rf $HOME/Library/Caches Pods Podfile.lock cocoapods-test.xcworkspace

    # If repo is reachable, setup GOPROXY env
    _repo_url="${_base_url%/}/repository/go-proxy"
    if _is_url_reachable "${_repo_url}"; then
        #local _protocol="http"
        #local _repo_url_without_http="${_repo_url}"
        #if [[ "${_repo_url}" =~ ^(https?)://(.+)$ ]]; then
        #    _protocol="${BASH_REMATCH[1]}"
        #    _repo_url_without_http="${BASH_REMATCH[2]}"
        #fi
        #GOPROXY=${_protocol}://${_usr}:${_pwd}@${_repo_url_without_http%/}
        echo "export GO111MODULE=on
export GOPROXY=${_repo_url}" > ${_TMP%/}/go-proxy.sh
        # Or: go env -w GOPROXY=${_repo_url}
        ${_cmd} cp ${_TMP%/}/go-proxy.sh ${_name}:/etc/profile.d/go-proxy.sh
    fi

    # Install Conda, and if repo is reachable, setup conda/anaconda/miniconda env
    curl -o ${_TMP%/}/Miniconda3-latest-Linux-x86_64.sh --compressed https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh &&
        ${_cmd} cp ${_TMP%/}/Miniconda3-latest-Linux-x86_64.sh ${_name}:/home/${_user}/Miniconda3-latest-Linux-x86_64.sh && \
        ${_cmd} exec -it ${_name} chown ${_user}: /home/${_user}/Miniconda3-latest-Linux-x86_64.sh &&
        ${_cmd} exec -it ${_name} -u ${_user} bash /home/${_user}/Miniconda3-latest-Linux-x86_64.sh -b -p /home/${_user}/miniconda3 &&
        ${_cmd} exec -it ${_name} -u ${_user} bash -c "mkdir /home/${_user}/bin; ln -s /home/${_user}/miniconda3/bin/conda /home/${_user}/bin/conda"
    _repo_url="${_base_url%/}/repository/conda-proxy"
    if _is_url_reachable "${_repo_url}"; then
        #local _pwd_encoded="$(python -c \"import sys, urllib as ul; print(ul.quote('${_pwd}'))\")"
        echo "channels:
  - ${_repo_url%/}
  - defaults" > ${_TMP%/}/condarc
        ${_cmd} cp ${_TMP%/}/condarc ${_name}:/home/${_user}/.condarc && ${_cmd} exec -it ${_name} chown ${_user}: /home/${_user}/.condarc
    fi

    # Regardless of repo availability, setup helm
    curl -fsSL -o ${_TMP%/}/get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
    if [ -s ${_TMP%/}/get_helm.sh ]; then
        ${_cmd} cp ${_TMP%/}/get_helm.sh ${_name}:/home/ && \
        ${_cmd} exec -it ${_name} chown -R ${_user}: /home/${_user}/get_helm.sh && \
        ${_cmd} exec -it -u ${_user} ${_name} /home/${_user}/get_helm.sh
    fi

    sed -i -e "s@_REPLACE_MAVEN_USERNAME_@${_usr}@1" -e "s@_REPLACE_MAVEN_USER_PWD_@${_pwd}@1" -e "s@_REPLACE_MAVEN_REPO_URL_@${_repo_url%/}/@1" ${_TMP%/}/settings.xml && \
    ${_cmd} exec -it ${_name} bash -l -c '_f=/home/'${_user}'/.m2/settings.xml; [ -s ${_f} ] && cat ${_f} > ${_f}.bak; mkdir /home/'${_user}'/.m2 &>/dev/null' && \
    ${_cmd} cp ${_TMP%/}/settings.xml ${_name}:/home/${_user}/.m2/settings.xml && \
    ${_cmd} exec -it ${_name} chown -R ${_user}: /home/${_user}/.m2

    # Using Nexus maven repository if available
    _repo_url="${_base_url%/}/repository/maven-group"
    curl -s -f -o ${_TMP%/}/settings.xml -L ${_DL_URL%/}/misc/m2_settings.tmpl.xml && \
    sed -i -e "s@_REPLACE_MAVEN_USERNAME_@${_usr}@1" -e "s@_REPLACE_MAVEN_USER_PWD_@${_pwd}@1" -e "s@_REPLACE_MAVEN_REPO_URL_@${_repo_url%/}/@1" ${_TMP%/}/settings.xml && \
    ${_cmd} exec -it ${_name} bash -l -c '_f=/home/'${_user}'/.m2/settings.xml; [ -s ${_f} ] && cat ${_f} > ${_f}.bak; mkdir /home/'${_user}'/.m2 &>/dev/null' && \
    ${_cmd} cp ${_TMP%/}/settings.xml ${_name}:/home/${_user}/.m2/settings.xml && \
    ${_cmd} exec -it ${_name} chown -R ${_user}: /home/${_user}/.m2
}

function f_container_iq_cli() {
    local _name="${1}"
    local _user="${2:-"$USER"}"
    local _iq_cli_ver="${3:-"${_IQ_CLI_VER}"}"
    local _cmd="${4:-"${r_DOCKER_CMD:-"docker"}"}"
    [ -z "${_iq_cli_ver}" ] && return 99
    ${_cmd} exec -d ${_name} bash -c '_f=/home/'${_user}'/nexus-iq-cli-'${_iq_cli_ver}'.jar; [ ! -s "${_f}" ] && curl -sf -L "https://download.sonatype.com/clm/scanner/nexus-iq-cli-'${_iq_cli_ver}'.jar" -o "${_f}" && chown '${_user}': ${_f}'
}

# Set admin password after initial installation. If no 'admin.password' file, no error message and silently fail.
function f_nexus_admin_pwd() {
    local _container_name="${1:-"${r_NEXUS_CONTAINER_NAME_1:-"${r_NEXUS_CONTAINER_NAME}"}"}"
    local _new_pwd="${2:-"${r_ADMIN_PWD:-"${_ADMIN_PWD}"}"}"
    local _current_pwd="${3}"
    [ -z "${_container_name}" ] && return 110
    [ -z "${_current_pwd}" ] && _current_pwd="$(docker exec -ti ${_container_name} cat /opt/sonatype/sonatype-work/nexus3/admin.password | tr -cd "[:print:]")"
    [ -z "${_current_pwd}" ] && _current_pwd="$(docker exec -ti ${_container_name} cat /nexus-data/admin.password | tr -cd "[:print:]")"
    [ -z "${_current_pwd}" ] && return 112
    f_api "/service/rest/beta/security/users/admin/change-password" "${_new_pwd}" "PUT" "admin" "${_current_pwd}"
}

# Create a test user and test role
function f_nexus_testuser() {
    f_apiS '{"action":"coreui_Role","method":"create","data":[{"version":"","source":"default","id":"test-role","name":"testRole","description":"test role","privileges":["nx-repository-view-*-*-*","nx-usertoken-current"],"roles":[]}],"type":"rpc"}'
    f_apiS '{"action":"coreui_User","method":"create","data":[{"userId":"testuser","version":"","firstName":"test","lastName":"user","email":"testuser@example.com","status":"active","roles":["test-role"],"password":"testuser"}],"type":"rpc"}'
}

function f_nexus_https_config() {
    local _mount="${1}"
    local _ca_pem="${2}"

    _upsert ${_mount%/}/etc/nexus.properties "ssl.etc" "\${karaf.data}/etc/jetty" || return $?
    _upsert ${_mount%/}/etc/nexus.properties "nexus-args" "\${jetty.etc}/jetty.xml,\${jetty.etc}/jetty-http.xml,\${jetty.etc}/jetty-requestlog.xml,\${ssl.etc}/jetty-https.xml" || return $?
    _upsert ${_mount%/}/etc/nexus.properties "application-port-ssl" "8443" || return $?

    if [ ! -d "${_mount%/}/etc/jetty" ]; then
        # Should change the permission/ownership?
        mkdir -p "${_mount%/}/etc/jetty" || return $?
    fi
    if [ ! -s "${_mount%/}/etc/jetty/jetty-https.xml" ]; then
        curl -s -f -L -o "${_mount%/}/etc/jetty/jetty-https.xml" "${_DL_URL%/}/misc/nexus-jetty-https.xml" || return $?
    fi
    if [ ! -s "${_mount%/}/etc/jetty/keystore.jks" ]; then
        curl -s -f -L -o "${_mount%/}/etc/jetty/keystore.jks" "${_DL_URL%/}/misc/standalone.localdomain.jks" || return $?
    fi

    _trust_ca "${_ca_pem}" || return $?
    _log "DEBUG" "HTTPS configured against config files under ${_mount}"
}

function f_nexus_ha_config() {
    local _mount="$1"
    _upsert ${_mount%/}/etc/nexus.properties "nexus.clustered" "true" || return $?
    _upsert ${_mount%/}/etc/nexus.properties "nexus.log.cluster.enabled" "false" || return $?
    _upsert ${_mount%/}/etc/nexus.properties "nexus.hazelcast.discovery.isEnabled" "false" || return $?
    [ -f "${_mount%/}/etc/fabric/hazelcast-network.xml" ] && mv -f ${_mount%/}/etc/fabric/hazelcast-network.xml{,bak}
    [ ! -d "${_mount%/}/etc/fabric" ] && mkdir -p "${_mount%/}/etc/fabric"
    curl -s -f -m 7 --retry 2 -L "${_DL_URL%/}/misc/hazelcast-network.tmpl.xml" -o "${_mount%/}/etc/fabric/hazelcast-network.xml" || return $?
    for _i in {1..3}; do
        local _tmp_v_name="r_NEXUS_CONTAINER_NAME_${_i}"
        _sed -i "0,/<member>%HA_NODE_/ s/<member>%HA_NODE_.%<\/member>/<member>${!_tmp_v_name}.${_DOMAIN#.}<\/member>/" "${_mount%/}/etc/fabric/hazelcast-network.xml" || return $?
    done
    _log "DEBUG" "HA-C configured against config files under ${_mount}"
}

function f_nexus_mount_volume() {
    local _mount="$1"
    local _v=""
    if [ -n "${_mount}" ]; then
        _v="${_v% } -v ${_mount%/}:/nexus-data"
        if _isYes "${r_NEXUS_INSTALL_HAC}" && [ -n "${r_NEXUS_MOUNT_DIR_SHARED}" ]; then
            if [ ! -d "${r_NEXUS_MOUNT_DIR_SHARED}" ]; then
                mkdir -m 777 -p ${r_NEXUS_MOUNT_DIR_SHARED%/} || return $?
            fi
            _v="${_v% } -v ${r_NEXUS_MOUNT_DIR_SHARED%/}:/nexus-data/blobs"
        fi
    fi
    echo "${_v}"
}

#    if _isYes "${r_NEXUS_MOUNT}"; then
function f_nexus_init_properties() {
    local _sonatype_work="$1"
    [ -z "${_sonatype_work}" ] && return 0  # Nothing to do

    if [ ! -d "${_sonatype_work%/}/etc/jetty" ]; then
        mkdir -p ${_sonatype_work%/}/etc/jetty || return $?
        chmod -R a+w ${_sonatype_work%/}
    else
        _log "INFO" "Mount directory:${_sonatype_work%/} already exists. Reusing..."
    fi

    # If the file exists, at this moment, not adding misc. nexus properties
    if [ ! -s "${_sonatype_work%/}/etc/nexus.properties" ]; then
        echo 'nexus.onboarding.enabled=false
nexus.scripts.allowCreation=true' > ${_sonatype_work%/}/etc/nexus.properties || return $?
    fi

    # HTTPS/SSL/TLS setup
    f_nexus_https_config "${_sonatype_work%/}" || return $?
    # HA-C related setup
    if _isYes "${r_NEXUS_INSTALL_HAC}"; then
        f_nexus_ha_config "${_sonatype_work%/}" || return $?
    fi

    # A license file in local
    local _license="${r_NEXUS_LICENSE_FILE}"
    [ -z "${_license}" ] && _license="$(ls -1t ${_WORK_DIR%/}/sonatype/sonatype-*.lic 2>/dev/null | head -n1)"
    if [ -s "${_license}" ]; then
        [ -d "${_DOCKER_CONTAINER_SHARE_DIR}" ] && cp -f "${_license}" "${_DOCKER_CONTAINER_SHARE_DIR%/}/sonatype/"
        _upsert ${_sonatype_work%/}/etc/nexus.properties "nexus.licenseFile" "${_DOCKER_CONTAINER_SHARE_DIR%/}/sonatype/$(basename "${_license}")" || return $?
    elif _isYes "${r_NEXUS_INSTALL_HAC}"; then
        _log "ERROR" "HA-C is requested but no license."
        return 1
    fi
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
    [ -z "${r_DOCKER_CMD}" ] && r_DOCKER_CMD="$(_docker_cmd)"
    [ -z "${_cmd}" ] && return 0    # If no docker command, just exist

    # Ask if install nexus docker container if docker command is available
    if [ -n "${r_DOCKER_CMD}" ]; then
        _ask "Would you like to install Nexus in a docker container?" "Y" "r_NEXUS_INSTALL" "N" "N"
        if _isYes "${r_NEXUS_INSTALL}"; then
            echo "NOTE: sudo password may be required."
            _ask "Nexus version" "latest" "r_NEXUS_VERSION" "N" "Y"
            local _ver_num=$(echo "${r_NEXUS_VERSION}" | sed 's/[^0-9]//g')
            if [ "`uname`" = "Darwin" ]; then
                # TODO: Mac's docker containers do not look like able to communicate each other.
                r_NEXUS_INSTALL_HAC=N
            else
                _ask "Would you like to build HA-C?" "N" "r_NEXUS_INSTALL_HAC" "N" "N"
            fi
            if _isYes "${r_NEXUS_INSTALL_HAC}"; then
                echo "NOTE: You may also need to set up a reverse proxy."
                # NOTE: mounting a volume to sonatype-work is mandatory for HA-C
                r_NEXUS_MOUNT="Y"
                for _i in {1..3}; do
                    _ask "Nexus container name ${_i}" "nexus${_ver_num}-${_i}" "r_NEXUS_CONTAINER_NAME_${_i}" "N" "N" "_is_container_name"
                    local _tmp_v_name="r_NEXUS_CONTAINER_NAME_${_i}"
                    _ask "Mount to container:/nexus-data" "${_WORK_DIR%/}/sonatype/nexus-data_${!_tmp_v_name}" "r_NEXUS_MOUNT_DIR_${_i}" "N" "Y" "_is_existed"
                done
                _ask "Mount path for shared blobstore" "${_WORK_DIR%/}/sonatype/nexus-data_nexus${_ver_num}_shared_blobs" "r_NEXUS_MOUNT_DIR_SHARED" "N" "Y" "_is_existed"
                _ask "Would you like to start a Socks proxy (if you do not have a reverse proxy)" "N" "r_SOCKS_PROXY"
                if _isYes "${r_SOCKS_PROXY}"; then
                    _ask "Socks proxy port" "48484" "r_SOCKS_PROXY_PORT"
                fi
            else
                _ask "Nexus container name" "nexus${_ver_num}" "r_NEXUS_CONTAINER_NAME" "N" "N" "_is_container_name"
                _ask "Would you like to mount SonatypeWork directory?" "Y" "r_NEXUS_MOUNT" "N" "N"
                if _isYes "${r_NEXUS_MOUNT}"; then
                    _ask "Mount to container:/nexus-data" "${_WORK_DIR%/}/sonatype/nexus-data_${r_NEXUS_CONTAINER_NAME%/}" "r_NEXUS_MOUNT_DIR" "N" "Y" "_is_existed"
                fi
                _ask "Nexus container exposing port for 8081 ('0' to disable docker port forward)" "8081" "r_NEXUS_CONTAINER_PORT1" "N" "Y" "_is_port_available"
                if [ -n "${r_NEXUS_CONTAINER_PORT1}" ] && [ "${r_NEXUS_CONTAINER_PORT1}" -gt 0 ]; then
                    _ask "Nexus container exposing port for 8443 (HTTPS)" "8443" "r_NEXUS_CONTAINER_PORT2" "N" "N" "_is_port_available"
                fi
            fi
            _ask "Nexus license file path if you have:
If empty, it will try finding from ${_WORK_DIR%/}/sonatype/sonatype-*.lic" "" "r_NEXUS_LICENSE_FILE" "N" "N" "_is_license_path"
        fi
        _ask "Would you like to create another container with python, npm, mvn etc. client commands?" "N" "r_NEXUS_CLIENT_INSTALL" "N" "N"
    fi

    if _isYes "${r_NEXUS_INSTALL}"; then
        if _isYes "${r_NEXUS_INSTALL_HAC}"; then
            _ask "Nexus base URL (normally reverse proxy)" "http://${r_NEXUS_CONTAINER_NAME_1}.${_DOMAIN#.}:8081/" "r_NEXUS_URL" "N" "Y"
        else
            if [ -z "${r_NEXUS_CONTAINER_PORT1}" ] || [ "${r_NEXUS_CONTAINER_PORT1}" -gt 0 ]; then
                _ask "Nexus base URL" "http://localhost:${r_NEXUS_CONTAINER_PORT1:-"8081"}/" "r_NEXUS_URL" "N" "Y"
            elif [ -n "${r_NEXUS_CONTAINER_NAME}" ]; then
                _ask "Nexus base URL" "http://${r_NEXUS_CONTAINER_NAME}.${_DOMAIN#.}:8081/" "r_NEXUS_URL" "N" "Y"
            else
                _ask "Nexus base URL" "" "r_NEXUS_URL" "N" "Y"
            fi
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
    if [ -n "${r_DOCKER_CMD}" ] && [[ "${r_REPO_FORMATS}" =~ docker ]]; then
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
function questions_cleanup() {
    local _clean_cmds_file="${_TMP%/}/clean_cmds.sh"
    > ${_clean_cmds_file} || return $?
    if [ -n "${r_NEXUS_CONTAINER_NAME}" ]; then
        _questions_cleanup_inner "${r_NEXUS_CONTAINER_NAME}" "${r_NEXUS_MOUNT_DIR}" "${_clean_cmds_file}"
    else
        for _i in {1..3}; do
            local _v_name="r_NEXUS_CONTAINER_NAME_${_i}"
            local _v_name_m="r_NEXUS_MOUNT_DIR_${_i}"
            _questions_cleanup_inner "${!_v_name}" "${!_v_name_m}" "${_clean_cmds_file}"
        done
    fi
    # Only if the mount path is under ${_WORK_DIR%/}/sonatype to be safe.
    if [ -n "${r_NEXUS_MOUNT_DIR_SHARED}" ] && [ -n "${_WORK_DIR%/}" ] && [[ "${r_NEXUS_MOUNT_DIR_SHARED}" =~ ^${_WORK_DIR%/}/sonatype ]]; then
        _questions_cleanup_inner_inner "sudo rm -rf ${r_NEXUS_MOUNT_DIR_SHARED}" "${_clean_cmds_file}"
    fi
    echo "=== Commands which will be run: ==================================="
    cat ${_clean_cmds_file} || return $?
    echo "==================================================================="
    if ! ${_AUTO}; then
        _ask "Are you sure to execute above? ('sudo' password may be asked)" "N"
        if ! _isYes; then
            echo "Aborting..."
            return 0
        fi
    else
        sleep 5
    fi
    [ -s "${_clean_cmds_file}" ] && bash -x ${_clean_cmds_file}
}
function _questions_cleanup_inner() {
    local _name="$1"
    local _mount="$2"
    local _tmp_file="$3"
    if [ -n "${_name}" ]; then
        _questions_cleanup_inner_inner "docker rm -f ${_name}" "${_tmp_file}"
    fi
    # Only if the mount path is under _WORK_DIR to be safe.
    if [ -n "${_mount}" ] && [ -n "${_WORK_DIR%/}" ] && [[ "${_mount}" =~ ^${_WORK_DIR%/}/sonatype ]]; then
        _questions_cleanup_inner_inner "sudo rm -rf ${_mount}" "${_tmp_file}"
    fi
}
function _questions_cleanup_inner_inner() {
    local _cmd="$1"
    local _tmp_file="$2"
    if ! ${_AUTO}; then
        _ask "Would you like to run '${_cmd}'" "N"
        _isYes && echo "${_cmd}" >> ${_tmp_file}
    else
        echo "${_cmd}" >> ${_tmp_file}
    fi
}


### Validation functions (NOTE: needs to start with _is because of _ask()) #######################################
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
        _license="$(ls -1t ${_WORK_DIR%/}/sonatype/sonatype-*.lic 2>/dev/null | head -n1)"
        if [ -z "${_license}" ]; then
            echo "HA-C is requested but no license with 'ls ${_WORK_DIR%/}/sonatype/sonatype-*.lic'." >&2
            return 1
        fi
    fi
}
function _is_url_reachable() {
    # As I'm checking the reachability, not using -f
    if [ -n "$1" ] && ! curl -s -I -L -k -m1 --retry 0 "$1" &>/dev/null; then
        echo "$1 is not reachable." >&2
        return 1
    fi
}
function _is_port_available() {
    if [ -n "$1" ] && nc -w1 -z localhost $1 2>/dev/null; then
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
# NOTE: Above  can't be moved into utils.sh as it might be used in _ask


### Main #######################################################################################################
main() {
    # Clear the log file if not empty
    [ -s "${_LOG_FILE_PATH}" ] && gzip -S "_$(date +'%Y%m%d%H%M%S').gz" "${_LOG_FILE_PATH}" &>/dev/null
    [ -n "${_LOG_FILE_PATH}" ] && touch ${_LOG_FILE_PATH} && chmod a+w ${_LOG_FILE_PATH}
    # Just in case, creating the work directory
    [ -n "${_WORK_DIR}" ] && [ ! -d "${_WORK_DIR}/sonatype" ] && mkdir -p -m 777 ${_WORK_DIR}/sonatype

    # Checking requirements (so far only a few commands)
    if [ "`uname`" = "Darwin" ]; then
        if which gsed &>/dev/null && which ggrep &>/dev/null; then
            _log "DEBUG" "gsed and ggrep are available."
        else
            _log "ERROR" "gsed and ggrep are required (brew install gnu-sed ggrep)"
            return 1
        fi
    fi

    if ! ${_AUTO}; then
        _log "DEBUG" "_check_update $BASH_SOURCE with force:N"
        _check_update "$BASH_SOURCE" "" "N"
    fi

    # If _RESP_FILE is popurated by -r xxxxx.resp, load it
    if [ -s "${_RESP_FILE}" ];then
        _load_resp "${_RESP_FILE}"
    elif ! ${_AUTO}; then
        _ask "Would you like to load your response file?" "Y" "" "N" "N"
        _isYes && _load_resp
    fi
    # Command line arguments are stronger than response file
    [ -n "${_REPO_FORMATS_FROM_ARGS}" ] && r_REPO_FORMATS="${_REPO_FORMATS_FROM_ARGS}"
    [ -n "${_NEXUS_VERSION_FROM_ARGS}" ] && r_NEXUS_VERSION="${_NEXUS_VERSION_FROM_ARGS}"

    if ${_CLEAN}; then
        _log "WARN" "CLEAN-UP (DELETE) mode is selected."
        questions_cleanup
        return $?
    fi
    if ! ${_AUTO}; then
        interview
        _ask "Interview completed. Would like you like to setup?" "Y" "" "N" "N"
        if ! _isYes; then
            echo 'Bye!'
            return
        fi
    fi

    if _isYes "${r_NEXUS_INSTALL}"; then
        echo "NOTE: If 'password' is asked, please type 'sudo' password." >&2
        sudo echo "Starting Nexus installation..." >&2
        # TODO: Mac's docker doesn't work well with extra network interface (or I do not know how to configure)
        if [ "`uname`" = "Darwin" ]; then
            unset _DOCKER_NETWORK_NAME
        else
            _docker_add_network "${_DOCKER_NETWORK_NAME}" "" "${r_DOCKER_CMD}" || return $?
        fi

        if _isYes "${r_NEXUS_INSTALL_HAC}"; then
            local _ext_opts=""
            if [ -n "${_DOCKER_NETWORK_NAME}" ]; then
                _ext_opts="--network=${_DOCKER_NETWORK_NAME}"
                local _ip_1="$(_container_available_ip "${r_NEXUS_CONTAINER_NAME_1}.${_DOMAIN#.}" "/etc/hosts")" || return $?
                local _ip_2="$(_container_available_ip "${r_NEXUS_CONTAINER_NAME_2}.${_DOMAIN#.}" "/etc/hosts")" || return $?
                local _ip_3="$(_container_available_ip "${r_NEXUS_CONTAINER_NAME_3}.${_DOMAIN#.}" "/etc/hosts")" || return $?
                _ext_opts="${_ext_opts} --add-host ${r_NEXUS_CONTAINER_NAME_1}.${_DOMAIN#.}:${_ip_1}"
                _ext_opts="${_ext_opts} --add-host ${r_NEXUS_CONTAINER_NAME_2}.${_DOMAIN#.}:${_ip_2}"
                _ext_opts="${_ext_opts} --add-host ${r_NEXUS_CONTAINER_NAME_3}.${_DOMAIN#.}:${_ip_3}"
                # TODO: it should exclude own host:ip, otherwise, container's hosts file has two lines for own host:ip
                _log "DEBUG" "_add_hosts: ${_ext_opts}"
            fi

            for _i in {1..3}; do
                local _v_name="r_NEXUS_CONTAINER_NAME_${_i}"
                local _v_name_m="r_NEXUS_MOUNT_DIR_${_i}"
                local _v_name_ip="_ip_${_i}"
                local _tmp_ext_opts="${_ext_opts}"
                _tmp_ext_opts="${_tmp_ext_opts} -v ${_WORK_DIR%/}:${_DOCKER_CONTAINER_SHARE_DIR}"
                if _isYes "${r_NEXUS_MOUNT}"; then
                    _tmp_ext_opts="${_tmp_ext_opts} $(f_nexus_mount_volume "${!_v_name_m}")" || return $?
                    f_nexus_init_properties "${!_v_name_m}" || return $?
                fi
                [ -n "${!_v_name_ip}" ] && _tmp_ext_opts="${_tmp_ext_opts} --ip=${!_v_name_ip}"
                _docker_run_or_start "${!_v_name}" "${_tmp_ext_opts}" "sonatype/nexus3:${r_NEXUS_VERSION:-"latest"}" "${r_DOCKER_CMD}" || return $?
                if [ "${!_v_name}" == "${r_NEXUS_CONTAINER_NAME_1}" ]; then
                    _log "INFO" "Waiting for ${r_NEXUS_CONTAINER_NAME_1} started ..."
                    # If HA-C, needs to wait the first node starts (TODO: what if not 8081?)
                    if ! _wait_url "http://${!_v_name}.${_DOMAIN#.}:8081/"; then
                        _log "ERROR" "${!_v_name}.${_DOMAIN#.} is unreachable"
                        return 1
                    fi
                fi
            done
        else
            local _tmp_ext_opts="-v ${_WORK_DIR%/}:${_DOCKER_CONTAINER_SHARE_DIR}"
            # Port forwarding for Nexus Single Node (obviously can't do same for HA as port will conflict)
            if [ -n "${r_NEXUS_CONTAINER_PORT1}" ] && [ "${r_NEXUS_CONTAINER_PORT1}" -gt 0 ]; then
                local _p="-p ${r_NEXUS_CONTAINER_PORT1}:8081"
                [ -n "${r_NEXUS_CONTAINER_PORT2}" ] && [ "${r_NEXUS_CONTAINER_PORT2}" -gt 0 ] && _p="${_p% } -p ${r_NEXUS_CONTAINER_PORT2}:8443"
                if [[ "${r_DOCKER_PROXY}" =~ :([0-9]+)$ ]]; then
                    _pid_by_port "${BASH_REMATCH[1]}" &>/dev/null || _p="${_p% } -p ${BASH_REMATCH[1]}:${BASH_REMATCH[1]}"
                fi
                if [[ "${r_DOCKER_HOSTED}" =~ :([0-9]+)$ ]]; then
                    _pid_by_port "${BASH_REMATCH[1]}" &>/dev/null || _p="${_p% } -p ${BASH_REMATCH[1]}:${BASH_REMATCH[1]}"
                fi
                if [[ "${r_DOCKER_GROUP}" =~ :([0-9]+)$ ]]; then
                    _pid_by_port "${BASH_REMATCH[1]}" &>/dev/null || _p="${_p% } -p ${BASH_REMATCH[1]}:${BASH_REMATCH[1]}"
                fi
                _tmp_ext_opts="${_p} ${_tmp_ext_opts}"
            fi
            if _isYes "${r_NEXUS_MOUNT}"; then
                _tmp_ext_opts="${_tmp_ext_opts} $(f_nexus_mount_volume "${r_NEXUS_MOUNT_DIR}")" || return $?
                f_nexus_init_properties "${r_NEXUS_MOUNT_DIR}" || return $?
            fi
            _docker_run_or_start "${r_NEXUS_CONTAINER_NAME}" "${_tmp_ext_opts}" "sonatype/nexus3:${r_NEXUS_VERSION:-"latest"}"  "${r_DOCKER_CMD}"
            # 'main' requires "r_NEXUS_URL"
            if [ -z "${r_NEXUS_URL}" ] || ! _wait_url "${r_NEXUS_URL}"; then
                _log "ERROR" "${r_NEXUS_URL} is unreachable"
                return 1
            fi
        fi
    fi

    _log "INFO" "Updating 'admin' user's password (may fail if already updated) ..."
    f_nexus_admin_pwd
    _log "INFO" "Creating 'testuser' if it hasn't been created."
    f_nexus_testuser &>/dev/null  # it's OK if this fails

    if ! _is_blob_available "${r_BLOB_NAME}"; then
        f_create_file_blobstore || return $?
    fi
    for _f in `echo "${r_REPO_FORMATS:-"${_REPO_FORMATS}"}" | sed 's/,/ /g'`; do
        _log "INFO" "Executing f_setup_${_f} ..."
        if ! f_setup_${_f}; then
            _log "ERROR" "Executing setup for format:${_f} failed."
        fi
    done

    if _isYes "${r_NEXUS_CLIENT_INSTALL}"; then
        _log "INFO" "Installing a client container ..."
        p_client_container
    fi

    if _isYes "${r_SOCKS_PROXY}"; then
        _socks5_proxy "${r_SOCKS_PROXY_PORT}" "${r_NEXUS_URL}"
    fi
    _log "INFO" "Setup completed. (log:${_LOG_FILE_PATH})"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || [[ "$1" == "help" ]]; then
        usage | less
        exit 0
    fi
    
    # parsing command options (help is handled before calling 'main')
    _REPO_FORMATS_FROM_ARGS=""
    _NEXUS_VERSION_FROM_ARGS=""
    while getopts "ACDf:r:v:" opts; do
        case $opts in
            A)
                _AUTO=true
                ;;
            C)
                _CLEAN=true
                ;;
            D)
                _DEBUG=true
                ;;
            f)
                _REPO_FORMATS_FROM_ARGS="$OPTARG"
                ;;
            r)
                _RESP_FILE="$OPTARG"
                ;;
            v)
                _NEXUS_VERSION_FROM_ARGS="$OPTARG"
                ;;
        esac
    done
    
    main
fi