#!/usr/bin/env bash
# DOWNLOAD:
# curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/patch_java_v2.sh
#
# NOTE: each function should be usable by just copying & pasting (no external function)
#
# Extra tips
#   jar -xvf ../nexus-3.79.1-04/bin/sonatype-nexus-repository-3.80.0-02.jar
#   jar -cvf ../sonatype-nexus-repository-3.80.0-02_patched.jar ./*   # extracted_modified_files
#

# Location to store downloaded JDK
_JAVA_DIR="${_JAVA_DIR:-"/var/tmp/share/java"}"
_TARGET="${_TARGET:-"./target"}"

function usage() {
    cat << EOS
Patch Nexus Repository 3.78 and higher

\$ bash $0 {main_jar_file} {main_jar_file} {class_file} [{extract_dir}]

    {main_jar_file} is the jar file which contains many jar files
    {jar_file} is the jar file to be patched
    {class_file} is the path to the modified .java/.class file
    {extract_dir} is the directory to extract the jar file (default: current directory)
EOS
}

function f_javaenvs() {
    local _lib_dir="${1}"  # or directory path
    local _user="$USER"

    if [ -n "$JAVA_HOME" ] && [ -n "$CLASSPATH" ]; then
        echo "JAVA_HOME and CLASSPATH are already set. Skipping f_javaenvs..."
        return 0
    fi

    if [ -z "${_lib_dir}" ]; then
        echo "_lib_dir is empty. Please manually set JAVA_HOME and CLASSPATH."
        return 10
    fi

    local _jcmd="$(_find_jcmd "${_lib_dir}")"
    [ -z "${JAVA_HOME}" ] && [ -n "${_jcmd}" ] && export JAVA_HOME="$(dirname $(dirname ${_jcmd}))"
    if [ -z "${JAVA_HOME}" ]; then
        echo "WARN: Couldn't not set JAVA_HOME (by using jcmd location). Please set JAVA_HOME for javac and jar commands."
        return 1
    fi

    if [ -x "${_jcmd}" ]; then
        if [ -z "$CLASSPATH" ]; then
            f_set_classpath "${_lib_dir}" "${_user}"
            _set_extra_classpath "${_lib_dir}"  # If dir, will be just ignored (only _EXTRA_LIB is used)
        else
            echo "INFO: CLASSPATH is already set, so not overwriting/appending."
        fi
    else
        echo "WARN: Couldn't not set CLASSPATH because of no executable jcmd found."; sleep 3
    fi
}

function f_set_classpath() {
    local _lib_dir="${1}"  # directory path
    if [ -d "${_lib_dir}" ]; then
        # NOTE: wouldn't be able to use -maxdepth as can't predict the depth of the Group ID, hence not using -L (symlink)
        local _tmp_cp="$(find $(readlink -f "${_lib_dir%/}") -type f -name '*.jar' | tr '\n' ':')"
        export CLASSPATH=".:${_tmp_cp%:}"
    elif [ -s "${_lib_dir}" ]; then
        export CLASSPATH=".:${_lib_dir}"
    elif [ -s ./pom.xml ] && type mvn &>/dev/null; then
        mvn dependency:build-classpath -Dmdep.outputFile=/tmp/build-classpath.out || return $?
        if [ -s /tmp/build-classpath.out ]; then
            export CLASSPATH=".:$(cat /tmp/build-classpath.out)"
        fi
    fi
}

function _set_extra_classpath() {
    local _extra_lib="${1-"${_EXTRA_LIB}"}"
    local _classpath=""

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
    local _target="${4:-"${_TARGET}"}"
    local _compiled_dir="${_class_name}"

    if [ ! -d "$JAVA_HOME" ]; then
        echo "JAVA_HOME is not set. Use 'f_javaenvs <port>' or export JAVA_HOME=."
        return 1
    fi

    local _jar_filename="$(basename ${_jar_filepath})"
    if [ "$(readlink -f "${_jar_filepath}")" != "$(readlink -f ./${_jar_filename})" ]; then
        cp -p ${_jar_filepath} ./${_jar_filename} || return $?
    fi
    if [ ! -s "${_target%/}/${_jar_filename}.orig" ]; then
        cp -v -p ${_jar_filepath} ${_target%/}/${_jar_filename}.orig || return $?
    fi

    if [ ! -d "${_target%/}/${_compiled_dir}" ]; then
        cd "${_target%/}" || return 11
        _compiled_dir="`dirname "$(find . -name "${_class_name}.class" -print | tail -n1)"`"
        cd - || return 12
        if [ "${_compiled_dir}" = "." ] || [ -z "${_compiled_dir}" ]; then
            echo "${_class_name}.class shouldn't be located under ${_compiled_dir}."
            return 1
        fi
    fi

    local _class_file_path="${_compiled_dir%/}/*.class"
    [ -n "${_updating_specific_class}" ] && _class_file_path="${_compiled_dir%/}/${_updating_specific_class}[.$]*class"

    echo "Updating ./${_jar_filename} with ${_class_file_path} ..."
    local _updating_jar="$(readlink -f ./${_jar_filename})"
    local _updated_time="$(date | grep -oE ' [0-9][0-9]:[0-9][0-9]:[0-9]')"
    # -C doesn't work with wildcard (*.class)
    cd ${_target%/} || return 13
    $JAVA_HOME/bin/jar -uvf ${_updating_jar} ${_class_file_path} || return $?
    cd - || return 14
    echo "------------------------------------------------------------------------------------"
    echo "Checking if any non-updated class... (zip -d ${_jar_filepath} '/path/to/class')"
    $JAVA_HOME/bin/jar -tvf ${_updating_jar} | grep -w ${_class_name} | grep -v "${_updated_time}"

    cp -v -p -f ${_updating_jar} ${_target%/}/${_jar_filename}.patched || return $?
    echo "Moving ./${_jar_filename} to ${_jar_filepath} (may ask yes or no) ..."
    ls -l ${_updating_jar} ${_jar_filepath} || return $?
    mv -v ${_updating_jar} ${_jar_filepath} || return $?
    return 0
}


### Main ###############################
main() {
    local _spring_jar="${1}"
    local _class="${2}"
    local _lib_jar="${3}"
    local _extract_dir="${4}"
    local _target="${5:-"${_TARGET}"}"

    if [ -z "${_extract_dir}" ]; then
        _extract_dir="/tmp/patch_java_$$"
    fi
    if [ ! -d "${_extract_dir}" ]; then
        mkdir -p "${_extract_dir}" || return $?
    fi

    if [ -d "${_extract_dir%/}/BOOT-INF/lib" ]; then
        echo "Directory ${_extract_dir%/}/BOOT-INF/lib already exists."
    else
        jar -xf "${_spring_jar}" -C "${_extract_dir}" || return $?
    fi
    f_set_classpath "${_extract_dir%/}/BOOT-INF/lib" || return $?

    local _class_name="${_class%.*}"
    if [ -n "${_UPDATING_CLASSNAME}" ]; then
        _class_name="${_UPDATING_CLASSNAME}"
    fi
    if [ -z "${_lib_jar}" ]; then
        f_jargrep "${_class_name}.class" "${_extract_dir%/}/BOOT-INF/lib"
        [ -n "${_UPDATING_CLASSNAME}" ]  && f_jargrep "${_UPDATING_CLASSNAME}\.class" "${_extract_dir%/}/BOOT-INF/lib"
        echo "Please pick a jar file from above, and re-run the script:
    $0 '$1' '$2' '<jar path from above>' '$4' '$5'"
        return
    fi

    if [[ "${_NOT_COMPILING}" =~ [yY] ]]; then
        echo "Skipping compilation as requested."
    else
        local _cmd="javac"
        if [ -s "$JAVA_HOME/bin/javac" ]; then
            _cmd="$JAVA_HOME/bin/javac"
        fi
        JAVA_OPTS=-Xmx1024m ${_cmd} -d "${_target:-"."}" "${_class}" || return $?
    fi

    # If _JAR_FILEPATH is given, updating the jar
    if [ -n "${_lib_jar}" ] && [ -e "${_lib_jar}" ] && [ -n "${_CLASS_NAME}" ]; then
        f_update_jar "${_lib_jar}" "${_class_name}" "${_UPDATING_CLASSNAME}" || exit $?
        if [ ! -s "${_spring_jar}.orig" ]; then
            cp -v -p "${_spring_jar}" "${_spring_jar}.orig" || exit $?
        fi
        local _c_dir="$(dirname "$(dirname "${_lib_jar}")")"
        jar -u0vf ${_spring_jar} -C ${_c_dir%/} BOOT-INF/lib/$(basename "${_lib_jar}") || return $?
        echo "Completed. Please restart the process."
    else
        echo "No jar filepath or class name to update."
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi