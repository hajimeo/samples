# ln -s ~/IdeaProjects/samples/runcom/bash_profile.sh ~/.bash_profile

export GOPATH=$HOME/go
export KRB5_CONFIG=$HOME/krb5.conf
export RIPGREP_CONFIG_PATH=$HOME/.rgrc

if [ -f ~/IdeaProjects/samples/runcom/bash_aliases.sh ]; then
    source ~/IdeaProjects/samples/runcom/bash_aliases.sh
fi
