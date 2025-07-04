#!/usr/bin/env bash
# BASH script to setup NXRM3 repositories.
# Based on functions in start_hdp.sh from 'samples' and install_sonatype.sh from 'work'.
#   bash <(curl -sSfL https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_nexus3_repos.sh --compressed) -A
#
# For local test:
#   _import() { source /var/tmp/share/sonatype/$1; } && export -f _import
#
# How to source:
#   source /dev/stdin <<< "$(curl -sSfL https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_nexus3_repos.sh --compressed)"
#   #export _NEXUS_URL="http://localhost:8081/"
#   _AUTO=true main
#
_DL_URL="${_DL_URL:-"https://raw.githubusercontent.com/hajimeo/samples/master"}"
type _import &>/dev/null || _import() { [ ! -s /tmp/${1} ] && curl -sf --compressed "${_DL_URL%/}/bash/$1" -o /tmp/${1}; . /tmp/${1}; }

_import "utils.sh"
_import "utils_db.sh"
_import "utils_container.sh"

function usage() {
    local _filename="$(basename $BASH_SOURCE)"
    echo "Main purpose of this script is to create repositories with some sample components.
Also functions in this script can be used for testing downloads and uploads.

#export _NEXUS_URL='http://SOME_REMOTE_NEXUS:8081/'
./${_filename} -A

DOWNLOADS:
    curl ${_DL_URL%/}/bash/${_filename} -o ${_WORK_DIR%/}/sonatype/${_filename}

REQUIREMENTS / DEPENDENCIES:
    'unzip', 'gunzip', 'curl'
    If Mac, 'gsed' and 'ggrep' are required (brew install gnu-sed grep)
    'python' is required for f_setup_cocoapods, f_register_script

COMMAND OPTIONS:
    -A
        Automatically setup repositories against _NEXUS_URL Nexus (best effort)
    -r <response_file_path>
        Specify your saved response file. Without -A, you can review your responses.
    -f <format1,format2,...>
        Comma separated repository formats.
        Default: ${_REPO_FORMATS}
    -v <nexus version>
        Install Nexus with this version number (eg: 3.24.0)
    -d <dbname>
        Existing PostgreSQL DB name or 'h2'

    -h list
        List all functions
    -h <function name>
        Show help of the function

EXAMPLE COMMANDS:
Start script with interview mode:
    sudo ${_filename}

Using default values and NO interviews:
    sudo ${_filename} -A

Create Nexus 3.24.0 and setup available formats:
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
"
}


## Global variables
: ${_REPO_FORMATS:="maven,pypi,npm,nuget,docker,yum,rubygem,helm,conda,cocoapods,bower,go,apt,r,p2,gitlfs,raw"}
#TODO: : ${_NO_ASSET_UPLOAD:=""}
: ${_ADMIN_USER:="admin"}
: ${_ADMIN_PWD:="admin123"}
: ${_DOMAIN:="standalone.localdomain"}
: ${_NEXUS_URL:="http://localhost:8081/"}   # or https://local.standalone.localdomain:8443/ for docker
: ${_NEXUS_DOCKER_HOSTNAME:="local.${_DOMAIN#.}"}
: ${_IQ_URL:="http://localhost:8070/"}
: ${_IQ_CLI_VER-"latest"}                   # If "" (empty), not download CLI jar
: ${_DOCKER_NETWORK_NAME:="nexus"}
: ${_SHARE_DIR:="/var/tmp/share"}
: ${_IS_NXRM2:="N"}
: ${_NO_DATA:="N"}          # To just create repositories
#: ${_NO_REPO_CREATE:="N"}
: ${_ASYNC_CURL:="N"}       # _get_asset won't wait for the result
: ${_BLOBTORE_NAME:=""}     # eg: default. Empty means auto
: ${_IS_NEWDB:=""}
: ${_DATASTORE_NAME:=""}    # If Postgres (or H2), needs to add attributes.storage.dataStoreName = "nexus"
: ${_EXTRA_STO_OPT:=""}
: ${_TID:=80}
## Misc. variables
_LOG_FILE_PATH="/tmp/setup_nexus3_repos.log"
_TMP="/tmp"  # for downloading/uploading assets
## Variables which used by command arguments
_AUTO=false
_DEBUG=false
_RESP_FILE=""
: "${_NEXUS_ENABLE_HA:=""}"
: "${_NEXUS_NO_AUTO_TASKS:=""}"


### Nexus installation functions ##############################################################################
# To re-install: _RECREATE_ALL=Y f_install_nexus3 "<version>" "<dbname>"
# To install HA instances (port is automatic): _NEXUS_ENABLE_HA=Y f_install_nexus3 "" "nxrmlatestha"
#     2nd node: _NEXUS_ENABLE_HA=Y _NXRM3_INSTALL_DIR="some_dir_path" f_install_nexus3 "" "nxrmlatestha"
# To upgrade (from ${_dirpath}/): tar -xvf $HOME/.nexus_executable_cache/nexus-3.79.1-04-mac-aarch_64.tar.gz
function f_install_nexus3() {
    local __doc__="Install specific NXRM3 version (to recreate sonatype-work and DB, _RECREATE_ALL=Y)"
    local _ver="${1:-"${r_NEXUS_VERSION}"}"     # 'latest' or '3.71.0-03-java17'
    local _dbname="${2-"${r_NEXUS_DBNAME}"}"   # If h2, use H2
    local _dbusr="${3-"nexus"}"     # Specifying default as do not want to create many users/roles
    local _dbpwd="${4-"${_dbusr}123"}"
    local _dbhost="${5}"               # Database hostname:port. If empty, $(hostname -f):5432
    local _port="${6-"${r_NEXUS_INSTALL_PORT:-"${_NXRM3_INSTALL_PORT}"}"}"      # If not specified, checking from 8081
    local _dirpath="${7-"${r_NEXUS_INSTALL_PATH:-"${_NXRM3_INSTALL_DIR}"}"}"    # If not specified, create a new dir under current dir
    local _download_dir="${8}"
    local _schema="${_DB_SCHEMA}"

    if [ -z "${_dbname}" ] && _isYes "${_NEXUS_ENABLE_HA:-"${r_NEXUS_ENABLE_HA}"}"; then
        _log "ERROR" "HA is requested but no DB name"
        return 1
    fi

    if [ -z "${_ver}" ] || [ "${_ver}" == "latest" ]; then
        # API: https://api.github.com/repos/sonatype/nexus-public/tags does not contain latest
        _ver="$(curl -s -I https://github.com/sonatype/nexus-public/releases/latest | sed -n -E '/^location/ s/^location: http.+\/release-([0-9\.-]+).*$/\1/p')"
    fi
    [ -z "${_ver}" ] && return 1
    if [ -z "${_port}" ]; then
        _port="$(_find_port "8081" "" "^8082$")"
        [ -z "${_port}" ] && return 1
        if [ "${_port}" != "8081" ]; then
            _log "WARN" "Using port: *** ${_port} ***"; sleep 1
        fi
    fi
    if [ -n "${_dbname}" ]; then
        if [[ "${_dbname}" =~ _ ]]; then
            _log "WARN" "PostgreSQL allows '_' but not this function, so removing"
            _dbname="$(echo "${_dbname}" | tr -d '_')"
        fi
        # I think PostgreSQL doesn't work with mixed case.
        _dbname="$(echo "${_dbname}" | tr '[:upper:]' '[:lower:]')"
    fi
    if [ -z "${_dirpath}" ]; then
        _dirpath="./nxrm_${_ver}"
        [ -n "${_dbname}" ] && _dirpath="${_dirpath}_${_dbname}"
        #[ "${_port}" != "8081" ] && _dirpath="${_dirpath}_${_port}"
    fi

    if [[ "${_RECREATE_ALL}" =~ [yY] ]] && ! _isYes "${_NEXUS_ENABLE_HA:-"${r_NEXUS_ENABLE_HA}"}"; then
        if [ -d "${_dirpath%/}" ]; then
            _log "WARN" "Removing ${_dirpath%/} (to avoid set _RECREATE_ALL='N')"; sleep 3
            rm -v -rf "${_dirpath%/}" || return $?
        fi
        [ -z "${_RECREATE_DB}" ] && _RECREATE_DB="Y"
    fi
    # If no `-\d\d`, appending the wildcard to pick from the local cache (downloading fails)
    local _tgz_ver="${_ver}"
    [[ "${_ver}" =~ ^3\.[0-9]+\.[0-9]+$ ]] && _tgz_ver="${_ver}-*"
    local _os="unix"
    local _arch="$(uname -m)"
    local _ext="tar.gz"
    if [ "$(uname -s)" == "Darwin" ]; then
        _os="mac"
        if [[ ! "${_ver}" =~ ^3\.(7[89]|[89]).* ]]; then
            _ext="tgz"
        fi
    fi
    local _tgz_name="nexus-${_tgz_ver}-${_os}.${_ext}"
    if [[ "${_ver}" =~ ^3\.(79\.[1-9]|[89][0-9]\.|[1-9][0-9][0-9]).* ]]; then
        # From version 3.79.1, nexus-3.79.1-04-linux-aarch_64.tar.gz
        [ "$(uname -s)" == "Linux" ] && _os="linux"
        [ "${_arch}" = "x86_64" ] && _arch="x86_64"
        [ "${_arch}" = "arm64" ] && _arch="aarch_64"
        _tgz_name="nexus-${_tgz_ver}-${_os}-${_arch}.${_ext}"
    elif [[ "${_ver}" =~ ^3\.(78|79\.0).* ]]; then
        # From version 3.78 and until 3.79.0, nexus-unix-x86-64-3.78.0-14.tar.gz
        [ "${_arch}" = "x86_64" ] && _arch="x86-64"
        [ "${_arch}" = "arm64" ] && _arch="aarch64"
        _tgz_name="nexus-${_os}-${_arch}-${_tgz_ver}.${_ext}"
    elif [[ "${_ver}" =~ ^3\.70\..* ]]; then
        # 3.70.x offers java8 and java11, so using java8, also if macOS, tgz...
        #https://download.sonatype.com/nexus/3/nexus-3.70.4-02-java8-mac.tgz
        _tgz_name="nexus-${_tgz_ver}-java8-${_os}.${_ext}"
    fi
    # download-staging.sonatype.com
    _prepare_install "${_dirpath}" "https://download.sonatype.com/nexus/${_ver%%.*}/${_tgz_name}" "${r_NEXUS_LICENSE_FILE}" || return $?

    if [ ! -d ${_dirpath%/}/sonatype-work/nexus3/etc/fabric ]; then
        mkdir -p ${_dirpath%/}/sonatype-work/nexus3/etc/fabric || return $?
    fi
    local _prop="${_dirpath%/}/sonatype-work/nexus3/etc/nexus.properties"
    if [ ! -f "${_prop}" ]; then
        touch "${_prop}" || return $?
    fi

    _upsert "${_prop}" "application-port" "${_port}" || return $?
    local _license_path="${_LICENSE_PATH}"
    if [ ! -s "${_license_path}" ]; then
        _log "WARN" "No license file: ${_license_path}"; sleep 3
    else
        _upsert "${_prop}" "nexus.licenseFile" "${_license_path}" || return $?
    fi
    if _isYes "${_NEXUS_ENABLE_HA:-"${r_NEXUS_ENABLE_HA}"}"; then
        _log "INFO" "For HA, 'nexus.datastore.clustered.enabled=true' and 'nexus.zero.downtime.enabled=true'"
        _upsert "${_prop}" "nexus.datastore.clustered.enabled" "true" || return $?
        _upsert "${_prop}" "nexus.zero.downtime.enabled" "true" || return $?
        #TODO: This property does not change the nexus node name
        local _cluster_name="$(basename "${_dirpath%/}")"   # assuming the directory name is unique
        _upsert "${_prop}" "nexus.clustered.nodeName" "${_cluster_name}" || return $?
    fi
    # optional
    _upsert "${_prop}" "nexus.security.randompassword" "false" || return $?
    _upsert "${_prop}" "nexus.onboarding.enabled" "false" || return $?
    _upsert "${_prop}" "nexus.scripts.allowCreation" "true" || return $?
    if ! _isYes "${_NEXUS_NO_AUTO_TASKS:-"${r_NEXUS_NO_AUTO_TASKS}"}"; then
        _upsert "${_prop}" "nexus.elasticsearch.autoRebuild" "false" || return $?
        _upsert "${_prop}" "nexus.search.updateIndexesOnStartup.enabled" "false" || return $?
        _upsert "${_prop}" "nexus.browse.component.tree.automaticRebuild" "false" || return $?
    fi

    if [ -n "${_dbname}" ]; then
        _upsert "${_prop}" "nexus.datastore.enabled" "true" || return $?
        if [[ "${_dbname}" =~ [hH]2 ]]; then
            _log "INFO" "Using H2 database"
        else
            if [ -z "${_dbhost}" ]; then
                _log "INFO" "Creating database with \"${_dbusr}\" \"********\" \"${_dbname}\" \"${_schema}\" in localhost:5432"
                if ! _RECREATE_DB=${_RECREATE_DB:-"N"} _postgresql_create_dbuser "${_dbusr}" "${_dbpwd}" "${_dbname}" "${_schema}"; then
                    _log "WARN" "Failed to create ${_dbusr} or ${_dbname}" || return $?
                fi
                _dbhost="$(hostname -f):5432"
            fi
            cat << EOF > "${_dirpath%/}/sonatype-work/nexus3/etc/fabric/nexus-store.properties"
jdbcUrl=jdbc\:postgresql\://${_dbhost//:/\\:}/${_dbname}?targetServerType=primary
username=${_dbusr}
password=${_dbpwd}
schema=${_schema:-"public"}
maximumPoolSize=40
advanced=maxLifetime\=30000
EOF
        fi
    fi

    cd "${_dirpath%/}" || return $?

    if [[ ! "${_NO_HTTPS}" =~ [yY] ]]; then
        local _ssl_port="$(_find_port "8443")"
        _log "INFO" "Setting up HTTPS on port ${_ssl_port}"
        f_setup_https "" "${_ssl_port}" || return $?
    fi

    if [[ "${_ver}" =~ ^3\.(7[1-9]\.|[89][0-9]\.|[1-9][0-9][0-9]).+ ]]; then
        if [ -d "${JAVA_HOME_17}" ]; then
            export JAVA_HOME="${JAVA_HOME_17}"
            _log "INFO" "Export-ed JAVA_HOME=\"${JAVA_HOME_17}\""
        else
            _log "WARN" "Make sure JAVA_HOME is set to Java 17"
        fi
    fi

    echo "To start: ./nexus-${_ver}/bin/nexus run"
    type nxrmStart &>/dev/null && echo "      Or: nxrmStart"
    if [ "${_port}" != "8081" ]; then
        echo "      May need to execute 'export _NEXUS_URL=\"http://localhost:${_port}/\"'"
    fi
    _isYes "${_NEXUS_ENABLE_HA:-"${r_NEXUS_ENABLE_HA}"}" && _log "WARN" "Make sure 'blobs' use fullpath or symlinked"
}

function f_uninstall_nexus3() {
    local __doc__="Uninstall NXRM3 by deleting database and directory"
    local _dirpath="${1}"
    if [ ! -d "${_dirpath%/}" ] || [[ ! "${_dirpath}" =~ [/]*nxrm_ ]]; then
        echo "Incorrect _dirpath"
        return 1
    fi
    local _nexus_store="$(find ${_dirpath%/} -mindepth 5 -maxdepth 5 -name 'nexus-store.properties' 2>/dev/null | head -n1)"
    if [ -n "${_nexus_store}" ]; then
        if grep -q ':postgresql' ${_nexus_store}; then
            source ${_nexus_store}
            [[ "${jdbcUrl}" =~ jdbc:postgresql://([^:/]+):?([0-9]*)/([^\?]+) ]] && _DBHOST="${BASH_REMATCH[1]}" _DBPORT="${BASH_REMATCH[2]}" _DBNAME="${BASH_REMATCH[3]}" _DBUSER="${username}" _DBSCHEMA="${schema:-"public"}" PGPASSWORD="${password}"
            local _pcmd="psql -h ${_DBHOST} -p ${_DBPORT:-"5432"} -U ${_DBUSER} -d template1 -c \"DROP DATABASE ${_DBNAME}\""
            echo "${_pcmd}"; sleep 3
            eval "PGPASSWORD="${password}" ${_pcmd}" || return $?
        fi
    fi
    rm -rf -v "${_dirpath%/}"
}


### Repository setup functions ################################################################################
# Eg: r_NEXUS_URL="http://dh1.standalone.localdomain:8081/" f_setup_xxxxx
# TODO: ,"replication":{"preemptivePullEnabled":false}
function f_setup_maven() {
    local __doc__="Create Maven2 proxy/hosted/group repositories with dummy data"
    local _prefix="${1:-"maven"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _source_nexus_url="${4:-"${r_SOURCE_NEXUS_URL:-"${_SOURCE_NEXUS_URL}"}"}"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    local _extra_sto_opt="$(_get_extra_sto_opt "${_ds_name}")"
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        # NOTE: I prefer "maven":{...,"contentDisposition":"ATTACHMENT"...}, but using default for various testings.
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"MIXED","layoutPolicy":"PERMISSIVE"},"proxy":{"remoteUrl":"https://repo1.maven.org/maven2/","contentMaxAge":-1,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"maven2-proxy"}],"type":"rpc"}' || return $?
        echo "NOTE: if 'IQ: Audit and Quarantine' is needed for ${_prefix}-proxy (set _IQ_URL)"
        echo "      f_iq_quarantine \"${_prefix}-proxy\""
        echo "      ${_NEXUS_URL%/}/repository/${_prefix}-proxy/org/sonatype/maven-policy-demo/1.3.0/maven-policy-demo-1.3.0.jar"
        # NOTE: com.fasterxml.jackson.core:jackson-databind:2.9.3 should be quarantined if IQ is configured. May need to delete the component first
        #f_get_asset "maven-proxy" "com/fasterxml/jackson/core/jackson-databind/2.9.3/jackson-databind-2.9.3.jar" "test.jar"
        #_get_asset_NXRM2 central "com/fasterxml/jackson/core/jackson-databind/2.9.3/jackson-databind-2.9.3.jar" "test.jar"
    fi
    # add some data for xxxx-proxy
    # If NXRM2: _get_asset_NXRM2 "${_prefix}-proxy" "junit/junit/4.12/junit-4.12.jar"
    _ASYNC_CURL="Y" f_get_asset "${_prefix}-proxy" "junit/junit/4.12/junit-4.12.pom"
    f_get_asset "${_prefix}-proxy" "junit/junit/4.12/junit-4.12.jar" "${_TMP%/}/junit-4.12.jar"
    # TODO: https://repo1.maven.org/maven2/org/sonatype/maven-policy-demo/

    if [ -n "${_source_nexus_url}" ] && [ -n "${_extra_sto_opt}" ] && ! _is_repo_available "${_prefix}-repl-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"MIXED","layoutPolicy":"PERMISSIVE"},"proxy":{"remoteUrl":"'${_source_nexus_url%/}'/repository/'${_prefix}'-hosted/","contentMaxAge":60,"metadataMaxAge":60},"replication":{"preemptivePullEnabled":true,"assetPathRegex":""},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":true}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-repl-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"maven2-proxy"}],"type":"rpc"}' || return $?
    fi

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"MIXED","layoutPolicy":"PERMISSIVE"},"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW_ONCE","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"maven2-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    if [ -s "${_TMP%/}/junit-4.12.jar" ]; then
        #mvn deploy:deploy-file -DgroupId=junit -DartifactId=junit -Dversion=4.21 -DgeneratePom=true -Dpackaging=jar -DrepositoryId=nexus -Durl=${r_NEXUS_URL}/repository/${_prefix}-hosted -Dfile=${_TMP%/}/junit-4.12.jar
        _ASYNC_CURL="Y" f_upload_asset "${_prefix}-hosted" -F maven2.groupId=com.example -F maven2.artifactId=my-test-junit -F maven2.version=4.21 -F maven2.asset1=@${_TMP%/}/junit-4.12.jar -F maven2.asset1.extension=jar
        if curl -sf -o ${_TMP%/}/junit-4.12-sources.jar "https://repo1.maven.org/maven2/junit/junit/4.12/junit-4.12-sources.jar"; then
            _ASYNC_CURL="Y" f_upload_asset "${_prefix}-hosted" -F maven2.groupId=com.example -F maven2.artifactId=my-test-junit -F maven2.version=4.21 -F maven2.asset1=@${_TMP%/}/junit-4.12-sources.jar -F maven2.asset1.extension=jar -F maven2.asset1.classifier=sources
        fi
        _ASYNC_CURL="Y" f_upload_asset "${_prefix}-hosted" -F maven2.groupId=com.example -F maven2.artifactId=my-test-junit -F maven2.version=9.99 -F maven2.asset1=@${_TMP%/}/junit-4.12.jar -F maven2.asset1.extension=jar
    fi

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        # Hosted first
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"maven2-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group ("." in groupdId should be changed to "/")
    if [ -s "${_TMP%/}/junit-4.12.jar" ]; then
        _ASYNC_CURL="Y" f_upload_asset "${_prefix}-hosted" -F maven2.groupId=junit -F maven2.artifactId=junit -F maven2.version=99.99 -F maven2.asset1=@${_TMP%/}/junit-4.12.jar -F maven2.asset1.extension=jar >/dev/null
        _ASYNC_CURL="Y" f_get_asset "${_prefix}-group" "junit/junit/maven-metadata.xml"
    fi
}

function f_setup_pypi() {
    local __doc__="Create Pypi proxy/hosted/group repositories with dummy data"
    local _prefix="${1:-"pypi"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    local _extra_sto_opt="$(_get_extra_sto_opt "${_ds_name}")"
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://pypi.org/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"pypi-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    _ASYNC_CURL="Y" f_get_asset "${_prefix}-proxy" "packages/unit/0.2.2/Unit-0.2.2.tar.gz"
    # NOTE: https://pypi.org/project/python-policy-demo/#history
    #for i in {1..3}; do f_get_asset "pypi-proxy" "packages/python_policy_demo/1.$i.0/python_policy_demo-1.$i.0-py3-none-any.whl"; done

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW_ONCE","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"pypi-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    if [ -s "${_TMP%/}/mydummyproject-3.0.0.tar.gz" ] || curl -sf -o ${_TMP%/}/mydummyproject-3.0.0.tar.gz -L "https://github.com/hajimeo/samples/raw/master/misc/mydummyproject-3.0.0.tar.gz"; then
        _ASYNC_CURL="Y" f_upload_asset "${_prefix}-hosted" -F "pypi.asset=@${_TMP%/}/mydummyproject-3.0.0.tar.gz"
    fi
    # add some data for xxxx-hosted
    if [ -s "${_TMP%/}/mydummyproject-3.0.0-py3-none-any.whl" ] || curl -sf -o ${_TMP%/}/mydummyproject-3.0.0-py3-none-any.whl -L "https://github.com/hajimeo/samples/raw/master/misc/mydummyproject-3.0.0-py3-none-any.whl"; then
        _ASYNC_CURL="Y" f_upload_asset "${_prefix}-hosted" -F "pypi.asset=@${_TMP%/}/mydummyproject-3.0.0-py3-none-any.whl"
    fi
    # To test a pypi group metadata merge
    if [ -s "${_TMP%/}/Unit-9.9.9.tar.gz" ] || curl -sf -o ${_TMP%/}/Unit-9.9.9.tar.gz -L "https://github.com/hajimeo/samples/raw/master/misc/Unit-9.9.9.tar.gz"; then
        _ASYNC_CURL="Y" f_upload_asset "${_prefix}-hosted" -F "pypi.asset=@${_TMP%/}/Unit-9.9.9.tar.gz"
    fi

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        # Hosted first
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"pypi-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    _ASYNC_CURL="Y" f_get_asset "${_prefix}-group" "packages/pyyaml/5.3.1/PyYAML-5.3.1.tar.gz"
}

function f_setup_p2() {
    local __doc__="Create Maven2 proxy repository with dummy data"
    local _prefix="${1:-"p2"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    local _extra_sto_opt="$(_get_extra_sto_opt "${_ds_name}")"
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://download.eclipse.org/releases/2019-09/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"dataStoreName":"nexus","blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"'${_prefix}'-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    _ASYNC_CURL="Y" f_get_asset "${_prefix}-proxy" "p2.index"
    _ASYNC_CURL="Y" f_get_asset "${_prefix}-proxy" "compositeContent.jar"
}

function f_setup_npm() {
    local __doc__="Create NPM proxy/hosted/group repositories with dummy data"
    local _prefix="${1:-"npm"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _source_nexus_url="${4:-"${r_SOURCE_NEXUS_URL:-"${_SOURCE_NEXUS_URL}"}"}"
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    local _extra_sto_opt="$(_get_extra_sto_opt "${_ds_name}")"
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://registry.npmjs.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"npm-proxy"}],"type":"rpc"}' || return $?
        echo "NOTE: if 'IQ: Audit and Quarantine' is needed for ${_prefix}-proxy (set _IQ_URL)"
        echo "      f_iq_quarantine \"${_prefix}-proxy\""
    fi
    # add some data for xxxx-proxy
    #_ASYNC_CURL="Y" f_get_asset "${_prefix}-proxy" "lodash/-/lodash-4.17.19.tgz"
    _ASYNC_CURL="Y" f_get_asset "${_prefix}-proxy" "es5-ext/-/es5-ext-0.10.62.tgz"
    _ASYNC_CURL="Y" f_get_asset "${_prefix}-proxy" "@sonatype/policy-demo/-/policy-demo-2.0.0.tgz" # Good (normal) one
    #for i in {1..3}; do f_get_asset "npm-proxy" "@sonatype/policy-demo/-/policy-demo-2.$i.0.tgz"; done

    if [ -n "${_source_nexus_url}" ] && [ -n "${_extra_sto_opt}" ] && ! _is_repo_available "${_prefix}-repl-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"npm":{"removeNonCataloged":false,"removeQuarantinedVersions":false},"proxy":{"remoteUrl":"'${_source_nexus_url%/}'/repository/'${_prefix}'-hosted/","contentMaxAge":60,"metadataMaxAge":60},"replication":{"preemptivePullEnabled":true,"assetPathRegex":""},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":true}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-repl-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"npm-proxy"}],"type":"rpc","tid"' || return $?
    fi

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW_ONCE","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"npm-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    for i in {1..3}; do # 2.0.0 is used in npm-proxy, 1.0.0 will be used in npm-prop-hosted
        if [ ! -s "${_TMP%/}/sonatype-policy-demo-2.${i}.0.tgz" ]; then
            curl -sSf -o "${_TMP%/}/sonatype-policy-demo-2.${i}.0.tgz" -L "https://registry.npmjs.org/@sonatype/policy-demo/-/policy-demo-2.${i}.0.tgz" || continue
        fi
        _ASYNC_CURL="Y" f_upload_asset "${_prefix}-hosted" -F "npm.asset=@${_TMP%/}/sonatype-policy-demo-2.${i}.0.tgz"
    done

    # If no xxxx-prop-hosted (proprietary | namespace confusion protection), create it (from 3.30)
    # https://help.sonatype.com/integrations/iq-server-and-repository-management/iq-server-and-nxrm-3.x/preventing-namespace-confusion
    # https://help.sonatype.com/iqserver/managing/policy-management/reference-policy-set-v6
    if ! _is_repo_available "${_prefix}-prop-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW_ONCE","strictContentTypeValidation":true'${_extra_sto_opt}'},"component":{"proprietaryComponents":true},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-prop-hosted","format":"","type":"","url":"","online":true,"recipe":"npm-hosted"}],"type":"rpc"}' # || return $? # this would fail if version is not 3.30
    fi
    if [ ! -s "${_TMP%/}/sonatype-policy-demo-1.0.0.tgz" ]; then
        curl -sSf -o "${_TMP%/}/sonatype-policy-demo-1.0.0.tgz" -L "https://registry.npmjs.org/@sonatype/policy-demo/-/policy-demo-1.0.0.tgz"
    fi
    if [ -s "${_TMP%/}/sonatype-policy-demo-1.0.0.tgz" ]; then
        _ASYNC_CURL="Y" f_upload_asset "${_prefix}-prop-hosted" -F "npm.asset=@${_TMP%/}/sonatype-policy-demo-1.0.0.tgz"
        #f_iq_quarantine "npm-proxy"
        # Need to delete 2.0.0 (normal) from npm-proxy and restart Nexus to start firewall.proprietary.name.sync ...
        #curl -sSf -D- -o/dev/null -L "${_NEXUS_URL%/}/repository/npm-proxy/@sonatype/policy-demo/-/policy-demo-2.0.0.tgz"
    fi

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        # Hosted first
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"npm-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    #f_get_asset "${_prefix}-group" "grunt/-/grunt-1.1.0.tgz"
    _ASYNC_CURL="Y" f_get_asset "${_prefix}-group" "@sonatype/policy-demo"
}

function f_setup_nuget() {
    local __doc__="Create Nuget V2|V3 proxy/hosted/group repositories with dummy data"
    local _prefix="${1:-"nuget"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    local _extra_sto_opt="$(_get_extra_sto_opt "${_ds_name}")"
    _log "NOTE" "v3.29 and higher added \"nugetVersion\":\"V3\", so please check if nuget proxy repos have correct version from Web UI."
    if ! _is_repo_available "${_prefix}-v2-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"nugetProxy":{"nugetVersion":"V2","queryCacheItemMaxAge":3600},"proxy":{"remoteUrl":"https://www.nuget.org/api/v2/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-v2-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"nuget-proxy"}],"type":"rpc"}'
    fi
    _ASYNC_CURL="Y" f_get_asset "${_prefix}-v2-proxy" "/HelloWorld/1.3.0.15"
    if ! _is_repo_available "${_prefix}-v3-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"nugetProxy":{"nugetVersion":"V3","queryCacheItemMaxAge":3600},"proxy":{"remoteUrl":"https://api.nuget.org/v3/index.json","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-v3-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"nuget-proxy"}],"type":"rpc"}'
    fi
    # add some data for xxxx-proxy
    f_get_asset "${_prefix}-v3-proxy" "index.json"  # This one may fail on some older Nexus version
    f_get_asset "${_prefix}-v3-proxy" "/v3/content/test/2.0.1.1/test.2.0.1.1.nupkg" "${_TMP%/}/test.2.0.1.1.nupkg"  # this one may fail on some older Nexus version

    if ! _is_repo_available "${_prefix}-ps-proxy"; then # Need '"nugetVersion":"V2",'?
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"nugetProxy":{"nugetVersion":"V2","queryCacheItemMaxAge":3600},"proxy":{"remoteUrl":"https://www.powershellgallery.com/api/v2","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-ps-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"nuget-proxy"}],"type":"rpc"}'
    fi
    # TODO: should add "https://www.myget.org/F/workflow" as well?

    if ! _is_repo_available "${_prefix}-choco-proxy"; then # Need '"nugetVersion":"V2",'?
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"nugetProxy":{"nugetVersion":"V2","queryCacheItemMaxAge":3600},"proxy":{"remoteUrl":"https://chocolatey.org/api/v2/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-choco-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"nuget-proxy"}],"type":"rpc"}'
    fi

    # Nexus should have nuget.org-proxy, nuget-group, and nuget-hosted already, so creating only v3 one
    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"nuget-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    if [ -s "${_TMP%/}/test.2.0.1.1.nupkg" ]; then
        _ASYNC_CURL="Y" f_upload_asset "${_prefix}-hosted" -F "nuget.asset=@${_TMP%/}/test.2.0.1.1.nupkg"
    fi

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-v3-group"; then
        # Hosted first
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-v3-proxy"]}},"name":"'${_prefix}'-v3-group","format":"","type":"","url":"","online":true,"recipe":"nuget-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group. This may not work if proxy is directly used
    _ASYNC_CURL="Y" f_get_asset "${_prefix}-v3-group" "/v3/content/nlog/3.1.0/nlog.3.1.0.nupkg"  # this one may fail on some Nexus version
}

function f_test_nuget_with_dotnet_restore() {
    local __doc__="Test downloading against Nuget repositories with dotnet restore"
    local _nuget_url="${1:-"https://api.nuget.org/v3/index.json"}"
    local _work_dir="${2:-"${_TMP%/}/dotnet"}"
    local _project_name="${3:-"MyTestProject"}"
    local _not_clear_all="${4}"
    if ! type dotnet &>/dev/null; then
        _log "WARN" "dotnet is not installed. Please install it."
        return 1
    fi

    if [ ! -d "${_work_dir}" ]; then
        mkdir -p "${_work_dir}" || return $?
    fi
    if [ ! -f "${_work_dir%/}/${_project_name%/}${_project_name}.csproj" ]; then
        dotnet new console -o "${_work_dir%/}/${_project_name}" || return $?
    fi
    cat << EOF > "${_work_dir%/}/${_project_name%/}${_project_name}.csproj"
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net7.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Swashbuckle.AspNetCore" Version="7.2.0" />
  </ItemGroup>
</Project>
EOF
    local _configfile=""
    if [ -n "${_nuget_url}" ]; then
        local _v="2"
        [[ "${_nuget_url}" =~ /index.json ]] && _v="3"
        cat << EOF > "${_work_dir%/}/${_project_name%/}nuget.config"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <add key="nuget_test" value="${_nuget_url}" protocolVersion="${_v}" />
    </packageSources>
</configuration>
EOF
       _configfile="--configfile \"${_work_dir%/}/${_project_name%/}nuget.config\""
    fi
    if [[ ! "${_not_clear_all}" =~ ^[Yy] ]]; then
        dotnet nuget locals --clear all
    fi
    eval "dotnet restore --no-cache ${_configfile} \"${_work_dir%/}/${_project_name%/}${_project_name}.csproj\""
    # TODO: Unable to load the service index for source http://localhost:8081/repository/nuget.org/index.json
}

#_NEXUS_URL=http://node3281.standalone.localdomain:8081/ f_setup_docker
function f_setup_docker() {
    local __doc__="Create Docker proxy/hosted/group repositories with dummy data"
    local _prefix="${1:-"docker"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _source_nexus_url="${4:-"${r_SOURCE_NEXUS_URL:-"${_SOURCE_NEXUS_URL}"}"}"
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    local _extra_sto_opt="$(_get_extra_sto_opt "${_ds_name}")"
    #local _opts="--tls-verify=false"    # TODO: only for podman. need an *easy* way to use http for 'docker'

    # NOTE: How to test Docker subdomain connector https://help.sonatype.com/en/docker-subdomain-connector.html
    #curl -I -H 'Host: docker-proxy.${_DOMAIN#.}:8443' "${_NEXUS_URL%/}/repository/docker-proxy/v2/"

    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        # "httpPort":18178 - 18179
        # https://issues.sonatype.org/browse/NEXUS-26642 contentMaxAge -1
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":18178,"httpsPort":18179,"forceBasicAuth":false,"v1Enabled":true},"proxy":{"remoteUrl":"https://registry-1.docker.io","contentMaxAge":-1,"metadataMaxAge":1440},"dockerProxy":{"indexType":"HUB","cacheForeignLayers":false,"useTrustStoreForIndexAccess":false},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"docker-proxy"}],"type":"rpc"}' || return $?
    fi
    if ! _is_repo_available "${_prefix}-quay-proxy"; then
        # "httpPort":18168 - 18169. For v1 test. cacheForeignLayers is true
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":18168,"httpsPort":18169,"forceBasicAuth":false,"v1Enabled":true},"proxy":{"remoteUrl":"https://quay.io","contentMaxAge":-1,"metadataMaxAge":1440},"dockerProxy":{"indexType":"REGISTRY","cacheForeignLayers":true,"useTrustStoreForIndexAccess":false},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-quay-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"docker-proxy"}],"type":"rpc"}' || return $?
        #curl https://quay.io/v2/coreos/clair/manifests/v2.1.2|grep schemaVersion
        # Need docker version older than 27
        #docker pull local.standalone.localdomain:18169/coreos/clair:v2.1.2
    fi

    if [ -n "${_source_nexus_url}" ] && [ -n "${_extra_sto_opt}" ] && ! _is_repo_available "${_prefix}-repl-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":null,"httpsPort":null,"forceBasicAuth":false,"v1Enabled":true},"proxy":{"remoteUrl":"'${_source_nexus_url%/}'/repository/'${_prefix}'-hosted/","contentMaxAge":-1,"metadataMaxAge":60},"replication":{"preemptivePullEnabled":true,"assetPathRegex":""},"dockerProxy":{"indexType":"HUB","cacheForeignLayers":false,"useTrustStoreForIndexAccess":false},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":true}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-repl-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"docker-proxy"}],"type":"rpc"}' || return $?
    fi

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        # Using "httpPort":18181 - 18182,
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":18181,"httpsPort":18182,"forceBasicAuth":true,"v1Enabled":true},"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"docker-hosted"}],"type":"rpc"}' || return $?
    fi

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        # Using "httpPort":4999, httpsPort: 15000
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"httpPort":4999,"httpsPort":15000,"forceBasicAuth":true,"v1Enabled":true},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"groupWriteMember":"'${_prefix}'-hosted","memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"docker-group"}],"type":"rpc"}' || return $?
    fi


    # add some data for xxxx-proxy
    _log "INFO" "Populating ${_prefix}-proxy repository with some image ..."
    if ! _populate_docker_proxy; then
        _log "WARN" "_populate_docker_proxy failed. May need f_setup_https (and FQDN) or 'Docker Bearer Token Realm' (not only for anonymous access)."
    fi

    # add some data for xxxx-hosted
    _log "INFO" "Populating ${_prefix}-hosted repository with some image ..."
    if ! _populate_docker_hosted; then
        _log "WARN" "_populate_docker_hosted failed. May need f_setup_https (and FQDN) or 'Docker Bearer Token Realm' (not only for anonymous access)."
    fi
    if type helm &>/dev/null; then
        if [ -s "${_TMP%/}/helm-oci-demo-0.1.0.tgz" ] || curl -sf -o ${_TMP%/}/helm-oci-demo-0.1.0.tgz -L "https://github.com/hajimeo/samples/raw/refs/heads/master/misc/helm-oci-demo-0.1.0.tgz"; then
            #_log "INFO" "Populating ${_prefix}-hosted repository with demo helm chart (OCI) ..."
            if ! helm registry login ${_NEXUS_DOCKER_HOSTNAME}:18182 -u "${_ADMIN_USER}" -p "${_ADMIN_PWD}"; then
                _log "WARN" "helm registry login ${_NEXUS_DOCKER_HOSTNAME}:18182 failed."
            else
                if ! helm push ${_TMP%/}/helm-oci-demo-0.1.0.tgz oci://${_NEXUS_DOCKER_HOSTNAME}:18182/oci-demo; then #--debug
                    _log "WARN" "Populating ${_prefix}-hosted repository with demo helm chart (OCI) failed."
                else
                    # The 'title' or 'name' is 'demo' in Chart.yaml, not "helm-oci-demo"
                    _log "TODO" "helm show all oci://${_NEXUS_DOCKER_HOSTNAME}:18182/oci-demo/demo --version 0.1.0"
                    _log "TODO" "helm pull oci://${_NEXUS_DOCKER_HOSTNAME}:18182/oci-demo/demo --version 0.1.0"
                fi
            fi
        fi
    fi

    # add some data for xxxx-group
    _log "INFO" "Populating ${_prefix}-group repository with some image via docker proxy repo ..."
    _populate_docker_proxy "hello-world" "" "15000 4999"
}

#_populate_docker_proxy "" "m1mac.standalone.localdomain:15000"
function _populate_docker_proxy() {
    local _img_name="${1:-"alpine:3.7"}"    # To test OCI image: jenkins/jenkins:lts
    local _host_port="${2:-"${r_DOCKER_PROXY:-"${r_DOCKER_GROUP:-"${r_NEXUS_URL:-"${_NEXUS_DOCKER_HOSTNAME:-"${_NEXUS_URL}"}"}"}"}"}"
    local _backup_ports="${3-"18179 18178 15000 443"}"
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
# Example 1: RHEL UBI9 image
#   _populate_docker_hosted "redhat/ubi9:9.4-1181" "local.standalone.localdomain:18182"
# Example 2: with ssh port forwarding
#   ssh -2CNnqTxfg -L18182:localhost:18182 node3250    #ps aux | grep 2CNnqTxfg
#   _populate_docker_hosted "" "local.standalone.localdomain:18182"
# Example 3: *Group* repo test by creating an image which uses blobs from proxy (pull & push from group repo)
#   # After deleting alpine_hosted (and 'docker system prune -a -f'):
#   _populate_docker_hosted "local.standalone.localdomain:15000/alpine:latest" "local.standalone.localdomain:15000"
#   _TAG_TO="thrivent-web/doi-invite:latest" _populate_docker_hosted "local.standalone.localdomain:15000/alpine:latest" "local.standalone.localdomain:15000"
function _populate_docker_hosted() {
    local _base_img="${1:-"alpine:latest"}"    # dh1.standalone.localdomain:15000/alpine:3.7
    local _host_port="${2:-"${r_DOCKER_PROXY:-"${r_DOCKER_GROUP:-"${r_NEXUS_URL:-"${_NEXUS_DOCKER_HOSTNAME:-"${_NEXUS_URL}"}"}"}"}"}"
    local _tag_to="${3:-"${_TAG_TO}"}"
    local _num_layers="${4:-"${_NUM_LAYERS:-"1"}"}" # Can be used to test overwriting image
    local _backup_ports="${5-"18182 18181 15000 443"}"
    local _cmd="${6-"${r_DOCKER_CMD}"}"
    local _usr="${7:-"${_ADMIN_USER}"}"
    local _pwd="${8:-"${_ADMIN_PWD}"}"
    [ -z "${_cmd}" ] && _cmd="$(_docker_cmd)"
    [ -z "${_cmd}" ] && return 0    # If no docker command, just exist

    if [[ ! "${_DOCKER_NO_LOGIN}" =~ [yY] ]]; then
        _log "INFO" "docker login ${_host_port}"
        _host_port="$(_docker_login "${_host_port}" "${_backup_ports}" "${_usr}" "${_pwd}" "${_cmd}")" || return $?
    fi

    if [ -z "${_tag_to}" ]; then
        _tag_to="dummy-img-n${_num_layers}:latest"
    fi
    if ${_cmd} images --format "{{.Repository}}:{{.Tag}}" | grep -qE "^${_host_port%/}/${_tag_to}$"; then
        _log "INFO" "'${_host_port%/}/${_tag_to}' already exists. Skipping the build ..."
    else
        # NOTE: docker build -f does not work (bug?)
        local _build_dir="${HOME%/}/${FUNCNAME[0]}_build_tmp_dir_$(date +'%Y%m%d%H%M%S')"  # /tmp or /var/tmp fails on Ubuntu
        if [ ! -d "${_build_dir%/}" ]; then
            mkdir -v -p ${_build_dir} || return $?
        fi
        cd ${_build_dir} || return $?
        local _build_str="FROM ${_base_img}"
        # Crating random (multiple) layer. NOTE: 'CMD' doesn't create new layers.
        #echo -e "FROM alpine:3.7\nRUN apk add --no-cache mysql-client\nCMD echo 'Built ${_tag_to} from image:${_base_img}' > Dockerfile
        for i in $(seq 1 ${_num_layers}); do
            #\nRUN apk add --no-cache mysql-client
            _build_str="${_build_str}\nRUN echo 'Adding layer ${i} for ${_tag_to} at $(date +'%Y%m%d%H%M%S') (R${RANDOM})' > /var/tmp/layer_${i}"
        done
        echo -e "${_build_str}" > Dockerfile
        ${_cmd} build --rm -t ${_tag_to} .
        local _rc=$?
        cd -  && mv -v ${_build_dir} ${_TMP%/}/
        if [ ${_rc} -ne 0 ]; then
            _log "ERROR" "'${_cmd} build --rm -t ${_tag_to} .' failed (${_rc}, ${_TMP%/}/$(basename "${_build_dir}"))"
            return ${_rc}
        fi
    fi

    # It seems newer docker appends "localhost/" so trying this one first.
    if ! ${_cmd} tag localhost/${_tag_to} ${_host_port}/${_tag_to} 2>/dev/null; then
        _log "INFO" "docker tag ${_tag_to} ${_host_port}/${_tag_to}"
        ${_cmd} tag ${_tag_to} ${_host_port}/${_tag_to} || return $?
    fi
    _log "INFO" "${_cmd} push ${_host_port}/${_tag_to}"
    ${_cmd} push ${_host_port}/${_tag_to} || return $?
    #${_cmd} rmi ${_host_port}/${_tag_to} || return $?  # this leaves <none> images
}

function f_setup_yum() {
    local __doc__="Create Yum(rpm) proxy/hosted/group repositories with dummy data"
    local _prefix="${1:-"yum"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _yum_upload_path="${_YUM_UPLOAD_PATH:-"Packages"}"
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    local _extra_sto_opt="$(_get_extra_sto_opt "${_ds_name}")"
    # NOTE: due to the known limitation, some version of Nexus requires anonymous for yum repo
    # https://support.sonatype.com/hc/en-us/articles/213464848-Authenticated-Access-to-Nexus-from-Yum-Doesn-t-Work
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        # http://mirror.centos.org/centos/ is dead
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://vault.centos.org/7.9.2009/os/x86_64/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"yum-proxy"}],"type":"rpc"}' || return $?
    fi
    # Add some data for xxxx-proxy (Ubuntu has "yum" command)
    # NOTE: using 'yum' command is a bit too slow, so not using at this moment, but how to
    #   _echo_yum_repo_file "${_prefix}-proxy" > /etc/yum.repos.d/nexus-yum-test.repo
    #   yum --disablerepo="*" --enablerepo="nexusrepo-test" install --downloadonly --downloaddir=${_TMP%/} dos2unix
    f_get_asset "${_prefix}-proxy" "Packages/dos2unix-6.0.3-7.el7.x86_64.rpm" "${_TMP%/}/dos2unix-6.0.3-7.el7.x86_64.rpm"

    # This site is no longer working
    #if ! _is_repo_available "${_prefix}-epel-proxy"; then
    #    _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://dl.fedoraproject.org/pub/epel/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-epel-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"yum-proxy"}],"type":"rpc"}' || return $?
    #fi

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        # NOTE: using '3' for repodataDepth because of using 7/os/x86_64/Packages (x86_64 is 3rd)
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"yum":{"repodataDepth":0,"deployPolicy":"PERMISSIVE"},"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"yum-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    local _upload_file=""   #$(_rpm_build "test-rpm" "9.9.9" "1" 2>/dev/null)
    if [ -s "${_TMP%/}/test-rpm-9.9.9-1.noarch.rpm" ] || curl -sSf -L -o ${_TMP%/}/test-rpm-9.9.9-1.noarch.rpm "https://github.com/hajimeo/samples/raw/master/misc/test-rpm-9.9.9-1.noarch.rpm"; then
        _upload_file=${_TMP%/}/test-rpm-9.9.9-1.noarch.rpm
    fi
    if [ ! -s "${_upload_file}" ]; then
        _upload_file="$(find -L ${_TMP%/} -type f -size +1k -name "*.rpm" 2>/dev/null | head -n1)"
    fi
    if [ ! -s "${_upload_file}" ]; then
        if curl -sSf -L -o ${_TMP%/}/aether-api-1.13.1-13.el7.noarch.rpm "https://vault.centos.org/7.9.2009/os/x86_64/Packages/aether-api-1.13.1-13.el7.noarch.rpm"; then
            _upload_file=${_TMP%/}/aether-api-1.13.1-13.el7.noarch.rpm
        fi
    fi
    if [ -s "${_upload_file}" ]; then
        # NOTE: curl also works
        #curl -D/dev/stderr -u admin:admin123 "${_NEXUS_URL%/}/repository/${_prefix}-hosted/Packages/" -T ${_upload_file}
        _ASYNC_CURL="Y" f_upload_asset "${_prefix}-hosted" -F "yum.asset=@${_upload_file}" -F "yum.asset.filename=$(basename ${_upload_file})" -F "yum.directory=${_yum_upload_path%/}"
    fi
    #curl -u 'admin:admin123' --upload-file /etc/pki/rpm-gpg/RPM-GPG-KEY-pmanager ${r_NEXUS_URL%/}/repository/yum-hosted/RPM-GPG-KEY-pmanager

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"yum-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    #f_get_asset "${_prefix}-group" "7/os/x86_64/Packages/$(basename ${_upload_file})"
    #f_get_asset "${_prefix}-hosted" "7/os/x86_64/repodata/repomd.xml"
    #f_get_asset "${_prefix}-proxy" "7/os/x86_64/repodata/repomd.xml"
    # This can be very slow ...
    _ASYNC_CURL="Y" f_get_asset "${_prefix}-group" "7/os/x86_64/repodata/repomd.xml"
}
function _rpm_build() {
    # https://stackoverflow.com/questions/880227/what-is-the-minimum-i-have-to-do-to-create-an-rpm-file
    local __doc__="Create a simple RPM package, and echo the rpm file name (so no stdout from other)"
    local _name="${1:-"foobar"}"
    local _version="${2:-"1.0"}"
    local _release="${3:-"1"}"
    local _work_dir="${4:-"."}"
    _work_dir="$(readlink -f "${_work_dir}")"
    if ! type rpmbuild &>/dev/null; then
        _log "ERROR" "rpmbuild is not available. Please install rpm-build package (brew install rpm)"
        return 1
    fi

    local _tmpdir="$(mktemp -d)"
    cd ${_tmpdir} || return $?

    if [ -s "${HOME%/}/.rpmmacros" ] && [ ! -s "${HOME%/}/.rpmmacros_$$" ]; then
        cp -v -p "${HOME%/}/.rpmmacros" "${HOME%/}/.rpmmacros_$$" >&2
    fi
    cat << EOF > ${HOME%/}/.rpmmacros
%_topdir   ${_work_dir%/}/rpmbuild
%_tmppath  %{_topdir}/tmp
EOF
    mkdir -p ./{RPMS,SRPMS,BUILD,SOURCES,SPECS,tmp}
    cat << EOF > ./SPECS/${_name}.spec
Summary: A very simple toy bin rpm package
Name: ${_name}
Version: ${_version}
Release: ${_release}
License: GPL+
Group: ${_name}-group
BuildArch: noarch

%description
%{summary}

%prep
# Empty section.

%clean
# Empty section.

%files
%defattr(-,root,root,-)
EOF
    rpmbuild -bb ./SPECS/${_name}.spec >&2
    local _rc="$?"
    find ${_work_dir%/}/rpmbuild/RPMS -type f -name "${_name}-${_version}-${_release}.*.rpm"
    [ -s "${HOME%/}/.rpmmacros_$$" ] && mv -f "${HOME%/}/.rpmmacros_$$" "${HOME%/}/.rpmmacros" >&2
    cd - &>/dev/null
    return ${_rc}
}
function _echo_yum_repo_file() {
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
    local __doc__="Create Rubygems proxy/hosted/group repositories with dummy data"
    local _prefix="${1:-"rubygem"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    local _extra_sto_opt="$(_get_extra_sto_opt "${_ds_name}")"
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://rubygems.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"rubygems-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    #local _nexus_url="${r_NEXUS_URL:-"${_NEXUS_URL}"}"
    #_gen_gemrc "${_nexus_url%/}/repository/${_prefix}-proxy" "/tmp/gemrc" "" "${r_ADMIN_USER:-"${_ADMIN_USER}"}:${r_ADMIN_PWD:-"${_ADMIN_PWD}"}"
    #gem fetch loudmouth --config-file /tmp/gemrc
    #gem fetch loudmouth --clear-sources -s http://admin:admin123@localhost:8081/repository/rubygem-proxy/ -V --debug

    #f_get_asset "${_prefix}-proxy" "latest_specs.4.8.gz" "${_TMP%/}/specs.4.8.gz"
    #f_get_asset "${_prefix}-proxy" "latest_specs.4.8.gz" "${_TMP%/}/latest_specs.4.8.gz"
    f_get_asset "${_prefix}-proxy" "gems/loudmouth-0.2.4.gem" "${_TMP%/}/loudmouth-0.2.4.gem"

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW_ONCE","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"rubygems-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    if [ -s "${_TMP%/}/loudmouth-0.2.4.gem" ]; then
        _ASYNC_CURL="Y" f_upload_asset "${_prefix}-hosted" -F rubygem.asset=@${_TMP%/}/loudmouth-0.2.4.gem
    fi

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"rubygems-group"}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out || return $?
    fi
    _ASYNC_CURL="Y" f_get_asset "${_prefix}-group" "gems/CFPropertyList-3.0.3.gem"
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
    else
        if [ ! -f "${HOME%/}/.gem/credentials" ]; then
            cat << EOF > "${HOME%/}/.gem/credentials"
---
:rubygems_api_key: dummy
EOF
            chmod 600 "${HOME%/}/.gem/credentials"
        fi
    fi
}

function f_setup_helm() {
    local __doc__="Create Helm proxy/hosted repositories with dummy data"
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
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://charts.bitnami.com/bitnami","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"helm-proxy"}],"type":"rpc"}' || return $?
    fi
    if ! _is_repo_available "${_prefix}-sonatype-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://sonatype.github.io/helm3-charts","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-sonatype-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"helm-proxy"}],"type":"rpc"}' || return $?
        #curl -O "https://sonatype.github.io/helm3-charts/nexus-iq-server-174.0.0.tgz"
        # At least from 3.74, path stopped working
        #curl -D- -u admin:admin123 "http://localhost:8081/repository/helm-hosted/" -T nexus-iq-server-174.0.0.tgz
    fi
    # add some data for xxxx-proxy
    f_get_asset "${_prefix}-proxy" "/mysql-9.4.1.tgz" "${_TMP%/}/mysql-9.4.1.tgz"

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"helm-hosted","format":"","type":"","url":"","online":true,"recipe":"'${_prefix}'-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    # https://issues.sonatype.org/browse/NEXUS-31326
    [ -s "${_TMP%/}/mysql-9.4.1.tgz" ] && curl -sf -u "${r_ADMIN_USER:-"${_ADMIN_USER}"}:${r_ADMIN_PWD:-"${_ADMIN_PWD}"}" "${_NEXUS_URL%/}/repository/${_prefix}-hosted/" -T "${_TMP%/}/mysql-9.4.1.tgz"
}

function f_setup_bower() {
    local __doc__="Create Bower proxy repository with dummy data"
    local _prefix="${1:-"bower"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"bower":{"rewritePackageUrls":true},"proxy":{"remoteUrl":"https://registry.bower.io","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"bower-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    _ASYNC_CURL="Y" f_get_asset "${_prefix}-proxy" "/jquery/versions.json"
    # TODO: hosted and group
}

function f_setup_conan() {
    local __doc__="Create Conan proxy/hosted repositories with dummy data"
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
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://center.conan.io/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"conan-proxy"}],"type":"rpc"}' || return $?
        #conan remote add conan-proxy "${_NEXUS_URL%/}/repository/conan-proxy" --force
    fi
    # TODO: add some data for xxxx-proxy
    # conan download zlib/1.2.12@ -r conan-proxy
    # From 3.74, conan v2 support
    if ! _is_repo_available "${_prefix}-v2-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"conan":{"conanVersion":"V2"},"proxy":{"remoteUrl":"https://center2.conan.io","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"conan-proxy"}],"type":"rpc"}'
        #conan remote add conan-v2-proxy "${_NEXUS_URL%/}/repository/conan-v2-proxy" --force
    fi

    # If no xxxx-hosted, create it. From 3.35, so it's OK to fail
    if ! _is_repo_available "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW"'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"conan-hosted"}],"type":"rpc"}' || return $?
    fi
    _upload_to_conan_hosted2 "${_prefix}"
    return 0    # ignore the last function failure
}
function _upload_to_conan_hosted() {
    # https://github.com/conan-io/docs/blob/develop2/tutorial/creating_packages/create_your_first_package.rst
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
    # $HOME/.conan/profiles/default
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
    CONAN_LOGIN_USERNAME="${_ADMIN_USER}" CONAN_PASSWORD="${_ADMIN_PWD}" conan upload --confirm --all --retry 0 -r="${_prefix}-hosted" ${_pkg_ver}@${_usr_stable}
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
function _upload_to_conan_hosted2() {
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
    #conan remote remove ${_prefix}-hosted
    conan remote add ${_prefix}-hosted "${_NEXUS_URL%/}/repository/${_prefix}-hosted" --force || return $?

    local _pkg="hello"
    local _ver="0.2"
    local _usr_stable="demo/testing"
    local _build_dir="$(mktemp -d)"
    cd "${_build_dir}" || return $?
    if [ ! -s "$HOME/.conan2/profiles/default" ]; then
        conan profile detect || return $?
        sed -i.bak -e 's|compiler.version=.*|compiler.version=15|' $HOME/.conan2/profiles/default
    fi
    conan new cmake_lib -d name=${_pkg} -d version=${_ver} || return $?
    if ! conan create . ; then  # -s arch=x86_64 -s os=Linux
        cd -
        return 1
    fi
    CONAN_LOGIN_USERNAME="${_ADMIN_USER}" CONAN_PASSWORD="${_ADMIN_PWD}" conan upload -r "${_prefix}-hosted" ${_pkg}/${_ver}
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
    local __doc__="Create Conda proxy repository"
    local _prefix="${1:-"conda"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it (NOTE: No HA)
    if ! _is_repo_available "${_prefix}-proxy"; then
        # Or https://repo.anaconda.com/pkgs/ or https://repo.continuum.io/pkgs/ or https://conda.anaconda.org/
        # At this moment, https://conda.anaconda.org/conda-forge/ is not working with `/main` in the client config
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://conda.anaconda.org/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"conda-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    _ASYNC_CURL="Y" f_get_asset "${_prefix}-proxy" "main/linux-64/pytest-3.10.1-py37_0.tar.bz2"
}

function f_setup_cocoapods() {
    local __doc__="Create Cocoapod proxy repository with dummy data"
    local _prefix="${1:-"cocoapods"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it (NOTE: No HA, but seems to work with HA???)
    if ! _is_repo_available "${_prefix}-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://cdn.cocoapods.org/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"cocoapods-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    # add some data for xxxx-proxy
    local _name="SDWebImage"
    local _ver="5.9.3"
    local _podspec_path="$(python -c "import hashlib
n=\"${_name}\";v=\"${_ver}\"
md5=hashlib.md5()
md5.update(n.encode('utf-8'))
h=md5.hexdigest()
print(\"Specs/%s/%s/%s/%s/%s/%s.podspec.json\" % (h[0],h[1],h[2],n,v,n))")"
    #curl -v -LO http://dh1:8081/repository/cocoapods-proxy/Specs/1/1/7/SDWebImage/5.9.3/SDWebImage.podspec.json
    f_get_asset "${_prefix}-proxy" "${_podspec_path}" "${_TMP%/}/${_name}.podspec.json"
    #curl -v -LO http://dh1:8081/repository/cocoapods-proxy/pods/SDWebImage/5.9.3/5.9.3.tar.gz
    local _url_tar_gz="$(cat "${_TMP%/}/${_name}.podspec.json" | python -c "import sys,json;print(json.load(sys.stdin)['source']['http'])")"
    if [ -n "${_url_tar_gz}" ]; then
        curl -sf -u "${r_ADMIN_USER:-"${_ADMIN_USER}"}:${r_ADMIN_PWD:-"${_ADMIN_PWD}"}" -I "${_url_tar_gz}"
    else
        _ASYNC_CURL="Y" f_get_asset "${_prefix}-proxy" "pods/${_name}/${_ver}/${_ver}.tar.gz"
    fi
}

function f_setup_go() {
    local __doc__="Create Golang proxy repositories with dummy data"
    local _prefix="${1:-"go"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it (NOTE: No HA support)
    if ! _is_repo_available "${_prefix}-proxy"; then
        # https://gonexus.dev/ was deprecated
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://proxy.golang.org/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"go-proxy"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-proxy
    # Workaround for https://issues.sonatype.org/browse/NEXUS-21642
    if ! _is_repo_available "gosum-raw-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"raw":{"contentDisposition":"ATTACHMENT"},"proxy":{"remoteUrl":"https://sum.golang.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"gosum-raw-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"raw-proxy"}],"type":"rpc"}' || return $?
        _log "INFO" "May need to set 'GOSUMDB=\"sum.golang.org ${r_NEXUS_URL:-"${_NEXUS_URL%/}"}/repository/gosum-raw-proxy\"'"
    fi
    # TODO: add hosted probably from 3.74
    #curl -X PUT -u 'admin:admin123' http://localhost:8081/repository/go-hosted/github.com/gorilla/mux/@v/mux-1.8.1.zip  -T mux-1.8.1.zip
}

function f_setup_apt() {
    local __doc__="Create Apt proxy repositories (NOTE: No HA-C support)"
    local _prefix="${1:-"apt"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        # distribution should be focal, bionic, etc, but it seems any string is OK.
        # With http://archive.ubuntu.com/ubuntu/, 'apt install jq' didn't work
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"apt":{"distribution":"ubuntu","flat":false},"proxy":{"remoteUrl":"http://ports.ubuntu.com/ubuntu-ports/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"apt-proxy"}],"type":"rpc"}' || return $?
    fi
    if ! _is_repo_available "${_prefix}-sec-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"apt":{"distribution":"ubuntu","flat":false},"proxy":{"remoteUrl":"http://security.ubuntu.com/ubuntu/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-sec-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"apt-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    _ASYNC_CURL="Y" f_get_asset "apt-proxy" "pool/main/a/appstream/appstream_0.9.4-1_amd64.deb"

    if ! _is_repo_available "${_prefix}-debian-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"apt":{"distribution":"debian","flat":false},"proxy":{"remoteUrl":"http://deb.debian.org/debian","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-debian-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"apt-proxy"}],"type":"rpc"}' || return $?
    fi
    if ! _is_repo_available "${_prefix}-debian-sec-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"apt":{"distribution":"debian","flat":false},"proxy":{"remoteUrl":"http://security.debian.org/debian-security","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-debian-sec-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"apt-proxy"}],"type":"rpc"}' || return $?
    fi
    # add hosted
    if ! _is_repo_available "${_prefix}-hosted"; then
        if [ -s "${_TMP%/}/gpg_dummy.txt.gz" ] || curl -sf -o ${_TMP%/}/gpg_dummy.txt.gz -L "https://github.com/hajimeo/samples/raw/master/misc/gpg_dummy.txt.gz"; then
            local _gpg="$(gunzip -c ${_TMP%/}/gpg_dummy.txt.gz)"
            _apiS "{\"action\":\"coreui_Repository\",\"method\":\"create\",\"data\":[{\"attributes\":{\"apt\":{\"distribution\":\"ubuntu\"},\"aptSigning\":{\"keypair\":\"${_gpg}\",\"passphrase\":\"admin123\"},\"storage\":{\"blobStoreName\":\"${_bs_name}\",\"strictContentTypeValidation\":true,\"writePolicy\":\"ALLOW_ONCE\"${_extra_sto_opt}},\"component\":{\"proprietaryComponents\":false},\"cleanup\":{\"policyName\":[]}},\"name\":\"${_prefix}-hosted\",\"format\":\"\",\"type\":\"\",\"url\":\"\",\"online\":true,\"recipe\":\"apt-hosted\"}],\"type\":\"rpc\"}" || return $?
        fi
    fi
    if [ -s "${_TMP%/}/hello-world_1.0.0.deb" ] || curl -sf -o ${_TMP%/}/hello-world_1.0.0.deb -L "https://github.com/hajimeo/samples/raw/master/misc/hello-world_1.0.0_unsigned.deb"; then
        _ASYNC_CURL="Y" f_upload_asset "${_prefix}-hosted" -F apt.asset=@${_TMP%/}/hello-world_1.0.0.deb
    fi
}
function _deb_build() {
    # https://earthly.dev/blog/creating-and-hosting-your-own-deb-packages-and-apt-repo/
    local __doc__="Create a simple deb (apt) package, and echo the deb file name (so no stdout from other lines)"
    # Naming rule: <package-name>_<version>-<release-number>_<architecture>
    local _name="${1:-"hello-world"}"
    local _version="${2:-"1.0.0"}"
    local _release="${3:-"1"}"
    local _arch="${4:-"all"}"
    local _work_dir="${5:-"."}"
    _work_dir="$(readlink -f "${_work_dir}")"
    if ! type dpkg-deb &>/dev/null; then
        _log "ERROR" "dpkg-deb is not available. Please install rpm-build package (brew install dpkg)"
        return 1
    fi

    local _tmpdir="$(mktemp -d)"
    cd ${_tmpdir} || return $?
    mkdir -p ${_name}/DEBIAN || return $?
    mkdir -p ${_name}/usr/local/bin || return $?
    # Currently always overwrite
    cat << EOF > "${_name}/usr/local/bin/${_name}"
#!/bin/sh
echo "Hello world!"
EOF
    cat << EOF > "${_name}/DEBIAN/control"
Package: ${_name}
Version: ${_version}
Section: misc
Priority: optional
Architecture: ${_arch}
Maintainer: ${_ADMIN_USER:-"${_USER}"}
Description: Hello world!
EOF
    chmod +x "${_name}/usr/local/bin/${_name}" || return $?
    #_log "INFO" "Building ${_work_dir}/${_name}_${_version}-{_release}_${_arch}.deb ..."
    dpkg-deb --root-owner-group --build -Znone -z0 "${_name}" "${_work_dir}/${_name}_${_version}-${_release}_${_arch}.deb" >&2 || return $?
    #_log "INFO" "Verifying with dpkg -c ${_work_dir}/${_name}_${_version}-${_release}_${_arch}.deb"
    #dpkg -c ${_work_dir}/${_name}_${_version}-{_release}_${_arch}.deb || return $?
    cd - &>/dev/null
    echo "${_work_dir}/${_name}_${_version}-${_release}_${_arch}.deb"
}
function f_start_ubuntu_for_apt_test() {
    local __doc__="Start Ubuntu container"
    local _img_tag="${1:-"ubuntu:latest"}"  # ubuntu:16.04 nxrm3helmha-docker-k8s.standalone.localdomain/debian:12
    local _repo_url="${2-"${_NEXUS_URL%/}/repository/apt-proxy/"}"
    local _name="${3:-"apt-test-$$"}"
    local _ca_pem="${4:-"${_CA_PEM}"}"
    docker run --rm -t -d --name ${_name} ${_img_tag}
    if [ -n "${_repo_url}" ]; then
        sleep 1
        if [[ "${_repo_url}" =~ ^https: ]]; then
            docker exec -it ${_name} bash -c "apt update;apt install -y apt-transport-https ca-certificates" || return $?
            # TODO: this seems not working and [trusted=yes] is not working
            if [ -n "${_ca_pem}" ]; then
                docker cp ${_ca_pem} ${_name}:/usr/local/share/ca-certificates/ && \
                docker exec -it ${_name} /usr/sbin/update-ca-certificates || return $?
            fi
        fi
        docker exec -it ${_name} bash -c "sed -i.bak -E \"s@http://(archive|ports).ubuntu.com/(ubuntu|ubuntu-ports)/@[trusted=yes] ${_repo_url%/}/@g\" /etc/apt/sources.list" || return $?
        if ! _is_repo_available "apt-sec-proxy"; then
            docker exec -it ${_name} bash -c "sed -i.bak2 -E \"s@http://security.ubuntu.com/ubuntu@[trusted=yes] ${_repo_url%/}@g\" /etc/apt/sources.list" || return $?
        fi
    fi
    echo "Command examples (Verify-Peer=false is for https):
    apt -o Acquire::https::Verify-Peer=false -o Debug::pkgProblemResolver=true -o Debug::pkgAcquire::Worker=true update
    apt -o Acquire::https::Verify-Peer=false -o Debug::pkgProblemResolver=true -o Debug::pkgAcquire::Worker=true install strace
    "
    docker exec -it ${_name} bash
}

function f_setup_r() {
    local __doc__="Create R proxy/hosted/group repositories with dummy data"
    local _prefix="${1:-"r"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-proxy, create it
    if ! _is_repo_available "${_prefix}-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://cran.r-project.org/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"r-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    #f_get_asset "${_prefix}-proxy" "download/plugins/nexus-jenkins-plugin/3.9.20200722-164144.e3a1be0/nexus-jenkins-plugin.hpi"

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true,"writePolicy":"ALLOW"'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"r-hosted"}],"type":"rpc"}' && \
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
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"r-group"}],"type":"rpc"}' && \
            echo "# install.packages('bit', repos='${_NEXUS_URL%/}/repository/r${_prefix}-group/', type='binary')"
    fi
    # add some data for xxxx-group
    #f_get_asset "${_prefix}-group" "test/test_1k.data"
}

function f_setup_gitlfs() {
    local __doc__="Create Git-LFS hosted repository"
    local _prefix="${1:-"gitlfs"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}',"writePolicy":"ALLOW"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"gitlfs-hosted"}],"type":"rpc"}' || return $?
    fi
}

function f_setup_cargo() {
    local __doc__="Create Cargo Proxy/Hosted/Group repositories (v3.73+)"
    local _prefix="${1:-"cargo"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    if ! _is_repo_available "${_prefix}-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://index.crates.io/","contentMaxAge":1440,"metadataMaxAge":1440},"replication":{"preemptivePullEnabled":false},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"cargo-proxy"}],"type":"rpc"}' || return $?
    fi
    if ! _is_repo_available "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}',"writePolicy":"ALLOW_ONCE"},"component":{"proprietaryComponents":false},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"cargo-hosted"}],"type":"rpc"}' || return $?
    fi
    if ! _is_repo_available "${_prefix}-group"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"cargo-group"}],"type":"rpc"}' || return $?
    fi
    echo "To test:
    curl -sSf -D- -o/dev/null -H \"Authorization: Basic <B64encoded_UserToken>\" ${_NEXUS_URL%/}/repository/${_prefix}-hosted/config.json
    curl -sSf -D- ${_NEXUS_URL%/}/repository/${_prefix}-group/me"   # To get the token (but User Token should be actually used
}

function f_setup_composer() {
    local __doc__="Create PHP Composer Proxy repository (v3.75+)"
    local _prefix="${1:-"composer"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _extra_sto_opt=""
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _extra_sto_opt=',"dataStoreName":"'${_ds_name}'"'
    if ! _is_repo_available "${_prefix}-proxy"; then
        # https://packagist.org is deprecated from Feb 2025
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://repo.packagist.org","contentMaxAge":1440,"metadataMaxAge":1440},"replication":{"preemptivePullEnabled":false},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"dataStoreName":"nexus","blobStoreName":"'${_bs_name}'","strictContentTypeValidation":true'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"composer-proxy"}],"type":"rpc"}' || return $?
    fi
    echo "To test:
    curl -sSf -D- ${_NEXUS_URL%/}/repository/${_prefix}-proxy/packages.json"
}

#curl -D- -sSf -u 'admin:admin123' "http://localhost:8081/service/rest/v1/repositories/raw/hosted" -H "Content-Type: application/json" -d '{"name":"raw-hosted","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":false,"writePolicy":"ALLOW"}}'
#curl -D- -sSf -u 'admin:admin123' "http://localhost:8081/repository/raw-hosted/test/test.txt" -T <(echo 'test')
function f_setup_raw() {
    local __doc__="Create Raw proxy/hosted/group repositories with dummy data"
    local _prefix="${1:-"raw"}"
    local _bs_name="${2:-"${r_BLOBSTORE_NAME:-"${_BLOBTORE_NAME}"}"}"
    local _ds_name="${3:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    local _extra_sto_opt="$(_get_extra_sto_opt "${_ds_name}")"
    # NOTE: using "strictContentTypeValidation":false for raw repositories

    # If no xxxx-hosted, create it
    if ! _is_repo_available "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":false'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}' || return $?
    fi

    # If no xxxx-proxy, create it (but no standard remote URL for Raw format)
    if ! _is_repo_available "${_prefix}-repl-proxy"; then
        # TODO: using localhost:8081 or ${_NEXUS_URL%/} is not perfect
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"replication":{"enabled":false,"preemptivePullEnabled":true,"assetPathRegex":""},"raw":{"contentDisposition":"ATTACHMENT"},"proxy":{"remoteUrl":"'${_NEXUS_URL%/}'/repository/'${_prefix}'-hosted/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true},"storage":{"dataStoreName":"nexus","blobStoreName":"'${_bs_name}'","strictContentTypeValidation":false'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-repl-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"raw-proxy"}],"type":"rpc"}' #|| return $?
    fi
    if ! _is_repo_available "${_prefix}-repl-proxy" && ! _is_repo_available "${_prefix}-jenkins-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"raw":{"contentDisposition":"ATTACHMENT"},"proxy":{"remoteUrl":"https://updates.jenkins.io/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":false'${_extra_sto_opt}'},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-jenkins-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"raw-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    #f_get_asset "${_prefix}-jenkins-proxy" "download/plugins/nexus-jenkins-plugin/3.9.20200722-164144.e3a1be0/nexus-jenkins-plugin.hpi"

    # Quicker way: NOTE --limit-rate=4k can be a handy option to test:
    # *NOTE*: The following test does not work with different extensions with the Strict Content Validation enabled.
    #   time curl -D- -u 'admin:admin123' -T <(echo 'test') "${_NEXUS_URL%/}/repository/raw-hosted/test/test.txt"
    #   (Not working) Create a dummy 1K file: dd if=/dev/zero of=${_TMP%/}/test_1k.data bs=1024 count=1 oflag=dsync
    dd if=/dev/zero of=${_TMP%/}/test_1k.data bs=1 count=0 seek=1024 && \
    _ASYNC_CURL="Y" f_upload_asset "${_prefix}-hosted" -F raw.directory=test -F raw.asset1=@${_TMP%/}/test_1k.data -F raw.asset1.filename=test_1k.data
    # If real large size is required:
    #   dd if=/dev/zero of=./test_100m.data bs=1024 count=$((1024*100))
    # Test by uploading and downloading:
    #   curl -u 'admin' -w "status:\t%{http_code}\nelapsed:\t%{time_total}\n" -T ${_TMP%/}/test_100m.data "${_NEXUS_URL%/}/repository/raw-hosted/test/test_100m.data"
    #   curl -u 'admin' -w "status:\t%{http_code}\nnelapsed:\t%{time_total}\n" -o/dev/null "${_NEXUS_URL%/}/repository/raw-hosted/test/test_100m.data"

    # If no xxxx-group, create it
    if ! _is_repo_available "${_prefix}-group"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":false'${_extra_sto_opt}'},"group":{"memberNames":["'${_prefix}'-hosted"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"raw-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    #_ASYNC_CURL="Y" f_get_asset "${_prefix}-group" "test/test_1k.data"
}

### Nexus related Misc. functions #################################################################
function _get_inst_dir() {
    local _install_dir="$(ps auxwww | sed -n -E '/org.sonatype.nexus.karaf.NexusMain/ s/.+-Dexe4j.moduleName=([\S]+)\/bin\/nexus .+/\1/p' | head -1)"
    [ -z "${_install_dir}" ] && _install_dir="$(find . -mindepth 1 -maxdepth 1 -type d -name 'nexus*' 2>/dev/null | sort | tail -n1)"
    readlink -f "${_install_dir%/}"
}
function _get_work_dir() {
    local _work_dir="$(ps auxwww | sed -n -E '/org.sonatype.nexus.karaf.NexusMain/ s/.+-Dkaraf.data=([\S]+) .+/\1/p' | head -n1)"
    if [ -n "${_work_dir}" ] && [[ ! "${_work_dir}" =~ ^/ ]]; then
        local _install_dir="$(_get_inst_dir)"
        _work_dir="${_install_dir%/}/${_work_dir%/}"
    else
        _work_dir="$(find . -mindepth 1 -maxdepth 2 -type d -path '*/sonatype-work/*' -name 'nexus3' | sort | tail -n1)"
    fi
    readlink -f "${_work_dir}"
}
# TODO: haven't used yet. Thinking of adding conditions based on version
function _get_version() {
    #curl -I "${_NEXUS_URL%/}/service/rest/v1/status" often doesn't work via reverse proxy
    [ -n "${_NEXUS_VER}" ] && [ "${_NEXUS_VER}" != "<null>" ] && echo "${_NEXUS_VER}" && return
    local _app_ver="$(f_api "/service/rest/atlas/system-information" | grep -A1 '"nexus-status"' | grep '"version"' | sed -r 's/.*"version" *: *"([^"]+)".*/\1/g')"
    [ -n "${_app_ver}" ] && export _NEXUS_VER="${_app_ver}" && echo "${_app_ver}"
}
function _get_blobstore_name() {
    local _bs_name="default"
    if [ -n "${_BLOBTORE_NAME}" ]; then
        echo "${_BLOBTORE_NAME}"
        return
    fi
    f_api "/service/rest/v1/blobstores" | sed -r -n 's/.*"name" *: *"([^"]+)".*/\1/gp' >${_TMP%/}/${FUNCNAME[0]}_$$.out
    local _line_num="$(cat ${_TMP%/}/${FUNCNAME[0]}_$$.out | wc -l | tr -d '[:space:]')"
    if grep -qE "^${_bs_name}$" ${_TMP%/}/${FUNCNAME[0]}_$$.out; then
        _BLOBTORE_NAME="${_bs_name}"
    elif [ "${_line_num}" == "0" ]; then
        _log "INFO" "No blobstore defined. Creating '${_bs_name}' file blobstore ..."; sleep 1
        f_create_file_blobstore "${_bs_name}" || return $?
        _BLOBTORE_NAME="${_bs_name}"
    elif [ "${_line_num}" == "1" ]; then
        # If only one blobstore defined, use it, otherwise return false
        _BLOBTORE_NAME="$(cat ${_TMP%/}/${FUNCNAME[0]}_$$.out)"
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

function _get_extra_sto_opt() {
    local _ds_name="$1"
    if [ -n "${_EXTRA_STO_OPT}" ]; then
        echo "${_EXTRA_STO_OPT}"
        return
    fi
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    [ -n "${_ds_name}" ] && _EXTRA_STO_OPT=',"dataStoreName":"'${_ds_name}'"'
    echo "${_EXTRA_STO_OPT}"
}

function f_reencrypt() {
    local __doc__="Re-encrypt the secrets. https://help.sonatype.com/en/re-encryption-in-nexus-repository.html"
    local _id="${1:-"my-key"}"
    local _key="${2:-"my-secret-passphrase"}"
    local _key_path="${3}"
    local _work_dir="$(_get_work_dir)"  # this returns absolute path
    if [ -z "${_key_path}" ]; then
        _key_path="${_work_dir}/etc/nexus-secrets.json"
    fi
    if [ -s "${_key_path}" ]; then
        _log "WARN" "Secrets file ${_key_path} exists."
    else
        cat << EOF > ${_key_path}
    {
      "active": null,
      "keys": [
        {
          "id": "${_id}", "key": "${_key}"
        }
      ]
    }
EOF
    fi
    _upsert ${_work_dir%/}/etc/nexus.properties "nexus.secrets.file" "${_key_path}" || return $?
    _log "INFO" "Restart required to apply the new secrets."
cat << EOF
curl -u "${_ADMIN_USER}" "${_NEXUS_URL%/}/service/rest/v1/secrets/encryption/re-encrypt" -X PUT -H 'accept:application/json' -H 'Content-Type: application/json' -d '{"secretKeyId":"${_id:-"__KEY_ID__"}"}'
EOF
}

function f_branding() {
    local __doc__="NXRM3 branding|brand example"
    local _msg="${1:-"HelloWorld!"}"
    #<marquee direction="right" behavior="alternate"><span style="color:#f0f8ff;">some text</span></marquee>
    _apiS '{"action":"capability_Capability","method":"create","data":[{"id":"NX.coreui.model.Capability-1","typeId":"rapture.branding","notes":"","enabled":true,"properties":{"headerEnabled":"true","headerHtml":"<div style=\"background-color:white;text-align:right\">'${_msg}'</a>&nbsp;</div>","footerEnabled":null,"footerHtml":""}}],"type":"rpc"}'
}

function f_create_file_blobstore() {
    local __doc__="Create a File type blobstore"
    local _bs_name="${1:-"default"}"
    if ! _apiS '{"action":"coreui_Blobstore","method":"create","data":[{"type":"File","name":"'${_bs_name}'","isQuotaEnabled":false,"attributes":{"file":{"path":"'${_bs_name}'"}}}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out; then
        _log "ERROR" "Blobstore ${_bs_name} does not exist."
        _log "ERROR" "$(cat ${_TMP%/}/f_apiS_last.out)"
        return 1
    fi
    _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
}

# AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=yyy f_create_s3_blobstore
# _NO_REPO_CREATE=Y f_create_s3_blobstore
function f_create_s3_blobstore() {
    local __doc__="Create a S3 blobstore. AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are required"
    local _bs_name="${1:-"s3-test"}"
    local _prefix="${2:-"$(hostname -s)_${_bs_name}"}"    # cat /etc/machine-id is not perfect if docker container
    local _bucket="${3:-"apac-support-bucket"}"
    local _region="${4:-"${AWS_REGION:-"ap-southeast-2"}"}"
    local _ak="${5:-"${AWS_ACCESS_KEY_ID}"}"
    local _sk="${6:-"${AWS_SECRET_ACCESS_KEY}"}"
    if [ -n "${_prefix}" ]; then    # AWS S3 prefix shoudln't start with / (and may need to end with /)
        _prefix="${_prefix#/}"
        _prefix="${_prefix%/}/"
    fi
    # NOTE: 3.27 has ',"state":""'
    #       From 3.80 'coreui_Blobstore' may not work
    if ! f_api "/service/rest/v1/blobstores/s3" '{"name":"'${_bs_name}'","bucketConfiguration":{"bucket":{"region":"'${_region}'","prefix":"Hajimes-MacBook-Pro-2_s3-test","name":"'${_bucket}'"},"bucketSecurity":{"secretAccessKey":"'${_sk}'","accessKeyId":"'${_ak}'"},"encryption":null,"advancedBucketConnection":{"endpoint":"","forcePathStyle":false},"failoverBuckets":[],"activeRegion":null}}' > ${_TMP%/}/f_api_last.out; then
        if ! _apiS '{"action":"coreui_Blobstore","method":"create","data":[{"type":"S3","name":"'${_bs_name}'","isQuotaEnabled":false,"property_region":"'${_region}'","property_bucket":"'${_bucket}'","property_prefix":"'${_prefix%/}'","property_expiration":1,"authEnabled":true,"property_accessKeyId":"'${_ak}'","property_secretAccessKey":"'${_sk}'","property_assumeRole":"","property_sessionToken":"","encryptionSettingsEnabled":false,"advancedConnectionSettingsEnabled":false,"attributes":{"s3":{"region":"'${_region}'","bucket":"'${_bucket}'","prefix":"'${_prefix%/}'","expiration":"2","accessKeyId":"'${_ak}'","secretAccessKey":"'${_sk}'","assumeRole":"","sessionToken":""}}}],"type":"rpc"}' > ${_TMP%/}/f_apiS_last.out; then
            _log "ERROR" "Failed to create blobstore: ${_bs_name} ."
            _log "ERROR" "$(cat ${_TMP%/}/f_api_last.out)"
            _log "ERROR" "$(cat ${_TMP%/}/f_apiS_last.out)"
            return 1
        fi
    fi
    _log "DEBUG" "$(cat ${_TMP%/}/f_apiS_last.out)"
    if [[ ! "${_NO_REPO_CREATE}" =~ [yY] ]] && ! _is_repo_available "raw-s3-hosted"; then
        # Not sure why but the file created by `dd` doesn't work if strictContentTypeValidation is true
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":false'$(_get_extra_sto_opt)'},"cleanup":{"policyName":[]}},"name":"raw-s3-hosted","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}' || return $?
        if ! _is_repo_available "raw-s3-hosted"; then
            _log "WARN" "Failed to create raw-s3-hosted"
        else
            _log "INFO" "Created raw-s3-hosted"
        fi
    fi
    _log "INFO" "AWS CLI command examples (not AWS_REGION may matter):
aws s3api get-bucket-acl --bucket ${_bucket}
aws s3api get-bucket-policy --bucket ${_bucket}                 # same as 'checkBucketOwner'
aws s3api get-bucket-ownership-controls --bucket ${_bucket}     # same as 'checkBucketOwner'
aws s3api head-object --bucket ${_bucket} --key ${_prefix}metadata.properties  # same as 'metadata.exists()'
aws s3 ls s3://${_bucket}/${_prefix}content/   # --recursive but 1000 limits (same for list-objects)
aws s3api list-objects --bucket ${_bucket} --query \"Contents[?contains(Key, 'f062f002-88f0-4b53-aeca-7324e9609329.properties')]\"
aws s3api get-object-tagging --bucket ${_bucket} --key \"${_prefix}content/vol-42/chap-31/f062f002-88f0-4b53-aeca-7324e9609329.properties\"
aws s3 cp s3://${_bucket}/${_prefix}content/vol-42/chap-31/f062f002-88f0-4b53-aeca-7324e9609329.properties -
"
}

function f_create_azure_blobstore() {
    local __doc__="Create an Azure blobstore. AZURE_STORAGE_ACCOUNT_NAME and AZURE_STORAGE_ACCOUNT_KEY are required"
    #https://pkg.go.dev/github.com/Azure/azure-sdk-for-go/sdk/azidentity#readme-environment-variables
    local _bs_name="${1:-"az-test"}"
    local _container_name="${2:-"$(hostname -s | tr '[:upper:]' '[:lower:]')-${_bs_name}"}"
    local _an="${3:-"${AZURE_STORAGE_ACCOUNT_NAME}"}"
    local _ak="${4:-"${AZURE_STORAGE_ACCOUNT_KEY}"}"
    # NOTE: nexus.azure.server=<your.desired.blob.storage.server>
    # Container names can contain only lowercase letters, numbers, and the dash (-) character, and must be 3-63 characters long.
    if ! f_api "/service/rest/v1/blobstores/azure" '{"name":"'${_bs_name}'","bucketConfiguration":{"authentication":{"authenticationMethod":"ACCOUNTKEY","accountKey":"'${_ak}'"},"accountName":"'${_an}'","containerName":"'${_container_name}'"}}' > ${_TMP%/}/f_api_last.out; then
        _log "ERROR" "Failed to create blobstore: ${_bs_name} ."
        _log "ERROR" "$(cat ${_TMP%/}/f_api_last.out)"
        return 1
    fi
    _log "DEBUG" "$(cat ${_TMP%/}/f_api_last.out)"
    if [[ ! "${_NO_REPO_CREATE}" =~ [yY] ]] && ! _is_repo_available "raw-az-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":false'$(_get_extra_sto_opt)'},"cleanup":{"policyName":[]}},"name":"raw-az-hosted","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}' || return $?
        _log "INFO" "Created raw-az-hosted"
    fi
    _log "TODO" "Azure CLI command examples"
}

function f_create_google_blobstore() {
    local __doc__="Create an Google blobstore. GOOGLE_APPLICATION_CREDENTIALS is required (3.74+)"
    local _bs_name="${1:-"gc-test"}"
    local _accountKeyFle="${2:-"${GOOGLE_APPLICATION_CREDENTIALS}"}"
    local _bucket="${3:-"${GOOGLE_BUCKET}"}"
    local _prefix="${4:-"$(hostname -s)_${_bs_name}"}"
    local _region="${5:-"${GOOGLE_REGION:-"australia-southeast1"}"}"
    local _accountKeyFle_content="$(cat "${_accountKeyFle}" | JSON_ESCAPE=Y _sortjson)"
    local _project_id="$(cat "${_accountKeyFle}" | JSON_SEARCH_KEY="project_id" _sortjson)"
    echo '{"name":"'${_bs_name}'","bucketConfiguration":{"bucketSecurity":{"authenticationMethod":"accountKey","file":{"0":{}},"accountKey":"'${_accountKeyFle_content}'"},"bucket":{"projectId":"'${_project_id}'","name":"'${_bucket}'","prefix":"'${_prefix}'","region":"'${_region}'"}}}' > ${_TMP%/}/${FUNCNAME[0]}_$$.json
    if ! f_api "/service/rest/v1/blobstores/google" "@${_TMP%/}/${FUNCNAME[0]}_$$.json" > ${_TMP%/}/f_api_last.out; then
        _log "ERROR" "Failed to create blobstore: ${_bs_name} ."
        _log "ERROR" "$(cat ${_TMP%/}/f_api_last.out)"
        return 1
    fi
    _log "DEBUG" "$(cat ${_TMP%/}/f_api_last.out)"
    if [[ ! "${_NO_REPO_CREATE}" =~ [yY] ]] && ! _is_repo_available "raw-gc-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":false'$(_get_extra_sto_opt)'},"cleanup":{"policyName":[]}},"name":"raw-gc-hosted","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}' || return $?
        _log "INFO" "Created raw-gc-hosted"
    fi
    _log "TODO" "Google CLI command examples"
}

function f_create_group_blobstore() {
    local __doc__="Create a new group blob store. Not promoting to group"
    local _bs_name="${1:-"bs-group"}"
    local _member_pfx="${2:-"member"}"
    local _file_policy="${3:-"writeToFirst"}"   # writeToFirst or roundRobin
    local _repo_name="${4-"raw-grpbs-hosted"}"
    f_create_file_blobstore "${_member_pfx}1"
    f_create_file_blobstore "${_member_pfx}2"
    f_api '/service/rest/v1/blobstores/group' '{"name":"'${_bs_name}'","members":["'${_member_pfx}'1","'${_member_pfx}'2"],"fillPolicy":"'${_file_policy}'"}' || return $?
    if [ -n "${_repo_name}" ] && ! _is_repo_available "${_repo_name}"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":true'$(_get_extra_sto_opt)'},"cleanup":{"policyName":[]}},"name":"'${_repo_name}'","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}' || return $?
        _log "INFO" "Created ${_repo_name} (no asset)"
    fi
}

_IQ_CONFIGURED=false
function f_iq_quarantine() {
    local __doc__="Create Firewall Audit and Quarantine capability (also set up IQ connection)"
    local _repo_name="$1"
    local _iq_url="${2-"${_IQ_URL}"}"   # accept empty string so that won't override with _IQ_URL
    local _iq_user="${3:-"${_ADMIN_USER}"}"
    local _iq_pwd="${4:-"${_ADMIN_PWD}"}"
    if ! ${_IQ_CONFIGURED} && f_api "/service/rest/v1/iq" | grep -qE '"enabled" *: *true'; then
        _log "INFO" "IQ is *probably* already configured."
        _IQ_CONFIGURED=true
    fi
    if [ -z "${_iq_url}" ] && ! ${_IQ_CONFIGURED}; then
        _log "ERROR" "IQ is not enabled and no _iq_url."
        return 1
    fi
    if [ -n "${_iq_url}" ] && ! ${_IQ_CONFIGURED}; then
        if ! curl -sfI "${_iq_url}" &>/dev/null ; then
            _log "WARN" "IQ ${_iq_url} is not reachable, but try creating the capability."
        fi
        # Should use the API?
        _log "INFO" "Configuring IQ ${_iq_url} with '${_iq_user}' ..."
        f_iq_connection "${_iq_url}" "true" "${_iq_user}" "${_iq_pwd}" || return $?
        _IQ_CONFIGURED=true
    fi
    # To create IQ: Audit and Quarantine for this repository:
    if [ -n "${_repo_name}" ]; then
        _apiS '{"action":"capability_Capability","method":"create","data":[{"id":"NX.coreui.model.Capability-1","typeId":"firewall.audit","notes":"","enabled":true,"properties":{"repository":"'${_repo_name}'","quarantine":"true"}}],"type":"rpc"}' || return $?
        _log "INFO" "IQ: Audit and Quarantine for ${_repo_name} completed."
    fi
}

function f_iq_connection() {
    local __doc__="Create IQ connection"
    local _iq_url="${1:-"${_IQ_URL}"}"   # accept empty string so that won't override with _IQ_URL
    local _enabled="${2:-"true"}"
    local _iq_user="${3:-"${_ADMIN_USER}"}"
    local _iq_pwd="${4:-"${_ADMIN_PWD}"}"
    _apiS '{"action":"clm_CLM","method":"update","data":[{"enabled":'${_enabled}',"url":"'${_iq_url}'","authenticationType":"USER","username":"'${_iq_user}'","password":"'${_iq_pwd}'","timeoutSeconds":null,"properties":"","showLink":true}],"type":"rpc"}'
}

function f_iq_quarantine_all() {
    local __doc__="Create Firewall Audit and Quarantine capabilities for all proxy repositories"
    local _repo_name_regex="$1"
    local _iq_url="${2-"${_IQ_URL}"}"   # accept empty string so that won't override with _IQ_URL
    local _iq_user="${3:-"${_ADMIN_USER}"}"
    local _iq_pwd="${4:-"${_ADMIN_PWD}"}"
    f_api "/service/rest/v1/repositories" | grep -E '"type" *: *"proxy"' -B2 | grep '"name"' | sed -r 's/.*"name" *: *"([^"]+)".*/\1/g' | while read _repo_name; do
        if [ -z "${_repo_name_regex}" ] || [[ "${_repo_name}" =~ ${_repo_name_regex} ]]; then
            _log "INFO" "Setting IQ qurantine for ${_repo_name} ..."
            f_iq_quarantine "${_repo_name}" "${_iq_url}" "${_iq_user}" "${_iq_pwd}"
        fi
    done
}

# f_get_and_upload_jars "maven" "junit" "junit" "3.8 4.0 4.1 4.2 4.3 4.4 4.5 4.6 4.7 4.8 4.9 4.10 4.11 4.12"
function f_get_and_upload_jars() {
    local __doc__="Example script for getting multiple versions from maven-proxy, then upload to maven-hosted"
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
    local __doc__="Example script for testing staging/promotion API"
    local _from_repo="$1"
    local _to_repo="$2"
    local _group="$3"
    local _artifact="${4:-"*"}"
    local _version="${5:-"*"}"
    [ -z "${_group}" ] && return 11
    f_api "/service/rest/v1/staging/move/${_to_repo}?repository=${_from_repo}&group=${_group}&name=${_artifact}&version=${_version}" "" "POST"
}

function f_get_asset() {
    local __doc__="Get/download one asset"
    if [[ "${_IS_NXRM2}" =~ ^[yY] ]]; then
        _get_asset_NXRM2 "$@"
    else
        _get_asset "$@"
    fi
}
#NOTE: using _ASYNC_CURL and _NO_DATA
function _get_asset() {
    local _repo="$1"
    local _path="$2"
    local _out_path="${3}"
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
    if [ -n "${_out_path}" ]; then
        _curl="${_curl} -D ${_TMP%/}/_proxy_test_header_$$.out -o ${_out_path}"
    else
        cat /dev/null > ${_TMP%/}/_proxy_test_header_$$.out
        _curl="${_curl} -I" # NOTE: this is NOT same as '-X HEAD'
    fi
    _curl="${_curl} -u ${_user}:${_pwd} -k \"${_base_url%/}/repository/${_repo%/}/${_path#/}\""
    if [[ "${_ASYNC_CURL}" =~ ^[yY] ]]; then
        # bash -c is different from eval
        bash -c "nohup ${_curl} >/dev/null 2>&1 &" &>/dev/null
        return $?
    fi
    eval "${_curl}"
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

# NOTE: Using _ASYNC_CURL env variable. If Nexus2, _IS_NXRM2.
# If NXRM2, below curl also works:
#   curl -D- -u admin:admin123 -T <(echo "test upload") "http://localhost:8081/nexus/content/repositories/raw-hosted/test/test.txt"
#f_upload_asset "maven-releases" -F "maven2.groupId=keystores" -F "maven2.artifactId=my-test-jks" -F "maven2.version=20241024" -F "maven2.asset1.extension=jks" -F "maven2.asset1=@$HOME/IdeaProjects/samples/misc/standalone.localdomain.jks"
function f_upload_asset() {
    local __doc__="Upload one asset with Upload API"
    local _repo_or_fmt="$1"    # format if NXRM2
    local _forms=${@:2} #-F "maven2.groupId=junit" -F "maven2.artifactId=junit" -F "maven2.version=4.21" -F "maven2.asset1.extension=jar" -F "maven2.asset1=@${_TMP%/}/junit-4.12.jar"
    # NOTE: Because _forms takes all arguments except first one, can't assign any other arguments
    local _usr="${r_ADMIN_USER:-"${_ADMIN_USER}"}"
    local _pwd="${r_ADMIN_PWD:-"${_ADMIN_PWD}"}"   # If explicitly empty string, curl command will ask password (= may hang)
    local _base_url="${r_NEXUS_URL:-"${_NEXUS_URL}"}"

    if [[ "${_NO_DATA}" =~ ^[yY] ]]; then
        _log "INFO" "_NO_DATA is set so no action."; return 0
    fi

    local _url="${_base_url%/}/service/rest/v1/components?repository=${_repo_or_fmt}"
    if [[ "${_IS_NXRM2}" =~ ^[yY] ]]; then
        _url="${_base_url%/}/nexus/service/local/artifact/${_repo_or_fmt}/content"
    fi

    local _curl="curl -sf"
    ${_DEBUG} && _curl="curl -fv"
    # TODO: not sure if -H \"accept: application/json\" is required
    _curl="${_curl} -D ${_TMP%/}/_upload_test_header_$$.out -w \"%{http_code} ${_forms} (%{time_total}s)\n\" -u ${_usr}:${_pwd} -H \"accept: application/json\" -H \"Content-Type: multipart/form-data\" -X POST -k \"${_url}\" ${_forms}"
    if [[ "${_ASYNC_CURL}" =~ ^[yY] ]]; then
        # bash -c is different from eval
        bash -c "nohup ${_curl} >/dev/null 2>&1 &" &>/dev/null
        return $?
    fi
    eval "${_curl}"
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        if grep -qE '^HTTP/1.1 [45]' ${_TMP%/}/_upload_test_header_$$.out; then
            _log "ERROR" "Failed to post to ${_url} (${_rc})"
            cat ${_TMP%/}/_upload_test_header_$$.out >&2
            return ${_rc}
        else
            _log "WARN" "Post to ${_url} might be failed (${_rc})"
            cat ${_TMP%/}/_upload_test_header_$$.out >&2
        fi
    fi
}

### Utility/Misc. functions #################################################################
function _apiS() {
    # NOTE: may require nexus.security.anticsrftoken.enabled=false (NEXUS-23735)
    local _data="${1}"
    local _method="${2}"
    local _usr="${3:-${r_ADMIN_USER:-"${_ADMIN_USER}"}}"
    local _pwd="${4-${r_ADMIN_PWD:-"${_ADMIN_PWD}"}}"   # Accept an empty password
    local _nexus_url="${5:-${r_NEXUS_URL:-"${_NEXUS_URL}"}}"

    local _usr_b64="$(echo -n "${_usr}" | base64)"
    local _pwd_b64="$(echo -n "${_pwd}" | base64)"
    local _user_pwd="username=${_usr_b64}&password=${_pwd_b64}"
    [ -n "${_data}" ] && [ -z "${_method}" ] && _method="POST"
    [ -z "${_method}" ] && _method="GET"

    # Mac's /tmp is symlink so without the ending "/", would needs -L but does not work with -delete
    find -L ${_TMP%/} -maxdepth 1 -type f -name '.nxrm_c_*' -mmin +1 -exec rm -f {} \; 2>/dev/null
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
        _sess_key="NXJWT"   # It's unclear if this is still used.
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
        if ! cat ${_TMP%/}/_apiS_nxrm$$.out | JSON_NO_SORT="Y" _sortjson 2>/dev/null; then
            echo -n "$(cat ${_TMP%/}/_apiS_nxrm$$.out)"
            echo ""
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
    [ "${_data:0:1}" != "{" ] && [ "${_data:0:1}" != "[" ] && [[ ! "${_data}" =~ json ]] && _content_type="Content-Type: text/plain"

    local _curl="curl -sSf"
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
      cat ${_TMP%/}/f_api_nxrm_$$.out | _sortjson
    elif ! cat ${_TMP%/}/f_api_nxrm_$$.out | JSON_NO_SORT="Y" _sortjson 2>/dev/null; then
        echo -n "$(cat ${_TMP%/}/f_api_nxrm_$$.out)"
        echo ""
    fi
}

# Create a container which installs python, npm, mvn, nuget, etc.
#usermod -a -G docker $USER (then relogin)
#docker rm -f nexus-client; p_client_container "http://dh1.standalone.localdomain:8081/"
function p_client_container() {
    local __doc__="Process multiple functions to create a docker container to install various client commands"
    local _base_url="${1:-"${r_NEXUS_URL:-"${_NEXUS_URL}"}"}"
    local _name="${2:-"nexus-client"}"
    local _image_tag="${3:-"fedora:41"}"
    local _cmd="${4:-"${r_DOCKER_CMD:-"docker"}"}"

    local _image_name="${_name}:latest"
    local _existing_id="`${_cmd} images -q ${_image_name}`"
    if [ -n "${_existing_id}" ]; then
        _log "INFO" "Image ${_image_name} (${_existing_id}) already exists. Running / Starting a container..."
    else
        local _build_dir="./${FUNCNAME[0]}_$$"
        if [ ! -d "${_build_dir}" ]; then
            mkdir -p "${_build_dir}" || return $?
        fi
        local _dockerfile="${_build_dir%/}/Dockerfile"

        # Expecting f_setup_yum and f_setup_docker have been run
        curl -s -f -m 7 --retry 2 "${_DL_URL%/}/docker/DockerFile_Nexus" -o ${_dockerfile} || return $?

        local _os_and_ver="docker.io/${_image_tag}"
        # If docker-group or docker-proxy host:port is provided, trying to use it.
        if [ -n "${r_DOCKER_GROUP:-"${r_DOCKER_PROXY}"}" ]; then
            if ! _docker_login "${r_DOCKER_GROUP}" "" "${r_ADMIN_USER:-"${_ADMIN_USER}"}" "${r_ADMIN_PWD:-"${_ADMIN_PWD}"}"; then
                if _docker_login "${r_DOCKER_PROXY}" "" "${r_ADMIN_USER:-"${_ADMIN_USER}"}" "${r_ADMIN_PWD:-"${_ADMIN_PWD}"}"; then
                    _os_and_ver="${r_DOCKER_PROXY}/${_image_tag}"
                fi
            else
                _os_and_ver="${r_DOCKER_GROUP}/${_image_tag}"
            fi
        fi
        _sed -i -r "s@^FROM .+@FROM ${_os_and_ver}@1" ${_dockerfile} || return $?
        if [ -s $HOME/.ssh/id_rsa ]; then
            local _pkey="`_sed ':a;N;$!ba;s/\n/\\\\\\\n/g' $HOME/.ssh/id_rsa`"
            _sed -i "s@_REPLACE_WITH_YOUR_PRIVATE_KEY_@${_pkey}@1" ${_dockerfile} || return $?
        fi
        _log "DEBUG" "$(cat ${_dockerfile})"

        cd ${_build_dir} || return $?
        _log "INFO" "Building ${_image_name} ... (outputs:${_LOG_FILE_PATH:-"/dev/null"})"
        ${_cmd} build --rm -t ${_image_name} . 2>&1 >>${_LOG_FILE_PATH:-"/dev/null"} || return $?
        cd -
        if [ -n "${_build_dir}" ] && [ -d "${_build_dir}" ]; then
            rm -rf ${_build_dir}
        fi
    fi

    if [ -n "${_cmd}" ] && ! ${_cmd} network ls --format "{{.Name}}" | grep -q "^${_DOCKER_NETWORK_NAME}$"; then
        _docker_add_network "${_DOCKER_NETWORK_NAME}" "" "${_cmd}" || return $?
    fi

    # TODO: fedra doesn't work with `:ro`
    local _ext_opts="-v /sys/fs/cgroup:/sys/fs/cgroup --privileged=true -v ${_WORK_DIR%/}:${_SHARE_DIR}"
    [ -n "${_DOCKER_NETWORK_NAME}" ] && _ext_opts="--network=${_DOCKER_NETWORK_NAME} ${_ext_opts}"
    _log "INFO" "Running or Starting '${_name}'"
    # TODO: not right way to use 3rd and 4th arguments. Also if two IPs are configured, below might update /etc/hosts with 2nd IP.
    _docker_run_or_start "${_name}" "${_ext_opts}" "${_image_name} /sbin/init" "${_cmd}" || return $?
    _container_add_NIC "${_name}" "bridge" "Y" "${_cmd}"

    # Try updating /etc/resolv.conf of the container
    _container_update_resolv_conf "${_name}"

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
    # To save more space: https://github.com/goldmann/docker-squash
}

# Setup (reset) client configs "from" a CentOS container and as "root"
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
        _echo_yum_repo_file "yum-group" "${_base_url}" > /etc/yum.repos.d/nexus-yum-test.repo
    fi

    _log "INFO" "Not setting up any nuget/pwsh configs. Please do it manually later ..."

    # Using Nexus npm repository if available
    _repo_url="${_base_url%/}/repository/npm-group"
    if _is_url_reachable "${_repo_url}"; then
        _log "INFO" "Create a sample ${_home%/}/.npmrc ..."
        local _cred="$(echo -n "${_usr}:${_pwd}" | base64)"
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
    # (probably) how to retry 'pod install':
    # cd $HOME/cocoapods-test && rm -rf $HOME/Library/Caches Pods Podfile.lock cocoapods-test.xcworkspace

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
    local _yum_install="yum install -y --skip-unavailable"
    if [ -s /etc/yum.repos.d/nexus-yum-test.repo ]; then
        _yum_install="yum --disablerepo=base --enablerepo=nexusrepo-test install -y --skip-unavailable"
    fi
    if ! ${_yum_install} epel-release; then
        _log "WARN" "${_yum_install} epel-release failed. but continuing ..."
        return 1
    fi
    curl -fL https://rpm.nodesource.com/setup_14.x --compressed | bash - || _log "ERROR" "Executing https://rpm.nodesource.com/setup_14.x failed"
    rpm -Uvh https://packages.microsoft.com/config/centos/7/packages-microsoft-prod.rpm
    yum install -y centos-release-scl-rh centos-release-scl || _log "ERROR" "Installing .Net (for Nuget) related packages failed"
    # TODO: I think rubygems on CentOS requires ruby 2.3 (or 2.6?) or was it for cocoapods?
    ${_yum_install} java-1.8.0-openjdk-devel maven nodejs aspnetcore-runtime-3.1 gcc openssl-devel bzip2-devel libffi-devel zlib-devel xz-devel || _log "ERROR" "yum install java maven nodejs etc. failed"
    if type python3 &>/dev/null; then
        _log "WARN" "python3 is already in the $PATH so not installing"
    else
        local _pwd="$(pwd)"
        [ ! -d "/usr/src" ] && mkdir -v -p /usr/src
        cd "/usr/src"
        local _py_ver="3.7.11"
        _log "INFO" "Installing python ${_py_ver} ..."
        [ ! -s "./Python-${_py_ver}.tgz" ] && curl -fL -O "https://www.python.org/ftp/python/${_py_ver}/Python-${_py_ver}.tgz"
        tar -xzf ./Python-${_py_ver}.tgz && cd Python-${_py_ver} && \
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
    yum-config-manager --add-repo=https://copr.fedorainfracloud.org/coprs/carlwgeorge/ripgrep/repo/epel-7/carlwgeorge-ripgrep-epel-7.repo && yum install -y ripgrep
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
    curl -fL -o /etc/yum.repos.d/microsoft-prod.repo https://packages.microsoft.com/config/rhel/7/prod.repo --compressed && yum install -y powershell
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
    _log "INFO" "Setting up Rubygem (2.3?), which requires git version 1.8.4 or higher ..."
    # @see: https://www.server-world.info/en/note?os=CentOS_7&p=ruby23
    #       Also need git newer than 1.8.8, but https://github.com/iusrepo/git216/issues/5
    if ! type git &>/dev/null || git --version | grep -q 'git version 1.'; then
        _log "INFO" "Updating git for Rubygem ..."
        yum remove -y git*
        yum install -y https://packages.endpointdev.com/rhel/7/os/x86_64/endpoint-repo.x86_64.rpm
        yum --disablerepo=nexusrepo-test --enablerepo=endpoint install -y git || _log "ERROR" "'yum install git' for git v2 failed"
    fi

    # Enabling ruby 2.6 globally for Bundler|bundle and cocoapods (can't remember why 2.3 was used)
    for rb in "26"; do
        if [ ! -s /opt/rh/rh-ruby${rb}/enable ]; then   # not ruby-devel
            yum install -y rh-ruby${rb} rh-ruby${rb}-ruby-devel rubygems
        fi
        cat << EOF > "/etc/profile.d/rh-ruby${rb}.sh"
#!/bin/bash
source /opt/rh/rh-ruby${rb}/enable
export X_SCLS="\$(scl enable rh-ruby${rb} 'echo \$X_SCLS')"
EOF
    done
    _log "INFO" "Install Bundler (bundle) -v 2.4.13 ..."
    bash -l -c "gem install bundle -v 2.4.13"
    # NOTE: At this moment, the newest cocoapods fails with "Failed to build gem native extension"
    _log "INFO" "Install cocoapods 1.8.4 (for ruby 2.6)..."
    # mkmf.rb can't find header files for ruby at /opt/...
    bash -l -c "gem install cocoapods -v 1.8.4" # To reload shell just in case
    # it's very hard to use cocoapods pod command without trusting certificate
    if [ ! -f /etc/pki/ca-trust/source/anchors/rootCA_standalone.crt ] && [ -s /var/tmp/share/cert/rootCA_standalone.crt ]; then
        cp -v /var/tmp/share/cert/rootCA_standalone.crt /etc/pki/ca-trust/source/anchors/ && update-ca-trust
    fi

    # golang requires git, so installing in here
    _log "INFO" "Install go/golang and adding GO111MODULE=on ..."
    rpm --import https://mirror.go-repo.io/centos/RPM-GPG-KEY-GO-REPO
    curl -fL https://mirror.go-repo.io/centos/go-repo.repo --compressed > /etc/yum.repos.d/go-repo.repo
    ${_yum_install} golang || _log "ERROR" "'yum install golang' failed"
    cat << EOF > /etc/profile.d/go-proxy.sh
export GO111MODULE=on
EOF
    #_log "INFO" "Install HOME/go/bin/dlv ..."
    #sudo -u testuser -i go get github.com/go-delve/delve/cmd/dlv    # '-i' is also required to reload profile
    _log "INFO" "Install (or updating) conda ..."
    if curl -fL -o /var/tmp/Miniconda3-latest-Linux-x86_64.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh --compressed; then
        if [ -d /usr/local/miniconda3 ]; then
            bash /var/tmp/Miniconda3-latest-Linux-x86_64.sh -b -u -p /usr/local/miniconda3
        else
            bash /var/tmp/Miniconda3-latest-Linux-x86_64.sh -b -p /usr/local/miniconda3
        fi && chmod -R a+w /usr/local/miniconda3 && ln -v -w -sf /usr/local/miniconda3/bin/conda /usr/local/bin/conda
        if [ -s /usr/local/miniconda3/bin/python ]; then
            /usr/local/miniconda3/bin/python -m pip install chardet
        else
            pip3 install chardet
        fi
    fi
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
function f_nexus_change_pwd() {
    local __doc__="Change admin password with API"
    local _username="${1}"
    local _new_pwd="${2:-"${_username}123"}"
    local _current_pwd="${3}"
    local _base_dir="${4:-"."}"
    [ -z "${_current_pwd}" ] && _current_pwd="$(find ${_base_dir%/} -maxdepth 4 -name "admin.password" -print | head -n1 | xargs cat)"
    [ -z "${_current_pwd}" ] && return 112
    f_api "/service/rest/beta/security/users/${_username}/change-password" "${_new_pwd}" "PUT" "admin" "${_current_pwd}"
}

function f_put_realms() {
    local __doc__="PUT some security realms"
    local _append_realm="$1"    #SamlRealm
    local _realms="\"NexusAuthenticatingRealm\",\"User-Token-Realm\",\"rutauth-realm\",\"DockerToken\",\"ConanToken\",\"NpmToken\",\"NuGetApiKey\",\"LdapRealm\""
    # NOTE: ,\"NexusAuthorizingRealm\" was removed from 3.61
    f_api "/service/rest/v1/security/realms/available" | grep -q '"NexusAuthorizingRealm"' && _realms="\"NexusAuthenticatingRealm\",\"NexusAuthorizingRealm\",\"User-Token-Realm\",\"rutauth-realm\",\"DockerToken\",\"ConanToken\",\"NpmToken\",\"NuGetApiKey\",\"LdapRealm\""
    # Keep using SAML Realm only if it is already active (otherwise, "Sign in" always shows the SSO popup)
    f_api "/service/rest/v1/security/realms/active" | grep -q '"SamlRealm"' && _realms="${_realms},\"SamlRealm\""
    if [ -n "${_append_realm}" ] && ! echo "${_realms}" | grep -q "${_append_realm}"; then
        _realms="${_realms},\"${_append_realm}\""
    fi
    f_api "/service/rest/v1/security/realms/active" "[${_realms}]" "PUT" || return $?
}

function f_enable_quarantines() {
    local __doc__="Enable Firewall Audit & Quarantine capability against *all* proxy repositories"
    local _proxy_name_rx="${1:-"[^\"]+"}"
    f_api "/service/rest/v1/repositories" | grep -B2 -E '^\s*"type"\s*:\s*"proxy"' | sed -n -E 's/^ *"name": *"('${_proxy_name_rx}')".*/\1/p' | while read -r _repo; do
        f_iq_quarantine "${_repo}"
    done
}

#f_create_cleanup_policy "1dayold" "" "" "1"
function f_create_cleanup_policy() {
    local __doc__="Create a cleanup policy. NOTE: a backslash needs to be escaped with 3 more backslashes"
    local _policy_name="${1}"
    local _asset_matcher="${2}" # .+
    local _format="${3}"        # maven2
    local _age_days="${4}"
    local _usage_days="${5}"
    [ -z "${_policy_name}" ] && _policy_name="clean_${format:-"all"}"
    [ -n "${_asset_matcher}" ] && _asset_matcher="\"${_asset_matcher}\""
    [ -n "${_age_days}" ] && _age_days="\"${_age_days}\""
    [ -n "${_usage_days}" ] && _usage_days="\"${_usage_days}\""
    #{"name":"all","notes":"","format":"*","criteriaLastBlobUpdated":"1","criteriaLastDownloaded":"1","criteriaReleaseType":null,"criteriaAssetRegex":null,"retain":null,"sortBy":null}
    f_api "/service/rest/internal/cleanup-policies" "{\"name\":\"${_policy_name}\",\"notes\":\"\",\"format\":\"${_format:-"*"}\",\"criteriaLastBlobUpdated\":${_age_days:-"null"},\"criteriaLastDownloaded\":${_usage_days:-"null"},\"criteriaReleaseType\":null,\"criteriaAssetRegex\":${_asset_matcher:-"null"},\"retain\":null,\"sortBy\":null}" || return $?
}
#UPDATE docker_asset SET last_downloaded = (created - interval '240 days') WHERE kind = 'MANIFEST' AND created > (now() - interval '1 day');
#UPDATE docker_asset_blob SET blob_created = (blob_created - interval '1000 days') WHERE added_to_repository > (now() - interval '1 day');
#f_api "/service/rest/internal/cleanup-policies" "{\"name\":\"maven2-without-sort\",\"notes\":null,\"format\":\"maven2\",\"criteriaLastBlobUpdated\":1,\"criteriaReleaseType\":\"RELEASES\",\"retain\":\"10\"}"

# To restrict DELETE for npm logout
#f_create_csel "npm-logout" "format == 'npm' and path =^ '/-/user/token/'" "npm-hosted" "delete"
function f_create_csel() {
    local __doc__="Create/add a test content selector"
    local _csel_name="${1:-"csel-test"}"
    local _expression="${2:-"format == 'raw' and path =^ '/test/'"}" # TODO: currently can't use double quotes
    local _repos="${3:-"*"}"
    local _actions="${4:-"*"}"
    f_api "/service/rest/v1/security/content-selectors" "{\"name\":\"${_csel_name}\",\"description\":\"\",\"expression\":\"${_expression}\"}" || return $?
    _apiS '{"action":"coreui_Privilege","method":"create","data":[{"id":"NX.coreui.model.Privilege-99","name":"'${_csel_name}'-priv","description":"","version":"","type":"repository-content-selector","properties":{"contentSelector":"'${_csel_name}'","repository":"'${_repos}'","actions":"'${_actions}'"}}],"type":"rpc"}'
}

# Create a test user and test role
function f_create_testuser() {
    local __doc__="Create/add a test user with a test role"
    local _userid="${1:-"testuser"}"
    local _privs="${2-"\"nx-repository-view-*-*-*\",\"nx-search-read\",\"nx-component-upload\",\"nx-usertoken-current\",\"nx-apikey-all\""}"
    # NOTE: nx-usertoken-current does not work with OSS because no User Token
    #       nx-apikey-all is needed for Nuget AP key...
    local _role="${3-"test-role"}"
    if [ -n "${_role}" ]; then
        f_api "/service/rest/v1/security/roles" "{\"id\":\"${_role}\",\"name\":\"${_role} name\",\"description\":\"${_role} desc\",\"privileges\":[${_privs}],\"roles\":[]}"
    fi
    _apiS '{"action":"coreui_User","method":"create","data":[{"userId":"'${_userid}'","version":"","firstName":"test","lastName":"user","email":"'${_userid}'@example.com","status":"active","roles":["'${_role:-"nx-anonymous"}'"],"password":"'${_userid}'"}],"type":"rpc"}'
}

function f_setup_https() {
    local __doc__="Enable HTTPS/SSL by using the provided .jks which contains key/cert"
    local _jks="${1}"   # If empty, will use *.standalone.localdomain cert.
    local _port="${2:-"8443"}"
    local _pwd="${3:-"password"}"
    local _alias="${4}"
    local _work_dir="${5}"
    local _inst_dir="${6}"
    local _usr="${7}"

    [ -z "${_inst_dir}" ] && _inst_dir="$(_get_inst_dir)"
    [ -z "${_inst_dir%/}" ] && return 10
    [ -z "${_work_dir}" ] && _work_dir="$(_get_work_dir)"
    [ -z "${_work_dir%/}" ] && return 11

    if [ ! -d "${_work_dir%/}/etc/ssl" ]; then
        mkdir -v -p ${_work_dir%/}/etc/ssl || return $?
        [ -n "${_usr}" ] && chown "${_usr}" ${_work_dir%/}/etc/ssl
    fi
    if [ -s "${_work_dir%/}/etc/ssl/keystore.jks" ]; then
        _log "INFO" "${_work_dir%/}/etc/ssl/keystore.jks exits. reusing ..."; sleep 1
    else
        if [ -n "${_jks}" ]; then
            cp -v -f "${_jks}" "${_work_dir%/}/etc/ssl/keystore.jks" || return $?
        else
            curl -sSf -L -o "${_work_dir%/}/etc/ssl/keystore.jks" "${_DL_URL%/}/misc/standalone.localdomain.jks" || return $?
            _log "INFO" "No jks file specified. Downloaded standalone.localdomain.jks ..."
        fi
        [ -n "${_usr}" ] && chown "${_usr}" ${_work_dir%/}/etc/ssl/keystore.jks && chmod 600 ${_work_dir%/}/etc/ssl/keystore.jks
    fi

    if [ -z "${_alias}" ]; then
        _alias="$(keytool -list -v -keystore ${_work_dir%/}/etc/ssl/keystore.jks -storepass "${_pwd}" 2>/dev/null | _sed -nr 's/Alias name: (.+)/\1/p')"
        _log "INFO" "Using '${_alias}' as alias name..." && sleep 1
    fi

    _log "INFO" "Updating ${_work_dir%/}/etc/nexus.properties ..."
    if [ ! -s ${_work_dir%/}/etc/nexus.properties.orig ]; then
        cp -p ${_work_dir%/}/etc/nexus.properties ${_work_dir%/}/etc/nexus.properties.orig || return $?
    fi
    _upsert ${_work_dir%/}/etc/nexus.properties "application-port-ssl" "${_port}" || return $?
    _upsert ${_work_dir%/}/etc/nexus.properties "ssl.etc" "\${karaf.data}/etc/ssl" || return $?
    _upsert ${_work_dir%/}/etc/nexus.properties "nexus-args" "\${jetty.etc}/jetty.xml,\${jetty.etc}/jetty-http.xml,\${karaf.data}/etc/jetty/jetty-https.xml,\${jetty.etc}/jetty-requestlog.xml" || return $?

    local _needToSed=true
    if [ ! -f ${_work_dir%/}/etc/jetty/jetty-https.xml ]; then
        [ ! -d "${_work_dir%/}/etc/jetty" ] && mkdir -v -p ${_work_dir%/}/etc/jetty
        if [ -d "${_inst_dir%/}" ]; then
            cp -v -p ${_inst_dir%/}/etc/jetty/jetty-https.xml ${_work_dir%/}/etc/jetty/ || return $?
        else
            curl -sSf -L -o "${_work_dir%/}/etc/jetty/jetty-https.xml" "${_DL_URL%/}/misc/nexus-jetty-https.xml" || return $?
            _needToSed=false
        fi
    fi

    if ${_needToSed}; then
        _log "INFO" "Updating ${_work_dir%/}/etc/jetty/jetty-https.xml ..."
        # Check <Set name="KeyStorePassword">password</Set> and <Set name="KeyStorePassword"/>
        # Also if it's already customised, don't forget to check "KeyStorePath", which default is ("ssl.etc" + ???) /keystore.jks
        for _name in "KeyStorePassword" "KeyManagerPassword" "TrustStorePassword"; do
            _sed -i -r "s@<Set name=.${_name}.+>@<Set name=\"${_name}\">${_pwd}</Set>@gI" ${_work_dir%/}/etc/jetty/jetty-https.xml || return $?
        done
        # Doc says alias is optional, but didn't work when it was wrong.
        if [ -n "${_alias}" ]; then
            if ! grep -q '<Set name="certAlias">' ${_work_dir%/}/etc/jetty/jetty-https.xml; then
                _sed -i '/<Set name="KeyStorePath">/i \
    <Set name="certAlias">'${_alias}'</Set>' ${_work_dir%/}/etc/jetty/jetty-https.xml
            fi
        fi
        # Jetty behaviour change: https://github.com/eclipse/jetty.project/issues/4425 (from Nexus 3.26)
        if [[ "${_ver}" =~ ^(3\.26|3\.27|3\.28) ]]; then
            _sed -i 's@class=\"org.eclipse.jetty.util.ssl.SslContextFactory\"@class=\"org.eclipse.jetty.util.ssl.SslContextFactory\$Server\"@g' ${_work_dir%/}/etc/jetty/jetty-https.xml
        fi
    fi
    _log "INFO" "Please restart service.
Also update _NEXUS_URL. For example: export _NEXUS_URL=\"https://local.standalone.localdomain:${_port}/\""
    if [[ "${_NEXUS_URL}" =~ https?://([^:/]+) ]]; then
        local _hostname="${BASH_REMATCH[1]}"
        if [ ${_hostname} == "localhost" ]; then
            _hostname="${_NEXUS_DOCKER_HOSTNAME:-"$(hostname -f)"}"
        fi
        echo "To check the SSL connection:
    curl -svf -k \"https://${_hostname}:${_port}/\" -o/dev/null 2>&1 | grep 'Server certificate:' -A 5"
    fi
    # TODO: generate pem file and trust
    #_trust_ca "${_ca_pem}" || return $?
    _log "INFO" "To trust this certificate, _trust_ca \"\${_ca_pem}\""
}



function f_setup_reverse_proxy() {
    local __doc__="TODO: Setup reverse proxy server with caddy"
    local _install_dir="${1:-"${_SHARE_DIR%/}/caddy"}"
    local _ver="${2:-"2.10.0"}"
    # https://github.com/caddyserver/caddy/releases/download/v2.10.0/caddy_2.10.0_linux_amd64.tar.gz
    local _file_prefix="caddy_${_ver}_linux"
    if [ "$(uname)" == "Darwin" ]; then
        # https://github.com/caddyserver/caddy/releases/download/v2.10.0/caddy_2.10.0_mac_arm64.tar.gz
        _file_prefix="caddy_${_ver}_mac"
    fi
    local _file_name="${_file_prefix}_$(uname -m).tar.gz"
    if [ -d "${_install_dir%/}" ]; then
        mkdir -v -p "${_install_dir%/}" || return $?
    fi
    cd "${_install_dir%/}" || return $?
    if [ ! -s "${_file_name}" ]; then
        curl -O -L "https://github.com/caddyserver/caddy/releases/download/v${_ver}/${_file_name}" || return $?
    fi
    if [ ! -s "${_file_name}" ]; then
        _log "ERROR" "Downloading ${_install_dir%/}/${_file_name} failed. Please check the URL."
        return 1
    fi
    tar -xf ${_file_name} caddy || return $?
    chmod u+x caddy || return $?
}
function f_start_reverse_proxy() {
    local __doc__="Install and start a reverse proxy server with caddy"
    local _port="${1:-"8080"}"
    local _install_dir="${2:-"${_SHARE_DIR%/}/caddy"}"
    local _ver="${3:-"2.10.0"}"
    if type caddy &>/dev/null; then
        _log "INFO" "Caddy is already installed in the PATH. Using it ..."
    else
        f_setup_reverse_proxy "${_install_dir}" "${_ver}" || return $?
    fi
    # TODO: not completed
}

# friendly attributes {uid=[samluser], eduPersonAffiliation=[users], givenName=[saml], eduPersonPrincipalName=[samluser@standalone.localdomain], cn=[Saml User], sn=[user]}
# NXRM3 meta: curl -o ${_sp_meta_file} -u "admin:admin123" "http://localhost:8081/service/rest/v1/security/saml/metadata"
function f_start_saml_server() {
    # SAML server: https://github.com/hajimeo/samples/blob/master/golang/SamlTester/README.md
    local __doc__="Install and start a dummy SAML service"
    local _idp_base_url="${1:-"http://localhost:2080/"}"
    local _sp_meta_file="${2}"
    local _sp_meta_url="${3}"   # If IQ: http://localhost:8070/api/v2/config/saml/metadata (cab be multiple with space delimiter)
    local _sp_uid="${4-"${_ADMIN_USER}"}"
    local _sp_pwd="${5-"${_ADMIN_PWD}"}"
    local _install_dir="${6:-"${_SHARE_DIR%/}/simplesaml"}"
    local _users_json="${7:-"${_install_dir%/}/simple-saml-idp.json"}"

    if [ -z "${_sp_meta_url}" ]; then
        if [ -n "${_NEXUS_URL%/}" ]; then   # && _isUrl "${_NEXUS_URL%/}/service/rest/v1/status" "Y"
            _sp_meta_url="${_NEXUS_URL%/}/service/rest/v1/security/saml/metadata"
        else
            _sp_meta_url="http://localhost:8081/service/rest/v1/security/saml/metadata"
        fi
        if [ -n "${_IQ_URL%/}" ]; then   # && _isUrl "${_IQ_URL%/}/ping" "Y"
            _sp_meta_url="${_sp_meta_url} ${_IQ_URL%/}/api/v2/config/saml/metadata"
        else
            _sp_meta_url="${_sp_meta_url} http://localhost:8070/api/v2/config/saml/metadata"
        fi
    fi

    # Installing simplesamlidp
    if [ ! -d "${_install_dir%/}" ]; then
        mkdir -v -p "${_install_dir%/}" || return $?
    fi
    local _cmd="simplesamlidp"  # If not in the PATH, download it
    if ! type ${_cmd} &>/dev/null; then
        if [ ! -s "${_install_dir%/}/simplesamlidp" ]; then
            curl -o "${_install_dir%/}/simplesamlidp" -L "https://github.com/hajimeo/samples/raw/master/misc/simplesamlidp_$(uname)_$(uname -m)" --compressed || return $?
            chmod u+x "${_install_dir%/}/simplesamlidp" || return $?
        fi
        _cmd="${_install_dir%/}/simplesamlidp"
    fi
    if [ ! -s "${_users_json}" ]; then
        curl -sSf -o "${_users_json}" -L "https://raw.githubusercontent.com/hajimeo/samples/master/misc/simple-saml-idp.json" --compressed  || return $?
    fi

    # If SP metadata file does not exist, download it as samplesamlidp does not support authentication.
    if [ -n "${_sp_meta_url}" ] && [ -z "${_sp_meta_file}" ]; then
        local index=0
        for _url in ${_sp_meta_url}; do
            if [ -n "${_url}" ]; then
                index=$((index + 1))
                local _tmp_file="${_TMP%/}/sp_metadata_${index}.xml"
                _log "INFO" "Downloading SP metafile from ${_url} ..."
                curl -sSf -L -o "${_tmp_file}" -u "${_sp_uid}:${_sp_pwd}" "${_url}"
                if [ -s "${_tmp_file}" ]; then
                    if [ -z "${_sp_meta_file}" ]; then
                        _sp_meta_file="${_tmp_file}"
                    else
                        _sp_meta_file="${_sp_meta_file},${_tmp_file}"
                    fi
                fi
            fi
        done
        if [ -z "${_sp_meta_file}" ]; then
            _log "WARN" "No SP metadata file downloaded. Please check the service is configured for SAML (f_setup_saml_simplesaml for RM3 or IQ)"
            _log "WARN" "But still starting to save the IDP metadata to ${_TMP%/}/idp_metadata.xml ..."
            _log "WARN" "As RM3 and IQ requires authentication, may need to restart this IdP."
            _sp_meta_file="${_sp_meta_url}"
        fi
    fi
    # If no key/cert, generate it
    if [ ! -s ${_install_dir%/}/myidp.key ]; then
        openssl req -x509 -newkey rsa:2048 -keyout ${_install_dir%/}/myidp.key -out ${_install_dir%/}/myidp.crt -days 3650 -nodes -subj "/CN=$(hostname -f)" || return $?
    fi

    export IDP_KEY="${_install_dir%/}/myidp.key" IDP_CERT="${_install_dir%/}/myidp.crt" USER_JSON="${_users_json}" IDP_BASE_URL="${_idp_base_url}" SERVICE_METADATA_URL="${_sp_meta_file}" SERVICE_UID="${_sp_uid}" SERVICE_PWD="${_sp_pwd}"
    _log "INFO" "Starting IdP with SERVICE_METADATA_URL SP metafiles from ${SERVICE_METADATA_URL} ..."
    eval "${_cmd}" &> ${_TMP%/}/simplesamlidp_$$.log &
    local _pid="$!"
    sleep 2
    if ! jobs -l | grep -w "${_pid}" | grep -q -w Running; then
        _log "ERROR" "simplesamlidp failed to start. Please check ${_TMP%/}/simplesamlidp_$$.log"
        return 1
    fi
    curl -sf -o ${_TMP%/}/idp_metadata.xml "${_idp_base_url%/}/metadata" || return $?
    echo "[INFO] Running simplesamlidp in background ..."
    echo "       PID: ${_pid}  Log: ${_TMP%/}/simplesamlidp_$$.log"
    echo "       users/groups: ${USER_JSON}"
    echo "       IdP metadata: ${_TMP%/}/idp_metadata.xml"
    #echo "       curl -D- -X PUT -u admin:admin123 http://localhost:8070/api/v2/roleMemberships/global/role/b9646757e98e486da7d730025f5245f8/group/ipausers"
    if [ ! -s "${_sp_meta_file}" ]; then
        #echo "       Example Attr: {uid=[samluser], eduPersonPrincipalName=[samluser@standalone.localdomain], eduPersonAffiliation=[users], givenName=[saml], sn=[user], cn=[Saml User]}"
        #echo "       So, eduPersonPrincipalName can be used for 'email', eduPersonAffiliation for 'groups'."
        echo "[INFO] Please execute 'f_setup_saml_simplesaml'. If some login issue, please restart this IdP."
        #echo "       If necessary, save '${_sp_meta_url}' into ${_sp_meta_file}:"
        #echo "       curl -o ${_sp_meta_file} -u \"admin\" \"${_sp_meta_url}\""
    fi
}
function f_setup_saml_simplesaml() {
    local __doc__="Setup SAML for Nexus3 with PUT /v1/security/saml"
    local _entityId="${1:-"${_NEXUS_URL%/}/service/rest/v1/security/saml/metadata"}"
    local _idp_metadata="${2:-"${_TMP%/}/idp_metadata.xml"}"
    if [ ! -s "${_idp_metadata}" ]; then
        echo "Please specify _idp_metadata"; return 1
    fi
    # Escaping \n on Mac is complicated so just removing new lines
    local _idp_meta_str="$(cat "${_idp_metadata}" | sed 's/^[ \t]*//;s/[ \t]*$//;s/\"/\\"/g' | tr -d '\n')"
    if ! f_api "/service/rest/v1/security/saml" "{\"entityId\":\"${_entityId}\",\"idpMetadata\":\"${_idp_meta_str}\",\"usernameAttribute\":\"uid\",\"firstNameAttribute\":\"givenName\",\"lastNameAttribute\":\"sn\",\"emailAttribute\":\"eduPersonPrincipalName\",\"groupsAttribute\":\"eduPersonAffiliation\",\"validateResponseSignature\":false,\"validateAssertionSignature\":false}" "PUT"; then
        echo "If SAML is already configured, please try 'DELETE /service/rest/v1/security/saml' first."
        return 1
    fi
    f_put_realms "SamlRealm"
}

function f_start_dummy_smtp() {
    local __doc__="Install and start a dummy SMTP server with MailHog https://github.com/mailhog/MailHog/blob/master/docs/CONFIG.md"
    local _smtp_port="${1:-"1025"}"
    local _ui_api_port="${1:-"8025"}"
    local _install_dir="${2:-"${_SHARE_DIR%/}/mailhog"}"

    if [ ! -d "${_install_dir%/}" ]; then
        mkdir -v -p "${_install_dir%/}" || return $?
    fi

    # Installing mailhog
    local _cmd="mailhog"  # If not in the PATH, download it
    if ! type ${_cmd} &>/dev/null; then
        if [ ! -s "${_install_dir%/}/mailhog" ]; then
            curl -o "${_install_dir%/}/mailhog" -L "https://github.com/hajimeo/samples/raw/master/misc/mailhog_$(uname)_$(uname -m)" --compressed || return $?
            chmod u+x "${_install_dir%/}/mailhog" || return $?
        fi
        _cmd="${_install_dir%/}/mailhog"
    fi

    eval "${_cmd} -smtp-bind-addr 0.0.0.0:${_smtp_port} -api-bind-addr 0.0.0.0:${_ui_api_port} -ui-bind-addr 0.0.0.0:${_ui_api_port}" &> ${_TMP%/}/mailhog_$$.log &
    local _pid="$!"
    sleep 2
    echo "[INFO] Running mailhog in background http://127.0.0.1:${_ui_api_port}/"
    echo "       PID: ${_pid}  Log: ${_TMP%/}/mailhog_$$.log"
}
function f_setup_smtp_mailhog() {
    local _smtp_port="${1:-"1025"}"
    local _smtp_host="${2:-"localhost"}"
    local _from_addr="${3:-"smtptest@example.com"}"
    # TODO: should use create? or update?
    _apiS '{"action":"coreui_Email","method":"update","data":[{"enabled":true,"host":"'${_smtp_host}'","port":'${_smtp_port}',"username":"","password":"","fromAddress":"'${_from_addr}'","subjectPrefix":"To mailhog - ","startTlsEnabled":false,"startTlsRequired":false,"sslOnConnectEnabled":false,"sslCheckServerIdentityEnabled":false,"nexusTrustStoreEnabled":false}],"type":"rpc"}'
}

function f_start_ldap_server() {
    local __doc__="Install and start a dummy LDAP server with glauth"
    local _install_dir="${1:-"${_SHARE_DIR%/}/glauth"}"
    local _port="${2:-8389}"
    local _download_dir="/tmp"
    if [ ! -d "${_install_dir%/}" ]; then
        mkdir -v -p "${_install_dir%/}" || return $?
    fi
    local _fname="$(uname | tr '[:upper:]' '[:lower:]')$(uname -m).zip"
    if [ "$(uname -m)" == "x86_64" ]; then
        _fname="$(uname | tr '[:upper:]' '[:lower:]')amd64.zip"
    elif [ "$(uname -m)" == "aarch64" ]; then
        _fname="$(uname | tr '[:upper:]' '[:lower:]')arm64.zip"
    fi
    if [ ! -s "${_install_dir%/}/glauth" ]; then
        if [ ! -s "${_download_dir%/}/${_fname}" ]; then
            _log "INFO" "Downloading glauth v2.1.0 ..."
            curl -sf -o "${_download_dir%/}/${_fname}" -L "https://github.com/glauth/glauth/releases/download/v2.1.0/${_fname}" --compressed || return $?
        fi
        if type unzip &>/dev/null; then
            unzip -d "${_install_dir%/}" "${_download_dir%/}/${_fname}" || return $?
        elif type tar &>/dev/null; then
            tar -xzf "${_download_dir%/}/${_fname}" -C "${_install_dir%/}" || return $?
        else
            jar -xvf "${_download_dir%/}/${_fname}" -C "${_install_dir%/}" || return $?
        fi
        chmod u+x "${_install_dir%/}/glauth" || return $?
    else
        _log "INFO" "glauth already exists. Skipping download v2.1.0 / unzip ..."
    fi
    if [ ! -s ${_install_dir%/}/glauth-simple.cfg ]; then
        _log "INFO" "Downloading the sample config into ${_install_dir%/}/glauth-simple.cfg ..."
        curl -sSf -o ${_install_dir%/}/glauth-simple.cfg -L "https://raw.githubusercontent.com/hajimeo/samples/master/misc/glauth-simple.cfg" --compressed || return $?
    fi
    _log "INFO" "Starting glauth with ${_install_dir%/}/glauth-simple.cfg ..."
    # listening 0.0.0.0:8389
    eval "${_install_dir%/}/glauth -c ${_install_dir%/}/glauth-simple.cfg" &> ${_TMP%/}/glauth_$$.log &
    local _pid="$!"
    sleep 2
    if ! jobs -l | grep -w "${_pid}" | grep -q -w Running; then
        _log "ERROR" "glauth failed to start. Please check ${_TMP%/}/glauth_$$.log"
        return 1
    fi
    echo "[INFO] Running glauth in background ..."
    echo "    PID: ${_pid}  Log: ${_TMP%/}/glauth_$$.log"
    echo "    LDAP config: ${_install_dir%/}/glauth-simple.cfg"
    echo "To test:"
    echo "    curl -v -u \"admin@standalone.localdomain\" -k \"ldap://${_host}:${_port}/ou=users,dc=standalone,dc=localdomain?uid,cn,mail,memberof?sub?(&(objectClass=posixAccount)(uid=*))\""   # + userFilter
    echo "To test group mappings (space may need to be changed to %20):"
    echo "    curl -v -u \"cn=ldapadmin,dc=standalone,dc=localdomain\" -k \"ldap://${_host:-"localhost"}:${_port:-"389"}/ou=users,dc=standalone,dc=localdomain?dn,cn,mail,memberof?sub?(&(objectClass=posixAccount)(uid=ldapuser))\"" # + userFilter
    # echo "To test: LDAPTLS_REQCERT=never ldapsearch -H ldap://${_host}:${_port} -b 'dc=standalone,dc=localdomain' -D 'admin@standalone.localdomain' -w '${_LDAP_PWD:-"secret12"}' -s sub '(&(objectClass=posixAccount)(uid=*))'"
    # TODO: Bind request: curl -v -u "cn=ldapuser,ou=ipausers,ou=users,dc=standalone,dc=localdomain:ldapuser" -k "ldap://${_host:-"localhost"}:${_port:-"389"}/dc=standalone,dc=localdomain""   # + userFilter
    echo "    # For STATIC group mapping type:"
    # groupIDAttribute is returned
    echo "    curl -v -u \"cn=ldapadmin,dc=standalone,dc=localdomain\" -k \"ldap://${_host:-"localhost"}:${_port:-"389"}/ou=users,dc=standalone,dc=localdomain?cn?sub?(&(objectClass=posixGroup)(cn=*)(memberUid=ldapuser))\"" # + userFilter
}
function f_gen_glauth_groups_config() {
    local __doc__="Generate/output glauth groups config"
    # @see: https://pkg.go.dev/github.com/gwelch-contegix/glauth/v2/pkg/config
    local _groups="${1}"    # File or space delimited group names
    local _user_name="${2}"
    local _gid_num="${3:-6501}"
    local _uid_num="${4:-5101}"
    local _mail_domain="${5:-"mail.${_DOMAIN#.}"}"
    local _group_lines=""
    if [ -s "${_groups}" ]; then
        _group_lines="$(cat "${_groups}")"
    else
        _group_lines="$(echo "${_groups}" | tr ' ' '\n')"
    fi
    local __other_groups=""
    local __gid_num="${_gid_num}"
    while read -r _line; do
        [ -n "${_line}" ] || continue
        cat << EOF
[[groups]]
name = "${_line}"
gidnumber = ${_gid_num}
EOF
#includegroups = [ ${include_uid} ]    <<< probably for nested group
        if [ -z "${__other_groups}" ]; then
            __other_groups="${__gid_num}"
        else
            __other_groups="${__other_groups}, ${__gid_num}"
        fi
        __gid_num=$(( __gid_num + 1 ))
    done <<< "${_group_lines}"
    if [ -n "${_othergroups}" ]; then
        echo ""
    fi

    if [ -n "${_user_name}" ]; then
        local _mail="${_user_name}@${_mail_domain}"
        local _userid="${_user_name}"
        # If user_name contains "@" use it as email
        if [[ "${_user_name}" =~ ^([^@]+)@.+ ]]; then
            _mail="${_user_name}"
            _userid="${BASH_REMATCH[1]}"
        fi
        cat << EOF
[[users]]
name = "${_user_name}"
givenname="GN${_userid}"
sn="SN${_userid}"
mail = "${_mail}"
uidnumber = ${_uid_num}
primarygroup = ${_gid_num}
passsha256 = "$(echo -n "${_user_name}" | sha256sum | cut -d' ' -f1)"
EOF
        if [ -n "${_othergroups}" ]; then
            echo "othergroups = [ ${__other_groups} ]"
        fi
    fi
}
function f_setup_ldap_glauth() {
    local __doc__="Setup LDAP for GLAuth server."
    local _name="${1:-"glauth"}"
    local _host="${2:-"localhost"}"
    local _port="${3:-"8389"}"   # 636
    #[ -z "${_LDAP_PWD}" ] && _log "WARN" "Missing _LDAP_PWD" && sleep 3
    #nc -z ${_host} ${_port} || return $?
    _apiS '{"action":"ldap_LdapServer","method":"create","data":[{"id":"","name":"'${_name}'","protocol":"ldap","host":"'${_host}'","port":"'${_port}'","searchBase":"dc=standalone,dc=localdomain","authScheme":"simple","authUsername":"admin@standalone.localdomain","authPassword":"'${_LDAP_PWD:-"secret12"}'","connectionTimeout":"30","connectionRetryDelay":"300","maxIncidentsCount":"3","template":"Posix%20with%20Dynamic%20Groups","userBaseDn":"ou=users","userSubtree":true,"userObjectClass":"posixAccount","userLdapFilter":"","userIdAttribute":"uid","userRealNameAttribute":"cn","userEmailAddressAttribute":"mail","userPasswordAttribute":"","ldapGroupsAsRoles":true,"groupType":"dynamic","userMemberOfAttribute":"memberOf"}],"type":"rpc"}' #|| return $?
    # RM3 doesn't have groupSubtree?
    _apiS '{"action":"coreui_Role","method":"create","data":[{"version":"","source":"LDAP","id":"ipausers","name":"ipausers-role","description":"ipausers-role-desc","privileges":["nx-repository-view-*-*-*","nx-search-read","nx-component-upload"],"roles":[]}],"type":"rpc"}'
}

function f_setup_ldap_freeipa_Deprecated() {
    local __doc__="Deprecated: setup LDAP with freeIPA server."
    local _name="${1:-"freeipa"}"
    local _host="${2:-"dh1.standalone.localdomain"}"
    local _port="${3:-"389"}"   # 636
    [ -z "${_LDAP_PWD}" ] && echo "Missing _LDAP_PWD" && return 1
    #nc -z ${_host} ${_port} || return $?
    _apiS '{"action":"ldap_LdapServer","method":"create","data":[{"id":"","name":"'${_name}'","protocol":"ldap","host":"'${_host}'","port":"'${_port}'","searchBase":"cn=accounts,dc=standalone,dc=localdomain","authScheme":"simple","authUsername":"uid=admin,cn=users,cn=accounts,dc=standalone,dc=localdomain","authPassword":"'${_LDAP_PWD}'","connectionTimeout":"30","connectionRetryDelay":"300","maxIncidentsCount":"3","template":"Posix%20with%20Dynamic%20Groups","userBaseDn":"cn=users","userSubtree":false,"userObjectClass":"person","userLdapFilter":"","userIdAttribute":"uid","userRealNameAttribute":"cn","userEmailAddressAttribute":"mail","userPasswordAttribute":"","ldapGroupsAsRoles":true,"groupType":"dynamic","userMemberOfAttribute":"memberOf"}],"type":"rpc"}'
    _apiS '{"action":"coreui_Role","method":"create","data":[{"version":"","source":"LDAP","id":"ipausers","name":"ipausers-role","description":"ipausers-role-desc","privileges":["nx-repository-view-*-*-*","nx-search-read","nx-component-upload"],"roles":[]}],"type":"rpc"}'
}

function f_repository_replication_Deprecated() {
    local __doc__="DEPRECATED: Setup Repository Replication v1 using 'admin' user"
    local _src_repo="${1:-"raw-hosted"}"
    local _tgt_repo="${2:-"raw-repl-hosted"}"
    local _target_url="${3:-"http://$(hostname):8081/"}"
    local _src_blob="${4:-"${_BLOBTORE_NAME}"}"
    local _tgt_blob="${5:-"test"}"
    local _ds_name="${6:-"${r_DATASTORE_NAME:-"${_DATASTORE_NAME}"}"}"
    local _workingDirectory="${7:-"${_WORKING_DIR:-"/opt/sonatype/sonatype-work/nexus3"}"}"
    [ -z "${_ds_name}" ] && _ds_name="$(_get_datastore_name)"
    local _extra_sto_opt="$(_get_extra_sto_opt "${_ds_name}")"
    curl -sS -f -k -I "${_target_url}" >/dev/null || return $?

    # It's OK if can't create blobs/repos as this could be due to permission.
    if ! _is_blob_available "${_src_repo}"; then
        _apiS '{"action":"coreui_Blobstore","method":"create","data":[{"type":"File","name":"'${_src_blob}'","isQuotaEnabled":false,"attributes":{"file":{"path":"'${_src_blob}'"}}}],"type":"rpc"}' &> ${_TMP%/}/f_setup_repo_repl.out
    fi
    if ! _is_blob_available "${_tgt_repo}" "${_target_url}" ; then
        _NEXUS_URL="${_target_url}" _apiS '{"action":"coreui_Blobstore","method":"create","data":[{"type":"File","name":"'${_tgt_blob}'","isQuotaEnabled":false,"attributes":{"file":{"path":"'${_tgt_blob}'"}}}],"type":"rpc"}' &> ${_TMP%/}/f_setup_repo_repl.out
    fi
    if ! _is_repo_available "${_src_repo}"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_src_blob}'","writePolicy":"ALLOW","strictContentTypeValidation":false'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_src_repo}'","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}'
    fi
    if ! _is_repo_available "${_tgt_repo}" "${_target_url}" ; then
        _NEXUS_URL="${_target_url}" _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_tgt_blob}'","writePolicy":"ALLOW","strictContentTypeValidation":false'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_tgt_repo}'","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}'
    fi

    _apiS '{"action":"capability_Capability","method":"create","data":[{"id":"NX.coreui.model.Capability-1","typeId":"replication","notes":"","enabled":true,"properties":{}}],"type":"rpc"}' && sleep 2
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

function f_upload_dummies_raw() {
    local __doc__="Upload text files into raw hosted repository by using f_upload_dummies"
    local _repo_name="${1:-"raw-hosted"}"
    local _how_many="${2:-"10"}"
    local _parallel="${3:-"5"}"
    local _path="${4:-"dummies"}"
    local _file_prefix="${5}"
    local _file_suffix="${6:-".txt"}"
    local _sub_dir_depth="${7:-"${_SUB_DIR_DEPTH:-3}"}"
    local _usr="${8:-"${_ADMIN_USER}"}"
    local _pwd="${9:-"${_ADMIN_PWD}"}"

    local _repo_path="${_NEXUS_URL%/}/repository/${_repo_name}/${_path#/}"
    local _seq_start="${_SEQ_START:-1}"
    local _seq_end="$((${_seq_start} + ${_how_many} - 1))"
    local _seq="seq ${_seq_start} ${_seq_end}"
    [[ "${_how_many}" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]] && _seq="seq ${_how_many}"

    if ! _is_repo_available "${_repo_name}"; then
        local _ds_name="$(_get_datastore_name)"
        local _bs_name="$(_get_blobstore_name)"
        local _extra_sto_opt="$(_get_extra_sto_opt "${_ds_name}")"
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":false'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_repo_name}'","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}' || return $?
    fi

    # -T<(echo "aaa") may not work with old bash, also somehow some of files become 0 byte, so creating a file
    echo "test at $(date +'%Y-%m-%d %H:%M:%S')" > ${_TMP%/}/${FUNCNAME[0]}_$$.txt || return $?

    for i in $(eval "${_seq}"); do
        if [ -z "${_file_prefix}" ]; then
            local _final_prefix=""
            local _rand_depth=$((RANDOM % (${_sub_dir_depth:-3} + 1)))
            if [ ${_rand_depth} -gt 0 ]; then
                for j in $(seq 1 ${_rand_depth}); do
                    local _k=$((RANDOM % ${_sub_dir_depth:-3} + 1))
                    _final_prefix="${_final_prefix}test_subdir${_k}/"
                done
            fi
            _final_prefix="${_final_prefix}test_"
        else
            _final_prefix="${_file_prefix}"
        fi
        echo "${_final_prefix}${i}${_file_suffix}"
    done | xargs -I{} -P${_parallel} curl -sf -u "${_usr}:${_pwd}" -w '%{http_code} '${_path%/}/'{} (%{time_total}s)\n' -T ${_TMP%/}/${FUNCNAME[0]}_$$.txt -L -k "${_repo_path%/}/{}"
    # NOTE: xargs only stops if exit code is 255
}

function f_upload_dummies_raw_with_api() {
    local __doc__="Upload text files into raw hosted repository with Upload API"
    local _repo_name="${1:-"raw-hosted"}"
    local _how_many="${2:-"10"}"
    local _file_prefix="${3:-"test_"}"
    local _file_suffix="${4:-".txt"}"
    for i in `seq ${_SEQ_START:-1} $((${_SEQ_START:-1} + ${_how_many} - 1))`; do
        echo "test by f_upload_dummies_raw_with_api at $(date +'%Y-%m-%d %H:%M:%S')" > ${_TMP%/}/${FUNCNAME[0]}_$$.txt || return $?
        f_upload_asset "${_repo_name}" -F raw.directory=/dummies -F raw.asset1=@${_TMP%/}/${FUNCNAME[0]}_$$.txt -F raw.asset1.filename=${_file_prefix}${i}${_file_suffix} || return $?
    done
}

function f_upload_dummies_raw_from_list() {
    local __doc__="Upload files, which paths are in a text file, into a raw hosted repository"
    local _repo_name="${1:-"raw-hosted"}"
    local _list_file="${2}"
    local _parallel="${3:-"5"}"
    local _usr="${4:-"${_ADMIN_USER}"}"
    local _pwd="${5:-"${_ADMIN_PWD}"}"
    if [ -z "${_list_file}" ] || [ ! -s "${_list_file}" ]; then
        _log "ERROR" "Please specify _list_file"
        return 1
    fi
    local _repo_path="${_NEXUS_URL%/}/repository/${_repo_name}/"
    echo "test by f_upload_dummies_raw_from_list" > ${_TMP%/}/${FUNCNAME[0]}_$$.txt || return $?
    cat "${_list_file}" | xargs -I{} -P${_parallel} curl -sf -u "${_usr}:${_pwd}" -w '%{http_code} {} (%{time_total}s)\n' -T ${_TMP%/}/${FUNCNAME[0]}_$$.txt -L -k "${_repo_path%/}/{}"
}

function _gen_dummy_jar() {
    local _filepath="${1:-"${_TMP%/}/dummy.jar"}"
    if [ ! -s "${_filepath}" ]; then
        if type jar &>/dev/null; then
            echo "test at $(date +'%Y-%m-%d %H:%M:%S')" > dummy.txt
            jar -cf ${_filepath} dummy.txt || return $?
            rm -f dummy.txt
        else
            curl -o "${_filepath}" "https://repo1.maven.org/maven2/org/sonatype/goodies/goodies-i18n/2.3.4/goodies-i18n-2.3.4.jar" || return $?
        fi
    fi
}

function _gen_mvn_settings() {
    local _setting_path="${1:-"./m2_settings.xml"}"
    if [ -s "${_setting_path}" ]; then
        echo "WARN ${_setting_path} already exists"
        return 1
    fi
    cat << 'EOF' > "${_setting_path}"
<settings>
    <servers>
        <server>
            <id>${repo.id}</id>
            <username>${repo.login}</username>
            <password>${repo.pwd}</password>
        </server>
    </servers>
</settings>
EOF
}

#f_deploy_maven "maven-hosted" "/tmp/dummy.jar" "my.deploy.test:dummy:1.0" "-Dpackaging=jar -DcreateChecksum=true"
function f_deploy_maven() {
    local _repo_name="${1}"
    local _file="${2}"
    local _gav="${3}"
    local _options="${4}"   # -DcreateChecksum=true
    local _usr="${5:-"${_ADMIN_USER}"}"
    local _pwd="${6:-"${_ADMIN_PWD}"}"
    [ -z "${_repo_name}" ] && return 11
    [ ! -f "${_file}" ] && return 12
    [[ "${_gav}" =~ ^" "*([^: ]+)" "*:" "*([^: ]+)" "*:" "*([^: ]+)" "*$ ]] || return 13
    local _g="${BASH_REMATCH[1]}"
    local _a="${BASH_REMATCH[2]}"
    local _v="${BASH_REMATCH[3]}"
    local _repo_url="${_NEXUS_URL%/}/repository/${_repo_name%/}/"
    # https://issues.apache.org/jira/browse/MRESOLVER-56     -Daether.checksums.algorithms="SHA256,SHA512"
    if [ ! -s "${_TMP%/}/m2_settings.xml" ]; then
        _gen_mvn_settings "${_TMP%/}/m2_settings.xml" || return $?
    fi
    #-DaltDeploymentRepository="nexusDummy::default::${_repo_url}"
    local _cmd="mvn -s \"${_TMP%/}/m2_settings.xml\" deploy:deploy-file -Durl=${_repo_url} -Dfile=\"${_file}\" -DrepositoryId=\"nexusDummy\" -Drepo.id=\"nexusDummy\" -DgroupId=\"${_g}\" -DartifactId=\"${_a}\" -Dversion=\"${_v}\" -DgeneratePom=true -Drepo.login=\"${_usr}\" ${_options}"
    echo "${_cmd}"
    eval "${_cmd} -Drepo.pwd=\"${_pwd}\""
}

# Example of uploading 100 versions 9 concurrency (total 900 + 10)
: <<'EOF'
# test first (if 400, might be due to Deployment policy)
f_upload_dummies_maven "maven-hosted" "10" "3" "setup.nexus3.repos0" "dummy0"
for g in {1..3}; do
  for a in {1..3}; do
    f_upload_dummies_maven "maven-hosted" "50" "1" "setup.nexus3.repos${g}" "dummy${a}" &
  done
done; wait

# creating 1010 GA with 10 version (101 * 10 * 10 = 10100) with 3x10 concurrency
for g in {1..101}; do
  for a in {1..10}; do
    f_upload_dummies_maven "maven-hosted" "10" "3" "setup.nexus3.repos${g}" "dummy${a}" &
  done; wait
done
EOF
alias f_upload_dummies_maven2='f_upload_dummies_maven'
function f_upload_dummies_maven() {
    local __doc__="Upload dummy jar files into maven hosted repository"
    local _repo_name="${1:-"maven-releases"}"
    local _how_many_vers="${2:-"10"}"    # this is used for versions
    local _parallel="${3:-"3"}"
    local _g="${4:-"setup.nexus3.repos"}"
    local _a="${5:-"dummy"}"
    local _ver_sfx="${6:-"${_MVN_VER_SFX}"}"   # Can't use '-SNAPSHOT' as "Upload to snapshot repositories not supported"
    local _usr="${7:-"${_ADMIN_USER}"}"
    local _pwd="${8:-"${_ADMIN_PWD}"}"

    if ! _is_repo_available "${_repo_name}"; then
        local _ds_name="$(_get_datastore_name)"
        local _bs_name="$(_get_blobstore_name)"
        local _extra_sto_opt="$(_get_extra_sto_opt "${_ds_name}")"
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"RELEASE","layoutPolicy":"STRICT"},"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW_ONCE","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_repo_name}'","format":"","type":"","url":"","online":true,"recipe":"maven2-hosted"}],"type":"rpc"}' || return $?
    fi

    # _SEQ_START is for continuing
    local _seq_start="${_SEQ_START:-1}"
    local _seq_end="$((${_seq_start} + ${_how_many_vers} - 1))"
    local _seq="seq ${_seq_start} ${_seq_end}"
    [[ "${_how_many_vers}" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]] && _seq="seq ${_how_many_vers}"

    _gen_dummy_jar "${_TMP%/}/dummy.jar" || return $?

    # The below 'export' does not work with Mac's bash...
    #export -f f_upload_asset
    for i in $(eval "${_seq}"); do
      echo "$i${_ver_sfx}"
    done | xargs -I{} -P${_parallel} curl -sf -u "${_usr}:${_pwd}" -w "%{http_code} ${_g}:${_a}:{} (%{time_total}s)\n" -H "accept: application/json" -H "Content-Type: multipart/form-data" -X POST -k "${_NEXUS_URL%/}/service/rest/v1/components?repository=${_repo_name}" -F maven2.groupId=${_g} -F maven2.artifactId=${_a} -F maven2.version={} -F maven2.asset1=@${_TMP%/}/dummy.jar -F maven2.asset1.extension=jar
    # TODO: -F maven2.generate-pom=true is not working
    # NOTE: xargs only stops if exit code is 255
}

# Example of uploading 100 snapshots each with 27 concurrency (total 2700)
: <<'EOF'
# test first
f_upload_dummies_maven_snapshot "maven-snapshots" 10 "com.example0" "my-app0" "0.0-SNAPSHOT"
for g in {1..3}; do
  for a in {1..3}; do
    for v in {1..3}; do
      f_upload_dummies_maven_snapshot "maven-snapshots" 100 "com.example${g}" "my-app${a}" "${v}.0-SNAPSHOT" &
    done
  done
done; wait
EOF

function f_upload_dummies_maven_snapshot() {
    local __doc__="Upload dummy jar files into maven snapshot hosted repository. Requires 'mvn' command"
    local _repo_name="${1:-"maven-snapshots"}"
    local _how_many="${2:-"5"}"     # 10 takes longer
    local _group="${3:-"com.example"}"
    local _name="${4:-"my-app"}"
    local _ver="${5:-"1.0-SNAPSHOT"}"
    local _usr="${6:-"${_ADMIN_USER}"}"
    local _pwd="${7:-"${_ADMIN_PWD}"}"

    if ! _is_repo_available "${_repo_name}"; then
        local _ds_name="$(_get_datastore_name)"
        local _bs_name="$(_get_blobstore_name)"
        local _extra_sto_opt="$(_get_extra_sto_opt "${_ds_name}")"
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"SNAPSHOT","layoutPolicy":"STRICT"},"storage":{"blobStoreName":"'${_bs_name}'","writePolicy":"ALLOW","strictContentTypeValidation":true'${_extra_sto_opt}'},"cleanup":{"policyName":[]}},"name":"'${_repo_name}'","format":"","type":"","url":"","online":true,"recipe":"maven2-hosted"}],"type":"rpc"}' || return $?
    fi

    # _SEQ_START is for continuing
    f_upload_dummies_with_mvn "${_repo_name}" "${_how_many}" "${_group}" "${_name}" "${_ver}" "${_SEQ_START}" || return $?
}

function f_upload_dummies_with_mvn {
    local _repo_name="${1:-"maven-releases"}"
    local _how_many="${2:-"5"}"     # 10 takes longer
    local _group="${3:-"com.example"}"
    local _name="${4:-"my-app"}"
    local _ver="${5}"
    local _seq_start="${6:-1}"
    local _seq_end="$((${_seq_start} + ${_how_many} - 1))"
    local _seq="seq ${_seq_start} ${_seq_end}"
    [[ "${_how_many}" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]] && _seq="seq ${_how_many}"
    local _repo_url="${_NEXUS_URL%/}/repository/${_repo_name%/}/"

    _gen_dummy_jar "${_TMP%/}/dummy.jar" || return $?
    for _s in $(eval "${_seq}"); do
        f_deploy_maven "${_repo_name}" "${_TMP%/}/dummy.jar" "${_group}:${_name}:${_ver:-"${_s}"}" "-Dpackaging=jar -DcreateChecksum=true -DgeneratePom=true" || break
    done
}

function f_download_dummies_npm() {
    local __doc__="Download *random* tgz via npm proxy repository"
    local _repo_name="${1:-"npm-proxy"}"
    local _how_many="${2:-"10"}"
    local _parallel="${3:-"3"}"
    local _dummy_pkg_name="${4}"
    local _usr="${5:-"${_ADMIN_USER}"}"
    local _pwd="${6:-"${_ADMIN_PWD}"}"

    local _repo_url="${_NEXUS_URL%/}/repository/${_repo_name}/"
    local _seq_start="${_SEQ_START:-1}"
    local _seq_end="$((${_seq_start} + ${_how_many} - 1))"
    local _seq="seq ${_seq_start} ${_seq_end}"
    if [ -z "${_dummy_pkg_name}" ]; then
        _dummy_pkg_name="*$(echo $((RANDOM % 26 + 65)) | tr -d '\n' | awk '{printf "%c", $0}' | tr '[:upper:]' '[:lower:]')*"
    fi
    _log "INFO" "Searching ${_repo_url%/} for ${_dummy_pkg_name} (${_how_many})..."
    curl -sSf -u "${_usr}:${_pwd}" -o "${_TMP%/}/${_repo_name}_search_$$.json" -L "${_repo_url%/}/-/v1/search?text=${_dummy_pkg_name}&size=${_how_many}" || return $?
    cat ${_TMP%/}/${_repo_name}_search_$$.json | JSON_SEARCH_KEY="objects.package" _sortjson | IS_NDJSON="Y" OUTPUT_DELIMITER=" " JSON_SEARCH_KEY="name,version" _sortjson | while IFS=" " read -r _name _ver; do
        if [ -z "${_name}" ] || [ -z "${_ver}" ]; then
            _log "ERROR" "Invalid name or version: ${_name}, ${_ver}"
            continue
        fi
        local _filename="${_name}"
        if [[ "${_name}" =~ ^([^/]+)/([^/]+)$ ]]; then
            #_scope="${BASH_REMATCH[1]}"
            _filename="${BASH_REMATCH[2]}"
        fi
        echo "${_repo_url%/}/${_name}/-/${_filename}-${_ver}.tgz"
    done | xargs -I{} -P${_parallel} curl -sf -u "${_usr}:${_pwd}" -w '%{http_code} {} (%{time_total}s)\n' -L -k "{}" -o/dev/null
}

# 100 packages with 100 versions each with 5 concurrency (please check the Deployment policy)
# for p in {1..5}; do sleep 1; for i in {1..20}; do f_upload_dummies_npm "npm-hosted" 100 "@test/dummy-pkg-${p}-${i}" || break; done & done; wait
function f_upload_dummies_npm() {
    local __doc__="Upload dummy tgz into npm hosted repository"
    local _repo_name="${1:-"npm-hosted"}"
    local _how_many="${2:-"10"}"
    local _dummy_pkg_name="${3:-"dummy-policy-demo"}"
    local _repo_url="${_NEXUS_URL%/}/repository/${_repo_name}/"
    local _seq_start="${_SEQ_START:-1}"
    local _seq_end="$((${_seq_start} + ${_how_many} - 1))"
    local _seq="seq ${_seq_start} ${_seq_end}"
    if [ ! -s "${_TMP%/}/policy-demo-2.0.0.tgz" ]; then
        curl -sSf -o "${_TMP%/}/policy-demo-2.0.0.tgz" -L "https://registry.npmjs.org/@sonatype/policy-demo/-/policy-demo-2.0.0.tgz" || return $?
    fi
    # TODO: upload concurrently with some limit (not only using _ASYNC_CURL="Y")
    for i in $(eval "${_seq}"); do
        f_upload_dummy_npm "${_repo_name}" "${_dummy_pkg_name}" "9.${i}.0" || return $?
    done
}
#for i in {1..100}; do f_upload_dummy_npm "" "@test/dummy-policy-demo-$i" "0.0.0"; done
#npm search -ddd --registry ${_NEXUS_URL%/}/repository/npm-hosted/ @test --searchlimit 100
function f_upload_dummy_npm() {
    local __doc__="Upload one file into a npm hosted repository to upload with the specific version string"
    local _repo_name="${1:-"npm-hosted"}"
    local _dummy_pkg_name="${2:-"dummy-policy-demo"}"
    local _ver="${3:-"9.9.9"}"
    # Using policy-demo-2.0.0.tgz as a dummy (template)
    if [ ! -s "${_TMP%/}/policy-demo-2.0.0.tgz" ]; then
        if [ ! -s "${_TMP%/}/policy-demo-2.0.0.tgz_$$" ]; then
            curl -sSf -o "${_TMP%/}/policy-demo-2.0.0.tgz_$$" -L "https://registry.npmjs.org/@sonatype/policy-demo/-/policy-demo-2.0.0.tgz" || return $?
        fi
        if [ -s "${_TMP%/}/policy-demo-2.0.0.tgz_$$" ] && [ ! -s "${_TMP%/}/policy-demo-2.0.0.tgz" ]; then
            mv -v "${_TMP%/}/policy-demo-2.0.0.tgz_$$" "${_TMP%/}/policy-demo-2.0.0.tgz" || return $?
        fi
    fi
    local _uploading_file="$(_update_npm_tgz "${_TMP%/}/policy-demo-2.0.0.tgz" "${_dummy_pkg_name}" "${_ver}")" || return $?
    if [ -z "${_uploading_file}" ]; then
        _log "ERROR" "Failed to generate a new upload tgz file with ${_TMP%/}/policy-demo-2.0.0.tgz, ${_dummy_pkg_name}, ${_ver}"
        return 1
    fi
    f_upload_asset "${_repo_name}" -F "npm.asset=@${_uploading_file}" || return $?
    rm -v -f ${_TMP%/}/${_dummy_pkg_name}-${_ver}.tgz
}
#curl -sSf -o "${_TMP%/}/policy-demo-2.0.0.tgz" -L "https://registry.npmjs.org/@sonatype/policy-demo/-/policy-demo-2.0.0.tgz"
#_update_npm_tgz "${_TMP%/}/policy-demo-2.0.0.tgz" "@ros/mof-ui-library" "9.9.9" "Y"
function _update_npm_tgz() {
    local _tgz="$1"
    local _new_name="$2"
    local _new_ver="$3"
    local _no_tgz="$4"
    local _tmpbase="${5:-"${_TMP%/}"}"

    if [[ "${_tgz}" =~ ([^/]+)-([0-9.]+).tgz ]]; then
        local _tzg_name="${BASH_REMATCH[1]}"
        local _tzg_ver="${BASH_REMATCH[2]}"
    else
        _log "ERROR" "Invalid tgz file name: ${_tgz}"
        return 1
    fi
    local _tmpdir="${_tmpbase%/}/${FUNCNAME[0]}_$$"
    if [ -s "${_tmpdir%/}/package/package.json" ]; then
        _log "INFO" "${_tmpdir%/}/package/package.json already exists"
    else
        mkdir -p ${_tmpdir%/} || return $?
        tar -xf ${_tgz} -C ${_tmpdir%/} || return $?
    fi
    if [ -n "${_new_name}" ]; then
        if ! sed -i.tmp -E 's;"name": ".+";"name": "'${_new_name}'";' ${_tmpdir%/}/package/package.json; then
            _log "ERROR" "Failed to update name in ${_tmpdir%/}/package/package.json"
            return 1
        fi
        _tzg_name="${_new_name}"
        if [[ "${_new_name}" =~ ([^/]+)/([^/]+) ]]; then
            _tzg_name="${BASH_REMATCH[2]}"
        fi
    fi
    if [ -n "${_new_ver}" ]; then
        if ! sed -i.tmp -E 's/"version": ".+"/"version": "'${_new_ver}'"/' ${_tmpdir%/}/package/package.json; then
            _log "ERROR" "Failed to update version in ${_tmpdir%/}/package/package.json"
            return 1
        fi
        _tzg_ver="${_new_ver}"
    fi
    rm -f ${_tmpdir%/}/package/package.json.tmp
    if [[ "${_no_tgz}" =~ [yY] ]]; then
        _log "INFO" "Updated ${_tmpdir%/}/package/package.json only"
    else
        if ! tar -czf ${_tmpbase}/${_tzg_name}-${_tzg_ver}.tgz -C ${_tmpdir%/} package; then
            _log "ERROR" "Failed to create ${_tmpbase}/${_tzg_name}-${_tzg_ver}.tgz"
            return 1
        fi
        echo "${_tmpbase}/${_tzg_name}-${_tzg_ver}.tgz"
    fi
    rm -rf ${_tmpdir%/}
}

function f_upload_dummy_pypi() {
    local __doc__="Upload dummy .whl into PyPI hosted repository"
    local _repo_name="${1:-"pypi-hosted"}"
    local _new_name="${2:-"mydummyproject"}"  # Default project name if not specified
    local _new_ver="${3:-"0.0.1"}"  # Default version if not specified
    local _tmpbase="${4:-"${_TMP%/}"}"

    if [ ! -s "${_TMP%/}/pypi-sampleproject.tgz" ]; then
        if [ ! -s "${_TMP%/}/pypi-sampleproject.tgz_$$" ]; then
            curl -sSf -o "${_TMP%/}/pypi-sampleproject.tgz_$$" -L "https://github.com/hajimeo/samples/raw/refs/heads/master/misc/pypi-sampleproject.tgz" || return $?
        fi
        if [ -s "${_TMP%/}/pypi-sampleproject.tgz_$$" ] && [ ! -s "${_TMP%/}/pypi-sampleproject.tgz" ]; then
            mv -v "${_TMP%/}/pypi-sampleproject.tgz_$$" "${_TMP%/}/pypi-sampleproject.tgz" || return $?
        fi
    fi
    if [ ! -s "${_TMP%/}/pypi-sampleproject.tgz" ]; then
        _log "ERROR" "pypi-sampleproject.tgz not found in ${_TMP%/}"
        return 1
    fi
    local _tmpdir="${_tmpbase%/}/${FUNCNAME[0]}_$$"
    mkdir -p ${_tmpdir%/} || return $?
    tar -xf "${_TMP%/}/pypi-sampleproject.tgz" -C "${_tmpdir%/}" || return $?
    local _uploading_file="$(_build_pypi_project "${_tmpdir%/}/sampleproject" "${_new_name}" "${_new_ver}")" || return $?
    if [ -z "${_uploading_file}" ]; then
        _log "ERROR" "Failed to update the pypi project with ${_tmpdir}, ${_new_name}, ${_new_ver}"
        return 1
    fi
    f_upload_asset "${_repo_name}" -F "pypi.asset=@${_uploading_file}" || return $?
    rm -rf ${_tmpdir%/}
}

function _build_pypi_project() {
    local __doc__="Update and build PyPI project with a new name and version. Requires setuptools, wheel, and build"
    local _project_dir="${1:-"."}"  # Directory where the project is extracted
    local _new_name="${2:-"mydummyproject"}"  # Default project name if not specified
    local _new_ver="${3:-"0.0.1"}"  # Default version if not specified
    local _build_home="${4:-"${_project_dir}"}"
    if [ -z "${_new_name}" ] || [ -z "${_new_ver}" ]; then
        _log "ERROR" "Please specify project name and new version"
        return 1
    fi
    cd "${_project_dir}" || return $?
    if [ ! -s "./pyproject.toml" ]; then
        _log "ERROR" "pyproject.toml not found in ${_project_dir}"
        return 1
    fi
    sed -i '' -E 's/^name = ".+$/name = "'${_new_name}'"/' ./pyproject.toml
    sed -i '' -E 's/^version = ".+$/version = "'${_new_ver}'"/' ./pyproject.toml
    if ! grep -q "name = \"${_new_name}\"" ./pyproject.toml || ! grep -q "version = \"${_new_ver}\"" ./pyproject.toml; then
        _log "ERROR" "Failed to update pyproject.toml"
        return 1
    fi
    #HOME="." python -m pip install --upgrade setuptools wheel build
    if ! HOME="${_build_home:-"${HOME}"}" python -m build &> ${_TMP%/}/pybuild_last.out; then
        _log "ERROR" "Building ${_project_dir} failed. Check ${_TMP%/}/pybuild_last.out for details."
        return 1
    fi
    local _whl_file="$(find ./dist -type f -name "${_new_name}-${_new_ver}-*.whl" -mmin -1 | head -n 1)"
    if [ -z "${_whl_file}" ]; then
        _log "ERROR" "No wheel file found in ./dist after build"
        return 1
    fi
    _whl_file="$(readlink -f "${_whl_file}")"
    echo "${_whl_file}"
    cd - >/dev/null || return $?
}

# Example command to create with 4 concurrency and 500 each (=2000)
#for _i in {0..3}; do _SEQ_START=$((500 * ${_i} + 1)) f_upload_dummies_nuget "nuget-hosted" 500 & done
function f_upload_dummies_nuget() {
    local __doc__="Upload dummy .nupkg into Nuget hosted repository"
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
    #local _nuspec="$(find -L ${_TMP%/}/${_pkg_name} -type f -name '*.nuspec' -print | head -n1)"
    #local _psmdcp="$(find -L ${_TMP%/}/${_pkg_name} -type f -name '*.psmdcp' -print | head -n1)"
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
        # NOTE: Can't execute this curl in parallel (unlike other f_upload_dummies_xxxx) because of using same file name.
        #       Use different _SEQ_START to make upload faster
        curl -sSf -u "${_usr}:${_pwd}" -o/dev/null -w "%{http_code} ${_pkg_name}.${_base_ver}.$i.nupkg (%{time_total}s)\n" -X PUT "${_repo_url%/}/" -F "package=@${_tmpdir%/}/${_pkg_name}.${_base_ver}.${_seq_start}.nupkg" || return $?
        #f_upload_asset "${_repo_name}" -F "nuget.asset=@${_TMP%/}/${_pkg_name}.${_base_ver}.$i.nupkg" || return $?
    done
}

#f_upload_dummies_rubygem "" "100" "nexus"
#f_upload_dummies_rubygem "" "1" "loudmonth.+0.2.0"
#f_upload_dummies_rubygem "rubygem-misc-hosted" "20" "(acts_as_tree|haml|rdoc)"
#_SEQ_START=11 f_upload_dummies_rubygem "" "5" "Checked"
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
    _log "INFO" "Using ${_tmpdir} ..."

    if [ ! -s /tmp/rubygem_specs.4.8.gz ] || [ ! -s /tmp/rubygem_specs.4.8.txt ]; then
        curl -o /tmp/rubygem_specs.4.8.gz -f -L "https://rubygems.org/specs.4.8.gz" || return $?
        _log "INFO" "Grep-ing specs.4.8.gz to generate /tmp/rubygem_specs.4.8.txt ..."
        ruby -rpp -e 'pp Marshal.load(Gem::Util.gunzip(File.read("/tmp/rubygem_specs.4.8.gz")))' > ${_tmpdir%/}/specs.4.8.tmp || return $?
        grep -oE '"[^"][^"][^"]+", ?Gem::Version.new[^,]+' ${_tmpdir%/}/specs.4.8.tmp > /tmp/rubygem_specs.4.8.txt
        #cat /tmp/rubygem_specs.4.8.txt | cut -d ',' -f1 | sort | uniq -c | grep -vE '^\s*[0-9]\s' | sort | head
    fi

    if [ -n "${_pkg_name}" ]; then
        grep -E "\"${_pkg_name}\"" /tmp/rubygem_specs.4.8.txt
    else
        cat /tmp/rubygem_specs.4.8.txt
    fi | sort -R | sed -n "${_seq_start},${_seq_end}p" | while read -r _pkg_ver; do
        [[ "${_pkg_ver}" =~ .*\"([^\"]+)\",[^\"]*\"([^\"]+)\" ]] || continue
        local _pkg="${BASH_REMATCH[1]}"
        local _ver="${BASH_REMATCH[2]}"
        local _url="https://rubygems.org/gems/${_pkg}-${_ver}.gem"
        curl -sSf -w "Download: %{http_code} ${_url} (%{time_total}s)\n" "${_url}" -o ${_tmpdir%/}/${_pkg}-${_ver}.gem || continue
        f_upload_asset "${_repo_name}" -F rubygem.asset=@${_tmpdir%/}/${_pkg}-${_ver}.gem || return $?
        #curl -sSf -w "Download: %{http_code} specs.4.8.gz (%{time_total}s | %{size_download}b)\n" -o/dev/null "${_repo_url%/}/specs.4.8.gz"
    done
}

function f_upload_dummies_docker() {
    local __doc__="Upload dummy docker images into docker hosted repository (requires 'docker' command)"
    local _host_port="${1}"
    local _how_many="${2:-"10"}"    # this number * _parallel is the actual number of images
    local _parallel="${3:-"1"}"
    local _base_img="${4:-"${_BASE_IMG:-"alpine:latest"}"}"    # "redhat/ubi9:9.4-1181"
    local _usr="${5:-"${_ADMIN_USER}"}"
    local _pwd="${6:-"${_ADMIN_PWD}"}"
    local _cmd="$(_docker_cmd)"
    local _seq_start="${_SEQ_START:-1}"
    local _seq_end="$((${_seq_start} + ${_how_many} - 1))"
    local _seq="seq ${_seq_start} ${_seq_end}"
    # docker login first
    _docker_login "${_host_port}" "" "${_usr}" "${_pwd}" "${_cmd}" || return $?
    for i in $(eval "${_seq}"); do
        for j in $(eval "seq 1 ${_parallel}"); do
            local _img="dummy${i}-${j}:tag$(date +'%H%M%S')"
            (_DOCKER_NO_LOGIN="Y" _populate_docker_hosted "${_base_img}" "${_host_port}" "${_img}" &>/dev/null &&  echo "[$(date +'%H:%M:%S')] Pushed dummy image '${_img}' to ${_host_port}") &
        done
        wait
    done 2>/tmp/f_upload_dummies_docker_$$.err
    _log "INFO" "Completed. May want to run 'f_delete_dummy_docker_images \"${_host_port}\"' to remove dummy images."
}

function f_delete_dummy_docker_images() {
    local _host_port="${1}"
    local _cmd="$(_docker_cmd)"
    ${_cmd} images --format "{{.Repository}}:{{.Tag}}" | grep -E "^${_host_port%/}/dummy[0-9]+" | while read -r _img; do
        ${_cmd} rmi -f "${_img}"
    done
    ${_cmd} images --format "{{.Repository}}:{{.Tag}}" | grep -E "^dummy[0-9]+" | while read -r _img; do
        ${_cmd} rmi -f "${_img}"
    done
    echo "May need to run 'docker system prune -f' to remove dangling images"
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
        grep -E "\b${_pkg_name}\b" /tmp/helm_urls.out
    else
        cat /tmp/helm_urls.out
    fi | sed -n "${_seq_start},${_seq_end}p" | sort -R | while read -r _url; do
        _name="$(basename "${_url}")"
        if [ -n "${_pkg_name}" ] && ! echo "${_name}" | grep -qE "\b${_pkg_name}\b"; then
            continue
        fi
        # Helm doesn't care about the file name
        curl -sSf -w "Download: %{http_code} ${_name} (%{time_total}s)\n" "${_url}" -o ${_tmpdir%/}/helm-cart_tmp.tgz || continue
        curl -sSf -w "Upload  : %{http_code} ${_name} (%{time_total}s)\n" -T ${_tmpdir%/}/helm-cart_tmp.tgz -u "${_usr}:${_pwd}" "${_repo_url%/}/${_name}" || return $?
        #curl -sSf -w "Download: %{http_code} index.yaml (%{time_total}s | %{size_download}b)\n" -o/dev/null "${_repo_url%/}/index.yaml"
    done
}

function f_upload_dummies_helm_push() {
    local __doc__="To test OCI with docker repository"
    local _host_port="${1:-"${_NEXUS_DOCKER_HOSTNAME}:18182"}"
    local _how_many="${2:-"10"}"
    local _pkg_name="${3:-"demo"}"
    local _usr="${4:-"${_ADMIN_USER}"}"
    local _pwd="${5:-"${_ADMIN_PWD}"}"

    local _seq_start="${_SEQ_START:-1}"
    local _seq_end="$((${_seq_start} + ${_how_many} - 1))"
    local _seq="seq ${_seq_start} ${_seq_end}"
    local _tmpdir="$(mktemp -d)"

    if [ ! -s "${_TMP%/}/demo-0.1.0.tgz" ]; then
        curl -sf -o ${_TMP%/}/demo-0.1.0.tgz -L "https://github.com/hajimeo/samples/raw/refs/heads/master/misc/helm-oci-demo-0.1.0.tgz" || return $?
    fi

    if ! helm registry login ${_host_port} -u "${_usr}" -p "${_pwd}"; then
        _log "WARN" "helm registry login ${_host_port} failed."
        return 1
    fi
    cd ${_tmpdir%/} || return $?
    # Due to 'Cannot append to compressed archive.', can't extract only Chart.yaml
    tar -xf ${_TMP%/}/demo-0.1.0.tgz || return $?
    if [ "${_pkg_name}" != "demo" ]; then
        mv -v "demo" "${_pkg_name}" || return $?
    fi
    sed -i '' -E 's/^name: .+/name: '${_pkg_name}'/' ${_pkg_name}/Chart.yaml || return $?

    for i in $(eval "${_seq}"); do
        if [ -f "${_TMP%/}/${_pkg_name}-0.0.0.tgz" ]; then
            rm -f ${_TMP%/}/${_pkg_name}-0.0.0.tgz || return $?
        fi
        # Due to some bug in helm, need to change the version in Chart.yaml
        sed -i '' -E 's/^version: .+/version: 0.'${i}'.0/' ${_pkg_name}/Chart.yaml || return $?
        # File name is not important
        tar -czf ${_TMP%/}/${_pkg_name}-0.0.0.tgz ${_pkg_name} || return $?
        helm push "${_TMP%/}/${_pkg_name}-0.0.0.tgz" "oci://${_host_port}/${_pkg_name}" || return $?    # --debug
        _log "INFO" "Pushed ${_pkg_name}-0.${i}.0.tgz into ${_host_port}"
    done
    cd - >/dev/null
}

function f_upload_dummy_yum_build() {
    local __doc__="Upload one rpm after building"
    local _repo_name="${1:-"yum-hosted"}"
    local _pkg_name="${2:-"test-rpm"}"
    local _ver="${3:-"0.0.0"}"
    local _release="${4:-"1"}"
    local _yum_upload_path="${_YUM_UPLOAD_PATH:-"Packages"}"
    local _upload_file="$(_rpm_build "${_pkg_name}" "${_ver}" "${_release}" 2>/dev/null)"
    [ -s "${_upload_file}" ] || return 102
    f_upload_asset "${_repo_name}" -F yum.asset=@${_upload_file} -F yum.asset.filename=${_pkg_name}-${_ver}-${_release}.noarch.rpm -F yum.directory=${_yum_upload_path%/}/Packages
}

# This can be used for populating not only local hosted and a yum-proxy with 'vault' and _YUM_REMOTE_URL
function f_upload_dummies_yum() {
    local __doc__="Upload rpms from vault.centos.org or 'rpmbuild' command or using same rpm but different path"
    local _repo_name="${1:-"yum-hosted"}"
    local _how_many="${2:-"10"}"
    local _pkg_name="${3}"      # used with grep -E "\b${_pkg_name}\b"
    local _upload_method="${4-"${_YUM_DUMMY_UPLOAD_METHOD:-"path"}"}"  # "vault" or "build" or "path"

    local _seq_start="${_SEQ_START:-1}"
    local _seq_end="$((${_seq_start} + ${_how_many} - 1))"
    local _seq="seq ${_seq_start} ${_seq_end}"

    local _repo_url="${_NEXUS_URL%/}/repository/${_repo_name}/"
    local _yum_remote_url="${_YUM_REMOTE_URL:-"https://vault.centos.org/7.9.2009/os/x86_64/Packages/"}"
    local _yum_upload_path="${_YUM_UPLOAD_PATH:-"Packages"}"

    if [[ "${_upload_method}" =~ ^[vV] ]]; then
        # not using _tmpdir for index, as don't want to download always
        if [ ! -s /tmp/yum_index.yaml ] || [ ! -s /tmp/yum_urls.out ]; then
            curl -o /tmp/yum_index.yaml -f -L "${_yum_remote_url%/}/" || return $?
            sed -n -r 's@^.+href="([^"]+\.rpm)".+$@'${_yum_remote_url%/}/'\1@pg' /tmp/yum_index.yaml > /tmp/yum_urls.out
        fi
        if [ ! -s /tmp/yum_urls.out ]; then
            return 101
        fi

        local _tmpdir="$(mktemp -d)"
        if [ -n "${_pkg_name}" ]; then
            grep -E "\b${_pkg_name}\b" /tmp/yum_urls.out
        else
            cat /tmp/yum_urls.out
        fi | sed -n "${_seq_start},${_seq_end}p" | sort -R | while read -r _url; do
            _name="$(basename "${_url}")"
            if [ -n "${_pkg_name}" ] && ! echo "${_name}" | grep -qE "\b${_pkg_name}\b"; then
                continue
            fi
            curl -sSf -w "Download: %{http_code} ${_name} (%{time_total} secs, %{size_download} bytes)\n" "${_url}" -o ${_tmpdir%/}/${_name} || continue
            curl -sSf -w "Upload  : %{http_code} ${_name} (%{time_total} secs, %{size_download} bytes)\n" -T ${_tmpdir%/}/${_name} -u "${_ADMIN_USER}:${_ADMIN_PWD}" "${_repo_url%/}/${_yum_upload_path%/}/Packages/${_name}" || return $?
            rm -f ${_tmpdir%/}/${_name}
            #sleep 60
            #curl -sSf -w "Download: %{http_code} ${_YUM_GROUP_REPO} repomd.xml (%{time_total} secs, %{size_download} bytes)\n" -o/dev/null "${_NEXUS_URL%/}/repository/${_YUM_GROUP_REPO}/${_yum_upload_path%/}/repodata/repomd.xml"
        done
    elif [[ "${_upload_method}" =~ ^[bB] ]]; then
        for i in $(eval "${_seq}"); do
            f_upload_dummy_yum_build "${_repo_name}" "${_pkg_name:-"test-rpm"}" "0.0.0" "${i}" || return $?
        done
    elif [[ "${_upload_method}" =~ ^[pP] ]]; then
        # Fastest but using a bug in Nexus3. Also can't change the name or version.
        local _upload_file=${_TMP%/}/test-rpm-9.9.9-1.noarch.rpm
        if [ ! -s "${_upload_file}" ] && ! curl -sSf -L -o ${_upload_file}"https://github.com/hajimeo/samples/raw/master/misc/test-rpm-9.9.9-1.noarch.rpm"; then
            return 103
        fi
        for i in $(eval "${_seq}"); do
            f_upload_asset "${_repo_name}" -F yum.asset=@${_upload_file} -F yum.asset.filename=test-rpm-9.9.9-1.noarch.rpm -F yum.directory=dummy/os/path${i}/Packages || return $?
        done
    else
        return 111
    fi
}

function f_upload_dummies_all_hosted() {
    # TODO: When a new f_upload_dummies_* is added, need to add here
    local __doc__="Get repositories with /v1/repositorySettings, and call f_upload_dummies_* for each"
    f_api /service/rest/v1/repositorySettings | JSON_SEARCH_KEY="name,format,type" OUTPUT_DELIMITER=" " sortjson | grep -E ' hosted$' | while read -r _repo _format _type; do
        if type "f_upload_dummies_${_format}" &>/dev/null; then
            _log "INFO" "Uploading dummy data to ${_repo} (${_format})"
            eval "f_upload_dummies_${_format} \"${_repo}\""
        else
            _log "WARN" "Not supported: ${_repo} (${_format})"
        fi
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
    rm -f ${_TMP%/}/${FUNCNAME[0]}_*.out || return $?
    local _path="/service/rest/v1/assets"
    local _query=""
    local _base_query="?"
    [ -z "${_path_regex}" ] && return 11
    [ -z "${_repo}" ] && return 12  # repository is mandatory
    [ -n "${_repo}" ] && _base_query="?repository=${_repo}"
    for i in $(seq "1" "${_max_loop}"); do
        _API_SORT_KEYS=Y f_api "${_path}${_base_query}${_query}" > ${_TMP%/}/${FUNCNAME[0]}_${i}.json || return $?
        grep -E '"(id|path)"' ${_TMP%/}/${FUNCNAME[0]}_${i}.json | grep -E "\"${_path_regex}\"" -B1 > ${_TMP%/}/${FUNCNAME[0]}_${i}_matched_IDs.out
        if [ $? -eq 0 ] && [[ ! "${_search_all}" =~ ^[yY] ]]; then
            break
        fi
        grep -qE '"continuationToken": *"[0-9a-f]+' ${_TMP%/}/${FUNCNAME[0]}_${i}.json || break
        local cToken="$(cat ${_TMP%/}/${FUNCNAME[0]}_${i}.json | JSON_SEARCH_KEY="continuationToken" _sortjson)"
        _query="&continuationToken=${cToken}"
    done
    grep -E '^            "id":' -h ${_TMP%/}/${FUNCNAME[0]}_*_matched_IDs.out | sort | uniq > ${_TMP%/}/${FUNCNAME[0]}_$$.out || return $?
    local _line_num="$(cat ${_TMP%/}/${FUNCNAME[0]}_$$.out | wc -l | tr -d '[:space:]')"
    if [[ ! "${_force}" =~ ^[yY] ]]; then
        read -p "Are you sure to delete matched (${_line_num}) assets?: " "_yes"
        echo ""
        [[ "${_yes}" =~ ^[yY] ]] || return
    fi
    cat ${_TMP%/}/${FUNCNAME[0]}_$$.out | while read -r _l; do
        if [[ "${_l}" =~ \"id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            echo "# ${BASH_REMATCH[1]}"
            f_api "/service/rest/v1/assets/${BASH_REMATCH[1]}" "" "DELETE" || break
        fi
    done
    echo "Deleted ${_line_num} assets"
}
function f_get_all_assets() {
    local __doc__="Get all assets but only one attribute from one repository with Search REST API (require correct search index)"
    local _repo="$1"
    local _attr="${2:-"id"}"    # or "downloadUrl"
    local _max_loop="${3:-200}" # 50 * 200 = 10000 max
    rm -f ${_TMP%/}/${FUNCNAME[0]}_*.out || return $?
    local _path="/service/rest/v1/search/assets"
    local _query=""
    local _base_query=""
    [ -n "${_repo}" ] && _base_query="?repository=${_repo}"
    cat /dev/null > ${_TMP%/}/${FUNCNAME[0]}_attr_$$.out
    for i in $(seq "1" "${_max_loop}"); do
        f_api "${_path}${_base_query}${_query}" > ${_TMP%/}/${FUNCNAME[0]}_$$.json || return $?
        # TODO: should output only '"_attr":"_value_"'
        grep -E '^            "'${_attr}'":' -h ${_TMP%/}/${FUNCNAME[0]}_$$.json | sort | uniq >> ${_TMP%/}/${FUNCNAME[0]}_attr_$$.out || return $?
        grep -qE '"continuationToken": *"[0-9a-f]+' ${_TMP%/}/${FUNCNAME[0]}_$$.json || break
        local _line_num="$(cat "${_TMP%/}/${FUNCNAME[0]}_attr_$$.out" | wc -l | tr -d '[:space:]')"
        _log "INFO" "Found ${_line_num} assets so far (${i})"
        local cToken="$(cat ${_TMP%/}/${FUNCNAME[0]}_$$.json | JSON_SEARCH_KEY="continuationToken" _sortjson)"
        if [ -z "${_base_query}" ]; then
            _query="?continuationToken=${cToken}"
        else
            _query="&continuationToken=${cToken}"
        fi
    done
    # NOTE: as this function is used for f_check_all_assets, should output only file name
    echo "${_TMP%/}/${FUNCNAME[0]}_attr_$$.out"
}
function f_check_all_assets() {
    local __doc__="Check/test if all assets can be downloaded (should update the downloaded time)"
    local _repo="$1"
    local _parallel="${2:-"3"}"
    local _usr="${3:-"${_ADMIN_USER}"}"
    local _pwd="${4:-"${_ADMIN_PWD}"}"

    local _all_asset_file="$(f_get_all_assets "${_repo}" "downloadUrl")" || return $?
    local _line_num="$(cat "${_all_asset_file}" | wc -l | tr -d '[:space:]')"
    # TODO: should use sed
    cat "${_all_asset_file}" | while read -r _l; do
        if [[ "${_l}" =~ \"downloadUrl\"[[:space:]]*:[[:space:]]*\"(http.?://[^/]+)(.*)\" ]]; then
            echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
        fi
    done | xargs -I{} -P${_parallel} curl -sf -u "${_usr}:${_pwd}" -w '%{http_code} {} (%{time_total}s)\n' -L -k "{}" -o/dev/null
    _log "INFO" "Checked ${_line_num} assets"
}
function f_delete_all_assets() {
    local __doc__="Delete 'almost' all assets (not components) with Search REST API (require correct search index)"
    local _repo="$1"
    local _force="$2"
    local _max_loop="$3"    # One loop gets 50 assets. Default is 200, so 10K max
    local _parallel="${4:-"3"}"
    local _usr="${5:-"${_ADMIN_USER}"}"
    local _pwd="${6:-"${_ADMIN_PWD}"}"
    local _nexus_url="${7:-"${r_NEXUS_URL:-"${_NEXUS_URL}"}"}"

    local _all_asset_file="$(f_get_all_assets "${_repo}" "id" "${_max_loop}")" || return $?
    local _line_num="$(cat "${_all_asset_file}" | wc -l | tr -d '[:space:]')"
    if [[ ! "${_force}" =~ ^[yY] ]]; then
        read -p "Are you sure to delete all (${_line_num}) assets?: " "_yes"
        echo ""
        [[ "${_yes}" =~ ^[yY] ]] || return
    fi
    cat "${_all_asset_file}" | while read -r _l; do
        if [[ "${_l}" =~ \"id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            echo "/service/rest/v1/assets/${BASH_REMATCH[1]}"
        fi
    done | xargs -I{} -P${_parallel} curl -sf -u "${_usr}:${_pwd}" -w '%{http_code} {} (%{time_total}s)\n' -X DELETE -L -k "${_nexus_url%/}{}"
    # To make this function faster, not using f_api "/service/rest/v1/assets/${BASH_REMATCH[1]}" "" "DELETE" (but now can't stop at the first error...)
    _log "INFO" "Deleted ${_line_num} assets. 'After waiting for 'nexus.assetBlobCleanupTask.blobCreatedDelayMinute', Cleanup unused <format> blobs from <datastore> task' (f_run_tasks_by_type \"assetBlob.cleanup\") needs to be run."
}

# 1. Create a new raw-test-hosted repo from Web UI (or API)
#   f_setup_raw
#   f_api "/service/rest/v1/repositories/raw/hosted" '{"name":"raw-test-hosted","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":false,"writePolicy":"ALLOW"}}'
# 2. curl -D- -u "admin:admin123" -T<(echo "test for f_staging_move") -L -k "${_NEXUS_URL%/}/repository/raw-hosted/test/nxrm3Staging.txt"
# 3. f_associate_tag "repository=raw-hosted" "raw-test-tag"
#    f_staging_move "raw-test-hosted" "raw-test-tag"
#  Or without tag but search query:
#    f_staging_move "raw-test-hosted" "raw-test-tag" "repository=raw-hosted&name=*test/nxrm3Staging*.txt"
#    NOTE: Tag is optional. Using "*" in 'name=' as name|path in NewDB starts with "/"
# 4. f_staging_move "raw-hosted" "raw-test-tag" "repository=raw-test-hosted&name=*test/nxrm3Staging*.txt"
# With maven2:
#   f_upload_dummies_maven "maven-hosted" "" "" "com.example" "my-app-staging"
#   f_staging_move "maven-releases" "maven-test-tag" "repository=maven-hosted&name=my-app-staging"
#   f_upload_dummies_maven
#   f_staging_move "maven-hosted" "" "repository=maven-releases&group=setup.nexus3.repos&name=dummy&version=3"
# Just search components with the tag
#   f_api "/service/rest/v1/search?tag=raw-test-tag"
function f_staging_move() {
    local __doc__="To test staging move API with search and tag APIs"
    local _move_to_repo="${1}"
    local _tag="${2}"
    local _search="${3}"
    if [ -n "${_search}" ]; then
        if [ -z "${_tag}" ] && [ -z "${_move_to_repo}" ]; then
            # If only search is given, just search
            echo "# /service/rest/v1/search with ${_search}"
            f_api "/service/rest/v1/search?${_search}"
            echo ""
            return
        fi
        if [ -n "${_tag}" ] && [ -n "${_search}" ]; then
            # If tag is given, associate the search matching components to this tag
            # If it's already associated, Nexus does not return any error
            f_associate_tag "${_search}" "${_tag}" || return $?
        fi
    fi
    # Move!
    if [ -n "${_tag}" ]; then
        # TODO: no 'wait' for staging/move?
        echo "# /service/rest/v1/staging/move/${_move_to_repo}?tag=${_tag}"
        f_api "/service/rest/v1/staging/move/${_move_to_repo}?tag=${_tag}" "" "POST" || return $?
    elif [ -n "${_search}" ]; then
        echo "# /service/rest/v1/staging/move/${_move_to_repo}?${_search}"
        f_api "/service/rest/v1/staging/move/${_move_to_repo}?${_search}" "" "POST" || return $?
    fi
    echo ""
}

# To prepare data: f_upload_dummies_maven "maven-releases"
#   f_associate_tag "repository=maven-releases&maven.groupId=setup.nexus3.repos&maven.artifactId=dummy&maven.baseVersion=3"
#   f_staging_move "maven-hosted" "tag-test"
function f_associate_tag() {
    local __doc__="Associate one tag to the search result"
    local _search="${1}"
    local _tag="${2:-"tag-test"}"
    if [ -z "${_search}" ]; then
        _log "ERROR" "Search is mandatory"
        return 1
    fi
    # Ignoring if tag creation fails
    echo "# /service/rest/v1/tags -d '{\"name\":\"${_tag}\"}'"
    f_api "/service/rest/v1/tags" "{\"name\":\"${_tag}\"}"
    echo "# /service/rest/v1/tags/associate/${_tag}?${_search}" # 'wait' (default is true) for Elasticsearch to wait for calm down
    f_api "/service/rest/v1/tags/associate/${_tag}?${_search}" "" "POST" || return $?
    sleep 3 # Just in case waiting for elastic search
    echo "To confirm:"
    echo "    f_api \"/service/rest/v1/search?${_search}\" | grep '\"${_tag}\"' -c"
    echo "    f_api \"/service/rest/v1/search?tag=${_tag}\""
}
# TODO: add `/service/rest/v1/staging/delete`

function f_run_tasks_by_type() {
    local __doc__="Run/start multiple tasks by type (eg. 'assetBlob.cleanup')"
    local _task_type="$1"   #assetBlob.cleanup
    if [ -z "${_task_type}" ]; then
        f_api "/service/rest/v1/tasks"
        return $?
    fi
    f_api "/service/rest/v1/tasks?type=${_task_type}" > ${_TMP%/}/${FUNCNAME[0]}.json || return $?
    cat ${_TMP%/}/${FUNCNAME[0]}.json | JSON_SEARCH_KEY="items.id" _sortjson | while read -r _id; do
        _log "INFO" "/service/rest/v1/tasks/${_id}/run"
        f_api "/service/rest/v1/tasks/${_id}/run" "" "POST" || return $?
        cat ${_TMP%/}/_api_header_$$.out
    done
}

function f_test_download() {
    local __doc__="Test download with curl for checking performance"
    local _repo="${1:-"raw-hosted"}"
    local _work_dir="${2}"
    local _bs_name="${3}"
    local _usr="${4:-"${_ADMIN_USER}"}"
    local _pwd="${5:-"${_ADMIN_PWD}"}"
    [ -z "${_work_dir}" ] && _work_dir="$(_get_work_dir)"
    local _tmpdir="${_work_dir:-"."}/tmp"
    [ -z "${_bs_name}" ] && _bs_name="$(_get_blobstore_name)"
    if ! _is_repo_available "${_repo}"; then
        _log "INFO" "Crete a new repository ${_repo} ..."
        curl -sSf -u "${_usr}:${_pwd}" -k "${_NEXUS_URL%/}/service/rest/v1/repositories/raw/hosted" -H "Content-Type: application/json" -d '{"name":"'${_repo}'","online":true,"storage":{"blobStoreName":"'${_bs_name}'","strictContentTypeValidation":false,"writePolicy":"ALLOW"}}'
    fi
    _log "INFO" "Creating ${_tmpdir%/}/test_100MB.data, and check how fast this location is ..."
    #time dd if=/dev/zero of=${_tmpdir%/}/test_100MB.data bs=1 count=0 seek=$((1024*1024*100))
    time dd if=/dev/zero of=${_tmpdir%/}/test_100MB.data bs=1024 count=102400
    _log "INFO" "Uploading as ${_repo}/test/test_100MB.data, and check how fast ..."
    curl -sSf -w 'Status: %{http_code}, Elapsed: %{time_total}s\n' -u "${_usr}:${_pwd}" -k "${_NEXUS_URL%/}/repository/${_repo}/test/test_100MB.data" -T ${_tmpdir%/}/test_100MB.data
    _log "INFO" "Downloading ${_repo}/test/test_100MB.data, and check how fast ..."
    curl -sSf -w 'Status: %{http_code}, Elapsed: %{time_total}s\n' -u "${_usr}:${_pwd}" -k "${_NEXUS_URL%/}/repository/${_repo}/test/test_100MB.data" -o/dev/null
}

function f_register_script() {
    local __doc__="Register a groovy script"
    local _script_file="$1"
    local _script_name="$2"
    [ -s "${_script_file%/}" ] || return 1
    [ -z "${_script_name}" ] && _script_name="$(basename ${_script_file} .groovy)"
    local _script_text="$(cat ${_script_file} | JSON_ESCAPE=Y _sortjson)"
    #python -c "import sys,json;print(json.dumps(open('${_script_file}').read()))" > ${_TMP%/}/${_script_name}_$$.out || return $?
    echo "{\"name\":\"${_script_name}\",\"content\":${_script_text},\"type\":\"groovy\"}" > ${_TMP%/}/${_script_name}_$$.json
    _log "INFO" "Delete ${_script_name} if exists (may return error if not exist)"
    f_api "/service/rest/v1/script/${_script_name}" "" "DELETE"
    f_api "/service/rest/v1/script" "$(cat ${_TMP%/}/${_script_name}_$$.json)" || return $?
    echo "To run:
    curl -u admin -X POST -H 'Content-Type: application/json' '${_NEXUS_URL%/}/service/rest/v1/script/${_script_name}/run' -d'{arg:value}'"
}

#_installDir="/opt/sonatype/nexus"
#java -jar ${_installDir%/}/system/org/codehaus/groovy/groovy/3.0.19/groovy-3.0.19.jar -e 'println java.security.SecureRandom.getInstance("SHA1PRNG").algorithm'
function f_run_groovy_deprecated() {
    local __doc__="DEPRECATED Run groovy command (not via Nexus). No longer works with 3.78 and higher."
    local _script="${1}"
    local _installDir="${2}"
    local _groovy_jar="${_installDir%/}/system/org/codehaus/groovy/groovy-all/2.4.17/groovy-all-2.4.17.jar"
    if [ ! -s "${_groovy_jar}" ]; then
        _groovy_jar="$(find "${_installDir%/}/system/org/codehaus/groovy/groovy" -type f -name 'groovy-3.*.jar' 2>/dev/null | head -n1)"
    fi
    local _java="java"
    if [ -n "${JAVA_HOME}" ]; then
        _java="${JAVA_HOME%/}/bin/java"
    fi
    local _groovy_classpath="$(find ${_installDir%/}/system -type f -name '*.jar' | tr '\n' ':')"
    ${_java:-"java"} -classpath ${_groovy_jar} org.codehaus.groovy.tools.GroovyStarter --main groovy.ui.GroovyMain --classpath "${_groovy_classpath%:}:." -e "${_script}" || return $?
}



### K8s related but not in use yet | any more
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



### Database related
function _export_postgres_config() {
    local _db_props_file="${1}"
    [ ! -s "${_db_props_file}" ] && return 1
    # TODO: if no nexus-store.properties, check "cat /proc/${_pid}/environ | tr '\0' '\n'"
    #local _pid="$(ps auxwww | grep -F 'org.sonatype.nexus.karaf.NexusMain' | grep -vw grep | awk '{print $2}' | tail -n1)"
    source "${_db_props_file}" || return $?
    [[ "${jdbcUrl}" =~ jdbc:postgresql://([^:/]+):?([0-9]*)/([^\?]+) ]]
    export _DBHOST="${BASH_REMATCH[1]}"
    export _DBPORT="${BASH_REMATCH[2]}"
    export _DBNAME="${BASH_REMATCH[3]}"
    export _DBUSER="${username}"
    if [[ "${password}" =~ [a-zA-Z0-9] ]]; then
        export PGPASSWORD="${password}"
    fi
}

# NOTE: currently this function is tested against support.zip boot-ed then migrated database
# Example export command (Using --no-owner and --clean, but not using --data-only as needs CREATE statements. -t with * requires PostgreSQL v12 or higher):
# Other interesting tables: -t "*_browse_node" -t "*deleted_blob*" -t "change_blobstore"
function f_export_postgresql_component() {
    local __doc__="Export specific tables from PostgreSQL, like OrientDB's component database"
    local _exportTo="${1:-"./component_db_$(date +"%Y%m%d%H%M%S").sql.gz"}"
    local _fmt="${2}"
    local _workingDirectory="${3}"
    if [ -z "${_workingDirectory}" ]; then
        _workingDirectory="$(_get_work_dir)"
        [ -z "${_workingDirectory}" ] && _log "ERROR" "No sonatype work directory found (to read nexus-store.properties)" && return 1
    fi
    [ -z "${_fmt}" ] && _fmt="*"
    _export_postgres_config "${_workingDirectory%/}/etc/fabric/nexus-store.properties" || return $?
    PGGSSENCMODE=disable pg_dump -h ${_DBHOST} -p ${_DBPORT:-"5432"} -U ${_DBUSER} -d ${_DBNAME} -c -O -t "repository" -t "${_fmt}_content_repository" -t "${_fmt}_component" -t "${_fmt}_component_tag" -t "${_fmt}_asset" -t "${_fmt}_asset_blob" -t "tag" -Z 6 -f "${_exportTo}"
}

# How to verify
#VACUUM(FREEZE, ANALYZE, VERBOSE);  -- or FULL (FREEZE marks the table as vacuumed)
#SELECT relname, reltuples as row_count_estimate FROM pg_class WHERE relnamespace ='public'::regnamespace::oid AND relkind = 'r' AND relname NOT LIKE '%_browse_%' AND (relname like '%repository%' OR relname like '%component%' OR relname like '%asset%') ORDER BY 2 DESC LIMIT 40;
function f_restore_postgresql_component() {
    local __doc__="Restore f_export_postgresql_component generated gzip file into the database"
    local _sql_file="${1}"
    local _workingDirectory="${2}"
    if [ -z "${_workingDirectory}" ]; then
        _workingDirectory="$(_get_work_dir)"
        [ -z "${_workingDirectory}" ] && _log "ERROR" "No sonatype work directory found (to read nexus-store.properties)" && return 1
    fi
    if [ -z "${_sql_file}" ]; then
        _sql_file="$(ls -1 ./component_db_*.sql.gz | tail -n1)"
        [ -z "${_sql_file}" ] && _log "ERROR" "No sql file to restore/import" && return 1
    fi

    _export_postgres_config "${_workingDirectory%/}/etc/fabric/nexus-store.properties" || return $?
    local _cmd="psql -h ${_DBHOST} -p ${_DBPORT:-"5432"} -U ${_DBUSER} -d ${_DBNAME}"
    if [[ "${_sql_file}" =~ \.gz$ ]]; then
        gunzip -c "${_sql_file}" || return $?
    else
        cat "${_sql_file}" || return $?
    fi | sed -E 's/^DROP TABLE ([^;]+);$/DROP TABLE \1 cascade;/' | PGGSSENCMODE=disable ${_cmd} -L ./psql_restore.log 2>./psql_restore.log
    _log "INFO" "Executed '... ${_sql_file} | ${_cmd} ... ./psql_restore.log"
    grep -w ERROR ./psql_restore.log | grep -v "cannot drop constraint"
}

#f_psql "SELECT blob_ref FROM %FMT%_asset_blob"
#f_psql "SELECT attributes FROM %FMT%_content_repository WHERE attributes is not null and attributes <> '{}'"
#f_psql "UPDATE %FMT%_content_repository SET attributes = '{}'::jsonb WHERE attributes is not null and attributes <> '{}'"
#f_psql "SELECT r.repo_name, sc.namespace, sc.search_component_name, sc.version, sc.last_modified, sc.tags FROM search_components sc JOIN r USING (repository_id) ORDER BY last_modified DESC"
function f_psql() {
    local __doc__="Query against all assets or components by using nexus-store.properties"
    local _query="${1}" # Use '%FMT%'
    local _workingDirectory="${2:-"."}"
    local _dry_run="${3:-"${_DRY_RUN}"}"
    local _psql_opts="${4-"${_PSQL_OPTS}"}" # -tAF,
    local _prop="$(find "${_workingDirectory%/}" -maxdepth 5 -name nexus-store.properties -path '*/etc/fabric/*' | head -n1)"
    _export_postgres_config "${_prop}" || return $?
    local _cmd="psql -h ${_DBHOST} -p ${_DBPORT:-"5432"} -U ${_DBUSER} -d ${_DBNAME}"
    if [ -z "${_query}" ]; then
        # If no query, start the psql console
        ${_cmd}
        return $?
    fi

    if [[ "${_query}" =~ %FMT% ]]; then
        ${_cmd} -tA -c "SELECT distinct REGEXP_REPLACE(recipe_name, '-.+', '') AS fmt FROM repository ORDER BY fmt" | while read -r _fmt; do
            local _q="$(echo "${_query}" | sed "s/%FMT%/${_fmt}/g")"
            echo "# ${_q}" >&2
            if [[ "${_dry_run}" =~ ^[yY] ]]; then
                continue
            fi
            ${_cmd} ${_psql_opts} -c "${_q}" || return $?
        done
        return
    fi

    local _q_cte=""
    for _fmt in $(psql -d nxrm3772ha -tA -c "SELECT distinct REGEXP_REPLACE(recipe_name, '-.+', '') AS fmt FROM repository ORDER BY fmt"); do
        if [ -n "${_q_cte}" ]; then
            _q_cte="${_q_cte} UNION ALL "
        fi
        _q_cte="${_q_cte}SELECT r.name as repo_name, cr.repository_id FROM ${_fmt}_content_repository cr join repository r on r.id = cr.config_repository_id"
    done
    ${_cmd} ${_psql_opts} -c "WITH r AS (${_q_cte}) ${_query}"
    return $?
}



### Misc.
# f_set_log_level "root"
# f_set_log_level "org.eclipse.jetty.server.HttpChannel" (outbound pool)
# f_set_log_level "org.eclipse.jetty.util.thread" (thread pool)
# f_set_log_level "com.zaxxer.hikari.pool.HikariPool" (db pool)
function f_set_log_level() {
    local __doc__="Set / Change some logger's log level"
    # NOTE: if incorrect class name is used, may need to edit sonatype-work/nexus3/etc/logback/logback-overrides.xml
    local _log_class="${1}"
    local _log_level="${2:-"DEBUG"}"
    if [ -z "${_log_class}" ]; then
        _log "INFO" "RESET-ing the log levels"
        _log_class="RESET"
    fi
    if [ "${_log_class}" == "root" ]; then
        _log_class="ROOT"
    elif [ "${_log_class}" == "RESET" ] || [ "${_log_class}" == "reset" ]; then
        f_api "/service/rest/internal/ui/loggingConfiguration/reset" "" "POST"
        return $?
    fi
    f_api "/service/rest/internal/ui/loggingConfiguration/${_log_class}" "{\"name\":\"${_log_class}\",\"level\":\"${_log_level}\"}" "PUT"
}

function f_setup_service() {
    local __doc__="Setup NXRM as a service"
    # https://help.sonatype.com/display/NXRM3/Run+as+a+Service
    local _base_dir="${1:-"."}"
    local _usr="${2:-"$USER"}"
    local _num_of_files="${3:-4096}"    # Increase this if production
        local _svc_file="/etc/systemd/system/nexus.service"
    local _env="#env="
    # NOTE: you can also use EnvironmentFile=/etc/envfile.conf
    #_env="Environment=\"INSTALL4J_ADD_VM_PARAMS=-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005\""
    local _bin_nexus="$(find "${_base_dir%/}" -maxdepth 3 -type f -name "nexus" -path '*/bin/*' | head -n1)"
    if [ -z "${_bin_nexus}" ]; then
        _log "ERROR" "Nexus executable does not exist under ${_base_dir%/}"
        return 1
    fi
    _bin_nexus="$(readlink -f "${_bin_nexus}")"

    if [ -s ${_svc_file} ]; then
        _log "WARN" "${_svc_file} already exists. Overwriting..."; sleep 3
    fi
    # NOTE: If OS is integrated with One Identity Authentication Service, use "After=vasd.target"
    #       If needs to wait for (network) mount: https://unix.stackexchange.com/questions/246935/set-systemd-service-to-execute-after-fstab-mount
    cat << EOF > /tmp/nexus.service || return $?
[Unit]
Description=nexus service
After=network-online.target

[Service]
${_env}
Type=forking
LimitNOFILE=${_num_of_files}
ExecStart=${_bin_nexus} start
ExecStop=${_bin_nexus} stop
User=${_usr}
Restart=on-abort
TimeoutSec=600

[Install]
WantedBy=multi-user.target
EOF
    sudo cp -f -v /tmp/nexus.service ${_svc_file} || return $?
    sudo chmod a+x ${_svc_file}
    sudo systemctl daemon-reload || return $?
    sudo systemctl enable nexus.service
    _log "INFO" "Service configured. If Nexus is currently running, please stop, then 'systemctl start nexus.service'"
    # NOTE: for troubleshooting 'systemctl cat nexus'
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
    _ask "Would you like to install Nexus?" "Y" "r_NEXUS_INSTALL" "N" "N"
    if _isYes "${r_NEXUS_INSTALL}"; then
        _ask "Nexus version" "latest" "r_NEXUS_VERSION" "N" "Y"
        if [ "${r_NEXUS_VERSION}" == "latest" ]; then
            r_NEXUS_VERSION="$(curl -s -I https://github.com/sonatype/nexus-public/releases/latest | sed -n -E '/^location/ s/^location: http.+\/release-([0-9\.-]+).*$/\1/p')"
        fi
        #local _ver_num=$(echo "${r_NEXUS_VERSION}" | sed 's/[^0-9]//g')
        local _port="$(_find_port "8081")"
        _ask "Nexus install port" "${_port}" "r_NEXUS_INSTALL_PORT" "N" "Y" "_is_port_available"
        _ask "*Existing* PostgreSQL DB name or 'h2'=H2 or empty=OrientDB)" "" "r_NEXUS_DBNAME" "N" "N" "_is_DB_created"
        if [ -n "${r_NEXUS_DBNAME}" ] && [[ ! "${r_NEXUS_DBNAME}" =~ ^[hH]2 ]]; then
            _ask "Start this Nexus as new HA?" "N" "r_NEXUS_ENABLE_HA" "N" "N"
        fi
        _ask "Nexus install path" "./nexus_${r_NEXUS_VERSION}${r_NEXUS_DBNAME}" "r_NEXUS_INSTALL_PATH" "N" "N" "_is_available"
        _ask "Nexus license file path if you have:
If empty, it will try finding from ${_WORK_DIR%/}/sonatype/sonatype-*.lic" "" "r_NEXUS_LICENSE_FILE" "N" "N" "_is_license_path"
        _ask "Nexus base URL" "${_NEXUS_URL}" "r_NEXUS_URL" "N" "Y"
    else
        _ask "Nexus base URL" "${_NEXUS_URL}" "r_NEXUS_URL" "N" "Y" "_is_url_reachable"
    fi

    local _host="$(hostname -f)"
    [[ "${r_NEXUS_URL}" =~ ^https?://([^:/]+).+$ ]] && _host="${BASH_REMATCH[1]}"
    _ask "Blob store name (empty = automatically decided)" "${_BLOBTORE_NAME}" "r_BLOBSTORE_NAME" "N" "N"
    [ -n "${r_NEXUS_DBNAME}" ] && [ -z "${_DATASTORE_NAME}" ] && _DATASTORE_NAME="nexus"
    _ask "Data store name ('nexus' if PostgreSQL/H2, empty if OrientDB)" "${_DATASTORE_NAME}" "r_DATASTORE_NAME"
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


### Validation functions (NOTE: needs to start with _is because of _ask()) #######################################
function _is_repo_available() {
    local _repo_name="$1"
    local _nexus_url="${2:-"${r_NEXUS_URL:-"${_NEXUS_URL}"}"}"
    # At this moment, not always checking
    find -L ${_TMP%/} -type f -name '_does_repo_exist*.out' -mmin +5 --exec rm -f {} \; 2>/dev/null
    if [ ! -s ${_TMP%/}/_does_repo_exist$$.out ]; then
        _NEXUS_URL="${_nexus_url}" f_api "/service/rest/v1/repositories" | grep '"name":' > ${_TMP%/}/_does_repo_exist$$.out
    fi
    if [ -n "${_repo_name}" ]; then
        # case insensitive
        grep -iq "\"${_repo_name}\"" ${_TMP%/}/_does_repo_exist$$.out
        return $?
    fi
    cat ${_TMP%/}/_does_repo_exist$$.out | sed -n -E 's/^ *"name": *"([^"]+)".*/\1/p'
    return 1
}
function _is_blob_available() {
    local _bs_name="$1"
    local _nexus_url="${2:-"${r_NEXUS_URL:-"${_NEXUS_URL}"}"}"
    # At this moment, not always checking
    find -L ${_TMP%/} -type f -name '_does_blob_exist*.out' -mmin +5 -exec rm -f {} \; 2>/dev/null
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
    return 0
}
function _is_license_path() {
    if [ -n "$1" ] && [ ! -s "$1" ]; then
        echo "$1 does not exist." >&2
        return 1
    fi
    return 0
}
function _is_url_reachable() {
    # As I'm checking the reachability, not using -f
    if [ -n "$1" ] && ! curl -s -I -L -k -m1 --retry 0 "$1" &>/dev/null; then
        echo "$1 is not reachable." >&2
        return 1
    fi
    return 0
}
function _is_port_available() {
    # TODO: checking only tcp (and ipv4)
    if [ "`uname`" = "Darwin" ]; then
        lsof -ti:${1}
    else
        netstat -t4lnp | grep -q -wE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:${1}"
    fi &>/dev/null && return 1
    return 0
}
function _is_available() {
    if [ -n "$1" ] && [ -e "$1" ]; then
        echo "$1 is already taken." >&2
        return 1
    fi
    return 0
}
function _is_DB_created() {
    # If can't check, return true for now
    type psql &>/dev/null || return 0
    # special logic
    if [ -z "${1}" ] || [[ "${1}" =~ ^[hH]2 ]]; then
        return 0
    fi

    psql -l 2>/dev/null | grep -qE "^\s*${1}\s"
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

    # If _RESP_FILE is populated by -r xxxxx.resp, load it
    if [ -s "${_RESP_FILE}" ];then
        _load_resp "${_RESP_FILE}"
    elif ! ${_AUTO}; then
        _ask "Would you like to load your response file?" "N" "" "N" "N"
        _isYes && _load_resp
    fi
    # Command line arguments are stronger than response file
    [ -n "${_REPO_FORMATS_FROM_ARGS}" ] && r_REPO_FORMATS="${_REPO_FORMATS_FROM_ARGS}"
    [ -n "${_NEXUS_VERSION_FROM_ARGS}" ] && r_NEXUS_VERSION="${_NEXUS_VERSION_FROM_ARGS}"
    [ -n "${_NEXUS_DBNAME_FROM_ARGS}" ] && r_NEXUS_DBNAME="${_NEXUS_DBNAME_FROM_ARGS}"

    if ! ${_AUTO}; then
        interview
        _ask "Interview completed. Would like you like to start configuring?" "Y" "" "N" "N"
        if ! _isYes; then
            echo 'Bye!'
            return
        fi
    fi

    if _isYes "${r_NEXUS_INSTALL}"; then
        #echo "NOTE: If 'password' is asked, please type 'sudo' password." >&2
        echo "Starting Nexus installation..." >&2
        _NEXUS_START="Y" f_install_nexus3 || return $?
    fi
    if [ -z "${r_NEXUS_URL:-"${_NEXUS_URL}"}" ] || ! _wait_url "${r_NEXUS_URL:-"${_NEXUS_URL}"}"; then
        _log "ERROR" "${r_NEXUS_URL:-"${_NEXUS_URL}"} is unreachable"
        return 1
    fi

    _log "INFO" "Updating 'admin' user's password (may fail if already updated) ..."
    f_nexus_change_pwd "admin" "${r_ADMIN_PWD:-"${_ADMIN_PWD}"}" "" "."

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
    f_create_csel &>/dev/null  # it's OK if this fails
    _log "INFO" "Creating 'testuser' if it hasn't been created."
    f_create_testuser &>/dev/null
    #f_create_testuser "testuser" "\"csel-test-priv\"" "test-role"

    if _isYes "${r_NEXUS_CLIENT_INSTALL}"; then
        _log "INFO" "Installing a client container ..."
        p_client_container "" "" ""
    fi
    _log "INFO" "Setup completed. (log:${_LOG_FILE_PATH})"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || [[ "$1" == "help" ]]; then
        if [[ "$2" =~ ^f_ ]] && type _help &>/dev/null; then
            _help "$2" | less
        elif [ "$2" == "list" ] && type _list &>/dev/null; then
            _list | less
        else
            usage | less
        fi
        exit 0
    fi
    
    # parsing command options (help is handled before calling 'main')
    _REPO_FORMATS_FROM_ARGS=""
    _NEXUS_VERSION_FROM_ARGS=""
    _NEXUS_DBNAME_FROM_ARGS=""
    while getopts "ADf:r:v:d:" opts; do
        case $opts in
            A)
                _AUTO=true
                ;;
            D)
                _DEBUG=true
                ;;
            r)
                _RESP_FILE="$OPTARG"
                ;;
            f)
                _REPO_FORMATS_FROM_ARGS="$OPTARG"
                ;;
            v)
                _NEXUS_VERSION_FROM_ARGS="$OPTARG"
                ;;
            d)
                _NEXUS_DBNAME_FROM_ARGS="$OPTARG"
                ;;
			*)
				echo "Unsupported command line argument: $opts"
				exit 1
				;;
        esac
    done
    
    main
fi