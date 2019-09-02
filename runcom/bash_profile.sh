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
    [[ ":$PATH:" != *":$PATH:$GOROOT/bin:"* ]] && export PATH=$PATH:$GOROOT/bin
    [[ ":$PATH:" != *":$GOPATH/bin:"* ]] && export PATH=$PATH:$GOPATH/bin
fi

# Kerberos client
if [ -s $HOME/krb5.conf ]; then
    [ -z "${KRB5_CONFIG}" ] && export KRB5_CONFIG=$HOME/krb5.conf
fi

# ripgrep(rg)
if [ -s $HOME/.rgrc ]; then
    [ -z "${RIPGREP_CONFIG_PATH}" ] && export RIPGREP_CONFIG_PATH=$HOME/.rgrc
fi

# python related
if [ -d /usr/local/Cellar/python/`python3 -V | cut -d " " -f 2`/Frameworks/Python.framework/Versions/3.7/bin ]; then
    # Mac's brew installs pip in this directory and may not in the path
    export PATH=/usr/local/Cellar/python/`python3 -V | cut -d " " -f 2`/Frameworks/Python.framework/Versions/3.7/bin:$PATH
    # Rather than above, maybe better create a symlink for pip3?
fi
if [ -d $HOME/IdeaProjects/samples/python ]; then
    # Intentionally adding at the beginning
    [[ ":$PYTHONPATH:" != *":$HOME/IdeaProjects/samples/python:"* ]] && export PYTHONPATH=$HOME/IdeaProjects/samples/python:$PYTHONPATH
fi

# java related
if [ -f /usr/libexec/java_home ]; then
    #[ -z "${JAVA_HOME}" ] && export JAVA_HOME=`/usr/libexec/java_home -v 10`
    [ -z "${JAVA_HOME}" ] && export JAVA_HOME=`/usr/libexec/java_home -v 1.8`
fi

# iterm2
#curl -L https://iterm2.com/shell_integration/bash -o $HOME/.iterm2_shell_integration.bash
if [ -n "$ITERM_SESSION_ID" ] && [ -f $HOME/.iterm2_shell_integration.bash ]; then
    source $HOME/.iterm2_shell_integration.bash
fi

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/hajime/Downloads/google-cloud-sdk/path.bash.inc' ]; then . '/Users/hajime/Downloads/google-cloud-sdk/path.bash.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/hajime/Downloads/google-cloud-sdk/completion.bash.inc' ]; then . '/Users/hajime/Downloads/google-cloud-sdk/completion.bash.inc'; fi
