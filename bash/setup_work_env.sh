#!/usr/bin/env bash
#
# Collection of functions to setup a desktop / work environment which *should* work on Ubuntu and Mac
#
# NOTE: This script always tries to overwrite (update)
#       Using 'sudo' for pip3 and others
#
# curl -O "https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_work_env.sh"
#

_DOWNLOAD_FROM_BASE="https://raw.githubusercontent.com/hajimeo/samples/master/"
_SOURCE_REPO_BASE="${HOME%/}/IdeaProjects/samples"
type _import &>/dev/null || _import() {
    [ ! -s /tmp/${1}_$$ ] && curl -sf --compressed "${_DOWNLOAD_FROM_BASE%/}/bash/$1" -o /tmp/${1}_$$
    . /tmp/${1}_$$
}
_import "utils.sh"

function f_prepare() {
    # commands which may require sudo, but minimum (not including screen)
    if ! which brew &>/dev/null; then
        if ! which add-apt-repository &>/dev/null; then
            _install software-properties-common
        fi
        add-apt-repository ppa:deadsnakes/ppa -y
        apt-get update
    fi
    _install sudo curl screen jq python3.7 #netcat
    # Below is for pyenv and not using at this moment
    #_install make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev python-openssl git
    f_install_rg

    if ! sudo which pip &>/dev/null || ! pip -V; then
        _log "WARN" "no pip installed or not in PATH (sudo easy_install pip). Trying to install..."
        # NOTE: Mac's pip3 is installed by 'brew install python3'
        #sudo python3 -m pip uninstall pip
        #sudo apt remove python3-pip
        # For python 2.7 https://bootstrap.pypa.io/pip/2.7/get-pip.py
        curl -s -f "https://bootstrap.pypa.io/get-pip.py" -o /tmp/get-pip.py || return $?
        # @see https://github.com/pypa/get-pip/issues/43
        _install python3-distutils
        sudo python3.7 /tmp/get-pip.py || return $?
    fi
    # python 3.7 does not have virtualenv?
    #python3.7 -m pip install -U virtualenv venv

    # For bar_chart.py  TODO: this works only with python2, hence no pip3 (and not in virtualenv), and eventually will stop working
    if which python2 &>/dev/null; then
        sudo -i python2 -m pip install -U data_hacks
    else
        sudo -i pip install -U data_hacks
    fi # it's OK if this fails

    if grep -qw docker /etc/group; then
        sudo usermod -a -G docker $USER && _log "NOTE" "Please re-login as user group has been changed."
    fi
}

function f_setup_misc() {
    _symlink_or_download "runcom/bash_profile.sh" "$HOME/.bash_profile" || return $?
    _symlink_or_download "runcom/bash_aliases.sh" "$HOME/.bash_aliases" || return $?
    _symlink_or_download "runcom/vimrc" "$HOME/.vimrc" || return $?
    if [ ! -d "$HOME/.ssh" ]; then
        mkdir -p $HOME/.ssh || return $?
    fi
    _symlink_or_download "runcom/ssh_config" "$HOME/.ssh/config" || return $?

    if [ ! -d "${_SOURCE_REPO_BASE%/}/bash" ]; then
        mkdir -p ${_SOURCE_REPO_BASE%/}/bash || return $?
    fi
    # Need for logS alias
    _symlink_or_download "bash/log_search.sh" "/usr/local/bin/log_search" || return $?
    chmod u+x ${_SOURCE_REPO_BASE%/}/bash/log_search.sh

    if [ ! -d "${_SOURCE_REPO_BASE%/}/python" ]; then
        mkdir -p ${_SOURCE_REPO_BASE%/}/python || return $?
    fi
    _symlink_or_download "python/line_parser.py" "/usr/local/bin/line_parser.py" || return $?
    chmod a+x ${_SOURCE_REPO_BASE%/}/python/line_parser.py

    #_symlink_or_download "misc/dateregex_`uname`" "/usr/local/bin/dateregex" "Y"
    #chmod a+x /usr/local/bin/dateregex

    if which git &>/dev/null && ! git config credential.helper | grep -qw cache; then
        git config --global credential.helper "cache --timeout=600"
    fi
}

function f_install_rg() {
    # as of today, rg is not in Ubuntu repository so not using _install
    if ! which rg &>/dev/null && ! _install ripgrep; then
        # If Linux, try installing from the github
        if [ "$(uname)" = "Linux" ]; then
            local _url="https://github.com/BurntSushi/ripgrep/releases/"
            local _ver="$(curl -sI ${_url%/}/latest | _sed -nr 's/^Location:.+\/releases\/tag\/(.+)$/\1/p' | tr -d '[:space:]')"
            _log "INFO" "Installing rg version: ${_ver} ..."
            sleep 3
            _download "${_url%/}/download/${_ver}/ripgrep_${_ver}_amd64.deb" "/tmp/ripgrep_${_ver}_amd64.deb" "Y" "Y" || return $?
            sudo dpkg -i /tmp/ripgrep_${_ver}_amd64.deb || return $?
        else
            _log "ERROR" "rg install failed."
            return 1
        fi
    fi
}

function f_setup_rg() {
    _symlink_or_download "runcom/rgrc" "$HOME/.rgrc" || return $?
    if ! grep -qR '^export RIPGREP_CONFIG_PATH=' $HOME/.bash_profile; then
        echo -e '\nexport RIPGREP_CONFIG_PATH=$HOME/.rgrc' >>$HOME/.bash_profile || return $?
    fi
}

function f_setup_screen() {
    if ! which screen &>/dev/null; then
        _log "ERROR" "no screen installed or not in PATH"
        return 1
    fi

    [ -d $HOME/.byobu ] || mkdir $HOME/.byobu
    _backup $HOME/.byobu/.screenrc
    _symlink_or_download "runcom/screenrc" "$HOME/.screenrc" || return $?
    [ -f $HOME/.byobu/.screenrc ] && rm -f $HOME/.byobu/.screenrc
    ln -s $HOME/.screenrc $HOME/.byobu/.screenrc
}

function f_install_golang() {
    local _ver="${1:-"1.[12]"}"
    # TODO: currently only for Ubuntu and Mac, and hard-coding go version
    if ! which go &>/dev/null || ! go version | grep -qE "go${_ver}"; then
        if [ "$(uname)" = "Darwin" ]; then
            if which brew &>/dev/null; then
                brew install go || return $? # as of 1.13.8, --with-cgo does not work.
            else
                _log "WARN" "Please install 'go'. https://golang.org/doc/install"
                sleep 3
                return 1
            fi
        else
            sudo add-apt-repository ppa:gophers/archive -y
            sudo apt-get update
            sudo apt-get install golang-${_ver}-go -y || return $?

            local _go="$(which go)"
            if [ -z "${_go}" ] && [ -s /usr/lib/go-${_ver}/bin/go ]; then
                sudo ln -s /usr/lib/go-${_ver}/bin/go /usr/bin/go
            elif [ -L "${_go}" ] && [ -s /usr/lib/go-${_ver}/bin/go ]; then
                sudo rm "${_go}"
                sudo ln -s /usr/lib/go-${_ver}/bin/go "${_go}"
            fi
        fi
    fi
}

function f_setup_golang() {
    local _ver="${1:-"1.13"}"
    f_install_golang "${_ver}"

    if [ ! -d "$HOME/go" ]; then
        _log "WARN" "\$HOME/go does not exist. Creating ..."
        mkdir "$HOME/go" || return 1
    fi
    if [ -z "$GOPATH" ]; then
        _log "WARN" "May need to add 'export GOPATH=$HOME/go' in profile"
        export GOPATH=$HOME/go
    fi
    # Installing something. Ex: go get -v -u github.com/hajimeo/docker-webui
    _log "INFO" "Installing/updating gore ..."
    go get -u github.com/motemen/gore/cmd/gore || return $?
    _log "INFO" "Installing/updating delve/dlv ..."
    # If Mac: brew install go-delve/delve/delve
    go get -u github.com/go-delve/delve/cmd/dlv || return $?
    [ ! -d /var/tmp/share ] && sudo mkdir -m 777 -p /var/tmp/share || return $?
    sudo cp -f $GOPATH/bin/dlv /var/tmp/share/dlv || return $?
    sudo chmod a+x /var/tmp/share/dlv
}

# Currently NOT using as it cause some slowness in the shell
function f_setup_pyenv() {
    # @see: https://github.com/pyenv/pyenv/wiki/Common-build-problems
    local _ver="${1:-"3.7.9"}"
    # At this moment, not sure if below is needed
    #if [ "$(uname)" = "Darwin" ]; then
    #    sudo installer -pkg /Library/Developer/CommandLineTools/Packages/macOS_SDK_headers_for_macOS_10.14.pkg -target /
    #fi
    if ! which pyenv; then
        curl https://pyenv.run | bash || return $?
    fi
    if grep -q -w pyenv $HOME/.bashrc || grep -q -w pyenv $HOME/.bash_profile; then
        echo "Seems pyenv is configured (or intentionally disabled in .bashrc / .bash_profile)"
    else
        cat << EOF >> $HOME/.bashrc
export PATH="\$HOME/.pyenv/bin:\$PATH"
eval "\$(pyenv init -)"
eval "\$(pyenv virtualenv-init -)"
EOF
    fi
    # shell script wouldn't read .bash_profile?
    source $HOME/.bashrc || return $?
    if [ -n "${_ver}" ]; then
        if [ ! -d "$HOME/.pyenv/versions/${_ver}" ]; then
            pyenv install ${_ver} || return $?
        fi
        pyenv local ${_ver}
        python3 -V | grep -iq "Python ${_ver}"
    fi
}

function f_setup_python() {
    local _pypi_proxy_url="$1"
    local _no_venv="$2"
    if ! which python3.7 &>/dev/null; then
        echo "FIXME: Due to Jupyter autocomplete bug, python 3.7 is required (use f_prepare to install)"
        return 1
    fi
    # Currently expecting anonymous is allowed.
    local _i_opt=""
    if _isUrl "${_pypi_proxy_url}" "Y" && [[ "${_pypi_proxy_url}" =~ ^https?://([^:/]+) ]]; then
        _i_opt="-i ${_pypi_proxy_url%/}/simple --trusted-host ${BASH_REMATCH[1]}"
    fi

    if [[ ! "${_no_venv}" =~ ^(y|Y) ]]; then
        deactivate &>/dev/null
        # NOTE: when python version is changed, need to run virtualenv command again
        echo "Activating virtualenv: $HOME/.pyvenv (https://virtualenv.pypa.io/en/latest/user_guide.html) ..."
        if ! python3.7 -m virtualenv -p python3.7 $HOME/.pyvenv; then
            python3.7 -m venv $HOME/.pyvenv || return $?
        fi
        source $HOME/.pyvenv/bin/activate || return $?
        # NOTE: Currently not using pyenv (below) as it makes shell slower
        #pyenv deactivate &>/dev/null    # Or pyenv local system
        #f_setup_pyenv
        #pyenv virtualenv ${_ver} mypyvenv || return $?
        #pyenv activate mypyvenv || return $?
    fi

    ### pip3 (not pip) from here ############################################################
    #python3.7 -m pip install -U pip ${_i_opt} &>/dev/null
    # outdated list
    python3.7 -m pip list -o ${_i_opt} | tee /tmp/pip.log
    #python -m pip list -o --format=freeze ${_i_opt} | cut -d'=' -f1 | xargs python -m pip install -U

    # My favourite/essential python packages (except jupyter and pandas related)
    python3.7 -m pip install -U ${_i_opt} lxml xmltodict pyyaml markdown memory_profiler
    #   %load_ext memory_profiler
    #   %mprun -f al.etl al.analyse_logs()
    python3.7 -m pip install -U ${_i_opt} pyjq 2>/dev/null # TODO: as of this typing, this fails against python 3.8 (3.7 looks OK)

    # Important packages (Jupyter and pandas)
    # TODO: Autocomplete doesn't work with Lab and NB if different version is used. @see https://github.com/ipython/ipython/issues/11530
    #       However, using 7.1.1 with python 3.8 may cause TypeError: required field "type_ignores" missing from Module
    python3.7 -m pip install -U ${_i_opt} ipython==7.1.1 || return $?  #prettytable==0.7.2
    #python3.7 -m pip install -U ${_i_opt} modin[ray] --log /tmp/pip.log    # it's OK if fails
    python3.7 -m pip install -U ${_i_opt} jupyter jupyterlab pandas dfsql --log /tmp/pip.log || return $?   #ipython
    # Reinstall: python3.7 -m pip uninstall -y jupyterlab && python3.7 -m pip install jupyterlab

    # Must-have packages. NOTE: Initially I thought pandasql looked good but it's actually using sqlite, and slow, and doesn't look like maintained any more.
    python3.7 -m pip install -U ${_i_opt} jupyter_kernel_gateway sqlalchemy ipython-sql pivottablejs matplotlib psycopg2 --log /tmp/pip.log
    # pandas_profiling may fail to install. pixiedust works only with jupyter-notebook
    #python3.7 -m pip install -U ${_i_opt} pandas_profiling pixiedust --log /tmp/pip.log
    #   import pandas_profiling as pdp
    #   pdp.ProfileReport(df)
    # NOTE: In case I might use jupyter notebook, still installing this
    python3.7 -m pip install -U ${_i_opt} bash_kernel --log /tmp/pip.log && python3.7 -m bash_kernel.install
    # For Spark etc., BeakerX http://beakerx.com/ NOTE: this works with only python3.7
    #python3.7 -m pip install -U ${_i_opt} beakerx && beakerx-install

    # Enable jupyter *Notebook* extensions NOTE: somehow this uses /usr/local/share/jupyter so may need sudo
    #sudo python3.7 -m pip install -U ${_i_opt} jupyter-contrib-nbextensions jupyter-nbextensions-configurator
    #jupyter contrib nbextension install && jupyter nbextensions_configurator enable && jupyter nbextension enable spellchecker/main
    # Spellchecker for Jupyter Lab but not working...?
    #jupyter labextension install @ijmbarr/jupyterlab_spellchecker

    # Enable Holloviews http://holoviews.org/user_guide/Installing_and_Configuring.html
    # Ref: http://holoviews.org/reference/index.html
    #python3.7 -m pip install ${_i_opt} 'holoviews[recommended]'
    #jupyter labextension install @pyviz/jupyterlab_pyviz
    # NOTE: Above causes ValueError: Please install nodejs 5+ and npm before continuing installation.
    # Not so useful? (may need sudo if installing)
    #python3.7 -m pip install ${_i_opt} jupyterlab_templates
    #jupyter labextension install jupyterlab_templates && jupyter serverextension enable --py jupyterlab_templates

    # For SASL test
    #_install libsasl2-dev
    #python3.7 -m pip install ${_i_opt} sasl thrift thrift-sasl PyHive

    # JDBC wrapper. "0.6.3" is for using Java 1.8 also this requires GCC
    #python3.7 -m pip install ${_i_opt} JPype1==0.6.3 JayDeBeApi
    # For Google BigQuery (actually one of below)
    #python3.7 -m pip install ${_i_opt} google-cloud-bigquery pandas-gbq

    f_jupyter_util
}

function f_jupyter_util() {
    local _dir="${1:-"${_SOURCE_REPO_BASE%/}/python"}"
    # If we use this location, .bash_profile automatically adds PYTHONPATH
    if [ ! -d "${_dir%/}" ]; then
        mkdir -p ${_dir%/} || return $?
    fi
    # If not local test, would like to always overwrite ...
    _check_update "${_dir%/}/jn_utils.py" "${_DOWNLOAD_FROM_BASE%/}/python/" "Y" || return $?
    _check_update "${_dir%/}/get_json.py" "${_DOWNLOAD_FROM_BASE%/}/python/" "Y" || return $?
    _check_update "${_dir%/}/analyse_logs.py" "${_DOWNLOAD_FROM_BASE%/}/python/" "Y" || return $?

    #$ jupyter-lab --generate-config
    #Writing default config to: /home/loganalyser/.jupyter/jupyter_notebook_config.py
    if [ ! -d "$HOME/.jupyter" ]; then
        mkdir -p "$HOME/.jupyter" || return $?
    fi
    # Port also can be specified with --port=xxxx
    cat << EOF > "$HOME/.jupyter/jupyter_notebook_config.py"
c.NotebookApp.ip = '0.0.0.0'  #default= localhost
#c.NotebookApp.port = 8888     #default=8888
EOF
    # Jupyter 3.0.x way
    # To reset: source $HOME/.pyvenv/bin/activate; jupyter-lab password
    cat << EOF > "$HOME/.jupyter/jupyter_server_config.json"
{
  "ServerApp": {
    "password": "sha1:80d886d09dd4:3f7f3075356e065192c9e55457792e282b421b1d"
  }
}
EOF
    if [ ! -d "$HOME/.ipython/profile_default/startup" ]; then
        mkdir -p "$HOME/.ipython/profile_default/startup" || return $?
    fi
    # As pandas_profiling can't be installed, No "import pandas_profiling as pp"
    #   How-to: pp.ProfileReport(df)
    # How to get the startup directory location:
    #   get_ipython().profile_dir.startup_dir
    cat << EOF > "$HOME/.ipython/profile_default/startup/import_ju.py"
import sys
if "${_dir%/}" not in sys.path:
    sys.path.append("${_dir%/}")
import pandas as pd
import get_json as gj
import jn_utils as ju
import analyse_logs as al
get_ipython().run_line_magic("matplotlib", "inline")
EOF
}

function f_setup_java() {
    local _v="${1-"8"}" # Using 8 as JayDeBeApi uses specific version and which is for java 8
    local _ver="${_v}"  # Java version can be "9" or "1.8"
    # NOTE: for Oracle java
    #wget -c --no-cookies --no-check-certificate --header "Cookie: oraclelicense=accept-securebackup-cookie" https://download.oracle.com/otn-pub/java/jdk/8u301-b09/d3c52aa6bfa54d3ca74e617f18309292/jre-8u301-linux-i586.tar.gz

    [[ "${_v}" =~ ^[678]$ ]] && _ver="1.${_v}"

    if [ "$(uname)" = "Darwin" ]; then
        if [ -z "${_v}" ]; then
            brew install java
        else
            brew tap adoptopenjdk/openjdk
            #brew search adoptopenjdk
            brew install adoptopenjdk${_v}
        fi
        #/usr/libexec/java_home -v ${_v}
    elif [ -z "${_v}" ]; then
        _log "INFO" "Version is not specified, so installing default-jdk ... (sudo required)"
        _install default-jdk
    else
        # If Linux, downloading .tar.gz file and extract, so that it can be re-used in the container
        # NOTE: with grep or sed, without --compressed is faster
        #local _java_exact_ver="$(basename $(curl -s https://github.com/AdoptOpenJDK/openjdk${_v}-binaries/releases/latest | _sed -nr 's/.+"(https:[^"]+)".+/\1/p'))"
        local _java_exact_ver="$(curl -s -L "https://api.adoptopenjdk.net/v3/assets/latest/${_v}/hotspot?release=latest&jvm_impl=hotspot&vendor=adoptopenjdk" | grep -m1 -E '"release_name": "jdk-?'${_v}'.[^"]+"' | grep -oE 'jdk-?'${_v}'[^"]+')"
        # NOTE: hoping the naming rule is same for different versions (eg: jdk8u275-b01, jdk-11.0.9.1+1)
        if [[ "${_java_exact_ver}" =~ (jdk-?)([^-+]+)([-+])([^_]+) ]]; then
            [ ! -d "/var/tmp/share/java" ] && mkdir -p -m 777 /var/tmp/share/java
            local _jdk="${BASH_REMATCH[1]}"         # jdk- or jdk
            local _jdk_ver="${BASH_REMATCH[2]}"     # 8u275 or 11.0.9.1
            local _ver_sep="${BASH_REMATCH[3]}"     # - or +
            local _jdk_minor="${BASH_REMATCH[4]}"   # b01 or 1
            local _ver_sep2=""
            [ "${_ver_sep}" == "+" ] && _ver_sep2="_"
            #https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u275-b01/OpenJDK8U-jdk_x64_linux_hotspot_8u275b01.tar.gz
            #https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.9.1%2B1/OpenJDK11U-jdk_x64_linux_hotspot_11.0.9.1_1.tar.gz
            local _fname="OpenJDK${_v}U-jdk_x64_linux_hotspot_${_jdk_ver}${_ver_sep2}${_jdk_minor}.tar.gz"
            _download "https://github.com/AdoptOpenJDK/openjdk${_v}-binaries/releases/download/${_jdk}${_jdk_ver}${_ver_sep}${_jdk_minor}/${_fname}" "/var/tmp/share/java/${_fname}" "Y" "Y" || return $?
            if [ -s "/var/tmp/share/java/${_fname}" ]; then
                tar -xf "/var/tmp/share/java/${_fname}" -C /var/tmp/share/java/ || return $?
                _log "INFO" "OpenJDK${_v} is extracted under '/var/tmp/share/java/${_java_exact_ver}'"
                if [ -d /etc/profile.d ] && [ ! -f /etc/profile.d/java.sh ]; then
                    _log "INFO" "Creating /etc/profile.d/java.sh ... (sudo required)"
                    cat << EOF > /tmp/java.sh
[[ "\$PATH" != *"/var/tmp/share/java/"* ]] && export PATH=/var/tmp/share/java/${_java_exact_ver}/bin:\${PATH#:}
[ -z "\${JAVA_HOME}" ] && export JAVA_HOME=/var/tmp/share/java/${_java_exact_ver}
EOF
                    sudo mv /tmp/java.sh /etc/profile.d/java.sh
                fi
            else
                _log "INFO" "Could not download ${_fname} so installing openjdk-${_v}-jdk ... (sudo required)"
                _install openjdk-${_v}-jdk
            fi
        fi
    fi

    # Below lines are for JayDeBeApi (which requires java 8), and it's OK if fails, so no || return $?
    local _parent_dir="${_SOURCE_REPO_BASE%/}"
    [ ! -d "${_parent_dir%/}/java/hadoop" ] && mkdir -p "${_parent_dir%/}/java/hadoop"
    #_download "https://public-xxxxxxx.s3.amazonaws.com/hive-jdbc-client-1.2.1.jar" "${_parent_dir%/}/java/hadoop/hive-jdbc-client-1.2.1.jar" "Y" "Y"
    _download "https://github.com/hajimeo/samples/raw/master/java/hadoop/hadoop-core-1.0.3.jar" "${_parent_dir%/}/java/hadoop/hadoop-core-1.0.3.jar" "Y" "Y"
    _download "https://github.com/hajimeo/samples/raw/master/java/hadoop/hive-jdbc-1.0.0-standalone.jar" "${_parent_dir%/}/java/hadoop/hive-jdbc-1.0.0-standalone.jar" "Y" "Y"

    if ! java -version 2>&1 | grep -w "build ${_ver}" -m 1; then
        _log "WARN" "Current Java version is not ${_ver}."
    fi
}

function _install() {
    if which apt-get &>/dev/null; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" || return $?
    elif which brew &>/dev/null; then
        # TODO: ugly hack for brew and python specific version installation
        if [[ "$@" =~ ^(.*)python([0-9]\.[0-9]+)(.*)$ ]]; then
            brew install ${BASH_REMATCH[1]}python@${BASH_REMATCH[2]}${BASH_REMATCH[3]}
        else
            brew install "$@" || return $?
        fi
    else
        _log "ERROR" "$(uname) is not supported yet to install a package"
        return 1
    fi
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

# TODO: setup below (not installing at this moment)
#s3cmd

main() {
    sudo echo "Starting setup ..."
    #f_prepare
    _log "INFO" "Running f_setup_misc ..."
    f_setup_misc
    echo "Exit code $?"
    _log "INFO" "Running f_setup_screen ..."
    f_setup_screen
    echo "Exit code $?"
    _log "INFO" "Running f_setup_rg ..."
    f_setup_rg
    echo "Exit code $?"
    _log "INFO" "Running f_setup_python ..."
    f_setup_python
    echo "Exit code $?"
    #_log "INFO" "Running f_setup_golang ..."
    #f_setup_golang
    #echo "Exit code $?"
    #_log "INFO" "Running f_setup_java ..."
    #f_setup_java
    #echo "Exit code $?"
    echo "Completed."
}

### Main ###############################################################################################################
if [ "$0" = "$BASH_SOURCE" ]; then
    if [[ "$1" =~ ^f_ ]]; then
        eval "$@"
    else
        main
    fi
fi