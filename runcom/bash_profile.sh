# source /dev/stdin <<< "(curl https://raw.githubusercontent.com/hajimeo/samples/master/runcom/bash_profile.sh --compressed)"

# NOTE: for screen, .bashrc is needed, and in .bashrc, source .bash_profile
# An example of usage
#   ln -s $HOME/IdeaProjects/samples/runcom/bash_profile.sh $HOME/.bash_profile
#
export HISTTIMEFORMAT="%Y-%m-%d %T "

[ -s $HOME/.bashrc ] && source $HOME/.bashrc
[ -s $HOME/.bash_aliases ] && source $HOME/.bash_aliases
#[ -s $HOME/IdeaProjects/samples/runcom/bash_aliases.sh ] && source $HOME/IdeaProjects/samples/runcom/bash_aliases.sh

# Go/Golang related
if which go &>/dev/null; then
    [ -z "${GOROOT}" ] && export GOROOT=/usr/local/opt/go/libexec
    [ -z "${GOPATH}" ] && export GOPATH=$HOME/go
    [[ ":$PATH:" != *":$PATH:$GOROOT/bin:"* ]] && export PATH=${PATH%:}:$GOROOT/bin
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

if [ "$(uname)" = "Darwin" ]; then
    # Some older Mac, pip3 was not in the path, and below was the workaround
    #if [ -d /usr/local/Cellar/python/`python3 -V | cut -d " " -f 2`*/Frameworks/Python.framework/Versions/3.7/bin ]; then
    #    # Mac's brew installs pip in this directory and may not in the path
    #    export PATH=$(ls -d /usr/local/Cellar/python/`python3 -V | cut -d " " -f 2`*/Frameworks/Python.framework/Versions/3.7/bin):$PATH
    #fi
    # Use Brew one first (Using 3.7 for jupyter related dependency)
    ___python37bin="$(ls -1d /usr/local/Cellar/python@3.7/3.7*/bin | tail -n1)"
    if [ -n "${___python37bin}" ]; then
        [[ ":$PATH:" != *":${___python37bin%/}:"* ]] && export PATH=${___python37bin%/}:${PATH#:}
    elif [ -d $HOME/Library/Python/3.7/bin ]; then
        [[ ":$PATH:" != *":$HOME/Library/Python/3.7/bin:"* ]] && export PATH=$HOME/Library/Python/3.7/bin:${PATH#:}
    fi
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
    # java related
    if [ -f /usr/libexec/java_home ]; then
        #[ -z "${JAVA_HOME}" ] && export JAVA_HOME=`/usr/libexec/java_home -v 11 2>/dev/null`
        [ -z "${JAVA_HOME}" ] && export JAVA_HOME=`/usr/libexec/java_home -v 1.8 2>/dev/null`
        _JAVA_HOME_11="$(/usr/libexec/java_home -v 11)"
        [ -n "${_JAVA_HOME_11}" ] && alias jshell="$(/usr/libexec/java_home -v 11)/bin/jshell"
    fi
fi

#if [ -d "$HOME/.pyenv/bin" ]; then
#    export PATH="$HOME/.pyenv/bin:$PATH"
#    eval "$(pyenv init -)"
#    eval "$(pyenv virtualenv-init -)"
#fi

if [ -d "$HOME/IdeaProjects/grumpy/build" ]; then
    # https://github.com/google/grumpy
    # make
    export PATH="$HOME/IdeaProjects/grumpy/build/bin:$PATH"
    export GRUMPYPATH="$HOME/IdeaProjects/grumpy/build"
    #export GOPATH="$GRUMPYPATH:$GOPATH" # TODO: not sure if this is OK for other golang code
    #export PYTHONPATH="$HOME/IdeaProjects/grumpy/build/lib/python2.7/site-packages:$PYTHONPATH"
    # echo 'some python code' | GOPATH=GRUMPYPATH grumprun
    # TODO: below causes get_json.bin: line 1: syntax error near unexpected token `newline'
    #grumpc -modname=get_json ./get_json.py > ./get_json/module.go
    #go build -o get_json_`uname` ./get_json
fi

export _SERVICE="sonatype"

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/hosako/Downloads/google-cloud-sdk/path.bash.inc' ]; then . '/Users/hosako/Downloads/google-cloud-sdk/path.bash.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/hosako/Downloads/google-cloud-sdk/completion.bash.inc' ]; then . '/Users/hosako/Downloads/google-cloud-sdk/completion.bash.inc'; fi
