#!/usr/bin/env bash
#
# Collection of functions to setup a desktop / work environment
#
# NOTE: This script always tries to overwrite (update)
#       Using 'sudo' for pip3 and others
#
# curl -O "https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_work_env.sh"
#

_DOWNLOAD_FROM_BASE="https://raw.githubusercontent.com/hajimeo/samples/master"
_SOURCE_REPO_BASE="$HOME/IdeaProjects/samples"

function f_setup_misc() {
    _symlink_or_download "runcom/bash_profile.sh" "$HOME/.bash_profile" || return $?
    _symlink_or_download "runcom/bash_aliases.sh" "$HOME/.bash_aliases" || return $?
    _symlink_or_download "runcom/vimrc" "$HOME/.vimrc" || return $?
    if [ ! -d "$HOME/.ssh" ]; then
        mkdir -p $HOME/.ssh || return $?
    fi
    _symlink_or_download "runcom/ssh_config" "$HOME/.ssh/config" || return $?

    if [ ! -d "$HOME/IdeaProjects/samples/bash" ]; then
        mkdir -p $HOME/IdeaProjects/samples/bash || return $?
    fi
    # Need for logS alias
    _symlink_or_download "bash/log_search.sh" "/usr/local/bin/log_search" || return $?
    chmod u+x $HOME/IdeaProjects/samples/bash/log_search.sh

    if [ ! -d "$HOME/IdeaProjects/samples/python" ]; then
        mkdir -p $HOME/IdeaProjects/samples/python || return $?
    fi
    _symlink_or_download "python/line_parser.py" "/usr/local/bin/line_parser.py" || return $?
    chmod a+x $HOME/IdeaProjects/samples/python/line_parser.py

    #_symlink_or_download "misc/dateregex_`uname`" "/usr/local/bin/dateregex" "Y"
    #chmod a+x /usr/local/bin/dateregex

    if grep -qw docker /etc/group; then
        sudo usermod -a -G docker $USER && _log "NOTE" "Please re-login as user group has been changed."
    fi

    if which git &>/dev/null && ! git config credential.helper | grep -qw cache; then
        git config --global credential.helper "cache --timeout=600"
    fi

    _install jq
}

function f_setup_rg() {
    # as of today, rg is not in Ubuntu repository so not using _install
    local _url="https://github.com/BurntSushi/ripgrep/releases/"
    if ! which rg &>/dev/null; then
        if ! _install ripgrep; then
            if [ "`uname`" = "Darwin" ]; then
                _log "WARN" "Please install 'rg' first. ${_url}"; sleep 3
                return 1
            elif [ "`uname`" = "Linux" ]; then
                local _ver="$(curl -sI ${_url%/}/latest | _sed -nr 's/^Location:.+\/releases\/tag\/(.+)$/\1/p' | tr -d '[:space:]')"
                _log "INFO" "Installing rg version: ${_ver} ..."; sleep 3
                _download "${_url%/}/download/${_ver}/ripgrep_${_ver}_amd64.deb" "/tmp/ripgrep_${_ver}_amd64.deb" "Y" "Y" || return $?
                sudo dpkg -i /tmp/ripgrep_${_ver}_amd64.deb || return $?
            else
                _log "WARN" "Please install 'rg' first. ${_url}"; sleep 3
                return 1
            fi
        fi
    fi

    _symlink_or_download "runcom/rgrc" "$HOME/.rgrc" || return $?
    if ! grep -qR '^export RIPGREP_CONFIG_PATH=' $HOME/.bash_profile; then
        echo -e '\nexport RIPGREP_CONFIG_PATH=$HOME/.rgrc' >> $HOME/.bash_profile || return $?
    fi
}

function f_setup_screen() {
    if ! which screen &>/dev/null && ! _install screen; then
        _log "ERROR" "no screen installed or not in PATH"
        return 1
    fi

    [ -d $HOME/.byobu ] || mkdir $HOME/.byobu
    _backup $HOME/.byobu/.screenrc
    _symlink_or_download "runcom/screenrc" "$HOME/.screenrc" || return $?
    [ -f $HOME/.byobu/.screenrc ] && rm -f $HOME/.byobu/.screenrc
    ln -s $HOME/.screenrc $HOME/.byobu/.screenrc
}

function f_setup_golang() {
    local _ver="${1:-"1.13"}"
    # TODO: currently only for Ubuntu and Mac, and hard-coding go version
    if ! which go &>/dev/null || ! go version | grep -q "go${_ver}"; then
        if [ "`uname`" = "Darwin" ]; then
            if which brew &>/dev/null; then
                brew install go || return $?  # as of 1.13.8, --with-cgo does not work.
            else
                _log "WARN" "Please install 'go'. https://golang.org/doc/install"; sleep 3
                return 1
            fi
        else
            sudo add-apt-repository ppa:gophers/archive -y
            sudo apt-get update
            sudo apt-get install golang-${_ver}-go -y || return $?

            local _go="`which go`"
            if [ -z "${_go}" ] && [ -s /usr/lib/go-${_ver}/bin/go ]; then
                sudo ln -s /usr/lib/go-${_ver}/bin/go /usr/bin/go
            elif [ -L "${_go}" ] && [ -s /usr/lib/go-${_ver}/bin/go ]; then
                sudo rm "${_go}"
                sudo ln -s /usr/lib/go-${_ver}/bin/go "${_go}"
            fi
        fi
    fi

    if [ ! -d "$HOME/go" ]; then
        _log "WARN" "\$HOME/go does not exist. Creating ..."
        mkdir "$HOME/go" || return 1
    fi
    if [ -z "$GOPATH" ]; then
        _log "WARN" "May need to add 'export GOPATH=$HOME/go' in profile"
        export GOPATH=$HOME/go
    fi
    # Installing something. Ex: go get -v -u github.com/hajimeo/docker-webui
    _log "INFO" "Installing/udating delve/dlv ..."
    # If Mac: brew install go-delve/delve/delve
    go get -u github.com/go-delve/delve/cmd/dlv || return $?
    [ ! -d /var/tmp/share ] && sudo mkdir -m 777 -p /var/tmp/share || return $?
    sudo cp -f $GOPATH/bin/dlv /var/tmp/share/dlv || return $?
    sudo chmod a+x /var/tmp/share/dlv
}

function f_setup_python() {
    local _python="${1:-"`which python3`"}"
    if [ ! -s "${_python}" ] && ! _install python3; then
        _log "ERROR" "no python3 installed or not in PATH"
        return 1
    fi
    if ! which pip &>/dev/null; then
        _log "WARN" "no pip installed or not in PATH (sudo easy_install pip). Trying to install..."
        # NOTE: Mac's pip3 is installed by 'brew install python3'
        # sudo python3 -m pip uninstall pip
        # sudo apt remove python3-pip
        curl -s -f "https://bootstrap.pypa.io/get-pip.py" -o /tmp/get-pip.py || return $?
        # @see https://github.com/pypa/get-pip/issues/43
        _install python3-distutils
        "${_python}" /tmp/get-pip.py || return $?
    fi

    # TODO: this works only with python2, hence not pip3 and not in virtualenv, and eventually will stop working
    deactivate &>/dev/null
    if which python2 &>/dev/null; then
        sudo -i python2 -m pip install -U data_hacks
    else
        sudo -i pip install -U data_hacks
    fi  # it's OK if this fails

    ${_python} -m pip install -U virtualenv || return $?

    # When python version is changed, need to run virtualenv command again
    virtualenv -p "${_python}" $HOME/.pyvenv || return $?
    source $HOME/.pyvenv/bin/activate || return $?

    ### pip3 (not pip) from here ############################################################
    #${_python} -m pip install -U pip &>/dev/null
    # outdated list
    ${_python} -m pip list -o | tee /tmp/pip.log
    #${_python} -m pip list -o --format=freeze | cut -d'=' -f1 | xargs ${_python} -m pip install -U

    # My favourite/essential packages
    ${_python} -m pip install -U lxml xmltodict pyyaml
    ${_python} -m pip install -U pyjq    # TODO: as of this typing, this fails against python 3.8 (3.7 looks OK)

    # Jupyter related
    # NOTE: Autocomplete doesn't work if diff version is used. @see https://github.com/ipython/ipython/issues/11530
    #${_python} -m pip install ipython==7.1.1
    ${_python} -m pip install -U jupyter jupyterlab --log /tmp/pip.log &>/dev/null || return $?
    # Need "-H"? eg: sudo -H ${_python} -m pip uninstall -y jupyterlab && sudo -H ${_python} -m pip install jupyterlab
    # Need to add /usr/local/Cellar/python/3.7.1/Frameworks/Python.framework/Versions/3.7/bin in PATH?

    # NOTE: Initially I thought pandasql looked good but it's actually using sqlite. Pixiedust works only with jupyter-notebook
    ${_python} -m pip install -U pandas pandas_profiling pixiedust sqlalchemy ipython-sql pandas-gbq --log /tmp/pip.log &>/dev/null
    # NOTE: In case I might use jupyter notebook, still installing this
    ${_python} -m pip install -U bash_kernel --log /tmp/pip.log &>/dev/null && python3 -m bash_kernel.install
    # For Spark etc., BeakerX http://beakerx.com/ NOTE: this works with only python3
    #${_python} -m pip install beakerx && beakerx-install

    # TODO: as of today no jupyter_contrib_labextensions (lab)
    # Enable jupyter notebook extensions (spell checker)
    ${_python} -m pip install -U jupyter_contrib_nbextensions
    jupyter contrib nbextension install && jupyter nbextension enable spellchecker/main
    jupyter labextension install @ijmbarr/jupyterlab_spellchecker

    # Enable Holloviews http://holoviews.org/user_guide/Installing_and_Configuring.html
    # Ref: http://holoviews.org/reference/index.html
    #${_python} -m pip install 'holoviews[recommended]'
    #jupyter labextension install @pyviz/jupyterlab_pyviz
    # TODO: Above causes ValueError: Please install nodejs 5+ and npm before continuing installation.

    # Not so useful?
    ${_python} -m pip install jupyterlab_templates
    #jupyter labextension install jupyterlab_templates && jupyter serverextension enable --py jupyterlab_templates

    #_install libsasl2-dev
    #${_python} -m pip install sasl thrift thrift-sasl PyHive
    # This is for using Java 1.8 (to avoid "unsupported major.minor version 52.0")
    ${_python} -m pip install JPype1==0.6.3 JayDeBeApi
    #${_python} -m pip install google-cloud-bigquery

    f_jupyter_util
}

function f_jupyter_util() {
    # If we use this location, .bash_profile automatically adds PYTHONPATH
    if [ ! -d "$HOME/IdeaProjects/samples/python" ]; then
        mkdir -p $HOME/IdeaProjects/samples/python || return $?
    fi
    if [ ! -d "$HOME/IdeaProjects/samples/java/hadoop" ]; then
        mkdir -p "$HOME/IdeaProjects/samples/java/hadoop" || return $?
    fi
    _download "https://raw.githubusercontent.com/hajimeo/samples/master/python/jn_utils.py" "$HOME/IdeaProjects/samples/python/jn_utils.py" "Y" "Y" || return $?
    #_download "https://public-xxxxxxx.s3.amazonaws.com/hive-jdbc-client-1.2.1.jar" "$HOME/IdeaProjects/samples/java/hadoop/hive-jdbc-client-1.2.1.jar" "Y" "Y" || return $?
    _download "https://github.com/hajimeo/samples/raw/master/java/hadoop/hadoop-core-1.0.3.jar" "$HOME/IdeaProjects/samples/java/hadoop/hadoop-core-1.0.3.jar" "Y" "Y" || return $?
    _download "https://github.com/hajimeo/samples/raw/master/java/hadoop/hive-jdbc-1.0.0-standalone.jar" "$HOME/IdeaProjects/samples/java/hadoop/hive-jdbc-1.0.0-standalone.jar" "Y" "Y" || return $?

    if [ ! -d "$HOME/.ipython/profile_default/startup" ]; then
        mkdir -p "$HOME/.ipython/profile_default/startup" || return $?
    fi
    # How-to: pp.ProfileReport(df)
    echo "import pandas as pd
import pandas_profiling as pp
import jn_utils as ju
get_ipython().run_line_magic('matplotlib', 'inline')" > "$HOME/.ipython/profile_default/startup/import_ju.py"
}

function f_setup_java() {
    local _v="${1-"8"}" # Using 8 as JayDeBeApi uses specific version and which is for java 8
    local _ver="${_v}"  # Java version can be "9" or "1.8"
    [[ "${_v}" =~ ^[678]$ ]] && _ver="1.${_v}"

    if [ "`uname`" = "Darwin" ]; then
        brew tap adoptopenjdk/openjdk
        if [ -z "${_v}" ]; then
            brew cask install java
        else
            brew cask install adoptopenjdk${_v}
        fi
        #/usr/libexec/java_home -v ${_v}
    else
        if [ -z "${_v}" ]; then
            _install default-jdk
        else
            # If Linux, downloading .tar.gz file and extract, so that it can be re-used in the container
            local _java_exact_ver="$(basename $(curl -s https://github.com/AdoptOpenJDK/openjdk${_v}-binaries/releases/latest | _sed -nr 's/.+"(https:[^"]+)".+/\1/p'))"
            # NOTE: hoping the naming rule is same for different versions (eg: jdk8u222-b10_openj9-0.15.1)
            if [[ "${_java_exact_ver}" =~ jdk([^-]+)-([^_]+) ]]; then
                [ ! -d "/var/tmp/share/java" ] && mkdir -p -m 777 /var/tmp/share/java
                local _jdk_ver="${BASH_REMATCH[1]}"     # 8u222
                local _jdk_minor="${BASH_REMATCH[2]}"   # b10
                _download "https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk${_jdk_ver}-${_jdk_minor}/OpenJDK${_v}U-jdk_x64_linux_hotspot_${_jdk_ver}${_jdk_minor}.tar.gz" "/var/tmp/share/java/OpenJDK${_v}U-jdk_x64_linux_hotspot_${_jdk_ver}${_jdk_minor}.tar.gz" "Y" "Y" || return $?
                if [ -s "/var/tmp/share/java/OpenJDK${_v}U-jdk_x64_linux_hotspot_${_jdk_ver}${_jdk_minor}.tar.gz" ]; then
                    tar -xf "/var/tmp/share/java/OpenJDK${_v}U-jdk_x64_linux_hotspot_${_jdk_ver}${_jdk_minor}.tar.gz" -C /var/tmp/share/java/ || return $?
                    _log "INFO" "OpenJDK${_v} is extracted under '/var/tmp/share/java/jdk${_jdk_ver}-${_jdk_minor}'"
                fi
            else
                _install openjdk-${_v}-jdk
            fi
        fi
    fi

    if ! java -version 2>&1 | grep -w "build ${_ver}" -m 1; then
        _log "WARN" "Current Java version is not ${_ver}."
    fi
}

function _install() {
    if which apt-get &>/dev/null; then
        sudo apt-get install -y "$@" || return $?
    elif which brew &>/dev/null; then
        brew install "$@" || return $?
    else
        _log "ERROR" "`uname` is not supported yet to install a package"
        return 1
    fi
}

function _sed() {
    local _cmd="sed"; which gsed &>/dev/null && _cmd="gsed"
    ${_cmd} "$@"
}

function _symlink_or_download() {
    local _source_filename="$1"
    local _destination="$2"
    local _no_backup="$3"
    local _if_not_exists="$4"
    if [ ! -f ${_destination} ] && [ -s ${_SOURCE_REPO_BASE%/}/${_source_filename} ]; then
        if which realpath &>/dev/null; then
            ln -s "$(realpath "${_SOURCE_REPO_BASE%/}/${_source_filename}")" "$(realpath "${_destination}")" || return $?
        else
            ln -s "${_SOURCE_REPO_BASE%/}/${_source_filename}" "${_destination}" || return $?
        fi
    elif [ ! -L ${_destination} ]; then
        _download "${_DOWNLOAD_FROM_BASE%/}/${_source_filename}" "${_destination}" "${_no_backup}" "${_if_not_exists}" || return $?
    fi
}

function _download() {
    local _url="$1"
    local _save_as="$2"
    local _no_backup="$3"
    local _if_not_exists="$4"   # default is always overwriting

    if [[ "${_if_not_exists}" =~ ^(y|Y) ]] && [ -s "${_save_as}" ]; then
        _log "INFO" "Not downloading as ${_save_as} exists."
        return
    fi
    local _cmd="curl -s -f --retry 3 --compressed -L -k '${_url}'"
    # NOTE: if the file already exists, "-C -" may do something unexpected for text files
    if [ -s "${_save_as}" ] && ! file "${_save_as}" | grep -qwi "text"; then
        _cmd="${_cmd} -C -"
    fi
    if [ -z "${_save_as}" ]; then
        _cmd="${_cmd} -O"
    else
        [[ "${_no_backup}" =~ ^(y|Y) ]] || _backup "${_save_as}"
        _cmd="${_cmd} -o ${_save_as}"
    fi

    _log "INFO" "Downloading ${_url}..."
    eval ${_cmd}
}

function _log() {
    # At this moment, outputting to STDERR
    if [ -n "${_LOG_FILE_PATH}" ]; then
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $@" | tee -a ${_LOG_FILE_PATH} 1>&2
    else
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $@" 1>&2
    fi
}

function _backup() {
    [ -s "$1" ] && cp -p "$1" /tmp/$(basename "$1")_$(date +'%Y%m%d%H%M%S')
}


# TODO: setup (not install) below
#s3cmd


### Main ###############################################################################################################
if [ "$0" = "$BASH_SOURCE" ]; then
    if [[ "$1" =~ ^f_ ]]; then
        eval "$@"
    else
        sudo echo "Starting setup ..."
        _log "INFO" "Running f_setup_misc ..."
        f_setup_misc; echo "Exit code $?"
        _log "INFO" "Running f_setup_screen ..."
        f_setup_screen; echo "Exit code $?"
        _log "INFO" "Running f_setup_rg ..."
        f_setup_rg; echo "Exit code $?"
        _log "INFO" "Running f_setup_jupyter ..."
        f_setup_python; echo "Exit code $?"
        _log "INFO" "Running f_setup_golang ..."
        f_setup_golang; echo "Exit code $?"
        _log "INFO" "Running f_setup_java ..."
        f_setup_java; echo "Exit code $?"
        echo "Completed."
    fi
fi