#!/usr/bin/env bash
# BASH script to setup NXRM3 repositories.
# Based on functions in start_hdp.sh from 'samples' and install_sonatype.sh from 'work'.
#
# For local test:
#   _import() { source /var/tmp/share/sonatype/$1; } && export -f _import
#
# How to source:
#   source /dev/stdin <<< "$(curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_nexus3_repos.sh --compressed)"
#   export _NEXUS_URL="http://localhost:8081/"
#
_DL_URL="${_DL_URL:-"https://raw.githubusercontent.com/hajimeo/samples/master"}"
type _import &>/dev/null || _import() { [ ! -s /tmp/${1} ] && curl -sf --compressed "${_DL_URL%/}/bash/$1" -o /tmp/${1}; . /tmp/${1}; }

_import "utils.sh"
_import "utils_db.sh"
_import "utils_container.sh"

type python &>/dev/null || alias python=python3  # For M1 Mac workaround

function usage() {
    local _filename="$(basename $BASH_SOURCE)"
    echo "Main purpose of this script is to create repositories with some sample components.
Also functions in this script can be used for testing downloads and uploads.

_NEXUS_URL='http://node-nxrm-ha1.standalone.localdomain:8081/' ./${_filename} -A

DOWNLOADS:
    curl ${_DL_URL%/}/bash/setup_nexus3_repos.sh -o ${_WORK_DIR%/}/sonatype/setup_nexus3_repos.sh

REQUIREMENTS / DEPENDENCIES:
    If Mac, 'gsed' and 'ggrep' are required.
    brew install gnu-sed grep

COMMAND OPTIONS:
    -A
        Automatically setup Nexus (best effort)
    -r <response_file_path>
        Specify your saved response file. Without -A, you can review your responses.
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
    sudo ${_filename} -A

Create Nexus 3.24.0 container and setup available formats:
    sudo ${_filename} -v 3.24.0 [-A]

Setup docker repositories only (and populate some data if 'docker' command is available):
    sudo ${_filename} -f docker [-A]

Setup maven,npm repositories only:
    sudo ${_filename} -f maven,npm [-A]

Using previously saved response file and review your answers:
    sudo ${_filename} -r ./my_saved_YYYYMMDDhhmmss.resp

Using previously saved response file and NO interviews:
    sudo ${_filename} -A -r ./my_saved_YYYYMMDDhhmmss.resp

Just get the repositories setting:
    f_api /service/rest/v1/repositorySettings

NOTE:
For fresh install with same container name:
    docker rm -f <container>
    sudo mv ${_WORK_DIR%/}/sonatype/<mounting-volume> /tmp/  # or rm -rf

To upgrade, if /nexus-data is a mounted volume, just reuse same response file but with newer Nexus version.
If HA-C, edit nexus.properties for all nodes, then remove 'db' directory from node-2 and node-3.
"
}


## Global variables
: ${_REPO_FORMATS:="maven,pypi,npm,nuget,docker,yum,rubygem,helm,conda,cocoapods,bower,go,apt,r,p2,gitlfs,raw"}
: ${_ADMIN_USER:="admin"}
: ${_ADMIN_PWD:="admin123"}
: ${_DOMAIN:="standalone.localdomain"}
: ${_NEXUS_URL:="http://localhost:8081/"}   # or https://local.standalone.localdomain:8443/ for docker
: ${_IQ_URL:="http://localhost:8070/"}
: ${_IQ_CLI_VER-"1.141.0-01"}               # If "" (empty), not download CLI jar
: ${_DOCKER_NETWORK_NAME:="nexus"}
: ${_SHARE_DIR:="/var/tmp/share"}
: ${_IS_NXRM2:="N"}
: ${_NO_DATA:="N"}
: ${_BLOBTORE_NAME:=""}     # eg: default. Empty means auto
: ${_IS_NEWDB:=""}
: ${_DATASTORE_NAME:=""}    # If Postgres (or H2), needs to add attributes.storage.dataStoreName = "nexus"
: ${_TID:=80}
## Misc. variables
_LOG_FILE_PATH="/tmp/setup_nexus3_repos.log"
_TMP="/tmp"  # for downloading/uploading assets
## Variables which used by command arguments
_AUTO=false
_DEBUG=false
_CLEAN=false
_RESP_FILE=""


### Repository setup functions ################################################################################
# Eg: r_NEXUS_URL="http://dh1.standalone.localdomain:8081/" f_setup_xxxxx
function f_setup_maven() {
    local _prefix="${1:-"maven"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _source_nexus_url="${4:-"${r_SOURCE_NEXUS_URL:-"${_SOURCE_NEXUS_URL}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        # NOTE: I prefer "maven":{...,"contentDisposition":"ATTACHMENT"...}, but using default for various testings.
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"MIXED","layoutPolicy":"PERMISSIVE"},"proxy":{"remoteUrl":"https://repo1.maven.org/maven2/","contentMaxAge":-1,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"maven2-proxy"}],"type":"rpc"}' || return $?
        echo "NOTE: if 'IQ: Audit and Quarantine' is needed for ${_prefix}-proxy:"
        echo "      f_iq_quarantine \"${_prefix}-proxy\""
        # NOTE: com.fasterxml.jackson.core:jackson-databind:2.9.3 should be quarantined if IQ is configured. May need to delete the component first
        #f_get_asset "maven-proxy" "com/fasterxml/jackson/core/jackson-databind/2.9.3/jackson-databind-2.9.3.jar" "test.jar"
        #_get_asset_NXRM2 central "com/fasterxml/jackson/core/jackson-databind/2.9.3/jackson-databind-2.9.3.jar" "test.jar"
    fi
    # add some data for xxxx-proxy
    # If NXRM2: _get_asset_NXRM2 "${_prefix}-proxy" "junit/junit/4.12/junit-4.12.jar"
    f_get_asset "${_prefix}-proxy" "junit/junit/4.12/junit-4.12.jar" "${_TMP%/}/junit-4.12.jar"

    if [ -n "${_source_nexus_url}" ] && [ -n "${_extra_sto_opt}" ] && ! _is_repo_available "${_prefix}-repl-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"MIXED","layoutPolicy":"PERMISSIVE"},"proxy":{"remoteUrl":"'${_source_nexus_url%/}'/repository/'${_prefix}'-hosted/","contentMaxAge":60,"metadataMaxAge":60},"replication":{"preemptivePullEnabled":true,"assetPathRegex":""},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":true}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-repl-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"maven2-proxy"}],"type":"rpc"}' || return $?
    fi

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"MIXED","layoutPolicy":"PERMISSIVE"},"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW_ONCE","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"maven2-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    #mvn deploy:deploy-file -DgroupId=junit -DartifactId=junit -Dversion=4.21 -DgeneratePom=true -Dpackaging=jar -DrepositoryId=nexus -Durl=${r_NEXUS_URL}/repository/${_prefix}-hosted -Dfile=${_TMP%/}/junit-4.12.jar
    f_upload_asset "${_prefix}-hosted" -F maven2.groupId=junit -F maven2.artifactId=junit -F maven2.version=4.21 -F maven2.asset1=@${_TMP%/}/junit-4.12.jar -F maven2.asset1.extension=jar

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        # Hosted first
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"maven2-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group ("." in groupdId should be changed to "/")
    f_get_asset "${_prefix}-group" "org/apache/httpcomponents/httpclient/4.5.12/httpclient-4.5.12.jar"
}

function f_setup_pypi() {
    local _prefix="${1:-"pypi"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://pypi.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"pypi-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    f_get_asset "${_prefix}-proxy" "packages/unit/0.2.2/Unit-0.2.2.tar.gz" "${_TMP%/}/Unit-0.2.2.tar.gz"

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW_ONCE","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"pypi-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    f_upload_asset "${_prefix}-hosted" -F "pypi.asset=@${_TMP%/}/Unit-0.2.2.tar.gz"

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        # Hosted first
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"pypi-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    f_get_asset "${_prefix}-group" "packages/pyyaml/5.3.1/PyYAML-5.3.1.tar.gz"
}

function f_setup_p2() {
    local _prefix="${1:-"p2"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://download.eclipse.org/releases/2019-09/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"dataStoreName":"nexus","blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"'${_prefix}'-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    f_get_asset "${_prefix}-proxy" "p2.index"
    f_get_asset "${_prefix}-proxy" "compositeContent.jar"
}

function f_setup_npm() {
    local _prefix="${1:-"npm"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _source_nexus_url="${4:-"${r_SOURCE_NEXUS_URL:-"${_SOURCE_NEXUS_URL}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://registry.npmjs.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"npm-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    f_get_asset "${_prefix}-proxy" "lodash/-/lodash-4.17.19.tgz" "${_TMP%/}/lodash-4.17.19.tgz"

    if [ -n "${_source_nexus_url}" ] && [ -n "${_extra_sto_opt}" ] && ! _is_repo_available "${_prefix}-repl-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"npm":{"removeNonCataloged":false,"removeQuarantinedVersions":false},"proxy":{"remoteUrl":"'${_source_nexus_url%/}'/repository/'${_prefix}'-hosted/","contentMaxAge":60,"metadataMaxAge":60},"replication":{"preemptivePullEnabled":true,"assetPathRegex":""},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":true}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-repl-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"npm-proxy"}],"type":"rpc","tid"' || return $?
    fi

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW_ONCE","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"npm-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    f_upload_asset "${_prefix}-hosted" -F "npm.asset=@${_TMP%/}/lodash-4.17.19.tgz"

    # If no xxxx-prop-hosted (proprietary), create it (from 3.30)
    # https://help.sonatype.com/integrations/iq-server-and-repository-management/iq-server-and-nxrm-3.x/preventing-namespace-confusion
    # https://help.sonatype.com/iqserver/managing/policy-management/reference-policy-set-v6
    if ! _is_repo_available "${_prefix}-prop-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW_ONCE","strictContentTypeValidation":true'${_extra_sto_opt}'},"component":{"proprietaryComponents":true},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-prop-hosted","format":"","type":"","url":"","online":true,"recipe":"npm-hosted"}],"type":"rpc"}' # || return $? # this would fail if version is not 3.30
        echo "NOTE: if 'IQ: Audit and Quarantine' is needed for ${_prefix}-prop-hosted:"
        echo "      f_iq_quarantine \"${_prefix}-prop-hosted\""
    fi

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        # Hosted first
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"npm-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    f_get_asset "${_prefix}-group" "grunt/-/grunt-1.1.0.tgz"
}

function f_setup_nuget() {
    local _prefix="${1:-"nuget"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    _log "NOTE" "v3.29 and higher added \"nugetVersion\":\"V3\", so please check if nuget proxy repos have correct version from Web UI."
    if ! _is_repo_available "${_prefix}-v2-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"nugetProxy":{"nugetVersion":"V2","queryCacheItemMaxAge":3600},"proxy":{"remoteUrl":"https://www.nuget.org/api/v2/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-v2-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"nuget-proxy"}],"type":"rpc"}'
    fi
    f_get_asset "${_prefix}-v2-proxy" "/HelloWorld/1.3.0.15" "${_TMP%/}/helloworld.1,3.0.15.nupkg"
    if ! _is_repo_available "${_prefix}-v3-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"nugetProxy":{"nugetVersion":"V3","queryCacheItemMaxAge":3600},"proxy":{"remoteUrl":"https://api.nuget.org/v3/index.json","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-v3-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"nuget-proxy"}],"type":"rpc"}'
    fi
    # add some data for xxxx-proxy
    f_get_asset "${_prefix}-v3-proxy" "index.json"  # This one may fail on some older Nexus version
    f_get_asset "${_prefix}-v3-proxy" "/v3/content/test/2.0.1.1/test.2.0.1.1.nupkg" "${_TMP%/}/test.2.0.1.1.nupkg"  # this one may fail on some older Nexus version

    if ! _is_repo_available "${_prefix}-ps-proxy"; then # Need '"nugetVersion":"V2",'?
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"nugetProxy":{"nugetVersion":"V2","queryCacheItemMaxAge":3600},"proxy":{"remoteUrl":"https://www.powershellgallery.com/api/v2","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-ps-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"nuget-proxy"}],"type":"rpc"}'
    fi
    # TODO: should add "https://www.myget.org/F/workflow" as well?

    if ! _is_repo_available "${_prefix}-choco-proxy"; then # Need '"nugetVersion":"V2",'?
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"nugetProxy":{"nugetVersion":"V2","queryCacheItemMaxAge":3600},"proxy":{"remoteUrl":"https://chocolatey.org/api/v2/","contentMaxAge":1440,"metadataMaxAge":1440},"replication":{"preemptivePullEnabled":false},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-choco-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"nuget-proxy"}],"type":"rpc"}'
    fi

    # Nexus should have nuget.org-proxy, nuget-group, and nuget-hosted already, so creating only v3 one
    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"nuget-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    f_upload_asset "${_prefix}-hosted" -F "nuget.asset=@${_TMP%/}/test.2.0.1.1.nupkg"

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-v3-group"; then
        # Hosted first
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-v3-proxy"]}},"name":"'${_prefix}'-v3-group","format":"","type":"","url":"","online":true,"recipe":"nuget-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    f_get_asset "${_prefix}-v3-group" "/v3/content/nlog/3.1.0/nlog.3.1.0.nupkg" "${_TMP%/}/nlog.3.1.0.nupkg"  # this one may fail on some Nexus version
}

#_NEXUS_URL=http://node3281.standalone.localdomain:8081/ f_setup_docker
function f_setup_docker() {
    local _prefix="${1:-"docker"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _source_nexus_url="${4:-"${r_SOURCE_NEXUS_URL:-"${_SOURCE_NEXUS_URL}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    #local _opts="--tls-verify=false"    # TODO: only for podman. need an *easy* way to use http for 'docker'

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        # "httpPort":18178 - 18179
        # https://issues.sonatype.org/browse/NEXUS-26642 contentMaxAge -1
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":18178,"httpsPort":18179,"forceBasicAuth":false,"v1Enabled":true},"proxy":{"remoteUrl":"https://registry-1.docker.io","contentMaxAge":-1,"metadataMaxAge":1440},"dockerProxy":{"indexType":"HUB","cacheForeignLayers":false,"useTrustStoreForIndexAccess":false},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"undefined":[false,false],"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"docker-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    _log "INFO" "Populating ${_prefix}-proxy repository with some image ..."
    if ! f_populate_docker_proxy; then
        _log "WARN" "f_populate_docker_proxy failed. May need to add 'Docker Bearer Token Realm' (not only for anonymous access)."
    fi

    if [ -n "${_source_nexus_url}" ] && [ -n "${_extra_sto_opt}" ] && ! _is_repo_available "${_prefix}-repl-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":null,"httpsPort":null,"forceBasicAuth":false,"v1Enabled":true},"proxy":{"remoteUrl":"'${_source_nexus_url%/}'/repository/'${_prefix}'-hosted/","contentMaxAge":-1,"metadataMaxAge":60},"replication":{"preemptivePullEnabled":true,"assetPathRegex":""},"dockerProxy":{"indexType":"HUB","cacheForeignLayers":false,"useTrustStoreForIndexAccess":false},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":true}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-repl-proxy","format":"","type":"","url":"","online":true,"undefined":[false,false],"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"docker-proxy"}],"type":"rpc"}' || return $?
    fi

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        # Using "httpPort":18181 - 18182,
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":18181,"httpsPort":18182,"forceBasicAuth":true,"v1Enabled":true},"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"undefined":[false,false],"recipe":"docker-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    _log "INFO" "Populating ${_prefix}-hosted repository with some image ..."
    if ! f_populate_docker_hosted; then
        _log "WARN" "f_populate_docker_hosted failed. May need to add 'Docker Bearer Token Realm'."
    fi

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        # Using "httpPort":4999 - 5000
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":4999,"httpsPort":5000,"forceBasicAuth":true,"v1Enabled":true},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"groupWriteMember":"'${_prefix}'-hosted","memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"undefined":[false,false],"recipe":"docker-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    _log "INFO" "Populating ${_prefix}-group repository with some image via docker proxy repo ..."
    f_populate_docker_proxy "hello-world" "${r_DOCKER_GROUP}" "5000 4999"
}

#f_populate_docker_proxy "" "nxrm3ha-docker-k8s.standalone.localdomain"
function f_populate_docker_proxy() {
    local _img_name="${1:-"alpine:3.7"}"
    local _host_port="${2:-"${r_DOCKER_PROXY:-"${r_DOCKER_GROUP:-"${r_NEXUS_URL:-"${_NEXUS_URL}"}"}"}"}"
    local _backup_ports="${3-"18179 18178"}"
    local _cmd="${4-"${r_DOCKER_CMD}"}"
    [ -z "${_cmd}" ] && _cmd="$(_docker_cmd)"
    [ -z "${_cmd}" ] && return 0    # If no docker command, just exist
    _host_port="$(_docker_login "${_host_port}" "${_backup_ports}" "${r_ADMIN_USER:-"${_ADMIN_USER}"}" "${r_ADMIN_PWD:-"${_ADMIN_PWD}"}" "${_cmd}")" || return $?

    for _imn in $(${_cmd} images --format "{{.Repository}}" | grep -w "${_img_name}"); do
        _log "WARN" "Deleting ${_imn} (waiting for 3 secs)";sleep 3
        if ! ${_cmd} rmi ${_imn}; then
            _log "WARN" "Deleting ${_imn} failed but keep continuing..."
        fi
    done
    _log "DEBUG" "${_cmd} pull ${_host_port}/${_img_name}"
    ${_cmd} pull ${_host_port}/${_img_name} || return $?
}
#ssh -2CNnqTxfg -L18182:localhost:18182 node3250    #ps aux | grep 2CNnqTxfg
#f_populate_docker_hosted "" "localhost:18182"
function f_populate_docker_hosted() {
    local _base_img="${1:-"alpine:latest"}"    # dh1.standalone.localdomain:5000/alpine:3.7
    local _host_port="${2:-"${r_DOCKER_PROXY:-"${r_DOCKER_GROUP:-"${r_NEXUS_URL:-"${_NEXUS_URL}"}"}"}"}"
    local _backup_ports="${3-"18182 18181"}"
    local _cmd="${4-"${r_DOCKER_CMD}"}"
    local _tag_to="${5:-"${_TAG_TO}"}"
    local _num_layers="${6:-"${_NUM_LAYERS:-"1"}"}"
    [ -z "${_cmd}" ] && _cmd="$(_docker_cmd)"
    [ -z "${_cmd}" ] && return 0    # If no docker command, just exist
    _host_port="$(_docker_login "${_host_port}" "${_backup_ports}" "${r_ADMIN_USER:-"${_ADMIN_USER}"}" "${r_ADMIN_PWD:-"${_ADMIN_PWD}"}" "${_cmd}")" || return $?

    if [ -z "${_tag_to}" ] && [[ "${_base_img}" =~ ([^:]+):?.* ]]; then
        _tag_to="${BASH_REMATCH[1]}_hosted"
    fi

    for _imn in $(${_cmd} images --format "{{.Repository}}" | grep -w "${_tag_to}"); do
        _log "WARN" "Deleting ${_imn} (waiting for 3 secs)";sleep 3
        if ! ${_cmd} rmi ${_imn}; then
            _log "WARN" "Deleting ${_imn} failed but keep continuing..."
        fi
    done

    # NOTE: docker build -f does not work (bug?)
    local _build_dir="${HOME%/}/${FUNCNAME}_build_tmp_dir_$(date +'%Y%m%d%H%M%S')"  # /tmp or /var/tmp fails on Ubuntu
    if [ ! -d "${_build_dir%/}" ]; then
        mkdir -v -p ${_build_dir} || return $?
    fi
    cd ${_build_dir} || return $?
    # NOTE: Trying to create a layer. NOTE: 'CMD' doesn't create new layers.
    local _build_str="FROM ${_base_img}"    #\nRUN apk add --no-cache mysql-client
    for i in $(seq 1 ${_num_layers}); do
        _build_str="${_build_str}\nRUN echo 'Adding layer ${i} for ${_tag_to}' > /var/tmp/layer_${i}"
    done
    echo -e "${_build_str}" > Dockerfile
    ${_cmd} build --rm -t ${_tag_to} .
    local _rc=$?
    cd -  && mv -v ${_build_dir} ${_TMP%/}/
    if [ ${_rc} -ne 0 ]; then
        _log "ERROR" "'${_cmd} build --rm -t ${_tag_to} .' failed (${_rc}, ${_TMP%/}/${_build_dir})"
        return ${_rc}
    fi
    # It seems newer docker appends "localhost/" so trying this one first.
    if ! ${_cmd} tag localhost/${_tag_to} ${_host_port}/${_tag_to} 2>/dev/null; then
        ${_cmd} tag ${_tag_to} ${_host_port}/${_tag_to} || return $?
    fi
    _log "DEBUG" "${_cmd} push ${_host_port}/${_tag_to}"
    ${_cmd} push ${_host_port}/${_tag_to} || return $?
}
#echo -e "FROM alpine:3.7\nRUN apk add --no-cache mysql-client\nCMD echo 'Built ${_tag_to} from image:${_base_img}' > /var/tmp/f_populate_docker_hosted.out" > Dockerfile && ${_cmd} build --rm -t ${_tag_to} .

function f_setup_yum() {
    local _prefix="${1:-"yum"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"http://mirror.centos.org/centos/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"yum-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy (Ubuntu has "yum" command)
    # NOTE: using 'yum' command is a bit too slow, so not using at this moment
    #f_echo_yum_repo_file "${_prefix}-proxy" > /etc/yum.repos.d/nexus-yum-test.repo
    #yum --disablerepo="*" --enablerepo="nexusrepo-test" install --downloadonly --downloaddir=${_TMP%/} dos2unix
    # NOTE: due to the known limitation, some version of Nexus requires anonymous for yum repo
    # https://support.sonatype.com/hc/en-us/articles/213464848-Authenticated-Access-to-Nexus-from-Yum-Doesn-t-Work
    f_get_asset "${_prefix}-proxy" "7/os/x86_64/Packages/dos2unix-6.0.3-7.el7.x86_64.rpm" "${_TMP%/}/dos2unix-6.0.3-7.el7.x86_64.rpm"
    # NOTE: https://issues.sonatype.org/browse/NEXUS-27899
    if ! _is_repo_available "${_prefix}-epel-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://dl.fedoraproject.org/pub/epel/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-epel-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"yum-proxy"}],"type":"rpc"}' || return $?
    fi

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        # NOTE: using '3' for repodataDepth because of using 7/os/x86_64/Packages (x86_64 is 3rd)
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"yum":{"repodataDepth":3,"deployPolicy":"PERMISSIVE"},"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"yum-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    local _upload_file="$(find ${_TMP%/} -type f -size +1k -name "dos2unix-*.el7.x86_64.rpm" 2>/dev/null | tail -n1)"
    if [ ! -s "${_upload_file}" ]; then
        if curl -sSf -o ${_TMP%/}/aether-api-1.13.1-13.el7.noarch.rpm "http://mirror.centos.org/centos/7/os/x86_64/Packages/aether-api-1.13.1-13.el7.noarch.rpm"; then
            _upload_file=${_TMP%/}/aether-api-1.13.1-13.el7.noarch.rpm
        fi
    fi
    if [ -s "${_upload_file}" ]; then
        #curl -D/dev/stderr -u admin:admin123 -X PUT "${_NEXUS_URL%/}/repository/${_prefix}-hosted/7/os/x86_64/Packages/$(basename ${_upload_file})" -T ${_upload_file}
        f_upload_asset "${_prefix}-hosted" -F "yum.asset=@${_upload_file}" -F "yum.asset.filename=$(basename ${_upload_file})" -F "yum.directory=7/os/x86_64/Packages"
    fi
    #curl -u 'admin:admin123' --upload-file /etc/pki/rpm-gpg/RPM-GPG-KEY-pmanager ${r_NEXUS_URL%/}/repository/yum-hosted/RPM-GPG-KEY-pmanager

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"yum-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    f_get_asset "${_prefix}-group" "7/os/x86_64/Packages/$(basename ${_upload_file})"
}
function f_echo_yum_repo_file() {
    local _repo="${1:-"yum-group"}"
    local _base_url="${2:-"${r_NEXUS_URL:-"${_NEXUS_URL}"}"}"
    # At this moment, Nexus yum repositories require anonymous, so not modifying the url with "https://admin:admin123@HOST:PORT/repository/..."
    local _repo_url="${_base_url%/}/repository/${_repo}"
echo '[nexusrepo-test]
name=Nexus Repository
baseurl='${_repo_url%/}'/$releasever/os/$basearch/
enabled=1
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
priority=1
username='${_ADMIN_USER:-"admin"}'
password='${_ADMIN_PWD:-"admin123"}
# https://support.sonatype.com/hc/en-us/articles/213464848-Authenticated-Access-to-Nexus-from-Yum-Doesn-t-Work
}

function f_setup_rubygem() {
    local _prefix="${1:-"rubygem"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://rubygems.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"rubygems-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    #local _nexus_url="${r_NEXUS_URL:-"${_NEXUS_URL}"}"
    #_gen_gemrc "${_nexus_url%/}/repository/${_prefix}-proxy" "/tmp/gemrc" "" "${r_ADMIN_USER:-"${_ADMIN_USER}"}:${r_ADMIN_PWD:-"${_ADMIN_PWD}"}"
    #gem fetch loudmouth --config-file /tmp/gemrc
    #gem fetch loudmouth --clear-sources -s http://admin:admin123@localhost:8081/repository/rubygem-proxy/ -V --debug
    #f_get_asset "${_prefix}-proxy" "latest_specs.4.8.gz" "${_TMP%/}/specs.4.8.gz"
    f_get_asset "${_prefix}-proxy" "latest_specs.4.8.gz" "${_TMP%/}/latest_specs.4.8.gz"
    f_get_asset "${_prefix}-proxy" "gems/loudmouth-0.2.4.gem" "${_TMP%/}/loudmouth-0.2.4.gem"

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW_ONCE","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"rubygems-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    if [ -s "${_TMP%/}/loudmouth-0.2.4.gem" ]; then
        f_upload_asset "${_prefix}-hosted" -F rubygem.asset=@${_TMP%/}/loudmouth-0.2.4.gem
    fi

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"rubygems-group"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
    fi
    f_get_asset "${_prefix}-group" "gems/CFPropertyList-3.0.3.gem" "${_TMP%/}/CFPropertyList-3.0.3.gem"
}
function _gen_gemrc() {
    local _repo_url="${1}"
    local _gemrc_path="${2:-"${HOME%/}/.gemrc"}"
    local _user="${3}"
    local _credential="${4}"

    local _protocol="http"
    local _repo_url_without_http="${_repo_url}"
    if [[ "${_repo_url}" =~ ^(https?)://(.+)$ ]]; then
        _protocol="${BASH_REMATCH[1]}"
        _repo_url_without_http="${BASH_REMATCH[2]}"
    fi
    if [ -n "${_credential}" ]; then
        _repo_url="${_protocol}://${_credential}@${_repo_url_without_http%/}"
    fi
    cat << EOF > "${_gemrc_path}"
:verbose: :really
:disable_default_gem_server: true
:sources:
    - ${_repo_url%/}/
EOF
    if [ -n "${_user}" ]; then
        chown -v ${_user}:${_user} "${_gemrc_path}"
    fi
}

function f_setup_helm() {
    local _prefix="${1:-"helm"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it. NOTE: not supported with HA-C
    if ! _is_repo_available "${_prefix}-proxy"; then
        # https://charts.helm.sh/stable looks like deprecated
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://charts.bitnami.com/bitnami","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"helm-proxy"}],"type":"rpc"}' || return $?
    fi
    if ! _is_repo_available "${_prefix}-sonatype-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://sonatype.github.io/helm3-charts","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-sonatype-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"helm-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    f_get_asset "${_prefix}-proxy" "/mysql-9.4.1.tgz" "${_TMP%/}/mysql-9.4.1.tgz"

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"helm-hosted","format":"","type":"","url":"","online":true,"recipe":"'${_prefix}'-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    # https://issues.sonatype.org/browse/NEXUS-31326
    [ -s "${_TMP%/}/mysql-9.4.1.tgz" ] && curl -sf -u "${r_ADMIN_USER:-"${_ADMIN_USER}"}:${r_ADMIN_PWD:-"${_ADMIN_PWD}"}" "${_NEXUS_URL%/}/repository/${_prefix}-hosted/" -T "${_TMP%/}/mysql-9.4.1.tgz"
}

function f_setup_bower() {
    local _prefix="${1:-"bower"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"bower":{"rewritePackageUrls":true},"proxy":{"remoteUrl":"https://registry.bower.io","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"bower-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    f_get_asset "${_prefix}-proxy" "/jquery/versions.json" "${_TMP%/}/bowser_jquery_versions.json"
    # TODO: hosted and group
}

function f_setup_conan() {
    local _prefix="${1:-"conan"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # NOTE: If you disabled Anonymous access, then it is needed to enable the Conan Bearer Token Realm (via Administration > Security > Realms):

    # If no xxxx-proxy, create it (NOTE: No HA, but seems to work with HA???)
    if ! _is_repo_available "${_prefix}-proxy"; then
        # Used to be https://conan.bintray.com
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://center.conan.io/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"conan-proxy"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-proxy

    # If no xxxx-hosted, create it. From 3.35, so it's OK to fail
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW"'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"conan-hosted"}],"type":"rpc"}'
    fi
    _upload_to_conan_hosted "${_prefix}"
    return 0    # ignore the last function failure
}
function _upload_to_conan_hosted() {
    local _prefix="${1:-"conan"}"
    if ! type conan &>/dev/null; then
        _log "WARN" "_upload_to_conan_hosted requires 'conan'"
        return 1
    fi
    if ! type cmake &>/dev/null; then
        _log "WARN" "_upload_to_conan_hosted requires 'cmake'"
        # sudo snap install cmake --classic
        return 1
    fi
    if ${_DEBUG}; then
        export CONAN_LOGGING_LEVEL=debug
    fi
    # Ignoring Remote 'conan-hosted' does not exist or if add fails
    conan remote remove ${_prefix}-hosted
    conan remote add ${_prefix}-hosted "${_NEXUS_URL%/}/repository/${_prefix}-hosted" false

    local _pkg_ver="hello/0.2"
    local _usr_stable="demo/testing"
    local _build_dir="$(mktemp -d)"
    cd "${_build_dir}" || return $?
    conan new ${_pkg_ver}
    # example: https://issues.sonatype.org/browse/NEXUS-37563
    if ! conan create -s arch=x86_64 -s os=Linux . ${_usr_stable}; then
        cd -
        return 1
    fi
    #conan user -c
    #conan user -p ${_ADMIN_PWD} -r "${_prefix}-hosted" ${_ADMIN_USER}
    CONAN_LOGIN_USERNAME="${_ADMIN_USER}" CONAN_PASSWORD="${_ADMIN_PWD}" conan upload --confirm --all --retry 0 -r "${_prefix}-hosted" ${_pkg_ver}@${_usr_stable}
    local _rc=$?
    if [ ${_rc} != 0 ]; then
        # /v1/users/check_credentials returns 401 if no realm
        _log "ERROR" "Please make sure 'Conan Bearer Token Realm' (ConanToken) is enabled (f_put_realms)"
    fi
    cd -
    if ${_DEBUG}; then
        unset CONAN_LOGGING_LEVEL
    fi
    return ${_rc}
}

function f_setup_conda() {
    local _prefix="${1:-"conda"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it (NOTE: No HA)
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://repo.continuum.io/pkgs/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"conda-proxy"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-proxy
}

function f_setup_cocoapods() {
    local _prefix="${1:-"cocoapods"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it (NOTE: No HA, but seems to work with HA???)
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://cdn.cocoapods.org/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"cocoapods-proxy"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-proxy
}

function f_setup_go() {
    local _prefix="${1:-"go"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it (NOTE: No HA support)
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://gonexus.dev/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"go-proxy"}],"type":"rpc"}' || return $?
    fi
    # Workaround for https://issues.sonatype.org/browse/NEXUS-21642
    if ! _is_repo_available "gosum-raw-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"raw":{"contentDisposition":"ATTACHMENT"},"proxy":{"remoteUrl":"https://sum.golang.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"gosum-raw-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"raw-proxy"}],"type":"rpc"}' || return $?
        _log "INFO" "May need to set 'GOSUMDB=\"sum.golang.org ${r_NEXUS_URL:-"${_NEXUS_URL%/}"}/repository/gosum-raw-proxy\"'"
    fi
    # TODO: add some data for xxxx-proxy
}

function f_setup_apt() {
    local _prefix="${1:-"apt"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it (NOTE: No HA support)
    if ! _is_repo_available "${_prefix}-proxy"; then
        # distribution should be focal, bionic, etc, but it seems any string is OK.
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"apt":{"distribution":"ubuntu","flat":false},"proxy":{"remoteUrl":"http://archive.ubuntu.com/ubuntu/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"apt-proxy"}],"type":"rpc"}' || return $?
    fi
    if ! _is_repo_available "${_prefix}-debian-proxy"; then
        # distribution should be focal, bionic, etc, but it seems any string is OK.
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"apt":{"distribution":"debian","flat":false},"proxy":{"remoteUrl":"http://deb.debian.org/debian","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-debian-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"apt-proxy"}],"type":"rpc"}' || return $?
    fi
    if ! _is_repo_available "${_prefix}-debian-sec-proxy"; then
        # distribution should be focal, bionic, etc, but it seems any string is OK.
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"apt":{"distribution":"debian","flat":false},"proxy":{"remoteUrl":"http://security.debian.org/debian-security","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-debian-sec-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"apt-proxy"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-proxy
    # TODO: add hosted
}

function f_setup_r() {
    local _prefix="${1:-"r"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://cran.r-project.org/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"r-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    #f_get_asset "${_prefix}-proxy" "download/plugins/nexus-jenkins-plugin/3.9.20200722-164144.e3a1be0/nexus-jenkins-plugin.hpi"

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW"'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"r-hosted"}],"type":"rpc"}' && \
            echo "# install.packages('agricolae', repos='${_NEXUS_URL%/}/repository/r${_prefix}-proxy/', type='binary')"
    fi
    if [ ! -s "${_TMP%/}/myfunpackage_1.0.tar.gz" ]; then
        curl -sf -o "${_TMP%/}/myfunpackage_1.0.tar.gz" -L https://github.com/sonatype-nexus-community/nexus-repository-r/raw/NEXUS-20439_r_format_support/nexus-repository-r-it/src/test/resources/r/myfunpackage_1.0.tar.gz
    fi
    if [ -s "${_TMP%/}/myfunpackage_1.0.tar.gz" ]; then
        curl -sf -u "${r_ADMIN_USER:-"${_ADMIN_USER}"}:${r_ADMIN_PWD:-"${_ADMIN_PWD}"}" "${_NEXUS_URL%/}/repository/${_prefix}-hosted/src/contrib/myfunpackage_1.0.tar.gz" -T "${_TMP%/}/myfunpackage_1.0.tar.gz" && \
            echo "# install.packages('myfunpackage', repos='${_NEXUS_URL%/}/repository/r${_prefix}-hosted/', type='source')"
    fi

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"r-group"}],"type":"rpc"}' && \
            echo "# install.packages('bit', repos='${_NEXUS_URL%/}/repository/r${_prefix}-group/', type='binary')"
    fi
    # add some data for xxxx-group
    #f_get_asset "${_prefix}-group" "test/test_1k.img"
}

function f_setup_gitlfs() {
    local _prefix="${1:-"gitlfs"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}',"writePolicy":"ALLOW"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"gitlfs-hosted"}],"type":"rpc"}' || return $?
    fi
}

function f_setup_raw() {
    local _prefix="${1:-"raw"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # NOTE: using "strictContentTypeValidation":false for raw repositories
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-jenkins-proxy"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"raw":{"contentDisposition":"ATTACHMENT"},"proxy":{"remoteUrl":"https://updates.jenkins.io/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":false'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-jenkins-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"raw-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    #f_get_asset "${_prefix}-jenkins-proxy" "download/plugins/nexus-jenkins-plugin/3.9.20200722-164144.e3a1be0/nexus-jenkins-plugin.hpi"

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":false'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}' || return $?
    fi
    dd if=/dev/zero of=${_TMP%/}/test_1k.img bs=1 count=0 seek=1024
    if [ -s "${_TMP%/}/test_1k.img" ]; then
        f_upload_asset "${_prefix}-hosted" -F raw.directory=test -F raw.asset1=@${_TMP%/}/test_1k.img -F raw.asset1.filename=test_1k.img
    fi
    # Quicker way: --limit-rate=4k
    # curl -D- -u 'admin:admin123' -T <(echo 'test') "${_NEXUS_URL%/}/repository/raw-hosted/test/test.txt"

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":false'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"raw-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    f_get_asset "${_prefix}-group" "test/test_1k.img"
}

function f_branding() {
    local __doc__="NXRM3 branding|brand example"
    local _msg="${1:-"HelloWorld!"}"
    #<marquee direction="right" behavior="alternate"><span style="color:#f0f8ff;">some text</span></marquee>
    f_apiS '{"action":"capability_Capability","method":"create","data":[{"id":"NX.coreui.model.Capability-1","typeId":"rapture.branding","notes":"","enabled":true,"properties":{"headerEnabled":"true","headerHtml":"<div style=\"background-color:white;text-align:right\">'${_msg}'</a>&nbsp;</div>","footerEnabled":null,"footerHtml":""}}],"type":"rpc"}'
}

### Nexus related Misc. functions #################################################################
function _get_blobstore_name() {
    local _bs_name="default"
    if [ -n "${_BLOBTORE_NAME}" ]; then
        echo "${_BLOBTORE_NAME}"
        return
    fi
    f_api "/service/rest/v1/blobstores" | sed -r -n 's/.*"name" *: *"([^"]+)".*/\1/gp' >${_TMP%/}/${FUNCNAME}_$$.out
    local _line_num="$(cat ${_TMP%/}/${FUNCNAME}_$$.out | wc -l | tr -d '[:space:]')"
    if grep -qE "^${_bs_name}$" ${_TMP%/}/${FUNCNAME}_$$.out; then
        _BLOBTORE_NAME="${_bs_name}"
    elif [ "${_line_num}" == "0" ]; then
        _log "INFO" "No blobstore defined. Creating '${_bs_name}' file blobstore ..."; sleep 3
        f_create_file_blobstore "${_bs_name}" || return $?
        _BLOBTORE_NAME="${_bs_name}"
    elif [ "${_line_num}" == "1" ]; then
        # If only one blobstore defined, use it, otherwise return false
        _BLOBTORE_NAME="$(cat ${_TMP%/}/${FUNCNAME}_$$.out)"
    else
        return 1
    fi
    echo "${_BLOBTORE_NAME}"
    return
}

function _get_datastore_name() {
    local _ds_name="nexus"  # at this moment, it seems hard-coded as 'nexus'
    if [ -n "${_DATASTORE_NAME}" ]; then
        echo "${_DATASTORE_NAME}"
        return
    fi
    if [[ "${_IS_NEWDB}" =~ ^(y|Y) ]]; then
        _DATASTORE_NAME="${_ds_name}"
        echo "${_DATASTORE_NAME}"
        return
    fi
    if [ -z "${_IS_NEWDB}" ] && f_api "/service/rest/internal/ui/datastore" &>/dev/null; then
        _DATASTORE_NAME="${_ds_name}"
        _IS_NEWDB="Y"
        echo "${_DATASTORE_NAME}"
        return
    fi
    return 1
}

function f_create_file_blobstore() {
    local _bs_name="${1:-"default"}"
    if ! f_apiS '{"action":"coreui_Blobstore","method":"create","data":[{"type":"File","name":"'${_bs_name}'","isQuotaEnabled":false,"attributes":{"file":{"path":"'${_bs_name}'"}}}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out; then
        _log "ERROR" "Blobstore ${_bs_name} does not exist."
        _log "ERROR" "$(cat ${_TMP%/}/f_apiS_last.out)"
        return 1
    fi
    _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
}

# AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=yyy f_create_s3_blobstore
function f_create_s3_blobstore() {
    local _bs_name="${1:-"s3-test"}"
    local _prefix="${2:-"$(hostname -s)_${_bs_name}"}"    # cat /etc/machine-id is not perfect if docker container
    local _bucket="${3:-"apac-support-bucket"}"
    local _region="${4:-"${AWS_REGION:-"ap-southeast-2"}"}"
    local _ak="${5:-"${AWS_ACCESS_KEY_ID}"}"
    local _sk="${6:-"${AWS_SECRET_ACCESS_KEY}"}"
    # NOTE 3.27 has ',"state":""'
    # TODO: replace with /v1/blobstores/s3 POST
    if ! f_apiS '{"action":"coreui_Blobstore","method":"create","data":[{"type":"S3","name":"'${_bs_name}'","isQuotaEnabled":false,"property_region":"'${_region}'","property_bucket":"'${_bucket}'","property_prefix":"'${_prefix}'","property_expiration":1,"authEnabled":true,"property_accessKeyId":"'${_ak}'","property_secretAccessKey":"'${_sk}'","property_assumeRole":"","property_sessionToken":"","encryptionSettingsEnabled":false,"advancedConnectionSettingsEnabled":false,"attributes":{"s3":{"region":"'${_region}'","bucket":"'${_bucket}'","prefix":"'${_prefix}'","expiration":"2","accessKeyId":"'${_ak}'","secretAccessKey":"'${_sk}'","assumeRole":"","sessionToken":""}}}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out; then
        _log "ERROR" "Failed to create blobstore: ${_bs_name} ."
        _log "ERROR" "$(cat ${_TMP%/}/f_apiS_last.out)"
        return 1
    fi
    _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    if ! _is_repo_available "raw-s3-hosted"; then
        _log "INFO" "Creating raw-s3-hosted ..."
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"raw-s3-hosted","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}' || return $?
    fi
    _log "INFO" "Command examples:
aws s3 ls s3://${_bucket}/${_prefix}/content/ # --recursive but 1000 limits (same for list-objects)
aws s3api list-objects --bucket ${_bucket} --query \"Contents[?contains(Key, 'f062f002-88f0-4b53-aeca-7324e9609329.properties')]\"
aws s3api get-object-tagging --bucket ${_bucket} --key \"${_prefix}/content/vol-42/chap-31/f062f002-88f0-4b53-aeca-7324e9609329.properties\"
aws s3 cp s3://${_bucket}/${_prefix}/content/vol-42/chap-31/f062f002-88f0-4b53-aeca-7324e9609329.properties -
"
}

function f_create_azure_blobstore() {
    #https://learn.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal#get-tenant-and-app-id-values-for-signing-in
    local _bs_name="${1:-"az-test"}"
    local _container_name="${2:-"$(hostname -s)_${_bs_name}"}"
    local _an="${3:-"${AZURE_ACCOUNT_NAME}"}"
    local _ak="${4:-"${AZURE_ACCOUNT_KEY}"}"
    # nexus.azure.server=<your.desired.blob.storage.server>
    if ! f_api "/service/rest/v1/blobstores/azure" '{"name":"'${_bs_name}'","bucketConfiguration":{"authentication":{"authenticationMethod":"ACCOUNTKEY","accountKey":"'${_ak}'"},"accountName":"'${_an}'","containerName":"'${_container_name}'"}}' > ${_TMP%/}/f_api_last.out; then
        _log "ERROR" "Failed to create blobstore: ${_bs_name} ."
        _log "ERROR" "$(cat ${_TMP%/}/f_api_last.out)"
        return 1
    fi
    _log "DEBUG" "$(cat ${_TMP%/}/f_api_last.out)"
    if ! _is_repo_available "raw-az-hosted"; then
        _log "INFO" "Creating raw-az-hosted ..."
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"raw-az-hosted","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}' || return $?
    fi
}

f_create_group_blobstore() {
    local __doc__="Create a new blob store, then promote to group"
    echo "TODO: Not implemented yet"
    return
}

function f_iq_quarantine() {
    local _repo_name="$1"
    if [ -z "${_IQ_URL}" ] || ! curl -sfI "${_IQ_URL}" &>/dev/null ; then
        _log "WARN" "IQ ${_IQ_URL} is not reachable capability"
        return
    fi
    f_apiS '{"action":"clm_CLM","method":"update","data":[{"enabled":true,"url":"'${_IQ_URL}'","authenticationType":"USER","username":"'${_ADMIN_USER}'","password":"'${_ADMIN_PWD}'","timeoutSeconds":null,"properties":"","showLink":true}],"type":"rpc"}' || return $?
    # To create IQ: Audit and Quarantine for this repository:
    if [ -n "${_repo_name}" ]; then
        f_apiS '{"action":"capability_Capability","method":"create","data":[{"id":"NX.coreui.model.Capability-1","typeId":"firewall.audit","notes":"","enabled":true,"properties":{"repository":"'${_repo_name}'","quarantine":"true"}}],"type":"rpc"}' || return $?
        _log "INFO" "IQ: Audit and Quarantine for ${_repo_name} completed."
    fi
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

# Same way as using Upload UI
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
            _log "WARN" "Post to ${_base_url%/}/service/rest/v1/components?repository=${_repo} might be failed (${_rc})"
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
    local _sess="$(_sed -nr 's/.+\sNXSESSIONID\s+([0-9a-f]+)/\1/p' ${_c})"
    local _sess_key="NXSESSIONID"
    if [ -z "${_sess}" ]; then
        _sess="$(_sed -nr 's/.+\sNXJWT\s+([^\s]+)/\1/p' ${_c})"
        if [ -z "${_sess}" ]; then
            _log "ERROR" "No session id in '${_c}'"
            return 1
        fi
        _sess_key="NXJWT"
    fi
    local _H_sess="${_sess_key}: ${_sess}"
    local _H_anti="NX-ANTI-CSRF-TOKEN: test"
    local _C="Cookie: NX-ANTI-CSRF-TOKEN=test; ${_sess_key}=${_sess}"
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
    local _sort_keys="${7:-"${r_API_SORT_KEYS:-"${_API_SORT_KEYS}"}"}"

    local _user_pwd="${_usr}"
    [ -n "${_pwd}" ] && _user_pwd="${_usr}:${_pwd}"
    [ -n "${_data}" ] && [ -z "${_method}" ] && _method="POST"
    [ -z "${_method}" ] && _method="GET"
    # TODO: check if GET and DELETE *can not* use Content-Type json?
    local _content_type="Content-Type: application/json"
    [ "${_data:0:1}" != "{" ] && [ "${_data:0:1}" != "[" ] && _content_type="Content-Type: text/plain"

    local _curl="curl -sf"
    ${_DEBUG} && _curl="curl -vf"
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
    if [[ "${_sort_keys}" =~ ^[yY] ]]; then
      cat ${_TMP%/}/f_api_nxrm_$$.out | python -c "import sys,json;print(json.dumps(json.load(sys.stdin), indent=4, sort_keys=True))"
    elif ! cat ${_TMP%/}/f_api_nxrm_$$.out | python -m json.tool 2>/dev/null; then
        echo -n "$(cat ${_TMP%/}/f_api_nxrm_$$.out)"
        echo ""
    fi
}

# Create a container which installs python, npm, mvn, nuget, etc.
#usermod -a -G docker $USER (then relogin)
#docker rm -f nexus-client; p_client_container "http://dh1.standalone.localdomain:8081/"
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

    local _ext_opts="-v /sys/fs/cgroup:/sys/fs/cgroup:ro --privileged=true -v ${_WORK_DIR%/}:${_SHARE_DIR}"
    [ -n "${_DOCKER_NETWORK_NAME}" ] && _ext_opts="--network=${_DOCKER_NETWORK_NAME} ${_ext_opts}"
    _log "INFO" "Running or Starting '${_name}'"
    # TODO: not right way to use 3rd and 4th arguments. Also if two IPs are configured, below might update /etc/hosts with 2nd IP.
    _docker_run_or_start "${_name}" "${_ext_opts}" "${_image_name} /sbin/init" "${_cmd}" || return $?
    _container_add_NIC "${_name}" "bridge" "Y" "${_cmd}"

    # Create a test user if hasn't created (testuser:testuser123)
    _container_useradd "${_name}" "testuser" "" "Y" "${_cmd}"

    # Trust default CA certificate
    if [[ "${_base_url}" =~ \.standalone\.localdomain ]] && [ -s "${_WORK_DIR%/}/cert/rootCA_standalone.crt" ]; then
        ${_cmd} cp ${_WORK_DIR%/}/cert/rootCA_standalone.crt ${_name}:/etc/pki/ca-trust/source/anchors/ && \
        ${_cmd} exec -it ${_name} update-ca-trust
    fi

    _log "INFO" "Setting up various client commands ..."
    #${_cmd} cp $BASH_SOURCE ${_name}:/tmp/setup_nexus3_repos.sh || return $? # This started failing
    ${_cmd} exec -it ${_name} bash -c "source /dev/stdin <<< \"\$(curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_nexus3_repos.sh --compressed)\" && f_reset_client_configs \"testuser\" \"${_base_url}\" && f_install_clients" || return $?
    _log "INFO" "Completed $FUNCNAME .
To save : docker stop ${_name}; docker commit ${_name} ${_name}
To login: ssh testuser@${_name}"
}

# Setup (reset) client configs against a CentOS container
#f_reset_client_configs "testuser" "http://dh1.standalone.localdomain:8081/" && f_install_clients
function f_reset_client_configs() {
    local __doc__="Configure various client tools"
    local _user="${1:-"$USER"}"
    local _base_url="${2:-"${r_NEXUS_URL:-"${_NEXUS_URL}"}"}"   # Nexus URL
    local _usr="${3:-"${r_ADMIN_USER:-"${_ADMIN_USER}"}"}"  # Nexus user
    local _pwd="${4:-"${r_ADMIN_PWD:-"${_ADMIN_PWD}"}"}"    # Nexus user's password
    local _home="${5:-"/home/${_user%/}"}"

    if [ ! -d "${_home%/}" ]; then
        _log "ERROR" "No ${_home%/}"
        return 1
    fi

    local _repo_url="${_base_url%/}/repository/yum-group"
    if _is_url_reachable "${_repo_url}"; then
        _log "INFO" "Generating /etc/yum.repos.d/nexus-yum-test.repo ..."
        f_echo_yum_repo_file "yum-group" "${_base_url}" > /etc/yum.repos.d/nexus-yum-test.repo
    fi

    _log "INFO" "Not setting up any nuget/pwsh configs. Please do it manually later ..."

    # Using Nexus npm repository if available
    _repo_url="${_base_url%/}/repository/npm-group"
    if _is_url_reachable "${_repo_url}"; then
        _log "INFO" "Create a sample ${_home%/}/.npmrc ..."
        local _cred="$(python -c "import sys, base64; print(base64.b64encode('${_usr}:${_pwd}'))")"
        cat << EOF > ${_home%/}/.npmrc
strict-ssl=false
registry=${_repo_url%/}
_auth=\"${_cred}\""
EOF
        chown -v ${_user}:${_user} ${_home%/}/.npmrc
    fi
    _repo_url="${_base_url%/}/repository/bower-proxy"
    if _is_url_reachable "${_repo_url}"; then
        _log "INFO" "Create a sample ${_home%/}/.bowerrc ..."
        cat << EOF > ${_home%/}/.bowerrc
{
    "registry" : "${_repo_url%/}",
    "resolvers": ["bower-nexus3-resolver"]
}
EOF
        chown -v ${_user}:${_user} ${_home%/}/.bowerrc
    fi

    # Using Nexus pypi repository if available
    _repo_url="${_base_url%/}/repository/pypi-group"
    if _is_url_reachable "${_repo_url}"; then
        _log "INFO" "Create a sample ${_home%/}/.pypirc ..."
        cat << EOF > ${_home%/}/.pypirc
[distutils]
index-servers =
  nexus-group

[nexus-group]
repository: ${_repo_url%/}
username: ${_usr}
password: ${_pwd}
EOF
        chown -v ${_user}:${_user} ${_home%/}/.pypirc
    fi
    # Using Nexus conan proxy repository if available
    _repo_url="${_base_url%/}/repository/conan-proxy"
    if _is_url_reachable "${_repo_url}" && type conan &>/dev/null; then
        # Or should overwrite $HOME/.conan/conan.conf ?
        conan remote remove conan-center
        conan remote remove conancenter
        conan remote add conan-proxy ${_repo_url} false
        #rm -rf $HOME/.conan    # clear conan local cache
    fi

    _repo_url="${_base_url%/}/repository/rubygem-proxy"
    if _is_url_reachable "${_repo_url}"; then
        _log "INFO" "Create/overwrite a sample ${_home%/}/.gemrc ..."
        _gen_gemrc "${_repo_url}" "${_home%/}/.gemrc" "${_user}" "${_usr}:${_pwd}"
    fi

    # Need Xcode on Mac?: https://download.developer.apple.com/Developer_Tools/Xcode_10.3/Xcode_10.3.xip (or https://developer.apple.com/download/more/)
    if [ ! -s "${_home%/}/cocoapods-test.tgz" ]; then
        _log "INFO" "Downloading a Xcode cocoapods test project ..."
        curl -fL -o ${_home%/}/cocoapods-test.tgz https://github.com/hajimeo/samples/raw/master/misc/cocoapods-test.tgz
        chown -v ${_user}:${_user} ${_home%/}/cocoapods-test.tgz
    fi
    # TODO: cocoapods is installed but not configured properly
    #https://raw.githubusercontent.com/hajimeo/samples/master/misc/cocoapods-Podfile
    # (probably) how to retry pod install: cd $HOME/cocoapods-test && rm -rf $HOME/Library/Caches Pods Podfile.lock cocoapods-test.xcworkspace

    # If repo is reachable, setup GOPROXY env
    _repo_url="${_base_url%/}/repository/go-proxy"
    if _is_url_reachable "${_repo_url}"; then
        _log "INFO" "Update GOPROXY with 'go env' or .bash_profile ..."
        #local _protocol="http"
        #local _repo_url_without_http="${_repo_url}"
        #if [[ "${_repo_url}" =~ ^(https?)://(.+)$ ]]; then
        #    _protocol="${BASH_REMATCH[1]}"
        #    _repo_url_without_http="${BASH_REMATCH[2]}"
        #fi
        #GOPROXY=${_protocol}://${_usr}:${_pwd}@${_repo_url_without_http%/}
        if ! type go &>/dev/null || ! go env -w GOPROXY=${_repo_url}; then
            _upsert "${_home%/}/.bash_profile" "export GOPROXY" "${_repo_url}"
        fi
    fi

    # Install Conda, and if repo is reachable, setup conda/anaconda/miniconda env
    _repo_url="${_base_url%/}/repository/conda-proxy"
    if _is_url_reachable "${_repo_url}"; then
        _log "INFO" "Create a sample ${_home%/}/.condarc ..."
        #local _pwd_encoded="$(python -c \"import sys, urllib as ul; print(ul.quote('${_pwd}'))\")"
        cat << EOF > ${_home%/}/.condarc
channels:
  - ${_repo_url%/}/main
  - defaults
EOF
        chown -v ${_user}:${_user} ${_home%/}/.condarc
    fi

    # .lfsconfig needs to be under a git repo, so can't configure
    #_repo_url="${_base_url%/}/repository/gitlfs-hosted"
    #if _is_url_reachable "${_repo_url}" && git lfs version &>/dev/null; then
    #    _log "INFO" "Create git config for ${_repo_url%/}/info/lfs ..."
    #    git config -f .lfsconfig lfs.url ${_repo_url%/}/info/lfs
    #    git add .lfsconfig
    #fi

    _repo_url="${_base_url%/}/repository/maven-group"
    if _is_url_reachable "${_repo_url}"; then
        local _f=${_home%/}/.m2/settings.xml
        _log "INFO" "Create ${_f} ..."
        [ ! -d "${_home%/}/.m2" ] && mkdir -v ${_home%/}/.m2 && chown -v ${_user}:${_user} ${_home%/}/.m2
        [ -s ${_f} ] && cat ${_f} > ${_f}.bak
        curl -fL -o ${_f} -L ${_DL_URL%/}/misc/m2_settings.tmpl.xml --compressed && \
            sed -i -e "s@_REPLACE_MAVEN_USERNAME_@${_usr}@1" -e "s@_REPLACE_MAVEN_USER_PWD_@${_pwd}@1" -e "s@_REPLACE_MAVEN_REPO_URL_@${_repo_url%/}/@1" ${_f}
    fi

    # Regardless of repo availability, setup helm
    _log "INFO" "Not setting up any helm/helm3 configs. Please do it manually later ..."
}
function f_install_clients() {
    local __doc__="Install various client software with mainly yum as 'root' (TODO: so that works with CentOS 7 only)"

    if [ -n "${_IQ_CLI_VER}" ]; then
        [ -d "${_SHARE_DIR%/}/sonatype" ] || mkdir -v -p -m 777 "${_SHARE_DIR%/}/sonatype"
        local _f="${_SHARE_DIR%/}/sonatype/nexus-iq-cli-${_IQ_CLI_VER}.jar"
        if [ ! -s "${_f}" ]; then
            _log "INFO" "Downloading IQ CLI jar, version:${_IQ_CLI_VER} ..."
            curl -fL "https://download.sonatype.com/clm/scanner/nexus-iq-cli-${_IQ_CLI_VER}.jar" -o "${_f}"
        fi
        if [ -s "${_f}" ]; then
            _log "INFO" "Create IQ CLI executable /usr/local/bin/nexus-iq-cli ..."
            cat << "EOF" > /tmp/nexus-iq-cli.sh
#!/usr/bin/env bash
[[ ! " $@" =~ [[:space:]]-s[[:space:]]+[^-] ]] && _OPTS="${_OPTS% } -s ${_IQ_URL:-"http://localhost:8070/"}"
[[ ! " $@" =~ [[:space:]]-a[[:space:]]+[^-] ]] && _OPTS="${_OPTS% } -a ${_ADMIN_USER:-"admin"}:${_ADMIN_PWD:-"admin123"}"
[[ ! " $@" =~ [[:space:]]-i[[:space:]]+[^-] ]] && _OPTS="${_OPTS% } -i sandbox-application"
[[ ! " $@" =~ [[:space:]]-t[[:space:]]+[^-] ]] && _OPTS="${_OPTS% } -t build"
[[ ! " $@" =~ [[:space:]]-r[[:space:]]+[^-] ]] && _OPTS="${_OPTS% } -r iq_result_$(date +'%Y%m%d%H%M%S').json"
set -x
exec java -jar $BASH_SOURCE ${_OPTS% } "$@"
EOF
            (cat /tmp/nexus-iq-cli.sh && cat ${_f}) > "/usr/local/bin/nexus-iq-cli"
            chmod -v a+x "/usr/local/bin/nexus-iq-cli"
        fi
    fi

    _log "INFO" "Install packages with yum ..."
    local _yum_install="yum install -y"
    if [ -s /etc/yum.repos.d/nexus-yum-test.repo ]; then
        _yum_install="yum --disablerepo=base --enablerepo=nexusrepo-test install -y"
    fi
    if ! ${_yum_install} epel-release; then
        _log "ERROR" "${_yum_install} epel-release failed. Stopping the installations."
        return 1
    fi
    curl -fL https://rpm.nodesource.com/setup_14.x --compressed | bash - || _log "ERROR" "Executing https://rpm.nodesource.com/setup_14.x failed"
    rpm -Uvh https://packages.microsoft.com/config/centos/7/packages-microsoft-prod.rpm
    yum install -y centos-release-scl-rh centos-release-scl || _log "ERROR" "Installing .Net (for Nuget) related packages failed"
    ${_yum_install} java-1.8.0-openjdk-devel maven nodejs rh-ruby23 rubygems aspnetcore-runtime-3.1 golang git gcc openssl-devel bzip2-devel libffi-devel zlib-devel xz-devel || _log "ERROR" "yum install java maven nodejs etc. failed"
    if type python3 &>/dev/null; then
        _log "WARN" "python3 is already in the $PATH so not installing"
    else
        _log "INFO" "Installing python 3.7 ..."
        local _pwd="$(pwd)"
        [ ! -d "/usr/src" ] && mkdir -v -p /usr/src
        cd "/usr/src"
        [ ! -s "./Python-3.7.11.tgz" ] && curl -fL -O "https://www.python.org/ftp/python/3.7.11/Python-3.7.11.tgz"
        tar -xzf ./Python-3.7.11.tgz && \
        cd Python-3.7.11 && \
        ./configure --enable-optimizations && make altinstall
        if [ $? -eq 0 ] && [ -x /usr/local/bin/python3.7 ]; then
            if [ -f /bin/python3 ]; then
                mv -v /bin/python3 /bin/python3.orig
            fi
            ln -s /usr/local/bin/python3.7 /bin/python3
        fi
        cd "${_pwd}"
    fi

    _log "INFO" "Installing ripgrep (rg) ..."
    yum-config-manager --add-repo=https://copr.fedorainfracloud.org/coprs/carlwgeorge/ripgrep/repo/epel-7/carlwgeorge-ripgrep-epel-7.repo && sudo yum install -y ripgrep
    _log "INFO" "Install Skopeo ..."
    # Skopeo (instead of podman) https://github.com/containers/skopeo/blob/master/install.md
    # NOTE: may need Deployment policy = allow redeployment
    # skopeo --debug copy --src-creds=admin:admin123 --dest-creds=admin:admin123 docker://dh1.standalone.localdomain:18082/alpine:3.7 docker://dh1.standalone.localdomain:18082/alpine:test
    curl -fL -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_7/devel:kubic:libcontainers:stable.repo --compressed
    yum install -y skopeo
    # Install nuget.exe regardless of Nexus nuget repository availability (can't remember why install then immediately remove...)
    _log "INFO" "Install mono and nuget.exe ..."
    curl https://download.mono-project.com/repo/centos7-stable.repo | tee /etc/yum.repos.d/mono-centos7-stable.repo && yum install -y mono-complete
    yum remove -y nuget
    curl -fL -o /usr/local/bin/nuget.exe "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
    # Adding nuget alias globally
    cat << EOF > /etc/profile.d/nuget.sh
if [ -s /usr/local/bin/nuget.exe ]; then
  alias nuget="mono /usr/local/bin/nuget.exe"
fi
EOF
    # https://docs.microsoft.com/en-us/powershell/scripting/install/install-centos?view=powershell-7.2
    _log "INFO" "Install Powershell ..."    # NOTE: using /rhel/ is correct.
    curl -fL -o /etc/yum.repos.d/microsoft-prod.repo https://packages.microsoft.com/config/rhel/7/prod.repo --compressed
    yum install -y powershell
    _log "INFO" "Install yarn and bower globally ..."
    npm install -g yarn
    npm install -g bower
    npm install -g bower-nexus3-resolver
    if ! type cmake &>/dev/null; then
        _log "INFO" "Install cmake ..."
        [ ! -d /opt/cmake ] && mkdir /opt/cmake
        cd /opt/cmake
        [ ! -s ./cmake-3.22.1-linux-x86_64.sh ] && curl -o ./cmake-3.22.1-linux-x86_64.sh -L https://github.com/Kitware/CMake/releases/download/v3.22.1/cmake-3.22.1-linux-x86_64.sh
        bash ./cmake-3.22.1-linux-x86_64.sh --skip-license
        cd -
        ln -v -s /opt/cmake/bin/* /usr/local/bin && ${_yum_install} gcc gcc-c++ make
    fi
    _log "INFO" "Install conan ..."
    if ! type pip3 &>/dev/null; then
        _log "WARN" "No 'conan' installed because of no 'pip3' (probably no python3)"
    else
        pip3 install conan
    fi
    _log "INFO" "Setting up Rubygem 2.3 ..."
    # @see: https://www.server-world.info/en/note?os=CentOS_7&p=ruby23
    #       Also need git newer than 1.8.8, but https://github.com/iusrepo/git216/issues/5
    if git --version | grep 'git version 1.'; then
        _log "INFO" "Updating git for Rubygem ..."
        yum remove -y git*
        yum install -y https://packages.endpoint.com/rhel/7/os/x86_64/endpoint-repo-1.7-1.x86_64.rpm
        ${_yum_install} git
    fi
    # Enabling ruby 2.3 globally
    if [ ! -s /opt/rh/rh-ruby23/enable ]; then
        yum install -y rh-ruby23
    fi
    cat << EOF > /etc/profile.d/rh-ruby23.sh
#!/bin/bash
source /opt/rh/rh-ruby23/enable
export X_SCLS="`scl enable rh-ruby23 \"echo $X_SCLS\"`"
EOF
    # NOTE: At this moment, the newest cocoapods fails with "Failed to build gem native extension"
    _log "INFO" "*EXPERIMENTAL* Install cocoapods 1.8.4 ..."
    bash -l -c "gem install cocoapods -v 1.8.4" # To reload shell just in case
    _log "INFO" "Install go/golang and adding GO111MODULE=on ..."
    rpm --import https://mirror.go-repo.io/centos/RPM-GPG-KEY-GO-REPO
    curl -fL https://mirror.go-repo.io/centos/go-repo.repo --compressed > /etc/yum.repos.d/go-repo.repo
    yum install -y golang
    cat << EOF > /etc/profile.d/go-proxy.sh
export GO111MODULE=on
EOF
    #_log "INFO" "Install HOME/go/bin/dlv ..."
    #sudo -u testuser -i go get github.com/go-delve/delve/cmd/dlv    # '-i' is also required to reload profile
    _log "INFO" "Install conda ..."
    curl -fL -o /var/tmp/Miniconda3-latest-Linux-x86_64.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh --compressed && \
        bash /var/tmp/Miniconda3-latest-Linux-x86_64.sh -b -p /usr/local/miniconda3
    [ -L "/usr/local/bin/conda" ] && rm -v -f /usr/local/bin/conda
    [ ! -s "/usr/local/bin/conda" ] && ln -s /usr/local/miniconda3/bin/conda /usr/local/bin/conda
    _log "INFO" "Install helm3 ..."
    curl -fL -o /var/tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 --compressed
    bash /var/tmp/get_helm.sh
    if type git &>/dev/null; then
        _log "INFO" "Install git lfs ..."
        curl -sSf https://packagecloud.io/install/repositories/github/git-lfs/script.rpm.sh | sudo bash
        yum install -y git-lfs && git lfs install
    fi
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

function f_put_realms() {
    local _optional_realms=""
    f_api "/service/rest/v1/security/realms/active" | grep -q '"SamlRealm"' || _optional_realms=",\"SamlRealm\""
    f_api "/service/rest/v1/security/realms/active" "[\"NexusAuthenticatingRealm\",\"NexusAuthorizingRealm\",\"User-Token-Realm\",\"DockerToken\",\"ConanToken\",\"NpmToken\",\"NuGetApiKey\",\"LdapRealm\",\"rutauth-realm\"${_optional_realms}]" "PUT" || return $?
    # Removed ,"SamlRealm" as it adds extra popup to login
}

function f_nexus_csel() {
    local _csel_name="${1:-"csel-test"}"
    local _expression="${2:-"format == 'raw' and path =^ '/test/'"}" # TODO: currently can't use double quotes
    local _repos="${3:-"*"}"
    local _actions="${4:-"*"}"
    f_api "/service/rest/v1/security/content-selectors" "{\"name\":\"${_csel_name}\",\"description\":\"\",\"expression\":\"${_expression}\"}" || return $?
    f_apiS '{"action":"coreui_Privilege","method":"create","data":[{"id":"NX.coreui.model.Privilege-99","name":"'${_csel_name}'-priv","description":"","version":"","type":"repository-content-selector","properties":{"contentSelector":"'${_csel_name}'","repository":"'${_repos}'","actions":"'${_actions}'"}}],"type":"rpc"}'
}

# Create a test user and test role
function f_nexus_testuser() {
    local _userid="${1:-"testuser"}"
    local _privs="${2-"\"nx-repository-view-*-*-*\",\"nx-search-read\",\"nx-component-upload\""}" # NOTE: nx-usertoken-current does not work with OSS as no User Token
    local _role="${3-"test-role"}"
    if [ -n "${_role}" ]; then
        f_api "/service/rest/v1/security/roles" "{\"id\":\"${_role}\",\"name\":\"${_role} name\",\"description\":\"${_role} desc\",\"privileges\":[${_privs}],\"roles\":[]}"
    fi
    f_apiS '{"action":"coreui_User","method":"create","data":[{"userId":"'${_userid}'","version":"","firstName":"test","lastName":"user","email":"'${_userid}'@example.com","status":"active","roles":["'${_role:-"nx-anonymous"}'"],"password":"'${_userid}'"}],"type":"rpc"}'
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

function f_nexus_mount_volume() {
    local _mount="$1"
    local _v=""
    if [ -n "${_mount}" ]; then
        _v="${_v% } -v ${_mount%/}:/nexus-data"
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

    # A license file in local
    local _license="${r_NEXUS_LICENSE_FILE}"
    [ -z "${_license}" ] && _license="$(ls -1t ${_WORK_DIR%/}/sonatype/sonatype-*.lic 2>/dev/null | head -n1)"
    if [ -s "${_license}" ]; then
        [ -d "${_SHARE_DIR}" ] && cp -f "${_license}" "${_SHARE_DIR%/}/sonatype/"
        _upsert ${_sonatype_work%/}/etc/nexus.properties "nexus.licenseFile" "${_SHARE_DIR%/}/sonatype/$(basename "${_license}")" || return $?
    fi
}



# SAML server: https://github.com/hajimeo/samples/blob/master/golang/SamlTester/README.md
function f_start_saml_server() {
    local _service_metadata_url="${1:-"./service-metadata.xml"}"
    local _idp_base_url="${2:-"http://localhost:2080/"}"
    if [ -z "${_service_metadata_url}" ]; then
        echo "Please specify _service_metadata_url"; return 1
    fi
    local _cmd="simplesamlidp"
    if type ${_cmd} &>/dev/null; then
        if [ ! -s "${_SHARE_DIR%/}/simplesamlidp" ]; then
            curl -o "${_SHARE_DIR%/}/simplesamlidp" -L "https://github.com/hajimeo/samples/raw/master/misc/simplesamlidp_$(uname)_$(uname -m)" --compressed || return $?
            chmod u+x "${_SHARE_DIR%/}/simplesamlidp" || return $?
        fi
        _cmd="${_SHARE_DIR%/}/simplesamlidp"
    fi
    if [ ! -s ./simple-saml-idp.json ]; then
        curl -O -L "https://raw.githubusercontent.com/hajimeo/samples/master/misc/simple-saml-idp.json" --compressed  || return $?
    fi
    openssl req -x509 -newkey rsa:2048 -keyout ./myidp.key -out ./myidp.crt -days 365 -nodes -subj "/CN=$(hostname -f)"
    export IDP_KEY=./myidp.key IDP_CERT=./myidp.crt USER_JSON=./simple-saml-idp.json IDP_BASE_URL="${_idp_base_url}" SERVICE_METADATA_URL="${_service_metadata_url}"
    eval "${_cmd}"
}

function f_start_ldap_server() {
    local _fname="$(uname | tr '[:upper:]' '[:lower:]')$(uname -m).zip"
    if [ ! -s "${_SHARE_DIR%/}/${_fname}" ]; then
        curl -o "${_SHARE_DIR%/}/${_fname}" -L "https://github.com/glauth/glauth/releases/download/v2.1.0/${_fname}" --compressed || return $?
    fi
    if [ ! -s ./glauth/glauth ]; then
        unzip -d ./glauth "${_SHARE_DIR%/}/${_fname}"
        chmod u+x ./glauth/glauth || return $?
    fi
    if [ ! -s ./glauth/glauth-simple.cfg ]; then
        curl -o ./glauth/glauth-simple.cfg -L "https://raw.githubusercontent.com/hajimeo/samples/master/misc/glauth-simple.cfg" --compressed || return $?
    fi
    # listening 0.0.0.0:389
    ./glauth/glauth -c ./glauth/glauth-simple.cfg
}
function f_nexus_ldap_config() {
    local __doc__="Setup LDAP for GLAuth server."
    local _name="${1:-"glauth"}"
    local _host="${2:-"localhost"}"
    local _port="${3:-"389"}"   # 636
    #nc -z ${_host} ${_port} || return $?
    # Using 'mail' instead of 'uid' so that not confused with same 'admin' user between local and ldap
    f_apiS '{"action":"ldap_LdapServer","method":"create","data":[{"id":"","name":"'${_name}'","protocol":"ldap","host":"'${_host}'","port":"'${_port}'","searchBase":"dc=standalone,dc=localdomain","authScheme":"simple","authUsername":"admin@standalone.localdomain","authPassword":"secret12","connectionTimeout":"30","connectionRetryDelay":"300","maxIncidentsCount":"3","template":"Posix%20with%20Dynamic%20Groups","userBaseDn":"ou=users","userSubtree":true,"userObjectClass":"posixAccount","userLdapFilter":"","userIdAttribute":"mail","userRealNameAttribute":"cn","userEmailAddressAttribute":"mail","userPasswordAttribute":"","ldapGroupsAsRoles":true,"groupType":"dynamic","userMemberOfAttribute":"memberOf"}],"type":"rpc"}'
    f_apiS '{"action":"coreui_Role","method":"create","data":[{"version":"","source":"LDAP","id":"ipausers","name":"ipausers-role","description":"ipausers-role-desc","privileges":["nx-repository-view-*-*-*","nx-search-read","nx-component-upload"],"roles":[]}],"type":"rpc"}'
}

function f_repository_replication() {
    local __doc__="DEPRECATED Setup Repository Replication v1 using 'admin' user"
    local _src_repo="${1:-"raw-hosted"}"
    local _tgt_repo="${2:-"raw-repl-hosted"}"
    local _target_url="${3:-"http://$(hostname):8081/"}"
    local _src_blob="${4:-"${_BLOBTORE_NAME}"}"
    local _tgt_blob="${5:-"test"}"
    local _ds_name="${6:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _workingDirectory="${7:-"${_WORKING_DIR:-"/opt/sonatype/sonatype-work/nexus3"}"}"
    local _extra_sto_opt=""
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    curl -sS -f -k -I "${_target_url}" >/dev/null || return $?

    # It's OK if can't create blobs/repos as this could be due to permission.
    if ! _is_blob_available "${_src_repo}"; then
        f_apiS '{"action":"coreui_Blobstore","method":"create","data":[{"type":"File","name":"'${_src_blob}'","isQuotaEnabled":false,"attributes":{"file":{"path":"'${_src_blob}'"}}}],"type":"rpc"}' &> ${_TMP%/}/f_setup_repo_repl.out
    fi
    if ! _is_blob_available "${_tgt_repo}" "${_target_url}" ; then
        _NEXUS_URL="${_target_url}" f_apiS '{"action":"coreui_Blobstore","method":"create","data":[{"type":"File","name":"'${_tgt_blob}'","isQuotaEnabled":false,"attributes":{"file":{"path":"'${_tgt_blob}'"}}}],"type":"rpc"}' &> ${_TMP%/}/f_setup_repo_repl.out
    fi
    if ! _is_repo_available "${_src_repo}"; then
        f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_src_blob}'","writePolicy":"ALLOW","strictContentTypeValidation":false'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_src_repo}'","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}'
    fi
    if ! _is_repo_available "${_tgt_repo}" "${_target_url}" ; then
        _NEXUS_URL="${_target_url}" f_apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_tgt_blob}'","writePolicy":"ALLOW","strictContentTypeValidation":false'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_tgt_repo}'","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}'
    fi

    f_apiS '{"action":"capability_Capability","method":"create","data":[{"id":"NX.coreui.model.Capability-1","typeId":"replication","notes":"","enabled":true,"properties":{}}],"type":"rpc"}' && sleep 2
    # TODO: may not be working
    if ! f_api "/service/rest/beta/replication/connection/" '{"id":"","name":"'${_src_repo}'_to_'${_tgt_repo}'","sourceRepositoryName":"'${_src_repo}'","includeExistingContent":false,"destinationInstanceUrl":"'${_target_url}'","destinationInstanceUsername":"'${r_ADMIN_USER:-"${_ADMIN_USER}"}'","destinationInstancePassword":"'${r_ADMIN_PWD:-"${_ADMIN_PWD}"}'","destinationRepositoryName":"'${_tgt_repo}'","contentRegexes":[],"replicatedContent":"all"}' "POST"; then
        _log "ERROR" "Creating '${_src_repo}_to_${_tgt_repo}' failed."
    fi
    echo ""
    if [ -d "${_workingDirectory}" ]; then
        echo "# replication cli jar from '${_workingDirectory%/}../..'"
        find ${_workingDirectory%/}/../.. -maxdepth 4 -name 'nexus-replicator-cli-*.jar'
    fi
    echo "# Example config.yml for *file* type with '${_workingDirectory}'"
    cat << EOF
debug:
    true
sources:
  - path: ${_workingDirectory}/blobs/${_src_blob}/
    type: file
    targets:
      - path: ${_workingDirectory}/blobs/${_tgt_blob}/
        type: file
        repositoryName: ${_tgt_repo}
        connectionName: ${_src_repo}_to_${_tgt_repo}
EOF
}

function f_register_script() {
    local _script_file="$1"
    local _script_name="$2"
    [ -s "${_script_file%/}" ] || return 1
    [ -z "${_script_name}" ] && _script_name="$(basename ${_script_file} .groovy)"
    python -c "import sys,json;print(json.dumps(open('${_script_file}').read()))" > ${_TMP%/}/${_script_name}_$$.out || return $?
    echo "{\"name\":\"${_script_name}\",\"content\":$(cat ${_TMP%/}/${_script_name}_$$.out),\"type\":\"groovy\"}" > ${_TMP%/}/${_script_name}_$$.json
    # Delete if exists
    f_api "/service/rest/v1/script/${_script_name}" "" "DELETE"
    f_api "/service/rest/v1/script" "$(cat ${_TMP%/}/${_script_name}_$$.json)" || return $?
    echo "To run:
    curl -u admin -X POST -H 'Content-Type: text/plain' '${_NEXUS_URL%/}/service/rest/v1/script/${_script_name}/run' -d'{arg:value}'"
}

#f_upload_dummies "http://localhost:8081/repository/raw-hosted/manyfiles" "1432 10000" 8
function f_upload_dummies() {
    local __doc__="Upload text files into (raw) hosted repository"
    local _repo_path="${1:-"${_NEXUS_URL%/}/repository/raw-hosted/test"}"
    local _how_many="${2:-"10"}"
    local _parallel="${3:-"4"}"
    local _file_prefix="${4:-"test_"}"
    local _file_suffix="${5:-".txt"}"
    local _usr="${6:-"${_ADMIN_USER}"}"
    local _pwd="${7:-"${_ADMIN_PWD}"}"
    # _SEQ_START is for continuing
    local _seq_start="${_SEQ_START:-1}"
    local _seq_end="$((${_seq_start} + ${_how_many} - 1))"
    local _seq="seq ${_seq_start} ${_seq_end}"
    [[ "${_how_many}" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]] && _seq="seq ${_how_many}"
    # -T<(echo "aaa") may not work with some old bash, so creating a file
    for i in $(eval "${_seq}"); do
      echo "${_file_prefix}${i}${_file_suffix}"
    done | xargs -I{} -P${_parallel} curl -s -f -u "${_usr}:${_pwd}" -w '%{http_code} {} (%{time_total}s)\n' -T<(echo "test by f_upload_dummies at $(date +'%Y-%m-%d %H:%M:%S')") -L -k "${_repo_path%/}/{}"
    # NOTE: xargs only stops if exit code is 255
}

function f_upload_dummies_mvn() {
    local __doc__="Upload text files into (maven) hosted repository"
    local _repo_name="${1:-"maven-hosted"}"
    local _how_many="${2:-"10"}"
    local _parallel="${3:-"4"}"
    local _file_prefix="${4:-"test_"}"
    local _file_suffix="${5:-".txt"}"
    local _usr="${6:-"${_ADMIN_USER}"}"
    local _pwd="${7:-"${_ADMIN_PWD}"}"
    # _SEQ_START is for continuing
    local _seq_start="${_SEQ_START:-1}"
    local _seq_end="$((${_seq_start} + ${_how_many} - 1))"
    local _seq="seq ${_seq_start} ${_seq_end}"
    [[ "${_how_many}" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]] && _seq="seq ${_how_many}"
    local _filepath="${_TMP%/}/dummy.jar"
    if [ ! -s "${_filepath}" ]; then
        if type jar &>/dev/null; then
            echo "test by f_upload_dummies at $(date +'%Y-%m-%d %H:%M:%S')" > dummy.txt
            jar -cvf ${_filepath} dummy.txt || return $?
        else
            curl -o "${_filepath}" "https://repo1.maven.org/maven2/org/sonatype/goodies/goodies-i18n/2.3.4/goodies-i18n-2.3.4.jar" || return $?
        fi
    fi
    local _g="setup.nexus3.repos"
    local _a="dummy"
    # Does not work with Mac's bash...
    #export -f f_upload_asset
    for i in $(eval "${_seq}"); do
      echo "$i"
    done | xargs -I{} -P${_parallel} curl -s -f -u "${_usr}:${_pwd}" -w "%{http_code} ${_g}:${_a}:{} (%{time_total}s)\n" -H "accept: application/json" -H "Content-Type: multipart/form-data" -X POST -k "${_NEXUS_URL%/}/service/rest/v1/components?repository=${_repo_name}" -F maven2.groupId=${_g} -F maven2.artifactId=${_a} -F maven2.version={} -F maven2.asset1=@${_filepath} -F maven2.asset1.extension=jar
    # NOTE: xargs only stops if exit code is 255
}

function f_upload_dummies_npm() {
    local __doc__="Upload dummy tgz into (npm) hosted repository"
    local _repo_name="${1:-"npm-hosted"}"
    local _how_many="${2:-"10"}"
    local _pkg_name="${3:-"mytest"}"
    local _repo_url="${_NEXUS_URL%/}/repository/${_repo_name}/"
    local _seq_start="${_SEQ_START:-1}"
    local _seq_end="$((${_seq_start} + ${_how_many} - 1))"
    local _seq="seq ${_seq_start} ${_seq_end}"
    if ! type npm &>/dev/null; then
        echo "ERROR: this function requires 'npm' in the PATH"
        return 1
    fi
    local _dir="$(mktemp -d)"
    cat << EOF > "${_dir%/}/package.json"
{
    "author": "nxrm test",
    "description": "reproducing issue",
    "keywords": [],
    "license": "ISC",
    "main": "index.js",
    "name": "${_pkg_name}",
    "publishConfig": {
        "registry": "${_repo_url}"
    },
    "scripts": {
        "test": "echo \"Error: no test specified\" && exit 1"
    },
    "version": "1.0.0"
}
EOF
    cd "${_dir}"
    for i in $(eval "${_seq}"); do
      sed -i.tmp -E 's/"version": "1.[0-9].0"/"version": "1.'${i}'.0"/' ./package.json
      # TODO: should be parallel
      if ! npm publish --registry "${_repo_url}" -ddd; then
          echo "ERROR: may need 'npm Bearer Token Realm'"
          echo "       also 'npm adduser --registry ${_repo_url%/}/' (check ~/.npmrc as well)"
          cd -
          return 1
      fi
      sleep 1
    done
    cd -
    echo "To test:
    curl -O ${_repo_url%/}/${_pkg_name}
    npm cache clean --force
    npm pack --registry ${_repo_url%/}/ ${_pkg_name}"
}

# Example command to create with 4 concurrency and 500 each (=2000)
#for _i in {0..3}; do _SEQ_START=$((500 * ${_i} + 1)) f_upload_dummies_nuget "nuget-hosted" 500 & done
function f_upload_dummies_nuget() {
    local __doc__="Upload dummy .nupkg into (Nuget) hosted repository"
    local _repo_name="${1:-"nuget-hosted"}"
    local _how_many="${2:-"10"}"
    local _pkg_name="${3:-"HelloWorld"}"    # eg. AutoFixture.AutoNSubstitute for dependencies
    local _base_ver="${4:-"9.9"}"
    local _usr="${5:-"${_ADMIN_USER}"}"
    local _pwd="${6:-"${_ADMIN_PWD}"}"
    local _repo_url="${_NEXUS_URL%/}/repository/${_repo_name}/"
    local _seq_start="${_SEQ_START:-1}"
    local _seq_end="$((${_seq_start} + ${_how_many} - 1))"
    local _seq="seq ${_seq_start} ${_seq_end}"
    local _tmpdir="$(mktemp -d)"

    if [ ! -s "${_TMP%/}/${_pkg_name}.latest.nupkg" ]; then
        if ! curl -sf -L "https://www.nuget.org/api/v2/package/${_pkg_name}/" -o "${_TMP%/}/${_pkg_name}.latest.nupkg"; then
            _log "ERROR" "Downloading https://www.nuget.org/api/v2/package/${_pkg_name}/ failed ($?)"
            return 1
        fi
    fi
    local _nuspec="$(unzip -l "${_TMP%/}/${_pkg_name}.latest.nupkg" | grep -oE '[^ ]+\.nuspec$')"
    local _psmdcp="$(unzip -l "${_TMP%/}/${_pkg_name}.latest.nupkg" | grep -oE '[^ ]+\.psmdcp$')"
    #local _nuspec="$(find ${_TMP%/}/${_pkg_name} -type f -name '*.nuspec' -print | head -n1)"
    #local _psmdcp="$(find ${_TMP%/}/${_pkg_name} -type f -name '*.psmdcp' -print | head -n1)"
    if [ -z "${_nuspec}" ]; then
        _log "ERROR" "${_TMP%/}/${_pkg_name}.latest.nupkg does not have .nuspec file"
        return 1
    fi

    if [ ! -s "${_tmpdir%/}/${_nuspec}" ]; then
        unzip -d ${_tmpdir%/} "${_TMP%/}/${_pkg_name}.latest.nupkg" ${_nuspec} ${_psmdcp} || return $?
    fi
    #local _base_ver="$(sed -n -r 's@.*<version>(.+)</version>.*@\1@p' "${_nuspec}")"
    cp -v -f "${_TMP%/}/${_pkg_name}.latest.nupkg" "${_tmpdir%/}/${_pkg_name}.${_base_ver}.${_seq_start}.nupkg" || return $?
    for i in $(eval "${_seq}"); do
        sed -i.tmp -E 's@<version>.+</version>@<version>'${_base_ver}'.'$i'</version>@' "${_tmpdir%/}/${_nuspec}"
        sed -i.tmp -E 's@<version>.+</version>@<version>'${_base_ver}'.'$i'</version>@' "${_tmpdir%/}/${_psmdcp}"
        cd "${_tmpdir%/}" || return $?
        zip -q "./${_pkg_name}.${_base_ver}.${_seq_start}.nupkg" "${_nuspec}" "${_psmdcp}"
        local _rc=$?
        cd - >/dev/null
        [ ${_rc} != 0 ] && return ${_rc}
        # NOTE: Can't execute this curl in parallel (unlike other f_upload_dummies) because of using same file name.
        #       Use different _SEQ_START to make upload faster
        curl -s -f -u "${_usr}:${_pwd}" -o/dev/null -w "%{http_code} ${_pkg_name}.${_base_ver}.$i.nupkg (%{time_total}s)\n" -X PUT "${_repo_url%/}/" -F "package=@${_tmpdir%/}/${_pkg_name}.${_base_ver}.${_seq_start}.nupkg" || return $?
        #f_upload_asset "${_repo_name}" -F "nuget.asset=@${_TMP%/}/${_pkg_name}.${_base_ver}.$i.nupkg" || return $?
    done
}

function f_upload_dummies_rubygem() {
    local __doc__="Upload dummy .gem into rubygem hosted repository. Require 'ruby'"
    local _repo_name="${1:-"rubygem-hosted"}"
    local _how_many="${2:-"10"}"
    local _pkg_name="${3}"    # used with grep -E "\"${_pkg_name}\"" (eg. Checked (20), aws-sdk (1174))
    local _usr="${4:-"${_ADMIN_USER}"}"
    local _pwd="${5:-"${_ADMIN_PWD}"}"
    local _repo_url="${_NEXUS_URL%/}/repository/${_repo_name}/"
    local _seq_start="${_SEQ_START:-1}"
    local _seq_end="$((${_seq_start} + ${_how_many} - 1))"
    local _tmpdir="$(mktemp -d)"

    if [ ! -s /tmp/rubygem_specs.4.8.gz ] || [ ! -s /tmp/rubygem_specs.latest.txt ]; then
        curl -o /tmp/rubygem_specs.4.8.gz -f -L "https://rubygems.org/specs.4.8.gz" || return $?
        ruby -rpp -e 'pp Marshal.load(Gem.gunzip(File.read("/tmp/rubygem_specs.4.8.gz")))' > ${_tmpdir%/}/specs.latest.tmp || return $?
        grep -oE '"[^"][^"][^"]+", ?Gem::Version.new[^,]+' ${_tmpdir%/}/specs.latest.tmp > /tmp/rubygem_specs.latest.txt
        #cat /tmp/rubygem_specs.latest.txt | cut -d ',' -f1 | sort | uniq -c | grep -vE '^\s*[0-9]\s' | sort | head
    fi

    if [ -n "${_pkg_name}" ]; then
        grep -E "\"${_pkg_name}\"" /tmp/rubygem_specs.latest.txt | sed -n "${_seq_start},${_seq_end}p"
    else
        sed -n "${_seq_start},${_seq_end}p" /tmp/rubygem_specs.latest.txt
    fi | while read -r _pkg_ver; do
        [[ "${_pkg_ver}" =~ .*\"([^\"]+)\",[^\"]*\"([^\"]+)\" ]] || continue
        local _pkg="${BASH_REMATCH[1]}"
        local _ver="${BASH_REMATCH[2]}"
        local _url="https://rubygems.org/gems/${_pkg}-${_ver}.gem"
        curl -sf -w "Download: %{http_code} ${_pkg}-${_ver}.gem (%{time_total}s)\n" "${_url}" -o ${_tmpdir%/}/${_pkg}-${_ver}.gem || continue
        f_upload_asset "${_prefix}-hosted" -F rubygem.asset=@${_tmpdir%/}/${_pkg}-${_ver}.gem || return $?
        #curl -sf -w "Download: %{http_code} specs.4.8.gz (%{time_total}s | %{size_download}b)\n" -o/dev/null "${_repo_url%/}/specs.4.8.gz"
    done
}

function f_upload_dummies_helm() {
    local __doc__="Upload bitnami helm charts into helm hosted repository"
    local _repo_name="${1:-"helm-hosted"}"
    local _how_many="${2:-"10"}"
    local _pkg_name="${3}"      # used with grep -E "\b${_pkg_name}\b"
    local _usr="${4:-"${_ADMIN_USER}"}"
    local _pwd="${5:-"${_ADMIN_PWD}"}"
    local _repo_url="${_NEXUS_URL%/}/repository/${_repo_name}/"
    local _seq_start="${_SEQ_START:-1}"
    local _seq_end="$((${_seq_start} + ${_how_many} - 1))"
    local _tmpdir="$(mktemp -d)"
    # not using _tmpdir as don't want to download always
    if [ ! -s /tmp/helm_index.yaml ] || [ ! -s /tmp/helm_urls.out ]; then
        curl -o /tmp/helm_index.yaml -f -L "https://charts.bitnami.com/bitnami/index.yaml" || return $?
        grep -oE 'https://charts.bitnami.com/bitnami/.+\.tgz' /tmp/helm_index.yaml > /tmp/helm_urls.out
    fi
    if [ ! -s /tmp/helm_urls.out ]; then
        return 1
    fi

    if [ -n "${_pkg_name}" ]; then
        grep -E "\b${_pkg_name}\b" /tmp/helm_urls.out | sed -n "${_seq_start},${_seq_end}p"
    else
        sed -n "${_seq_start},${_seq_end}p" /tmp/helm_urls.out
    fi | while read -r _url; do
        _name="$(basename "${_url}")"
        if [ -n "${_pkg_name}" ] && ! echo "${_name}" | grep -qE "\b${_pkg_name}\b"; then
            continue
        fi
        curl -sf -w "Download: %{http_code} ${_name} (%{time_total}s)\n" "${_url}" -o ${_tmpdir%/}/helm-cart_tmp.tgz || continue
        curl -sf -w "Upload  : %{http_code} ${_name} (%{time_total}s)\n" -T ${_tmpdir%/}/helm-cart_tmp.tgz -u "${_usr}:${_pwd}" "${_repo_url%/}/${_name}" || return $?
        #curl -sf -w "Download: %{http_code} index.yaml (%{time_total}s | %{size_download}b)\n" -o/dev/null "${_repo_url%/}/index.yaml"
    done
}


# NOTE: below may not work with group repo:
# org.sonatype.nexus.repository.IllegalOperationException: Deleting from repository pypi-group of type pypi is not supported
function f_delete_asset() {
    local __doc__="Delete matching assets (not components) with Assets REST API (not Search)"
    local _force="$1"
    local _path_regex="$2"
    local _repo="$3"
    local _search_all="$4"
    local _max_loop="${5:-200}" # 50 * 200 = 10000 max
    rm -f ${_TMP%/}/${FUNCNAME}_*.out || return $?
    local _path="/service/rest/v1/assets"
    local _query=""
    local _base_query="?"
    [ -z "${_path_regex}" ] && return 11
    [ -z "${_repo}" ] && return 12  # repository is mandatory
    [ -n "${_repo}" ] && _base_query="?repository=${_repo}"
    for i in $(seq "1" "${_max_loop}"); do
        _API_SORT_KEYS=Y f_api "${_path}${_base_query}${_query}" > ${_TMP%/}/${FUNCNAME}_${i}.json || return $?
        grep -E '"(id|path)"' ${_TMP%/}/${FUNCNAME}_${i}.json | grep -E "\"${_path_regex}\"" -B1 > ${_TMP%/}/${FUNCNAME}_${i}_matched_IDs.out
        if [ $? -eq 0 ] && [[ ! "${_search_all}" =~ ^[yY] ]]; then
            break
        fi
        grep -qE '"continuationToken": *"[0-9a-f]+' ${_TMP%/}/${FUNCNAME}_${i}.json || break
        local cToken="$(cat ${_TMP%/}/${FUNCNAME}_${i}.json | python -c 'import sys,json;a=json.loads(sys.stdin.read());print(a["continuationToken"])')"
        _query="&continuationToken=${cToken}"
    done
    grep -E '^            "id":' -h ${_TMP%/}/${FUNCNAME}_*_matched_IDs.out | sort | uniq > ${_TMP%/}/${FUNCNAME}_$$.out || return $?
    local _line_num="$(cat ${_TMP%/}/${FUNCNAME}_$$.out | wc -l | tr -d '[:space:]')"
    if [[ ! "${_force}" =~ ^[yY] ]]; then
        read -p "Are you sure to delete matched (${_line_num}) assets?: " "_yes"
        echo ""
        [[ "${_yes}" =~ ^[yY] ]] || return
    fi
    cat ${_TMP%/}/${FUNCNAME}_$$.out | while read -r _l; do
        if [[ "${_l}" =~ \"id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            echo "# ${BASH_REMATCH[1]}"
            f_api "/service/rest/v1/assets/${BASH_REMATCH[1]}" "" "DELETE" || break
        fi
    done
    echo "Deleted ${_line_num} assets"
}
function f_delete_all_assets() {
    local __doc__="Delete all assets (not components) with Search REST API (require correct search index)"
    local _force="$1"
    local _repo="$2"
    local _max_loop="${3:-200}" # 50 * 200 = 10000 max
    rm -f ${_TMP%/}/${FUNCNAME}_*.out || return $?
    local _path="/service/rest/v1/search/assets"
    local _query=""
    local _base_query="?"
    [ -n "${_repo}" ] && _base_query="?repository=${_repo}"
    cat /dev/null > ${_TMP%/}/${FUNCNAME}_$$.out
    for i in $(seq "1" "${_max_loop}"); do
        f_api "${_path}${_base_query}${_query}" > ${_TMP%/}/${FUNCNAME}.json || return $?
        grep -E '^            "id":' -h ${_TMP%/}/${FUNCNAME}.json | sort | uniq >> ${_TMP%/}/${FUNCNAME}_$$.out || return $?
        grep -qE '"continuationToken": *"[0-9a-f]+' ${_TMP%/}/${FUNCNAME}.json || break
        local cToken="$(cat ${_TMP%/}/${FUNCNAME}.json | python -c 'import sys,json;a=json.loads(sys.stdin.read());print(a["continuationToken"])')"
        _query="&continuationToken=${cToken}"
    done
    local _line_num="$(cat ${_TMP%/}/${FUNCNAME}_$$.out | wc -l | tr -d '[:space:]')"
    if [[ ! "${_force}" =~ ^[yY] ]]; then
        read -p "Are you sure to delete all (${_line_num}) assets?: " "_yes"
        echo ""
        [[ "${_yes}" =~ ^[yY] ]] || return
    fi
    cat ${_TMP%/}/${FUNCNAME}_$$.out | while read -r _l; do
        if [[ "${_l}" =~ \"id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            echo "# ${BASH_REMATCH[1]}"
            f_api "/service/rest/v1/assets/${BASH_REMATCH[1]}" "" "DELETE" || break
        fi
    done
    echo "Deleted ${_line_num} assets (run Cleanup unused <format> blobs from <datastore> task)"
}

# K8s related but not in use yet | any more
function _pod_ready_waiter() {
    local _instance="${1}"
    local _namespace="${2:-"sonatype"}"
    local _n="${3:-"1"}"
    local _times="${4:-"90"}"
    local _interval="${5:-"6"}"
    for _x in $(seq 1 ${_times}); do
        sleep ${_interval}
        ${_KUBECTL} get -n ${_namespace} pods --field-selector="status.phase=Running" -l "app.kubernetes.io/instance=${_instance}" | grep -w "${_n}/${_n}" && return 0
    done
    return 1
}
function _update_name_resolution() {    # no longer in use but leaving as an example
    local _dns_server="$1"
    local _pod_prefix="${2:-"nxrm3-ha"}"
    local _namespace="${3:-"sonatype"}"
    local _app_name="${4:-"nexus-repository-manager"}"
    if [ -n "${_dns_server}" ] && hostname -I | grep -qw "${_dns_server}"; then
        local _hostfile="/etc/hosts"
        # TODO: at this moment, assuming this DNS server uses banner_add_hosts or /etc/hosts
        [ -f "/etc/banner_add_hosts" ] && _hostfile="/etc/banner_add_hosts"
        _update_hosts_for_k8s "${_hostfile}" "${_app_name}" "${_namespace}"
    else
        _k8s_exec "grep -wE '${_pod_prefix}.' /etc/hosts" "app.kubernetes.io/name=${_app_name}" "${_namespace}" "3" 2>/dev/null | sort | uniq > ${_TMP%/}/${_pod_prefix}_hosts.txt || return $?
        # If only one line or zero, no point of updating
        [ "$(grep -c -wE "${_pod_prefix}.\.pods" "${_TMP%/}/${_pod_prefix}_hosts.txt")" -lt 2 ] && return 0
        if _k8s_exec "echo -e \"\$(grep -vwE '${_pod_prefix}.\.pods' /etc/hosts)\n$(cat ${_TMP%/}/${_pod_prefix}_hosts.txt)\" > /etc/hosts" "app.kubernetes.io/name=${_app_name}" "${_namespace}" "3" 2>${_TMP%/}/${_pod_prefix}_hosts.err; then
            _log "INFO" "Pods /etc/hosts have been updated."
            cat ${_TMP%/}/${_pod_prefix}_hosts.txt
        else
            _log "WARN" "Couldn't update Pods /etc/hosts."
            cat ${_TMP%/}/${_pod_prefix}_hosts.err
        fi
    fi
}

# NOTE: currently this function is tested against support.zip boot-ed then migrated database
# Example export command (Using --no-owner and --clean, but not using --data-only as needs CREATE statements. -t with * requires PostgreSQL v12 or higher):
# Other interesting tables: -t "*_browse_node" -t "*deleted_blob*" -t "change_blobstore"
function f_export_postgresql_component() {
    local _workingDirectory="${1}"
    local _exportTo="${2:-"./component_db_$(date +"%Y%m%d%H%M%S").sql.gz"}"
    source "${_workingDirectory%/}/etc/fabric/nexus-store.properties" || return $?
    [[ "${jdbcUrl}" =~ jdbc:postgresql://([^:/]+):?([0-9]*)/([^\?]+) ]]
    local _dbhost="${BASH_REMATCH[1]}"
    local _dbport="${BASH_REMATCH[2]}"
    local _dbname="${BASH_REMATCH[3]}"
    local _fmt="*"
    PGPASSWORD="${password}" PGGSSENCMODE=disable pg_dump -h ${_dbhost} -p ${_dbport:-"5432"} -U ${username} -d ${_dbname} -c -O -t "repository" -t "${_fmt}_content_repository" -t "${_fmt}_component" -t "${_fmt}_component_tag" -t "${_fmt}_asset" -t "${_fmt}_asset_blob" -t "tag" -Z 6 -f "${_exportTo}"
}

# How to verify
#VACUUM(FULL, ANALYZE, VERBOSE);
#SELECT relname, reltuples as row_count_estimate FROM pg_class WHERE relnamespace ='public'::regnamespace::oid AND relkind = 'r' AND relname NOT LIKE '%_browse_%' AND (relname like '%repository%' OR relname like '%component%' OR relname like '%asset%') ORDER BY 2 DESC LIMIT 40;
function f_restore_postgresql_component() {
    local _workingDirectory="${1}"
    source "${_workingDirectory%/}/etc/fabric/nexus-store.properties" || return $?
    local _importFrom="${2}"
    [[ "${jdbcUrl}" =~ jdbc:postgresql://([^:/]+):?([0-9]*)/([^\?]+) ]]
    local _dbhost="${BASH_REMATCH[1]}"
    local _dbport="${BASH_REMATCH[2]}"
    local _dbname="${BASH_REMATCH[3]}"
    if [ -z "${_importFrom}" ]; then
        _importFrom="$(ls -1 ./component_db_*.sql.gz | tail -n1)"
        [ -z "${_importFrom}" ] && return 1
    fi
    (gunzip -c "${_importFrom}" | sed -E 's/^DROP TABLE ([^;]+);$/DROP TABLE \1 cascade;/') | PGPASSWORD="${password}" PGGSSENCMODE=disable psql -h ${_dbhost} -p ${_dbport:-"5432"} -U ${username} -d ${_dbname} -L ./psql_restore.log 2>./psql_restore.log
    grep -w ERROR ./psql_restore.log && return 1
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
            _ask "Nexus container name" "nexus${_ver_num}" "r_NEXUS_CONTAINER_NAME" "N" "N" "_is_container_name"
            _ask "Would you like to mount SonatypeWork directory?" "Y" "r_NEXUS_MOUNT" "N" "N"
            if _isYes "${r_NEXUS_MOUNT}"; then
                _ask "Mount to container:/nexus-data" "${_WORK_DIR%/}/sonatype/nexus-data_${r_NEXUS_CONTAINER_NAME%/}" "r_NEXUS_MOUNT_DIR" "N" "Y" "_is_existed"
            fi
            _ask "Nexus container exposing port for 8081 ('0' to disable docker port forward)" "8081" "r_NEXUS_CONTAINER_PORT1" "N" "Y" "_is_port_available"
            if [ -n "${r_NEXUS_CONTAINER_PORT1}" ] && [ "${r_NEXUS_CONTAINER_PORT1}" -gt 0 ]; then
                _ask "Nexus container exposing port for 8443 (HTTPS)" "8443" "r_NEXUS_CONTAINER_PORT2" "N" "N" "_is_port_available"
            fi
            _ask "Nexus license file path if you have:
If empty, it will try finding from ${_WORK_DIR%/}/sonatype/sonatype-*.lic" "" "r_NEXUS_LICENSE_FILE" "N" "N" "_is_license_path"
        fi
        _ask "Would you like to create another container with python, npm, mvn etc. client commands?" "N" "r_NEXUS_CLIENT_INSTALL" "N" "N"
    fi

    if _isYes "${r_NEXUS_INSTALL}"; then
        if [ -z "${r_NEXUS_CONTAINER_PORT1}" ] || [ "${r_NEXUS_CONTAINER_PORT1}" -gt 0 ]; then
            _ask "Nexus base URL" "http://localhost:${r_NEXUS_CONTAINER_PORT1:-"8081"}/" "r_NEXUS_URL" "N" "Y"
        elif [ -n "${r_NEXUS_CONTAINER_NAME}" ]; then
            _ask "Nexus base URL" "http://${r_NEXUS_CONTAINER_NAME}.${_DOMAIN#.}:8081/" "r_NEXUS_URL" "N" "Y"
        else
            _ask "Nexus base URL" "" "r_NEXUS_URL" "N" "Y"
        fi
    else
        _ask "Nexus base URL" "" "r_NEXUS_URL" "N" "Y" "_is_url_reachable"
    fi
    local _host="$(hostname -f)"
    [[ "${r_NEXUS_URL}" =~ ^https?://([^:/]+).+$ ]] && _host="${BASH_REMATCH[1]}"
    _ask "Blob store name" "${_BLOBTORE_NAME}" "r_BLOBSTORE_NAME" "N" "Y"
    _ask "Data store name ('nexus' if PostgreSQL, empty if OrientDB)" "${_DATASTORE_NAME}" "r_DATASTORE_NAME"
    _ask "Admin username" "${r_ADMIN_USER:-"${_ADMIN_USER}"}" "r_ADMIN_USER" "N" "Y"
    _ask "Admin password" "${r_ADMIN_PWD:-"${_ADMIN_PWD}"}" "r_ADMIN_PWD" "Y" "Y"
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
    local _nexus_url="${2:-"${r_NEXUS_URL:-"${_NEXUS_URL}"}"}"
    # At this moment, not always checking
    find ${_TMP%/}/ -type f -name '_does_repo_exist*.out' -mmin +5 -delete 2>/dev/null
    if [ ! -s ${_TMP%/}/_does_repo_exist$$.out ]; then
        _NEXUS_URL="${_nexus_url}" f_api "/service/rest/v1/repositories" | grep '"name":' > ${_TMP%/}/_does_repo_exist$$.out
    fi
    if [ -n "${_repo_name}" ]; then
        # case insensitive
        grep -iq "\"${_repo_name}\"" ${_TMP%/}/_does_repo_exist$$.out
    fi
}
function _is_blob_available() {
    local _bs_name="$1"
    local _nexus_url="${2:-"${r_NEXUS_URL:-"${_NEXUS_URL}"}"}"
    # At this moment, not always checking
    find ${_TMP%/}/ -type f -name '_does_blob_exist*.out' -mmin +5 -delete 2>/dev/null
    if [ ! -s ${_TMP%/}/_does_blob_exist$$.out ]; then
        _NEXUS_URL="${_nexus_url}" f_api "/service/rest/beta/blobstores" | grep '"name":' > ${_TMP%/}/_does_blob_exist$$.out
    fi
    if [ -n "${_bs_name}" ]; then
        # case insensitive
        grep -iq "\"${_bs_name}\"" ${_TMP%/}/_does_blob_exist$$.out
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

        local _tmp_ext_opts="-v ${_WORK_DIR%/}:${_SHARE_DIR}"
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

    _log "INFO" "Updating 'admin' user's password (may fail if already updated) ..."
    f_nexus_admin_pwd

    if ! _is_blob_available "${r_BLOBSTORE_NAME}"; then
        f_create_file_blobstore || return $?
    fi

    _log "INFO" "Resetting Realms to this script's default realms ..."
    f_put_realms

    for _f in `echo "${r_REPO_FORMATS:-"${_REPO_FORMATS}"}" | sed 's/,/ /g'`; do
        _log "INFO" "Executing f_setup_${_f} ..."
        if ! f_setup_${_f}; then
            _log "ERROR" "Executing setup for format:${_f} failed."
        fi
    done

    _log "INFO" "Adding a sample Content Selector (CSEL) ..."
    f_nexus_csel &>/dev/null  # it's OK if this fails
    _log "INFO" "Creating 'testuser' if it hasn't been created."
    f_nexus_testuser &>/dev/null
    #f_nexus_testuser "testuser" "\"csel-test-priv\"" "test-role"

    if _isYes "${r_NEXUS_CLIENT_INSTALL}"; then
        _log "INFO" "Installing a client container ..."
        p_client_container "" "" ""
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