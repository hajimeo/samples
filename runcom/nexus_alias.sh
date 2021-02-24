# source <(curl https://raw.githubusercontent.com/hajimeo/samples/master/runcom/nexus_alias.sh --compressed)

if [ -z "${_WORK_DIR}" ]; then
    if [ "`uname`" = "Darwin" ]; then
        _WORK_DIR="$HOME/share"
    else
        _WORK_DIR="/var/tmp/share"
    fi
fi


[ -s $HOME/IdeaProjects/nexus-toolbox/analyzer/analyze.py ] && alias sptZip="python3 $HOME/IdeaProjects/nexus-toolbox/analyzer/analyze.py"
#[ -s $HOME/IdeaProjects/nexus-toolbox/scripts/analyze-nexus3-support-zip.py ] && alias sptZip3="python3 $HOME/IdeaProjects/nexus-toolbox/scripts/analyze-nexus3-support-zip.py"
#[ -s $HOME/IdeaProjects/nexus-toolbox/scripts/analyze-nexus2-support-zip.py ] && alias sptZip2="python3 $HOME/IdeaProjects/nexus-toolbox/scripts/analyze-nexus2-support-zip.py"
[ -s $HOME/IdeaProjects/nexus-toolbox/scripts/dump_nxrm3_groovy_scripts.py ] && alias sptDumpScript="python3 $HOME/IdeaProjects/nexus-toolbox/scripts/dump_nxrm3_groovy_scripts.py"
[ -s $HOME/IdeaProjects/samples/misc/blobpath.jar ] && alias blobpath="java -jar $HOME/IdeaProjects/samples/misc/blobpath.jar"


# Start iq CLI
function iqCli() {
    local __doc__="https://help.sonatype.com/integrations/nexus-iq-cli#NexusIQCLI-Parameters"
    local _path="${1:-"./"}"
    # overwrite-able global variables
    local _iq_app_id="${2:-${_IQ_APP_ID:-"sandbox-application"}}"
    local _iq_stage="${3:-${_IQ_STAGE:-"build"}}" #develop|build|stage-release|release|operate
    local _iq_url="${4:-${_IQ_URL}}"
    local _iq_cli_ver="${5:-${_IQ_CLI_VER:-"1.95.0-01"}}"
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
    local _cmd="java -Djava.io.tmpdir=\"${_iq_tmp}\" -jar ${_iq_cli_jar} -s ${_iq_url} -a 'admin:admin123' -i ${_iq_app_id} -t ${_iq_stage} -r \"${_iq_tmp%/}/iq_result_$(date +'%Y%m%d%H%M%S').json\" -X ${_path}"
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

function iqHds() {
    local _component_identifier="$1"    # {"format":"pypi","coordinates":{"extension":"zip","name":"apache-beam","qualifier":"","version":"2.8.0"}}
    local _fp="${2:-"${_NEXUS_FP}"}"    #~/.bashrc
    [ -z "${_fp}" ] && return 11
    if [[ "${_component_identifier}" =~ ^([^:]+):([^:]+):([^:]+)$ ]]; then
        # NOTE: do not need to do ${BASH_REMATCH[1]//.//}
        _component_identifier="{\"format\":\"maven\",\"coordinates\":{\"groupId\":\"${BASH_REMATCH[1]}\",\"artifactId\":\"${BASH_REMATCH[2]}\",\"version\":\"${BASH_REMATCH[3]}\",\"classifier\":\"\",\"extension\":\"jar\"}}"
    elif [[ "${_component_identifier}" =~ ^([^ ]+)" "\(([^\)]+)\)" "([^ ]+)" "\(\.(whl)\)$ ]]; then
        #pymongo (cp26-cp26mu-manylinux1_x86_64) 3.6.1 (.whl)
        _component_identifier="{\"format\":\"pypi\",\"coordinates\":{\"name\":\"${BASH_REMATCH[1]}\",\"qualifier\":\"${BASH_REMATCH[2]}\",\"version\":\"${BASH_REMATCH[3]}\",\"extension\":\"${BASH_REMATCH[4]}\"}}"
    fi
    local _curl_opt="-sf"
    [[ "${_DEBUG}" =~ ^(y|Y) ]] && _curl_opt="-fv"
    curl ${_curl_opt} -H "X-CLM-Token: ${_fp}" "https://clm.sonatype.com/rest/ci/componentDetails" \
        -G --data-urlencode "componentIdentifier=${_component_identifier}" | python -m json.tool
}

function sptBoot() {
    local _zip="${1}"
    local _opts="${2}"    # If empty and NXRM, using "--noboot --convert-repos" (not --remote-debug)
    pyv

    [ -s $HOME/IdeaProjects/nexus-toolbox/support-zip-booter/boot_support_zip.py ] || return 1
    if [ -z "${_zip}" ]; then
        _zip="$(ls -1 ./*-202?????-??????*.zip | tail -n1)" || return $?
        echo "# Using ${_zip} ..."
    fi

    # some mods for HTTPS
    if [ ! -s $HOME/.nexus_executable_cache/ssl/keystore.jks.orig ]; then
        echo "# Replacing keystore.jks ..."
        mv $HOME/.nexus_executable_cache/ssl/keystore.jks $HOME/.nexus_executable_cache/ssl/keystore.jks.orig
        cp $HOME/IdeaProjects/samples/misc/standalone.localdomain.jks $HOME/.nexus_executable_cache/ssl/keystore.jks
        echo "# Append 'local.standalone.localdomain' in 127.0.0.1 line in /etc/hosts."
    fi

    local _dir="./$(basename "${_zip}" .zip)_tmp"
    if [ ! -d "${_dir}" ]; then
        local _final_opts="${_opts}"
        if unzip -t "${_zip}" | grep -q config.yml; then
            # My iqStart does not work with "--noboot" because without boot, not loading any json files, so currently if IQ, may need to clear _opts
            #_final_opts=""
            echo "Probably IQ ..."
        elif [ -z "${_opts}" ]; then
            # If empty and NXRM, using "--noboot --convert-repos"
            _final_opts="--noboot --convert-repos"
        fi
        python3 $HOME/IdeaProjects/nexus-toolbox/support-zip-booter/boot_support_zip.py ${_final_opts} "${_zip}" "${_dir}" || return $?
    else
        echo "# ${_dir} already exists. so just starting ..."
    fi

    if [[ "${_opts}" =~ noboot ]]; then
        echo "# 'noboot' is specified, so not starting ..."
        return
    fi

    local _nxiq="$(ls -d1 ${_dir%/}/nexus-iq-server-1* | tail -n1)"
    if [ -n "${_nxiq}" ]; then
        iqStart "${_dir}" ""
    else
        # Mods for NXRM2 HTTPS/SSL/TLS
        local _nxrm2="$(ls -d1 ${_dir%/}/nexus-professional-2* | tail -n1)"
        if [ -d "${_nxrm2%/}/conf" ] && [ ! -d "${_nxrm2%/}/conf/ssl" ] && [ -s $HOME/.nexus_executable_cache/ssl/keystore.jks ]; then
            mkdir "${_nxrm2%/}/conf/ssl"
            cp $HOME/.nexus_executable_cache/ssl/keystore.jks ${_nxrm2%/}/conf/ssl/

            if [ ! -s "${_nxrm2%/}/conf/jetty-https.xml.orig" ]; then
                cp -p "${_nxrm2%/}/conf/jetty-https.xml" "${_nxrm2%/}/conf/jetty-https.xml.orig"
            fi
            sed -i.bak 's/OBF:1v2j1uum1xtv1zej1zer1xtn1uvk1v1v/password/g' "${_nxrm2%/}/conf/jetty-https.xml"
            if ! grep -q 'wrapper.app.parameter.3' "${_nxrm2%/}/bin/jsw/conf/wrapper.conf"; then
                if type _sed &>/dev/null; then
                    _sed -i.bak '/wrapper.app.parameter.2/a wrapper.app.parameter.3=./conf/jetty-https.xml' "${_nxrm2%/}/bin/jsw/conf/wrapper.conf"
                elif which gsed &>/dev/null; then
                    gsed -i.bak '/wrapper.app.parameter.2/a wrapper.app.parameter.3=./conf/jetty-https.xml' "${_nxrm2%/}/bin/jsw/conf/wrapper.conf"
                else
                    sed -i.bak '/wrapper.app.parameter.2/a wrapper.app.parameter.3=./conf/jetty-https.xml' "${_nxrm2%/}/bin/jsw/conf/wrapper.conf"
                fi
            fi
            grep -q "application-port-ssl" "${_nxrm2%/}/conf/nexus.properties" || echo "application-port-ssl=8443" >> "${_nxrm2%/}/conf/nexus.properties"
        fi
        #export INSTALL4J_ADD_VM_PARAMS="-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005"
        nxrmStart "${_dir}" ""
    fi
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

    local _nexus_data="/var/tmp/share/sonatype/${_name}-data"
    if [ ! -d "${_nexus_data%/}" ]; then
        mkdir -p -m 777 "${_nexus_data%/}" || return $?
    fi
    local _opts="--name=${_name}"
    [ -n "${INSTALL4J_ADD_VM_PARAMS}" ] && _opts="${_opts} -e INSTALL4J_ADD_VM_PARAMS=\"${INSTALL4J_ADD_VM_PARAMS}\""
    [ -d /var/tmp/share ] && _opts="${_opts} -v /var/tmp/share:/var/tmp/share"
    [ -d "${_nexus_data%/}" ] && _opts="${_opts} -v ${_nexus_data%/}:/nexus-data"
    [ -n "${_extra_opts}" ] && _opts="${_opts} ${_extra_opts}"  # Should be last to overwrite
    local _cmd="docker run -d -p ${_port}:8081 -p ${_port_ssl}:8443 ${_opts} sonatype/nexus3:${_tag}"
    echo "${_cmd}"
    eval "${_cmd}"
}

# To start local (on Mac) IQ server
function iqStart() {
    local _base_dir="${1:-"."}"
    local _java_opts=${2-"-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005"}
    #local _java_opts=${@:2}
    local _jar_file="$(realpath "$(find ${_base_dir%/} -maxdepth 1 -type f -name 'nexus-iq-server*.jar' 2>/dev/null | sort | tail -n1)")"
    [ -z "${_jar_file}" ] && return 11
    local _cfg_file="$(realpath "$(dirname "${_jar_file}")/config.yml")"
    [ -z "${_cfg_file}" ] && return 12
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

    local _nexus_data="/var/tmp/share/sonatype/${_name}-data"
    [ ! -d "${_nexus_data%/}" ] && mkdir -p -m 777 "${_nexus_data%/}"
    [ ! -d "${_nexus_data%/}/etc" ] && mkdir -p -m 777 "${_nexus_data%/}/etc"
    [ ! -d "${_nexus_data%/}/log" ] && mkdir -p -m 777 "${_nexus_data%/}/log"
    local _opts="--name=${_name}"
    local _java_opts=""
    [ -z "${_license}" ] && [ -d /var/tmp/share/sonatype ] && _license="$(ls -1t /var/tmp/share/sonatype/*.lic 2>/dev/null | head -n1)"
    [ -s "${_license}" ] && _java_opts="-Ddw.licenseFile=${_license}"
    [ -n "${JAVA_OPTS}" ] && _java_opts="${_java_opts} ${JAVA_OPTS}"
    [ -n "${_java_opts}" ] && _opts="${_opts} -e JAVA_OPTS=\"${_java_opts}\""
    [ -d /var/tmp/share ] && _opts="${_opts} -v /var/tmp/share:/var/tmp/share"
    [ -d "${_nexus_data%/}" ] && _opts="${_opts} -v ${_nexus_data%/}:/sonatype-work"
    [ -s "${_nexus_data%/}/etc/config.yml" ] && _opts="${_opts} -v ${_nexus_data%/}/etc:/etc/nexus-iq-server"
    [ -d "${_nexus_data%/}/log" ] && _opts="${_opts} -v ${_nexus_data%/}/log:/var/log/nexus-iq-server"
    [ -d "${_nexus_data%/}/log" ] && _opts="${_opts} -v ${_nexus_data%/}/log:/opt/sonatype/nexus-iq-server/log" # due to audit.log => fixed from v104
    [ -n "${_extra_opts}" ] && _opts="${_opts} ${_extra_opts}"  # Should be last to overwrite
    local _cmd="docker run -d -p ${_port}:8070 -p ${_port2}:8071 -p ${_port_ssl}:8444 ${_opts} sonatype/nexus-iq-server:${_tag}"
    echo "${_cmd}"
    eval "${_cmd}"
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
        mvn `_mvn_settings "${_remote_repo}"` archetype:generate -DgroupId=${_g} -DartifactId=${_a} -DarchetypeArtifactId=${_type} -DarchetypeVersion=${_v} -DinteractiveMode=false ${_options}
    fi
}

function mvn-add-snapshot-repo-in-pom() {
    # TODO:
  echo "<distributionManagement>
    <snapshotRepository>
      <id>nexus</id>
      <name>maven-snapshots</name>
      <url>https://local.standalone.localdomain:8443/repository/snapshots/</url>
    </snapshotRepository>
  </distributionManagement>"
}

function mvn-publish() {
    local _remote_repo="${1}"
    local _local_repo="${2}"
    local _options="${3-"-Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS -U -X"}"
    [ -n "${_local_repo}" ] && _options="${_options% } -Dmaven.repo.local=${_local_repo}"
    mvn `_mvn_settings "${_remote_repo}"` clean package ${_options}
}

# Example to generate 10 versions / snapshots (NOTE: in bash heredoc, 'EOF' and just EOF is different)
: <<'EOF'
mvn-arch-gen; cd my-app
_REPO_URL="http://node3290.standalone.localdomain:8081/repository/maven-hosted/"
#mvn-deploy "${_REPO_URL}" "" "nexus"
  #sed -i.tmp -E "s@<groupId>com.example.*</groupId>@<groupId>com.example${i}</groupId>@" pom.xml   # If need to change groupId
  #sed -i.tmp -E "s@<artifactId>my-app.*</artifactId>@<artifactId>my-app${i}</artifactId>@" pom.xml # If need to change artifactId
for i in {1..5000}; do
  sed -i.tmp -E "s@^  <version>.*</version>@  <version>1.${i}-SNAPSHOT</version>@" pom.xml
  mvn-deploy "${_REPO_URL}" "" "nexus" "" || break
done
EOF
function mvn-deploy() {
    local __doc__="https://stackoverflow.com/questions/13547358/maven-deploydeploy-using-daltdeploymentrepository"
    local _alt_repo="${1}"
    local _remote_repo="${2}"
    local _server_id="${3:-"nexus"}"
    local _options="${4-"-Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS -U -X"}"
    if [ -n "${_alt_repo}" ]; then
        _options="-DaltDeploymentRepository=${_server_id}::default::${_alt_repo} ${_options}"
    fi
    #[ -n "${_local_repo}" ] && _options="${_options% } -Dmaven.repo.local=${_local_repo}"
    mvn `_mvn_settings "${_remote_repo}"` clean package deploy ${_options}
}

# mvn archetype:generate wrapper to use a remote repo
#mvn-dep-file httpclient-4.5.1.jar "com.example:my-app:1.0" "http://local.standalone.localdomain:8081/repository/maven-hosted/"
#Test: get_by_gav "com.example:my-app:1.0" "http://local.standalone.localdomain:8081/repository/repo_maven_hosted/"
function mvn-dep-file() {
    local __doc__="https://maven.apache.org/plugins/maven-deploy-plugin/usage.html"
    local _file="${1}"
    local _gav="${2:-"com.example:my-app:1.0"}"
    local _remote_repo="$3"
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
    local _gav="${1:-"junit:junit:4.12"}"
    local _repo_url="${2:-"http://dh1.standalone.localdomain:8081/repository/maven-public/"}"
    local _user="${3:-"admin"}"
    local _pwd="${4:-"admin123"}"
    if [[ "${_gav}" =~ ^" "*([^: ]+)" "*:" "*([^: ]+)" "*:" "*([^: ]+)" "*$ ]]; then
        local _g="${BASH_REMATCH[1]}"
        local _a="${BASH_REMATCH[2]}"
        local _v="${BASH_REMATCH[3]}"
        local _path="$(echo "${_g}" | sed "s@\.@/@g")/${_a}/${_v}/${_a}-${_v}.jar"

        curl -v -O -J -L -f -u ${_user}:${_pwd} -k "${_repo_url%/}/${_path#/}" || return $?
        echo "$(basename "${_path}")"
    fi
}

# mvn devendency:get wrapper to use remote repo
function mvn-get() {
    # maven/mvn get/download
    local _gav="${1:-"junit:junit:4.12"}"
    local _remote_repo="$2"
    local _local_repo="${3-"./local_repo"}"
    local _options="${4-"-Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS -Dtransitive=false -U -X"}"
    [ -n "${_local_repo}" ] && _options="${_options% } -Dmaven.repo.local=${_local_repo}"
    mvn `_mvn_settings "${_remote_repo}"` dependency:get -Dartifact=${_gav} ${_options}
}

function mvn-get-then-deploy() {
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

# mvn devendency:resolve wrapper to use remote repo
function mvn-resolve() {
    # maven/mvn resolve dependency only
    local _remote_repo="$1"
    local _local_repo="$2"
    local _options=""
    [ -n "${_local_repo}" ] && _options="${_options% } -Dmaven.repo.local=${_local_repo}"
    mvn `_mvn_settings "${_remote_repo}"` -Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS dependency:resolve ${_options} -U -X
}

# mvn devendency:tree wrapper to use remote repo (not tested)
function mvn-tree() {
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
