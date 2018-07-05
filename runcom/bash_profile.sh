# ln -s ~/IdeaProjects/samples/runcom/bash_profile.sh ~/.bash_profile

# Go/Golang related
export GOROOT=/usr/local/opt/go/libexec
export GOPATH=$HOME/go
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin

# Kerberos client
export KRB5_CONFIG=$HOME/krb5.conf

# ripgrep(rg)
export RIPGREP_CONFIG_PATH=$HOME/.rgrc

if [ -f ~/IdeaProjects/samples/runcom/bash_aliases.sh ]; then
    source ~/IdeaProjects/samples/runcom/bash_aliases.sh
fi
