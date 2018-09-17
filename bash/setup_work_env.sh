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
    if ! which python &>/dev/null && ! _install python -y; then
        _log "ERROR" "no python installed or not in PATH"
        return 1
    fi

    if ! which pip &>/dev/null && ! _install python-pip -y; then
        _log "ERROR" "no python installed or not in PATH"
        return 1
    fi

    # TODO: should use vertualenv?
    #virtualenv myenv && source myenv/bin/activate
    sudo -i pip install --upgrade pip

    sudo -i pip install jupyter || return $?
    sudo -i pip install jupyter_contrib_nbextensions pandas sqlalchemy ipython-sql

    # Enable spell checker
    sudo -i pip install bash_kernel && sudo -i python -m bash_kernel.install
    if [ $? -eq 0 ]; then
        sudo -i jupyter contrib nbextension install # --user
        sudo -i jupyter nbextension enable spellchecker/main
    fi
}

function f_jn(){
    local _backup_dir="${1:-$HOME/backup/jupyter-notebook}"
    local _sleep="${2:-300}"
    local _port="${3:-8888}"

    if [ -d "${_backup_dir}" ]; then
        cp -f "${_backup_dir%/}/Aggregation.ipynb" ./
        while true; do
            sleep ${_sleep}
            local _wc="`ls -1 ./*.ipynb 2>/dev/null | wc -l`"
            if [  "${_wc}" -gt 0 ]; then
                rsync -a --exclude="Untitled.ipynb" ./*.ipynb "${_backup_dir%/}/" || break
            else
                break
            fi
            if ! nc -z localhost ${_port} &>/dev/null; then
                mv -f ./Aggregation.ipynb /tmp/
                break
            fi
        done &
    fi

    jupyter notebook --ip='*' &
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