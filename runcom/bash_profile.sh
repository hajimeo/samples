# NOTE: for screen, .bashrc is needed, and in .bashrc, source .bash_profile
# An example of usage
#   ln -s $HOME/IdeaProjects/samples/runcom/bash_profile.sh $HOME/.bash_profile
#
if [ -s $HOME/IdeaProjects/samples/runcom/bash_aliases.sh ]; then
    source $HOME/IdeaProjects/samples/runcom/bash_aliases.sh
elif [ -s $HOME/.bash_aliases ]; then
    source $HOME/.bash_aliases
fi

# Go/Golang related
if [ -d /usr/local/opt/go/libexec ]; then
    export GOROOT=/usr/local/opt/go/libexec
    export GOPATH=$HOME/go
    export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
fi

# Kerberos client
if [ -s $HOME/krb5.conf ]; then
    export KRB5_CONFIG=$HOME/krb5.conf
fi

# ripgrep(rg)
if [ -s $HOME/.rgrc ]; then
    export RIPGREP_CONFIG_PATH=$HOME/.rgrc
fi

# python related
if [ -d /usr/local/Cellar/python/`python3 -V | cut -d " " -f 2`/Frameworks/Python.framework/Versions/3.7/bin ]; then
    # Mac's brew installs pip in this directory and may not in the path
    export PATH=/usr/local/Cellar/python/`python3 -V | cut -d " " -f 2`/Frameworks/Python.framework/Versions/3.7/bin:$PATH
    # Rather than above, maybe better create a symlink for pip3?
fi
if [ -d $HOME/IdeaProjects/samples/python ]; then
    export PYTHONPATH=$HOME/IdeaProjects/samples/python:$PYTHONPATH
fi

# java related
if [ -f /usr/libexec/java_home ]; then
    #export JAVA_HOME=`/usr/libexec/java_home -v 10`
    export JAVA_HOME=`/usr/libexec/java_home -v 1.8`
fi

# iterm2
#curl -L https://iterm2.com/shell_integration/bash -o $HOME/.iterm2_shell_integration.bash
if [ -n "$ITERM_SESSION_ID" ] && [ -f $HOME/.iterm2_shell_integration.bash ]; then
    source $HOME/.iterm2_shell_integration.bash
fi
