#!/usr/bin/env bash
# BASH script to setup Nexus IQ configs
#   bash <(curl -sSfL https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_nexus_iq.sh --compressed) -A
#
# For local test:
#   _import() { source /var/tmp/share/sonatype/$1; } && export -f _import
#
# How to source:
#   source /dev/stdin <<< "$(curl -sSfL https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_nexus_iq.sh --compressed)"
#   #export _IQ_URL="http://localhost:8070/"
#   _AUTO=true main
#
# TODO: some of functions uses python, which does not exist in the image
# TODO: Direct / Transitive example for Java and NPM
#
_DL_URL="${_DL_URL:-"https://raw.githubusercontent.com/hajimeo/samples/master"}"
type _import &>/dev/null || _import() { [ ! -s /tmp/${1} ] && curl -sf --compressed "${_DL_URL%/}/bash/$1" -o /tmp/${1}; . /tmp/${1}; }

_import "utils.sh"
_import "utils_db.sh"

function usage() {
    local _filename="$(basename $BASH_SOURCE)"
    echo "Main purpose of this script is to create repositories with some sample components.
Also functions in this script can be used for testing downloads and uploads.

#export _IQ_URL='http://SOME_REMOTE_IQ:8070/'
./${_filename} -A

DOWNLOADS:
    curl ${_DL_URL%/}/bash/${_filename} -o ${_WORK_DIR%/}/sonatype/${_filename}

REQUIREMENTS / DEPENDENCIES:
    If Mac, 'gsed' and 'ggrep' are required (brew install gnu-sed grep)
    Also, currently requires 'python'

COMMAND OPTIONS:
    -A
        Automatically setup repositories against _IQ_URL Nexus (best effort)
    -r <response_file_path>
        Specify your saved response file. Without -A, you can review your responses.
    -f <format1,format2,...>
        Comma separated repository formats.
        Default: ${_REPO_FORMATS}
    -v <nexus version>
        Install Nexus with this version number (eg: 1.170.0)
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

Create IQ 1.170.0 and setup available formats:
    sudo ${_filename} -v 1.170.0 [-A]

Using previously saved response file and review your answers:
    sudo ${_filename} -r ./my_saved_YYYYMMDDhhmmss.resp

Using previously saved response file and NO interviews:
    sudo ${_filename} -A -r ./my_saved_YYYYMMDDhhmmss.resp
"
}

## Global variables
: ${_ADMIN_USER:="admin"}
: ${_ADMIN_PWD:="admin123"}
: ${_IQ_URL:="http://localhost:8070/"}
_TMP="/tmp"  # for downloading/uploading assets
_DEBUG=false
alias _curl="curl -sSf -u '${_ADMIN_USER}:${_ADMIN_PWD}'"



# To upgrade (from ${_dirname}/): mv -f -v ./config.yml{,.tmp} && tar -xvf $HOME/.nexus_executable_cache/nexus-iq-server-1.179.0-04-bundle.tar.gz && cp -p -v ./config.yml{.tmp,}
function f_install_iq() {
    local __doc__="Install specific IQ version (to recreate sonatype-work and DB, _RECREATE_ALL=Y)"
    local _ver="${1}"     # 'latest'
    local _dbname="${2}"
    local _dbusr="${3:-"nexus"}"     # Specifying default as do not want to create many users/roles
    local _dbpwd="${4:-"${_dbusr}123"}"
    local _port="${5:-"${_IQ_INSTALL_PORT}"}"      # If not specified, checking from 8070
    local _dirpath="${6}"    # If not specified, create a new dir under current dir
    local _download_dir="${7}"
    local _starting="${_NEXUS_START}"
    if [ -z "${_ver}" ] || [ "${_ver}" == "latest" ]; then
        local _location="$(curl -sSf -I "https://download.sonatype.com/clm/server/latest.tar.gz" | grep -i '^location:')"
        if [[ "${_location}" =~ nexus-iq-server-([0-9.]+-[0-9]+)-bundle.tar.gz ]]; then
            _ver="${BASH_REMATCH[1]}"
        fi
    fi
    [ -z "${_ver}" ] && return 1
    if [ -z "${_port}" ]; then
        _port="$(_find_port "8070" "" "^8071$")"
        [ -z "${_port}" ] && return 1
        _log "INFO" "Using port: ${_port}" >&2
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
        _dirpath="./nxiq_${_ver}"
        [ -n "${_dbname}" ] && _dirpath="${_dirpath}_${_dbname}"
        [ "${_port}" != "8070" ] && _dirpath="${_dirpath}_${_port}"
    fi
    if [[ "${_RECREATE_ALL}" =~ [yY] ]]; then
        if [ -d "${_dirpath%/}" ]; then
            _log "WARN" "As _RECREATE_ALL=${_RECREATE_ALL}, removing ${_dirpath%/}"; sleep 3
            rm -v -rf "${_dirpath%/}" || return $?
        fi
        _RECREATE_DB="Y"
    fi

    _prepare_install "${_dirpath}" "https://download.sonatype.com/clm/server/nexus-iq-server-${_ver}-bundle.tar.gz" "${r_NEXUS_LICENSE_FILE}" || return $?
    local _license_path="${_LICENSE_PATH}"

    local _jar_file="$(find ${_dirpath%/} -maxdepth 2 -type f -name 'nexus-iq-server*.jar' 2>/dev/null | sort | tail -n1)"
    [ -z "${_jar_file}" ] && return 11
    local _cfg_file="$(find ${_dirpath%/} -maxdepth 2 -type f -name 'config.yml' 2>/dev/null | sort | tail -n1)"
    [ -z "${_cfg_file}" ] && return 12

    if [ ! -f "${_cfg_file}.orig" ]; then
        cp -p "${_cfg_file}" "${_cfg_file}.orig"
    fi
    # TODO: From v138, most of configs need to use API: https://help.sonatype.com/iqserver/automating/rest-apis/configuration-rest-api---v2
    grep -qE '^hdsUrl:' "${_cfg_file}" || echo -e "hdsUrl: https://clm-staging.sonatype.com/\n$(cat "${_cfg_file}")" > "${_cfg_file}"
    grep -qE '^licenseFile' "${_cfg_file}" || echo -e "licenseFile: ${_license_path%/}\n$(cat "${_cfg_file}")" > "${_cfg_file}"
    grep -qE '^\s*port: 8070' "${_cfg_file}" && sed -i.tmp 's/port: 8070/port: '${_port}'/g' "${_cfg_file}"
    grep -qE '^\s*port: 8071' "${_cfg_file}" && sed -i.tmp 's/port: 8071/port: '$((${_port} + 1))'/g' "${_cfg_file}"

    if [ -n "${_dbname}" ]; then
        # NOTE: currently assuming "database:" is the end of file
        cat << EOF > ${_cfg_file}
$(sed -n '/^database:/q;p' ${_cfg_file})
database:
  type: postgresql
  hostname: $(hostname -f)
  port: 5432
  name: ${_dbname}
  username: ${_dbusr}
  password: ${_dbpwd}
EOF
        if ! _RECREATE_DB=${_RECREATE_DB} _postgresql_create_dbuser "${_dbusr}" "${_dbpwd}" "${_dbname}"; then
            _log "WARN" "Failed to create ${_dbusr} or ${_dbname}"
        fi
    fi

    [ ! -d ./log ] && mkdir -m 777 ./log
    if _isYes "${_starting}"; then
        echo "Starting with: java -jar ${_jar_file} server ${_cfg_file} >./log/iq-server.out 2>./log/iq-server.err &"; sleep 3
        eval "java -jar ${_jar_file} server ${_cfg_file} >./log/iq-server.out 2>./log/iq-server.err &"
    else
        cd "${_dirpath%/}" || return $?
        echo "To start: java -jar ${_jar_file} server ${_cfg_file} 2>./log/iq-server.err"
        if type iqStart &>/dev/null; then
            if type f_config_update &>/dev/null; then
                echo "      Or: iqStart & f_config_update; fg"
            else
                echo "      Or: iqStart"
            fi
        fi
    fi
}


### API related
function f_api_config() {
    local __doc__="/api/v2/config"
    local _d="$1"
    local _path="$2"
    local _method="${3:-"GET"}"
    local _content_type="${4}"
    local _url="${_IQ_URL%/}/api/v2/config${_path}"
    local _cmd="_curl -X \"${_method}\""
    if [[ "${_d}" =~ ^property= ]]; then
        _url="${_url}?${_d}"
    elif [ -n "${_d}" ]; then
        _cmd="_curl -X \"PUT\" -H \"Content-Type: application/json\" -d '${_d}'"
    fi
    #echo "${_cmd}"
    eval "${_cmd} ${_url}" || return $?
}

function f_api_orgId() {
    local __doc__="Get organization Internal ID from /api/v2/organizations (or create)"
    local _org_name="${1:-"Sandbox Organization"}"
    local _create="${2}"
    local _org_result="$(_curl "${_IQ_URL%/}/api/v2/organizations" --get --data-urlencode "organizationName=${_org_name}")"
    [ -z "${_org_result}" ] && return 12
    local _org_int_id="$(echo "${_org_result}" | python -c "import sys,json
a=json.loads(sys.stdin.read())
if len(a['organizations']) > 0:
    print(a['organizations'][0]['id'])")"
    if [ -z "${_org_int_id}" ] && [[ "${_create}" =~ ^[yY] ]]; then
        _org_int_id="$(_curl "${_IQ_URL%/}/api/v2/organizations" -H "Content-Type: application/json" -d "{\"name\":\"${_org_name}\"}" | python -c "import sys,json
a=json.loads(sys.stdin.read())
if 'id' in a:
    print(a['id'])")"
    fi
    echo "${_org_int_id}"
}

function f_api_appIntId() {
    local __doc__="Get application Internal ID from /api/v2/applications?publicId=\${_app_pub_id}"
    local _app_pub_id="${1}"
    _curl "${_IQ_URL%/}/api/v2/applications" --get --data-urlencode "publicId=${_app_pub_id}" | python -c "import sys,json
a=json.loads(sys.stdin.read())
if len(a['applications']) > 0:
    print(a['applications'][0]['id'])"
}

function f_api_create_app() {
    local __doc__="Create an application with /api/v2/applications"
    local _app_pub_id="${1}"
    local _create_under_org="${2:-"Sandbox Organization"}"
    [ -z "${_app_pub_id}" ] && return 11
    local _org_int_id="$(f_api_orgId "${_create_under_org}" "Y")"
    _curl "${_IQ_URL%/}/api/v2/applications" -H "Content-Type: application/json" -d '{"publicId":"'${_app_pub_id}'","name": "'${_app_pub_id}'","organizationId": "'${_org_int_id}'"}'
}

function f_api_role_mapping() {
    local __doc__="map an external user/group to IQ organisation/application and role"
    local _role_name="$1"
    local _external_id="$2" # login username, LDAP/AD groupname etc.
    local _apporg_name="${3:-"Root Organization"}"
    local _user_or_group="${4:-"group"}"
    local _app_or_org="organization"    # TODO: application is not supported yet
    local _role_int_id="$(_curl "${_IQ_URL%/}/api/v2/roles" | python -c "import sys,json
a=json.loads(sys.stdin.read())
for r in a['roles']:
    if '${_role_name}'.lower() == r['name'].lower():
        print(r['id'])
        break")"
    if [ -z "${_role_int_id}" ] || [ -z "${_external_id}" ]; then
        _curl "${_IQ_URL%/}/api/v2/roles" | python -m json.tool | grep '"name"'
        return $?
    fi
    _log "INFO" "Using Role Internal Id = ${_role_int_id} ..."
    local _int_id="$(_curl "${_IQ_URL%/}/api/v2/${_app_or_org}s"  --get --data-urlencode "${_app_or_org}Name=${_apporg_name}" | python -c "import sys,json
a=json.loads(sys.stdin.read())
print(a['${_app_or_org}s'][0]['id'])")" || return $?
    if [ -z "${_int_id}" ]; then
        _curl "${_IQ_URL%/}/api/v2/${_app_or_org}s" | python -m json.tool | grep '"name"'
        return $?
    fi
    _log "INFO" "Using ${_app_or_org} Internal Id = ${_int_id} ..."
    _curl "${_IQ_URL%/}/api/v2/roleMemberships/${_app_or_org}/${_int_id}/role/${_role_int_id}/${_user_or_group}/${_external_id}" -X PUT
    _curl "${_IQ_URL%/}/api/v2/roleMemberships/${_app_or_org}/${_int_id}" | python -c "import sys,json
a=json.loads(sys.stdin.read())
for r in a['memberMappings']:
    if '${_role_int_id}' == r['roleId']:
        print(json.dumps(r['members'], indent=2))
        break"
}

function f_api_eval_gav() {
    local __doc__="/api/v2/evaluation/applications/\${_app_int_id} with Maven GAV"
    local _gav="${1}"
    local _app_pub_id="${2:-"sandbox-application"}"
    [[ "${_gav}" =~ ^" "*([^: ]+)" "*:" "*([^: ]+)" "*:" "*([^: ]+)" "*$ ]] || return 11
    local _g="${BASH_REMATCH[1]}"
    local _a="${BASH_REMATCH[2]}"
    local _v="${BASH_REMATCH[3]}"
    local _app_int_id="$(f_api_appIntId "${_app_pub_id}")" || return $?

    _curl "${_IQ_URL%/}/api/v2/evaluation/applications/${_app_int_id}" -H "Content-Type: application/json" -d '{"components": [{"hash": null,"componentIdentifier": {"format": "maven","coordinates": {"artifactId": "'${_a}'","groupId": "'${_g}'","version": "'${_v}'","extension":"jar"}}}]}'
}



### Misc. setup functions
function f_config_update() {
    local _baseUrl="${1:-"${_IQ_URL}"}"
    local _no_wait="${2}"
    if ! f_api_config '{"baseUrl":"'${_baseUrl%/}'/","forceBaseUrl":false}' &>/dev/null; then
        if [ -z "${_no_wait}" ] && [ -n "${_IQ_URL%/}" ] && type _wait_url &>/dev/null; then
            _wait_url "${_IQ_URL%/}"
        fi
        f_api_config '{"baseUrl":"'${_baseUrl%/}'/","forceBaseUrl":false}' || return $?
    fi
    f_api_config '{"hdsUrl":"https://clm-staging.sonatype.com/"}'
    f_api_config '{"enableDefaultPasswordWarning":false}'
    f_api_config '{"sessionTimeout":120}'   # between 3 and 120
    f_api_config "" "/features/internalFirewallOnboardingEnabled" "DELETE" &>/dev/null  # this one can return 400
    #curl -u "admin:admin123" "${_IQ_URL%/}/api/v2/config/features/internalFirewallOnboardingEnabled" -X DELETE #POST
}

function f_add_testuser() {
    local __doc__="Add/Create a test IQ user with test-role"
    local _username="${1:-"testuser"}"
    local _password="${2:-"${_username}123"}"
    _apiS "/rest/user" '{"firstName":"'${_username}'","lastName":"test","email":"'${_username}'@example.com","username":"'${_username}'","password":"'${_password}'"}'
    _apiS "/rest/security/roles" '{"name":"test-role","description":"test_role_desc","builtIn":false,"permissionCategories":[{"displayName":"Administrator","permissions":[{"id":"VIEW_ROLES","displayName":"View","description":"All Roles","allowed":false}]},{"displayName":"IQ","permissions":[{"id":"MANAGE_PROPRIETARY","displayName":"Edit","description":"Proprietary Components","allowed":false},{"id":"CLAIM_COMPONENT","displayName":"Claim","description":"Components","allowed":false},{"id":"WRITE","displayName":"Edit","description":"IQ Elements","allowed":false},{"id":"READ","displayName":"View","description":"IQ Elements","allowed":true},{"id":"EDIT_ACCESS_CONTROL","displayName":"Edit","description":"Access Control","allowed":false},{"id":"EVALUATE_APPLICATION","displayName":"Evaluate","description":"Applications","allowed":true},{"id":"EVALUATE_COMPONENT","displayName":"Evaluate","description":"Individual Components","allowed":true},{"id":"ADD_APPLICATION","displayName":"Add","description":"Applications","allowed":false},{"id":"MANAGE_AUTOMATIC_APPLICATION_CREATION","displayName":"Manage","description":"Automatic Application Creation","allowed":false},{"id":"MANAGE_AUTOMATIC_SCM_CONFIGURATION","displayName":"Manage","description":"Automatic Source Control Configuration","allowed":false}]},{"displayName":"Remediation","permissions":[{"id":"WAIVE_POLICY_VIOLATIONS","displayName":"Waive","description":"Policy Violations","allowed":true},{"id":"CHANGE_LICENSES","displayName":"Change","description":"Licenses","allowed":false},{"id":"CHANGE_SECURITY_VULNERABILITIES","displayName":"Change","description":"Security Vulnerabilities","allowed":false},{"id":"LEGAL_REVIEWER","displayName":"Review","description":"Legal obligations for components licenses","allowed":false}]}]}' || return $?
    f_api_role_mapping "test-role" "testuser" "Root Organization" "user"
}

function f_setup_https() {
    local __doc__="Modify config files to enable SSL/TLS/HTTPS"
    # https://guides.sonatype.com/iqserver/technical-guides/iq-secure-connections/
    local _p12="${1}"   # If empty, will use *.standalone.localdomain cert.
    local _port="${2:-8470}"
    local _pwd="${3:-"password"}"
    local _alias="${4}"
    local _base_dir="${5:-"${_BASE_DIR:-"."}"}"
    local _usr="${6:-${_SERVICE}}"
    local _fqdn="$(hostname -f)"
    [[ "${_IQ_URL}" =~ https?://([^:/]+) ]] && _fqdn="${BASH_REMATCH[1]}"

    local _jar_file="$(find "${_base_dir%/}" -maxdepth 2 -type f -name 'nexus-iq-server*.jar' 2>/dev/null | sort | tail -n1)"
    [ -z "${_jar_file}" ] && return 11
    local _cfg_file="$(find "${_base_dir%/}" -maxdepth 2 -type f -name 'config.yml' 2>/dev/null | sort | tail -n1)"
    [ -z "${_cfg_file}" ] && return 12

    # If never started no "sonatype-work/clm-server"
    [ -d "${_base_dir%/}/sonatype-work/clm-server" ] || mkdir -p -v "${_base_dir%/}/sonatype-work/clm-server/cert"
    # Using sonatypeWork as upgrading breaks this IQ.
    if [ -s "${_base_dir%/}/sonatype-work/clm-server/keystore.p12" ]; then
        _p12="${_base_dir%/}/sonatype-work/clm-server/keystore.p12"
        _log "INFO" "${_p12} exits. reusing ..."; sleep 1
    else
        if [ -n "${_p12}" ]; then
            cp -v -f "${_p12}" "${_base_dir%/}/sonatype-work/clm-server/keystore.p12" || return $?
            _p12="${_base_dir%/}/sonatype-work/clm-server/keystore.p12"
        else
            _p12="${_base_dir%/}/sonatype-work/clm-server/keystore.p12"
            curl -sSf -L -o "${_p12}" "${_DL_URL%/}/misc/standalone.localdomain.p12" || return $?
            _log "INFO" "No P12 file specified. Downloaded standalone.localdomain.p12 ..."
            _fqdn="local.standalone.localdomain"
        fi
        [ -n "${_usr}" ] && chown "${_usr}" "${_p12}" && chmod 600 "${_p12}"
    fi

    if [ -z "${_alias}" ] && which keytool &>/dev/null; then
        _alias="$(keytool -list -v -keystore ${_base_dir%/}/sonatype-work/clm-server/keystore.p12 -storetype PKCS12 -storepass "${_pwd}" 2>/dev/null | _sed -nr 's/Alias name: (.+)/\1/p')"
        _log "INFO" "Using '${_alias}' as alias name..."; sleep 1
    fi

    _log "INFO" "Updating ${_cfg_file} ..."
    if [ ! -s ${_cfg_file}.orig ]; then
        cp -p ${_cfg_file} ${_cfg_file}.orig || return $?
    fi
    if grep -qE '^\s*-\s*type:\s*https' ${_cfg_file}; then
        _log "ERROR" "Looks like https is already configured."
        return 1
    fi
    local _workdir_escaped="`echo "${_base_dir%/}/sonatype-work/clm-server" | _sed 's/[\/]/\\\&/g'`"
    local _lines="    - type: https\n      port: ${_port}\n      keyStorePath: ${_workdir_escaped%/}\/keystore.p12\n      keyStorePassword: ${_pwd}\n      certAlias: ${_alias}"
    # TODO: currently replacing only the first match with "0,/" (so not doing for admin port)
    _sed -i -r "0,/^(\s*applicationConnectors:.*)$/s//\1\n${_lines}/" ${_cfg_file}

    _log "INFO" "Please restart service.
Also update _IQ_URL. For example: export _IQ_URL=\"https://${_fqdn}:${_port}/\""
    echo "To check the SSL connection:
    curl -svf -k \"https://${_fqdn}:${_port}/\" -o/dev/null 2>&1 | grep 'Server certificate:' -A 5"
    # TODO: generate pem file and trust
    #_trust_ca "${_ca_pem}" || return $?
    _log "INFO" "To trust this certificate, _trust_ca \"\${_ca_pem}\""
}


# Setup Org only: f_setup_scm "_token"
# Setup Org&app : f_setup_scm "_token" "github" "https://github.com/hajimeo/private-repo"
#  vs. CLI scan : iqCli . "private-repo" "source"
function f_setup_scm() {
    local __doc__="Setup IQ SCM"
    local _git_url="${1}"   # https://github.com/sonatype/support-apac-scm-test https://github.com/hajimeo/private-repo
    local _org_name="${2}"
    local _token="${3:-"${GITHUB_TOKEN}"}"
    local _provider="${4:-"github"}"
    local _branch="${5:-"main"}"
    [ -z "${_org_name}" ] && _org_name="${_provider}_org"

    #echo "Current SCM configuration:"
    #_curl "${_IQ_URL%/}/api/v2/config/sourceControl" | python -m json.tool
    #sleep 2

    # Automatic Source Control Configuration
    _apiS "/rest/config/automaticScmConfiguration" '{"enabled":true}' "PUT" &>/dev/null
    local _org_int_id
    if [ -n "${_org_name}" ]; then
        # Check if org exist, and if not, create
        _org_int_id="$(f_api_orgId "${_org_name}" "Y")"
        [ -n "${_org_int_id}" ] || return 11
        # If would like to enable automatic application
        #_apiS "/rest/config/automaticApplications" '{"enabled":true,"parentOrganizationId":"'${_org_int_id}'"}' "PUT" || return $?
    else
        _org_name="Root Organization"
        _org_int_id="ROOT_ORGANIZATION_ID"
    fi
    if [ -z "${_token}" ]; then
        _log "WARN" "No token specified. Please specify _token or GITHUB_TOKEN."
        return 1
    fi
    # https://help.sonatype.com/iqserver/automating/rest-apis/source-control-rest-api---v2
    # NOTE: It seems the remediationPullRequestsEnabled is false for default
    echo 'Setting "remediationPullRequestsEnabled":true,"statusChecksEnabled":true,"pullRequestCommentingEnabled":true,"sourceControlEvaluationsEnabled":true ...'
    _curl "${_IQ_URL%/}/api/v2/sourceControl/organization/${_org_int_id}" -H "Content-Type: application/json" -d '{"token":"'${_token}'","provider":"'${_provider}'","baseBranch":"'${_branch}'","remediationPullRequestsEnabled":true,"statusChecksEnabled":true,"pullRequestCommentingEnabled":true,"sourceControlEvaluationsEnabled":true}' &> /tmp/${FUNCNAME[0]}_$$.tmp #|| return $?
    # 400 SourceControl already exists for organization with id: ...

    if [ "${_git_url}" ]; then
        local _app_pub_id="$(basename "${_git_url}")"
        f_api_create_app "${_app_pub_id}" "${_org_name}" &>/dev/null
        local _app_int_id="$(f_api_appIntId "${_app_pub_id}" "${_org_name}")" || return $?
        [ -n "${_app_int_id}" ] || return 12
        _curl "${_IQ_URL%/}/api/v2/sourceControl/application/${_app_int_id}" -H "Content-Type: application/json" -d '{"remediationPullRequestsEnabled":true,"statusChecksEnabled":true,"pullRequestCommentingEnabled":true,"sourceControlEvaluationsEnabled":true,"baseBranch":"'${_branch}'","repositoryUrl":"'${_git_url}'"}' | python -m json.tool #|| return $?
        # 400 SourceControl already exists for application with id: ...
        echo "TODO: If application is manually created like this, may need to scan this repository with 'source' stage"
    fi
}

### Integration setup related ###
function f_setup_ldap_freeipa() {
    local __doc__="Setup LDAP. Currently using my freeIPA server."
    local _name="${1:-"freeIPA"}"
    local _ldap_host="${2:-"dh1.standalone.localdomain"}"
    local _ldap_port="${3:-"389"}"
    [ -z "${_LDAP_PWD}" ] && echo "Missing _LDAP_PWD" && return 1
    local _id="$(_apiS "/rest/config/ldap" '{"id":null,"name":"'${_name}'"}' | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a['id'])")" || return $?
    [ -z "${_id}" ] && return 111
    _apiS "/rest/config/ldap/${_id}/connection" '{"id":null,"serverId":"'${_id}'","protocol":"LDAP","hostname":"'${_ldap_host}'","port":'${_ldap_port}',"searchBase":"cn=accounts,dc=standalone,dc=localdomain","authenticationMethod":"SIMPLE","saslRealm":null,"systemUsername":"uid=admin,cn=users,cn=accounts,dc=standalone,dc=localdomain","systemPassword":"'${_LDAP_PWD}'","connectionTimeout":30,"retryDelay":30}' "PUT" | python -m json.tool || return $?
    _apiS "/rest/config/ldap/${_id}/userMapping" '{"id":null,"serverId":"'${_id}'","userBaseDN":"cn=users","userSubtree":true,"userObjectClass":"person","userFilter":"","userIDAttribute":"uid","userRealNameAttribute":"cn","userEmailAttribute":"mail","userPasswordAttribute":"","groupMappingType":"DYNAMIC","groupBaseDN":"","groupSubtree":false,"groupObjectClass":null,"groupIDAttribute":null,"groupMemberAttribute":null,"groupMemberFormat":null,"userMemberOfGroupAttribute":"memberOf","dynamicGroupSearchEnabled":true}' "PUT" | python -m json.tool
}

function f_setup_scm_for_bitbucket() {
    echo "docker run -v /var/tmp/share/bitbucket:/var/atlassian/application-data/bitbucket --name=bitbucket -d -p 7990:7990 -p 7999:7999 atlassian/bitbucket"
    cat << 'EOF'
1. Setup Bitbucket
    mkdir -p -m 777 /var/tmp/share/bitbucket
    docker run -v /var/tmp/share/bitbucket:/var/atlassian/application-data/bitbucket \
        --name=bitbucket -d -p 7990:7990 -p 7999:7999 atlassian/bitbucket:8.9.8
    # Or use _setup_host.sh, f_bitbucket
2. Create a Project and a Repository
3. Create an access token 'http://localhost:7990/plugins/servlet/access-tokens/users/${_user}/manage'
    Write for Repository (read for Project)
4. Setup IQ SCM for Bitbucket-DC, then import this test-repo
5. Add something
    #git config --global user.name "${_user}"
    #git config --global user.email "${_user_email}"
    git clone http://${_user}:${_pwd}@localhost:7990/scm/test/test-repo.git
    cd test-repo
    git fetch; git pull
    # add something (eg: f_gen_npm_dummy_meta)
    git add --all
    git commit -m "Initial Commit"
    git push
EOF
}

function f_scan_maven_demo() {
    if [ ! -s "maven-policy-demo-1.1.0.jar" ]; then
        curl -sSf -O "https://repo1.maven.org/maven2/org/sonatype/maven-policy-demo/1.1.0/maven-policy-demo-1.1.0.jar" || return $?
    fi
    echo "Please scan ./maven-policy-demo-1.1.0.jar"
}

function f_gen_npm_dummy_meta() {
    local _name="${1:-"lodash-vulnerable"}"
    local _ver="${2:-"1.0.0"}"
    # "jsonwebtoken": "^0.4.0"
    cat << EOF > ./package.json
{
  "name": "${_name}",
  "version": "${_ver}",
  "description": "",
  "main": "index.js",
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 0"
  },
  "keywords": [],
  "author": "",
  "dependencies" : {
    "lodash": "4.17.4",
    "on-finished": "2.3.0"
  },
  "license": "ISC"
}
EOF
    echo "npm install --package-lock-only" >&2
    cat << EOF > ./package-lock.json
{
  "name": "${_name}",
  "version": "${_ver}",
  "lockfileVersion": 2,
  "requires": true,
  "packages": {
    "": {
      "version": "1.0.0",
      "license": "ISC",
      "dependencies": {
        "lodash": "4.17.4",
        "on-finished": "2.3.0"
      }
    },
    "node_modules/ee-first": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/ee-first/-/ee-first-1.1.1.tgz",
      "integrity": "sha512-WMwm9LhRUo+WUaRN+vRuETqG89IgZphVSNkdFgeb6sS/E4OrDIN7t48CAewSHXc6C8lefD8KKfr5vY61brQlow=="
    },
    "node_modules/lodash": {
      "version": "4.17.4",
      "resolved": "https://registry.npmjs.org/lodash/-/lodash-4.17.4.tgz",
      "integrity": "sha512-6X37Sq9KCpLSXEh8uM12AKYlviHPNNk4RxiGBn4cmKGJinbXBneWIV7iE/nXkM928O7ytHcHb6+X6Svl0f4hXg=="
    },
    "node_modules/on-finished": {
      "version": "2.3.0",
      "resolved": "https://registry.npmjs.org/on-finished/-/on-finished-2.3.0.tgz",
      "integrity": "sha512-ikqdkGAAyf/X/gPhXGvfgAytDZtDbr+bkNUJ0N9h5MI/dmdgCs3l6hoHrcUv41sRKew3jIwrp4qQDXiK99Utww==",
      "dependencies": {
        "ee-first": "1.1.1"
      },
      "engines": {
        "node": ">= 0.8"
      }
    }
  },
  "dependencies": {
    "ee-first": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/ee-first/-/ee-first-1.1.1.tgz",
      "integrity": "sha512-WMwm9LhRUo+WUaRN+vRuETqG89IgZphVSNkdFgeb6sS/E4OrDIN7t48CAewSHXc6C8lefD8KKfr5vY61brQlow=="
    },
    "lodash": {
      "version": "4.17.4",
      "resolved": "https://registry.npmjs.org/lodash/-/lodash-4.17.4.tgz",
      "integrity": "sha512-6X37Sq9KCpLSXEh8uM12AKYlviHPNNk4RxiGBn4cmKGJinbXBneWIV7iE/nXkM928O7ytHcHb6+X6Svl0f4hXg=="
    },
    "on-finished": {
      "version": "2.3.0",
      "resolved": "https://registry.npmjs.org/on-finished/-/on-finished-2.3.0.tgz",
      "integrity": "sha512-ikqdkGAAyf/X/gPhXGvfgAytDZtDbr+bkNUJ0N9h5MI/dmdgCs3l6hoHrcUv41sRKew3jIwrp4qQDXiK99Utww==",
      "requires": {
        "ee-first": "1.1.1"
      }
    }
  }
}
EOF
    echo "Please scan ./package-lock.json and ./package.json"
}

function _apiS() {
    local _path="${1}"
    local _data="${2}"
    local _method="${3}"
    local _iq_url="${4:-"${_IQ_URL%/}"}"
    local _c="${_TMP%/}/.nxiq_c_$$"
    find ${_TMP%/}/ -type f -name .nxiq_c_$$ -mmin +10 -delete 2>/dev/null
    if [ ! -s "${_c}" ]; then
        _curl -b ${_c} -c ${_c} -o /dev/null "${_iq_url%/}/rest/user/session" || return $?
    fi
    [ -n "${_data}" ] && [ -z "${_method}" ] && _method="POST"
    [ -z "${_method}" ] && _method="GET"
    local _cmd="curl -sSf -u '${_ADMIN_USER}:${_ADMIN_PWD}' -b ${_c} -c ${_c} -H 'X-CSRF-TOKEN: $(_sed -nr 's/.+\sCLM-CSRF-TOKEN\s+([0-9a-f]+)/\1/p' ${_c})' '${_iq_url%/}${_path}' -X ${_method}"
    if [ "${_data:0:5}" == "file=" ]; then
        _cmd="${_cmd} -F ${_data}"
    elif [ -n "${_data}" ] && [ "${_data:0:1}" != "{" ]; then
        _cmd="${_cmd} -H 'Content-Type: text/plain' -d ${_data}"    # TODO: should use quotes?
    elif [ -n "${_data}" ]; then
        _cmd="${_cmd} -H 'Content-Type: application/json' -d '${_data}'"
    fi
    eval ${_cmd}
}

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
        echo "Starting IQ installation..." >&2
        _NEXUS_START="Y" f_install_iq || return $?
    fi
    if [ -z "${r_IQ_URL:-"${_IQ_URL}"}" ] || ! _wait_url "${r_IQ_URL:-"${_IQ_URL}"}"; then
        _log "ERROR" "${r_IQ_URL:-"${_IQ_URL}"} is unreachable"
        return 1
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