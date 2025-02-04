if [ -z "${_CONN_TO}" ]; then
  if [ -n "$SSH_CLIENT" ]; then
    _CONN_TO="$(echo $SSH_CLIENT | cut -d' ' -f1)"
  else
    _CONN_TO="$(w -hi | sort -k2 | grep -m1 -oE '192\.[0-9]+\.[0-9]+\.[0-9]+')"
  fi
fi
#sshfs -o uid=1000,gid=1000,umask=002,reconnect,follow_symlinks,transform_symlinks ${USER}@${_CONN_TO}:/Users/${USER}/share $HOME/share
sshfs -o uid=1000,gid=1000,umask=002,reconnect,follow_symlinks,transform_symlinks ${USER}@${_CONN_TO}:/Users/${USER}/utm-share /var/tmp/utm-share
sshfs -o uid=1000,gid=1000,umask=002,reconnect,follow_symlinks,transform_symlinks ${USER}@${_CONN_TO}:/Users/${USER}/IdeaProjects $HOME/IdeaProjects
sshfs -o uid=1000,gid=1000,umask=002,reconnect,follow_symlinks,transform_symlinks ${USER}@${_CONN_TO}:/Volumes/Samsung_T5/hajime/cases $HOME/Documents/cases
sshfs -o uid=1000,gid=1000,umask=002,reconnect,follow_symlinks,transform_symlinks ${USER}@${_CONN_TO}:/Volumes/Samsung_T5/hajime/nexus_executable_cache $HOME/.nexus_executable_cache
mount | grep "${USER}@${_CONN_TO}"
exit 0