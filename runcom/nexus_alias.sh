# source <(curl https://raw.githubusercontent.com/hajimeo/samples/master/runcom/nexus_alias.sh --compressed)

if [ -z "${_WORK_DIR}" ]; then
    if [ "`uname`" = "Darwin" ]; then
        _WORK_DIR="$HOME/share/sonatype"
    else
        _WORK_DIR="/var/tmp/share/sonatype"
    fi
fi

# Start iq CLI
function iqCli() {
    local __doc__="https://help.sonatype.com/integrations/nexus-iq-cli#NexusIQCLI-Parameters"
    # overwrite-able global variables
    local _iq_url="${_IQ_URL:-"http://dh1.standalone.localdomain:8070/"}"
    local _iq_cli_ver="${_IQ_CLI_VER:-"1.95.0-01"}"
    local _iq_cli_jar="${_IQ_CLI_JAR:-"${_WORK_DIR%/}/nexus-iq-cli-${_iq_cli_ver}.jar"}"
    local _iq_app_id="${_IQ_APP_ID:-"sandbox-application"}"
    local _iq_stage="${_IQ_STAGE:-"build"}" #develop|build|stage-release|release|operate
    local _iq_tmp="${_IQ_TMP:-"./tmp"}"

    if [ -z "$1" ]; then
        iqCli "./"
        return $?
    fi

    if [ -z "${_IQ_URL}" ] && curl -f -s -I "http://localhost:8070/" &>/dev/null; then
        _iq_url="http://localhost:8070/"
    fi
    #[ ! -d "${_iq_tmp}" ] && mkdir -p "${_iq_tmp}"
    if [ ! -s "${_iq_cli_jar}" ]; then
        local _tmp_iq_cli_jar="$(find ${_WORK_DIR%/} -name 'nexus-iq-cli*.jar' 2>/dev/null | sort -r | head -n1)"
        if [ -z "${_IQ_CLI_VER}" ] && [ -n "${_tmp_iq_cli_jar}" ]; then
            _iq_cli_jar="${_tmp_iq_cli_jar}"
        else
            curl -f -L "https://download.sonatype.com/clm/scanner/nexus-iq-cli-${_iq_cli_ver}.jar" -o "${_iq_cli_jar}" || return $?
        fi
    fi
    echo "Executing: java -jar ${_iq_cli_jar} -s "${_iq_url}" -a \"admin:admin123\" -i \"${_iq_app_id}\" -t \"${_iq_stage}\" $@" >&2
    java -Djava.io.tmpdir="${_iq_tmp}" -jar ${_iq_cli_jar} -s "${_iq_url}" -a "admin:admin123" -i "${_iq_app_id}" -t "${_iq_stage}" -r ${_iq_tmp%/}/iq_result_$(date +'%Y%m%d%H%M%S').json -X $@
}

# Start "mvn" with IQ plugin
function iqMvn() {
    # https://help.sonatype.com/display/NXI/Sonatype+CLM+for+Maven
    mvn com.sonatype.clm:clm-maven-plugin:evaluate -Dclm.additionalScopes=test,provided,system -Dclm.applicationId=sandbox-application -Dclm.serverUrl=http://dh1.standalone.localdomain:8070/ -Dclm.username=admin -Dclm.password=admin123
}

# mvn archetype:generate wrapper to use a remote repo
function mvn-arch-gen() {
    # https://maven.apache.org/guides/getting-started/maven-in-five-minutes.html
    local _gav="${1:-"com.example:my-app:1.0"}"
    local _remote_repo="$2"
    local _local_repo="${3-"./local_repo"}"
    local _options="${4-"-Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS -U -X"}"
    local _type="${5:-"maven-archetype-quickstart"}"

    if [[ "${_gav}" =~ ^([^:]+):([^:]+):([^:]+)$ ]]; then
        local _g="${BASH_REMATCH[1]}"
        local _a="${BASH_REMATCH[2]}"
        local _v="${BASH_REMATCH[3]}"
        #[ -n "${_local_repo}" ] && _options="${_options% } -Dmaven.repo.local=${_local_repo}"  # or -DremoteRepositories both doesn't work
        [ -n "${_remote_repo}" ] && _options="${_options% } -Dmaven.repo.remote=${_remote_repo}"
        mvn `_mvn_settings "${_remote_repo}"` archetype:generate -DgroupId=${_g} -DartifactId=${_a} -DarchetypeArtifactId=${_type} -DarchetypeVersion=${_v} -DinteractiveMode=false ${_options}
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
        sed -i -E "s@<url>http.+/(content|repository)/.+</url>@<url>${_remote_repo}</url>@1" ${_settings_xml}
    fi
    echo "-s ${_settings_xml}"
}
