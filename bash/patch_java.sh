#!/usr/bin/env bash
# DOWNLOAD:
# curl -o /var/tmp/share/java/patch_java.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/patch_java.sh
#
# REQUIRED: lsof, realpath
# NOTE: each function should be usable by just copying & pasting (no external function)
#

# Location to store downloaded JDK
_JAVA_DIR="${_JAVA_DIR:-"/var/tmp/share/java"}"

function usage() {
    cat << EOS
Patch one Java/Scala class file by injecting into one jar.

\$ bash $0 <port> <ClassName>.[java|scala] <some.jar> [specific_ClassName] [not_compile]

    <port>: Port or Directory path (mainly for Mac).
    <ClassName>.[java|scala]: A file path of your java or scala file.
    <some.jar>: A file path of your updating jar file. If a directory, search jars for your class.
    [specific_ClassName]: Sometimes filename is not equal to actual classname.
    [dir_detect_regex]: Sometimes same classname exist in multiple directories.
    [not_compile]: If 'Y', not compiling. Used when a class is already compiled.

If no process or no port, use f_javaenvs. For example:
    f_javaenvs /opt/sonatype/nexus-3.33.0

To start console (REPL):
    source ./patch_java.sh
    f_jshell [<port>]
    f_groovy [<port>]
    f_scala [<port>]
    f_spring_cli [<port>]
EOS
}

# copied from setup_work.env.sh and modified
function f_setup_java() {
    local _v="${1:-"8"}" # Using 8 as JayDeBeApi uses specific version and which is for java 8
    local _filter="${2:-"jdk_x64_linux"}" # (jdk|jre)_x64_(linux|mac)
    local _ver="${_v}"  # Java version can be "9" or "1.8"
    [[ "${_v}" =~ ^[678]$ ]] && _ver="1.${_v}"
    [ ! -d "${_JAVA_DIR%/}" ] && mkdir -p -m 777 ${_JAVA_DIR%/}

    # If Linux, downloading .tar.gz file and extract, so that it can be re-used in the container
    # NOTE: with grep or sed, without --compressed is faster
    #local _java_exact_ver="$(basename $(curl -s https://github.com/AdoptOpenJDK/openjdk${_v}-binaries/releases/latest | _sed -nr 's/.+"(https:[^"]+)".+/\1/p'))"
    curl -sf -L "https://api.adoptopenjdk.net/v3/assets/latest/${_v}/hotspot?release=latest&jvm_impl=hotspot&vendor=adoptopenjdk" -o /tmp/java_${_v}_latest.json || return $?
    local _java_exact_ver="$(grep -m1 -E '"release_name": "jdk-?'${_v}'.[^"]+"' /tmp/java_${_v}_latest.json | grep -oE 'jdk-?'${_v}'[^"]+')"
    # NOTE: hoping the naming rule is same for different versions (eg: jdk8u275-b01, jdk-11.0.9.1+1)
    if [[ ! "${_java_exact_ver}" =~ (jdk-?)([^-+]+)([-+])([^_]+) ]]; then
        echo "Could not determine the download-able version by using ${_v}."
        return 1
    fi
    local _dl_url="$(sed -nE 's/^ *"link": *"(.+'${_filter}'.+)",?$/\1/p' /tmp/java_8_latest.json)"
    if [ -z "${_dl_url}" ]; then
        echo "Could not determine the download-URL by using ${_java_exact_ver}."
        return 1
    fi

    local _fname="$(basename "${_dl_url}")"
    echo "Downloading ${_dl_url} ..."
    if [ ! -s "${_JAVA_DIR%/}/${_fname}" ]; then
        curl --retry 3 -C - -o "${_JAVA_DIR%/}/${_fname}" -f -L "${_dl_url}" || return $?
    fi

    tar -xf "${_JAVA_DIR%/}/${_fname}" -C ${_JAVA_DIR%/}/ || return $?
    echo "OpenJDK${_v} is extracted under '${_JAVA_DIR%/}/${_java_exact_ver}'"

    if [ -d /etc/profile.d ] && [ ! -f /etc/profile.d/java.sh ]; then
        echo "Creating /etc/profile.d/java.sh ... (sudo required)"
        cat << EOF > /tmp/java.sh
[[ "\$PATH" != *"${_JAVA_DIR%/}/"* ]] && export PATH=${_JAVA_DIR%/}/${_java_exact_ver}/bin:\${PATH#:}
[ -z "\${JAVA_HOME}" ] && export JAVA_HOME=${_JAVA_DIR%/}/${_java_exact_ver}
EOF
        sudo mv /tmp/java.sh /etc/profile.d/java.sh && source /etc/profile.d/java.sh
        if ! java -version 2>&1 | grep -w "build ${_ver}" -m 1; then
            echo "WARN Current Java version is not ${_ver}."
            return 1
        fi
    else
        echo "Not updating /etc/profile.d/java.sh with ${_JAVA_DIR%/}/${_java_exact_ver}"
    fi
}

function f_setup_scala() {
    local _ver="${1:-2.12.3}"
    local _extract_dir="${2:-"${_JAVA_DIR}"}"
    local _inst_dir="${3:-/usr/local/scala}"

    if [ -d "$SCALA_HOME" ]; then
        echo "SCALA_HOME is already set so that skipping setup."
        return
    fi

    if [ ! -x ${_inst_dir%/}/bin/scala ]; then
        if [ ! -d "${_extract_dir%/}/scala-${_ver}" ]; then
            if [ ! -s "${_extract_dir%/}/scala-${_ver}.tgz" ]; then
                curl --retry 3 -C - -o "${_extract_dir%/}/scala-${_ver}.tgz" -f -L "https://downloads.lightbend.com/scala/${_ver}/scala-${_ver}.tgz" || return $?
            fi
            tar -xf "${_extract_dir%/}/scala-${_ver}.tgz" -C "${_extract_dir%/}/" || return $?
        fi
        chmod a+x ${_extract_dir%/}/scala-${_ver}/bin/*
        [ -d "${_inst_dir%/}" ] || ln -s "${_extract_dir%/}/scala-${_ver}" "${_inst_dir%/}"
    fi
    export SCALA_HOME=${_inst_dir%/}
    [[ ":$PATH:" != *":${SCALA_HOME}/bin:"* ]] && export PATH=$PATH:${SCALA_HOME}/bin
}

function f_setup_groovy() {
    local _ver="${1:-2.4.17}"   # This version is for NXRM3
    local _extract_dir="${2:-"${_JAVA_DIR}"}"
    local _inst_dir="${3:-/usr/local/groovy}"

    if [ -d "$GROOVY_HOME" ]; then
        echo "GROOVY_HOME is already set so that skipping setup."
        return
    fi

    if [ ! -x ${_inst_dir%/}/bin/groovysh ]; then
        if [ ! -d "${_extract_dir%/}/groovy-${_ver}" ]; then
            if [ ! -s "${_extract_dir%/}/apache-groovy-binary-${_ver}.zip" ]; then
                curl --retry 3 -C - -o "${_extract_dir%/}/apache-groovy-binary-${_ver}.zip" -f -L "https://bintray.com/artifact/download/groovy/maven/apache-groovy-binary-${_ver}.zip" || return $?
            fi
            unzip "${_extract_dir%/}/apache-groovy-binary-${_ver}.zip" -d "${_extract_dir%/}/" || return $?
        fi
        chmod a+x ${_extract_dir%/}/groovy-${_ver}/bin/*
        [ -d "${_inst_dir%/}" ] || ln -s "${_extract_dir%/}/groovy-${_ver}" "${_inst_dir%/}"
    fi
    export GROOVY_HOME=${_inst_dir%/}
    [[ ":$PATH:" != *":${GROOVY_HOME}/bin:"* ]] && export PATH=$PATH:${GROOVY_HOME}/bin
}

function f_setup_spring_cli() {
    local _ver="${1:-2.2.2}"
    local _extract_dir="${2:-"${_JAVA_DIR}"}"
    local _inst_dir="${3:-/usr/local/spring-boot-cli}"

    if [ -d "$SPRING_CLI_HOME" ]; then
        echo "SPRING_CLI_HOME is already set so that skipping setup."
        return
    fi

    if [ ! -x ${_inst_dir%/}/bin/spring ]; then
        if [ ! -d "${_extract_dir%/}/spring-${_ver}.RELEASE" ]; then
            if [ ! -s "${_extract_dir%/}/spring-boot-cli-${_ver}.RELEASE-bin.tar.gz" ]; then
                curl --retry 3 -C - -o "${_extract_dir%/}/spring-boot-cli-${_ver}.RELEASE-bin.tar.gz" -f -L "https://repo.spring.io/release/org/springframework/boot/spring-boot-cli/${_ver}.RELEASE/spring-boot-cli-${_ver}.RELEASE-bin.tar.gz" || return $?
            fi
            tar -xf "${_extract_dir%/}/spring-boot-cli-${_ver}.RELEASE-bin.tar.gz" -C "${_extract_dir%/}/" || return $?
        fi
        chmod a+x ${_extract_dir%/}/spring-${_ver}.RELEASE/bin/*
        [ -d "${_inst_dir%/}" ] || ln -s "${_extract_dir%/}/spring-${_ver}.RELEASE" "${_inst_dir%/}"
    fi
    export SPRING_CLI_HOME=${_inst_dir%/}
    [[ ":$PATH:" != *":${SPRING_CLI_HOME}/bin:"* ]] && export PATH=$PATH:${SPRING_CLI_HOME}/bin
}

function f_javaenvs() {
    local _port_or_dir="${1}"  # or directory path
    local _user="$USER"

    if [ -n "$JAVA_HOME" ] && [ -n "$CLASSPATH" ]; then
        echo "JAVA_HOME and CLASSPATH are already set. Skipping f_javaenvs..."
        return 0
    fi

    if [ -z "${_port_or_dir}" ]; then
        echo "_port_or_dir is empty. Please manually set JAVA_HOME and CLASSPATH."
        return 10
    fi

    if [ ! -d "${_port_or_dir}" ]; then
        local _p="$(lsof -ti:${_port_or_dir} -s TCP:LISTEN)"
        if [ -z "${_p}" ]; then
            echo "Nothing running on port:${_port_or_dir}. Manually set JAVA_HOME and CLASSPATH."
            return 11
        fi
        _user="$(lsof -nP -p ${_p} | head -n2 | tail -n1 | awk '{print $3}')"   # This is slow but stat -c '%U' doesn't work on Mac
        [ -z "${_user}" ] && _user="$USER"
        export _CWD="$(realpath /proc/${_p}/cwd 2>/dev/null)"
    fi

    local _jcmd="$(_find_jcmd "${_port_or_dir}")"
    [ -z "${JAVA_HOME}" ] && [ -n "${_jcmd}" ] && export JAVA_HOME="$(dirname $(dirname ${_jcmd}))"
    if [ -z "${JAVA_HOME}" ]; then
        echo "WARN: Couldn't not set JAVA_HOME (by using jcmd location). Please set JAVA_HOME for javac and jar commands."
        return 1
    fi

    if [ -x "${_jcmd}" ]; then
        if [ -z "$CLASSPATH" ]; then
            f_set_classpath "${_port_or_dir}" "${_user}"
            _set_extra_classpath "${_port_or_dir}"  # If dir, will be just ignored
        else
            echo "INFO: CLASSPATH is already set, so not overwriting/appending."
        fi
    else
        echo "WARN: Couldn't not set CLASSPATH because of no executable jcmd found."; sleep 3
    fi
}

function _find_jcmd() {
    # _set_java_home 8081 "${_JAVA_DIR%/}"
    local _port="${1}"
    local _search_path="${2:-"${_JAVA_DIR}"}"   # Extra search location in case JAVA_HOME doesn't work
    local _java_home="${3:-"$JAVA_HOME"}"

    local _java_ver_str=""
    if [ -z "${_java_home}" ]; then
        local _p=`lsof -ti:${_port} -s TCP:LISTEN 2>/dev/null`
        if [ -n "${_p}" ]; then
            local _dir="$(dirname "$(readlink /proc/${_p}/exe)" 2>/dev/null)"
            _java_home="$(dirname "${_dir}")"
            _java_ver_str="$(/proc/${_p}/exe -version 2>&1 | grep -oE ' version .+')"
        fi
    fi

    local _jcmd="$(which jcmd 2>/dev/null)"
    [ -n "${_java_home}" ] && _jcmd="${_java_home}/bin/jcmd"    # if JAVA_HOME is set, overwrite
    if [ ! -x "${_jcmd}" ]; then
        _jcmd=""
        if [ -n "${_java_ver_str}" ]; then
            # Somehow the scope of "while" is local...
            for _j in $(find ${_search_path%/} -executable -name jcmd | grep -vw archives); do
                if $(dirname "${_j}")/java -version 2>&1 | grep -q "${_java_ver_str}"; then
                    _jcmd="$_j"
                    break
                fi
            done
        fi
    fi
    echo "${_jcmd}"
}

function f_set_classpath() {
    local _port_or_dir="${1}"  # port or directory path
    if [ -d "${_port_or_dir}" ]; then
        local _tmp_cp="$(find ${_port_or_dir%/} -type f -name '*.jar' | tr '\n' ':')"
        export CLASSPATH=".:${_tmp_cp%:}"
    else
        local _p=`lsof -ti:${_port} -s TCP:LISTEN` || return $?
        local _user="$(lsof -nP -p ${_p} | head -n2 | tail -n1 | awk '{print $3}')" # This is slow but stat -c '%U' doesn't work on Mac
        local _jcmd="$(_find_jcmd "${_port}")" || return $?
        # requires jcmd in the path
        export CLASSPATH=".:`sudo -u ${_user:-"$USER"} ${_jcmd} ${_p} VM.system_properties | _sed -nr 's/^java.class.path=(.+$)/\1/p' | _sed 's/[\]:/:/g'`"
    fi
}

function _set_extra_classpath() {
    # _set_extra_classpath 8081 "${_JAVA_DIR%/}/lib"
    # _EXTRA_LIB="${_JAVA_DIR%/}/lib" _set_extra_classpath 8081
    local _port="${1}"
    local _extra_lib="${2-${_EXTRA_LIB}}"
    local _classpath=""

    if [ "${_port}" == "8081" ] && [ -d "/usr/tmp/share/java/lib" ]; then
        # At this moment, not considering dups
        _classpath="${CLASSPATH%:}:$(find /usr/tmp/share/java/lib -type f -name '*.jar' | tr '\n' ':')"
        export CLASSPATH="${_classpath%:}"
    fi

    if [ "${_port}" == "8081" ] && [ -d "/opt/sonatype/nexus/system" ]; then
        # At this moment, not considering dups
        _classpath="${CLASSPATH%:}:$(find /opt/sonatype/nexus/system -type f -name '*.jar' | tr '\n' ':')"
        export CLASSPATH="${_classpath%:}"
    fi

    if [ "${_port}" == "8081" ] && [ -d "/opt/sonatype/nexus/lib" ]; then
        # At this moment, not considering dups
        _classpath="${CLASSPATH%:}:$(find /opt/sonatype/nexus/lib -type f -name '*.jar' | tr '\n' ':')"
        export CLASSPATH="${_classpath%:}"
    fi

    # using extra_dir only when no CLASSPATH set, otherwise, CLASSPATH can be super long
    if [ -d "${_extra_lib}" ]; then
        # It might contain another groovy jar but might be a different version, but as it should be using 2.4, should be OK
        #local _extra_classpath=$(find ${_extra_lib%/} -name '*.jar' -not -name 'groovy-*.jar' -print | tr '\n' ':')
        local _extra_classpath=$(find ${_extra_lib%/} -name '*.jar' -print | tr '\n' ':')
        export CLASSPATH="${_extra_classpath%:}:${CLASSPATH%:}"
    fi
}

function f_jargrep() {
    local _class="${1}"
    local _path="${2:-.}"
    local _cmd="less"
    if [ -e $JAVA_HOME/bin/jar ]; then
        _cmd="$JAVA_HOME/bin/jar -tf"
    elif which jar &>/dev/null; then
        _cmd="jar -tf"
    fi
    # NOTE: xargs behaves differently on Mac, so stopped using
    find -L ${_path%/} -type f -name '*.jar' | while read -r _l; do
        ${_cmd} "${_l}" 2>/dev/null | grep -wE "${_class}" && echo "^ Jar: ${_l}" >&2
    done
}

function f_update_jar() {
    local _jar_filepath="$1"
    local _class_name="$2"
    local _updating_specific_class="$3" # optional
    local _compiled_dir="${_class_name}"

    if [ ! -d "$JAVA_HOME" ]; then
        echo "JAVA_HOME is not set. Use 'f_javaenvs <port>'."
        return 1
    fi

    local _jar_filename="$(basename ${_jar_filepath})"
    cp -p ${_jar_filepath} ./${_jar_filename} || return $?
    if [ ! -s "${_jar_filename}.orig" ]; then
        cp -p ${_jar_filepath} ./${_jar_filename}.orig || return $?
    fi

    if [ ! -d "${_compiled_dir}" ]; then
        _compiled_dir="`dirname "$(find . -name "${_class_name}.class" -print | tail -n1)"`"
        if [ "${_compiled_dir}" = "." ] || [ -z "${_compiled_dir}" ]; then
            echo "${_class_name}.class shouldn't be located under ${_compiled_dir}."
            return 1
        fi
    fi

    local _class_file_path="${_compiled_dir%/}/*.class"
    [ -n "${_updating_specific_class}" ] && _class_file_path="${_compiled_dir%/}/${_updating_specific_class}[.$]*class"

    echo "Updating ./${_jar_filename} with ${_class_file_path} ..."
    #local _updated_date="$(date | _sed -r 's/[0-9][0-9]:[0-9][0-9]:[0-9][0-9].+//')"
    local _updated_time="$(date | grep -oE ' [0-9][0-9]:[0-9][0-9]:[0-9]')"
    $JAVA_HOME/bin/jar -uvf ./${_jar_filename} ${_class_file_path} || return $?
    echo "------------------------------------------------------------------------------------"
    echo "Checking if any non-updated class... (zip -d ${_jar_filepath} '/path/to/class')"
    $JAVA_HOME/bin/jar -tvf ./${_jar_filename} | grep -w ${_class_name} | grep -v "${_updated_time}"

    cp -p -f ./${_jar_filename} ${_jar_filename}.patched || return $?
    echo "Moving ./${_jar_filename} to ${_jar_filepath} (may ask yes or no) ..."
    ls -l ./${_jar_filename} ${_jar_filepath} || return $?
    mv ./${_jar_filename} ${_jar_filepath} || return $?
    return 0
}

# https://hadoop-and-hdp.blogspot.com/2016/11/jcmd-managementagent.html
function f_jcmd_agent() {
    local _port="${1}"
    local _agent_port="${2:-"1099"}"
    local _p="$(lsof -ti:${_port} -s TCP:LISTEN)" || return $?
    local _user="$(lsof -nP -p ${_p} | head -n2 | tail -n1 | awk '{print $3}')" # This is slow but stat -c '%U' doesn't work on Mac
    local _jcmd="$(_find_jcmd "${_port}")" || return $?
    sudo -u ${_user:-"$USER"} ${_jcmd} ${_p} ManagementAgent.start jmxremote.port=${_agent_port} jmxremote.authenticate=false jmxremote.ssl=false || return $?
    sudo -u ${_user:-"$USER"} $(dirname "${_jcmd}")/jstat -J-Djstat.showUnsupported=true -snap ${_p} | grep '\.remoteAddress=' || return $?
    echo "# To stop: 'sudo -u ${_user:-"$USER"} ${_jcmd} ${_p} ManagementAgent.stop'"
}

function f_scala() {
    local _port="${1}"
    local _cded=false
    f_setup_scala
    if [[ "${_port}" =~ ^[0-9]+$ ]]; then
        f_javaenvs "${_port}"
        cd "${_CWD}" && _cded=true
    else
        echo "No port, so not detecting/setting JAVA_HOME and CLASSPATH...";sleep 3
    fi
    scala
    ${_cded} && cd -
}

function f_groovy() {
    local _port="${1}"
    local _cded=false
    f_setup_groovy
    if [[ "${_port}" =~ ^[0-9]+$ ]]; then
        f_javaenvs "${_port}"
        cd "${_CWD}" && _cded=true
    else
        echo "No port, so not detecting/setting JAVA_HOME and CLASSPATH...";sleep 3
    fi
    groovysh -e ":set interpreterMode true" # -cp $CLASSPATH
    ${_cded} && cd -
}

function f_spring_cli() {
    local _port="${1}"
    local _cded=false
    f_setup_spring_cli
    if [[ "${_port}" =~ ^[0-9]+$ ]]; then
        f_javaenvs "${_port}"
        cd "${_CWD}" && _cded=true
    else
        echo "No port, so not detecting/setting JAVA_HOME and CLASSPATH...";sleep 3
    fi
    spring shell
    ${_cded} && cd -
}

# Start Java Shell (available from Java 9)
function f_jshell() {
    local _port="${1}"
    if [[ "${_port}" =~ ^[0-9]+$ ]]; then
        f_javaenvs "${_port}"
    else
        echo "No port, so not detecting/setting JAVA_HOME and CLASSPATH...";sleep 3
    fi

    if [ -d "${JAVA_HOME}" ] && [ -x "${JAVA_HOME%/}/bin/jshell" ]; then
        eval "${JAVA_HOME%/}/bin/jshell"
    elif type jshell &>/dev/null; then
        jshell
    else
        local _jshell="$(find ${_JAVA_DIR%/} -maxdepth 3 -name jshell | sort | tail -n1)" || return $?
        [ -x "${_jshell}" ] && eval "${_jshell}"
    fi
}

function _sed() {
    local _cmd="sed"; which gsed &>/dev/null && _cmd="gsed"
    if ${_SUDO_SED}; then
        sudo ${_cmd} "$@"
    else
        ${_cmd} "$@"
    fi
}


### Main ###############################
if [ "$0" = "$BASH_SOURCE" ]; then
    _PORT="$1"  # Or directory path
    _CLASS_FILEPATH="$2"
    _JAR_FILEPATH="$3"
    _UPDATING_CLASSNAME="$4"
    _DIR_DETECT_REGEX="$5"
    _NOT_COMPILING="$6"

    if [ "$#" -eq 0 ]; then
        echo "A port number (1st arg) to find PID is required."
        usage
        exit 1
    fi

    f_javaenvs "$_PORT" || exit $?
    if [ -z "${_JAR_FILEPATH}" ]; then
        if [ -d "${_PORT}" ]; then
            _JAR_FILEPATH="${_PORT}"
        else
            _JAR_FILEPATH="${_CWD:="."}"
        fi
    fi

    # If _CLASS_FILEPATH is given, compiling.
    if [ -n "${_CLASS_FILEPATH}" ]; then
        _CLASS_FILENAME="$(basename "${_CLASS_FILEPATH}")"
        if [ -z "${_UPDATING_CLASSNAME}" ]; then
            _CLASS_NAME="${_CLASS_FILENAME%.*}"
        else
            _CLASS_NAME="${_UPDATING_CLASSNAME}"
        fi
        _EXT="${_CLASS_FILENAME##*.}"

        if [ -n "${_JAR_FILEPATH}" ] && [ -d "${_JAR_FILEPATH}" ]; then
            f_jargrep "${_CLASS_NAME}.class" "${_JAR_FILEPATH}"
            [ -n "${_UPDATING_CLASSNAME}" ]  && f_jargrep "${_UPDATING_CLASSNAME}\.class" "${_JAR_FILEPATH}"
            echo "Please pick a jar file from above, and re-run the script:
$0 '$1' '$2' '<jar path from above>' '$4' '$5' [Y]"
            exit 0
        fi

        if [ "${_EXT}" = "scala" ]; then
            f_setup_scala
            _CMD="scalac"
        elif [ "${_EXT}" = "java" ]; then
            if [ -n "${_JAR_FILEPATH}" ] && [ -e "${_JAR_FILEPATH}" ]; then
                # TODO: not sure adding "/" before _CLASS_NAME is OK
                _DIR_PATH="$(dirname $($JAVA_HOME/bin/jar -tvf ${_JAR_FILEPATH} | grep -oE "${_DIR_DETECT_REGEX:-"[^ ]+"}/${_CLASS_NAME}.class"))"
                if [ ! -d "${_DIR_PATH}" ]; then
                    mkdir -p "${_DIR_PATH}" || exit $?
                fi
                if [ "$(realpath ${_CLASS_FILEPATH})" != "$(realpath ${_DIR_PATH%/}/${_CLASS_FILENAME})" ]; then
                    cp -p -f ${_CLASS_FILEPATH} ${_DIR_PATH%/}/ || exit $?
                fi
                _CLASS_FILEPATH=${_DIR_PATH%/}/${_CLASS_FILENAME}
            fi

            _CMD="$JAVA_HOME/bin/javac"
        fi

        if [ -z "${_NOT_COMPILING}" ]; then
            # to avoid Java heap space error (default seems to be set to 256m)
            JAVA_OPTS=-Xmx1024m ${_CMD} "${_CLASS_FILEPATH}" || exit $?
        fi
    fi

    # If _JAR_FILEPATH is given, updating the jar
    if [ -n "${_JAR_FILEPATH}" ] && [ -e "${_JAR_FILEPATH}" ] && [ -n "${_CLASS_NAME}" ]; then
        f_update_jar "${_JAR_FILEPATH}" "${_CLASS_NAME}" "${_UPDATING_CLASSNAME}" || exit $?
        echo "Completed. Please restart the process (current PID=`lsof -ti:${_PORT} -s TCP:LISTEN 2>/dev/null`)."
    else
        echo "No jar filepath or class name to update."
    fi
fi