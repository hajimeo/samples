# source /dev/stdin <<< "(curl https://raw.githubusercontent.com/hajimeo/samples/master/runcom/bash_profile.sh --compressed)"

# NOTE: for screen, .bashrc is needed, and in .bashrc, source .bash_profile
# An example of usage
#   ln -s $HOME/IdeaProjects/samples/runcom/bash_profile.sh $HOME/.bash_profile
#
export HISTTIMEFORMAT="%Y-%m-%d %T "

[ -s $HOME/.bashrc ] && source $HOME/.bashrc
[ -s $HOME/.bash_aliases ] && source $HOME/.bash_aliases
#[ -s $HOME/IdeaProjects/samples/runcom/bash_aliases.sh ] && source $HOME/IdeaProjects/samples/runcom/bash_aliases.sh

# @see: https://threkk.medium.com/how-to-use-bookmarks-in-bash-zsh-6b8074e40774
if [ -d "$HOME/.cdpath" ]; then
    export CDPATH=".:$HOME/.cdpath:/"
    alias goto="cd -P"
    alias gt="cd -P"
    #bookmark $HOME/Documents/cases
    function bookmark() {
        ln -v -s "$(realpath "${1%/}")" "$HOME/.cdpath/$(basename "${1%/}")"
    }
fi

if [ -x "/usr/local/opt/curl/bin/curl" ]; then
    export PATH="/usr/local/opt/curl/bin:$PATH"
fi

# nuget/dotnet related
if [ -s "$HOME/Apps/dotnet/dotnet" ]; then
    DOTNET_ROOT=$HOME/Apps/dotnet
    #mkdir -v -p "$DOTNET_ROOT"
    #curl -O -J -L https://download.visualstudio.microsoft.com/download/pr/50ae4c83-5e38-4eba-b683-68313e7ed6f2/14a0ed0f807fc8ecf3f68cb3464016bc/dotnet-sdk-5.0.402-osx-x64.tar.gz
    #tar -vzxf "$(ls -1 dotnet-sdk-5.*-osx-x64.tar.gz | tail -n1)" -C "$DOTNET_ROOT"
    export PATH=${PATH%:}:${DOTNET_ROOT%/}
fi

# Go/Golang related
if which go &>/dev/null; then
    [ -z "${GOROOT}" ] && export GOROOT=/usr/local/opt/go/libexec
    [[ ":$PATH:" != *":$PATH:$GOROOT/bin:"* ]] && export PATH=${PATH%:}:$GOROOT/bin
    #export GO111MODULE=off   # This is for keeping supporting older than 1.16
    [ -z "${GOPATH}" ] && export GOPATH=$HOME/go
    [[ ":$PATH:" != *":$GOPATH/bin:"* ]] && export PATH=${PATH%:}:$GOPATH/bin
fi

# Haskell related
if [ -d "$HOME/.local/bin" ]; then
    [[ ":$PATH:" != *":$PATH:$HOME/.local/bin:"* ]] && export PATH=${PATH%:}:$HOME/.local/bin
fi
type stack &>/dev/null && alias ghci="stack ghci"

# Kerberos client
if [ -s $HOME/krb5.conf ]; then
    [ -z "${KRB5_CONFIG}" ] && export KRB5_CONFIG=$HOME/krb5.conf
fi

# ripgrep(rg)
if [ -s $HOME/.rgrc ]; then
    [ -z "${RIPGREP_CONFIG_PATH}" ] && export RIPGREP_CONFIG_PATH=$HOME/.rgrc
fi

# Mac specific (so far python and Java)
if [ "$(uname)" = "Darwin" ]; then
    # Some older Mac, pip3 was not in the path, and below was the workaround
    #if [ -d /usr/local/Cellar/python/`python3 -V | cut -d " " -f 2`*/Frameworks/Python.framework/Versions/3.7/bin ]; then
    #    # Mac's brew installs pip in this directory and may not in the path
    #    export PATH=$(ls -d /usr/local/Cellar/python/`python3 -V | cut -d " " -f 2`*/Frameworks/Python.framework/Versions/3.7/bin):$PATH
    #fi
    # NOTE: This would no longer needed. Remove later
    # Use Brew one first (Using 3.7 for jupyter related dependency)
    #___python37bin="$(ls -1d /usr/local/Cellar/python@3.7/3.7*/bin | tail -n1)"
    #if [ -n "${___python37bin}" ]; then
    #    [[ ":$PATH:" != *":${___python37bin%/}:"* ]] && export PATH=${___python37bin%/}:${PATH#:}
    #elif [ -d $HOME/Library/Python/3.7/bin ]; then
    #    [[ ":$PATH:" != *":$HOME/Library/Python/3.7/bin:"* ]] && export PATH=$HOME/Library/Python/3.7/bin:${PATH#:}
    #fi
    if [ -d /usr/local/sbin ]; then
        # Intentionally adding at the beginning
        [[ ":$PATH:" != *":/usr/local/sbin:"* ]] && export PATH=${PATH%:}:/usr/local/sbin
    fi
    if [ -d $HOME/IdeaProjects/samples/python ]; then
        # Intentionally adding at the beginning
        if [ -z "$PYTHONPATH" ]; then
            export PYTHONPATH=$HOME/IdeaProjects/samples/python
        elif [[ ":$PYTHONPATH:" != *":$HOME/IdeaProjects/samples/python:"* ]]; then
            export PYTHONPATH=$HOME/IdeaProjects/samples/python:$PYTHONPATH
        fi
    fi

    # Java related
    # Truststore location: $(/usr/libexec/java_home)/lib/security/cacerts or $(/usr/libexec/java_home)/jre/lib/security/cacerts
    # To verify: -Djavax.net.debug=ssl,keymanager
    if [ -f /usr/libexec/java_home ]; then
        #[ -z "${_JAVA_HOME_11}" ] && export _JAVA_HOME_11=`/usr/libexec/java_home -v 11 2>/dev/null`
        [ -z "${JAVA_HOME}" ] && export JAVA_HOME=`/usr/libexec/java_home -v 1.8 2>/dev/null`
    fi
    if [ -d "$HOME/Apps/zulu11.60.19-ca-jdk11.0.17-macosx_aarch64" ]; then
        alias jshell="$HOME/Apps/zulu11.60.19-ca-jdk11.0.17-macosx_aarch64/bin/jshell"
        [ -z "${_JAVA_HOME_11}" ] && export _JAVA_HOME_11="$HOME/Apps/zulu11.60.19-ca-jdk11.0.17-macosx_aarch64"
    elif [ -n "${_JAVA_HOME_11%/}" ]; then
        alias jshell="${_JAVA_HOME_11}/bin/jshell"
    fi

    # Docker related. Use "podman" first
    if type podman &>/dev/null; then
        #brew install podman
        #podman machine init --cpus 2 --disk-size 40 --memory 4096
        # To add my root CA: podman machine ssh, then add pem under /etc/pki/ca-trust/source/anchors/ and update-ca-trust
        alias pd-start='podman machine start'
    elif type lima &>/dev/null; then
        # "limadocker" is the hostname defined in $HOME/.ssh/config
        export DOCKER_HOST=ssh://limadocker:60006
        alias lm-start='limactl start default'
    elif type docker-machine &>/dev/null; then
        alias dm-start='docker-machine start default && eval "$(docker-machine env default)" && docker-machine ssh default "echo \"$(docker-machine ip default) local.standalone.localdomain\" | sudo tee -a /etc/hosts"'
        [ -z "${DOCKER_HOST}" ] && docker-machine status default 2>/dev/null | grep -q "Running" && eval "$(docker-machine env default)"
        # To stop, docker-machine start default, then open a new shell
    fi
fi

# The next line updates PATH for the Google Cloud SDK.
if [ -f "$HOME/Downloads/google-cloud-sdk/path.bash.inc" ]; then . "$HOME/Downloads/google-cloud-sdk/path.bash.inc"; fi

# The next line enables shell command completion for gcloud.
if [ -f "$HOME/Downloads/google-cloud-sdk/completion.bash.inc" ]; then . "$HOME/Downloads/google-cloud-sdk/completion.bash.inc"; fi

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
