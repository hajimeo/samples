# ln -s ~/IdeaProjects/samples/runcom/bash_profile.sh ~/.bash_profile
if [ -s ~/IdeaProjects/samples/runcom/bash_aliases.sh ]; then
    source ~/IdeaProjects/samples/runcom/bash_aliases.sh
elif [ -s ~/.bash_aliases ]; then
    source ~/.bash_aliases
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
if [ -s RIPGREP_CONFIG_PATH=$HOME/.rgrc ]; then
    export RIPGREP_CONFIG_PATH=$HOME/.rgrc
fi

# python related
if [ -d ~/IdeaProjects/samples/python ]; then
    export PYTHONPATH=~/IdeaProjects/samples/python:$PYTHONPATH
fi

# java related
if [ -f /usr/libexec/java_home ]; then
    #export JAVA_HOME=`/usr/libexec/java_home -v 10`
    export JAVA_HOME=`/usr/libexec/java_home -v 1.8`
fi

# iterm2
#curl -L https://iterm2.com/shell_integration/bash -o ~/.iterm2_shell_integration.bash
if [ -n "$ITERM_SESSION_ID" ] && [ -f ~/.iterm2_shell_integration.bash ]; then
    source ~/.iterm2_shell_integration.bash
fi
