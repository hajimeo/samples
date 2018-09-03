#!/usr/bin/env bash
# Collection of functions to setup a desktop / work environment

function f_setup_rg() {
    if ! which rg &>/dev/null; then
        echo "https://github.com/BurntSushi/ripgrep/releases
    brew install ripgrep
or
    curl -LO https://github.com/BurntSushi/ripgrep/releases/download/0.9.0/ripgrep_0.9.0_amd64.deb
    sudo dpkg -i ripgrep_0.9.0_amd64.deb"
        return 1
    fi

    if [ ! -s ~/.rgrc ]; then
        curl -o ~/.rgrc -L "https://raw.githubusercontent.com/hajimeo/samples/master/runcom/rgrc"
    fi
    if ! grep -q '^export RIPGREP_CONFIG_PATH=' ~/.bash_profile; then
        echo -e '\nexport RIPGREP_CONFIG_PATH=$HOME/.rgrc' >> ~/.bash_profile
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

    sudo pip install --upgrade pip

    sudo pip install jupyter || return $?
    sudo pip install jupyter_contrib_nbextensions pandas sqlalchemy ipython-sql

    # Enable spell checker
    sudo pip install bash_kernel && python -m bash_kernel.install
    sudo jupyter contrib nbextension install # --user
    sudo jupyter nbextension enable spellchecker/main
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
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" | tee -a ${g_LOG_FILE_PATH} 1>&2
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" 1>&2
    fi
}


# TODO: setup (not install) below
#s3cmd


### Main ###############################################################################################################
if [ "$0" = "$BASH_SOURCE" ]; then
    if [ "$1" =~ ^f_ ]; then
        eval "$@"
    else
        f_setup_rg
        f_setup_jupyter
    fi
fi