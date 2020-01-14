#!/usr/bin/env bash
# curl -o /var/tmp/share/patch_java.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/patch_java.sh
# TODO: currently the script filename needs to be "ClassName.scala" or "ClassName.java" (case sensitive)
#
# export CLASSPATH=`find . -name '*.jar' | tr '\n' ':'`.
# javac org/something/YourClass.java
# f_jargrep YourClass
# f_update_jar ./to/be/updated.jar YourClass
#
# or
#
# export CLASSPATH=`find /opt/sonatype/nexus/{system,lib} -name '*.jar' | tr '\n' ':'`.
# /var/tmp/share/patch_java.sh "" YourClass.java /opt/sonatype/nexus/system/
#

function usage() {
    cat << EOS
Patch one class file by compiling and updating one jar

\$ bash $0 <port> <ClassName>.[java|scala] <some.jar> [specific_ClassName] [not_compile]

    <port>: Port number to get a PID.
    <ClassName>.[java|scala]: A file path of your java or scala file.
    <some.jar>: A file path to your jar file which will be updated. If a dir, search jars for your class.
    [specific_ClassName]: Sometimes filename is not equal to actual classname.
    [not_compile]: If 'Y', not compiling.

Or, to start scala console (REPL):

\$ source /var/tmp/share/patch_java.sh
\$ f_scala [<port>]
EOS
}

function f_setup_scala() {
    local _ver="${1:-2.12.3}"
    local _extract_dir="${2:-/var/tmp/share}"
    local _inst_dir="${3:-/usr/local/scala}"

    if [ -d "$SCALA_HOME" ]; then
        echo "SCALA_HOME is already set so that skipping setup."
        return
    fi

    if [ ! -x ${_inst_dir%/}/bin/scala ]; then
        if [ ! -d "${_extract_dir%/}/scala-${_ver}" ]; then
            if [ ! -s "${_extract_dir%/}/scala-${_ver}.tgz" ]; then
                curl --retry 3 -C - -o "${_extract_dir%/}/scala-${_ver}.tgz" -L "https://downloads.lightbend.com/scala/${_ver}/scala-${_ver}.tgz" || return $?
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
    local _ver="${1:-2.5.7}"
    local _extract_dir="${2:-/var/tmp/share}"
    local _inst_dir="${3:-/usr/local/groovy}"

    if [ -d "$GROOVY_HOME" ]; then
        echo "GROOVY_HOME is already set so that skipping setup."
        return
    fi

    if [ ! -x ${_inst_dir%/}/bin/groovysh ]; then
        if [ ! -d "${_extract_dir%/}/groovy-${_ver}" ]; then
            if [ ! -s "${_extract_dir%/}/apache-groovy-binary-${_ver}.zip" ]; then
                curl --retry 3 -C - -o "${_extract_dir%/}/apache-groovy-binary-${_ver}.zip" -L "https://bintray.com/artifact/download/groovy/maven/apache-groovy-binary-${_ver}.zip" || return $?
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
    local _extract_dir="${2:-/var/tmp/share}"
    local _inst_dir="${3:-/usr/local/spring-boot-cli}"

    if [ -d "$SPRING_CLI_HOME" ]; then
        echo "SPRING_CLI_HOME is already set so that skipping setup."
        return
    fi

    if [ ! -x ${_inst_dir%/}/bin/spring ]; then
        if [ ! -d "${_extract_dir%/}/spring-${_ver}.RELEASE" ]; then
            if [ ! -s "${_extract_dir%/}/spring-boot-cli-${_ver}.RELEASE-bin.tar.gz" ]; then
                curl --retry 3 -C - -o "${_extract_dir%/}/spring-boot-cli-${_ver}.RELEASE-bin.tar.gz" -L "https://repo.spring.io/release/org/springframework/boot/spring-boot-cli/${_ver}.RELEASE/spring-boot-cli-${_ver}.RELEASE-bin.tar.gz" || return $?
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
    local _port="${1}"
    if [ -z "${_port}" ]; then
        if [ -n "$JAVA_HOME" ] && [ -n "$CLASSPATH" ]; then
            echo "No port is given but JAVA_HOME and CLASSPATH are already set."
            return 0
        else
            echo "No port number to find PID. Manually set JAVA_HOME and CLASSPATH."
            return 10
        fi
    fi
    local _p=`lsof -ti:${_port} -s TCP:LISTEN`
    if [ -z "${_p}" ]; then
        if [ -n "$JAVA_HOME" ] && [ -n "$CLASSPATH" ]; then
            echo "No PID found from ${_port} but JAVA_HOME and CLASSPATH are already set."
            return 0
        else
            echo "Nothing running on port ${_port}. Manually set JAVA_HOME and CLASSPATH."
            return 11
        fi
    fi
    local _user="`stat -c '%U' /proc/${_p}`"
    if [ -z "$JAVA_HOME" ]; then
        local _dir="$(dirname `readlink /proc/${_p}/exe` 2>/dev/null)"
        export JAVA_HOME="$(dirname ${_dir})"
    fi
    local _jcmd="$JAVA_HOME/bin/jcmd"
    if [ ! -x $JAVA_HOME/bin/jcmd ]; then
        _jcmd="$(find /var/tmp/share/java -executable -name jcmd | tail -n 1)"
    fi
    if [ -x "${_jcmd}" ]; then
        if [ -z "$CLASSPATH" ]; then
            export CLASSPATH=".:`sudo -u ${_user} ${_jcmd} ${_p} VM.system_properties | sed -nr 's/^java.class.path=(.+$)/\1/p' | sed 's/[\]:/:/g'`"
        else
            export CLASSPATH="${CLASSPATH%:}:`sudo -u ${_user} ${_jcmd} ${_p} VM.system_properties | sed -nr 's/^java.class.path=(.+$)/\1/p' | sed 's/[\]:/:/g'`"
        fi
    else
        echo "WARN: Couldn't not set CLASSPATH because of no executable jcmd found."; sleep 3
    fi
    export _CWD="$(realpath /proc/${_p}/cwd)"
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
    groovysh
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

function f_jargrep() {
    local _class="${1}"
    local _path="${2:-.}"
    local _cmd="less"
    if [ -e $JAVA_HOME/bin/jar ]; then
        _cmd="$JAVA_HOME/bin/jar -tf"
    elif which jar &>/dev/null; then
        _cmd="jar -tf"
    fi
    find -L ${_path%/} -type f \( -name '*.jar' -or -name '*.war' \) -print0 | xargs -0 -n1 -I {} bash -c "${_cmd} {} 2>/dev/null | grep -w '${_class}' && echo '^ Jar: {}'" >&2
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
    if [ ! -s "${_jar_filename}.orig" ]; then
        cp -p ${_jar_filepath} ${_jar_filename}.orig || return $?
    fi

    if [ ! -d "${_compiled_dir}" ]; then
        _compiled_dir="`dirname "$(find . -name "${_class_name}.class" -print | tail -n1)"`"
        if [ "${_compiled_dir}" = "." ] || [ -z "${_compiled_dir}" ]; then
            echo "Please check 'package' of your class or check ${_class_name}.class file under ${_compiled_dir}"
            return 1
        fi
    fi

    local _class_file_path="${_compiled_dir%/}/*.class"
    [ -n "${_updating_specific_class}" ] && _class_file_path="${_compiled_dir%/}/${_updating_specific_class}[.$]*class"

    echo "Updating ${_jar_filepath} with ${_class_file_path} ..."
    #local _updated_date="$(date | sed -r 's/[0-9][0-9]:[0-9][0-9]:[0-9][0-9].+//')"
    local _updated_time="$(date | grep -oE ' [0-9][0-9]:[0-9][0-9]:[0-9]')"
    $JAVA_HOME/bin/jar -uvf ${_jar_filepath} ${_class_file_path} || return $?
    echo "------------------------------------------------------------------------------------"
    echo "Checking if any non-updated class... (zip -d ${_jar_filepath} '/path/to/class')"
    $JAVA_HOME/bin/jar -tvf ${_jar_filepath} | grep -w ${_class_name} | grep -v "${_updated_time}"

    cp -f ${_jar_filepath} ${_jar_filename}.patched
    return 0
}

### Main ###############################
if [ "$0" = "$BASH_SOURCE" ]; then
    _PORT="$1"
    _CLASS_FILEPATH="$2"
    _JAR_FILEPATH="$3"
    _UPDATING_CLASSNAME="$4"
    _NOT_COMPILING="$5"

    if [ -z "$JAVA_HOME" ] && [ -z "$CLASSPATH" ] && [ -z "$_PORT" ]; then
        echo "A port number (1st arg) to find PID is required."
        usage
        exit 1
    fi

    f_javaenvs "$_PORT" || exit $?
    [ -z "${_JAR_FILEPATH}" ] && _JAR_FILEPATH="${_CWD}"

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
            [ -n "${_UPDATING_CLASSNAME}" ]  && f_jargrep "${_UPDATING_CLASSNAME}.class" "${_JAR_FILEPATH}"
            echo "Please pick a jar file from above, and re-run the script:
$0 '$1' '$2' '<jar path from above>' '$4' [Y]"
            exit 0
        fi

        if [ "${_EXT}" = "scala" ]; then
            f_setup_scala
            _CMD="scalac"
        elif [ "${_EXT}" = "java" ]; then
            if [ -n "${_JAR_FILEPATH}" ] && [ -e "${_JAR_FILEPATH}" ]; then
                _DIR_PATH="$(dirname $($JAVA_HOME/bin/jar -tvf ${_JAR_FILEPATH} | grep -oE "[^ ]+${_CLASS_NAME}.class"))"
                if [ ! -d "${_DIR_PATH}" ]; then
                    mkdir -p "${_DIR_PATH}" || exit $?
                fi
                if [ "$(realpath ${_CLASS_FILEPATH})" != "$(realpath ${_DIR_PATH%/}/${_CLASS_FILENAME})" ]; then
                    cp -f ${_CLASS_FILEPATH} ${_DIR_PATH%/}/ || exit $?
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