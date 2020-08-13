# source <(curl https://raw.githubusercontent.com/hajimeo/samples/master/runcom/nexus_alias.sh --compressed)

if [ -z "${_WORK_DIR}" ]; then
    if [ "`uname`" = "Darwin" ]; then
        _WORK_DIR="$HOME/share"
    else
        _WORK_DIR="/var/tmp/share"
    fi
fi


[ -s $HOME/IdeaProjects/nexus-toolbox/scripts/analyze-nexus3-support-zip.py ] && alias sptZip3="python3 $HOME/IdeaProjects/nexus-toolbox/scripts/analyze-nexus3-support-zip.py"
[ -s $HOME/IdeaProjects/nexus-toolbox/scripts/analyze-nexus2-support-zip.py ] && alias sptZip2="python3 $HOME/IdeaProjects/nexus-toolbox/scripts/analyze-nexus2-support-zip.py"
[ -s $HOME/IdeaProjects/nexus-toolbox/scripts/dump_nxrm3_groovy_scripts.py ] && alias sptDumpScript="python3 $HOME/IdeaProjects/nexus-toolbox/scripts/dump_nxrm3_groovy_scripts.py"


# Start iq CLI
function iqCli() {
    local __doc__="https://help.sonatype.com/integrations/nexus-iq-cli#NexusIQCLI-Parameters"
    # overwrite-able global variables
    local _iq_url="${_IQ_URL:-"http://dh1.standalone.localdomain:8070/"}"
    local _iq_app_id="${_IQ_APP_ID:-"sandbox-application"}"
    local _iq_stage="${_IQ_STAGE:-"build"}" #develop|build|stage-release|release|operate
    local _iq_tmp="${_IQ_TMP:-"./tmp"}"
    local _iq_cli_ver="${_IQ_CLI_VER:-"1.95.0-01"}"
    local _iq_cli_jar="${_IQ_CLI_JAR:-"${_WORK_DIR%/}/sonatype/nexus-iq-cli-${_iq_cli_ver}.jar"}"

    if [ -z "$1" ]; then
        iqCli "./"
        return $?
    fi

    if [ -z "${_IQ_URL}" ] && curl -f -s -I "http://localhost:8070/" &>/dev/null; then
        _iq_url="http://localhost:8070/"
    elif [ -n "${_iq_url}" ] && [[ ! "${_iq_url}" =~ ^http.+ ]]; then
        _iq_url="http://${_iq_url}:8070/"
    fi
    #[ ! -d "${_iq_tmp}" ] && mkdir -p "${_iq_tmp}"
    # If no preference about CLI version, search local in case of Support boot
    local _tmp_iq_cli_jar="$(find . -maxdepth 3 -name 'nexus-iq-cli*.jar' 2>/dev/null | sort -r | head -n1)"
    if [ -z "${_IQ_CLI_VER}" ] && [ -z "${_IQ_CLI_JAR}" ] && [ -n "${_tmp_iq_cli_jar}" ]; then
        _iq_cli_jar="${_tmp_iq_cli_jar}"
    fi

    if [ ! -s "${_iq_cli_jar}" ]; then
        # If the file does not exist, trying to get the latest version from the _WORK_DIR
        local _tmp_iq_cli_jar="$(find ${_WORK_DIR%/}/sonatype -name 'nexus-iq-cli*.jar' 2>/dev/null | sort -r | head -n1)"
        if [ -n "${_tmp_iq_cli_jar}" ]; then
            _iq_cli_jar="${_tmp_iq_cli_jar}"
        else
            curl -f -L "https://download.sonatype.com/clm/scanner/nexus-iq-cli-${_iq_cli_ver}.jar" -o "${_iq_cli_jar}" || return $?
        fi
    fi
    local _cmd="java -Djava.io.tmpdir="${_iq_tmp}" -jar ${_iq_cli_jar} -s "${_iq_url}" -a "admin:admin123" -i "${_iq_app_id}" -t "${_iq_stage}" -r ${_iq_tmp%/}/iq_result_$(date +'%Y%m%d%H%M%S').json -X $@"
    echo "Executing: ${_cmd}" >&2
    eval "${_cmd}"
}

# Start "mvn" with IQ plugin
function iqMvn() {
    local __doc__="https://help.sonatype.com/display/NXI/Sonatype+CLM+for+Maven"
    local _iq_url="${_IQ_URL:-"http://dh1.standalone.localdomain:8070/"}"
    local _iq_app_id="${_IQ_APP_ID:-"sandbox-application"}"
    local _iq_stage="${_IQ_STAGE:-"build"}" #develop|build|stage-release|release|operate
    local _iq_mvn_ver="${_IQ_MVN_VER}"  # empty = latest
    [ -n "${_iq_mvn_ver}" ] && _iq_mvn_ver=":${_iq_mvn_ver}"
    if [ -z "${_IQ_URL}" ] && curl -f -s -I "http://localhost:8070/" &>/dev/null; then
        _iq_url="http://localhost:8070/"
    fi
    #local _iq_tmp="${_IQ_TMP:-"./tmp"}"
    local _cmd="mvn com.sonatype.clm:clm-maven-plugin${_iq_mvn_ver}:evaluate -Dclm.serverUrl=${_iq_url} -Dclm.applicationId=${_iq_app_id} -Dclm.stage=${_iq_stage} -Dclm.username=admin -Dclm.password=admin123 -U -X $@"
    echo "Executing: ${_cmd}" >&2
    eval "${_cmd}"
}

function sptBoot() {
    local _zip="$1"
    local _jdb="$2"

    [ -s $HOME/IdeaProjects/nexus-toolbox/support-zip-booter/boot_support_zip.py ] || return 1
    if [ -z "${_zip}" ]; then
        _zip="$(ls -1 ./*-202?????-??????*.zip | tail -n1)" || return $?
        echo "Using ${_zip} ..."
    fi
    #echo "To just re-launch or start, check relaunch-support.sh"
    if [ ! -s $HOME/.nexus_executable_cache/ssl/keystore.jks.orig ]; then
        echo "Replacing keystore.jks ..."
        mv $HOME/.nexus_executable_cache/ssl/keystore.jks $HOME/.nexus_executable_cache/ssl/keystore.jks.orig
        cp $HOME/IdeaProjects/samples/misc/standalone.localdomain.jks $HOME/.nexus_executable_cache/ssl/keystore.jks
        echo "Append 'local.standalone.localdomain' in 127.0.0.1 line in /etc/hosts."
    fi
    if [[ "${_jdb}" =~ ^(y|Y) ]]; then
        python3 $HOME/IdeaProjects/nexus-toolbox/support-zip-booter/boot_support_zip.py --remote-debug -cr "${_zip}" ./$(basename "${_zip}" .zip)_tmp
    else
        python3 $HOME/IdeaProjects/nexus-toolbox/support-zip-booter/boot_support_zip.py -cr "${_zip}" ./$(basename "${_zip}" .zip)_tmp
    fi || echo "NOTE: If error was port already in use, you might need to run below:
    . ~/IdeaProjects/work/bash/install_sonatype.sh
    f_sql_nxrm \"config\" \"SELECT attributes['docker']['httpPort'] FROM repository WHERE attributes['docker']['httpPort'] IS NOT NULL\" \".\" \"\$USER\"
If ports conflict, edit nexus.properties is easier. eg:8080.
"
}

# To start local (on Mac) IQ server
function iqStart() {
    local _base_dir="${1:-"."}"
    local _java_opts=${2}
    #local _java_opts=${@:2}
    local _jar_file="$(find ${_base_dir%/} -type f -name 'nexus-iq-server*.jar' 2>/dev/null | sort | tail -n1)"
    local _cfg_file="$(dirname "${_jar_file}")/config.yml"
    grep -qE '^\s*threshold:\s*INFO$' "${_cfg_file}" && sed -i.bak 's/threshold: INFO/threshold: ALL/g' "${_cfg_file}"
    grep -qE '^\s*level:\s*DEBUG$' "${_cfg_file}" || sed -i.bak -E 's/level: .+/level: DEBUG/g' "${_cfg_file}"
    java -Xmx2g ${_java_opts} -jar "${_jar_file}" server "${_cfg_file}"
}

# mvn archetype:generate wrapper to use a remote repo
function mvn-arch-gen() {
    local __doc__="https://maven.apache.org/guides/getting-started/maven-in-five-minutes.html"
    local _gav="${1:-"com.example:my-app:1.0"}"
    local _remote_repo="$2"
    local _local_repo="${3}"    # Not using local repo for this command
    local _options="${4-"-Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS -U -X"}"
    local _type="${5:-"maven-archetype-quickstart"}"

    if [[ "${_gav}" =~ ^([^:]+):([^:]+):([^:]+)$ ]]; then
        local _g="${BASH_REMATCH[1]}"
        local _a="${BASH_REMATCH[2]}"
        local _v="${BASH_REMATCH[3]}"
        [ -n "${_local_repo}" ] && _options="${_options% } -Dmaven.repo.local=${_local_repo}"
        mvn `_mvn_settings "${_remote_repo}"` archetype:generate -DgroupId=${_g} -DartifactId=${_a} -DarchetypeArtifactId=${_type} -DarchetypeVersion=${_v} -DinteractiveMode=false ${_options}
    fi
}

# mvn archetype:generate wrapper to use a remote repo
#mvn-dep-file httpclient-4.5.1.jar "com.example:my-app:1.0" "http://local.standalone.localdomain:8081/repository/maven-hosted/"
#get_by_gav "com.example:my-app:1.0" "http://local.standalone.localdomain:8081/repository/repo_maven_hosted/"
function mvn-dep-file() {
    local __doc__="https://maven.apache.org/plugins/maven-deploy-plugin/usage.html"
    local _file="${1}"
    local _gav="${2:-"com.example:my-app:1.0"}"
    local _remote_repo="$3"
    local _server_id="${4:-"nexus"}"
    local _options="${5-"-Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS -U -X"}"

    if [[ "${_gav}" =~ ^([^:]+):([^:]+):([^:]+)$ ]]; then
        local _g="${BASH_REMATCH[1]}"
        local _a="${BASH_REMATCH[2]}"
        local _v="${BASH_REMATCH[3]}"
        [ -n "${_remote_repo}" ] && _options="${_options% } -Durl=${_remote_repo}"
        [ -n "${_server_id}" ] && _options="${_options% } -DrepositoryId=${_server_id}"
        mvn `_mvn_settings "${_remote_repo}"` deploy:deploy-file -DgroupId=${_g} -DartifactId=${_a} -Dversion=${_v} -DgeneratePom=true -Dfile=${_file} ${_options}
    fi
}

# Get one jar (file) by GAV
function get_by_gav() {
    local _gav="$1" # eg: junit:junit:4.12
    local _repo_url="${2:-"http://dh1.standalone.localdomain:8081/repository/maven-public/"}"
    local _user="${3:-"admin"}"
    local _pwd="${4:-"admin123"}"
    if [[ "${_gav}" =~ ^([^:]+):([^:]+):([^:]+)$ ]]; then
        local _g="${BASH_REMATCH[1]}"
        local _a="${BASH_REMATCH[2]}"
        local _v="${BASH_REMATCH[3]}"
        local _path="$(echo "${_g}" | sed "s@\.@/@g")/${_a}/${_v}/${_a}-${_v}.jar"

        curl -v -O -J -L -f -u ${_user}:${_pwd} -k "${_repo_url%/}/${_path#/}" || return $?
    fi
}

# mvn devendency:get wrapper to use remote repo
function mvn-get() {
    # maven/mvn get/download
    local _gav="$1" # eg: junit:junit:4.12
    local _remote_repo="$2"
    local _local_repo="${3-"./local_repo"}"
    local _options="${4-"-Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS -Dtransitive=false -U -X"}"
    [ -n "${_local_repo}" ] && _options="${_options% } -Dmaven.repo.local=${_local_repo}"
    mvn `_mvn_settings "${_remote_repo}"` dependency:get -Dartifact=${_gav} ${_options}
}

# mvn devendency:resolve wrapper to use remote repo
function mvn-resolve() {
    # maven/mvn resolve dependency only
    local _remote_repo="$1"
    local _local_repo="$2"
    local _options=""
    [ -n "${_local_repo}" ] && _options="${_options% } -Dmaven.repo.local=${_local_repo}"
    mvn `_mvn_settings "${_remote_repo}"` -Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS dependency:resolve ${_options} -U -X
}

function _mvn_settings() {
    # -Dmaven.repo.remote=${_remote_repo} or -DremoteRepositories both is NOT working, so replacing settings.xml
    local _remote_repo="$1"
    local _settings_xml="$(find . -maxdepth 2 -name '*settings*.xml' -not -path "./.m2/*" -print | tail -n1)"
    if [ -z "${_settings_xml}" ] && [ -s $HOME/.m2/settings.xml ]; then
        _settings_xml="./m2_settings.xml"
        cp $HOME/.m2/settings.xml ${_settings_xml}
    fi
    [ -z "${_settings_xml}" ] && return 1
    echo "Using ${_settings_xml}..." >&2; sleep 3
    if [ -n "${_remote_repo}" ]; then
        # TODO: this substitute is not good
        sed -i.bak -E "s@<url>http.+/(content|repository)/.+</url>@<url>${_remote_repo}</url>@1" ${_settings_xml}
    fi
    echo "-s ${_settings_xml}"
}

# npm-init might be already used
function npmInit() {
    cat << EOF > ./package.json
{
  "name": "45674",
  "version": "1.0.0",
  "description": "",
  "main": "index.js",
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "keywords": [],
  "author": "",
  "dependencies" : {
    "lodash": "4.17.4"
  },
  "license": "ISC"
}
EOF
}
