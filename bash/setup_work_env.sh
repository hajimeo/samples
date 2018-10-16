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
    _backup ~/.bash_profile
    curl -f --retry 3 -o ~/.bash_profile -L "https://raw.githubusercontent.com/hajimeo/samples/master/runcom/bash_profile.sh" || return $?
    _backup ~/.bash_aliases
    curl -f --retry 3 -o ~/.bash_aliases -L "https://raw.githubusercontent.com/hajimeo/samples/master/runcom/bash_aliases.sh" || return $?

    # Command/scripts need for my bash_aliases.sh
    sudo -i pip install data_hacks  # it's OK if this fails
    if [ ! -d "~/IdeaProjects/samples/bash" ]; then
        mkdir -p ~/IdeaProjects/samples/bash || return $?
    fi
    _backup ~/IdeaProjects/samples/bash/log_search.sh
    curl -f --retry 3 -o ~/IdeaProjects/samples/bash/log_search.sh "https://raw.githubusercontent.com/hajimeo/samples/master/bash/log_search.sh" || return $?
}

function f_setup_rg() {
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
                curl -f --retry 3 -C - -o /tmp/ripgrep_${_ver}_amd64.deb -L "https://github.com/BurntSushi/ripgrep/releases/download/${_ver}/ripgrep_${_ver}_amd64.deb" || return $?
                sudo dpkg -i /tmp/ripgrep_${_ver}_amd64.deb || return $?
            fi
        else
            _log "WARN" "Please install 'rg' first. https://github.com/BurntSushi/ripgrep/releases"; sleep 3
            return 1
        fi
    fi

    _backup ~/.rgrc
    curl -f --retry 3 -o ~/.rgrc -L "https://raw.githubusercontent.com/hajimeo/samples/master/runcom/rgrc" || return $?
    if ! grep -q '^export RIPGREP_CONFIG_PATH=' ~/.bash_profile; then
        echo -e '\nexport RIPGREP_CONFIG_PATH=$HOME/.rgrc' >> ~/.bash_profile || return $?
    fi
}

function f_setup_jupyter() {
    if ! which python3 &>/dev/null && ! _install python3 -y; then
        _log "ERROR" "no python3 installed or not in PATH"
        return 1
    fi

    if ! which pip3 &>/dev/null && ! _install python3-pip -y; then
        _log "ERROR" "no pip installed or not in PATH (sudo easy_install pip)"
        return 1
    fi

    ### Pip(3) ############################################################
    # TODO: should use vertualenv?
    #virtualenv myenv && source myenv/bin/activate
    #sudo -i pip3 install -U pip &>/dev/null
    # outdated list
    sudo -i pip3 list -o | tee /tmp/pip.log
    #sudo -i pip3 list -o --format=freeze | cut -d'=' -f1 | xargs sudo -i pip3 install -U

    # TODO: is jupyter deprecated?
    sudo -i pip3 install jupyter --log /tmp/pip.log &>/dev/null || return $?
    sudo -i pip3 install jupyterlab --log /tmp/pip.log &>/dev/null || return $?
    # TODO: as of today no jupyter_contrib_labextensions
    sudo -i pip3 install jupyter_contrib_nbextensions pandas sqlalchemy ipython-sql --log /tmp/pip.log &>/dev/null
    sudo -i pip3 install bash_kernel --log /tmp/pip.log &>/dev/null && sudo -i python3 -m bash_kernel.install
    # Enable BeakerX. NOTE: this works with only python3
    #sudo -i pip3 install beakerx && beakerx-install
    ### Pip(3) end ########################################################

    # Enable jupyter extensions (spell checker)
    sudo -i jupyter contrib nbextension instal && sudo -i jupyter nbextension enable spellchecker/main
    # TODO: sudo -i jupyter labextension install @ijmbarr/jupyterlab_spellchecker
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
        f_setup_misc
        f_setup_rg
        f_setup_jupyter
    fi
fi