#!/usr/bin/env bash
#
# Collection of functions to setup a desktop / work environment
# Expecting this script works with non-root user (but sudo required)
#
# NOTE: This script always tries to overwrite (update)
#
# curl -O "https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_work_env.sh"
#

function f_setup_misc() {
    # Command/scripts need for my bash_aliases.sh
    sudo -i pip install data_hacks  # it's OK if this fails NOTE: this works only with python2

    _download "https://raw.githubusercontent.com/hajimeo/samples/master/runcom/bash_profile.sh" $HOME/.bash_profile || return $?
    _download "https://raw.githubusercontent.com/hajimeo/samples/master/runcom/bash_aliases.sh" $HOME/.bash_aliases || return $?
    _download "https://raw.githubusercontent.com/hajimeo/samples/master/runcom/vimrc" $HOME/.vimrc || return $?

    if [ ! -d "$HOME/IdeaProjects/samples/bash" ]; then
        mkdir -p $HOME/IdeaProjects/samples/bash || return $?
    fi
    _download "https://raw.githubusercontent.com/hajimeo/samples/master/bash/log_search.sh" $HOME/IdeaProjects/samples/bash/log_search.sh || return $?
    chmod u+x $HOME/IdeaProjects/samples/bash/log_search.sh
    _log "TODO" "May also want to get genfile_wrapper.sh (just reminder)"

    if [ ! -d "$HOME/IdeaProjects/samples/python" ]; then
        mkdir -p $HOME/IdeaProjects/samples/python || return $?
    fi
    _download "https://raw.githubusercontent.com/hajimeo/samples/master/python/line_parser.py" $HOME/IdeaProjects/samples/python/line_parser.py || return $?
    chmod a+x $HOME/IdeaProjects/samples/python/line_parser.py
    [ -L /usr/local/bin/line_parser.py ] && sudo rm -f /usr/local/bin/line_parser.py
    sudo ln -s $HOME/IdeaProjects/samples/python/line_parser.py /usr/local/bin/line_parser.py

    #_download "https://github.com/hajimeo/samples/raw/master/misc/dateregex_Linux" /usr/local/bin/dateregex "Y" || return $?
    #chmod a+x /usr/local/bin/dateregex
}

function f_setup_rg() {
    # as of today, rg is not in Ubuntu repository so not using _install
    if ! which rg &>/dev/null; then
        if [ "`uname`" = "Darwin" ]; then
            if which brew &>/dev/null; then
                brew install ripgrep || return
            else
                _log "WARN" "Please install 'rg' first. https://github.com/BurntSushi/ripgrep/releases"; sleep 3
                return 1
            fi
        elif [ "`uname`" = "Linux" ]; then
            if which apt-get &>/dev/null; then  # NOTE: Mac has 'apt' command
                local _ver="0.10.0"
                _log "INFO" "Installing rg version: ${_ver} ..."; sleep 3
                _download "https://github.com/BurntSushi/ripgrep/releases/download/${_ver}/ripgrep_${_ver}_amd64.deb" "/tmp/ripgrep_${_ver}_amd64.deb" "Y" "Y" || return $?
                sudo dpkg -i /tmp/ripgrep_${_ver}_amd64.deb || return $?
            fi
        else
            _log "WARN" "Please install 'rg' first. https://github.com/BurntSushi/ripgrep/releases"; sleep 3
            return 1
        fi
    fi

    _download "https://raw.githubusercontent.com/hajimeo/samples/master/runcom/rgrc" $HOME/.rgrc || return $?
    if ! grep -q '^export RIPGREP_CONFIG_PATH=' $HOME/.bash_profile; then
        echo -e '\nexport RIPGREP_CONFIG_PATH=$HOME/.rgrc' >> $HOME/.bash_profile || return $?
    fi
}

function f_setup_screen() {
    if ! which screen &>/dev/null && ! _install screen -y; then
        _log "ERROR" "no screen installed or not in PATH"
        return 1
    fi

    [ -d $HOME/.byobu ] || mkdir $HOME/.byobu
    _backup $HOME/.byobu/.screenrc
    _download "https://raw.githubusercontent.com/hajimeo/samples/master/runcom/screenrc" $HOME/.screenrc || return $?
    [ -f $HOME/.byobu/.screenrc ] && rm -f $HOME/.byobu/.screenrc
    ln -s $HOME/.screenrc $HOME/.byobu/.screenrc
}

function f_setup_golang() {
    # TODO: currently only for Ubuntu and hard-coding go version
    if ! which go &>/dev/null; then
        add-apt-repository ppa:gophers/archive -y
        apt-get update
        apt-get install golang-1.10-go -y || return $?
        ln -s /usr/lib/go-1.10/bin/go /usr/bin/go
    fi

    if [ ! -d "$GOPATH" ]; then
        _log "INFO" "May need to add 'export GOPATH=$HOME/go' in profile"
        export GOPATH=$HOME/go
    fi
    # Ex: go get -v -u github.com/hajimeo/docker-webui
}

function f_setup_jupyter() {
    if ! which python3 &>/dev/null && ! _install python3 -y; then
        _log "ERROR" "no python3 installed or not in PATH"
        return 1
    fi

    if ! which pip3 &>/dev/null; then
        _log "WARN" "no pip installed or not in PATH (sudo easy_install pip). Trying to install..."
        # NOTE: Mac's pip3 is installed by 'brew install python3'
        # sudo python3 -m pip uninstall pip
        # sudo apt remove python3-pip
        curl -s -f "https://bootstrap.pypa.io/get-pip.py" -o /tmp/get-pip.py || return $?
        sudo python3 /tmp/get-pip.py || return $?
    fi

    ### Pip(3) ############################################################
    # TODO: should use vertualenv?
    #virtualenv myenv && source myenv/bin/activate
    #sudo -i pip3 install -U pip &>/dev/null
    # outdated list
    sudo -i pip3 list -o | tee /tmp/pip.log
    #sudo -i pip3 list -o --format=freeze | cut -d'=' -f1 | xargs sudo -i pip3 install -U

    sudo -i pip3 install jupyter --log /tmp/pip.log &>/dev/null || return $?
    sudo -i pip3 install jupyterlab --log /tmp/pip.log &>/dev/null || return $?
    # TODO: as of today no jupyter_contrib_labextensions (lab)
    # NOTE: Initially I thought pandasql looked good but it's actually using sqlite
    sudo -i pip3 install jupyter_contrib_nbextensions pandas sqlalchemy ipython-sql --log /tmp/pip.log &>/dev/null
    sudo -i pip3 install bash_kernel --log /tmp/pip.log &>/dev/null && sudo -i python3 -m bash_kernel.install
    # Enable BeakerX. NOTE: this works with only python3
    #sudo -i pip3 install beakerx && beakerx-install
    ### Pip(3) end ########################################################

    # Enable jupyter notebook extensions (spell checker)
    sudo -i jupyter contrib nbextension install && sudo -i jupyter nbextension enable spellchecker/main
    # TODO: sudo -i jupyter labextension install @ijmbarr/jupyterlab_spellchecker

    # Enable Holloviews http://holoviews.org/user_guide/Installing_and_Configuring.html
    # Ref: http://holoviews.org/reference/index.html
    #sudo -i pip3 install 'holoviews[recommended]'
    #sudo -i jupyter labextension install @pyviz/jupyterlab_pyviz
    # TODO: Above causes ValueError: Please install nodejs 5+ and npm before continuing installation.

    #_install libsasl2-dev -y
    #sudo -i pip3 install sasl thrift thrift-sasl PyHive
    #sudo -i pip3 install pyhive[hive]
    sudo -i pip3 install JayDeBeApi

    f_jupyter_util
}

function f_jupyter_util() {
    # If we use this location, .bash_profile automatically adds PYTHONPATH
    if [ ! -d "$HOME/IdeaProjects/samples/python" ]; then
        mkdir -p $HOME/IdeaProjects/samples/python || return $?
    fi
    # always get the latest and wouldn't need a backup
    _download "https://raw.githubusercontent.com/hajimeo/samples/master/python/jn_utils.py" "$HOME/IdeaProjects/samples/python/jn_utils.py" || return $?

    if [ ! -d "$HOME/IdeaProjects/samples/java/hadoop" ]; then
        mkdir -p "$HOME/IdeaProjects/samples/java/hadoop" || return $?
    fi
    _download "https://github.com/hajimeo/samples/raw/master/java/hadoop/hadoop-core-1.0.3.jar" "$HOME/IdeaProjects/samples/java/hadoop/hadoop-core-1.0.3.jar" "Y" "Y" || return $?
    _download "https://github.com/hajimeo/samples/raw/master/java/hadoop/hive-jdbc-1.0.0-standalone.jar" "$HOME/IdeaProjects/samples/java/hadoop/hadoop-core-1.0.3.jar" "Y" "Y" || return $?

    if [ ! -d "$HOME/.ipython/profile_default/startup" ]; then
        mkdir -p "$HOME/.ipython/profile_default/startup" || return $?
    fi
    echo "import pandas as pd
import jn_utils as ju
get_ipython().run_line_magic('matplotlib', 'inline')" > "$HOME/.ipython/profile_default/startup/import_ju.py"
}

function _install() {
    if which apt-get &>/dev/null; then
        sudo apt-get install "$@" || return $?
    elif which brew &>/dev/null; then
        brew install "$@" || return $?
    else
        _log "ERROR" "`uname` is not supported yet to install a package"
        return 1
    fi
}

function _download() {
    local _url="$1"
    local _save_as="$2"
    local _no_backup="$3"
    local _if_not_exists="$4"

    if [[ "${_if_not_exists}" =~ ^(y|Y) ]] && [ -s "${_save_as}" ]; then
        _log "INFO" "Not downloading as ${_save_as} exists."
        return
    fi

    local _cmd="curl -s -f --retry 3 -L -k '${_url}'"
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
        _log "INFO" "Running f_setup_misc ..."
        f_setup_misc
        _log "INFO" "Running f_setup_screen ..."
        f_setup_screen
        _log "INFO" "Running f_setup_rg ..."
        f_setup_rg
        _log "INFO" "Running f_setup_jupyter ..."
        f_setup_jupyter
    fi
fi