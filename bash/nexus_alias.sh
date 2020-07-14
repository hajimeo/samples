# source <(curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/nexus_alias.sh)

# Start iq CLI
function iqCli() {
    local __doc__="https://help.sonatype.com/integrations/nexus-iq-cli#NexusIQCLI-Parameters"
    if [ -z "$1" ]; then
        iqCli "./"
        return $?
    fi
    local _jar="$(find /var/tmp/share/sonatype -name 'nexus-iq-cli*.jar' 2>/dev/null | sort -r | head -n1)" || return $?
    echo "Using ${_jar} ..." >&2
    java -jar ${_jar} -i "${_IQ_APP:-"sandbox-application"}" -s "${_IQ_URL:-"http://dh1.standalone.localdomain:8070/"}" -a "admin:admin123" -r ./iq_result_$(date +'%Y%m%d%H%M%S').json -X $@
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
    local _settings_xml="$(find . -maxdepth 2 -name '*settings*.xml' -print | tail -n1)"
    if [ -n "${_settings_xml}" ]; then
        echo "Using ${_settings_xml}..." >&2; sleep 3
        _options="${_options% } -s ${_settings_xml}"
    fi
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
