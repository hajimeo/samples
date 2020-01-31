# NOTE: for screen, .bashrc is needed, and in .bashrc, source .bash_profile
# An example of usage
#   ln -s $HOME/IdeaProjects/samples/runcom/bash_profile.sh $HOME/.bash_profile
#
export HISTTIMEFORMAT="%Y-%m-%d %T "

[ -s $HOME/IdeaProjects/samples/runcom/bash_aliases.sh ] && source $HOME/IdeaProjects/samples/runcom/bash_aliases.sh
[ -s $HOME/.bash_aliases ] && source $HOME/.bash_aliases

# Go/Golang related
if which go &>/dev/null; then
    [ -z "${GOROOT}" ] && export GOROOT=/usr/local/opt/go/libexec
    [ -z "${GOPATH}" ] && export GOPATH=$HOME/go
    [[ ":$PATH:" != *":$PATH:$GOROOT/bin:"* ]] && export PATH=${PATH%:}:$GOROOT/bin
    [[ ":$PATH:" != *":$GOPATH/bin:"* ]] && export PATH=${PATH%:}:$GOPATH/bin
fi

# Kerberos client
if [ -s $HOME/krb5.conf ]; then
    [ -z "${KRB5_CONFIG}" ] && export KRB5_CONFIG=$HOME/krb5.conf
fi

# ripgrep(rg)
if [ -s $HOME/.rgrc ]; then
    [ -z "${RIPGREP_CONFIG_PATH}" ] && export RIPGREP_CONFIG_PATH=$HOME/.rgrc
fi

# Some older Mac, pip3 was not in the path, and below was the workaround
#if [ -d /usr/local/Cellar/python/`python3 -V | cut -d " " -f 2`*/Frameworks/Python.framework/Versions/3.7/bin ]; then
#    # Mac's brew installs pip in this directory and may not in the path
#    export PATH=$(ls -d /usr/local/Cellar/python/`python3 -V | cut -d " " -f 2`*/Frameworks/Python.framework/Versions/3.7/bin):$PATH
#fi
if [ -d $HOME/Library/Python/3.7/bin ]; then
    # Intentionally adding at the beginning
    [[ ":$PATH:" != *":$HOME/Library/Python/3.7/bin:"* ]] && export PATH=$HOME/Library/Python/3.7/bin:${PATH#:}
fi
if [ -d /usr/local/sbin ]; then
    # Intentionally adding at the beginning
    [[ ":$PATH:" != *":/usr/local/sbin:"* ]] && export PATH=${PATH%:}:/usr/local/sbin
fi
if [ -d $HOME/IdeaProjects/samples/python ]; then
    # Intentionally adding at the beginning
    [[ ":$PYTHONPATH:" != *":$HOME/IdeaProjects/samples/python:"* ]] && export PYTHONPATH=$HOME/IdeaProjects/samples/python:$PYTHONPATH
fi

# java related
if [ -f /usr/libexec/java_home ]; then
    #[ -z "${JAVA_HOME}" ] && export JAVA_HOME=`/usr/libexec/java_home -v 10 2>/dev/null`
    [ -z "${JAVA_HOME}" ] && export JAVA_HOME=`/usr/libexec/java_home -v 1.8 2>/dev/null`
fi

export _SERVICE="sonatype"