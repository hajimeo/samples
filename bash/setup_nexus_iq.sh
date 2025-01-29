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
type _import &>/dev/null || _import() {
    [ ! -s /tmp/${1} ] && curl -sf --compressed "${_DL_URL%/}/bash/$1" -o /tmp/${1}
    . /tmp/${1}
}

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
: ${_DOMAIN:=".standalone.localdomain"}
: ${_ADMIN_USER:="admin"}
: ${_ADMIN_PWD:="admin123"}
: ${_IQ_URL:="http://localhost:8070/"}
: ${_IQ_TEST_URL:="https://nxiqha-k8s${_DOMAIN}/"}
_TMP="/tmp" # for downloading/uploading assets
_DEBUG=false

# To upgrade (from ${_dirname}/): mv -f -v ./config.yml{,.tmp} && tar -xvf $HOME/.nexus_executable_cache/nexus-iq-server-1.183.0-01-bundle.tar.gz && cp -p -v ./config.yml{.tmp,}
function f_install_iq() {
    local __doc__="Install specific IQ version (to recreate sonatype-work and DB, _RECREATE_ALL=Y)"
    local _ver="${1}" # 'latest'
    local _dbname="${2}"
    local _dbusr="${3:-"nexus"}" # Specifying default as do not want to create many users/roles
    local _dbpwd="${4:-"${_dbusr}123"}"
    local _port="${5:-"${_IQ_INSTALL_PORT}"}" # If not specified, checking from 8070
    local _dirpath="${6}"                     # If not specified, create a new dir under current dir
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
    if [[ "${_RECREATE_ALL-"Y"}" =~ [yY] ]]; then
        if [ -d "${_dirpath%/}" ]; then
            _log "WARN" "Removing ${_dirpath%/} (to avoid set _RECREATE_ALL)"
            sleep 3
            rm -v -rf "${_dirpath%/}" || return $?
        fi
        _RECREATE_DB="Y"
    fi

    # This function sets _LICENSE_PATH
    local _tgz_ver="${_ver}"
    [[ "${_ver}" =~ ^1\.[0-9]+\.[0-9]+$ ]] && _tgz_ver="${_ver}-*"
    _prepare_install "${_dirpath}" "https://download.sonatype.com/clm/server/nexus-iq-server-${_tgz_ver}-bundle.tar.gz" || return $?
    local _license_path="${_LICENSE_PATH}"

    local _jar_file="$(find ${_dirpath%/} -maxdepth 2 -type f -name 'nexus-iq-server*.jar' 2>/dev/null | sort | tail -n1)"
    [ -z "${_jar_file}" ] && return 11
    local _cfg_file="$(find ${_dirpath%/} -maxdepth 2 -type f -name 'config.yml' 2>/dev/null | sort | tail -n1)"
    [ -z "${_cfg_file}" ] && return 12

    if [ ! -f "${_cfg_file}.orig" ]; then
        cp -p "${_cfg_file}" "${_cfg_file}.orig"
    fi
    # TODO: From v138, most of configs need to use API: https://help.sonatype.com/iqserver/automating/rest-apis/configuration-rest-api---v2
    grep -qE '^hdsUrl:' "${_cfg_file}" || echo -e "hdsUrl: https://clm-staging.sonatype.com/\n$(cat "${_cfg_file}")" >"${_cfg_file}"
    grep -qE '^licenseFile' "${_cfg_file}" || echo -e "licenseFile: ${_license_path%/}\n$(cat "${_cfg_file}")" >"${_cfg_file}"
    grep -qE '^\s*port: 8070' "${_cfg_file}" && sed -i.tmp 's/port: 8070/port: '${_port}'/g' "${_cfg_file}"
    grep -qE '^\s*port: 8071' "${_cfg_file}" && sed -i.tmp 's/port: 8071/port: '$((${_port} + 1))'/g' "${_cfg_file}"

    if [ -n "${_dbname}" ]; then
        # NOTE: currently assuming "database:" is the end of file
        cat <<EOF >${_cfg_file}
$(sed -n '/^database:/q;p' ${_cfg_file})
database:
  type: postgresql
  hostname: $(hostname -f)
  port: 5432
  name: ${_dbname}
  username: ${_dbusr}
  password: ${_dbpwd}
EOF
        _log "INFO" "Creating database with \"${_dbusr}\" \"********\" \"${_dbname}\" in localhost:5432"
        if ! _RECREATE_DB=${_RECREATE_DB} _postgresql_create_dbuser "${_dbusr}" "${_dbpwd}" "${_dbname}"; then
            _log "WARN" "Failed to create ${_dbusr} or ${_dbname}"
        fi
    fi

    [ ! -d "${_dirpath%/}/log" ] && mkdir -v -m 777 "${_dirpath%/}/log"
    if _isYes "${_starting}"; then
        echo "Starting with: java -jar ${_jar_file} server ${_cfg_file} >${_dirpath%/}/log/iq-server.out 2>${_dirpath%/}/log/iq-server.err &"
        sleep 3
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
    local _parent_org="${3:-"Root Organization"}"
    [ -z "${_org_name}" ] && return 11
    local _org_int_id="$(_curl "${_IQ_URL%/}/api/v2/organizations" --get --data-urlencode "organizationName=${_org_name}" | _sortjson | sed -nE 's/^            "id": "(.+)",$/\1/p')"
    if [ -z "${_org_int_id}" ] && [[ "${_create}" =~ ^[yY] ]]; then
        local _parent_org_id="$(_curl "${_IQ_URL%/}/api/v2/organizations" --get --data-urlencode "organizationName=${_parent_org}" | _sortjson | sed -nE 's/^            "id": "(.+)",$/\1/p')"
        if [ -z "${_parent_org_id}" ]; then
            if [ "${_parent_org}" == "Root Organization" ]; then
                _parent_org_id="ROOT_ORGANIZATION_ID"
            else
                _log "INFO" "Failed to find parent organization: ${_parent_org}"
                return 1
            fi
        fi
        _org_int_id="$(_curl "${_IQ_URL%/}/api/v2/organizations" -H "Content-Type: application/json" -d "{\"name\":\"${_org_name}\",\"parentOrganizationId\": \"${_parent_org_id}\"}" | JSON_SEARCH_KEY="id" _sortjson)"
    fi
    if [ -z "${_org_int_id}" ]; then
        _log "ERROR" "Failed to find or create organization: ${_org_name}"
        return 1
    fi
    echo "${_org_int_id}"
}

function f_api_appIntId() {
    local __doc__="Get application Internal ID from /api/v2/applications?publicId=\${_app_pub_id}"
    local _app_pub_id="${1}"
    if [ -n "${_app_pub_id}" ]; then
        _curl "${_IQ_URL%/}/api/v2/applications" --get --data-urlencode "publicId=${_app_pub_id}" | JSON_SEARCH_KEY="applications.id" _sortjson
    else
        _curl "${_IQ_URL%/}/api/v2/applications" | JSON_SEARCH_KEY="applications" _sortjson | JSON_SEARCH_KEY="id,publicId" _sortjson
    fi
}

function f_api_create_app() {
    local __doc__="Create an application with /api/v2/applications"
    local _app_pub_id="${1}"
    local _create_under_org="${2:-"Sandbox Organization"}"
    if [ -z "${_app_pub_id}" ]; then
        _log "ERROR" "Application public ID is required."
        return 1
    fi
    local _org_int_id="$(f_api_orgId "${_create_under_org}" "Y")"
    [ -z "${_org_int_id}" ] && return 11
    local _app_int_id="$(f_api_appIntId "${_app_pub_id}")"
    if [ -n "${_app_int_id}" ]; then
        _log "INFO" "Not creating ${_app_pub_id} as it already exists."
        return 0
    fi
    _curl "${_IQ_URL%/}/api/v2/applications" -H "Content-Type: application/json" -d '{"publicId":"'${_app_pub_id}'","name": "'${_app_pub_id}'","organizationId": "'${_org_int_id}'"}'
}

function f_api_role_mapping() {
    local __doc__="map an external user/group to IQ organisation/application and role"
    local _role_name="$1"
    local _external_id="$2" # login username, LDAP/AD groupname etc.
    local _apporg_name="${3:-"Root Organization"}"
    local _user_or_group="${4:-"group"}"
    local _app_or_org="organization" # TODO: application is not supported yet
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
    local _int_id="$(_curl "${_IQ_URL%/}/api/v2/${_app_or_org}s" --get --data-urlencode "${_app_or_org}Name=${_apporg_name}" | python -c "import sys,json
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
    local _app_pub_id="${1:-"sandbox-application"}"
    local _gav="${2}"
    [[ "${_gav}" =~ ^" "*([^: ]+)" "*:" "*([^: ]+)" "*:" "*([^: ]+)" "*$ ]] || return 11
    local _g="${BASH_REMATCH[1]}"
    local _a="${BASH_REMATCH[2]}"
    local _v="${BASH_REMATCH[3]}"
    local _app_int_id="$(f_api_appIntId "${_app_pub_id}")" || return $?

    _curl "${_IQ_URL%/}/api/v2/evaluation/applications/${_app_int_id}" -H "Content-Type: application/json" -d '{"components": [{"hash": null,"componentIdentifier": {"format": "maven","coordinates": {"artifactId": "'${_a}'","groupId": "'${_g}'","version": "'${_v}'","extension":"jar"}}}]}'
}

function f_api_eval_scm() {
    local __doc__="/api/v2/evaluation/applications/\${_app_int_id} with Maven GAV"
    local _app_pub_id="${1}"
    local _branch="${2}"
    local _stage="${3:-"source"}"
    local _app_int_id="$(f_api_appIntId "${_app_pub_id}")" || return $?
    _curl "${_IQ_URL%/}/api/v2/evaluation/applications/${_app_int_id}/sourceControlEvaluation" -H "Content-Type: application/json" -d '{"stageId":"'${_stage}'","branchName":"'${_branch}'"}' | _sortjson
}

function f_api_audit() {
    local __doc__="/api/v2/auditLogs?startUtcDate=&endUtcDate="
    local _startUtcDate="${1}"
    local _endUtcDate="${2}"
    local _saveTo="${3}"
    [ -z "${_startUtcDate}" ] && _startUtcDate="$(date -u "+%Y-%m-%d")"
    [ -z "${_endUtcDate}" ] && _endUtcDate="$(date -u "+%Y-%m-%d")"
    [ -z "${_saveTo}" ] && _saveTo="./audit-${_startUtcDate}.log"
    _curl "${_IQ_URL%/}/api/v2/auditLogs?startUtcDate=${_startUtcDate}&endUtcDate=${_endUtcDate}" -o "${_saveTo}"
}

function f_api_report_success() {
    local __doc__="API to get Success Metrics *Weekly* report from /api/v2/reports/metrics"
    local _first_date_str="${1:-"1 week ago"}"
    local _last_date_str="${2:-"1 week ago"}"
    # Require gnu date
    local _date="date"
    if [ -n "$(type -P gdate)" ]; then
        _date="gdate"
    fi
    local _firstTimePeriod="$(eval "${_date} -d \"${_first_date_str}\" \"+%G-W%V\"")"
    local _lastTimePeriod="$(eval "${_date} -d \"${_last_date_str}\" \"+%G-W%V\"")"
    # -H "Accept: text/csv" for generating the report in CSV format
    _curl "${_IQ_URL%/}/api/v2/reports/metrics" -d "{\"timePeriod\":\"WEEK\",\"firstTimePeriod\":\"${_firstTimePeriod}\",\"lastTimePeriod\":\"${_lastTimePeriod}\",\"applicationIds\":[],\"organizationIds\":[]}"
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
    f_api_config '{"hdsUrl":"https://clm.sonatype.com/"}'
    #f_api_config '{"hdsUrl":"https://clm-staging.sonatype.com/"}'
    f_api_config '{"enableDefaultPasswordWarning":false}'
    f_api_config '{"sessionTimeout":120}' # between 3 and 120
    #f_api_config "" "/features/internalFirewallOnboardingEnabled" "POST"  # to enable
    f_api_config "" "/features/internalFirewallOnboardingEnabled" "DELETE" &>/dev/null # this one can return 400
    #curl -u "admin:admin123" "${_IQ_URL%/}/api/v2/config/features/internalFirewallOnboardingEnabled" -X DELETE #POST
}

function f_add_testuser() {
    local __doc__="Add/Create a test IQ user with test-role"
    local _username="${1:-"testuser"}"
    local _password="${2:-"${_username}123"}"
    local _apporg_name="${3:-"Root Organization"}"
    _apiS "/rest/user" '{"firstName":"'${_username}'","lastName":"test","email":"'${_username}'@example.com","username":"'${_username}'","password":"'${_password}'"}'
    _apiS "/rest/security/roles" '{"name":"test-role","description":"test_role_desc","builtIn":false,"permissionCategories":[{"displayName":"Administrator","permissions":[{"id":"VIEW_ROLES","displayName":"View","description":"All Roles","allowed":false}]},{"displayName":"IQ","permissions":[{"id":"MANAGE_PROPRIETARY","displayName":"Edit","description":"Proprietary Components","allowed":false},{"id":"CLAIM_COMPONENT","displayName":"Claim","description":"Components","allowed":false},{"id":"WRITE","displayName":"Edit","description":"IQ Elements","allowed":false},{"id":"READ","displayName":"View","description":"IQ Elements","allowed":true},{"id":"EDIT_ACCESS_CONTROL","displayName":"Edit","description":"Access Control","allowed":false},{"id":"EVALUATE_APPLICATION","displayName":"Evaluate","description":"Applications","allowed":true},{"id":"EVALUATE_COMPONENT","displayName":"Evaluate","description":"Individual Components","allowed":true},{"id":"ADD_APPLICATION","displayName":"Add","description":"Applications","allowed":false},{"id":"MANAGE_AUTOMATIC_APPLICATION_CREATION","displayName":"Manage","description":"Automatic Application Creation","allowed":false},{"id":"MANAGE_AUTOMATIC_SCM_CONFIGURATION","displayName":"Manage","description":"Automatic Source Control Configuration","allowed":false}]},{"displayName":"Remediation","permissions":[{"id":"WAIVE_POLICY_VIOLATIONS","displayName":"Waive","description":"Policy Violations","allowed":true},{"id":"CHANGE_LICENSES","displayName":"Change","description":"Licenses","allowed":false},{"id":"CHANGE_SECURITY_VULNERABILITIES","displayName":"Change","description":"Security Vulnerabilities","allowed":false},{"id":"LEGAL_REVIEWER","displayName":"Review","description":"Legal obligations for components licenses","allowed":false}]}]}' || return $?
    # Some times no root organization
    f_api_role_mapping "test-role" "testuser" "${_apporg_name}" "user"
}

function f_setup_https() {
    local __doc__="Modify config files to enable SSL/TLS/HTTPS"
    # https://guides.sonatype.com/iqserver/technical-guides/iq-secure-connections/
    local _p12="${1}" # If empty, will use *.standalone.localdomain cert.
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
        _log "INFO" "${_p12} exits. reusing ..."
        sleep 1
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
        _log "INFO" "Using '${_alias}' as alias name..."
        sleep 1
    fi

    _log "INFO" "Updating ${_cfg_file} ..."
    if [ ! -s ${_cfg_file}.orig ]; then
        cp -p ${_cfg_file} ${_cfg_file}.orig || return $?
    fi
    if grep -qE '^\s*-\s*type:\s*https' ${_cfg_file}; then
        _log "ERROR" "Looks like https is already configured."
        return 1
    fi
    # Need to escape '/' in the path
    local _workdir_escaped="$(echo "${_base_dir%/}/sonatype-work/clm-server" | _sed 's@[/]@\\/@g')"
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

function f_setup_saml_simplesaml() {
    local __doc__="Setup SAML for SimpleSAML server."
    local _name="${1:-"simplesaml"}"
    local _idp_metadata="${2:-"${_TMP%/}/idp_metadata.xml"}"
    local _host="${3:-"localhost"}"
    local _port="${4:-"2080"}"
    # Check if it's already setup
    _curl "${_IQ_URL%/}/api/v2/config/saml" 2>/dev/null
    if [ $? -eq 0 ]; then
        _log "INFO" "SAML is already setup."
        return 0
    fi
    if [ ! -s "${_idp_metadata}" ]; then
        _log "ERROR" "Missing IDP metadata file (_idp_metadata): ${_idp_metadata}"
        return 1
    fi
    if ! _curl "${_IQ_URL%/}/api/v2/config/saml" -X PUT -F identityProviderXml=@${_idp_metadata} -F samlConfiguration="{\"identityProviderName\":\"${_name}\",\"entityId\":\"${_IQ_URL%/}/api/v2/config/saml/metadata\",\"usernameAttributeName\":\"uid\",\"firstNameAttributeName\":\"givenName\",\"lastNameAttributeName\":\"sn\",\"emailAttributeName\":\"eduPersonPrincipalName\",\"groupsAttributeName\":\"eduPersonAffiliation\",\"validateResponseSignature\":false,\"validateAssertionSignature\":false}"; then
        echo "If SAML is already configured, please try 'DELETE /api/v2/config/saml' first."
        return 1
    fi
}

# NOTE: Use the setup_nexus3_repo.sh:f_start_ldap_server() to start GLAuth
#_LDAP_GROUP_MAPPING_TYPE="STATIC" f_setup_ldap_glauth     # For STATIC group mapping
function f_setup_ldap_glauth() {
    local __doc__="Setup LDAP for GLAuth server."
    local _name="${1:-"glauth"}"
    local _host="${2:-"localhost"}"
    local _port="${3:-"389"}" # 636
    #[ -z "${_LDAP_PWD}" ] && _log "WARN" "Missing _LDAP_PWD" && sleep 3
    local _server_id="$(_apiS "/rest/config/ldap" | JSON_SEARCH_KEY="id,name" _sortjson | sed -nE 's/([^,]+),'${_name}'$/\1/p')"
    local _um_id="null"
    if [ -z "${_server_id}" ]; then
        _server_id="$(_apiS "/rest/config/ldap" '{"id":null,"name":"'${_name}'"}' | JSON_SEARCH_KEY="id" _sortjson)" || return $?
        [ -z "${_server_id}" ] && return 111
        #nc -z ${_host} ${_port} || return $?
        _apiS "/rest/config/ldap/${_server_id}/connection" '{"id":null,"serverId":"'${_server_id}'","protocol":"LDAP","hostname":"'${_host}'","port":'${_port}',"searchBase":"dc=standalone,dc=localdomain","authenticationMethod":"SIMPLE","saslRealm":null,"systemUsername":"admin@standalone.localdomain","systemPassword":"'${_LDAP_PWD:-"secret12"}'","connectionTimeout":30,"retryDelay":30}' "PUT" | _sortjson || return $?
    else
        _um_id="\"$(_apiS "/rest/config/ldap/${_server_id}/userMapping" | JSON_SEARCH_KEY="id" _sortjson)\""
    fi

    # userFilter="ou=ipausers"
    if [ "${_LDAP_GROUP_MAPPING_TYPE}" == "STATIC" ]; then
        _apiS "/rest/config/ldap/${_server_id}/userMapping" '{"id":'${_um_id}',"serverId":"'${_server_id}'","userBaseDN":"ou=users","userObjectClass":"posixAccount","userFilter":"","userIDAttribute":"uid","userRealNameAttribute":"cn","userEmailAttribute":"mail","userPasswordAttribute":"","groupBaseDN":"ou=users","groupObjectClass":"posixGroup","groupIDAttribute":"cn","groupMemberAttribute":"memberUid","groupMemberFormat":"${username}","userMemberOfGroupAttribute":"memberOf","groupMappingType":"STATIC","userSubtree":true,"groupSubtree":true,"dynamicGroupSearchEnabled":true}' "PUT"
    else
        _apiS "/rest/config/ldap/${_server_id}/userMapping" '{"id":'${_um_id}',"serverId":"'${_server_id}'","userBaseDN":"ou=users","userSubtree":true,"userObjectClass":"posixAccount","userFilter":"","userIDAttribute":"uid","userRealNameAttribute":"cn","userEmailAttribute":"mail","userPasswordAttribute":"","groupMappingType":"DYNAMIC","groupBaseDN":"","groupSubtree":true,"groupObjectClass":null,"groupIDAttribute":null,"groupMemberAttribute":null,"groupMemberFormat":null,"userMemberOfGroupAttribute":"memberOf","dynamicGroupSearchEnabled":true}' "PUT"
    fi | _sortjson || return $?
    # Dynamic/Static use admin to check if the user exists
    echo "To test group mappings (space may need to be changed to %20):"
    echo "    curl -v -u \"cn=ldapadmin,dc=standalone,dc=localdomain\" -k \"ldap://${_host:-"localhost"}:${_port:-"389"}/ou=users,dc=standalone,dc=localdomain?dn,cn,mail,memberof?sub?(&(objectClass=posixAccount)(uid=ldapuser))\"" # + userFilter
    # echo "To test: LDAPTLS_REQCERT=never ldapsearch -H ldap://${_host}:${_port} -b 'dc=standalone,dc=localdomain' -D 'admin@standalone.localdomain' -w '${_LDAP_PWD:-"secret12"}' -s sub '(&(objectClass=posixAccount)(uid=*))'"
    # TODO: Bind request: curl -v -u "cn=ldapuser,ou=ipausers,ou=users,dc=standalone,dc=localdomain:ldapuser" -k "ldap://${_host:-"localhost"}:${_port:-"389"}/dc=standalone,dc=localdomain""   # + userFilter
    if [ "${_LDAP_GROUP_MAPPING_TYPE}" == "STATIC" ]; then
        # groupIDAttribute is returned
        echo "    curl -v -u \"cn=ldapadmin,dc=standalone,dc=localdomain\" -k \"ldap://${_host:-"localhost"}:${_port:-"389"}/ou=users,dc=standalone,dc=localdomain?cn?sub?(&(objectClass=posixGroup)(cn=*)(memberUid=ldapuser))\"" # + userFilter
    fi
    echo "To start glauth, execute f_start_ldap_server from setup_nexus3_repo.sh"
}

function f_deprecated_setup_ldap_freeipa() {
    local __doc__="Deprecated: Setup LDAP with freeIPA server"
    local _name="${1:-"freeIPA"}"
    local _host="${2:-"dh1.standalone.localdomain"}"
    local _port="${3:-"389"}"
    [ -z "${_LDAP_PWD}" ] && echo "Missing _LDAP_PWD" && return 1
    local _id="$(_apiS "/rest/config/ldap" '{"id":null,"name":"'${_name}'"}' | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a['id'])")" || return $?
    [ -z "${_id}" ] && return 111
    _apiS "/rest/config/ldap/${_id}/connection" '{"id":null,"serverId":"'${_id}'","protocol":"LDAP","hostname":"'${_host}'","port":'${_port}',"searchBase":"cn=accounts,dc=standalone,dc=localdomain","authenticationMethod":"SIMPLE","saslRealm":null,"systemUsername":"uid=admin,cn=users,cn=accounts,dc=standalone,dc=localdomain","systemPassword":"'${_LDAP_PWD}'","connectionTimeout":30,"retryDelay":30}' "PUT" | python -m json.tool || return $?
    _apiS "/rest/config/ldap/${_id}/userMapping" '{"id":null,"serverId":"'${_id}'","userBaseDN":"cn=users","userSubtree":true,"userObjectClass":"person","userFilter":"","userIDAttribute":"uid","userRealNameAttribute":"cn","userEmailAttribute":"mail","userPasswordAttribute":"","groupMappingType":"DYNAMIC","groupBaseDN":"","groupSubtree":false,"groupObjectClass":null,"groupIDAttribute":null,"groupMemberAttribute":null,"groupMemberFormat":null,"userMemberOfGroupAttribute":"memberOf","dynamicGroupSearchEnabled":true}' "PUT" | python -m json.tool
}

function f_setup_webhook() {
    local __doc__="Setup Webhook for IQ"
    local _url="${1}"
    local _name="${2:-"webhook-test"}"
    [ -z "${_url}" ] && return 11
    _apiS "/rest/config/webhook" "{\"eventTypes\":[\"Application Evaluation\",\"License Override Management\",\"Organization and Application Management\",\"Policy Management\",\"Security Vulnerability Override Management\",\"Violation Alert\",\"Waiver Request\"],\"url\":\"${_url}\",\"description\":\"${_name}\",\"secretKey\":\"\"}" || return $?
    echo ""
    if [[ "${_url}" =~ ^http://localhost:([0-9]+) ]]; then
        _log "INFO" "To test: nc -v -v -n -l ${BASH_REMATCH[1]}"
    fi
    _log "NOTE" "webhook uses HTTP proxy configured in IQ."
}

### Integration setup related ###

# NOTE: Do not forget export _IQ_GIT_TOKEN or GIT_TOKEN:
#   export _IQ_GIT_TOKEN="*******************"
# To setup Org only: f_setup_scm   # this will create 'github-org' with token
# To setup Org&app for github: f_setup_scm "github-org" "https://github.com/hajimeo/private-repo2"
# To setup Org&app for gitlab: f_setup_scm "gitlab-org" "https://gitlab.com/emijah/private-repo.git" "gitlab" "master"
# To setup Org&app for azure : f_setup_scm "azdevop-org" "https://dev.azure.com/hosako/_git/private-repo" "azure" "master"
#
### Another way with Automatic Application Creation and Automatic Source Control Configuration
# - Setup an IQ organization's SCM configuration (which is specified in the Automatic Application Creation)
# - Create a git repository with just pom.xml file, and push to "main" branch
# - Modify the pom.xml to add a vulnerable dependency, and push to a new branch (eg. "vul-branch"), then create a PR
# - Scan the "main" branch with "build" stage
#   export _IQ_URL="$_IQ_SAAS_URL" _IQ_CRED="$_IQ_SAAS_USER:$_IQ_SAAS_PWD"
#   export GIT_URL="https://hajimeo:${_IQ_GIT_TOKEN}@github.com/hajimeo/private-repo2"
#   _IQ_CLI_VER="1.183.0-01" _IQ_APP_ID="private-repo2" _IQ_STAGE="build" f_cli
# - Switch to the new branch, then scan with "develop" stage
#   _IQ_CLI_VER="1.183.0-01" _IQ_APP_ID="private-repo2" _IQ_STAGE="develop" f_cli
#
# Not so useful, but to check the result:
#    f_api_audit    # but it contains only `"domain":"governance.evaluation.application","type":"evaluate" ... "stageId":"develop"'
function f_setup_scm() {
    local __doc__="Setup IQ SCM on the Organisation and app if _git_url is specified"
    local _org_name="${1}"
    local _git_url="${2}" # https://github.com/sonatype/support-apac-scm-test https://github.com/hajimeo/private-repo
    local _provider="${3:-"github"}"
    local _branch="${4:-"main"}"
    local _username="${5}"
    local _token="${6:-"${_IQ_GIT_TOKEN:-"${GIT_TOKEN}"}"}"
    local _parent_org="${7:-"${_IQ_PARENT_ORG}"}"
    [ -z "${_org_name}" ] && _org_name="${_provider:-"scmtest"}-org"
    if [ -z "${_username}" ]; then
        if [[ "${_provider}" =~ ^(azure|bitbucket)$ ]]; then
            _username="${_IQ_GIT_USER:-"${GIT_USER}"}"
        fi
        _username="${_IQ_GIT_USER:-"${GIT_USER}"}"
        [ -z "${_username}" ] && _username="${_IQ_GIT_USER:-"${GIT_USER}"}"
    fi

    # Automatic Source Control Configuration. It's OK if fails
    _log "INFO" "Enabling Automatic Source Control Configuration ..."
    _apiS "/rest/config/automaticScmConfiguration" '{"enabled":true}' "PUT"

    # Check if org exist, and if not, create
    local _org_int_id="$(f_api_orgId "${_org_name}" "Y")"
    [ -n "${_org_int_id}" ] || return 11
    # If would like to enable automatic application
    #_apiS "/rest/config/automaticApplications" '{"enabled":true,"parentOrganizationId":"'${_org_int_id}'"}' "PUT" || return $?

    local _parent_org_int_id
    if [ -n "${_parent_org}" ]; then
        _parent_org_int_id="$(f_api_orgId "${_parent_org}" "Y")"
        [ -n "${_parent_org_int_id}" ] || return 11
    else
        _parent_org="Root Organization"
        _parent_org_int_id="ROOT_ORGANIZATION_ID"
    fi

    local _existing_config="$(_curl "${_IQ_URL%/}/api/v2/sourceControl/organization/${_org_int_id}" 2>/dev/null)"
    if [ -n "${_existing_config}" ]; then
        _log "INFO" "SourceControl already exists for organization ${_org_name}:${_org_int_id}"
        echo "${_existing_config}" | _sortjson
    else
        if [ -z "${_token}" ]; then # and provider and default branch are required
            _log "ERROR" "No token specified. Please specify _token or _IQ_GIT_TOKEN or GITHUB_TOKEN."
            return 1
        fi

        # https://help.sonatype.com/iqserver/automating/rest-apis/source-control-rest-api---v2
        # NOTE: It seems the remediationPullRequestsEnabled is false for default (if null UI may not show as Inherited)
        #       Also, do we need to set "sshEnabled" to false?
        _log "INFO" 'Configuring organization: '${_org_int_id}' with "token":"********","provider":"'${_provider}'","baseBranch":"'${_branch}' ...'
        _curl "${_IQ_URL%/}/api/v2/sourceControl/organization/${_org_int_id}" -H "Content-Type: application/json" -d '{"token":"'${_token}'","provider":"'${_provider}'","baseBranch":"'${_branch}'","remediationPullRequestsEnabled":true,"statusChecksEnabled":true,"pullRequestCommentingEnabled":true,"sourceControlEvaluationsEnabled":true,"sshEnabled":false}' || return $?
    fi

    if [ "${_git_url}" ]; then
        local _app_pub_id="$(basename "${_git_url}")"
        f_api_create_app "${_app_pub_id}" "${_org_name}" &>/dev/null
        local _app_int_id="$(f_api_appIntId "${_app_pub_id}" "${_org_name}")" || return $?
        [ -n "${_app_int_id}" ] || return 12

        local _existing_config="$(_curl "${_IQ_URL%/}/api/v2/sourceControl/application/${_app_int_id}" 2>/dev/null)"
        if [ -n "${_existing_config}" ]; then
            _log "INFO" "SourceControl already exists for application ${_app_pub_id}:${_app_int_id}"
            echo "${_existing_config}" | _sortjson
            return 0
        fi

        _curl "${_IQ_URL%/}/api/v2/sourceControl/application/${_app_int_id}" -H "Content-Type: application/json" -d '{"remediationPullRequestsEnabled":true,"statusChecksEnabled":true,"pullRequestCommentingEnabled":true,"sourceControlEvaluationsEnabled":true,"baseBranch":"'${_branch}'","repositoryUrl":"'${_git_url}'"}' | _sortjson || return $?

        _log "INFO" "If application is manually created, may need to scan the repository with 'source' stage (but may not work due to CLM-20570)"
        echo "    f_api_eval_scm \"${_app_pub_id}\" \"${_branch}\" \"source\""
        echo "NOTE: Form Maven, if scanner detects a. jar file, pom.xml is not utilised."
        echo "NOTE: if you face some strange SCM issue, try restarting IQ service or check 'git' config."
        #TODO: not sure if this is needed: curl -u admin:admin123 -sSf -X POST 'http://localhost:8070/api/v2/config/features/scan-pom-files-in-meta-inf-directory'
    fi
}

function f_setup_jenkins() {
    local __doc__="Setup Jenkins, with Docker if _JENKINS_USE_DOCKER=Y"
    # @see: https://abrahamntd.medium.com/automating-jenkins-setup-using-docker-and-jenkins-configuration-as-code-897e6640af9d
    local _plugin_ver="${1:-"3.20.6-01"}"
    local _jenkins_ver="${2:-"2.462.3"}"
    local _jenkins_home="${3:-"/var/tmp/share/jenkins_home"}"
    local _use_docker="${4:-"${_JENKINS_USE_DOCKER}"}"

    if [ ! -d "${_jenkins_home%/}" ]; then
        mkdir -v -p -m 777 "${_jenkins_home%/}/tmp" || return $?
        chmod 777 ${_jenkins_home} || return $?
    fi

    local _jave="java"
    if [ -n "${JAVA_HOME}" ]; then
        _java="${JAVA_HOME%/}/bin/java"
    fi
    if ! ${_java} -version 2>&1 | grep -q 'build 17.'; then
        _log "ERROR" "Java is not found or not 17. Please export JAVA_HOME to Java 17."
        return 1
    fi

    cat <<'EOF' >"${_jenkins_home%/}/jenkins-configuration.yaml"
jenkins:
 securityRealm:
  local:
   allowsSignup: false
   users:
    — id: admin
     password: admin123
EOF
    if [[ "${_use_docker}" =~ ^[yY] ]]; then
        # Jenkins Docker could be a bit tedious to setup IQ because of the network setting in Docker
        _log "INFO" "Starting jenkins with Docker ..."
        docker run --rm -d -p 8080:8080 -p 50000:50000 -e JAVA_OPTS="-Djenkins.install.runSetupWizard=false" -e CASC_JENKINS_CONFIG="/var/jenkins_home/jenkins-configuration.yaml" -v ${_jenkins_home}:/var/jenkins_home --name=jenkins jenkins/jenkins:lts-jdk17 || return $?
        # If password is not set: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
    else
        if [ ! -s "${_jenkins_home%/}/tmp/jenkins-${_jenkins_ver}.war" ]; then
            _log "INFO" "Downloading jenkins.war (${_jenkins_ver}) ..."
            curl -Sf -o "${_jenkins_home%/}/tmp/jenkins-${_jenkins_ver}.war" -L "https://get.jenkins.io/war-stable/${_jenkins_ver}/jenkins.war" || return $?
        fi
        export JENKINS_HOME="${_jenkins_home%/}" CASC_JENKINS_CONFIG="${_jenkins_home%/}/jenkins-configuration.yaml"
        #-Djava.util.logging.config.file=$HOME/Apps/jenkins-logging.properties
        eval "${_java} -Djenkins.install.runSetupWizard=false -jar ${_jenkins_home%/}/tmp/jenkins-${_jenkins_ver}.war &> /tmp/jenkins.log &"
    fi

    # NOTE: Creating ${_jenkins_home%/}/plugins and copying .hpi may fail with "Plugin is missing" errors
    if [ ! -s "${_jenkins_home%/}/tmp/nexus-jenkins-plugin-${_plugin_ver}.hpi" ]; then
        _log "INFO" "Downloading nexus-jenkins-plugin-${_plugin_ver}.hpi ..."
        curl -Sf -o "${_jenkins_home%/}/tmp/nexus-jenkins-plugin-${_plugin_ver}.hpi" -L "https://download.sonatype.com/integrations/jenkins/nexus-jenkins-plugin-${_plugin_ver}.hpi" || return $?
    fi

    _log "INFO" "Waiting http://localhost:8080/ ..."
    if _wait_url "http://localhost:8080/" "30" "2"; then
        if grep -q -w "${_plugin_ver}" ${_jenkins_home%/}/plugins/nexus-jenkins-plugin/META-INF/MANIFEST.MF; then
            _log "INFO" "nexus-jenkins-plugin-${_plugin_ver}.hpi was probably installed in ${_jenkins_home%/}/plugins/nexus-jenkins-plugin/ ..."
        else
            curl -sSf -o "${_jenkins_home%/}/tmp/jenkins-cli.jar" -L http://localhost:8080/jnlpJars/jenkins-cli.jar || return $?
            _log "INFO" "Installing nexus-jenkins-plugin-${_plugin_ver}.hpi and dependencies ..."
            ${_java} -jar ${_jenkins_home%/}/tmp/jenkins-cli.jar -s http://localhost:8080/ -auth admin:admin123 install-plugin file://${_jenkins_home%/}/tmp/nexus-jenkins-plugin-${_plugin_ver}.hpi workflow-api plain-credentials structs credentials bouncycastle-api || return $?
            _log "INFO" "Restarting jenkins ..."
            if [[ "${_use_docker}" =~ ^[yY] ]]; then
                docker restart jenkins || return $?
            else
                ${_java} -jar ${_jenkins_home%/}/tmp/jenkins-cli.jar -s http://localhost:8080/ -auth admin:admin123 safe-restart || return $?
            fi
        fi
    fi

    _log "INFO" "Checking logs (press Ctrl+C if looks OK)..."
    if [[ "${_use_docker}" =~ ^[yY] ]]; then
        docker logs -f jenkins
    else
        tail -f /tmp/jenkins.log
    fi
    cat <<'EOF'
# To configure Nexus IQ Server (jenkins_home/org.sonatype.nexus.ci.config.GlobalNexusConfiguration.xml):
    http://localhost:8080/manage/configure
# To configure maven / java:
    http://localhost:8080/configureTools/

EOF
    jobs -l
}

function f_setup_gitlab() {
    local __doc__="Setup GitLab with Docker"
    local _hostname="${1:-"gitlab${_DOMAIN}"}"
    local _tag="${2:-"latest"}"
    local _port_pfx="${3-5900}"
    local _gitlab_home="${4:-"${HOME%/}/share/gitlab"}"
    # @see: https://docs.gitlab.com/ee/install/docker/installation.html#install-gitlab-by-using-docker-engine
    #docker pull gitlab/gitlab-ee:${_tag} || return $?
    if [ ! -d "${_gitlab_home}" ]; then
        mkdir -v -p ${_gitlab_home}/{config,logs,data} || return $?
        chmod -R 777 ${_gitlab_home} || return $?
    fi
    # nslookup does not use /etc/hosts
    if ! ping -c1 ${_hostname} &>/dev/null; then
        _log "WARN" "Please make sure ${_hostname} is resolvable."
        sleep 5
    fi
    # TODO: not completed
    docker run --detach \
        --privileged=true \
        --hostname "${_hostname}" \
        --env GITLAB_OMNIBUS_CONFIG="external_url='http://${_hostname}:$((_port_pfx + 80))';gitlab_rails['lfs_enabled']=true;gitlab_rails['initial_root_password']='${_ADMIN_PWD}'" \
        --publish $((_port_pfx + 443)):443 --publish $((_port_pfx + 80)):80 --publish $((_port_pfx + 22)):22 \
        --name gitlab \
        --restart always \
        --volume ${_gitlab_home}/config:/etc/gitlab:z \
        --volume ${_gitlab_home}/logs:/var/log/gitlab:z \
        --volume ${_gitlab_home}/data:/var/opt/gitlab:z \
        --shm-size 256m \
        gitlab/gitlab-ee:${_tag} || return $?
    _log "INFO" "Please wait for a few minutes for GitLab to start. (http://${_hostname}:$((_port_pfx + 80)))"
}

function f_setup_bitbucket() {
    local __doc__="TODO: Setup Bitbucket with Docker"
    echo "docker run --rm -d -v /var/tmp/share/bitbucket:/var/atlassian/application-data/bitbucket -p 7990:7990 -p 7999:7999 --name=bitbucket atlassian/bitbucket"
    cat <<'EOF'
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

function f_prep_maven_jar_for_scan() {
    local __doc__="Download a demo jar file for Maven scan"
    local _ver="${1:-"1.1.0"}"
    local _remote_url="${2:-"https://repo1.maven.org/maven2/"}"
    local _tmpdir="$(mktemp -d)" || return $?
    cd "${_tmpdir}" || return $?
    if [ ! -s "./maven-policy-demo-${_ver}.jar" ]; then
        curl -sSf -O "${_remote_url%/}/org/sonatype/maven-policy-demo/${_ver}/maven-policy-demo-${_ver}.jar" || return $?
    fi
}

function f_prep_maven_pom_for_scan() {
    local __doc__="TODO: generate a pom.xml with dependencies for Maven scan"
    local _tmpdir="$(mktemp -d)" || return $?
    cd "${_tmpdir}" || return $?
    # https://help.sonatype.com/en/java-application-analysis.html#example--pom-xml
    # Does the pom.xml require `dependencyManagement`?
    cat <<'EOF' >./pom.xml
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
   <modelVersion>4.0.0</modelVersion>
   <groupId>org.example</groupId>
   <artifactId>ACME-Consumer</artifactId>
   <packaging>pom</packaging>
   <version>1.0-SNAPSHOT</version>
   <modules>
      <module>Consumer-Service</module>
      <module>Consumer-Data</module>
   </modules>
   <properties>
      <commons.version>2.6</commons.version>
   </properties>
   <dependencyManagement>
      <dependencies>
         <dependency>
            <groupId>commons-io</groupId>
            <artifactId>commons-io</artifactId>
            <version>${commons.version}</version>
         </dependency>
         <dependency>
            <groupId>org.example</groupId>
            <artifactId>ACME-data</artifactId>
            <version>1.0-SNAPSHOT</version>
         </dependency>
      </dependencies>
   </dependencyManagement>
</project>
EOF
}

#f_prep_dummy_npm_meta '{"@nestjs/cli": "^9.3.0"}'
function f_prep_npm_meta_for_scan() {
    local __doc__="Generate a dummy package.json for NPM scan"
    local _deps_json="${1:-"{\"lodash\":\"4.17.4\"}"}"
    local _remote_url="${2:-"https://registry.npmjs.org/"}"
    local _tmpdir="$(mktemp -d)" || return $?
    cd "${_tmpdir}" || return $?
    cat <<EOF >./package.json
{
  "name": "iq-npm-scan-demo",
  "version": "0.0.1",
  "description": "",
  "main": "index.js",
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 0"
  },
  "keywords": [],
  "author": "",
  "dependencies" : ${_deps_json},
  "license": "ISC"
}
EOF
    if type npm &>/dev/null; then
        npm install --package-lock-only --registry ${_remote_url%/} || return $?
        _log "INFO" "Please scan ./package-lock.json and ./package.json"
    else
        _log "INFO" "Please install npm and run 'npm install --package-lock-only'"
    fi
}

function f_prep_yum_meta_for_scan() {
    local _tmpdir="$(mktemp -d)" || return $?
    cd "${_tmpdir}" || return $?
    echo "expat.x86_64                   2.2.5-13.el8                 @nexusiq-test" >./yum-packages.txt
    echo "expat.x86_64                   2.5.0-2.el9                  @nexusiq-test" >>./yum-packages.txt
}

function f_prep_docker_image_for_scan() {
    local __doc__="TODO: Incomplete. Generate an image for docker scanning"
    local _base_img="${1:-"alpine:latest"}"    # dh1.standalone.localdomain:15000/alpine:3.7
    local _host_port="${2}"
    local _tag_to="${3:-"${_TAG_TO}"}"
    local _num_layers="${4:-"${_NUM_LAYERS:-"1"}"}" # Can be used to test overwriting image
    local _cmd="${6-"${r_DOCKER_CMD}"}"
    local _usr="${7:-"${_ADMIN_USER}"}"
    local _pwd="${8:-"${_ADMIN_PWD}"}"
    [ -z "${_cmd}" ] && _cmd="$(_docker_cmd)"
    [ -z "${_cmd}" ] && return 0    # If no docker command, just exist

    local _repo_tag="${_tag_to}"
    [ -n "${_host_port%/}" ] && _repo_tag="${_host_port%/}/${_tag_to}"
    if ${_cmd} images --format "{{.Repository}}:{{.Tag}}" | grep -qE "^${_repo_tag}$"; then
        _log "INFO" "'${_repo_tag}' already exists. Skipping the build ..."
        return
    fi

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
}

function f_prep_scan_target_for_proprietary_component() {
    local __doc__="As scan-<reportId>.xml.gz file can't be used for this test, generating a dummy jar file"
    local _path="${1:-"./"}"                # A/1/_work/8/s/all/target/some.class.com.all-1.0-SNAPSHOT.jar
    local _gen_file_name="${2:-"test.zip"}" # not a path
    local _dir="$(dirname "${_path}")"
    local _cwd="$(pwd)"
    local _tmpdir="$(mktemp -d)" || return $?
    cd "${_tmpdir}" || return $?
    # Not sure if mkdir is needed but just in case
    mkdir -v -p "${_dir#/}" || return $?
    _gen_dummy_jar "${_path#/}" || return $?
    zip -r "${_cwd%/}/${_gen_file_name}" . || return $?
    cd "${_cwd}" || return $?
}

function f_dummy_scans() {
    local __doc__="Generate dummy reports by scanning (dummy) scan targets against one application"
    local _scan_target="${1}"
    local _how_many="${2:-10}"
    #local _parallel="${3:-5}"  # Not used as can't scan in parallel for one application
    local _app_name="${3:-"sandbox-application"}"
    local _iq_stage="${4:-${_IQ_STAGE:-"build"}}" #develop|build|stage-release|release|operate
    local _create_under_org="${5-"${_CREATE_UNDER_ORG:-"Sandbox Organization"}"}"

    local _seq_start="${_SEQ_START:-1}"
    local _seq_end="$((_seq_start + _how_many - 1))"

    local _this_org_id=""
    if [ -n "${_create_under_org}" ]; then
        # Just in case, creating the base (under) organization
        _this_org_id="$(f_api_orgId "${_create_under_org}" "Y")"
        if [ -z "${_this_org_id}" ]; then
            _log "ERROR" "Failed to get the organization ID for '${_create_under_org}'"
            return 1
        fi
    fi
    # Just in case, creating the application
    f_api_create_app "${_app_name}" "${_this_org_id}" || return $?

    for i in $(eval "seq ${_seq_start} ${_seq_end}"); do
        local _this_scan_target="${_scan_target}"
        if [ -z "${_scan_target}" ]; then
            echo "test at $(date +'%Y-%m-%d %H:%M:%S')" > dummy.txt
            jar -cf ${_TMP%/}/dummy-${i}.jar dummy.txt || return $?
            rm -f dummy.txt
            _this_scan_target="${_TMP%/}/dummy-${i}.jar"
        fi

        _log "INFO" "Scanning for ${_app_name} against ${_this_scan_target} (${i}/${_seq_end}) ..."
        _SIMPLE_SCAN="Y" f_cli "${_this_scan_target}" "${_app_name}" "${_iq_stage}" || return $?

        if [ -z "${_scan_target}" ] && [ -s "${_this_scan_target}" ]; then
            rm -f "${_this_scan_target}"
        fi
    done
}

function f_dummy_scans_random() {
    local __doc__="Generate dummy reports by scanning same target but different application"
    local _scan_target="${1}"
    local _how_many="${2:-10}"
    local _parallel="${3:-5}"
    local _app_name_prefix="${4:-"dummy-app"}"
    local _org_name_prefix="${5:-"dummy-org"}"
    local _iq_stage="${6:-${_IQ_STAGE:-"develop"}}" #develop|build|stage-release|release|operate
    local _create_under_org="${7-"${_CREATE_UNDER_ORG:-"Sandbox Organization"}"}"

    local _seq_start="${_SEQ_START:-1}"
    local _seq_end="$((_seq_start + _how_many - 1))"

    if [ -z "${_scan_target}" ]; then
        _log "INFO" "No scan target is given. Using ./maven-policy-demo-1.3.0.jar"
        if [ ! -s "${_TMP%/}/maven-policy-demo-1.3.0.jar" ]; then
            curl -o "${_TMP%/}/maven-policy-demo-1.3.0.jar" -L "https://repo1.maven.org/maven2/org/sonatype/maven-policy-demo/1.3.0/maven-policy-demo-1.3.0.jar" || return $?
        fi
        _scan_target="${_TMP%/}/maven-policy-demo-1.3.0.jar"
    fi
    if [ -n "${_create_under_org}" ]; then
        # Just in case, creating the base (under) organization
        f_api_orgId "${_create_under_org}" "Y" || return $?
    fi
    # Automatic applications was required but not any more
    #_apiS "/rest/config/automaticApplications" '{"enabled":true,"parentOrganizationId":"'${_under_org_int_id}'"}' "PUT" || return $?

    local _completed=false
    local _counter=0
    for i in $(eval "seq ${_seq_start} ${_seq_end}"); do
        for j in $(eval "seq 1 ${_parallel}"); do
            local _this_org_id="$(f_api_orgId "${_org_name_prefix}${j}" "Y" "${_create_under_org}")"
            [ -z "${_this_org_id}" ] && return $((i * 10 + j))
            f_api_create_app "${_app_name_prefix}${i}" "${_this_org_id}" || return $?
            _counter=$((_counter + 1))
            local _num=$((_counter + _seq_start - 1))
            if [ ${_counter} -ge ${_how_many} ]; then
                _log "INFO" "Scanning for ${_app_name_prefix}${_num} (last one) ..."
                _SIMPLE_SCAN="Y" f_cli "${_scan_target}" "${_app_name_prefix}${_num}" "${_iq_stage}"
                _completed=true
                break
            fi
            _log "INFO" "Scanning for ${_app_name_prefix}${_num} ..."
            _SIMPLE_SCAN="Y" f_cli "${_scan_target}" "${_app_name_prefix}${_num}" "${_iq_stage}" &>/dev/null &
        done
        wait
        if ${_completed}; then
            break
        fi
    done
}

#f_set_log_level "org.apache.http.headers"
function f_set_log_level() {
    local __doc__="Set / Change some logger's log level (TODO: currently only localhost:8071)"
    local _log_class="${1}"
    local _log_level="${2:-"DEBUG"}"
    if [ -z "${_log_class}" ]; then
        _log "ERROR" "No logger class name is given."
        return 1
    fi
    curl -sSf -X POST -d "logger=${_log_class}&level=${_log_level}" "http://localhost:8071/tasks/log-level" || return $?
}

function f_setup_service() {
    local __doc__="Setup NXIQ as a service"
    # https://help.sonatype.com/iqserver/installing/running-iq-server-as-a-service#RunningIQServerasaService-systemd
    local _base_dir="${1:-"."}"
    local _usr="${2:-"$USER"}"
    local _num_of_files="${3:-4096}"
    local _svc_file="/etc/systemd/system/nexusiq.service"
    local _app_dir="$(readlink -f "${_base_dir%/}")"
    if [ ! -d "${_app_dir}" ]; then
        _log "ERROR" "App dir ${_app_dir} does not exist."
        return 1
    fi

    if [ ! -s ${_app_dir%/}/nexus-iq-server.sh ]; then
        _download_and_extract "https://raw.githubusercontent.com/hajimeo/samples/master/misc/nexus-iq-server.sh" "" "${_app_dir%/}" "" "${_usr}" || return $?
        chown ${_usr}: ${_app_dir%/}/nexus-iq-server.sh || return $?
        chmod u+x ${_app_dir%/}/nexus-iq-server.sh || return $?
    fi


    if [ -s ${_svc_file} ]; then
        _log "WARN" "${_svc_file} already exists. Overwriting..."
        sleep 3
    fi

    local _env="#env="
    #_env="Environment=\"INSTALL4J_ADD_VM_PARAMS=-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005\""
    cat <<EOF >/tmp/nexusiq.service || return $?
[Unit]
Description=nexus iq service
After=network-online.target

[Service]
${_env}
Type=forking
LimitNOFILE=${_num_of_files}
ExecStart=${_app_dir%/}/nexus-iq-server.sh start
ExecStop=${_app_dir%/}/nexus-iq-server.sh stop
User=${_usr}
Restart=on-abort
TimeoutSec=600

[Install]
WantedBy=multi-user.target
EOF
    sudo cp -f -v /tmp/nexusiq.service ${_svc_file} || return $?
    sudo chmod a+x ${_svc_file}
    sudo systemctl daemon-reload || return $?
    sudo systemctl enable nexusiq.service
    _log "INFO" "Service configured. If Nexus is currently running, please stop, then 'systemctl start nexusiq'"
    _log "INFO" "Please modify ${_app_dir%/}/nexus-iq-server.sh for your environment."
    # NOTE: for troubleshooting 'systemctl cat nexusiq'
}

#JAVA_TOOL_OPTIONS="-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=5007" f_cli
#iqCli "container:amazonlinux:2023"
function f_cli() {
    local __doc__="Start IQ CLI https://help.sonatype.com/integrations/nexus-iq-cli#NexusIQCLI-Parameters"
    local _path="${1:-"./"}"
    # overwrite-able global variables
    local _iq_app_id="${2:-${_IQ_APP_ID:-"sandbox-application"}}"
    local _iq_stage="${3:-${_IQ_STAGE:-"build"}}" #develop|build|stage-release|release|operate
    local _iq_url="${4:-${_IQ_URL}}"
    local _iq_cli_ver="${5:-${_IQ_CLI_VER}}"
    local _iq_cli_opt="${6:-${_IQ_CLI_OPT}}" # -D fileIncludes="**/package-lock.json"
    local _iq_cred="${7:-${_IQ_CRED:-"${_ADMIN_USER}:${_ADMIN_PWD}"}}"
    local _simple_scan="${8:-"${_SIMPLE_SCAN:-"N"}"}" # Y: simple, N: full

    _iq_url="$(_get_iq_url "${_iq_url}")" || return $?
    if [ -z "${_iq_cli_ver}" ]; then
        _iq_cli_ver="$(curl -m3 -sf "${_iq_url%/}/rest/product/version" | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a['version'])")"
    fi

    local _iq_cli_jar="${_IQ_CLI_JAR:-"$HOME/.nexus_executable_cache/nexus-iq-cli-${_iq_cli_ver}.jar"}"
    local _cli_dir="$(dirname "${_iq_cli_jar}")"
    if [ ! -s "${_iq_cli_jar}" ]; then
        #local _tmp_iq_cli_jar="$(find ${_WORK_DIR%/}/sonatype -name 'nexus-iq-cli*.jar' 2>/dev/null | sort -r | head -n1)"
        [ ! -d "${_cli_dir}" ] && mkdir -p "${_cli_dir}"
        if [ ! -s "$HOME/.nexus_executable_cache/nexus-iq-server-${_iq_cli_ver}-bundle.tar.gz" ] || ! tar -xvf $HOME/.nexus_executable_cache/nexus-iq-server-${_iq_cli_ver}-bundle.tar.gz -C "${_cli_dir}" nexus-iq-cli-${_iq_cli_ver}.jar; then
            if ! curl -f -L "https://download.sonatype.com/clm/scanner/nexus-iq-cli-${_iq_cli_ver}.jar" -o "${_iq_cli_jar}"; then
                local _cli_filename="$(curl -s -I -L "https://download.sonatype.com/clm/scanner/latest.jar" | grep -o "nexus-iq-cli-.*\.jar")"
                _iq_cli_jar="$HOME/.nexus_executable_cache/${_cli_filename}"
                if [ ! -s "${_iq_cli_jar}" ]; then
                    curl -f -L "https://download.sonatype.com/clm/scanner/latest.jar" -o "${_iq_cli_jar}" || return $?
                fi
            fi
        fi
    fi
    local _java="java"
    if [[ "${_iq_cli_ver}" =~ ^1\.1[89] ]] && [ -n "${JAVA_HOME_17}" ]; then
        _java="${JAVA_HOME_17%/}/bin/java"
    fi
    # NOTE: -X/--debug outputs to STDOUT
    #       Mac uses "TMPDIR" (and can't change), which is like java.io.tmpdir = /var/folders/ct/cc2rqp055svfq_cfsbvqpd1w0000gn/T/ + nexus-iq
    #       Newer IQ CLI removes scan-6947340794864341803.xml.gz (if no -k), so no point of changing the tmpdir...
    # -D includeSha256=true is for BFS
    local _cmd="${_java} -jar ${_iq_cli_jar} ${_iq_cli_opt} -s ${_iq_url} -a \"${_iq_cred}\" -i ${_iq_app_id} -t ${_iq_stage}"
    if [[ ! "${_simple_scan}" =~ ^[yY] ]]; then
        _cmd="${_cmd} -D includeSha256=true -r ./iq_result.json -k -X"
    fi
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Executing: ${_cmd} ${_path} | tee ./iq_cli.out" >&2
    eval "${_cmd} ${_path} | tee ./iq_cli.out"
    local _rc=$?
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Completed (${_rc})." >&2
    if [[ "${_simple_scan}" =~ ^[yY] ]]; then
        return ${_rc}
    fi
    local _scanId="$(rg -m1 '"reportDataUrl"\s*:\s*".+/([0-9a-f]{32})/.*"' -o -r '$1' ./iq_result.json)"
    if [ -n "${_scanId}" ]; then
        _cmd="curl -sf -u \"${_iq_cred}\" ${_iq_url%/}/api/v2/applications/${_iq_app_id}/reports/${_scanId}/raw | python -m json.tool > ./iq_raw.json"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Executing: ${_cmd}" >&2
        eval "${_cmd}"
    fi
}

function f_mvn() {
    local __doc__="Start mvn with IQ plugin https://help.sonatype.com/display/NXI/Sonatype+CLM+for+Maven"
    # overwrite-able global variables
    local _iq_app_id="${1:-${_IQ_APP_ID:-"sandbox-application"}}"
    local _iq_stage="${2:-${_IQ_STAGE:-"build"}}" #develop|build|stage-release|release|operate
    local _iq_url="${3:-${_IQ_URL}}"
    local _file="${4:-"."}"
    local _mvn_opts="${5:-"-X"}" # no -U
    #local _iq_tmp="${_IQ_TMP:-"./iq-tmp"}" # does not generate anything

    local _iq_mvn_ver="${_IQ_MVN_VER}" # empty = latest
    [ -n "${_iq_mvn_ver}" ] && _iq_mvn_ver=":${_iq_mvn_ver}"
    _iq_url="$(_get_iq_url "${_iq_url}")" || return $?

    #clm-maven-plugin:2.30.2-01:index | com.sonatype.clm:clm-maven-plugin:index to generate module.xml file
    local _cmd="mvn -f ${_file} com.sonatype.clm:clm-maven-plugin${_iq_mvn_ver}:evaluate -Dclm.serverUrl=${_iq_url} -Dclm.applicationId=${_iq_app_id} -Dclm.stage=${_iq_stage} -Dclm.username=admin -Dclm.password=admin123 -Dclm.resultFile=iq_result.json -Dclm.scan.dirExcludes=\"**/BOOT-INF/lib/**\" ${_mvn_opts}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Executing: ${_cmd}" >&2
    eval "${_cmd}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Completed." >&2
}

## Utility functions
function _curl() {
    local _sfx="$$_$RANDOM.out"
    curl -sSf -u "${_IQ_CRED:-"${_ADMIN_USER}:${_ADMIN_PWD}"}" "$@" > "${_TMP%/}/${FUNCNAME[0]}_${_sfx}"
    local _rc=$?
    # To make sure the stdout ends with a new line
    printf "%s\n" "$(cat "${_TMP%/}/${FUNCNAME[0]}_${_sfx}")"
    return ${_rc}
}

function _gen_dummy_jar() {
    local _filepath="${1:-"${_TMP%/}/dummy.jar"}"
    if [ ! -s "${_filepath}" ]; then
        if type jar &>/dev/null; then
            echo "test at $(date +'%Y-%m-%d %H:%M:%S')" >dummy.txt
            jar -cvf ${_filepath} dummy.txt || return $?
        else
            curl -o "${_filepath}" "https://repo1.maven.org/maven2/org/sonatype/goodies/goodies-i18n/2.3.4/goodies-i18n-2.3.4.jar" || return $?
        fi
    fi
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
    local _stdout_when_err=""
    if [ "${_data:0:5}" == "file=" ]; then
        _cmd="${_cmd} -F ${_data}"
    elif [ -n "${_data}" ] && [ "${_data:0:1}" != "{" ]; then
        _cmd="${_cmd} -H 'Content-Type: text/plain' --d ${_data}" # TODO: should use quotes?
    elif [ -n "${_data}" ]; then
        _cmd="${_cmd} -H 'Content-Type: application/json' --data-raw '${_data}'"
    fi
    printf "%s\n" "$(eval "${_cmd}")"
}

# In case _IQ_URL is not specified, check my test servers
function _get_iq_url() {
    local _iq_url="${1-${_IQ_URL}}"
    if [ -n "${_iq_url%/}" ]; then
        if [[ ! "${_iq_url}" =~ ^https?://.+ ]]; then
            if [[ ! "${_iq_url}" =~ .+:[0-9]+ ]]; then # Provided hostname only
                _iq_url="http://${_iq_url%/}:8070/"
            else
                _iq_url="http://${_iq_url%/}/"
            fi
        fi
        if curl -m1 -f -s -I "${_iq_url%/}/" &>/dev/null; then
            echo "${_iq_url%/}/"
            return
        fi
    fi
    # if curl is failing, silently replacing with
    for _url in "http://localhost:8070/" "${_IQ_TEST_URL%/}/"; do
        if [ "${_iq_url%/}" != "${_url%/}" ] && curl -m1 -f -s -I "${_url%/}/" &>/dev/null; then
            echo "${_url%/}/"
            return
        fi
    done
    return 1
}

### Main #######################################################################################################
main() {
    # Clear the log file if not empty
    [ -s "${_LOG_FILE_PATH}" ] && gzip -S "_$(date +'%Y%m%d%H%M%S').gz" "${_LOG_FILE_PATH}" &>/dev/null
    [ -n "${_LOG_FILE_PATH}" ] && touch ${_LOG_FILE_PATH} && chmod a+w ${_LOG_FILE_PATH}
    # Just in case, creating the work directory
    [ -n "${_WORK_DIR}" ] && [ ! -d "${_WORK_DIR}/sonatype" ] && mkdir -p -m 777 ${_WORK_DIR}/sonatype

    # Checking requirements (so far only a few commands)
    if [ "$(uname)" = "Darwin" ]; then
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
    if [ -s "${_RESP_FILE}" ]; then
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
