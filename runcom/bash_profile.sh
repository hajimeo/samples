# ln -s ~/IdeaProjects/samples/runcom/bash_profile.sh ~/.bash_profile
if [ -f ~/IdeaProjects/samples/runcom/bash_aliases.sh ]; then
    source ~/IdeaProjects/samples/runcom/bash_aliases.sh
fi

# Go/Golang related
export GOROOT=/usr/local/opt/go/libexec
export GOPATH=$HOME/go
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin

# Kerberos client
export KRB5_CONFIG=$HOME/krb5.conf

# ripgrep(rg)
export RIPGREP_CONFIG_PATH=$HOME/.rgrc

# python
export PYTHONPATH=~/IdeaProjects/samples/python:$PYTHONPATH

# java
#export JAVA_HOME=`/usr/libexec/java_home -v 10`
export JAVA_HOME=`/usr/libexec/java_home -v 1.8`

# iterm2
#curl -L https://iterm2.com/shell_integration/bash -o ~/.iterm2_shell_integration.bash
if [ -n "$ITERM_SESSION_ID" ] && [ -f ~/.iterm2_shell_integration.bash ]; then
    source ~/.iterm2_shell_integration.bash
fi
