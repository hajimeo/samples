#_import() { curl -sf --compressed "https://raw.githubusercontent.com/hajimeo/samples/master/$1" -o /tmp/_i;. /tmp/_i; }
#_import "runcom/nexus_alias.sh"

# For identifying elasticsearch directory name (hash id) from a repository name
alias esIndexName='python3 -c "import sys,hashlib; print(hashlib.sha1(sys.argv[1].encode(\"utf-16-le\")).hexdigest())"'
# Covert specs.4.8.gz to string
function rubySpecs2str() {
    local _specs="${1:-"./specs.4.8.gz"}"
    ruby -rpp -e "pp Marshal.load(Gem::Util.gunzip(File.read(\"${_specs}\")))"
}
function rubyRz2str() {
    local _pkg_ver_rz="${1}"    # https://rubygems.org/quick/Marshal.4.8/nexus-1.4.0.gemspec.rz
    #ruby -rpp -e "p Marshal.load(Zlib::Inflate.new.inflate(File.open(\"${_pkg_ver_rz}\").read))"
    ruby -rpp -e "p Marshal.load(Gem::Util.inflate(File.read(\"${_pkg_ver_rz}\")))"
}
# Cocoapods buildNxrmSpecFilePath
function specFilePath() {
    local _name="$1"
    local _ver="$2"
    python -c "import hashlib
n=\"${_name}\";v=\"${_ver}\"
md5=hashlib.md5()
md5.update(n.encode('utf-8'))
h=md5.hexdigest()
print(\"Specs/%s/%s/%s/%s/%s/%s.podspec.json\" % (h[0],h[1],h[2],n,v,n))"
}



if [ -z "${_WORK_DIR%/}" ]; then
    if [ "`uname`" = "Darwin" ]; then
        # dovker -v does not work with symlink
        _WORK_DIR="$HOME/share"
    else
        _WORK_DIR="/var/tmp/share"
    fi
fi

function _get_rm_url() {
    local _rm_url="${1:-${_NEXUS_URL}}"
    if [ -z "${_rm_url}" ]; then
        for _url in "http://localhost:8081/" "https://nxrm3pg-k8s.standalone.localdomain/" "http://dh1:8081/"; do
            if curl -m1 -f -s -I "${_url%/}/" &>/dev/null; then
                echo "${_url%/}/"
                _NEXUS_URL="${_url%/}/"
                return
            fi
        done
        return 1
    fi
    if [[ ! "${_rm_url}" =~ ^https?://.+ ]]; then
        if [[ ! "${_rm_url}" =~ .+:[0-9]+ ]]; then   # Provided hostname only
            _rm_url="http://${_rm_url%/}:8081/"
        else
            _rm_url="http://${_rm_url%/}/"
        fi
    fi
    echo "${_rm_url}"
    _NEXUS_URL="${_rm_url%/}/"
}
function _get_iq_url() {
    local _iq_url="${1-${_IQ_URL}}"
    if [ -n "${_iq_url%/}" ]; then
        if [[ ! "${_iq_url}" =~ ^https?://.+ ]]; then
            if [[ ! "${_iq_url}" =~ .+:[0-9]+ ]]; then   # Provided hostname only
                _iq_url="http://${_iq_url%/}:8070/"
            else
                _iq_url="http://${_iq_url%/}/"
            fi
        fi
        if curl -m1 -f -s -I "${_url%/}/" &>/dev/null; then
            echo "${_url%/}/"
            return
        fi
    fi
    for _url in "http://localhost:8070/" "https://nxiqha-k8s.standalone.localdomain/" "http://dh1:8070/"; do
        if curl -m1 -f -s -I "${_url%/}/" &>/dev/null; then
            echo "${_url%/}/"
            return
        fi
    done
    return 1
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
    local _iq_cli_ver="${5:-${_IQ_CLI_VER}}"
    local _iq_cli_opt="${6:-${_IQ_CLI_OPT}}"    # -D fileIncludes="**/package-lock.json"

    _iq_url="$(_get_iq_url "${_iq_url}")" || return $?
        if [ -z "${_iq_cli_ver}" ]; then
        _iq_cli_ver="$(curl -m3 -sf "${_iq_url%/}/rest/product/version" | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a['version'])")"
    fi

    local _iq_cli_jar="${_IQ_CLI_JAR:-"$HOME/.nexus_executable_cache/nexus-iq-cli-${_iq_cli_ver}.jar"}"
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
    #       Newer IQ CLI removes scan-6947340794864341803.xml.gz (if no -k), so no point of changing the tmpdir...
    # -D includeSha256=true is for BFS
    local _cmd="java -jar ${_iq_cli_jar} ${_iq_cli_opt} -s ${_iq_url} -a 'admin:admin123' -i ${_iq_app_id} -t ${_iq_stage} -D includeSha256=true -r ./iq_result_$$.json -k -X ${_path}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Executing: ${_cmd} | tee ./iq_cli_$$.out" >&2
    eval "${_cmd} | tee ./iq_cli_$$.out"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Completed ($?)." >&2
    local _scanId="$(rg -m1 '"reportDataUrl"\s*:\s*".+/([0-9a-f]{32})/.*"' -o -r '$1' ./iq_result_$$.json)"
    if [ -n "${_scanId}" ]; then
        _cmd="curl -sf -u admin:admin123 ${_iq_url%/}/api/v2/applications/${_iq_app_id}/reports/${_scanId}/raw | python -m json.tool > ./iq_raw_$$.json"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Executing: ${_cmd}" >&2
        eval "${_cmd}"
    fi
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

    #clm-maven-plugin:2.30.2-01:index | com.sonatype.clm:clm-maven-plugin:index to generate module.xml file
    local _cmd="mvn -f ${_file} com.sonatype.clm:clm-maven-plugin${_iq_mvn_ver}:evaluate -Dclm.serverUrl=${_iq_url} -Dclm.applicationId=${_iq_app_id} -Dclm.stage=${_iq_stage} -Dclm.username=admin -Dclm.password=admin123 -Dclm.resultFile=iq_result.json -Dclm.scan.dirExcludes=\"**/BOOT-INF/lib/**\" ${_mvn_opts}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Executing: ${_cmd}" >&2
    eval "${_cmd}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Completed." >&2
}

# To start local (on Mac) NXRM2 or NXRM3 server
# TODO: May need to reset 'admin' user, and also use below query (after modifying for H2/PostgreSQL/OrientDB)
#  UPDATE repository_blobstore SET attributes = {} where type = 'S3';
#  UPDATE repository_blobstore SET attributes.file = {} where type = 'S3';
#  UPDATE repository_blobstore SET type = 'File', attributes.file.path = 's3/test' where type = 'S3';
#
#  Orient: UPDATE capability SET enabled = false WHERE type like 'firewall%';update capability set enabled = false where type like 'clm';
#  H2: UPDATE capability_storage_item SET enabled = false WHERE type IN ('firewall.audit', 'clm', 'webhook.repository', 'healthcheck', 'crowd');
#      TODO: UPDATE realm_configuration SET realm_names = '["NexusAuthenticatingRealm", "NexusAuthorizingRealm"]' FORMAT JSON where id = 1;
#
#  DELETE FROM nuget_asset WHERE path = '/index.json';
#
#  TRUNCATE TABLE http_client_configuration;
#  INSERT INTO http_client_configuration (id, proxy) VALUES (1, '{"http": {"host": "localhost", "port": 28080, "enabled": true, "authentication": null}, "https": null, "nonProxyHosts": null}' FORMAT JSON);
function nxrmStart() {
    local _base_dir="${1:-"."}"
    # Adding monitor and heap=sites (and cpu=times) make the process too slow
    # -Xrunhprof:cpu=samples,interval=30,thread=y,cutoff=0.005,file=/tmp/cpu_samples_$$.hprof
    # -Xrunhprof:cpu=times,interval=30,thread=y,monitor=y,cutoff=0.001,doe=n,file=/tmp/cpu_samples_$$.hprof
    # -Xrunhprof:heap=sites,format=b,file=${_base_dir%/}/heap_sites_$$.hprof
    # only 'root.level' is changeable with _LOG_LEVEL
    # Debugger port for NXRM2 is 5004
    local _java_opts=${2-"-Droot.level=${_LOG_LEVEL:-"INFO"} -Xrunjdwp:transport=dt_socket,server=y,address=5005,suspend=${_SUSPEND:-"n"}"}
    local _mode=${3} # if NXRM2, not 'run' but 'console'
    #local _java_opts=${@:2}
    _base_dir="$(realpath "${_base_dir}")"

    _java_opts="${_java_opts} -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCCause -XX:+PrintClassHistogramAfterFullGC -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=100M -Xloggc:/tmp/rm-gc_%p_%t.log"
    if [ -n "${_CUSTOM_DNS}" ]; then
        _java_opts="${_java_opts} -Dsun.net.spi.nameservice.nameservers=${_CUSTOM_DNS} -Dsun.net.spi.nameservice.provider.1=dns,sun"
    fi

    local _nexus_file="${_base_dir%/}/nexus/bin/nexus"
    [ -s "${_nexus_file}" ] || _nexus_file="$(find ${_base_dir%/} -maxdepth 4 -path '*/bin/*' -type f -name 'nexus' 2>/dev/null | sort | tail -n1)"
    local _nexus_vmopt="$(find ${_base_dir%/} -maxdepth 4 -path '*/bin/*' -type f -name 'nexus.vmoptions' 2>/dev/null | sort | tail -n1)"
    local _sonatype_work="$(find ${_base_dir%/} -maxdepth 4 -path '*/sonatype-work/*' -type d \( -name 'nexus3' -o -name 'nexus2' -o -name 'nexus' -o -name 'nexus' \) 2>/dev/null | grep -v -w elasticsearch | sort | tail -n1)"
    if [ -z "${_sonatype_work%/}" ]; then
        echo "This function requires sonatype-work/{nexus|nexus3}"
        return 1
    fi
    local _nexus_ver="$(basename "$(dirname "$(dirname "$(realpath "${_nexus_file}")")")")"
    local _jetty_https="$(find ${_base_dir%/} -maxdepth 4 -path '*/etc/*' -type f -name 'jetty-https.xml' 2>/dev/null | sort | tail -n1)"
    local _karaf_conf="$(find . -maxdepth 4 -type f -name 'config.properties' -path '*/etc/karaf/*' | head -n1)"
    if [ -n "${_karaf_conf}" ] && ! grep -q 'org.openjdk.btrace' ${_karaf_conf}; then
        sed -i '' '/^org.osgi.framework.bootdelegation = /a \
        org.openjdk.btrace.*, \\
    ' ${_karaf_conf}
    fi
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
        if [ -n "${_jetty_https}" ] && [[ "${_nexus_ver}" =~ nexus-3\.26\.+ ]]; then
            # @see: https://issues.sonatype.org/browse/NEXUS-24867
            sed -i.bak 's@class="org.eclipse.jetty.util.ssl.SslContextFactory"@class="org.eclipse.jetty.util.ssl.SslContextFactory$Server"@g' ${_jetty_https}
        fi
        if [[ "${_nexus_ver}" =~ nexus-3\.[23] ]]; then
            # https://issues.sonatype.org/browse/NEXUS-29730 java.lang.NoClassDefFoundError: com/sun/jna/Platform
            _nexus29730 "${_base_dir%/}"
        fi
    else    # if NXRM2
        [ -z "${_mode}" ] && _mode="console"
        # jvm 1    | Caused by: java.lang.ClassNotFoundException: org.eclipse.tycho.nexus.internal.plugin.UnzipRepository
        #https://repo1.maven.org/maven2/org/eclipse/tycho/nexus/unzip-repository-plugin/0.14.0/unzip-repository-plugin-0.14.0-bundle.zip
        echo "NOTE: May need to 'unzip -d ${_base_dir%/}/sonatype-work/nexus/plugin-repository $HOME/Downloads/unzip-repository-plugin-0.14.0-bundle.zip'"
        # jvm 1    | Caused by: java.lang.ClassNotFoundException: org.codehaus.janino.ScriptEvaluator
        #./sonatype-work/nexus/conf/logback-nexus.xml
        if [ -n "${_java_opts}" ]; then
            export JAVA_TOOL_OPTIONS="${_java_opts/address=5005,/address=5004,}" && _java_opts=""
        fi
    fi
    # For java options, latter values are used, so appending
    ulimit -n 65536
    local _cmd="INSTALL4J_ADD_VM_PARAMS=\"-XX:-MaxFDLimit ${INSTALL4J_ADD_VM_PARAMS} ${_java_opts}\" ${_nexus_file} ${_mode}"
    echo "${_cmd}"; sleep 3
    eval "${_cmd}"
    # ulimit / Too many open files: https://help.sonatype.com/repomanager3/installation/system-requirements#SystemRequirements-MacOSX
}

#_NO_DB_CREATE
function setDbConn() {
    local _dbname="${1}"
    local _isIQ="${2}"
    local _baseDir="${3:-"."}"
    local _dbschema="${4:-"public"}"
    local _dbusr="nexus"
    local _dbpwd="nexus123"

    if [ -z "${_dbname%/}" ] || [ -d "${_dbname%/}" ]; then
        echo "Not doing anything as _dbname is empty or directory" >&2
        return 0
    fi

    # if my special script for PostgreSQL exists, create DB user and database
    if [[ ! "${_NO_DB_CREATE}" =~ ^[yY] ]] && [ -s "$HOME/IdeaProjects/samples/bash/utils_db.sh" ]; then
        source $HOME/IdeaProjects/samples/bash/utils.sh
        source $HOME/IdeaProjects/samples/bash/utils_db.sh
        _postgresql_create_dbuser "${_dbusr}" "${_dbpwd}" "${_dbname}" "${_dbschema}"
    fi

    local _work_dir="$(find ${_baseDir%/} -mindepth 1 -maxdepth 2 -type d -path '*/sonatype-work/*' -name 'nexus3' | sort | tail -n1)"

    if [ -z "${_dbname}" ]; then
        if echo "${JAVA_TOOL_OPTIONS}" | grep -q "nexus.datastore.nexus.schema="; then
            echo "${JAVA_TOOL_OPTIONS}"
            return 0
        fi
    fi

    if [[ ! "${_isIQ}" =~ ^[yY] ]] && [ -d "${_work_dir%/}" ]; then
        mkdir -v -p "${_work_dir%/}/etc/fabric"
        cat << EOF > "${_work_dir%/}/etc/fabric/nexus-store.properties"
jdbcUrl=jdbc\:postgresql\://$(hostname -f)\:5432/${_dbname}
username=${_dbusr}
password=${_dbpwd}
schema=${_schema:-"public"}
maximumPoolSize=40
advanced=maxLifetime\=600000
EOF
        if [ -s "${_work_dir%/}/etc/fabric/nexus-store.properties" ]; then
            cat ${_work_dir%/}/etc/fabric/nexus-store.properties | grep -v password
            return 0
        fi
    fi

    local _java_opts="-Dnexus.datastore.enabled=true -Dnexus.datastore.nexus.jdbcUrl=\"jdbc:postgresql://$(hostname -f):5432/${_dbname}\" -Dnexus.datastore.nexus.username=\"${_dbusr}\" -Dnexus.datastore.nexus.password=\"${_dbpwd}\" -Dnexus.datastore.nexus.schema=${_dbschema} -Dnexus.datastore.nexus.advanced=maxLifetime=600000 -Dnexus.datastore.nexus.maximumPoolSize=10"
    if [[ "${_isIQ}" =~ ^[yY] ]]; then
        _java_opts="-Ddw.database.type=postgresql -Ddw.database.hostname=$(hostname -f) -Ddw.database.port=5432 -Ddw.database.name=${_dbname%/} -Ddw.database.username=${_dbusr} -Ddw.database.password=${_dbpwd} ${_java_opts}"
    # TODO: Below was checking support zip
    #elif find . -maxdepth 5 -type f -name nexus-store.properties | grep nexus-store.properties; then
    #    echo "Found nexus-store.properties. Not setting Java options" >&2
    #    _java_opts=""
    fi
    if echo "${JAVA_TOOL_OPTIONS}" | grep -E "D(dw\.database\.type|nexus\.datastore\.enabled)="; then
        echo "Found JAVA_TOOL_OPTIONS has DB related options. Not setting Java options" >&2; sleep 5
        _java_opts=""
    fi
    if [ -n "${_java_opts}" ]; then
        if [ -n "${JAVA_TOOL_OPTIONS}" ]; then
            export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS} ${_java_opts}"
        else
            export JAVA_TOOL_OPTIONS="${_java_opts}"
        fi
    fi
}


function _updateNexusProps() {
    local _cfg_file="$1"
    if [ -s "${_cfg_file}" ] && [ ! -f "${_cfg_file}.orig" ]; then
        cp -p "${_cfg_file}" "${_cfg_file}.orig"
    fi
    touch "${_cfg_file}" || return $?
    grep -qE '^#?nexus.security.randompassword' "${_cfg_file}" || echo "nexus.security.randompassword=false" >> "${_cfg_file}"
    grep -qE '^#?nexus.onboarding.enabled' "${_cfg_file}" || echo "nexus.onboarding.enabled=false" >> "${_cfg_file}"
    grep -qE '^#?nexus.scripts.allowCreation' "${_cfg_file}" || echo "nexus.scripts.allowCreation=true" >> "${_cfg_file}"
    grep -qE '^#?nexus.browse.component.tree.automaticRebuild' "${_cfg_file}" || echo "nexus.browse.component.tree.automaticRebuild=false" >> "${_cfg_file}"
    # NOTE: this would not work if elasticsearch directory is empty
    #       or if upgraded from older than 3.39 due to https://sonatype.atlassian.net/browse/NEXUS-31285
    grep -qE '^#?nexus.elasticsearch.autoRebuild' "${_cfg_file}" || echo "nexus.elasticsearch.autoRebuild=false" >> "${_cfg_file}"
    grep -qE '^#?nexus.assetBlobCleanupTask.blobCreatedDelayMinute' "${_cfg_file}" || echo "nexus.assetBlobCleanupTask.blobCreatedDelayMinute=1" >> "${_cfg_file}"

    # ${nexus.h2.httpListenerPort:-8082} jdbc:h2:file:./nexus (no username)
    grep -qE '^#?nexus.h2.httpListenerEnabled' "${_cfg_file}" || echo "nexus.h2.httpListenerEnabled=true" >> "${_cfg_file}"
    # Binary (or HA-C) for 'connect remote:hostname/component admin admin'
    grep -qE '^#?nexus.orient.binaryListenerEnabled' "${_cfg_file}" || echo "nexus.orient.binaryListenerEnabled=true" >> "${_cfg_file}"
    # For OrientDB studio (hostname:2480/studio/index.html) (removed)
    #grep -qE '^#?nexus.orient.httpListenerEnabled' "${_cfg_file}" || echo "nexus.orient.httpListenerEnabled=true" >> "${_cfg_file}"
    #grep -qE '^#?nexus.orient.dynamicPlugins' "${_cfg_file}" || echo "nexus.orient.dynamicPlugins=true" >> "${_cfg_file}"

    #TODO: change the port automatically
    #_port="$(_find_port "8081" "" "^8082$")"
    #_upsert "${_prop}" "application-port" "${_port}" || return $?
    #echo "INFO Using port: ${_port}" >&2; sleep 5
}

# https://issues.sonatype.org/browse/NEXUS-29730 java.lang.NoClassDefFoundError: com/sun/jna/Platform
# https://docs.oracle.com/javase/8/docs/technotes/guides/standards/#:~:text=endorsed.,endorsed.
function _nexus29730() {
    local _base_dir="${1:-"."}"
    local _good_jar_root="${2:-"/var/tmp/share/java/libs"}"
    if [ ! -s "${_good_jar_root%/}/system/net/java/dev/jna/jna/5.11.0/jna-5.11.0.jar" ]; then
        echo "WARN: No good jar (${_good_jar_root%/}/system/net/java/dev/jna/jna/5.11.0/jna-5.11.0.jar)"
        return 1
    fi
    #local _endorsed="$(find ${_base_dir%/} -maxdepth 4 -type d -name endorsed -path '*/lib/*'| sort | tail -n1)"
    #cp -v -f ${_good_jar_root%/}/system/net/java/dev/jna/jna/5.11.0/jna-5.11.0.jar ${_endorsed%/}/ || return $?
    #cp -v -f ${_good_jar_root%/}/system/net/java/dev/jna/jna-platform/5.11.0/jna-platform-5.11.0.jar ${_endorsed%/}/ || return $?
    find ${_base_dir%/}/nexus-3.* -type f -path '*/system/net/java/dev/jna/jna/*' -name "jna-*.jar" | while read -r _jar; do
        if [[ "${_jar}" =~ /jna-[0-5]\.[0-9]\.[0-9]\.jar ]]; then
            cp -v -f ${_good_jar_root%/}/system/net/java/dev/jna/jna/5.11.0/jna-5.11.0.jar ${_jar}
        fi
    done
    find ${_base_dir%/}/nexus-3.* -type f -path '*/system/net/java/dev/jna/jna-platform/*' -name "jna-*.jar" | while read -r _jar; do
        if [[ "${_jar}" =~ /jna-platform-[0-5]\.[0-9]\.[0-9]\.jar ]]; then
            cp -v -f ${_good_jar_root%/}/system/net/java/dev/jna/jna-platform/5.11.0/jna-platform-5.11.0.jar ${_jar}
        fi
    done
}

# To install 2nd instance: _NXRM3_INSTALL_PORT=8083 _NXRM3_INSTALL_DIR=./nxrm_3.42.0-01_test nxrm3Install 3.42.0-01
# Re-create database: _RECREATE_DB=Y`
# To upgrade (from ${_dirname}/): tar -xvf $HOME/.nexus_executable_cache/nexus-3.56.0-01-mac.tgz
function nxrm3Install() {
    if [ -s "$HOME/IdeaProjects/samples/bash/setup_nexus3_repos.sh" ]; then
        source "$HOME/IdeaProjects/samples/bash/setup_nexus3_repos.sh" || return $?
        f_install_nexus3 "$@"
    fi
}

#nxrmDocker "nxrm3-test" "" "8181:8081 8543:8443 15000:5000" #"--read-only -v /tmp/nxrm3-test:/tmp" or --tmpfs /tmp:noexec
#mkdir -v -p -m777 /var/tmp/share/sonatype/nxrm3docker
#docker run --init -d -p 18081:8081 --name=nxrm3docker -e INSTALL4J_ADD_VM_PARAMS="-Dnexus-context-path=/nexus -Djava.util.prefs.userRoot=/nexus-data" -v /var/tmp/share:/var/tmp/share -v /var/tmp/share/sonatype/nxrm3docker:/nexus-data sonatype/nexus3:latest

# For new installation, creating local dir for /nexus-data
#_NEXUS_DATA_LOCAL="/var/tmp/share/sonatype/nxrm3-data-test";
#mkdir -v -p "${_NEXUS_DATA_LOCAL}/etc/ssl";
# NOTE: copy jetty-https.xml and keystore.jks into above directory
#       -Dapplication-port-ssl=8443 does not work
#chown -R 200:200 "${_NEXUS_DATA_LOCAL}";
#docker run --init -d -p 18081:8081 -p 18443:8443 --name=nxrm3dockerWithHTTPS --tmpfs /tmp:noexec -e INSTALL4J_ADD_VM_PARAMS="-Djava.util.prefs.userRoot=/nexus-data -Dssl.etc=\${karaf.data}/etc/ssl -Dnexus-args=\${jetty.etc}/jetty.xml,\${jetty.etc}/jetty-https.xml,\${jetty.etc}/jetty-requestlog.xml" -v /var/tmp/share:/var/tmp/share -v ${_NEXUS_DATA_LOCAL}:/nexus-data dh1.standalone.localdomain:5000/sonatype/nexus3:latest
# export INSTALL4J_ADD_VM_PARAMS="-Djava.util.prefs.userRoot=/nexus-data -XX:ActiveProcessorCount=2 -Xms2g -Xmx2g -XX:MaxDirectMemorySize=2g -XX:+PrintGC -XX:+PrintGCDateStamps -Dnexus.licenseFile=/var/tmp/share/sonatype/sonatype-license.lic"
# export INSTALL4J_ADD_VM_PARAMS="-Djava.util.prefs.userRoot=/nexus-data -XX:ActiveProcessorCount=2 -Xms2g -Xmx2g -XX:MaxDirectMemorySize=2g -Dnexus.licenseFile=/var/tmp/share/sonatype/sonatype-license.lic -Dnexus.datastore.enabled=true -Dnexus.datastore.nexus.jdbcUrl=jdbc\:postgresql\://localhost/nxrm?ssl=true&sslmode=require -Dnexus.datastore.nexus.username=nxrm -Dnexus.datastore.nexus.password=nxrm123 -Dnexus.datastore.nexus.maximumPoolSize=10 -Dnexus.datastore.nexus.advanced=maxLifetime=600000"
alias rmDocker='nxrmDocker'
function nxrmDocker() {
    local _name="${1:-"nxrm3"}"
    local _tag="${2:-"latest"}"
    local _ports="${3:-"8081:8081 15000:15000"}"
    local _extra_opts="${4}"    # this is docker options not INSTALL4J_ADD_VM_PARAMS. eg --platform=linux/amd64
    local _work_dir="${_WORK_DIR:-"/var/tmp/share"}"
    local _docker_host="${_DOCKER_HOST}"  #:-"dh1.standalone.localdomain:5000"

    local _nexus_data="${_work_dir%/}/sonatype/${_name}-data"
    if [ ! -d "${_nexus_data%/}" ]; then
        mkdir -p -m 777 "${_nexus_data%/}" || return $?
    fi
    local _p=""
    if [ -n "${_ports}" ]; then
        for _p_p in ${_ports}; do
            _p="-p ${_p_p} ${_p% }"
        done
    fi
    local _opts="--name=${_name}"
    #[ -z "${INSTALL4J_ADD_VM_PARAMS}" ] && INSTALL4J_ADD_VM_PARAMS="-Djava.util.prefs.userRoot=/nexus-data -Djdk.lang.Process.launchMechanism=vfork"
    [ -n "${INSTALL4J_ADD_VM_PARAMS}" ] && _opts="${_opts} -e INSTALL4J_ADD_VM_PARAMS=\"${INSTALL4J_ADD_VM_PARAMS}\""
    [ -d "${_work_dir%/}" ] && _opts="${_opts} -v ${_work_dir%/}:/var/tmp/share:z"  # :z or :Z for SELinux https://docs.docker.com/storage/bind-mounts/#configure-the-selinux-label
    [ -d "${_nexus_data%/}" ] && _opts="${_opts} -v ${_nexus_data%/}:/nexus-data"
    [ -n "${_extra_opts}" ] && _opts="${_opts} ${_extra_opts}"  # Should be last to overwrite
    [ -n "${_docker_host}" ] && _docker_host="${_docker_host%/}/"
    local _cmd="docker run --init -d ${_p} ${_opts} ${_docker_host%/}sonatype/nexus3:${_tag}"
    echo "${_cmd}"
    eval "${_cmd}"
    echo "To get the admin password:
    docker exec -ti ${_name} cat /nexus-data/admin.password"
    # If fails on Arm Mac, softwareupdate --install-rosetta --agree-to-license
}

# To start local (on Mac) IQ server, do not forget to delete LDAP and populate HTTP proxy (and DNS), also reset admin.
#   _CUSTOM_DNS="$(hostname -f)" iqStart
# export JAVA_TOOL_OPTIONS="-javaagent:$HOME/IdeaProjects/samples/misc/delver.jar=$HOME/IdeaProjects/samples/misc/delver-conf.xml"
function iqStart() {
    local _base_dir="${1:-"."}"
    local _java_opts="${2-"-agentlib:jdwp=transport=dt_socket,server=y,address=5006,suspend=${_SUSPEND:-"n"}"}"
    #local _java_opts=${@:2}

    _base_dir="$(realpath ${_base_dir%/})"
    local _jar_file="$(find "${_base_dir%/}" -maxdepth 2 -type f -name 'nexus-iq-server*.jar' 2>/dev/null | sort | tail -n1)"
    [ -z "${_jar_file}" ] && return 11
    local _cfg_file="$(find "${_base_dir%/}" -maxdepth 2 -type f -name 'config.yml' 2>/dev/null | sort | tail -n1)"
    [ -z "${_cfg_file}" ] && return 12
    local _work_dir="$(sed -n -E 's/sonatypeWork[[:space:]]*:[[:space:]]*(.+)/\1/p' "${_cfg_file}")"
    local _license="$(ls -1t /var/tmp/share/sonatype/*.lic 2>/dev/null | head -n1)"
    [ -z "${_license}" ] && [ -s "${HOME%/}/.nexus_executable_cache/nexus.lic" ] && _license="${HOME%/}/.nexus_executable_cache/nexus.lic"
    [ -s "${_license}" ] && _java_opts="${_java_opts} -Ddw.licenseFile=${_license}"
    _java_opts="${_java_opts} -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCCause -XX:+PrintClassHistogramAfterFullGC -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=100M -Xloggc:/tmp/iq-gc_%p_%t.log"

    # TODO: From v138, most of configs need to use API: https://help.sonatype.com/iqserver/automating/rest-apis/configuration-rest-api---v2
    # 'com.sonatype.insight.brain.migration.SimpleConfigurationMigrator - hdsUrl, enableDefaultPasswordWarning is now configured using the REST API. The configuration in the config.yml or via system properties is obsolete.'
    if [ ! -s "${_cfg_file}.orig" ]; then
        cp -v -p "${_cfg_file}" "${_cfg_file}.orig"
    fi
    grep -qE '^hdsUrl:' "${_cfg_file}" || echo -e "hdsUrl: https://clm-staging.sonatype.com/\n$(cat "${_cfg_file}")" > "${_cfg_file}"
    grep -qE '^enableDefaultPasswordWarning:' "${_cfg_file}" || echo -e "enableDefaultPasswordWarning: false\n$(cat "${_cfg_file}")" > "${_cfg_file}"
    grep -qE '^baseUrl:' "${_cfg_file}" || echo -e "baseUrl: http://$(hostname -f):8070/\n$(cat "${_cfg_file}")" > "${_cfg_file}"

    grep -qE '^\s*port: 8443$' "${_cfg_file}" && sed -i'' 's/port: 8443/port: 8470/g' "${_cfg_file}"
    grep -qE '^\s*threshold:\s*INFO$' "${_cfg_file}" && sed -i'' 's/threshold: INFO/threshold: ALL/g' "${_cfg_file}"
    grep -qE '^\s*level:\s*(DEBUG|TRACE)$' "${_cfg_file}" || sed -i'' -E 's/level: .+/level: DEBUG/g' "${_cfg_file}"
    cd "${_base_dir}"
    if ! grep -qE '^\s+"?com.sonatype.insight.policy.violation' "${_cfg_file}"; then
        # Mac's sed doesn't work with '/a'
        echo "$(sed '/^  loggers:/q' "${_cfg_file}")
    com.sonatype.insight.policy.violation:
      appenders:
      - type: file
        currentLogFilename: ./log/policy-violation.log
        archivedLogFilenamePattern: ./log/policy-violation-%d.log.gz
        archivedFileCount: 5
$(sed -n "/^  loggers:/,\$p" ${_cfg_file} | grep -v '^  loggers:')" > "${_cfg_file}"
    fi

    if [[ "${_java_opts}" =~ agentlib:jdwp ]] && [[ "${JAVA_TOOL_OPTIONS}" =~ agentlib:jdwp ]]; then
        echo "Unsetting JAVA_TOOL_OPTIONS = ${JAVA_TOOL_OPTIONS}"
        unset JAVA_TOOL_OPTIONS
    fi
    if [ -n "${_CUSTOM_DNS}" ]; then
        # TODO: it stopped working with 127.0.0.1
        _java_opts="${_java_opts} -Dsun.net.spi.nameservice.nameservers=${_CUSTOM_DNS} -Dsun.net.spi.nameservice.provider.1=dns,sun"
        # NOTE: below does not work for SCM due to the change added in INT-5729
        _java_opts="${_java_opts} -Dhttp.proxyHost=non-existing-hostname -Dhttp.proxyPort=8800 -Dhttp.nonProxyHosts=\"*.sonatype.com\""

        local _console=""
        if type h2-console &>/dev/null && [ -s "${_work_dir:-"."}/data/ods.h2.db" ]; then
            _console="h2-console ${_work_dir:-"."}/data/ods.h2.db"
        elif type psql &>/dev/null; then
            eval "$(grep "^database:" -A7 "${_cfg_file}" | sed -n -E 's/^ +([^:]+): *(.+)$/\1=\2/p')"
            if [ "${type}" == "postgresql" ]; then
                _console="PGPASSWORD=${password} psql -h ${hostname} -p ${port} -U ${username} -d ${name}"
            fi
        fi
        if [ -z "${_console}" ]; then
            echo "no '${_console}'"
            return 11
        fi

        if [ -s "${_work_dir:-"."}/data/ods.h2.db" ] && [ ! -f "${_work_dir:-"."}/data/ods.h2.db.gz" ]; then
            echo "No ${_work_dir:-"."}/data/ods.h2.db.gz. Gzip-ing ods.h2.db file ..."; sleep 3
            gzip -k "$(readlink -f "${_work_dir:-"."}/data/ods.h2.db")" || return $?
        else
            echo "WARN Not making a backup of database ${_work_dir:-"."}/data/ods.h2.db"; sleep 5;
        fi

        echo "*** reset-admin *** "; sleep 3;
        java -jar ${_jar_file} reset-admin ${_cfg_file} || return $?

        echo "*** Updating DB with '${_console}' ***"; sleep 3;
        _iqStartSQLs | eval "${_console}" || return $?
    fi
    local _cmd="java ${_java_opts} -jar \"${_jar_file}\" server \"${_cfg_file}\" 2>/tmp/iq-server.err"
    echo "${_cmd}"; sleep 2
    eval "${_cmd}"
    cd -
}
function _iqStartSQLs() {
#DELETE FROM insight_brain_ods.ldap_usermapping;
#DELETE FROM insight_brain_ods.ldap_connection;
#DELETE FROM insight_brain_ods.ldap_server;
#DELETE FROM insight_brain_ods.mail_configuration;
#UPDATE insight_brain_ods.source_control SET remediation_pull_requests_enabled = false, status_checks_enabled = false, pull_request_commenting_enabled = false, source_control_evaluations_enabled = false;
    cat << EOF
UPDATE insight_brain_ods.ldap_connection SET hostname = hostname || '.sptboot' WHERE hostname not like '%.sptboot';
UPDATE insight_brain_ods.mail_configuration SET hostname = hostname || '.sptboot' WHERE hostname not like '%.sptboot';
DELETE FROM insight_brain_ods.proxy_server_configuration;
INSERT INTO insight_brain_ods.proxy_server_configuration (proxy_server_configuration_id, hostname, port, exclude_hosts) VALUES ('proxy-server-configuration', 'non-existing-hostname', 8800, '*.sonatype.com');
INSERT INTO insight_brain_ods.system_configuration_property (system_configuration_property_id, name, value) VALUES (md5(random()::text), 'internalFirewallOnboardingEnabled', false) on conflict do nothing;
EOF
}

function _iqConfigAPI() {
    local _d="$1"
    local _iq_url="$2"
    _iq_url="$(_get_iq_url "${_iq_url}")" || return $?
    local _cmd="curl -sSf -u \"admin:admin123\" \"${_iq_url%/}/api/v2/config"
    if [[ "${_d}" =~ ^property= ]]; then
        _cmd="${_cmd}?${_d}\""
    elif [ -n "${_d}" ]; then
        _cmd="${_cmd}\" -H \"Content-Type: application/json\" -X PUT -d '${_d}'"
    else
        _cmd="${_cmd}\""
    fi
    echo "${_cmd}"
    eval "${_cmd}" || return $?
}

# NOTE: Below will overwrite config.yml, so saving and restoring
# To upgrade (from ${_dirname}/): mv -v ./config.yml{,.orig} && tar -xvf $HOME/.nexus_executable_cache/nexus-iq-server-1.169.0-01-bundle.tar.gz && cp -p -v ./config.yml{.orig,}
function iqInstall() {
    if [ -s "$HOME/IdeaProjects/samples/bash/setup_nexus_iq.sh" ]; then
        source "$HOME/IdeaProjects/samples/bash/setup_nexus_iq.sh" || return $?
        f_install_iq "$@"
    fi
}

#iqDocker "nxiq-test" "" "8170" "8171" "8544" #"--read-only -v /tmp/nxiq-test:/tmp"
function iqDocker() {
    local _name="${1:-"nxiq"}"
    local _tag="${2:-"latest"}"
    local _port="${3:-"8070"}"
    local _port2="${4:-"8071"}"
    local _port_ssl="${5:-"8444"}"
    local _extra_opts="${6}"    # --platform=linux/amd64
    local _license="${7}"
    local _work_dir="${_WORK_DIR:-"/var/tmp/share"}"
    local _docker_host="${_DOCKER_HOST}"  #:-"dh1.standalone.localdomain:5000"

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
    [ -d "${_work_dir%/}" ] && _opts="${_opts} -v ${_work_dir%/}:/var/tmp/share:z"  # :z or :Z for SELinux https://docs.docker.com/storage/bind-mounts/#configure-the-selinux-label
    [ -d "${_nexus_data%/}" ] && _opts="${_opts} -v ${_nexus_data%/}:/sonatype-work"
    [ -s "${_nexus_data%/}/etc/config.yml" ] && _opts="${_opts} -v ${_nexus_data%/}/etc:/etc/nexus-iq-server"
    [ -d "${_nexus_data%/}/log" ] && _opts="${_opts} -v ${_nexus_data%/}/log:/var/log/nexus-iq-server"
    [ -d "${_nexus_data%/}/log" ] && _opts="${_opts} -v ${_nexus_data%/}/log:/opt/sonatype/nexus-iq-server/log" # due to audit.log => fixed from v104
    [ -n "${_extra_opts}" ] && _opts="${_opts} ${_extra_opts}"  # Should be last to overwrite
    [ -n "${_docker_host}" ] && _docker_host="${_docker_host%/}/"
    local _cmd="docker run -d -p ${_port}:8070 -p ${_port2}:8071 -p ${_port_ssl}:8444 ${_opts} ${_docker_host%/}sonatype/nexus-iq-server:${_tag}"  # --init
    echo "${_cmd}"
    eval "${_cmd}"
    echo "NOTE: May need to repalce /opt/sonatype/nexus-iq-server/start.sh to add trap SIGTERM (used from next restart though)"
    # Not doing at this moment as newer version has the fix.
    if false && docker cp ${_name}:/opt/sonatype/nexus-iq-server/start.sh - | grep -qwa TERM; then
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


### maven/mvn related
alias mvn-sbom='mvn org.cyclonedx:cyclonedx-maven-plugin:makeAggregateBom'

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
_REPO_URL="http://localhost:8081/repository/maven-snapshots/"
#_REPO_URL="http://dh1:8081/nexus/content/repositories/releases/"
_SNAPSHOT="-SNAPSHOT"
mvn-arch-gen
#mvn-deploy "${_REPO_URL}" "" "nexus"
for v in {1..3}; do
  for a in {1..3}; do
    for g in {1..3}; do
      sed -i.tmp -E "s@^  <groupId>.+</groupId>@  <groupId>com.example${g:-"0"}</groupId>@" pom.xml
      sed -i.tmp -E "s@^  <artifactId>.+</artifactId>@  <artifactId>my-app${a:-"0"}</artifactId>@" pom.xml
      sed -i.tmp -E "s@^  <version>.+</version>@  <version>1.${v:-"0"}${_SNAPSHOT}</version>@" pom.xml
      mvn-deploy "${_REPO_URL}" "" "" "nexus" "" || break
    done || break
  done || break
done
# Download test (need to use group repo):
set -x;mvn-get "com.example1:my-app2:1.3-SNAPSHOT" "http://dh1:8081/repository/maven-public/";set +x
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
    local _deploy_repo="${1:-"$(_get_rm_url)repository/maven-hosted/"}"
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
#_get_rm_url
#mvn-get-file "org.apache.httpcomponents:httpclient:4.5.13"
#mvn-dep-file httpclient-4.5.13.jar "com.example:my-app:1.0" "http://dh1.standalone.localdomain:8081/repository/maven-hosted/" "" "-Dclassifier=bin -Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS -U -X"
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
        # -Daether.checksums.algorithms="SHA256,SHA512"
        mvn `_mvn_settings "${_remote_repo}"` deploy:deploy-file -DcreateChecksum=true -DgroupId=${_g} -DartifactId=${_a} -Dversion=${_v} -DgeneratePom=true -Dfile=${_file} ${_options}
    fi
}

# Using NXRM3's upload (would not work with NXRM2), also this API does not work with snapshot repository
function mvn-upload() {
    local _file="${1}"
    local _gav="${2:-"com.example:my-app:1.0"}"
    local _remote_repo="${3:-"maven-hosted"}"
    local _nexus_url="${4:-"$(_get_rm_url)"}"
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
alias mvn-get='mvn-get-file'
function mvn-get-file() {
    local __doc__="It says mvn- but curl to get a single file with GAV."
    local _gav="${1:-"junit:junit:4.12"}"   # or org.yaml:snakeyaml:jar:1.23
    local _repo_url="${2:-"$(_get_rm_url)repository/maven-public/"}"
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
function mvn-get-with-dep() {
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
    local _get_repo="${2:-"$(_get_rm_url)repository/maven-public/"}"
    local _dep_repo="${3:-"$(_get_rm_url)repository/maven-snapshots/"}" # layout policy: strict may make request fail.
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

alias mvnResolve='mvn -s $HOME/IdeaProjects/m2_settings.xml dependency:resolve'
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
    if [ -z "${_settings_xml}" ] && [ -s "${HOME%/}/IdeaProjects/samples/runcom/m2_settings.xml" ]; then
        _settings_xml="./m2_settings.xml"
        cp ${HOME%/}/IdeaProjects/samples/runcom/m2_settings.xml ${_settings_xml} || return $?
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
    echo "npm install --package-lock-only"
}

alias npm-deploy='npmDeploy'
alias npmPublish='npmDeploy'
function npmDeploy() {
    local _repo_url="${1:-"$(_get_rm_url)repository/npm-hosted/"}"
    local _name="${2:-"lodash-vulnerable"}"
    local _ver="${3:-"1.0.0"}"
    #npm login --registry=$(_get_rm_url)repository/npm-hosted/
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

function nuget-get() {
    local _pkg="$1" # Syncfusion.SfChart.WPF@19.2.0.62
    local _repo_url="${2:-"$(_get_rm_url)repository/nuget.org-proxy/index.json"}"
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

#rg '".typeId": "script"' _filtered/db_job_details.json | extGroovy
function extGroovy() {
    sed "s/,$//" | while read -r _l;do echo "${_l}" | python -c "import sys,json;print(json.load(sys.stdin)['jobDataMap']['source'])" && echo "// --- end of script --- //" >&2; done
}

# Convert the DeadBlobsFinder result (deadBlobResult-YYYYMMDD-hhmmss.json) to a simple list
function nxrm3DBF2csv() {
    local _json_file="$1"
    python3 -c "import sys,json,re;js=json.load(open('${_json_file}'))
for k in js:
    for i in js[k]:
        print('\"%s\",\"%s\",\"%s\",\"%s\"' % (k, i[1], re.search(r'blob_ref:([^,\}]+)', i[0]).group(1), re.search(r'name=([^,\}]+)', i[0]).group(1)))"
}
#nxrm3DBF2csv deadBlobResult-20230707-220054.json | rg -o '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | xargs -I {} blobpath {} "" "/data/nexus/blobs/default/content/"
#cat nxrm3DBF2list.out | awk '{print $1}' | sort | uniq | while read -r _repo; do rg "\"name\": \"${_repo}\"" --no-filename -g db_repos.json ; done
