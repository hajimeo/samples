#_import() { curl -sf --compressed "https://raw.githubusercontent.com/hajimeo/samples/master/$1" -o /tmp/_i;. /tmp/_i; }
#_import "runcom/nexus_alias.sh"

# For identifying elasticsearch directory name for repository
alias hashUnencodedChars='python3 -c "import sys,hashlib; print(hashlib.sha1(sys.argv[1].encode(\"utf-16-le\")).hexdigest())"'
alias esIndexName=hashUnencodedChars


if [ -z "${_WORK_DIR%/}" ]; then
    if [ "`uname`" = "Darwin" ]; then
        # dovker -v does not work with symlink
        _WORK_DIR="$HOME/share"
    else
        _WORK_DIR="/var/tmp/share"
    fi
fi

function _get_iq_url() {
    local _iq_url="${1:-${_IQ_URL}}"
    if [ -z "${_iq_url}" ]; then
        for _url in "http://localhost:8070/" "https://nxiq-k8s.standalone.localdomain/" "http://dh1:8070/"; do
            if curl -f -s -I "${_url%/}/" &>/dev/null; then
                echo "${_url%/}/"
                return
            fi
        done
        return 1
    fi
    if [[ ! "${_iq_url}" =~ ^https?://.+ ]]; then
        if [[ ! "${_iq_url}" =~ .+:[0-9]+ ]]; then   # Provided hostname only
            _iq_url="http://${_iq_url%/}:8070/"
        else
            _iq_url="http://${_iq_url%/}/"
        fi
    fi
    echo "${_iq_url}"
}

# Start iq CLI
# To debug, use suspend=y
#JAVA_TOOL_OPTIONS="-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=5007" iqCli
function iqCli() {
    local __doc__="https://help.sonatype.com/integrations/nexus-iq-cli#NexusIQCLI-Parameters"
    local _path="${1:-"./"}"
    # overwrite-able global variables
    local _iq_app_id="${2:-${_IQ_APP_ID:-"sandbox-application"}}"
    local _iq_stage="${3:-${_IQ_STAGE:-"build"}}" #develop|build|stage-release|release|operate
    local _iq_url="${4:-${_IQ_URL}}"
    local _iq_cli_ver="${5:-${_IQ_CLI_VER:-"1.140.0-01"}}"
    local _iq_cli_opt="${6:-${_IQ_CLI_OPT}}"    # -D fileIncludes="**/package-lock.json"
    local _iq_cli_jar="${_IQ_CLI_JAR:-"${_WORK_DIR%/}/sonatype/iq-cli/nexus-iq-cli-${_iq_cli_ver}.jar"}"

    _iq_url="$(_get_iq_url "${_iq_url}")" || return $?
    #[ ! -d "${_iq_tmp}" ] && mkdir -p "${_iq_tmp}"

    if [ ! -s "${_iq_cli_jar}" ]; then
        #local _tmp_iq_cli_jar="$(find ${_WORK_DIR%/}/sonatype -name 'nexus-iq-cli*.jar' 2>/dev/null | sort -r | head -n1)"
        local _cli_dir="$(dirname "${_iq_cli_jar}")"
        [ ! -d "${_cli_dir}" ] && mkdir -p "${_cli_dir}"
        if [ -s "$HOME/.nexus_executable_cache/nexus-iq-server-${_iq_cli_ver}-bundle.tar.gz" ]; then
            tar -xvf $HOME/.nexus_executable_cache/nexus-iq-server-${_iq_cli_ver}-bundle.tar.gz -C "${_cli_dir}" nexus-iq-cli-${_iq_cli_ver}.jar || return $?
        else
            curl -f -L "https://download.sonatype.com/clm/scanner/nexus-iq-cli-${_iq_cli_ver}.jar" -o "${_iq_cli_jar}" || return $?
        fi
    fi
    # NOTE: -X/--debug outputs to STDOUT
    #       Mac uses "TMPDIR" (and can't change), which is like java.io.tmpdir = /var/folders/ct/cc2rqp055svfq_cfsbvqpd1w0000gn/T/ + nexus-iq
    local _cmd="java -jar ${_iq_cli_jar} ${_iq_cli_opt} -s ${_iq_url} -a 'admin:admin123' -i ${_iq_app_id} -t ${_iq_stage} -r iq_result.json -X ${_path}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Executing: ${_cmd}" >&2
    eval "${_cmd}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Completed. (curl -u admin:admin123 ${_iq_url%/}/api/v2/applications/${_iq_app_id}/reports/{REPORT_ID}/raw | python -m json.tool > raw.json)" >&2
}

# Start "mvn" with IQ plugin
function iqMvn() {
    local __doc__="https://help.sonatype.com/display/NXI/Sonatype+CLM+for+Maven"
    # overwrite-able global variables
    local _iq_app_id="${1:-${_IQ_APP_ID:-"sandbox-application"}}"
    local _iq_stage="${2:-${_IQ_STAGE:-"build"}}" #develop|build|stage-release|release|operate
    local _iq_url="${3:-${_IQ_URL}}"
    local _file="${4:-"."}"
    local _mvn_opts="${5:-"-X"}"    # no -U
    #local _iq_tmp="${_IQ_TMP:-"./iq-tmp"}" # does not generate anything

    local _iq_mvn_ver="${_IQ_MVN_VER}"  # empty = latest
    [ -n "${_iq_mvn_ver}" ] && _iq_mvn_ver=":${_iq_mvn_ver}"
    _iq_url="$(_get_iq_url "${_iq_url}")" || return $?

    #clm-maven-plugin:2.30.2-01:index
    local _cmd="mvn -f ${_file} com.sonatype.clm:clm-maven-plugin${_iq_mvn_ver}:evaluate -Dclm.serverUrl=${_iq_url} -Dclm.applicationId=${_iq_app_id} -Dclm.stage=${_iq_stage} -Dclm.username=admin -Dclm.password=admin123 -Dclm.resultFile=iq_result.json -Dclm.scan.dirExcludes=\"**/BOOT-INF/lib/**\" ${_mvn_opts}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Executing: ${_cmd}" >&2
    eval "${_cmd}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Completed." >&2
}

# To start local (on Mac) NXRM2 or NXRM3 server
function nxrmStart() {
    local _base_dir="${1:-"."}"
    local _java_opts=${2-"-agentlib:jdwp=transport=dt_socket,server=y,address=5005,suspend=n"}
    local _mode=${3} # if NXRM2, not 'run' but 'console'
    #local _java_opts=${@:2}
    _base_dir="$(realpath "${_base_dir}")"
    local _nexus_file="${_base_dir%/}/nexus/bin/nexus"
    [ -s "${_nexus_file}" ] || _nexus_file="$(find ${_base_dir%/} -maxdepth 4 -path '*/bin/*' -type f -name 'nexus' 2>/dev/null | sort | tail -n1)"
    local _nexus_vmopt="$(find ${_base_dir%/} -maxdepth 4 -path '*/bin/*' -type f -name 'nexus.vmoptions' 2>/dev/null | sort | tail -n1)"
    local _sonatype_work="$(find ${_base_dir%/} -maxdepth 4 -path '*/sonatype-work/*' -type d \( -name 'nexus3' -o -name 'nexus2' -o -name 'nexus' \) 2>/dev/null | grep -v -w elasticsearch | sort | tail -n1)"
    if [ -z "${_sonatype_work%/}" ]; then
        echo "This function requires sonatype-work/{nexus|nexus3}"
        return 1
    fi
    local _version="$(basename "$(dirname "$(dirname "$(realpath "${_nexus_file}")")")")"
    local _jetty_https="$(find ${_base_dir%/} -maxdepth 4 -path '*/etc/*' -type f -name 'jetty-https.xml' 2>/dev/null | sort | tail -n1)"
    local _logback_overrides="$(find ${_base_dir%/} -maxdepth 4 -path '*/etc/logback/*' -type f -name 'logback-overrides.xml' 2>/dev/null | sort | tail -n1)"
    local _cfg_file="${_sonatype_work%/}/etc/nexus.properties"
    if [ -n "${_nexus_vmopt}" ]; then   # This means NXRM3
        # To avoid 'Caused by: java.lang.IllegalStateException: Insufficient configured threads' https://support.sonatype.com/hc/en-us/articles/360000744687-Understanding-Eclipse-Jetty-9-4-Thread-Allocation#ReservedThreadExecutor
        grep -qE -- '^\s*-XX:ActiveProcessorCount=' "${_nexus_vmopt}" || echo "-XX:ActiveProcessorCount=2" >> "${_nexus_vmopt}"

        #nexus.licenseFile=/var/tmp/share/sonatype/sonatype-*.lic
        if [ ! -d "${_sonatype_work%/}/etc" ]; then
            mkdir -p "${_sonatype_work%/}/etc"
        fi
        [ -n "${_cfg_file}" ] && _updateNexusProps "${_cfg_file}"
        [ -z "${_mode}" ] && _mode="run"
    else    # if NXRM2
        [ -z "${_mode}" ] && _mode="console"
        # jvm 1    | Caused by: java.lang.ClassNotFoundException: org.eclipse.tycho.nexus.internal.plugin.UnzipRepository
        #https://repo1.maven.org/maven2/org/eclipse/tycho/nexus/unzip-repository-plugin/0.14.0/unzip-repository-plugin-0.14.0-bundle.zip
        echo "NOTE: May need to 'unzip -d ${_base_dir%/}/sonatype-work/nexus/plugin-repository $HOME/Downloads/unzip-repository-plugin-0.14.0-bundle.zip'"
        # jvm 1    | Caused by: java.lang.ClassNotFoundException: org.codehaus.janino.ScriptEvaluator
        #./sonatype-work/nexus/conf/logback-nexus.xml
        #[ -n "${_java_opts}" ] && export JAVA_TOOL_OPTIONS="${_java_opts}"
    fi
    if [ -n "${_jetty_https}" ] && [[ "${_version}" =~ 3\.26\.+ ]]; then
        # @see: https://issues.sonatype.org/browse/NEXUS-24867
        sed -i.bak 's@class="org.eclipse.jetty.util.ssl.SslContextFactory"@class="org.eclipse.jetty.util.ssl.SslContextFactory$Server"@g' ${_jetty_https}
    fi
    # Currently i'm not using.
    if false && [ -s "${_logback_overrides}" ]; then
        echo "$(grep -vE "(org.sonatype.nexus.orient.explain|</included>)" ${_logback_overrides})
  <logger name='org.sonatype.nexus.orient.explain' level='TRACE'/>
</included>" > ${_logback_overrides}
    fi
    # For java options, latter values are used, so appending
    INSTALL4J_ADD_VM_PARAMS="-XX:-MaxFDLimit ${INSTALL4J_ADD_VM_PARAMS} ${_java_opts}" ${_nexus_file} ${_mode}
    # ulimit: https://help.sonatype.com/repomanager3/installation/system-requirements#SystemRequirements-MacOSX
}

function _updateNexusProps() {
    local _cfg_file="$1"
    touch ${_cfg_file}
    grep -qE '^\s*nexus.security.randompassword' "${_cfg_file}" || echo "nexus.security.randompassword=false" >> "${_cfg_file}"
    grep -qE '^\s*nexus.onboarding.enabled' "${_cfg_file}" || echo "nexus.onboarding.enabled=false" >> "${_cfg_file}"
    grep -qE '^\s*nexus.scripts.allowCreation' "${_cfg_file}" || echo "nexus.scripts.allowCreation=true" >> "${_cfg_file}"
    grep -qE '^\s*nexus.browse.component.tree.automaticRebuild' "${_cfg_file}" || echo "nexus.browse.component.tree.automaticRebuild=false" >> "${_cfg_file}"
    # NOTE: this would not work if elasticsearch directory is empty
    grep -qE '^\s*nexus.elasticsearch.autoRebuild' "${_cfg_file}" || echo "nexus.elasticsearch.autoRebuild=false" >> "${_cfg_file}"
    # ${nexus.h2.httpListenerPort:-8082} jdbc:h2:file:./nexus (no username)
    grep -qE '^\s*nexus.h2.httpListenerEnabled' "${_cfg_file}" || echo "nexus.h2.httpListenerEnabled=true" >> "${_cfg_file}"
    # Binary (or HA-C) connect remote:hostname/component admin admin
    grep -qE '^\s*nexus.orient.binaryListenerEnabled' "${_cfg_file}" || echo "nexus.orient.binaryListenerEnabled=true" >> "${_cfg_file}"
    # For OrientDB studio (hostname:2480/studio/index.html)
    grep -qE '^\s*nexus.orient.httpListenerEnabled' "${_cfg_file}" || echo "nexus.orient.httpListenerEnabled=true" >> "${_cfg_file}"
    grep -qE '^\s*nexus.orient.dynamicPlugins' "${_cfg_file}" || echo "nexus.orient.dynamicPlugins=true" >> "${_cfg_file}"
}

function _prepare_install() {
    local _type="$1"
    local _tgz="$2"

    local _dirname="${_type}_${_ver}"
    [ -n "${_dbname}" ] && _dirname="${_dirname}_${_dbname}"
    local _extractTar=true
    if [ -d "${_dirname}" ]; then
        echo "WARN ${_dirname} exists. Will just update the settings..."
        sleep 5
        _extractTar=false
    else
        if [ ! -s "${_tgz}" ]; then
            echo "no ${_tgz}"
            return 1
        fi
        mkdir -v "${_dirname}" || return $?
    fi

    cd "${_dirname}" || return $?
    if ${_extractTar}; then
        tar -xvf ${_tgz} || return $?
    fi
}

function nxrmInstall() {
    local _ver="$1" #3.40.1-01
    local _dbname="$2"  # If h2, use H2
    local _dbusr="${3:-"${_dbname}"}"
    local _dbpwd="${4:-"${_dbusr}123"}"
    local _port="${5:-"8081"}"
    local _installer_dir="${6:-"$HOME/.nexus_executable_cache"}"

    local _os="linux"
    [ "`uname`" = "Darwin" ] && _os="mac"

    if [ ! -s "${_installer_dir%/}/license/nexus.lic" ]; then
        echo "no ${_installer_dir%/}/license/nexus.lic"
        return 1
    fi

    _prepare_install "nxrm" "${_installer_dir%/}/nexus-${_ver}-${_os}.tgz" || return $?

    if [ ! -d ./sonatype-work/nexus3/etc/fabric ]; then
        mkdir -v -p ./sonatype-work/nexus3/etc/fabric || return $?
    fi
    local _prop="./sonatype-work/nexus3/etc/nexus.properties"
    for _l in "nexus.licenseFile=${_installer_dir%/}/license/nexus.lic" "application-port=${_port}" "nexus.security.randompassword=false" "nexus.onboarding.enabled=false" "nexus.scripts.allowCreation=true"; do
        grep -q "^${_l%=*}" "${_prop}" 2>/dev/null || echo "${_l}" >> "${_prop}" || return $?
    done
    if [ -n "${_dbname}" ]; then
        grep -q "^nexus.datastore.enabled" "${_prop}" 2>/dev/null || echo "nexus.datastore.enabled=true" >> "${_prop}" || return $?
        if [[ ! "${_dbname}" =~ [hH]2 ]]; then
            cat << EOF > ./sonatype-work/nexus3/etc/fabric/nexus-store.properties
jdbcUrl=jdbc\:postgresql\://$(hostname -f)\:5432/${_dbname}
username=${_dbusr}
password=${_dbpwd}
maximumPoolSize=40
advanced=maxLifetime\=600000
EOF
            local _util_dir="$(dirname "$(dirname "$BASH_SOURCE")")/bash"
            if [ -s "${_util_dir}/utils_db.sh" ]; then
                source ${_util_dir}/utils.sh
                source ${_util_dir}/utils_db.sh
                _postgresql_create_dbuser "${_dbusr}" "${_dbpwd}" "${_dbname}"
            else
                echo "WARN Not creating database"
            fi
        fi
    fi

    #nxrmStart
    echo "To start: ./nexus-${_ver}/bin/nexus run"
}

#nxrmDocker "nxrm3-test" "" "8181" "8543" #"--read-only -v /tmp/nxrm3-test:/tmp" or --tmpfs /tmp:noexec
#docker run --init -d -p 8081:8081 -p 8443:8443 --name=nxrm3docker --tmpfs /tmp:noexec -e INSTALL4J_ADD_VM_PARAMS="-Dssl.etc=\${karaf.data}/etc/ssl -Dnexus-args=\${jetty.etc}/jetty.xml,\${jetty.etc}/jetty-https.xml,\${jetty.etc}/jetty-requestlog.xml -Dapplication-port-ssl=8443 -Djava.util.prefs.userRoot=/nexus-data" -v /var/tmp/share:/var/tmp/share -v /var/tmp/share/sonatype/nxrm3-data:/nexus-data dh1.standalone.localdomain:5000/sonatype/nexus3:latest
# export INSTALL4J_ADD_VM_PARAMS="-XX:ActiveProcessorCount=2 -Xms2g -Xmx2g -XX:MaxDirectMemorySize=2g -XX:+PrintGC -XX:+PrintGCDateStamps -Dnexus.licenseFile=/var/tmp/share/sonatype/sonatype-license.lic"
# export INSTALL4J_ADD_VM_PARAMS="-XX:ActiveProcessorCount=2 -Xms2g -Xmx2g -XX:MaxDirectMemorySize=2g -Dnexus.licenseFile=/var/tmp/share/sonatype/sonatype-license.lic -Dnexus.datastore.enabled=true -Dnexus.datastore.nexus.jdbcUrl=jdbc\:postgresql\://localhost/nxrm?ssl=true&sslmode=require -Dnexus.datastore.nexus.username=nxrm -Dnexus.datastore.nexus.password=nxrm123 -Dnexus.datastore.nexus.maximumPoolSize=10 -Dnexus.datastore.nexus.advanced=maxLifetime=600000"
function nxrmDocker() {
    local _name="${1:-"nxrm3"}"
    local _tag="${2:-"latest"}"
    local _port="${3:-"8081"}"
    local _port_ssl="${4:-"8443"}"
    local _extra_opts="${5}"    # this is docker options not INSTALL4J_ADD_VM_PARAMS
    local _work_dir="${_WORK_DIR:-"/var/tmp/share"}"
    local _docker_host="${_DOCKER_HOST:-"dh1.standalone.localdomain:5000"}"

    local _nexus_data="${_work_dir%/}/sonatype/${_name}-data"
    if [ ! -d "${_nexus_data%/}" ]; then
        mkdir -p -m 777 "${_nexus_data%/}" || return $?
    fi
    local _opts="--name=${_name}"
    [ -n "${INSTALL4J_ADD_VM_PARAMS}" ] && _opts="${_opts} -e INSTALL4J_ADD_VM_PARAMS=\"${INSTALL4J_ADD_VM_PARAMS}\""
    [ -d "${_work_dir%/}" ] && _opts="${_opts} -v ${_work_dir%/}:/var/tmp/share"
    [ -d "${_nexus_data%/}" ] && _opts="${_opts} -v ${_nexus_data%/}:/nexus-data"
    [ -n "${_extra_opts}" ] && _opts="${_opts} ${_extra_opts}"  # Should be last to overwrite
    local _cmd="docker run --init -d -p ${_port}:8081 -p ${_port_ssl}:8443 ${_opts} ${_docker_host%/}/sonatype/nexus3:${_tag}"
    echo "${_cmd}"
    eval "${_cmd}"
    echo "To get the admin password:
    docker exec -ti ${_name} cat /nexus-data/admin.password"
}

# To start local (on Mac) IQ server
function iqStart() {
    local _base_dir="${1:-"."}"
    local _java_opts=${2-"-agentlib:jdwp=transport=dt_socket,server=y,address=5006,suspend=n"}
    #local _java_opts=${@:2}
    _base_dir="$(realpath ${_base_dir%/})"
    local _jar_file="$(find "${_base_dir%/}" -maxdepth 2 -type f -name 'nexus-iq-server*.jar' 2>/dev/null | sort | tail -n1)"
    [ -z "${_jar_file}" ] && return 11
    local _cfg_file="$(find "${_base_dir%/}" -maxdepth 2 -type f -name 'config.yml' 2>/dev/null | sort | tail -n1)"
    [ -z "${_cfg_file}" ] && return 12

    local _license="$(ls -1t /var/tmp/share/sonatype/*.lic 2>/dev/null | head -n1)"
    [ -z "${_license}" ] && [ -s "${HOME%/}/.nexus_executable_cache/nexus.lic" ] && _license="${HOME%/}/.nexus_executable_cache/nexus.lic"
    [ -s "${_license}" ] && _java_opts="${_java_opts} -Ddw.licenseFile=${_license}"

    # TODO: belows need to use API:
    #  curl -D- -u admin:admin123 -X PUT -H "Content-Type: application/json" -d '{"hdsUrl": "https://clm-staging.sonatype.com/"}' http://localhost:8070/api/v2/config;
    # curl -D- -u admin:admin123 -X PUT -H "Content-Type: application/json" -d '{"baseUrl": "http://'$(hostname -f)':8070/", "forceBaseUrl":false}' http://localhost:8070/api/v2/config;
    grep -qE '^hdsUrl:' "${_cfg_file}" || echo -e "hdsUrl: https://clm-staging.sonatype.com/\n$(cat "${_cfg_file}")" > "${_cfg_file}"
    grep -qE '^baseUrl:' "${_cfg_file}" || echo -e "baseUrl: http://$(hostname -f):8070/\n$(cat "${_cfg_file}")" > "${_cfg_file}"
    grep -qE '^enableDefaultPasswordWarning:' "${_cfg_file}" || echo -e "enableDefaultPasswordWarning: false\n$(cat "${_cfg_file}")" > "${_cfg_file}"

    grep -qE '^\s*port: 8443$' "${_cfg_file}" && sed -i.bak 's/port: 8443/port: 8470/g' "${_cfg_file}"
    grep -qE '^\s*threshold:\s*INFO$' "${_cfg_file}" && sed -i.bak 's/threshold: INFO/threshold: ALL/g' "${_cfg_file}"
    grep -qE '^\s*level:\s*DEBUG$' "${_cfg_file}" || sed -i.bak -E 's/level: .+/level: DEBUG/g' "${_cfg_file}"
    cd "${_base_dir}"
    local _cmd="java -Xms2g -Xmx4g ${_java_opts} -jar \"${_jar_file}\" server \"${_cfg_file}\" 2>/tmp/iq-server.err"
    echo "${_cmd}"
    eval "${_cmd}"
    cd -
}

function iqInstall() {
#nexus-iq-server-1.99.0-01-bundle.tar.gz
    local _ver="$1" #1.142.0-02
    local _dbname="$2"
    local _dbusr="${3:-"${_dbname}"}"
    local _dbpwd="${4:-"${_dbusr}123"}"
    local _port="${5:-"8070"}"
    local _port2="${6:-"8071"}"
    local _installer_dir="${7:-"$HOME/.nexus_executable_cache"}"

    if [ ! -s "${_installer_dir%/}/license/nexus.lic" ]; then
        echo "no ${_installer_dir%/}/license/nexus.lic"
        return 1
    fi

    _prepare_install "nxiq" "${_installer_dir%/}/nexus-iq-server-${_ver}-bundle.tar.gz" || return $?

    local _jar_file="$(find . -maxdepth 2 -type f -name 'nexus-iq-server*.jar' 2>/dev/null | sort | tail -n1)"
    [ -z "${_jar_file}" ] && return 11
    local _cfg_file="$(find . -maxdepth 2 -type f -name 'config.yml' 2>/dev/null | sort | tail -n1)"
    [ -z "${_cfg_file}" ] && return 12

    # TODO: belows need to use API:
    #  curl -D- -u admin:admin123 -X PUT -H "Content-Type: application/json" -d '{"hdsUrl": "https://clm-staging.sonatype.com/"}' http://localhost:8070/api/v2/config;
    # curl -D- -u admin:admin123 -X PUT -H "Content-Type: application/json" -d '{"baseUrl": "http://'$(hostname -f)':8070/", "forceBaseUrl":false}' http://localhost:8070/api/v2/config;
    grep -qE '^enableDefaultPasswordWarning:' "${_cfg_file}" || echo -e "enableDefaultPasswordWarning: false\n$(cat "${_cfg_file}")" > "${_cfg_file}"
    grep -qE '^licenseFile' "${_cfg_file}" || echo -e "licenseFile: ${_installer_dir%/}/license/nexus.lic\n$(cat "${_cfg_file}")" > "${_cfg_file}"
    grep -qE '^hdsUrl:' "${_cfg_file}" || echo -e "hdsUrl: https://clm-staging.sonatype.com/\n$(cat "${_cfg_file}")" > "${_cfg_file}"
    grep -qE '^baseUrl:' "${_cfg_file}" || echo -e "baseUrl: http://$(hostname -f):8070/\n$(cat "${_cfg_file}")" > "${_cfg_file}"

    grep -qE '^\s*port: 8070' "${_cfg_file}" && sed -i.bak 's/port: 8070/port: '${_port}'/g' "${_cfg_file}"
    grep -qE '^\s*port: 8071' "${_cfg_file}" && sed -i.bak 's/port: 8071/port: '${_port2}'/g' "${_cfg_file}"

    if [ -n "${_dbname}" ]; then
        # TODO: currently assuming "database:" is the end of file
        [ -s "${_cfg_file}" ] && cp -v -f -p ${_cfg_file} ${_cfg_file}_$$
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
        [ -s ${_cfg_file}_$$ ] && diff -wu ${_cfg_file}_$$ ${_cfg_file}

        local _util_dir="$(dirname "$(dirname "$BASH_SOURCE")")/bash"
        if [ -s "${_util_dir}/utils_db.sh" ]; then
            source ${_util_dir}/utils.sh
            source ${_util_dir}/utils_db.sh
            _postgresql_create_dbuser "${_dbusr}" "${_dbpwd}" "${_dbname}"
        else
            echo "WARN Not creating database"
        fi
    fi

    [ ! -d ./log ] && mkdir -m 777 ./log
    # iqStart
    echo "To start: java -jar ${_jar_file} server ${_cfg_file} 2>./log/iq-server.err"
}

#iqDocker "nxiq-test" "1.125.0" "8170" "8171" "8544" #"--read-only -v /tmp/nxiq-test:/tmp"
function iqDocker() {
    local _name="${1:-"nxiq"}"
    local _tag="${2:-"latest"}"
    local _port="${3:-"8070"}"
    local _port2="${4:-"8071"}"
    local _port_ssl="${5:-"8444"}"
    local _extra_opts="${6}"
    local _license="${7}"
    local _work_dir="${_WORK_DIR:-"/var/tmp/share"}"
    local _docker_host="${_DOCKER_HOST:-"dh1.standalone.localdomain:5000"}"

    local _nexus_data="${_work_dir%/}/sonatype/${_name}-data"
    [ ! -d "${_nexus_data%/}" ] && mkdir -p -m 777 "${_nexus_data%/}"
    [ ! -d "${_nexus_data%/}/etc" ] && mkdir -p -m 777 "${_nexus_data%/}/etc"
    [ ! -d "${_nexus_data%/}/log" ] && mkdir -p -m 777 "${_nexus_data%/}/log"
    local _opts="--name=${_name}"
    local _java_opts="" #"-Ddw.dbCacheSizePercent=50 -Ddw.needsAcknowledgementOfInitialDashboardFilter=true"
    # NOTE: symlink of *.lic does not work with -v
    [ -z "${_license}" ] && [ -d ${_work_dir%/}/sonatype ] && _license="$(ls -1t /var/tmp/share/sonatype/*.lic 2>/dev/null | head -n1)"
    [ -s "${_license}" ] && _java_opts="${_java_opts} -Ddw.licenseFile=${_license}"
    # To use PostgreSQL
    #-e JAVA_OPTS="-Ddw.database.type=postgresql -Ddw.database.hostname=db-server-name.domain.net"
    [ -n "${JAVA_OPTS}" ] && _java_opts="${_java_opts} ${JAVA_OPTS}"
    [ -n "${_java_opts}" ] && _opts="${_opts} -e JAVA_OPTS=\"${_java_opts}\""
    [ -d "${_work_dir%/}" ] && _opts="${_opts} -v ${_work_dir%/}:/var/tmp/share"
    [ -d "${_nexus_data%/}" ] && _opts="${_opts} -v ${_nexus_data%/}:/sonatype-work"
    [ -s "${_nexus_data%/}/etc/config.yml" ] && _opts="${_opts} -v ${_nexus_data%/}/etc:/etc/nexus-iq-server"
    [ -d "${_nexus_data%/}/log" ] && _opts="${_opts} -v ${_nexus_data%/}/log:/var/log/nexus-iq-server"
    [ -d "${_nexus_data%/}/log" ] && _opts="${_opts} -v ${_nexus_data%/}/log:/opt/sonatype/nexus-iq-server/log" # due to audit.log => fixed from v104
    [ -n "${_extra_opts}" ] && _opts="${_opts} ${_extra_opts}"  # Should be last to overwrite
    local _cmd="docker run -d -p ${_port}:8070 -p ${_port2}:8071 -p ${_port_ssl}:8444 ${_opts} ${_docker_host%/}/sonatype/nexus-iq-server:${_tag}"  # --init
    echo "${_cmd}"
    eval "${_cmd}"
    echo "NOTE: May need to repalce /opt/sonatype/nexus-iq-server/start.sh to add trap SIGTERM (used from next restart though)"
    # Not doing at this moment as newer version has the fix.
    if ! docker cp ${_name}:/opt/sonatype/nexus-iq-server/start.sh - | grep -qwa TERM; then
        local _tmpfile=$(mktemp)
        cat << EOF > ${_tmpfile}
_term() {
  echo "Received signal: SIGTERM"
  kill -TERM "\$(cat /sonatype-work/lock | cut -d"@" -f1)"
  sleep 10
}
trap _term SIGTERM
/usr/bin/java ${JAVA_OPTS} -jar nexus-iq-server-*.jar server /etc/nexus-iq-server/config.yml &
wait
EOF
        #docker cp ${_tmpfile} ${_name}:/opt/sonatype/nexus-iq-server/start.sh
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
_REPO_URL="http://localhost:8081/repository/maven-snapshots/"
#mvn-deploy "${_REPO_URL}" "" "nexus"
for v in {1..5}; do
  for a in {1..3}; do
    for g in {1..3}; do
      sed -i.tmp -E "s@^  <groupId>.+</groupId>@  <groupId>com.example${g}</groupId>@" pom.xml
      sed -i.tmp -E "s@^  <artifactId>.+</artifactId>@  <artifactId>my-app${a}</artifactId>@" pom.xml
      sed -i.tmp -E "s@^  <version>.+</version>@  <version>1.${v}-SNAPSHOT</version>@" pom.xml
      mvn-deploy "${_REPO_URL}" "" "" "nexus" "" || break
    done || break
  done || break
done
EOF
# Example for testing version sort order
: <<'EOF'
_REPO_URL="http://dh1:8081/repository/maven-hosted/"
for _v in "7.10.0" "7.9.0" "SortTest-1.3.1" "SortTest-1.3.0" "SortTest-1.2.0" "SortTest-1.1.0" "SortTest-1.0.6" "SortTest-1.0.5" "SortTest-1.0.4" "SortTest-1.0.3" "SortTest-1.0.2" "SortTest.SR1" "SortTest"; do
  sed -i.tmp -E "s@^  <version>.*</version>@  <version>${_v}</version>@" pom.xml
  mvn-deploy "${_REPO_URL}" "" "" "nexus" "" || break
done
EOF
function mvn-deploy() {
    local __doc__="Wrapper of mvn clean package deploy"
    local _deploy_repo="${1:-"http://dh1.standalone.localdomain:8081/repository/maven-hosted/"}"
    local _remote_repo="${2}"
    local _local_repo="${3}"
    local _server_id="${4:-"nexus"}"
    local _options="${5-"-DskipTests -Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS -U -X"}"
    if [ -n "${_deploy_repo}" ]; then
        _options="-DaltDeploymentRepository=${_server_id}::default::${_deploy_repo} ${_options}"
    fi
    [ -n "${_local_repo}" ] && _options="${_options% } -Dmaven.repo.local=${_local_repo}"
    # https://issues.apache.org/jira/browse/MRESOLVER-56     -Daether.checksums.algorithms="SHA256,SHA512"
    mvn `_mvn_settings "${_remote_repo}"` clean package deploy -DcreateChecksum=true ${_options}
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
        mvn `_mvn_settings "${_remote_repo}"` deploy:deploy-file -DcreateChecksum=true -Daether.checksums.algorithms="SHA256,SHA512" -DgroupId=${_g} -DartifactId=${_a} -Dversion=${_v} -DgeneratePom=true -Dfile=${_file} ${_options}
    fi
}

# Using NXRM3's upload (would not work with NXRM2), also this API does not work with snapshot repository
function mvn-upload() {
    local _file="${1}"
    local _gav="${2:-"com.example:my-app:1.0"}"
    local _remote_repo="${3:-"maven-hosted"}"
    local _nexus_url="${4:-"${_NEXUS_URL-"http://localhost:8081/"}"}"
    if [ -z "${_file}" ]; then
        if [ ! -f "./junit-4.12.jar" ]; then
            mvn-get-file "junit:junit:4.12" || return $?
        fi
        _file="./junit-4.12.jar"
    fi
    [ -f "${_file}" ] || return 11
    if [[ "${_gav}" =~ ^" "*([^: ]+)" "*:" "*([^: ]+)" "*:" "*([^: ]+)" "*$ ]]; then
        local _g="${BASH_REMATCH[1]}"
        local _a="${BASH_REMATCH[2]}"
        local _v="${BASH_REMATCH[3]}"
        local _ext="${_file##*.}"
        curl -u admin:admin123 -w "  %{http_code} ${_remote_repo} ${_gav}\n" -H "accept: application/json" -H "Content-Type: multipart/form-data" -X POST -k "${_nexus_url%/}/service/rest/v1/components?repository=${_remote_repo}" \
           -F groupId=${_g} \
           -F artifactId=${_a} \
           -F version=${_v} \
           -F asset1=@${_file} \
           -F asset1.extension=${_ext}
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
    local _ver="${2:-"1.0.0"}"
    mkdir "${_name}"
    cd "${_name}"
    cat << EOF > ./package.json
{
  "name": "${_name}",
  "version": "${_ver}",
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

alias npm-deploy='npmDeploy'
alias npmPublish='npmDeploy'
function npmDeploy() {
    local _repo_url="${1:-"http://localhost:8081/repository/npm-hosted/"}"
    local _name="${2:-"lodash-vulnerable"}"
    local _ver="${3:-"1.0.0"}"
    if [ -s ./package.json ] && [ ! -s ./package.json.orig ]; then
        cp -v -p ./package.json ./package.json.orig
    elif [ ! -s ./package.json ]; then
        npmInit "${_name}" "${_ver}"
    fi
    cat ./package.json | python -c "import sys,json
a=json.loads(sys.stdin.read())
d={\"name\":\"${_name}\",\"version\":\"${_ver}\",\"publishConfig\":{\"registry\":\"${_repo_url}\"}}
a.update(d);f=open(\"./package.json\",\"w\")
f.write(json.dumps(a,indent=4,sort_keys=True));" || return $?
    npm publish --registry "${_repo_url}" -ddd || return $?
}

# Create a dummy npm tgz from the original tgz and publish if repo URL is given
#curl -O -L https://registry.npmjs.org/auditjs/-/auditjs-4.0.33.tgz
function npmDummyVer() {
    local _repo_url="${1}"
    local _orig_tgz="${2}"
    local _new_ver="${3}"
    local _new_name="${4}"  # Optional

    local _crt_dir="$(pwd)"
    [[ "${_orig_tgz}" =~ ([^/]+)-([^-]+)\.tgz ]] || return $?
    _pkg="${BASH_REMATCH[1]}"
    [ -z "${_new_name}" ] && _new_name="${_pkg}"
    _ver="${BASH_REMATCH[2]}"
    local _dir="${_new_name}"
    if [ ! -d "${_dir%/}" ]; then
        mkdir -v "${_dir}" || return $?
    fi
    tar -xf "${_orig_tgz}" -C "${_dir%/}/" || return $?
    grep -w "${_ver}" ${_dir%/}/package/package.json || return $?
    sed -i.bak 's/"version": "'${_ver}'"/"version": "'${_new_ver}'"/' ${_dir%/}/package/package.json || return $?
    sed -i.bak 's/"name": "'${_pkg}'"/"name": "'${_new_name}'"/' ${_dir%/}/package/package.json || return $?
    grep -w "${_new_ver}" ${_dir%/}/package/package.json || return $?
    mv -f -v ${_dir%/}/package/package.json.bak /tmp/
    # Below somehow does NOT work! somehow old version and old name remains
    #gunzip "${_new_name}-${_new_ver}.tgz"&& tar -uvf "${_new_name}-${_new_ver}.tar" package/package.json && gzip "${_new_name}-${_new_ver}.tar" && mv "${_new_name}-${_new_ver}.tar.gz" "${_new_name}-${_new_ver}.tgz" || return $?
    cd "${_dir%/}"
    tar -czf "${_crt_dir%/}/${_new_name}-${_new_ver}.tgz" package || return $?
    cd -
    if [ -n "${_repo_url%/}" ] && [[ "${_repo_url%/}" =~ ^(.+)/repository/([^/]+) ]]; then
        _url="${BASH_REMATCH[1]}"
        _repo_name="${BASH_REMATCH[2]}"
        curl -vf -u admin:admin123 -k "${_url%/}/service/rest/v1/components?repository=${_repo_name%/}" -H "accept: application/json" -H "Content-Type: multipart/form-data" -X POST -F "npm.asset=@${_crt_dir%/}/${_new_name}-${_new_ver}.tgz" || return $?
        # NPM repo doesn't support PUT: curl -v -u admin:admin123 -X PUT -k "${_repo_url%/}/${_new_name}/-/${_new_name}-${_new_ver}.tgz" -T "${_crt_dir%/}/${_new_name}-${_new_ver}.tgz" || return $?
    fi
}

function npmDummyVers() {
    local _how_many="${1}"
    local _repo_url="${2}"
    local _pkg_name="${3:-"mytest"}"
    local _from_num="${4}"
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
    for i in `seq ${_from_num:-"1"} ${_how_many:-"1"}`; do
      sed -i.tmp -E 's/"version": "1.[0-9].0"/"version": "1.'${i}'.0"/' ./package.json
      npm publish --registry "${_repo_url}" -ddd || break
      sleep 1
    done
    cd -
    echo "To test: npm cache clean --force; npm pack ${_pkg_name} --registry ${_repo_url}"
}

function nuget-get() {
    local _pkg="$1" # Syncfusion.SfChart.WPF@19.2.0.62
    local _repo_url="${2:-"http://dh1.standalone.localdomain:8081/repository/nuget.org-proxy/index.json"}"
    local _save_to="${3}"  # NOTE: nuget.exe does not work with SSD with exFat
    local _ver=""
    if [[ "${_pkg}" =~ ^([^@]+)@([^ ]+)$ ]]; then
        _pkg="${BASH_REMATCH[1]}"
        _ver="-Version ${BASH_REMATCH[2]}"
    fi
    if [ -z "${_save_to%/}" ]; then
        _save_to="$(mktemp -d -t "nuget_")"
    fi
    eval nuget install ${_pkg} ${_ver} -Source ${_repo_url} -OutputDirectory ${_save_to} -NoCache -Verbosity Detailed || return $?
    ls -ltr ${_save_to%/}/ | tail -n5
}


### Misc.   #################################

# 1. Create a new raw-test-hosted repo
# 2. curl -D- -u "admin:admin123" -T<(echo "test for nxrm3Staging") -L -k "${_NEXUS_URL%/}/repository/raw-hosted/test/nxrm3Staging.txt"
# 3. nxrm3Staging "raw-test-hosted" "raw-test-tag" "repository=raw-hosted&name=*test%2Fnxrm3Staging.txt"
# ^ Tag is optional. Using "*" in name= as name|path in NewDB starts with "/"
# With maven2:
#   export _NEXUS_URL="https://nxrm3-pg-k8s.standalone.localdomain/"
#   mvn-upload "" "com.example:my-app-staging:1.0" "maven-hosted"
#   nxrm3Staging "maven-releases" "maven-test-tag" "repository=maven-hosted&name=my-app-staging"
function nxrm3Staging() {
    local _move_to_repo="${1}"
    local _tag="${2}"
    local _search="${3}"
    local _nxrm3_url="${4:-"${_NEXUS_URL-"http://localhost:8081/"}"}"
    # tag may already exist, so not stopping if error
    if [ -n "${_tag}" ]; then
        echo "# ${_nxrm3_url%/}/service/rest/v1/tags -d '{\"name\": \"'${_tag}'\"}'"
        curl -D- -u admin:admin123 -H "Content-Type: application/json" "${_nxrm3_url%/}/service/rest/v1/tags" -d '{"name": "'${_tag}'"}'
        echo ""
    fi
    if [ -n "${_search}" ]; then
        if [ -z "${_tag}" ] && [ -z "${_move_to_repo}" ]; then
            echo "# ${_nxrm3_url%/}/service/rest/v1/search?${_search}"
            curl -D- -u admin:admin123 -X GET "${_nxrm3_url%/}/service/rest/v1/search?${_search}"
            echo ""
            return
        fi
        if [ -n "${_tag}" ]; then
            echo "# ${_nxrm3_url%/}/service/rest/v1/tags/associate/${_tag}?${_search}"
            curl -D- -u admin:admin123 -X POST "${_nxrm3_url%/}/service/rest/v1/tags/associate/${_tag}?${_search}"
            echo ""
            # NOTE: immediately moving fails with 404
            sleep 5
        fi
    fi
    if [ -n "${_tag}" ]; then
        echo "# ${_nxrm3_url%/}/service/rest/v1/staging/move/${_move_to_repo}?tag=${_tag}"
        curl -D- -f -u admin:admin123 -X POST "${_nxrm3_url%/}/service/rest/v1/staging/move/${_move_to_repo}?tag=${_tag}" || return $?
    elif [ -n "${_search}" ]; then
        echo "# ${_nxrm3_url%/}/service/rest/v1/staging/move/${_move_to_repo}?${_search}"
        curl -D- -f -u admin:admin123 -X POST "${_nxrm3_url%/}/service/rest/v1/staging/move/${_move_to_repo}?${_search}" || return $?
    fi
    echo ""
}

function nxrm3Scripting() {
    local _groovy_file="$1"
    local _nexus_url="$2"
    local _script_name="$3"
    local _args_str="$4"
    [ -z "${_script_name}" ] && _script_name="${_groovy_file%%.*}"
    local _groovy_json_str="$(if [ -f "${_groovy_file}" ]; then
        cat "${_groovy_file}"
    else
        echo "${_groovy_file}"
    fi | python -c "import sys,json;print(json.dumps(sys.stdin.read()))")" || return $?
    echo '{"name":"'${_script_name}'","content":'${_groovy_json_str}',"type": "groovy"}' > /tmp/${_script_name}.json || return $?
    if ! curl -f -D- -u admin:admin123 -X POST -H 'Content-Type: application/json' "${_nexus_url%/}/service/rest/v1/script" -d@/tmp/${_script_name}.json; then
        echo "May need to run below (or use -X DELETE)
    curl -D- -u admin:admin123 -X PUT -H 'Content-Type: application/json' ${_nexus_url%/}/service/rest/v1/script/${_script_name} -d@/tmp/${_script_name}.json"
        #curl -D- -u admin:admin123 -X DELETE "${_nexus_url%/}/service/rest/v1/script/${_script_name}"
        return 1
    fi
    if [ -n "${_args_str}" ]; then
        echo "${_args_str}" > /tmp/${FUNCNAME}_args.json || return $?
        # TODO: why need to use text/plain?
        curl -D- -u admin:admin123 -X POST -H 'Content-Type: text/plain' "${_nexus_url%/}/service/rest/v1/script/${_script_name}/run" -d@/tmp/${FUNCNAME}_args.json
    fi
}
