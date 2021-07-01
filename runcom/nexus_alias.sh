#_import() { curl -sf --compressed "https://raw.githubusercontent.com/hajimeo/samples/master/$1" -o /tmp/_i;. /tmp/_i; }
#_import "runcom/nexus_alias.sh"

if [ -z "${_WORK_DIR%/}" ]; then
    if [ "`uname`" = "Darwin" ]; then
        # dovker -v does not work with symlink
        _WORK_DIR="$HOME/share"
    else
        _WORK_DIR="/var/tmp/share"
    fi
fi

# Start iq CLI
# To debug, use suspend=y
#_JAVA_OPTIONS="-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=5007" iqCli
function iqCli() {
    local __doc__="https://help.sonatype.com/integrations/nexus-iq-cli#NexusIQCLI-Parameters"
    local _path="${1:-"./"}"
    # overwrite-able global variables
    local _iq_app_id="${2:-${_IQ_APP_ID:-"sandbox-application"}}"
    local _iq_stage="${3:-${_IQ_STAGE:-"build"}}" #develop|build|stage-release|release|operate
    local _iq_url="${4:-${_IQ_URL}}"
    local _iq_cli_ver="${5:-${_IQ_CLI_VER:-"1.117.0-01"}}"
    local _iq_cli_opt="${6:-${_IQ_CLI_OPT}}"
    local _iq_cli_jar="${_IQ_CLI_JAR:-"${_WORK_DIR%/}/sonatype/iq-cli/nexus-iq-cli-${_iq_cli_ver}.jar"}"
    local _iq_tmp="${_IQ_TMP:-"./iq-tmp"}"

    if [ -z "${_iq_url}" ] && [ -z "${_IQ_URL}" ] && curl -f -s -I "http://localhost:8070/" &>/dev/null; then
        _iq_url="http://localhost:8070/"
    elif [ -n "${_iq_url}" ] && [[ ! "${_iq_url}" =~ ^https?://.+:[0-9]+ ]]; then   # Provided hostname only
        _iq_url="http://${_iq_url}:8070/"
    elif [ -z "${_iq_url}" ]; then  # default
        _iq_url="http://dh1.standalone.localdomain:8070/"
    fi
    #[ ! -d "${_iq_tmp}" ] && mkdir -p "${_iq_tmp}"

    if [ ! -s "${_iq_cli_jar}" ]; then
        #local _tmp_iq_cli_jar="$(find ${_WORK_DIR%/}/sonatype -name 'nexus-iq-cli*.jar' 2>/dev/null | sort -r | head -n1)"
        local _cli_dir="$(dirname "${_iq_cli_jar}")"
        [ ! -d "${_cli_dir}" ] && mkdir -p "${_cli_dir}"
        curl -f -L "https://download.sonatype.com/clm/scanner/nexus-iq-cli-${_iq_cli_ver}.jar" -o "${_iq_cli_jar}" || return $?
    fi
    local _cmd="java -Djava.io.tmpdir=\"${_iq_tmp}\" -jar ${_iq_cli_jar} ${_iq_cli_opt} -s ${_iq_url} -a 'admin:admin123' -i ${_iq_app_id} -t ${_iq_stage} -r \"${_iq_tmp%/}/iq_result_$(date +'%Y%m%d%H%M%S').json\" -X ${_path}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Executing: ${_cmd}" >&2
    eval "${_cmd}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Completed." >&2
}

# Start "mvn" with IQ plugin
function iqMvn() {
    local __doc__="https://help.sonatype.com/display/NXI/Sonatype+CLM+for+Maven"
    # overwrite-able global variables
    local _iq_app_id="${1:-${_IQ_APP_ID:-"sandbox-application"}}"
    local _iq_stage="${2:-${_IQ_STAGE:-"build"}}" #develop|build|stage-release|release|operate
    local _iq_url="${3:-${_IQ_URL}}"
    local _mvn_opts="${4:-"-X"}"    # no -U
    #local _iq_tmp="${_IQ_TMP:-"./iq-tmp"}" # does not generate anything

    local _iq_mvn_ver="${_IQ_MVN_VER}"  # empty = latest
    [ -n "${_iq_mvn_ver}" ] && _iq_mvn_ver=":${_iq_mvn_ver}"

    if [ -z "${_iq_url}" ] && [ -z "${_IQ_URL}" ] && curl -f -s -I "http://localhost:8070/" &>/dev/null; then
        _iq_url="http://localhost:8070/"
    elif [ -n "${_iq_url}" ] && [[ ! "${_iq_url}" =~ ^https?://.+:[0-9]+ ]]; then   # Provided hostname only
        _iq_url="http://${_iq_url}:8070/"
    elif [ -z "${_iq_url}" ]; then  # default
        _iq_url="http://dh1.standalone.localdomain:8070/"
    fi

    local _cmd="mvn com.sonatype.clm:clm-maven-plugin${_iq_mvn_ver}:evaluate -Dclm.serverUrl=${_iq_url} -Dclm.applicationId=${_iq_app_id} -Dclm.stage=${_iq_stage} -Dclm.username=admin -Dclm.password=admin123 ${_mvn_opts}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Executing: ${_cmd}" >&2
    eval "${_cmd}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Completed." >&2
}

# To start local (on Mac) NXRM2 or NXRM3 server
function nxrmStart() {
    local _base_dir="${1:-"."}"
    local _java_opts=${2-"-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005"}
    local _mode=${3} # if NXRM2, not 'run' but 'console'
    #local _java_opts=${@:2}
    local _nexus_file="$(find ${_base_dir%/} -maxdepth 4 -path '*/bin/*' -type f -name 'nexus' 2>/dev/null | sort | tail -n1)"
    local _cfg_file="$(find ${_base_dir%/} -maxdepth 4 -path '*/sonatype-work/nexus3/etc/*' -type f -name 'nexus.properties' 2>/dev/null | sort | tail -n1)"
    local _jetty_https="$(find ${_base_dir%/} -maxdepth 4 -path '*/etc/*' -type f -name 'jetty-https.xml' 2>/dev/null | sort | tail -n1)"
    local _logback_overrides="$(find ${_base_dir%/} -maxdepth 4 -path '*/etc/logback/*' -type f -name 'logback-overrides.xml' 2>/dev/null | sort | tail -n1)"
    if [ -n "${_cfg_file}" ]; then
        grep -qE '^\s*nexus.scripts.allowCreation' "${_cfg_file}" || echo "nexus.scripts.allowCreation=true" >> "${_cfg_file}"
        grep -qE '^\s*nexus.browse.component.tree.automaticRebuild' "${_cfg_file}" || echo "nexus.browse.component.tree.automaticRebuild=false" >> "${_cfg_file}"
        # NOTE: this would not work if elasticsearch directory is empty
        grep -qE '^\s*nexus.elasticsearch.autoRebuild' "${_cfg_file}" || echo "nexus.elasticsearch.autoRebuild=false" >> "${_cfg_file}"
        [ -z "${_mode}" ] && _mode="run"
    else
        [ -z "${_mode}" ] && _mode="console"
    fi
    if [ -n "${_jetty_https}" ]; then
        # TODO: version check as below breaks older nexus versions.
        sed -i.bak 's@class="org.eclipse.jetty.util.ssl.SslContextFactory"@class="org.eclipse.jetty.util.ssl.SslContextFactory$Server"@g' ${_jetty_https}
    fi
    if false && [ -s "${_logback_overrides}" ]; then
        echo "$(grep -vE "(org.sonatype.nexus.orient.explain|</included>)" ${_logback_overrides})
  <logger name='org.sonatype.nexus.orient.explain' level='TRACE'/>
</included>" > ${_logback_overrides}
    fi
    # For java options, latter values are used, so appending
    INSTALL4J_ADD_VM_PARAMS="${INSTALL4J_ADD_VM_PARAMS} ${_java_opts}" ${_nexus_file} ${_mode}
}

#nxrmDocker "nxrm3-test" "" "8181" "8543" "--read-only -v /tmp/nxrm3-test:/tmp"
function nxrmDocker() {
    local _name="${1:-"nxrm3"}"
    local _tag="${2:-"latest"}"
    local _port="${3:-"8081"}"
    local _port_ssl="${4:-"8443"}"
    local _extra_opts="${5}"    # such as -Djava.util.prefs.userRoot=/some-other-dir
    local _docker_host="${_DOCKER_HOST:-"dh1.standalone.localdomain:5000"}"

    local _nexus_data="${_WORK_DIR%/}/sonatype/${_name}-data"
    if [ ! -d "${_nexus_data%/}" ]; then
        mkdir -p -m 777 "${_nexus_data%/}" || return $?
    fi
    local _opts="--name=${_name}"
    [ -n "${INSTALL4J_ADD_VM_PARAMS}" ] && _opts="${_opts} -e INSTALL4J_ADD_VM_PARAMS=\"${INSTALL4J_ADD_VM_PARAMS}\""
    [ -d ${_WORK_DIR%/} ] && _opts="${_opts} -v ${_WORK_DIR%/}:/var/tmp/share"
    [ -d "${_nexus_data%/}" ] && _opts="${_opts} -v ${_nexus_data%/}:/nexus-data"
    [ -n "${_extra_opts}" ] && _opts="${_opts} ${_extra_opts}"  # Should be last to overwrite
    local _cmd="docker run -d -p ${_port}:8081 -p ${_port_ssl}:8443 ${_opts} ${_docker_host%/}/sonatype/nexus3:${_tag}"
    echo "${_cmd}"
    eval "${_cmd}"
    echo "
    docker exec -ti ${_name} cat /nexus-data/admin.password
    docker logs -f ${_name}"
}

# To start local (on Mac) IQ server
function iqStart() {
    local _base_dir="${1:-"."}"
    local _java_opts=${2-"-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5006"}
    #local _java_opts=${@:2}
    local _jar_file="$(realpath "$(find ${_base_dir%/} -maxdepth 1 -type f -name 'nexus-iq-server*.jar' 2>/dev/null | sort | tail -n1)")"
    [ -z "${_jar_file}" ] && return 11
    local _cfg_file="$(realpath "$(dirname "${_jar_file}")/config.yml")"
    [ -z "${_cfg_file}" ] && return 12
    grep -qE '^baseUrl:' "${_cfg_file}" || echo -e "baseUrl: http://localhost:8070/\n$(cat "${_cfg_file}")" > "${_cfg_file}"
    grep -qE '^\s*threshold:\s*INFO$' "${_cfg_file}" && sed -i.bak 's/threshold: INFO/threshold: ALL/g' "${_cfg_file}"
    grep -qE '^\s*level:\s*DEBUG$' "${_cfg_file}" || sed -i.bak -E 's/level: .+/level: DEBUG/g' "${_cfg_file}"
    cd "${_base_dir}"
    java -Xmx2g ${_java_opts} -jar "${_jar_file}" server "${_cfg_file}"
    cd -
}

#iqDocker "nxiq-test" "" "8170" "8171" "8544" #"--read-only -v /tmp/nxiq-test:/tmp"
function iqDocker() {
    local _name="${1:-"nxiq"}"
    local _tag="${2:-"latest"}"
    local _port="${3:-"8070"}"
    local _port2="${4:-"8071"}"
    local _port_ssl="${5:-"8444"}"
    local _extra_opts="${6}"
    local _license="${7}"
    local _docker_host="${_DOCKER_HOST:-"dh1.standalone.localdomain:5000"}"

    local _nexus_data="${_WORK_DIR%/}/sonatype/${_name}-data"
    [ ! -d "${_nexus_data%/}" ] && mkdir -p -m 777 "${_nexus_data%/}"
    [ ! -d "${_nexus_data%/}/etc" ] && mkdir -p -m 777 "${_nexus_data%/}/etc"
    [ ! -d "${_nexus_data%/}/log" ] && mkdir -p -m 777 "${_nexus_data%/}/log"
    local _opts="--name=${_name}"
    local _java_opts=""
    # NOTE: symlink of *.lic does not work with -v
    [ -z "${_license}" ] && [ -d ${_WORK_DIR%/}/sonatype ] && _license="$(ls -1t /var/tmp/share/sonatype/*.lic 2>/dev/null | head -n1)"
    [ -s "${_license}" ] && _java_opts="-Ddw.licenseFile=${_license}"
    [ -n "${JAVA_OPTS}" ] && _java_opts="${_java_opts} ${JAVA_OPTS}"
    [ -n "${_java_opts}" ] && _opts="${_opts} -e JAVA_OPTS=\"${_java_opts}\""
    [ -d ${_WORK_DIR%/} ] && _opts="${_opts} -v ${_WORK_DIR%/}:/var/tmp/share"
    [ -d "${_nexus_data%/}" ] && _opts="${_opts} -v ${_nexus_data%/}:/sonatype-work"
    [ -s "${_nexus_data%/}/etc/config.yml" ] && _opts="${_opts} -v ${_nexus_data%/}/etc:/etc/nexus-iq-server"
    [ -d "${_nexus_data%/}/log" ] && _opts="${_opts} -v ${_nexus_data%/}/log:/var/log/nexus-iq-server"
    [ -d "${_nexus_data%/}/log" ] && _opts="${_opts} -v ${_nexus_data%/}/log:/opt/sonatype/nexus-iq-server/log" # due to audit.log => fixed from v104
    [ -n "${_extra_opts}" ] && _opts="${_opts} ${_extra_opts}"  # Should be last to overwrite
    local _cmd="docker run -d -p ${_port}:8070 -p ${_port2}:8071 -p ${_port_ssl}:8444 ${_opts} ${_docker_host%/}/sonatype/nexus-iq-server:${_tag}"
    echo "${_cmd}"
    eval "${_cmd}"
    echo "/opt/sonatype/nexus-iq-server/start.sh may need to be replaced to trap SIGTERM"
    if ! docker cp nxiq-test:/opt/sonatype/nexus-iq-server/start.sh - | grep -qa TERM; then
        cat << EOF > /tmp/start_$$.sh
_term() {
  echo "Received signal: SIGTERM"
  kill -TERM "$(cat /sonatype-work/lock | cut -d"@" -f1)"
  sleep 10
}
trap _term SIGTERM
/usr/bin/java ${JAVA_OPTS} -jar nexus-iq-server-*.jar server /etc/nexus-iq-server/config.yml &
wait
EOF
        docker cp /tmp/start_$$.sh nxiq-test:/opt/sonatype/nexus-iq-server/start.sh
    fi
}



function mvn-purge-local() {
    local __doc__="https://maven.apache.org/plugins/maven-dependency-plugin/examples/purging-local-repository.html"
    local actTransitively="${1:-"false"}"
    local _local_repo="${2}"
    local _remote_repo="${3}"
    local _options="${4-"-X"}"
    [ -n "${_local_repo}" ] && _options="${_options% } -Dmaven.repo.local=${_local_repo}"
    mvn `_mvn_settings "${_remote_repo}"` dependency:purge-local-repository -DactTransitively=${actTransitively} ${_options}
}

# mvn archetype:generate wrapper to use a remote repo
function mvn-arch-gen() {
    local __doc__="https://maven.apache.org/guides/getting-started/maven-in-five-minutes.html"
    local _gav="${1:-"com.example:my-app:1.0"}"
    #local _output_dir="$2"
    local _remote_repo="$2"
    local _local_repo="${3}"    # Not using local repo for this command
    local _options="${4-"-Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS -U -X"}"
    local _type="${5:-"maven-archetype-quickstart"}"

    if [[ "${_gav}" =~ ^" "*([^: ]+)" "*:" "*([^: ]+)" "*:" "*([^: ]+)" "*$ ]]; then
        local _g="${BASH_REMATCH[1]}"
        local _a="${BASH_REMATCH[2]}"
        local _v="${BASH_REMATCH[3]}"
        [ -n "${_local_repo}" ] && _options="${_options% } -Dmaven.repo.local=${_local_repo}"
        #if [ -z "${_output_dir}" ]; then
        #    _options="${_options% } -DoutputDirectory=${_a}"
        #else
        #    _options="${_options% } -DoutputDirectory=${_output_dir}"
        #fi
        mvn `_mvn_settings "${_remote_repo}"` archetype:generate -DgroupId=${_g} -DartifactId=${_a} -DarchetypeArtifactId=${_type} -DarchetypeVersion=${_v} -DinteractiveMode=false ${_options} || return $?
        cd ${_a}
    fi
}

function mvn-package() {
    local __doc__="Wrapper of mvn clean package"
    local _remote_repo="${1}"
    local _local_repo="${2}"
    local _options="${3-"-Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS -U -X"}"
    [ -n "${_local_repo}" ] && _options="${_options% } -Dmaven.repo.local=${_local_repo}"
    mvn `_mvn_settings "${_remote_repo}"` clean package ${_options}
}

# Example to generate 10 versions / snapshots (NOTE: in bash heredoc, 'EOF' and just EOF is different)
: <<'EOF'
mvn-arch-gen
_REPO_URL="http://node3290.standalone.localdomain:8081/repository/maven-hosted/"
#mvn-deploy "${_REPO_URL}" "" "nexus"
  #sed -i.tmp -E "s@<groupId>com.example.*</groupId>@<groupId>com.example${i}</groupId>@" pom.xml   # If need to change groupId
  #sed -i.tmp -E "s@<artifactId>my-app.*</artifactId>@<artifactId>my-app${i}</artifactId>@" pom.xml # If need to change artifactId
for i in {1..5000}; do
  sed -i.tmp -E "s@^  <version>.*</version>@  <version>1.${i}-SNAPSHOT</version>@" pom.xml
  mvn-deploy "${_REPO_URL}" "" "" "nexus" "" || break
done
EOF
function mvn-deploy() {
    local __doc__="Wrapper of mvn clean package deploy"
    local _alt_repo="${1}"
    local _remote_repo="${2}"
    local _local_repo="${3}"
    local _server_id="${4:-"nexus"}"
    local _options="${5-"-DskipTests -Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS -U -X"}"
    if [ -n "${_alt_repo}" ]; then
        _options="-DaltDeploymentRepository=${_server_id}::default::${_alt_repo} ${_options}"
    fi
    [ -n "${_local_repo}" ] && _options="${_options% } -Dmaven.repo.local=${_local_repo}"
    mvn `_mvn_settings "${_remote_repo}"` clean package deploy ${_options}
}

#mvn-arch-gen
#mvn-get-file "org.apache.httpcomponents:httpclient:4.5.13"
#mvn-dep-file httpclient-4.5.13.jar "com.example:my-app:1.0" "http://dh1.standalone.localdomain:8081/repository/maven-hosted/" "" "-Dclassifier=bin"
#Test: get_by_gav "com.example:my-app:1.0" "http://local.standalone.localdomain:8081/repository/repo_maven_hosted/"
function mvn-dep-file() {
    local __doc__="Wrapper of mvn deploy:deploy-file"
    local _file="${1}"
    local _gav="${2:-"com.example:my-app:1.0"}"
    local _remote_repo="$3" # mandatory
    local _server_id="${4:-"nexus"}"
    local _options="${5-"-Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS -U -X"}"

    if [[ "${_gav}" =~ ^" "*([^: ]+)" "*:" "*([^: ]+)" "*:" "*([^: ]+)" "*$ ]]; then
        local _g="${BASH_REMATCH[1]}"
        local _a="${BASH_REMATCH[2]}"
        local _v="${BASH_REMATCH[3]}"
        [ -n "${_remote_repo}" ] && _options="${_options% } -Durl=${_remote_repo}"
        [ -n "${_server_id}" ] && _options="${_options% } -DrepositoryId=${_server_id}"
        mvn `_mvn_settings "${_remote_repo}"` deploy:deploy-file -DgroupId=${_g} -DartifactId=${_a} -Dversion=${_v} -DgeneratePom=true -Dfile=${_file} ${_options}
    fi
}

# Get one jar (file) by GAV
function mvn-get-file() {
    local __doc__="It says mvn- but curl to get a single file with GAV."
    local _gav="${1:-"junit:junit:4.12"}"   # or org.yaml:snakeyaml:jar:1.23
    local _repo_url="${2:-"http://dh1.standalone.localdomain:8081/repository/maven-public/"}"
    local _user="${3:-"admin"}"
    local _pwd="${4:-"admin123"}"
    local _path=""
    if [[ "${_gav}" =~ ^" "*([^: ]+)" "*:" "*([^: ]+)" "*:" "*([^: ]+)" "*$ ]]; then
        local _g="${BASH_REMATCH[1]}"
        local _a="${BASH_REMATCH[2]}"
        local _v="${BASH_REMATCH[3]}"
        _path="$(echo "${_g}" | sed "s@\.@/@g")/${_a}/${_v}/${_a}-${_v}.jar"
    elif [[ "${_gav}" =~ ^" "*([^: ]+)" "*:" "*([^: ]+)" "*:" "*([^: ]+)" "*:" "*([^: ]+)" "*$ ]]; then
        local _g="${BASH_REMATCH[1]}"
        local _a="${BASH_REMATCH[2]}"
        local _v="${BASH_REMATCH[4]}"
        _path="$(echo "${_g}" | sed "s@\.@/@g")/${_a}/${_v}/${_a}-${_v}.jar"
    fi
    [ -z "${_path}" ] && return 11
    curl -v -O -J -L -f -u ${_user}:${_pwd} -k "${_repo_url%/}/${_path#/}" || return $?
    echo "$(basename "${_path}")"
}

# mvn devendency:get wrapper to use remote repo
function mvn-get() {
    local __doc__="Wrapper of mvn dependency:get"
    # maven/mvn get/download
    local _gav="${1:-"junit:junit:4.12"}"
    local _remote_repo="$2"
    local _local_repo="${3-"./local_repo"}"
    local _options="${4-"-Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS -Dtransitive=false -U -X"}"
    [ -n "${_local_repo}" ] && _options="${_options% } -Dmaven.repo.local=${_local_repo}"
    mvn `_mvn_settings "${_remote_repo}"` dependency:get -Dartifact=${_gav} ${_options}
}

function mvn-get-then-deploy() {
    local __doc__="Get a file with curl/mvn-get-file, then mvn deploy:deploy-file"
    local _gav="${1:-"junit:junit:4.12"}"
    local _get_repo="${2:-"http://localhost:8081/repository/maven-public/"}"
    local _dep_repo="${3:-"http://localhost:8081/repository/maven-snapshots/"}" # layout policy: strict may make request fail.
    local _is_snapshot="${4-"Y"}"
    local _file="$(mvn-get-file "${_gav}" "${_get_repo}")" || return $?
    if [ -n "${_file}" ]; then
        if [[ "${_is_snapshot}" =~ ^(y|Y) ]] && [[ ! "${_file}" =~ SNAPSHOT ]]; then
            mv ${_file} "$(basename ${_file} .jar)-SNAPSHOT.jar" || return $?
            _file="$(basename ${_file} .jar)-SNAPSHOT.jar"
            _gav="${_gav}-SNAPSHOT"
        fi
        mvn-dep-file "${_file}" "${_gav}" "${_dep_repo}"
    fi
}

function mvn-resolve() {
    local __doc__="Wrapper of mvn dependency:resolve (to resolve the dependencies)"
    # mvn devendency:resolve wrapper to use remote repo
    local _remote_repo="$1"
    local _local_repo="$2"
    local _options=""
    [ -n "${_local_repo}" ] && _options="${_options% } -Dmaven.repo.local=${_local_repo}"
    mvn `_mvn_settings "${_remote_repo}"` -Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS dependency:resolve ${_options} -U -X
}

# mvn devendency:tree wrapper to use remote repo (not tested)
function mvn-tree() {
    local __doc__="Wrapper of mvn dependency:tree (to display dependencies)"
    # maven/mvn resolve dependency only
    local _remote_repo="$1"
    local _local_repo="$2"
    local _options="-Dverbose"
    [ -n "${_local_repo}" ] && _options="${_options% } -Dmaven.repo.local=${_local_repo}"
    mvn `_mvn_settings "${_remote_repo}"` -Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS dependency:tree ${_options} -U -X
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
    echo "Using ${_settings_xml}..." >&2
    if [ -n "${_remote_repo}" ]; then
        # TODO: this substitute is not good
        sed -i.bak -E "s@<url>http.+/(content|repository)/.+</url>@<url>${_remote_repo}</url>@1" ${_settings_xml}
    fi
    echo "-s ${_settings_xml}"
}

# basically same as npm init -y but adding lodash 4.17.4 :-)
function npmInit() {
    local _name="${1:-"lodash-vulnerable"}"
    mkdir "${_name}"
    cd "${_name}"
    cat << EOF > ./package.json
{
  "name": "${_name}",
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

alias npmPublish='npmDeploy'
function npmDeploy() {
    local _repo_url="${1:-"http://localhost:8081/repository/npm-hosted/"}"
    local _name="${2:-"lodash-vulnerable"}"
    if [ ! -f ./package.json ]; then
        npmInit "${_name}" || return $?
    fi
    [ -f ./package.json.orig ] || cp -p ./package.json ./package.json.orig
    cat ./package.json | python -c "import sys,json;a=json.loads(sys.stdin.read());d={\"publishConfig\":{\"registry\":\"${_repo_url}\"}};a.update(d);f=open(\"./package.json\",\"w\");f.write(json.dumps(a,indent=4,sort_keys=True));" || return $?
    npm publish --registry "${_repo_url}" -ddd
}


### Misc.   #################################
#nxrm3Staging "yum-releases-prd" "test-tag" "repository=${_REPO_NAME_FROM}&name=adwaita-qt-common"
function nxrm3Staging() {
    local _move_to_repo="${1}"
    local _tag="${2}"
    local _search="${3}"
    local _nxrm3_url="${4:-"http://localhost:8081/"}"
    # tag may already exist, so not stopping if error
    if [ -n "${_tag}" ]; then
        echo "# ${_nxrm3_url%/}/service/rest/v1/tags" -d '{"name": "'${_tag}'"}'
        curl -v -u admin:admin123 -H "Content-Type: application/json" "${_nxrm3_url%/}/service/rest/v1/tags" -d '{"name": "'${_tag}'"}'
        echo ""
    fi
    if [ -n "${_search}" ]; then
        if [ -z "${_tag}" ] || [ -z "${_move_to_repo}" ]; then
            echo "# ${_nxrm3_url%/}/service/rest/v1/search?${_search}"
            curl -u admin:admin123 -X GET "${_nxrm3_url%/}/service/rest/v1/search?${_search}"
            echo ""
            return
        fi
        echo "# ${_nxrm3_url%/}/service/rest/v1/tags/associate/${_tag}?${_search}"
        curl -v -f -u admin:admin123 -X POST "${_nxrm3_url%/}/service/rest/v1/tags/associate/${_tag}?${_search}" || return $?
        echo ""
        # NOTE: immediately moving fails with 404
        sleep 5
    fi
    echo "# ${_nxrm3_url%/}/service/rest/v1/staging/move/${_move_to_repo}?tag=${_tag}"
    curl -v -f -u admin:admin123 -X POST "${_nxrm3_url%/}/service/rest/v1/staging/move/${_move_to_repo}?tag=${_tag}" || return $?
    echo ""
}

# NOTE: filter the output before passing function would be faster
#zgrep "2021:10:1" request-2021-01-08.log.gz | replayGets "/nexus/content/repositories/central/([^/]+/.+)" "http://localhost:8081/repository/maven-central"
#rg -z "2021:\d\d:\d.+ \"GET /repository/maven-central/" request-2021-01-08.log.gz | replayGets "/repository/maven-central/([^/]+/.+)" "http://dh1:8081/repository/maven-central/"
function replayGets() {
    local _path_match="$1"  # Need (...) eg: "/nexus/content/repositories/central/([^/]+/.+)"
    local _url_path="$2"    # http://localhost:8081/repository/maven-central
    [[ "${_url_path}" =~ ^http ]] || return 1
    [[ "${_path_match}" =~ .*\(.+\).* ]] || return 2
    # rg is easier and faster but for the portability ...
    sed -nE "s|.+\"GET ${_path_match} HTTP/[0-9.]+\" 2[0-9][0-9].+|${_url_path%/}/\1|p" | sort | uniq | xargs -n1 -P4 -I {} curl -sf --head -o /dev/null -w "%{http_code} {}\n" "{}"
}
