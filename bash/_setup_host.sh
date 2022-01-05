#!/usr/bin/env bash
# This script contains functions which are for setting up host (Ubuntu for now) to install and setup packages.
#
# curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/_setup_host.sh
#
# Do NOT add functions which administrate docker.
# Do NOT add functions which run inside of a docker container.
# start_hdp.sh sources this script to call the functions.
#
# @author hajime
#

_DL_URL="${_DL_URL:-"https://raw.githubusercontent.com/hajimeo/samples/master"}"
type _import &>/dev/null || _import() { [ ! -s /tmp/${1}_$$ ] && curl -sf --compressed "${_DL_URL%/}/bash/$1" -o /tmp/${1}_$$; . /tmp/${1}_$$; }
_import "utils.sh"

function f_host_misc() {
    local __doc__="Misc. changes for Ubuntu OS"

    [ ! -d ${_WORK_DIR} ] && mkdir -p -m 777 ${_WORK_DIR}

    # AWS / Openstack only change
    if [ -s /home/ubuntu/.ssh/authorized_keys ] && [ ! -f $HOME/.ssh/authorized_keys.bak ]; then
        cp -p $HOME/.ssh/authorized_keys $HOME/.ssh/authorized_keys.bak
        grep 'Please login as the user' $HOME/.ssh/authorized_keys && cat /home/ubuntu/.ssh/authorized_keys >$HOME/.ssh/authorized_keys
    fi

    # apt-get instll openssh-server
    # If you would like to use the default, comment PasswordAuthentication or PermitRootLogin
    _upsert "/etc/ssh/sshd_config" "PasswordAuthentication" "yes" "#PasswordAuthentication" " "
    #_upsert "/etc/ssh/sshd_config" "PermitRootLogin" "yes" "#PermitRootLogin" " "
    _upsert "/etc/ssh/sshd_config" "ClientAliveInterval" "60" "#ClientAliveInterval" " "
    _upsert "/etc/ssh/sshd_config" "GatewayPorts" "yes" "#GatewayPorts" " "
    if [ $? -eq 0 ]; then   # not perfect but better than not checking.
        service ssh restart
    fi

    if [ ! -s /etc/update-motd.d/99-host-misc ]; then
        #ls -lt ~/*.resp
        cat << EOF > /etc/update-motd.d/99-host-misc
#!/bin/bash
screen -ls
docker ps
EOF
        chmod a+x /etc/update-motd.d/99-host-misc
        run-parts --lsbsysinit /etc/update-motd.d >/run/motd.dynamic
    fi

    if [ ! -f /etc/cron.daily/ipchk ]; then
        echo '#!/usr/bin/env bash
_ID="$(hostname -s | tail -c 8)"
_IP="$(ip route get 1 | sed -nr \"s/^.* src ([^ ]+) .*$/\1/p\")"
curl -s -f "http://www.osakos.com/tools/info.php?id=${_ID}&LOCAL_ADDR=${_IP}"' >/etc/cron.daily/ipchk
        chmod a+x /etc/cron.daily/ipchk
    fi

    f_del_log_cron "${_WORK_DIR%/}/*" "28"
}

function f_del_log_cron() {
    local __doc__="Add a *daily* cron for deleting 'log' and backup files."
    local _parent_dir="${1:-"${_WORK_DIR%/}/*"}"
    local _days="${2:-"7"}"
    # run-parts --test /etc/cron.daily
    # service cron status  # if fails service --status-all (or maybe crond)
    # Do not use any extension (.sh, .cron etc.)

    # It's OK if _parent_dir doesn't exist, but date should be number
    [[ "${_days}" =~ [1-9][0-9]* ]] || return 11
    local _name="del-${_parent_dir//[^[:alnum:]]/_}-${_days}_days"
    if [ -s /etc/cron.daily/${_name} ]; then
        echo "/etc/cron.daily/${_name} exists"
        return 1
    fi
    # NOTE: I'm using -print to output what will be deleted into STDOUT (but hiding error), which may generate cron email to root
    echo '#!/bin/bash
find '${_parent_dir%/}'/logs -type f -name "*log*" -mtime +'${_days}' -print -delete
find '${_parent_dir%/}'/backups -type f -mtime +'$((${_days} * 3))' -print -delete
find '${_parent_dir%/}'/backups/* -type d -mtime +2 -empty -print -delete
exit $?' >/etc/cron.daily/${_name}
    chmod a+x /etc/cron.daily/${_name}
}

function f_shellinabox() {
    local __doc__="Install and set up shellinabox https://code.google.com/archive/p/shellinabox/wikis/shellinaboxd_man.wiki"
    local _user="${1-webuser}"
    local _pass="${2-webuser}"
    local _proxy_port="${3-28081}"

    # TODO: currently only Ubuntu
    apt-get install -y openssl shellinabox || return $?

    if ! id -u $_user &>/dev/null; then
        f_useradd "$_user" "$_pass" "Y" || return $?
        usermod -a -G docker ${_user}
        _log "INFO" "${_user}:${_pass} has been created."
    fi

    if ! grep -qE "^SHELLINABOX_ARGS.+${_user}:.+/shellinabox_login\"" /etc/default/shellinabox; then
        # NOTE: disabling SSL for avoiding various errors (because too old), but it's via SSH anyway.
        [ ! -s /etc/default/shellinabox.orig ] && cp -p /etc/default/shellinabox /etc/default/shellinabox.orig
        sed -i 's@^SHELLINABOX_ARGS=.\+@SHELLINABOX_ARGS="--no-beep --disable-ssl -s /'${_user}':'${_user}':'${_user}':HOME:/usr/local/bin/shellinabox_login"@' /etc/default/shellinabox
        service shellinabox restart || return $?
    fi

    # NOTE: Assuming socks5 proxy is running on localhost 28081
    if [ ! -f /usr/local/bin/setup_standalone.sh ]; then
        cp $BASH_SOURCE /usr/local/bin/setup_standalone.sh || return $?
        _log "INFO" "$BASH_SOURCE is copied to /usr/local/bin/setup_standalone.sh. To avoid confusion, please delete .sh one"
    fi
    chown root:docker /usr/local/bin/setup_standalone*
    chmod 750 /usr/local/bin/setup_standalone*

    # Finding Network Address from docker. Seems Mac doesn't care if IP doesn't end with .0
    local _net_addr="$(docker inspect bridge | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['IPAM']['Config'][0]['Subnet'])")"
    _net_addr="$(echo "${_net_addr}" | sed 's/\.[1-9]\+\/[1-9]\+/.0/')"

    curl -s -f --retry 3 -o /usr/local/bin/shellinabox_login https://raw.githubusercontent.com/hajimeo/samples/master/misc/shellinabox_login.sh || return $?
    sed -i "s/%_user%/${_user}/g" /usr/local/bin/shellinabox_login
    sed -i "s/%_proxy_port%/${_proxy_port}/g" /usr/local/bin/shellinabox_login
    sed -i "s@%_net_addr%@${_net_addr}@g" /usr/local/bin/shellinabox_login
    chmod a+x /usr/local/bin/shellinabox_login

    sleep 1
    local _port=$(sed -n -r 's/^SHELLINABOX_PORT=([0-9]+)/\1/p' /etc/default/shellinabox)
    lsof -i:${_port}
    _log "INFO" "To access: 'http://$(ip route get 1 | sed -nr 's/^.* src ([^ ]+) .*$/\1/p'):${_port}/${_user}/'"
}

function f_sysstat_setup() {
    local __doc__="Install and set up sysstat"

    if ! which apt-get &>/dev/null; then
        _warn "No apt-get"
        return 1
    fi

    which sar &>/dev/null
    if [ $? -ne 0 ]; then
        apt-get -y install sysstat
    fi
    grep -i '^ENABLED="false"' /etc/default/sysstat &>/dev/null
    if [ $? -eq 0 ]; then
        sed -i.bak -e 's/ENABLED=\"false\"/ENABLED=\"true\"/' /etc/default/sysstat
        service sysstat restart
    fi
}

function f_haproxy() {
    local __doc__="Install and setup HAProxy"
    # NOTE: HAProxy needs a concatenated cert: cat ./server.crt ./rootCA.pem ./server.key > certificates.pem'
    # To generate '_nodes': docker ps --format "{{.Names}}" | grep -E "^node-(nxrm-ha.|nxiq|freeipa)$" | sort | sed 's/$/.standalone.localdomain/' | tr '\n' ' '
    local _nodes="${1}"                                                     # Space delimited. If empty, generated from 'docker ps'
    local _ports="${2:-"389 8444 8081 8443=8081 8070 8071 8470=8070 18185=18184"}" # Space delimited and accept '='
    local _skipping_chk="${3}"                                              # Not to check each backend port (handy when you will start backend later)
    local _certificate="${4}"                                               # Expecting same (concatenated) cert for front and backend
    local _haproxy_custom_cfg_dir="${5:-"${_WORK_DIR%/}/haproxy"}"          # Under this directory, create haproxy.PORT.cfg file
    local _domain="${6:-"standalone.localdomain"}"                          # `hostname -d`
    #local _haproxy_tmpl_conf="${_WORK_DIR%/}/haproxy.tmpl.cfg}"

    local _cfg="/etc/haproxy/haproxy.cfg"
    if which haproxy &>/dev/null; then
        _info "INFO" "HAProxy is already installed. To update, run apt-get|yum manually."
    else
        apt-get install haproxy rsyslog -y || return $?
    fi

    if [ -z "${_nodes}" ]; then
        # I'm using FreeIPA and that container name includes 'freeipa'
        _nodes="$(for _n in $(docker ps --format "{{.Names}}" | grep -E "^node-(nxrm-ha.|nxiq|freeipa)$" | sort); do docker inspect ${_n} | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['Config']['Hostname'])"; done | tr '\n' ' ')"
        if [ -z "${_nodes}" ]; then
            _info "WARN" "No nodes to setup/check. Exiting..."
            return 0
        fi
        _info "INFO" "Using '${_nodes}' ..."

        if [ -z "${_certificate}" ]; then
            _certificate="${_WORK_DIR%/}/cert/${_domain}.certs.pem"
            if [ ! -s "${_certificate}" ]; then
                if ! curl -f -o ${_certificate} "https://raw.githubusercontent.com/hajimeo/samples/master/misc/${_domain}.certs.pem"; then
                    _certificate=""
                fi
            fi
            _info "INFO" "Using '${_certificate}' ..."
        fi
    fi

    # If certificate is given, assuming to use TLS/SSL on *frontend*
    if [ -n "${_certificate}" ] && [ ! -s "${_certificate}" ]; then
        _error "No ${_certificate} file to setup TLS/SSL/HTTPS."
        return 1
    fi

    # Backup config file
    if [ -s "${_cfg}" ]; then
        mv -v "${_cfg}" "/tmp/$(basename ${_cfg})".$(date +"%Y%m%d%H%M%S") || return $?
    fi

    # HAProxy config 'global', 'defaults', and 'stats' sections
    echo "global
  maxconn 256
  ssl-server-verify none

defaults
  option forwardfor except 127.0.0.1
  mode http
  timeout connect 5000ms
  timeout client 2d
  timeout server 2d
  # timeout tunnel needed for websockets
  timeout tunnel 3600s
  #default-server init-addr last,libc,none

listen stats
  bind *:1080
  stats enable
  stats uri /
  stats auth admin:admin
" >${_cfg}

    # If dnsmasq is installed, utilise it
    local _resolver=""
    if which dnsmasq &>/dev/null; then
        echo "resolvers dnsmasq
  nameserver dns1 localhost:53
  accepted_payload_size 8192
" >>"${_cfg}"
        _resolver="resolvers dnsmasq init-addr none"
    fi

    # Check each port and append to config
    for _p in ${_ports}; do
        local _frontend_proto="http"
        local _backend_proto="http"

        local _f_port=${_p}
        local _b_port=${_p}
        if [[ "${_p}" =~ ^([0-9]+)=([0-9]+)$ ]]; then
            _f_port=${BASH_REMATCH[1]}
            _b_port=${BASH_REMATCH[2]}
            # if frontend port is different from backend port or _p includes "=" + certificate is given, frontend uses https
            [ -n "${_certificate}" ] && _frontend_proto="https"
        fi

        # Generating backend sections first
        for _n in ${_nodes}; do
            local _https_opts=""
            if [[ ! "${_skipping_chk}" =~ ^(y|Y) ]]; then
                # Checking if reachable and if HTTPS and H2|HTTP/2 are enabled.
                nc -z ${_n} ${_b_port} || continue
                # NOTE: curl -w '%{http_version}\n' does not work with older curl.
                if [ -n "${_certificate}" ]; then
                    local _https_ver="$(curl -m 1 -sI -k "https://${_n}:${_b_port}/" | sed -nr 's/^HTTP\/([12]).+/\1/p')"
                    if [ "${_https_ver}" == "1" ]; then
                        _https_opts=" ssl crt ${_certificate}"
                        _backend_proto="https"
                    elif [ "${_https_ver}" == "2" ]; then
                        _https_opts=" ssl crt ${_certificate} alpn h2,http/1.1"
                        _backend_proto="https"
                    fi
                    # If backend is using https, make sure front is also https
                    [ -n "${_https_ver}" ] && _frontend_proto="https"
                fi
            else
                # If skipping the check, then certificate is given, populate https options
                [ -n "${_certificate}" ] && _https_opts=" ssl crt ${_certificate}${_https_opts}"
            fi
            echo "  server ${_n} ${_n}:${_b_port}${_https_opts} check inter 5s ${_resolver}" # not using 'cookie' for now.
        done >/tmp/f_haproxy_backends_$$.out

        if [ ! -s /tmp/f_haproxy_backends_$$.out ]; then
            _info "No backend servers found for ${_p} ..."
            continue
        fi

        if [ -s "${_haproxy_custom_cfg_dir%/}/haproxy.${_f_port}.cfg" ]; then
            _info "Found ${_haproxy_custom_cfg_dir%/}/haproxy.${_f_port}.cfg. Appending ..."
            cat "${_haproxy_custom_cfg_dir%/}/haproxy.${_f_port}.cfg" >>"${_cfg}"
            cat /tmp/f_haproxy_backends_$$.out >>"${_cfg}"
            echo "" >>"${_cfg}"
        else
            # If frontend port is already configured somehow (which shouldn't be possible though), skipping
            if ! grep -qE "^frontend frontend_p${_f_port}$" "${_cfg}"; then
                local _frontend_ssl_crt=""
                # NOTE: Enabling HTTP/2 as newer HAProxy supports.
                [ -n "${_certificate}" ] && [ "${_frontend_proto}" = "https" ] && _frontend_ssl_crt=" ssl crt ${_certificate} alpn h2,http/1.1"
                echo "frontend frontend_p${_f_port}
  bind *:${_f_port}${_frontend_ssl_crt}
  reqadd X-Forwarded-Proto:\ ${_frontend_proto}
  default_backend backend_p${_b_port}" >>"${_cfg}"
                echo "" >>"${_cfg}"
            fi

            # If backend port is already configured, not adding as hapxory won't start
            if ! grep -qE "^backend backend_p${_b_port}$" "${_cfg}"; then
                # NOTE: not using 'roundrobin' as I'm not sure if sticky session with cookie is working.
                #       so, also removed 'cookie NXSESSIONID prefix nocache' and 'cookie' from server line
                #       Forgot why I added hash-type consistent, i don't think i need this.
                echo "backend backend_p${_b_port}
  balance first
  #hash-type consistent
  option forwardfor
  http-request set-header X-Forwarded-Port %[dst_port]
  option tcp-check" >>"${_cfg}" # option httpchk OPTIONS /
                #  http-request add-header X-Forwarded-Proto ${_backend_proto}
                cat /tmp/f_haproxy_backends_$$.out >>"${_cfg}"
                echo "" >>"${_cfg}"
            fi
        fi
    done

    # NOTE: May need to configure rsyslog.conf for log if CentOS
    if [ -s /etc/rsyslog.conf ]; then
        _upsert /etc/rsyslog.conf '$ModLoad' 'imudp' "" " "
        _upsert /etc/rsyslog.conf '$UDPServerAddress' '127.0.0.1' "" " "
        _upsert /etc/rsyslog.conf '$UDPServerRun' '514' "" " "
        service rsyslog restart
    fi
    service haproxy reload || return $?
    _info "Installing/Re-configuring HAProxy completed."
}

function f_nfs_server() {
    local __doc__="Install and setup NFS/NFSd on Ubuntu"
    # @see: https://www.digitalocean.com/community/tutorials/how-to-set-up-an-nfs-mount-on-ubuntu-18-04
    #       https://help.ubuntu.com/community/NFSv4Howto
    local _dir="${1:-"/var/tmp/share"}"     # exposing this directory
    local _network="${2:-"172.0.0.0/8"}"    # docker containers only
    local _options="${3:-"rw,sync,no_root_squash,no_subtree_check"}"
    apt-get install nfs-kernel-server nfs-common -y

    if [ -n "${_dir}" ]; then
        if [ ! -d "${_dir}" ]; then
            mkdir -p -m 777 "${_dir%/}" || return $?
        fi
        chown nobody:nogroup "${_dir%/}" || return $?

        if [ -f /etc/exports ]; then
            # Intentionally not using ^
            if ! grep -qE "${_dir%/}\s+" /etc/exports; then
                echo "${_dir%/} ${_network}(${_options}) 127.0.0.1(${_options})" >>/etc/exports || return $?
            fi
        fi
        service nfs-kernel-server restart || return $?
        #exportfs -ra   # to reload /etc/exports without restarting
    fi
    # TODO: RPCNFSDCOUNT=20 on /etc/default/nfs-kernel-server

    # NFS checking commands:
    showmount -e $(hostname)
    #rpcinfo -p `hostname`  # list NFS versions, ports, services but a bit too long
    rpcinfo -s # list NFS information
    #nfsstat -v             # -v = -o all Display Server and Client stats
    #service portmap status

    mkdir -m 777 /mnt/nfs &>/dev/null
    _info "Test:"
    # https://docs.aws.amazon.com/efs/latest/ug/mounting-fs-nfs-mount-settings.html
    # https://www.cyberciti.biz/faq/linux-unix-tuning-nfs-server-client-performance/
    # https://support.sonatype.com/hc/en-us/articles/213465258-Optimizing-Nexus-Disk-IO-Performance
    # NOTE: Trying vers=4.2 automatically falls back to a lower version if not supported
    # TODO: how about ,hard,noacl,proto=tcp,nolock,sync options?
echo '_DIR="/mnt/nfs"
mount -t nfs -vvv -o vers=3,noatime,nodiratime,rsize=1048576,wsize=1048576,timeo=600,retrans=2 '$(hostname)':'${_dir%/}' ${_DIR%/}
mount -t nfs -vvv -o vers=4.2,noatime,nodiratime,rsize=1048576,wsize=1048576,timeo=600,retrans=2 '$(hostname)':'${_dir%/}' ${_DIR%/}
grep -wE "(nfs|nfs4)" /proc/mounts # to check the nfs version
dd if=/dev/zero of=/tmp/test.img bs=33M count=1 oflag=dsync
time (for i in {1..100}; do bash -c "cp -v /tmp/test.img ${_DIR%/}/test_${i}.img && mv -v ${_DIR%/}/test_${i}.img ${_DIR%/}/test_${i}_deleting.img && rm -v -f ${_DIR%/}/test_${i}_deleting.img" & done; wait)
umount -f -l ${_DIR%/}'
    # Somehow Mac requires '-o resvport,rw'
}

function f_s3fs() {
    local __doc__="Install and setup NFS/NFSd on Ubuntu"
    # @see: https://github.com/s3fs-fuse/s3fs-fuse/blob/master/README.md
    local _secret="$1"
    local _bucket="$2"
    local _mnt_dir="$3"
    apt-get install s3fs -y || return $?

    if [ -n "${_secret}" ]; then
        if [ -s "$HOME/.passwd-s3fs" ]; then
            _log "INFO" "$HOME/.passwd-s3fs already exists, so not updating."
        else
            echo "${_secret}" >"$HOME/.passwd-s3fs" || return $?
            chmod 600 "$HOME/.passwd-s3fs" || return $?
        fi
    fi
    [ -z "${_bucket}" ] && return 0
    [ -n "${_mnt_dir}" ] && [ ! -d "${_mnt_dir}" ] && mkdir -p -m 777 "${_mnt_dir}"
    cat <<EOF
# Example mount command:
s3fs ${_bucket} ${_mnt_dir} -o endpoint=ap-southeast-2 \\
  -o cipher_suites=AESGCM,kernel_cache,max_background=1000,max_stat_cache_size=100000,multipart_size=52,parallel_count=30,multireq_max=30 \\
  -o dbglevel=warn
EOF
}

function f_chrome() {
    local __doc__="Install Google Chrome on Ubuntu"
    if ! grep -q "http://dl.google.com" /etc/apt/sources.list.d/google-chrome.list; then
        echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >>/etc/apt/sources.list.d/google-chrome.list || return $?
    fi
    curl -fsSL "https://dl.google.com/linux/linux_signing_key.pub" | apt-key add - || return $?
    apt-get update || return $?
    apt-get install google-chrome-stable -y
}

function f_chrome_remote_desktop() {
    local __doc__="Install Google Chrome Remote Desktop on Ubuntu (TODO: the setup function should be run as non root user but sudo cat doesn't work)"
    local _user="$1"
    # https://ubuntu.com/blog/launch-ubuntu-desktop-on-google-cloud
    # https://bytexd.com/install-chrome-remote-desktop-headless/
    apt-get install wget tasksel -y
    curl -o /tmp/chrome-remote-desktop_current_amd64.deb -L "https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb" || return $?
    apt-get install /tmp/chrome-remote-desktop_current_amd64.deb -y || return $?
    #sudo tasksel install ubuntu-desktop
    if [ ! -s /usr/bin/xfce4-session ]; then
        echo "Please install xfce4 with xscreensaver"
        return $?
    fi
    if [ -n "${_user}" ]; then
        usermod -a -G chrome-remote-desktop ${_user} || return $?
    fi
    bash -c 'echo "exec /etc/X11/Xsession /usr/bin/xfce4-session" > /etc/chrome-remote-desktop-session' || return $?
    #bash -c 'echo "exec /etc/X11/Xsession /usr/bin/gnome-session" > /etc/chrome-remote-desktop-session' || return $?
    if [ ! -f /etc/polkit-1/localauthority.conf.d/02-allow-colord.conf ]; then
        cat << EOF > /etc/polkit-1/localauthority.conf.d/02-allow-colord.conf
polkit.addRule(function(action, subject) {
 if ((action.id == "org.freedesktop.color-manager.create-device" ||
 action.id == "org.freedesktop.color-manager.create-profile" ||
 action.id == "org.freedesktop.color-manager.delete-device" ||
 action.id == "org.freedesktop.color-manager.delete-profile" ||
 action.id == "org.freedesktop.color-manager.modify-device" ||
 action.id == "org.freedesktop.color-manager.modify-profile") &&
 subject.isInGroup("{users}")) {
 return polkit.Result.YES;
 }
});
EOF
    fi
    echo "You might want to reboot, then go to https://remotedesktop.google.com/headless?pli=1 to authorise"
    #sudo systemctl status chrome-remote-desktop@$USER
}

function f_x2go_setup() {
    local __doc__="Install and setup next generation remote desktop X2Go"
    local _user="${1-$USER}"
    local _pass="${2:-"${_user}"}"

    if ! which apt-get &>/dev/null; then
        _warn "No apt-get"
        return 1
    fi

    apt-add-repository ppa:x2go/stable -y || return $?
    apt-get update || return $?
    # GNOME does not work well so installing XFCE
    apt-get install xfce4 xfce4-goodies xscreensaver -y || return $?
    apt-get install x2goserver x2goserver-xsession -y || return $?

    _info "Please install X2Go client from http://wiki.x2go.org/doku.php/doc:installation:x2goclient"

    if ! id -u $_user &>/dev/null; then
        f_useradd "$_user" "$_pass" || return $?
    fi
}

function f_hostname_set() {
    local __doc__="Set hostname"
    local _new_name="$1"
    if [ -z "$_new_name" ]; then
        _error "no hostname"
        return 1
    fi

    local _current="$(cat /etc/hostname)"
    hostname $_new_name
    echo "$_new_name" >/etc/hostname
    sed -i.bak "s/\b${_current}\b/${_new_name}/g" /etc/hosts
    diff /etc/hosts.bak /etc/hosts
}

function f_ip_set() {
    local __doc__="Set IP Address (TODO: Ubuntu 18 only)"
    local _ip_mask="$1" # eg: 192.168.1.31/24
    local _nic="$2" # ensXX
    local _gw="$3"
    if [[ ! "${_ip_mask}" =~ $_IP_RANGE_REGEX ]]; then
        _log "ERROR" "${_ip_mask} is not IP address range."
        return 1
    fi
    if [ -z "${_nic}" ]; then
        _nic="$(netstat -rn | grep ^0.0.0.0 | awk '{print $8}')"
    fi
    if [ -z "${_nic}" ]; then
        _log "ERROR" "No NIC name."
        return 1
    fi
    if [ -z "${_gw}" ] && [[ "${_ip_mask}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\..+ ]]; then
        _gw="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}.1"
    fi
    if [ -z "${_gw}" ]; then
        _log "ERROR" "No Gateway address."
        return 1
    fi

    local _conf_file="$(ls -1tr /etc/netplan/* | tail -n1)"
    if [ -z "${_conf_file}" ]; then
        _log "ERROR" "No netplan config file for updating found."
        return 1
    else
        _backup "${_conf_file}"
    fi

    echo "network:
  version: 2
  renderer: networkd
  ethernets:
    ${_nic}:
     dhcp4: no
     addresses: [${_ip_mask}]
     gateway4: ${_gw}
     nameservers:
       addresses: [1.1.1.1,8.8.8.8,8.8.4.4]
" >${_conf_file} || return $?
    netplan apply #--debug apply
}

function f_socks5_proxy() {
    local __doc__="Start Socks5 proxy (for websocket)"
    local _port="${1:-$((${r_PROXY_PORT:-28080} + 1))}" # 28081
    local _cmd="autossh -4gC2TxnNf -D${_port} socks5user@localhost &> /tmp/ssh_socks5.out"

    apt-get install -y autossh || return $?
    if [ ! -s $HOME/.ssh/id_rsa ]; then
        f_ssh_setup || return $?
    fi
    f_useradd "socks5user" "socks5user" "Y" || return $?
    _info "Testing 'socks5user' user's ssh log in (should not ask password)..."
    ssh -o StrictHostKeyChecking=no socks5user@localhost id || return $?

    touch /tmp/ssh_socks5.out
    chmod 777 /tmp/ssh_socks5.out
    [[ "${_port}" =~ ^[0-9]+$ ]] || return 11
    [ ! -s /etc/rc.lcoal ] && echo -e '#!/bin/bash\nexit 0' >/etc/rc.local
    _insert_line /etc/rc.local "${_cmd}" "exit 0"
    lsof -nPi:${_port} -s TCP:LISTEN | grep "^ssh" && return 0
    eval "${_cmd}"
}

function f_squid_proxy() {
    local _port="${1:-28082}"
    local _conf="/etc/squid/squid.conf"
    apt-get install squid -y || return $?
    _backup ${_conf} || return $?
    cat <<EOF >${_conf}
acl docker dst 172.17.0.0/16
acl docker dst 172.18.0.0/16
http_access allow docker
forwarded_for delete
http_port 0.0.0.0:${_port}
EOF
    service squid restart
}

function _apache_install() {
    # NOTE: how to check loaded modules: apache2ctl -M and/or check mods-available/ and mods-enabled/
    apt-get install -y apache2 apache2-utils || return $?
    apt-get install -y php libapache2-mod-php
    # https://www.cyberciti.biz/faq/apache-mod_dumpio-log-post-data/
    #a2enmod dump_io || return $?   # To log request headers but may log too much
    a2enmod proxy proxy_http proxy_connect proxy_wstunnel cache cache_disk ssl || return $?
    apt-get install -y libapache2-mod-auth-kerb || return $?
    a2enmod headers rewrite auth_kerb || return $?
    service apache2 restart || return $? # Disabling proxy_connect needed restart, so just in case restarting
    apachectl -t -D DUMP_VHOSTS
}

function f_apache_proxy() {
    local __doc__="Setup content cache proxy. @see:https://www.digitalocean.com/community/tutorials/how-to-configure-apache-content-caching-on-ubuntu-14-04#standard-http-caching"
    local _proxy_dir="/var/www/proxy"
    local _conf="/etc/apache2/sites-available/proxy.conf"
    local _port="${r_PROXY_PORT:-28080}"
    # NOTE: to disable weak TLS/SSL versions, edit /etc/apache2/mods-available/ssl.conf with:
    #SSLProtocol all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
    # NOTE: To configure docker to use proxy: https://medium.com/@airman604/getting-docker-to-work-with-a-proxy-server-fadec841194e
    # systemctl show --property=Environment docker
    # NOTE: To configure java to use proxy (https://docs.oracle.com/javase/6/docs/technotes/guides/net/proxies.html)
    # -Dhttp.proxyHost=192.168.1.31 -Dhttp.proxyPort=28080 -Dhttp.proxyUser=proxyuser -Dhttp.proxyPassword=proxypwd

    # TODO: 777...
    [ ! -d "${_proxy_dir}" ] && mkdir -p -m 777 "${_proxy_dir}"
    #[ ! -d "${_cache_dir}" ] && mkdir -p -m 777 "${_cache_dir}"

    if [ -s "${_conf}" ]; then
        _info "${_conf} already exists. Skipping..."
        return 0
    fi

    _apache_install || return $?
    grep -qi "^Listen ${_port}" /etc/apache2/ports.conf || echo "Listen ${_port}" >>/etc/apache2/ports.conf

    echo "<VirtualHost *:${_port}>
    DocumentRoot ${_proxy_dir}
    LogLevel warn
    ErrorLog \${APACHE_LOG_DIR}/proxy_error.log
    CustomLog \${APACHE_LOG_DIR}/proxy_access.log combined
    # NOTE: Log request headers (but too much information)
    #DumpIOInput On
    #DumpIOOutput On
    #LogLevel dumpio:trace7" >"${_conf}"

    if ! grep -qE '^proxyuser:' /etc/apache2/passwd-nospecial; then
        echo -n 'proxypwd' | htpasswd -i -c /etc/apache2/passwd-nospecial proxyuser
    fi
    echo "
    <Directory ${_proxy_dir}>
        Options +Indexes +FollowSymLinks -SymLinksIfOwnerMatch
        AllowOverride None
        Order allow,deny
        Allow from all
        AuthType Basic
        AuthName \"Basic Auth test\"
        AuthUserFile /etc/apache2/passwd-nospecial
        Require valid-user
    </Directory>

    SSLProxyEngine On
    SSLProxyVerify none
    SSLProxyCheckPeerCN off
    SSLProxyCheckPeerName off
    SSLProxyCheckPeerExpire off

    ProxyRequests On
    AllowCONNECT 443 1025-60000
    <Proxy *>
        Order deny,allow
        Allow from all
        AddDefaultCharset off
        # NOTE: Use below to test authentication
        #AuthType Basic
        #AuthName 'Authentication Required'
        #AuthUserFile /etc/apache2/passwd-nospecial
        #Require user proxyuser
        #Require valid-user
    </Proxy>
    ProxyVia On

    #<IfModule mod_cache_disk.c>
    # NOTE: changing CacheRoot may require to change HTCACHECLEAN_PATH
    CacheRoot /var/cache/apache2/mod_cache_disk
    CacheDirLevels 2
    CacheDirLength 1
    CacheMaxFileSize 536870912
    CacheMinFileSize 1024
    CacheIgnoreCacheControl On
    CacheEnable disk /
    CacheEnable disk http://
    CacheEnable disk https://
    #</IfModule>
</VirtualHost>" >>"${_conf}"

    a2ensite proxy || return $?
    # Due to 'ssl' module, using restart rather than reload
    _info "reloading ..."
    service apache2 reload || return $?
    echo "# Example commands to mount cache dir:
service apache2 stop
rm -rf /var/cache/apache2/mod_cache_disk/*
sshfs -o allow_other,uid=0,gid=0,umask=000,reconnect,follow_symlinks USER@REMOTE-HOST:/apache2/cache /var/cache/apache2/mod_cache_disk
service apache2 start"
}

function f_apache_reverse_proxy() {
    local __doc__="Generate reverse proxy.conf *per* port, and restart reload"
    # f_apache_reverse_proxy "http://node-nxiq.standalone.localdomain:8070" 18070 "dh1.standalone.localdomain" /etc/security/keytabs/HTTP.service.keytab
    # f_apache_reverse_proxy "http://node-nxrm-ha1.standalone.localdomain:8081" 18081 "dh1.standalone.localdomain" /etc/security/keytabs/HTTP.service.keytab
    # @see: https://help.sonatype.com/display/NXRM3/Run+Behind+a+Reverse+Proxy
    #       https://guides.sonatype.com/repo3/technical-guides/pki-auth/
    #       https://sites.google.com/site/mrxpalmeiras/notes/configuring-splunk-with-kerberos-sso-via-apache-reverse-proxy
    local _redirect="${1}" # http://hostname:port/path
    local _port="${2}"
    local _sever_host="${3:-$(hostname -f)}"
    local _keytab_file="${4}" # /etc/security/keytabs/HTTP.service.keytab
    local _ssl_ca_file="${5}" # /var/tmp/share/cert/rootCA_standalone.crt

    if [ -z "${_port}" ]; then
        if [[ "${_redirect}" =~ .+:([0-9]+)[/]?.* ]]; then
            _port="${BASH_REMATCH[1]}"
            _info "No port given, so using ${_port} ..."
        else
            _error "No port given"
            return 1
        fi
    fi
    if netstat -ltnp | grep -E ":${_port}\s+" | grep -v apache2; then
        _error "Port ${_port} might be in use."
        return 1
    fi

    local _conf="/etc/apache2/sites-available/rproxy${_port}.conf"
    if [ -s ${_conf} ]; then
        _info "${_conf} already exists. Skipping..."
        return 0
    fi

    _apache_install || return $?
    grep -qi "^Listen ${_port}" /etc/apache2/ports.conf || echo "Listen ${_port}" >>/etc/apache2/ports.conf

    # Common settings
    echo "<VirtualHost *:${_port}>
    ServerName ${_sever_host}
    AllowEncodedSlashes NoDecode
    LogLevel Debug
    ErrorLog \${APACHE_LOG_DIR}/proxy_error_${_port}.log
    CustomLog \${APACHE_LOG_DIR}/proxy_access_${_port}.log combined
    <Proxy *>
        Order allow,deny
        Allow from all
    </Proxy>
" >${_conf}

    # Proxy/Reverse Proxy related settings
    if [ -n "${_redirect%/}" ]; then
        echo "
    #connectiontimeout=5 timeout=90 retry=0
    ProxyPass / ${_redirect%/}/ nocanon
    ProxyPassReverse / ${_redirect%/}/
    #ProxyRequests Off
    #ProxyPreserveHost On
" >>${_conf}
    else
        local _proxy_dir="/var/www/proxy"
        [ ! -d "${_proxy_dir}" ] && mkdir -p -m 777 "${_proxy_dir}"
        echo "
    DocumentRoot ${_proxy_dir}
" >>${_conf}
    fi

    # If this apache uses https (if server.key and cert exists)
    if [ -s /etc/apache2/ssl/server.key ]; then
        echo "
    SSLEngine on
    SSLCertificateFile /etc/apache2/ssl/server.crt
    SSLCertificateKeyFile /etc/apache2/ssl/server.key
    RequestHeader set X-Forwarded-Proto https
" >>${_conf}
    fi

    if [ -n "${_keytab_file}" ] && [ ! -s "${_keytab_file}" ]; then
        _log "INFO" "No HTTP keytab: ${_keytab_file}"
        echo "    kadmin -p admin@\${_realm} -q 'add_principal -randkey HTTP/${_sever_host}'
    kadmin -p admin@\${_realm} -q "xst -k ${_keytab_file} HTTP/$(hostname -f)"
    # If freeIPA, after adding host and service from UI, 'kinit admin':
    ipa-getkeytab -s node-freeipa.standalone.localdomain -p \"HTTP/${_sever_host}\" -k ${_keytab_file}
    chmod a+r ${_keytab_file}"
    elif [ -s "${_keytab_file}" ]; then
        # http://www.microhowto.info/howto/configure_apache_to_use_kerberos_authentication.html
        #local _realm="`sed -n -e 's/^ *default_realm *= *\b\(.\+\)\b/\1/p' /etc/krb5.conf`"
        local _realm="$(klist -kt ${_keytab_file} | grep -m1 -oP '@.+' | sed 's/@//')"
        echo "    <Location \"/\">
        AuthType Kerberos
        AuthName \"SPNEGO Login\"
        KrbAuthRealms ${_realm}
        KrbServiceName HTTP/${_sever_host}@${_realm}
        Krb5KeyTab ${_keytab_file}
        KrbMethodK5Passwd On
        KrbSaveCredentials On
        #KrbMethodNegotiate On
        #KrbLocalUserMapping On
        require valid-user

        RewriteEngine On
        # Removing chars after / and @
        RewriteCond %{LA-U:REMOTE_USER} (^[^/@]+)
        # Assigning above into RU
        RewriteRule . - [E=RU:%1]
        RequestHeader set REMOTE_USER %{RU}e
    </location>
" >>${_conf}
        # @see: https://httpd.apache.org/docs/2.4/rewrite/intro.html & https://httpd.apache.org/docs/2.4/rewrite/flags.html
    fi

    # 2-way SSL | Client Certificate Authentication
    # TODO: Get username and integ with LDAP https://stackoverflow.com/questions/7635380/apache-ssl-client-certificate-ldap-authorizations
    if [ -s "${_ssl_ca_file}" ]; then
        chown www-data: ${_ssl_ca_file}
        echo "
    SSLProxyEngine On
    SSLProxyVerify none
    SSLProxyCheckPeerCN off
    SSLProxyCheckPeerName off
    #SSLProxyCheckPeerExpire off

    SSLOptions +StdEnvVars
    SSLVerifyClient require
    SSLVerifyDepth 10
    SSLCACertificateFile ${_ssl_ca_file}
    # set header to upstream, SSL_CLIENT_S_DN_CN can change to use other identifiers
    RequestHeader set REMOTE_USER \"%{SSL_CLIENT_S_DN_CN}s\"
" >>${_conf}
    fi

    echo "</VirtualHost>" >>${_conf}

    a2ensite rproxy${_port} || return $?
    # Due to 'ssl' module, using restart rather than reload
    _info "reloading ..."
    service apache2 reload
}

function f_apache_kdcproxy() {
    local __doc__="Generate proxy.conf for KdcPorxy"
    local _port="${1}"
    local _sever_host="${2:-$(hostname -f)}"
    # @see https://www.dragonsreach.it/2014/10/24/kerberos-over-http-on-a-firewalled-network/

    if netstat -ltnp | grep -E ":${_port}\s+" | grep -v apache2; then
        _error "Port ${_port} might be in use."
        return 1
    fi

    local _conf="/etc/apache2/sites-available/rproxy${_port}.conf"
    if [ -s ${_conf} ]; then
        _info "${_conf} already exists. Skipping..."
        return 0
    fi

    # How to check loaded modules: apache2ctl -M and/or check mods-available/ and mods-enabled/
    apt-get install -y apache2 apache2-utils python-kdcproxy libapache2-mod-wsgi || return $?
    a2enmod proxy headers proxy_http proxy_connect proxy_wstunnel ssl rewrite wsgi || return $?

    grep -qi "^Listen ${_port}" /etc/apache2/ports.conf || echo "Listen ${_port}" >>/etc/apache2/ports.conf

    # Common settings
    echo "<VirtualHost *:${_port}>
    ServerName ${_sever_host}
    AllowEncodedSlashes NoDecode
    LogLevel Debug
    ErrorLog \${APACHE_LOG_DIR}/proxy_error_${_port}.log
    CustomLog \${APACHE_LOG_DIR}/proxy_access_${_port}.log combined
    <Proxy *>
        Order allow,deny
        Allow from all
    </Proxy>
" >${_conf}

    # If this apache uses https (if server.key and cert exists)
    local _proto="https"
    if [ ! -s /etc/apache2/ssl/server.key ]; then
        _warn "No /etc/apache2/ssl/server.key (= no https)"
        _proto="http"
    else
        echo "
    SSLEngine on
    SSLCertificateFile /etc/apache2/ssl/server.crt
    SSLCertificateKeyFile /etc/apache2/ssl/server.key
" >>${_conf}
    fi

    local _kdcproxy_dir="/usr/lib/python2.7/dist-packages/kdcproxy"
    if [ ! -s ${_kdcproxy_dir%/}/__init__.py ]; then
        _error "${_kdcproxy_dir%/}/__init__.py does not exists."
        return 1
    fi
    echo "    WSGIDaemonProcess kdcproxy processes=2 threads=15 maximum-requests=1000 display-name=%{GROUP}
    WSGIImportScript ${_kdcproxy_dir%/}/__init__.py process-group=kdcproxy application-group=kdcproxy
    WSGIScriptAlias /KdcProxy ${_kdcproxy_dir%/}/__init__.py
    WSGIScriptReloading Off

    <Location \"/\">
        Satisfy Any
        Order Deny,Allow
        Allow from all
        WSGIProcessGroup kdcproxy
        WSGIApplicationGroup kdcproxy
    </Location>
" >>${_conf}
    echo "</VirtualHost>" >>${_conf}

    a2ensite rproxy${_port} || return $?
    # Due to 'ssl' module, using restart rather than reload
    _info "reloading ..."
    service apache2 reload || return $?
    echo "Completed! Add below in the kdc5.conf:
  kdc = ${_proto}://${_sever_host}:${_port}/
  kpasswd_server = ${_proto}://${_sever_host}:${_port}/"
}

function f_ssh_setup() {
    local __doc__="Create a private/public keys and setup authorized_keys ssh config & permissions on host"
    which ssh-keygen &>/dev/null || return $?

    if [ ! -e $HOME/.ssh/id_rsa ]; then
        ssh-keygen -f $HOME/.ssh/id_rsa -q -N "" || return 11
    fi

    if [ ! -e $HOME/.ssh/id_rsa.pub ]; then
        ssh-keygen -y -f $HOME/.ssh/id_rsa >$HOME/.ssh/id_rsa.pub || return 12
    fi

    _key="$(cat $HOME/.ssh/id_rsa.pub | awk '{print $2}')"
    grep "$_key" $HOME/.ssh/authorized_keys &>/dev/null
    if [ $? -ne 0 ]; then
        cat $HOME/.ssh/id_rsa.pub >>$HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys
        [ $? -ne 0 ] && return 13
    fi

    if [ ! -e $HOME/.ssh/config ]; then
        echo "Host node* *.localdomain
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
  User root" >$HOME/.ssh/config
    fi

    # If current user isn't 'root', copy this user's ssh keys to root
    if [ ! -e /root/.ssh/id_rsa ]; then
        mkdir /root/.ssh &>/dev/null
        cp $HOME/.ssh/id_rsa /root/.ssh/id_rsa
        chmod 600 /root/.ssh/id_rsa
        chown -R root:root /root/.ssh
    fi

    # To make 'ssh root@localhost' work
    grep -q "^$(cat $HOME/.ssh/id_rsa.pub)" /root/.ssh/authorized_keys || echo "$(cat $HOME/.ssh/id_rsa.pub)" >>/root/.ssh/authorized_keys

    if [ -d ${_WORK_DIR%/} ] && [ ! -f ${_WORK_DIR%/}/.ssh/authorized_keys ]; then
        [ ! -d ${_WORK_DIR%/}/.ssh ] && mkdir -m 700 ${_WORK_DIR%/}/.ssh
        ln -s /root/.ssh/authorized_keys ${_WORK_DIR%/}/.ssh/authorized_keys
    fi
}

function f_virtualbox() {
    local __doc__="Install the latest virtualbox from https://www.virtualbox.org/wiki/Linux_Downloads"
    #apt-get autoremove 'virtualbox*'
    curl -fsSL https://www.virtualbox.org/download/oracle_vbox_2016.asc | sudo apt-key add - || return $?
    add-apt-repository "deb [arch=amd64] https://download.virtualbox.org/virtualbox/debian $(lsb_release -cs) contrib" || return $?
    sudo apt-get update && sudo apt-get install virtualbox-6.1 -y
}

function f_docker_setup() {
    local __doc__="Install docker (if not yet) and customise for HDP test environment (TODO: Ubuntu only)"
    # https://docs.docker.com/install/linux/docker-ce/ubuntu/

    if ! which apt-get &>/dev/null; then
        _warn "No apt-get"
        return 1
    fi

    if which docker | grep -qw snap; then
        _warn "'docker' might be installed from 'snap'. Please remove with 'snap remove docker'"
        return 1
    fi

    if ! which docker &>/dev/null; then
        apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common || return $?
        # if Ubuntu 18
        if grep -qiP 'Ubuntu (18|20)\.' /etc/issue.net; then
            apt-get remove -y docker docker-engine docker.io containerd runc
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
            #apt-key fingerprint 0EBFCD88 || return $?  # probably no longer needed?
            add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
            apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io
        else
            # Old (14.04 and 16.04) way (TODO: apt.dockerproject.org no longer works)
            apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D || _info "Did not add key for docker"
            grep -q "deb https://apt.dockerproject.org/repo" /etc/apt/sources.list.d/docker.list || echo "deb https://apt.dockerproject.org/repo ubuntu-$(cat /etc/lsb-release | grep CODENAME | cut -d= -f2) main" >>/etc/apt/sources.list.d/docker.list
            apt-get update && apt-get purge lxc-docker*
            apt-get install docker-engine -y
        fi
    fi

    # commenting below as newer docker wouldn't need this and docker info sometimes takes time
    #local _storage_size="30G"
    # This part is different by docker version, so changing only if it was 10GB or 1*.**GB
    #docker info 2>/dev/null | grep 'Base Device Size' | grep -owP '1\d\.\d\dGB' &>/dev/null
    #if [ $? -eq 0 ]; then
    #    grep 'storage-opt dm.basesize=' /etc/init/docker.conf &>/dev/null
    #    if [ $? -ne 0 ]; then
    #        sed -i.bak -e 's/DOCKER_OPTS=$/DOCKER_OPTS=\"--storage-opt dm.basesize='${_storage_size}'\"/' /etc/init/docker.conf
    #        _warn "Restarting docker (will stop all containers)..."
    #        sleep 3
    #        service docker restart
    #    else
    #        _warn "storage-opt dm.basesize=${_storage_size} is already set in /etc/init/docker.conf"
    #    fi
    #fi

    if [ ! -f /etc/iptables.up.rules ]; then
        _info "Updating iptables to accept all ..."
        # @see: https://github.com/davesteele/comitup/issues/57
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        iptables -t nat -F
        iptables -t mangle -F
        iptables -F
        iptables -X
        iptables-save >/etc/iptables.up.rules
        #which docker &>/dev/null && service docker restart
    fi
}

function f_minikube4kvm() {
    local __doc__="Install minikube (kubernetes|k8s) for KVM"
    # @see: https://computingforgeeks.com/how-to-run-minikube-on-kvm/
    local _user="${1:-"virtuser"}"  # NOTE: expecting this user is already created
    apt-get install apt-transport-https -y
    curl -fL -o /usr/local/bin/minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 || return $?
    chmod a+x /usr/local/bin/minikube
    /usr/local/bin/minikube version || return $?
    curl -fL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" || return $?
    chmod a+x /usr/local/bin/kubectl
    /usr/local/bin/kubectl version -o json  # not checking return code as if no 8080, it returns 1

    usermod -aG libvirt ${_user}
    #newgrp libvirt
    sudo -i -u ${_user} minikube config set vm-driver kvm2 || return $?
    sudo -i -u ${_user} minikube start || return $?
    curl -k https://$(minikube ip):8443/livez?verbose   # health check
    _info "May want to move below file(s) to a faster drive."
    sudo -i -u ${_user} bash -c 'ls -l ${HOME%/}/.minikube/machines/minikube/*.rawdisk'
    sudo -i -u ${_user} kubectl config view
    _info "May want to set up Port-forwarding k8s API requests to minikube's host-only network IP:8443."
    echo "ssh-keygen -f /home/${_user}/.ssh/known_hosts -R \$(minikube ip)"
    echo "ssh -2CNnqTxfg -D38081 -i /home/${_user}/.minikube/machines/minikube/id_rsa docker@\$(minikube ip) -L 38443:localhost:8443"   # -o StrictHostKeyChecking=no
}

function f_microk8s() {
    local __doc__="Install microk8s (kubernetes|k8s) (TODO: Ubuntu only)"
    # @see: https://ubuntu.com/tutorials/install-a-local-kubernetes-with-microk8s#1-overview
    local dashboard=""  # change to "dashboard" to use dashboard
    snap install microk8s --classic || return $?
    #if ! type kubectl &>/dev/null && [ ! -f /etc/profile.d/microk8s.sh ]; then
    #    echo 'alias kubectl="microk8s kubectl"' > /etc/profile.d/microk8s.sh
    #    echo 'alias helm3="microk8s helm3"' >> /etc/profile.d/microk8s.sh
    #fi
    # https://stackoverflow.com/questions/63803171/how-to-change-microk8s-kubernetes-storage-location
    # edit /var/snap/microk8s/current/args/containerd

    ufw allow in on cni0 && ufw allow out on cni0
    ufw default allow routed
    # surprisingly ingress seems to work without coredns
    microk8s enable storage helm3 ingress ${dashboard} # dns dashboard metallb prometheus
    echo "To replace nginx SSL/HTTPS certificate
    microk8s kubectl -n ingress create secret tls standalone.localdomain --key /var/tmp/share/cert/standalone.localdomain.key --cert /var/tmp/share/cert/standalone.localdomain.crt
    microk8s kubectl edit -n ingress daemonsets nginx-ingress-microk8s-controller
    # then add below line in the containers.args:
    #        - '--default-ssl-certificate=ingress/standalone.localdomain'
    "
    microk8s.start || return $?

    # (a kind of) test
    microk8s kubectl get all --all-namespaces || return $?
    # If works update firewall. at this moment, only for ufw
    if type ufw &>/dev/null; then
        ufw allow in on vxlan.calico || return $?
        ufw allow out on vxlan.calico || return $?
        ufw default allow routed || return $?
    fi

    # output token if dashboard is enabled
    if [ -n "${dashboard}" ]; then
        microk8s kubectl -n kube-system describe secret $(microk8s kubectl -n kube-system get secret | grep -oP '^default-token[^ ]+')
        # Replace the dashboard certificate
        if [ -s /var/tmp/share/cert/standalone.localdomain.key ]; then
            microk8s kubectl -n kube-system delete secret kubernetes-dashboard-certs || return $?
            cd /var/tmp/share/cert/ || return $?
            microk8s kubectl -n kube-system create secret generic kubernetes-dashboard-certs --from-file=standalone.localdomain.crt --from-file=standalone.localdomain.key
            cd -
            echo "microk8s kubectl -n kube-system edit deploy kubernetes-dashboard -o yaml
    # Then, append below lines after '- args:'
            - --tls-cert-file=/standalone.localdomain.crt
            - --tls-key-file=/standalone.localdomain.key"

            local _dboard_ip="$(microk8s kubectl -n kube-system get service kubernetes-dashboard -ojson | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a['spec']['clusterIP'])")"
            if [ -z "${_dboard_ip}" ] || [ ! -s /var/tmp/share/sonatype/utils.sh ]; then
                _info "Update /etc/hosts or equivalent file for ${_dboard_ip}"
            else
                source /var/tmp/share/sonatype/utils.sh
                local _host_file=/etc/hosts
                [ -f /etc/banner_add_hosts ] && _host_file=/etc/banner_add_hosts
                _update_hosts_file k8sboard.standalone.localdomain ${_dboard_ip} ${_host_file}
            fi
        fi
    fi

    # Image location
    ls -l /var/snap/microk8s/common/var/lib/containerd/

    echo "# Command examples:
    microk8s status --wait-ready    # list enabled/disabled addons
    microk8s config     # to output the config
    microk8s inspect    # Very helpful troubleshooting command, generates a report
    microk8s kubectl run -n <namespace> -it --rm --restart=Never busybox --image=gcr.io/google-containers/busybox sh    # Start a pod for troubleshooting

    microk8s helm3 repo add nxrm3 http://dh1.standalone.localdomain:8081/repository/helm-proxy/
    microk8s helm3 search repo iq
    # after creating the namespace 'sonatype'
    microk8s helm3 install --debug nxiq helm-sonatype-proxy/nexus-iq-server -n sonatype -f ./helm-iq-values.yml
    microk8s helm3 install --debug nxrm3 helm-sonatype-proxy/nexus-repository-manager -n sonatype
    microk8s helm3 uninstall nxrm3     # to delete everything

    microk8s kubectl config get-contexts    # list available kubectl configs
    microk8s kubectl cluster-info #dump
    microk8s kubectl create -f your_deployment.yml
    microk8s kubectl get services          # or all, or deployments to check the NAME
    microk8s kubectl get deploy <deployment-name> -o yaml   # to export the deployment yaml
    microk8s kubectl expose deployment <deployment-name> --type=LoadBalancer --port=8081
    microk8s kubectl port-forward --address 0.0.0.0 <pod-name> 18081:8081 & # this command runs in foreground
    microk8s kubectl get pods              # get a pod name to login
    microk8s kubectl logs <pod-name>       # --previous
    microk8s kubectl describe pod <pod-name>    # shows Events
    microk8s kubectl describe pvc <pvc-name>
    microk8s kubectl exec <pod-name> -ti -- bash
    microk8s kubectl scale --replicas=0 deployment <deployment-name>    # stop all pods temporarily (if no HPA)

    # Ingress troubleshooting: https://kubernetes.github.io/ingress-nginx/troubleshooting/
    microk8s kubectl exec -it -n ingress nginx-ingress-microk8s-controller-xb9qh -- cat /etc/nginx/nginx.conf

    microk8s stop
    #systemctl stop snap.microk8s.daemon-containerd.service
    #systemctl stop snap.microk8s.daemon-scheduler.service
    #systemctl stop snap.microk8s.daemon-apiserver.service
    #systemctl stop snap.microk8s.daemon-controller-manager.service
    #systemctl stop snap.microk8s.daemon-proxy.service
"
}

function f_vnc_setup() {
    local __doc__="Install X and VNC Server. NOTE: this may use about 400MB space"
    # https://www.digitalocean.com/community/tutorials/how-to-install-and-configure-vnc-on-ubuntu-16-04
    local _user="${1:-vncuser}"
    local _vpass="${2:-${_user}}"
    local _pass="${3:-${_user}}"
    local _portXX="${4:-"10"}"
    local _install_xfce="$5"

    if ! which apt-get &>/dev/null; then
        _warn "No apt-get"
        return 1
    fi

    if ! id -u $_user &>/dev/null; then
        f_useradd "$_user" "$_pass" || return $?
    fi

    if [[ "${_install_xfce}" =~ ^(y|Y) ]]; then
        apt-get install xfce4 xfce4-goodies xscreensaver -y || return $?
    fi
    #f_chrome
    #apt-get install -y tightvncserver autocutsel || return $?
    apt-get install -y tigervnc-standalone-server || return $?

    # TODO: also disable screensaver and sleep (eg: /home/hajime/.xscreensaver)
    su - $_user -c 'expect <<EOF
spawn "vncpasswd"
expect "Password:"
send "'${_vpass}'\r"
expect "Verify:"
send "'${_vpass}'\r"
expect "Would you like to enter a view-only password (y/n)?"
send "n\r"
expect eof
exit
EOF
mv ${HOME%/}/.vnc/xstartup ${HOME%/}/.vnc/xstartup.bak &>/dev/null
echo "#!/bin/bash
xrdb ${HOME%/}/.Xresources
autocutsel -fork
startxfce4 &" > ${HOME%/}/.vnc/xstartup
chmod u+x ${HOME%/}/.vnc/xstartup'

    local _host_ip="$(hostname -I | cut -d" " -f1)"
    #echo "TightVNC client: https://www.tightvnc.com/download.php"
    # NOTE: -depth 16 does not work any more?
    echo "START VNC:
    su - $_user -c 'vncserver -localhost no -geometry 1600x960 :${_portXX}'
    NOTE: Please disable Screensaver from Settings.

STOP VNC:
    su - $_user -c 'vncserver -kill :${_portXX}'

ACCESS VNC:
    vnc://${_user}:${_vpass}@${_host_ip}:59${_portXX}
"
}

function f_useradd() {
    local __doc__="Add user on *Host*"
    local _user="$1"
    local _pwd="${2:-"${_user}123"}"
    local _copy_ssh_config="$3"

    [ -z "${_user}" ] && return 1
    if id -u ${_user} &>/dev/null; then
        _info "${_user} already exists. Skipping useradd command..."
    else
        # should specify home directory just in case?
        useradd -d "/home/${_user}/" -s "$(which bash)" -p "$(echo "${_pwd}" | openssl passwd -1 -stdin)" "${_user}"
        mkdir "/home/${_user}/" && chown "${_user}":"${_user}" "/home/${_user}/"
    fi

    if _isYes "$_copy_ssh_config"; then
        if [ ! -f ${HOME%/}/.ssh/id_rsa ]; then
            _error "${HOME%/}/.ssh/id_rsa does not exist. Not copying ssh configs ..."
            return 1
        fi

        if [ ! -d "/home/${_user}/" ]; then
            _error "No /home/${_user}/ . Not copying ssh configs ..."
            return 1
        fi

        if [ ! -d "/home/${_user}/.ssh" ]; then
            sudo -u ${_user} mkdir "/home/${_user}/.ssh" || return $?
        fi
        if [ ! -s "/home/${_user}/.ssh/id_rsa" ]; then
            #cp ${HOME%/}/.ssh/id_rsa* "/home/${_user}/.ssh/"
            sudo -u ${_user} ssh-keygen -f /home/${_user}/.ssh/id_rsa -q -N ""
            #chmod 600 "/home/${_user}/.ssh/id_rsa"
        fi
        # Copy (overwrite) same config and authorized keys if doesn't exist
        [ -s "${HOME%/}/.ssh/config" ] && cp -f -v ${HOME%/}/.ssh/config "/home/${_user}/.ssh/"
        [ -s "${HOME%/}/.ssh/authorized_keys" ] && cp -f -v  ${HOME%/}/.ssh/authorized_keys "/home/${_user}/.ssh/"
        chown -R "${_user}":"${_user}" /home/${_user}/.ssh
    fi
}

function f_dnsmasq() {
    local __doc__="Install and set up dnsmasq"
    local _how_many="${1-$r_NUM_NODES}"
    local _start_from="${2-$r_NODE_START_NUM}"
    local _domain_suffix="${3:-${g_DOMAIN_SUFFIX:-".localdomian"}}"

    # If Ubuntu 18.04 or 20.04 may want to stop systemd-resolved
    if grep -qiP 'Ubuntu (18|20)\.' /etc/issue.net; then
        sudo systemctl stop systemd-resolved
        sudo systemctl disable systemd-resolved
    fi
    apt-get -y install dnsmasq || return $?

    # For Ubuntu 18.04 name resolution slowness (ssh and sudo too).
    # Also local hostname needs to be resolved @see: https://linuxize.com/post/how-to-change-hostname-on-ubuntu-18-04/
    grep -q '^no-resolv' /etc/dnsmasq.conf || echo 'no-resolv' >>/etc/dnsmasq.conf
    # I might use 8.8.8.8
    grep -q '^server=' /etc/dnsmasq.conf || echo 'server=1.1.1.1' >>/etc/dnsmasq.conf
    #grep -q '^domain-needed' /etc/dnsmasq.conf || echo 'domain-needed' >> /etc/dnsmasq.conf
    #grep -q '^bogus-priv' /etc/dnsmasq.conf || echo 'bogus-priv' >> /etc/dnsmasq.conf
    grep -q '^local=' /etc/dnsmasq.conf || echo 'local=/'${_domain_suffix#.}'/' >>/etc/dnsmasq.conf
    #grep -q '^expand-hosts' /etc/dnsmasq.conf || echo 'expand-hosts' >> /etc/dnsmasq.conf
    #grep -q '^domain=' /etc/dnsmasq.conf || echo 'domain='${_domain_suffix#.} >> /etc/dnsmasq.conf
    grep -q '^addn-hosts=' /etc/dnsmasq.conf || echo 'addn-hosts=/etc/banner_add_hosts' >>/etc/dnsmasq.conf
    grep -q '^resolv-file=' /etc/dnsmasq.conf || (
        echo 'resolv-file=/etc/resolv.dnsmasq.conf' >>/etc/dnsmasq.conf
        echo 'nameserver 1.1.1.1' >/etc/resolv.dnsmasq.conf
    )
    #if [ -d "/etc/resolvconf/resolv.conf.d" ] && [ ! -f "/etc/resolvconf/resolv.conf.d/tail" ]; then
    #    echo "nameserver 127.0.0.1" > /etc/resolvconf/resolv.conf.d/tail
    #fi
    _warn "You might need to edit /etc/resolv.conf to add 'nameserver 127.0.0.1'"

    touch /etc/banner_add_hosts || return $?
    chmod 664 /etc/banner_add_hosts
    which docker &>/dev/null && chown root:docker /etc/banner_add_hosts

    if [ -n "$_how_many" ]; then
        f_dnsmasq_banner_reset "$_how_many" "$_start_from" || return $?
    fi

    # Without below, DNS (resolv.conf) in containers will be 8.8.8.8
    if [ -d /etc/docker ] && [ ! -s /etc/docker/daemon.json ]; then
        local _docker_bridge_net="$(docker inspect bridge | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['IPAM']['Config'][0]['Subnet'])" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')"
        local _daemon_json=""
        #_daemon_json="${_daemon_json%,},\n\"hosts\": [\"tcp://0.0.0.0:2375\", \"unix:///var/run/docker.sock\"]"
        if [ -n "${_docker_bridge_net}" ]; then
            _daemon_json="${_daemon_json%,},\n\"dns\": [\"${_docker_bridge_net}.1\", \"1.1.1.1\"]"
        fi
        echo -e "{${_daemon_json}\n}" > /etc/docker/daemon.json
        _warn "daemon.json updated. 'systemctl daemon-reload && service docker restart' required"
        #mkdir -p /etc/systemd/system/docker.service.d
        #echo -e '[Service]\nExecStart=\nExecStart=/usr/bin/dockerd' > /etc/systemd/system/docker.service.d/override.conf
        #_warn "Port 2375 is exposed. 'systemctl daemon-reload && service docker restart' required"
        # TODO: also add live-restore https://docs.docker.com/config/containers/live-restore/
    fi

    # @see https://bugs.launchpad.net/ubuntu/+source/systemd/+bug/1624320
    if [ -L /etc/resolv.conf ] && grep -qE '^nameserver\s+127.0.0.53' /etc/resolv.conf; then
        if grep -qE '^nameserver\s+127.0.0.1' /run/resolvconf/resolv.conf; then
            rm -f /etc/resolv.conf
            ln -s /run/resolvconf/resolv.conf /etc/resolv.conf
        else
            systemctl disable systemd-resolved
            rm -f /etc/resolv.conf
            echo 'nameserver 127.0.0.1' >/etc/resolv.conf
            _warn "systemctl disable systemd-resolved was run. Please reboot"
            [ -s /etc/rc.local ] && _insert_line /etc/rc.local "sed -i 's/127.0.0.53/127.0.0.1/' /etc/resolv.conf" "exit 0"
        fi
        # Also may need to use bind-interfaces and except-interface not to listen libvirt interfaces
    fi
    # TODO: To avoid "Ignoring query from non-local network" message:
    grep 'local-service' /etc/init.d/dnsmasq
}

function f_dnsmasq_banner_reset() {
    local __doc__="Regenerate /etc/banner_add_hosts"
    local _how_many="${1-$r_NUM_NODES}" # Or hostname
    local _start_from="${2-$r_NODE_START_NUM}"
    local _ip_prefix="${3-$r_DOCKER_NETWORK_ADDR}" # Or exact IP address
    local _remote_dns_host="${4}"
    local _remote_dns_user="${5:-$USER}"

    local _node="${r_NODE_HOSTNAME_PREFIX-$g_NODE_HOSTNAME_PREFIX}"
    local _domain="${r_DOMAIN_SUFFIX-$g_DOMAIN_SUFFIX}"
    local _base="${g_DOCKER_BASE}:$_os_ver"

    local _docker0="$(f_docker_ip)"
    # TODO: the first IP can be wrong one
    if [ -n "$r_DOCKER_HOST_IP" ]; then
        _docker0="$r_DOCKER_HOST_IP"
    fi

    if [ -z "$r_DOCKER_PRIVATE_HOSTNAME" ]; then
        _warn "Hostname for docker host in the private network is empty. using dockerhost1"
        r_DOCKER_PRIVATE_HOSTNAME="dockerhost1"
    fi

    rm -rf /tmp/banner_add_hosts

    # if no banner file, no point of updating it.
    if [ -s /etc/banner_add_hosts ]; then
        if [ -z "${_remote_dns_host}" ]; then
            cp -pf /etc/banner_add_hosts /tmp/banner_add_hosts || return $?
        else
            scp -q ${_remote_dns_user}@${_remote_dns_host}:/etc/banner_add_hosts /tmp/banner_add_hosts || return $?
        fi
    fi

    if [ -n "${_docker0}" ]; then
        # If an empty file
        if [ ! -s /tmp/banner_add_hosts ]; then
            echo "$_docker0     ${r_DOCKER_PRIVATE_HOSTNAME}${_domain} ${r_DOCKER_PRIVATE_HOSTNAME}" >/tmp/banner_add_hosts
        else
            grep -vE "$_docker0|${r_DOCKER_PRIVATE_HOSTNAME}${_domain}" /tmp/banner_add_hosts >/tmp/banner
            echo "$_docker0     ${r_DOCKER_PRIVATE_HOSTNAME}${_domain} ${r_DOCKER_PRIVATE_HOSTNAME}" >>/tmp/banner
            cat /tmp/banner >/tmp/banner_add_hosts
        fi
    fi

    if ! [[ "$_how_many" =~ ^[0-9]+$ ]]; then
        local _hostname="$_how_many"
        local _ip_address="${_ip_prefix}"
        local _shortname="$(echo "${_hostname}" | cut -d"." -f1)"
        grep -vE "${_hostname}|${_ip_address}" /tmp/banner_add_hosts >/tmp/banner
        echo "${_ip_address}    ${_hostname} ${_shortname}" >>/tmp/banner
        cat /tmp/banner >/tmp/banner_add_hosts
    else
        for _n in $(_docker_seq "$_how_many" "$_start_from"); do
            local _hostname="${_node}${_n}${_domain}"
            local _ip_address="${_ip_prefix%\.}.${_n}"
            local _shortname="${_node}${_n}"
            grep -vE "${_hostname}|${_ip_address}" /tmp/banner_add_hosts >/tmp/banner
            echo "${_ip_address}    ${_hostname} ${_shortname}" >>/tmp/banner
            cat /tmp/banner >/tmp/banner_add_hosts
        done
    fi

    # copy back and restart
    if [ -z "${_remote_dns_host}" ]; then
        cp -pf /tmp/banner_add_hosts /etc/
        service dnsmasq reload || service dnsmasq restart
    else
        scp -q /tmp/banner_add_hosts ${_remote_dns_user}@${_remote_dns_host}:/etc/
        ssh -q ${_remote_dns_user}@${_remote_dns_host} "service dnsmasq reload || service dnsmasq restart"
    fi
}

function f_pptpd() {
    local __doc__="Setup PPTP daemon on Ubuntu host"
    # Ref: https://askubuntu.com/questions/891393/vpn-pptp-in-ubuntu-16-04-not-working
    local _user="${1:-pptpuser}"
    local _pass="${2:-${_user}}"
    local _if="${3}"

    local _vpn_net="10.0.0"
    if [ -z "${_if}" ]; then
        _if="$(ifconfig | grep $(hostname -i) -B 1 | grep -oE '^e[^ ]+')"
    fi
    # https://pupli.net/2018/01/24/setup-pptp-server-on-ubuntu-16-04/
    apt-get install pptpd ppp pptp-linux -y || return $?
    systemctl enable pptpd
    grep -q '^logwtmp' /etc/pptpd.conf || echo -e "logwtmp" >>/etc/pptpd.conf
    grep -q '^localip' /etc/pptpd.conf || echo -e "localip ${_vpn_net}.1\nremoteip ${_vpn_net}.100-200" >>/etc/pptpd.conf
    # NOTE: not setting up DNS by editing pptpd-options, and net.ipv4.ip_forward=1 should have been done

    if ! id -u $_user &>/dev/null; then
        f_useradd "$_user" "$_pass" || return $?
    fi
    grep -q "^${_user}" /etc/ppp/chap-secrets || echo "${_user} * ${_pass} *" >>/etc/ppp/chap-secrets

    iptables -t nat -A POSTROUTING -s ${_vpn_net}.0/24 -o ${_if} -j MASQUERADE # make sure interface is correct
    iptables -A FORWARD -p tcp --syn -s ${_vpn_net}.0/24 -j TCPMSS --set-mss 1356

    service pptpd restart
}

function f_l2tpd() {
    local __doc__="Setup L2TP daemon on Ubuntu host"
    # Ref: https://qiita.com/namoshika/items/30c348b56474d422ef64 (japanese)
    local _user="${1:-l2tpuser}"
    local _pass="${2:-${_user}}"
    local _if="${3}"

    local _vpn_net="172.31.0"
    if [ -z "${_if}" ]; then
        _if="$(ifconfig | grep $(hostname -i) -B 1 | grep -oE '^e[^ ]+')"
    fi
    apt-get install strongswan xl2tpd -y || return $?

    if [ ! -e /etc/ipsec.conf.orig ]; then
        cp -p /etc/ipsec.conf /etc/ipsec.conf.orig || return $?
    else
        cp -p /etc/ipsec.conf /etc/ipsec.conf.$(date +"%Y%m%d%H%M%S")
    fi
    echo 'config setup
    nat_traversal=yes

conn %default
    auto=add

conn L2TP-NAT
    type=transport
    leftauth=psk
    rightauth=psk' >/etc/ipsec.conf || return $?

    if [ ! -e /etc/ipsec.secrets.orig ]; then
        cp -p /etc/ipsec.secrets /etc/ipsec.secrets.orig || return $?
    else
        cp -p /etc/ipsec.secrets /etc/ipsec.secrets.$(date +"%Y%m%d%H%M%S")
    fi
    echo ': PSK "longlongpassword"' >/etc/ipsec.secrets

    if [ ! -e /etc/xl2tpd/xl2tpd.conf.orig ]; then
        cp -p /etc/xl2tpd/xl2tpd.conf /etc/xl2tpd/xl2tpd.conf.orig || return $?
    else
        cp -p /etc/xl2tpd/xl2tpd.conf /etc/xl2tpd/xl2tpd.conf.$(date +"%Y%m%d%H%M%S")
    fi
    # see "man xl2tpd.conf"
    echo '[lns default]
  ip range = '${_vpn_net}'.100-200
  local ip = '${_vpn_net}'.1
  length bit = yes                          ; * Use length bit in payload?
  refuse pap = yes                          ; * Refuse PAP authentication
  refuse chap = yes                         ; * Refuse CHAP authentication
  require authentication = yes              ; * Require peer to authenticate
  name = l2tp                               ; * Report this as our hostname
  pppoptfile = /etc/ppp/options.l2tpd.lns   ; * ppp options file' >/etc/xl2tpd/xl2tpd.conf

    if [ -f /etc/ppp/options.l2tpd.lns ]; then
        cp -p /etc/ppp/options.l2tpd.lns /etc/ppp/options.l2tpd.lns.$(date +"%Y%m%d%H%M%S")
    fi
    # In file /etc/ppp/options.l2tpd.lns: unrecognized option 'lock'
    echo 'name l2tp
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
nodefaultroute
nobsdcomp
mtu 1100
mru 1100
logfile /var/log/xl2tpd.log' >/etc/ppp/options.l2tpd.lns

    if ! id -u $_user &>/dev/null; then
        f_useradd "$_user" "$_pass" || return $?
    fi
    grep -q "^${_user}" /etc/ppp/chap-secrets || echo "${_user} * ${_pass} *" >>/etc/ppp/chap-secrets

    # NOTE: net.ipv4.ip_forward=1 should have been set already
    #iptables -t nat -A POSTROUTING -s ${_vpn_net}.0/24 -o ${_if} -j MASQUERADE # make sure interface is correct
    #iptables -A FORWARD -p tcp --syn -s ${_vpn_net}.0/24 -j TCPMSS --set-mss 1356

    systemctl restart strongswan
    systemctl restart strongswan-starter
    systemctl restart xl2tpd
}

function f_sstpd() {
    local __doc__="Setup sstp daemon (SoftEther) on Ubuntu host"
    # Ref: https://www.softether.org/    https://qiita.com/t-ken/items/c43865973dc3dd5d047c

    echo "TODO: This function requires your input at this moment"
    # https://pupli.net/2018/01/24/setup-pptp-server-on-ubuntu-16-04/
    apt-get install bridge-utils gcc make -y || return $?
    local _tmpdir="$(mktemp -d)" || return $?
    curl --retry 3 -o ${_tmpdir%}/softether-vpnserver-latest-linux-x64-64bit.tar.gz "http://www.softether-download.com/files/softether/v4.28-9669-beta-2018.09.11-tree/Linux/SoftEther_VPN_Server/64bit_-_Intel_x64_or_AMD64/softether-vpnserver-v4.28-9669-beta-2018.09.11-linux-x64-64bit.tar.gz" || return $?
    tar -xv -C ${_tmpdir} -f ${_tmpdir%}/softether-vpnserver-latest-linux-x64-64bit.tar.gz || return $?
    cd ${_tmpdir%}/vpnserver || return $?
    make || $?
    cd -
    if [ -e /usr/local/vpnserver ]; then
        _error "/usr/local/vpnserver exists"
        return 1
    fi
    mv ${_tmpdir%}/vpnserver /usr/local/ || return $?
    chmod 600 /usr/local/vpnserver/*
    chmod 700 /usr/local/vpnserver/{vpncmd,vpnserver}

    if [ -s /etc/systemd/system/vpnserver.service ]; then
        _error "/etc/systemd/system/vpnserver.service exists"
        return 1
    fi

    echo '[Unit]
Description=SoftEther VPN Server
After=network.target network-online.target

[Service]
ExecStart=/usr/local/vpnserver/vpnserver start
ExecStop=/usr/local/vpnserver/vpnserver stop
Type=forking
RestartSec=3s

[Install]
WantedBy=multi-user.target' >/etc/systemd/system/vpnserver.service || return $?
    systemctl daemon-reload
    systemctl enable vpnserver.service
    systemctl start vpnserver.service || return $?

    # TODO
    return 1
}

function f_tunnel() {
    local __doc__="TODO: Create a tunnel between this host and a target host. Requires ppp and password-less SSH"
    local _connecting_to="$1"        # Remote host IP
    local _container_network_to="$2" # ex: 172.17.140.0 or 172.17.140.
    local _container_network_from="${3-${r_DOCKER_NETWORK_ADDR%.}.0}"
    local _container_net_mask="${4-24}"
    local _outside_nic_name="${5-ens3}"

    # NOTE: normally below should be OK but doesn't work with our VMs in the lab
    #[ -z "$_connecting_from" ] && _connecting_from="`hostname -i`"
    local _connecting_from="$(ifconfig ${_outside_nic_name} | grep -oP 'inet addr:\d+\.\d+\.\d+\.\d+' | cut -d":" -f2)"

    [ -z "$_connecting_to" ] && return 11
    [ -z "$_container_network_to" ] && return 12
    [ -z "$_container_network_from" ] && return 13

    local _regex="[0-9]+\.([0-9]+)\.([0-9]+)\.[0-9]+"
    local _network_prefix="10.0.0."
    local _tunnel_nic_to_ip="10.0.1.2"
    [[ "$_container_network_to" =~ $_regex ]] && _tunnel_nic_to_ip="10.${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.1"
    [[ "$_container_network_from" =~ $_regex ]] && _network_prefix="10.${BASH_REMATCH[1]}.${BASH_REMATCH[2]}."

    local _tunnel_nic_from_ip=""
    for i in {1..10}; do
        if ! ifconfig | grep -qw "${_network_prefix}$i"; then
            _tunnel_nic_from_ip="${_network_prefix}$i"
            break
        fi
    done
    if [ -z "$_tunnel_nic_from_ip" ]; then
        ps auxwww | grep -w pppd | grep -v grep
        return 21
    fi

    pppd updetach noauth silent nodeflate pty "ssh root@${_connecting_to} pppd nodetach notty noauth" ipparam vpn $_tunnel_nic_from_ip:$_tunnel_nic_to_ip || return $?
    ssh -qt root@${_connecting_to} "ip route add ${_container_network_from%0}0/${_container_net_mask#/} via $_tunnel_nic_to_ip"

    #ip route del ${_container_network_to%0}0/${_container_net_mask#/}
    ip route add ${_container_network_to%0}0/${_container_net_mask#/} via $_tunnel_nic_from_ip
    #iptables -t nat -L --line-numbers; iptables -t nat -D POSTROUTING 3 #iptables -t nat -F
    #iptables -t nat -A POSTROUTING -s ${_container_network_from%0}0/${_container_net_mask#/} ! -d 172.17.0.0/16 -j MASQUERADE
    #echo "Please run \"ip route del 172.17.0.0/16 via 0.0.0.0\" on all containers on both hosts."
}

function f_kvm() {
    local __doc__="Install KVM on Ubuntu (20.04) host"
    local _virt_user="${1-"virtuser"}"
    local _virt_pass="${2:-"${_virt_user}"}"
    local _image_dir="${3}"
    # https://linuxconfig.org/configure-default-kvm-virtual-storage-on-redhat-linux
    local _cpu_num=$(grep -Eoc '(vmx|svm)' /proc/cpuinfo)
    if [ -z "${_cpu_num}" ] || [[ 1 -gt ${_cpu_num} ]]; then
        _error "Hardware virtualization may not be supported."
        return 1
    fi

    if [ -n "${_image_dir}" ]; then
        if [ -f "/var/lib/libvirt/images" ]; then
            mv -v /var/lib/libvirt/images /var/lib/libvirt/images_orig || return $?
        fi
        if [ ! -d "${_image_dir}" ]; then
            mkdir -m 777 -p "${_image_dir}" || return $?
            if [ -d "/var/lib/libvirt/images_orig" ]; then
                _info "Created ${_image_dir}. copying images from /var/lib/libvirt/images_orig ..."
                cp -v -r -p /var/lib/libvirt/images_orig/* ${_image_dir%/}/
            fi
        fi

        ln -s ${_image_dir%/} /var/lib/libvirt/images || return $?
    fi

    if grep -qiP 'Ubuntu (18|20)\.' /etc/issue.net; then
        apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst virt-manager || return $?
        systemctl is-active libvirtd || return $?
    else    # for 16.04
        apt-get -y install qemu-kvm libvirt-bin virtinst bridge-utils libosinfo-bin libguestfs-tools virt-top virt-manager qemu-system || return $?
        if ! grep -qw "vhost_net" /etc/modules; then
            modprobe vhost_net
            echo vhost_net >>/etc/modules
            _warn "You may need to reboot before using KVM."
        fi
    fi

    # @see: https://computingforgeeks.com/use-virt-manager-as-non-root-user/
    if [ -n "${_virt_user}" ] && ! id -u ${_virt_user} &>/dev/null; then
        f_useradd "${_virt_user}" "${_virt_pass}" || return $?

        local _group="$(getent group | grep -E '^(libvirt|libvirtd):' | cut -d":" -f1)"
        if [ -z "${_group}" ]; then
            _error "libvirt(d) group does not exist. Check the installation (groupadd --system libvirtd)"
            return 1
        fi

        usermod -a -G ${_group} ${_virt_user}
        #newgrp libvirt

        if ! grep '^unix_sock_group' /etc/libvirt/libvirtd.conf | grep -qw ${_group}; then
            _error "${_group} is not configured in /etc/libvirt/libvirtd.conf"
            return 1
        fi

        if ! grep '^unix_sock_rw_perms' /etc/libvirt/libvirtd.conf | grep -q "770"; then
            _warn "unix_sock_rw_perms may not be 0770"
        fi
        _info "Execute 'systemctl restart libvirtd.service' if all good."
    fi

    # TODO: create a bridge interface (br0) https://www.cyberciti.biz/faq/how-to-add-network-bridge-with-nmcli-networkmanager-on-linux/
    # Well, docker0 NIC works... (and TODO: netsh winhttp set proxy proxy-server="http=172.17.0.1:28080;https=172.17.0.1:28080"
    #nmcli con add ifname br0 type bridge con-name br0 && nmcli con add type bridge-slave ifname eno1 master br0 && nmcli con modify br0 bridge.stp no && nmcli con up br0
    #nmcli connection modify br0 ipv4.addresses 192.168.52.31/24 && nmcli connection modify br0 ipv4.dns && nmcli connection modify br0 ipv4.method manual
    #nmcli connection show
    #nmcli -f bridge con show br0
    _info "To connect (need to configure ssh password-less access):
    virt-manager -c 'qemu+ssh://${_virt_user:-"root"}@$(ip route get 1 | sed -nr 's/^.* src ([^ ]+) .*$/\1/p')/system?socket=/var/run/libvirt/libvirt-sock'"
    # To check DHCP IP addresses
    #virsh net-dhcp-leases default
}

function f_postfix() {
    local __doc__="Install SMTP package (postfix) and configure."
    local _redirect_mail="${1}" # useful for SMTP testing
    local _relay_host="${2}"
    local _conf_file="/etc/postfix/main.cf"

    DEBIAN_FRONTEND=noninteractive apt-get -y install postfix mailutils || return $?

    touch /etc/postfix/generic || return $?
    _upsert "${_conf_file}" "smtp_generic_maps" "hash:/etc/postfix/generic"
    if [ -n "${_relay_host}" ]; then
        _upsert "${_conf_file}" "relayhost" "${_relay_host}"
    fi
    if [ -n "${_redirect_mail}" ]; then
        if grep -qw "${_redirect_mail}" /etc/postfix/recipient_canonical_map; then
            _log "WARN" "${_redirect_mail} exists in /etc/postfix/recipient_canonical_map, so not setting up the redirection."
            sleep 3
        else
            echo "/./ ${_redirect_mail}" >>/etc/postfix/recipient_canonical_map || return $?
            _upsert "${_conf_file}" "inet_protocols" "ipv4"
            _upsert "${_conf_file}" "recipient_canonical_classes" "envelope_recipient"
            _upsert "${_conf_file}" "recipient_canonical_maps" "regexp:/etc/postfix/recipient_canonical_map"
            _upsert "${_conf_file}" "smtpd_tls_security_level" "may"
            # Ubuntu's postfix uses /etc/ssl/private/ssl-cert-snakeoil.key so actually don't need below
            if [ -s /var/tmp/share/cert/standalone.localdomain.key ]; then
                _upsert "${_conf_file}" "smtpd_tls_key_file" "/var/tmp/share/cert/standalone.localdomain.key"
                _upsert "${_conf_file}" "smtpd_tls_cert_file" "/var/tmp/share/cert/standalone.localdomain.crt"
            fi
            _log "INFO" "openssl s_client -host localhost -port 25 -starttls smtp" # -debug
            echo -n | openssl s_client -host localhost:25 -starttls smtp -crlf
            # To connect with starttls, like telnet:
            #openssl s_client -connect localhost:25 -starttls smtp -crlf
            #ehlo localhost
            #mail from:sender@domain.com
            #rcpt to:recipient@remotedomain.com
            #data   # hit enter then type something and '.' enter, Ctrl+D to exit.
        fi
    fi

    postmap /etc/postfix/generic || return $?
    service postfix restart || return $?
    _log "INFO" "For 'Relay access denied', may need to modify 'mynetworks'"
    #postconf -n | grep smtpd_relay_restrictions
    #smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
    #mail --debug-level=9 -a "FROM:test@hajigle.com" -s "test mail" admin@osakos.com </dev/null
}

function f_mac2ip() {
    local __doc__="Try finding IP address from arp cache"
    local _mac="$1"
    local _xxx_xxx_xxx="$2" # ping -b takes looooooong time
    [ -z "${_mac}" ] && return 1
    if [ -n "${_xxx_xxx_xxx}" ]; then
        _info "ping-ing to ${_xxx_xxx_xxx%.}.% ..."
        echo $(seq 254) | xargs -P128 -I% -d" " ping -q -n -W 1 -c 1 ${_xxx_xxx_xxx%.}.% &>/dev/null
    fi
    arp -a | grep -i "${_mac}"
}

function f_vmware_tools_install() {
    local __doc__="Install VMWare Tools in Ubuntu host"
    mkdir /media/cdrom
    mount /dev/cdrom /media/cdrom && cd /media/cdrom && cp VMwareTools-*.tar.gz /tmp/ && cd /tmp/ && tar xzvf VMwareTools-*.tar.gz && cd vmware-tools-distrib/ && ./vmware-install.pl -d
}

function f_host_performance() {
    local __doc__="Performance related changes on the host. Eg: Change kernel parameters on Docker Host (Ubuntu)"
    grep -q '^vm.swappiness' /etc/sysctl.conf || echo "vm.swappiness = 0" >>/etc/sysctl.conf
    sysctl -w vm.swappiness=0

    grep -q '^net.core.somaxconn' /etc/sysctl.conf || echo "net.core.somaxconn = 16384" >>/etc/sysctl.conf
    sysctl -w net.core.somaxconn=16384

    # also ip forwarding as well
    grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf || echo "net.ipv4.ip_forward = 1" >>/etc/sysctl.conf
    sysctl -w net.ipv4.ip_forward=1
    grep -q '^net.ipv4.conf.all.forwarding' /etc/sysctl.conf || echo "net.ipv4.conf.all.forwarding = 1" >>/etc/sysctl.conf
    sysctl -w net.ipv4.conf.all.forwarding=1
    grep -q '^net.bridge.bridge-nf-call-iptables' /etc/sysctl.conf || echo "net.bridge.bridge-nf-call-iptables = 0" >>/etc/sysctl.conf
    sysctl -w net.bridge.bridge-nf-call-iptables=0

    grep -q '^kernel.panic' /etc/sysctl.conf || echo "kernel.panic = 20" >>/etc/sysctl.conf
    sysctl -w kernel.panic=60
    grep -q '^kernel.panic_on_oops' /etc/sysctl.conf || echo "kernel.panic_on_oops = 1" >>/etc/sysctl.conf
    sysctl -w kernel.panic_on_oops=1

    echo never >/sys/kernel/mm/transparent_hugepage/enabled
    echo never >/sys/kernel/mm/transparent_hugepage/defrag

    [ ! -s /etc/rc.lcoal ] && echo -e '#!/bin/bash\nexit 0' >/etc/rc.local

    if grep -q '^echo never > /sys/kernel/mm/transparent_hugepage/enabled' /etc/rc.local; then
        sed -i.bak '/^exit 0/i echo never > /sys/kernel/mm/transparent_hugepage/enabled\necho never > /sys/kernel/mm/transparent_hugepage/defrag\n' /etc/rc.local
    fi
    chmod a+x /etc/rc.local
}

function f_install_packages() {
    local __doc__="Install utility/common packages I frequently use"
    which apt-get &>/dev/null || return $?
    apt-get update || return $?
    apt-get -y install sysv-rc-conf # Not stopping if error because Ubuntu 18 does not have this
    apt-get -y install python2 python3 # Not stopping if error because Ubuntu 18 does not have this
    #apt-get -y install postgresql-client mysql-client libmysql-java    # Probably no longer need to install these all the time
    apt-get -y install vim openssh-server screen ntpdate curl wget sshfs tcpdump sharutils unzip libxml2-utils expect netcat nscd ppp at resolvconf
}

function f_sshfs_mount() {
    local __doc__="Mount sshfs. May need root priv"
    local _remote_src="${1}"
    local _local_dir="${2}"

    if mount | grep -qw "${_local_dir%/}"; then
        _info "Un-mounting ${_local_dir%/} ..."
        sleep 3
        umount -f "${_local_dir%/}" || return $?
    fi
    if [ ! -d "${_local_dir}" ]; then
        mkdir -p -m 777 "${_local_dir}" || return $?
    fi

    _info "Mounting ${_remote_src%/}/ to ${_local_dir} ..."
    _info "If it asks password, please stop and use ssh-copy-id."
    local _cmd="sshfs -o allow_other,uid=0,gid=0,umask=002,reconnect,follow_symlinks ${_remote_src%/}/ ${_local_dir%/}"
    eval ${_cmd} || return $?
    [ ! -s /etc/rc.lcoal ] && echo -e '#!/bin/bash\nexit 0' >/etc/rc.local
    _insert_line /etc/rc.local "${_cmd}" "exit 0"
}

function f_port_forward() {
    local __doc__="Port forwarding a local port to a container port"
    local _local_port="$1"
    local _remote_host="$2"
    local _remote_port="$3"
    local _kill_process="$4"

    if [ -z "$_local_port" ] || [ -z "$_remote_host" ] || [ -z "$_remote_port" ]; then
        _error "Local Port or Remote Host or Remote Port is missing."
        return 1
    fi
    local _pid="$(lsof -ti:$_local_port)"
    if [ -n "$_pid" ]; then
        _warn "Local port $_local_port is already used by PID $_pid."
        if _isYes "$_kill_process"; then
            kill $_pid || return 3
            _info "Killed $_pid."
        else
            return 0
        fi
    fi

    #if ! which socat &>/dev/null ; then
    #    _warn "No socat. Installing"; apt-get install socat -y || return 2
    #fi
    #nohup socat tcp4-listen:$_local_port,reuseaddr,fork tcp:$_remote_host:$_remote_port & TODO: which is better, socat or ssh?
    _info "port-forwarding -L$_local_port:$_remote_host:$_remote_port ..."
    ssh -2CNnqTxfg -L$_local_port:$_remote_host:$_remote_port $_remote_host
}

function f_gen_keytab() {
    local __doc__="Generate keytab(s). NOTE: NOT for FreeIPA"
    local _principal="${1}" # HTTP/`hosntame -f`@REALM
    local _kadmin_usr="${2:-"admin/admin"}"
    local _kadmin_pwd="${3:-${g_DEFAULT_PASSWORD:-"hadoop"}}"
    local _keytab_dir="${4:-"/etc/security/keytabs"}"
    local _delete_first="${5-${_DELETE_FIRST}}" # default is just creating keytab if already exists
    local _tmp_dir="${_WORK_DIR}"

    # This function will create the following keytabs:
    # ${_tmp_dir%/}/keytabs/${_user}.headless.keytab
    # ${_keytab_dir%/}/${_user}.service.keytab (contains both headless and service)
    local _service="${_principal}"
    local _host="$(hostname -f)"
    local _realm="$(sed -n -e 's/^ *default_realm *= *\b\(.\+\)\b/\1/p' /etc/krb5.conf)"
    if [[ "${_principal}" =~ ^([^ @/]+)/([^ @]+)$ ]]; then
        [ -n "${BASH_REMATCH[1]}" ] && _service="${BASH_REMATCH[1]}"
        [ -n "${BASH_REMATCH[2]}" ] && _host="${BASH_REMATCH[2]}"
    elif [[ "${_principal}" =~ ^([^ @/]+)/([^ @]+)@([^ ]+)$ ]]; then
        [ -n "${BASH_REMATCH[1]}" ] && _service="${BASH_REMATCH[1]}"
        [ -n "${BASH_REMATCH[2]}" ] && _host="${BASH_REMATCH[2]}"
        [ -n "${BASH_REMATCH[3]}" ] && _realm="${BASH_REMATCH[3]}" # NOT using at this moment
    fi

    if [ ! -d "${_tmp_dir%/}/keytabs" ]; then
        mkdir -p ${_tmp_dir%/}/keytabs || return $?
    fi

    if [[ "${_delete_first}" =~ ^(y|Y) ]]; then
        _log "WARN" "Deleting principals ${_service} ${_service}/${_host} ..."
        sleep 3
        kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "delete_principal -force ${_service}@${_realm}"
        kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "delete_principal -force ${_service}/${_host}@${_realm}"
        kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "delete_principal -force ${_principal}"

        # if successfully deleted, remove keytabs too
        if [ -s "${_tmp_dir%/}/keytabs/${_service}.headless.keytab" ]; then
            _log "WARN" "Removing ${_tmp_dir%/}/keytabs/${_service}.headless.keytab ..."
            sleep 3
            rm -f "${_tmp_dir%/}/keytabs/${_service}.headless.keytab" || return $?
        fi
    fi

    # Add only if not existed yet (do not want to increase kvno)
    if ! kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "get_principal ${_service}@${_realm}" | grep -wq "${_service}"; then
        kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "add_principal -randkey ${_service}@${_realm}"
    fi
    if ! kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "get_principal ${_service}/${_host}@${_realm}" | grep -wq "${_service}/${_host}"; then
        kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "add_principal -randkey ${_service}/${_host}@${_realm}" || return $?
    fi
    if ! kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "get_principal ${_principal}" | grep -wq "${_principal}"; then
        kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "add_principal -randkey ${_principal}" || return $?
    fi

    # trying not to update kvno by using a common user/headless keytab and ktutil...
    if [ ! -s "${_tmp_dir%/}/keytabs/${_service}.headless.keytab" ]; then
        kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "xst -k ${_tmp_dir%/}/keytabs/${_service}.headless.keytab ${_service}" || return $?
    fi

    [ ! -d "${_keytab_dir%/}" ] && mkdir -p "${_keytab_dir%/}"

    # backup
    if [ -s "${_keytab_dir%/}/${_service}.service.keytab" ] && [ ! -f "${_keytab_dir%/}/${_service}.service.keytab.orig" ]; then
        _log "INFO" "Moving ${_keytab_dir%/}/${_service}.service.keytab to .orig ..."
        sleep 1
        mv "${_keytab_dir%/}/${_service}.service.keytab" "${_keytab_dir%/}/${_service}.service.keytab.orig" || return $?
    fi
    kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "xst -k ${_keytab_dir%/}/${_service}.service.keytab ${_service}/${_host}" || return $?

    # backup
    if [ -s "${_keytab_dir%/}/${_service}.combined.keytab" ] && [ ! -f "${_keytab_dir%/}/${_service}.combined.keytab.orig" ]; then
        _log "INFO" "Moving ${_keytab_dir%/}/${_service}.combined.keytab to .orig ..."
        sleep 1
        mv "${_keytab_dir%/}/${_service}.combined.keytab" "${_keytab_dir%/}/${_service}.combined.keytab.orig" || return $?
    fi
    ktutil <<EOF
rkt ${_tmp_dir%/}/keytabs/${_service}.headless.keytab
rkt ${_keytab_dir%/}/${_service}.service.keytab
wkt ${_keytab_dir%/}/${_service}.combined.keytab
exit
EOF

    if [ "${_service}" == "HTTP" ]; then
        chmod a+r ${_tmp_dir%/}/keytabs/${_service}.headless.keytab ${_keytab_dir%/}/${_service}.*
    else
        chown ${_service}: ${_tmp_dir%/}/keytabs/${_service}.headless.keytab ${_keytab_dir%/}/${_service}.*
        chmod 600 ${_tmp_dir%/}/keytabs/${_service}.headless.keytab ${_keytab_dir%/}/${_service}.*
    fi
    _log "INFO" "Testing ..."
    ls -l ${_keytab_dir%/}/${_service}.*
    kinit -kt ${_keytab_dir%/}/${_service}.service.keytab ${_principal}
    klist -eaf
    kdestroy
}

function f_crowd() {
    local _ver="${1:-"4.1.2"}"
    local _user="${2-"crowd"}"
    local _data_dir="${3-"/var/crowd-home"}" # some persistent location if docker
    # rm -rf /opt/crowd/* /var/crowd/* /var/crowd-home/*
    _download_and_extract "https://product-downloads.atlassian.com/software/crowd/downloads/atlassian-crowd-${_ver}.tar.gz" "/opt/crowd" "" "" "${_user}" || return $?
    if ! grep -q "^crowd.home" "/opt/crowd/atlassian-crowd-${_ver}/crowd-webapp/WEB-INF/classes/crowd-init.properties"; then
        _upsert "/opt/crowd/atlassian-crowd-${_ver}/crowd-webapp/WEB-INF/classes/crowd-init.properties" "crowd.home" "${_data_dir%/}/${_ver}" || return $?
    fi
    [ -d "${_data_dir%/}" ] || mkdir -p -m 777 "${_data_dir%/}"
    if [ -n "${_user}" ]; then
        f_useradd "${_user}" || return $?
        chown -R "${_user}:" "/opt/crowd/atlassian-crowd-${_ver}"
    fi
    sudo -i -u "${_user}" bash /opt/crowd/atlassian-crowd-${_ver}/start_crowd.sh || return $?
    _log "INFO" "Access http://$(hostname -f):8095/
For trial license: https://developer.atlassian.com/platform/marketplace/timebomb-licenses-for-testing-server-apps/
Then, '3 hour expiration for all Atlassian host products'"
}

function f_jira() {
    local _ver="${1:-"8.14.1"}"
    local _user="${2-"jira"}"
    local _data_dir="${3-"/var/jira-home"}" # some persistent location if docker
    # rm -rf /opt/jira/* /var/jira-home/*
    _download_and_extract "https://product-downloads.atlassian.com/software/jira/downloads/atlassian-jira-software-${_ver}.tar.gz" "/opt/jira" "" "" "${_user}" || return $?
    if ! grep -qE "^jira.home *= *[^ ]+" "/opt/jira/atlassian-jira-software-${_ver}-standalone/atlassian-jira/WEB-INF/classes/jira-application.properties"; then
        _upsert "/opt/jira/atlassian-jira-software-${_ver}-standalone/atlassian-jira/WEB-INF/classes/jira-application.properties" "jira.home" "${_data_dir%/}/${_ver}" || return $?
    fi
    [ -d "${_data_dir%/}" ] || mkdir -p -m 777 "${_data_dir%/}"
    if [ -n "${_user}" ]; then
        f_useradd "${_user}" || return $?
        chown -R "${_user}:" "/opt/jira/atlassian-jira-software-${_ver}-standalone"
    fi
    sudo -i -u "${_user}" bash /opt/jira/atlassian-jira-software-${_ver}-standalone/bin/start-jira.sh || return $?
    _log "INFO" "Access http://$(hostname -f):8080/
For trial license: https://developer.atlassian.com/platform/marketplace/timebomb-licenses-for-testing-server-apps/
Then, '3 hour expiration for all Atlassian host products'"
}

function f_bitbucket() {
    # @see: https://confluence.atlassian.com/bitbucketserver/install-a-bitbucket-trial-867192384.html
    local _ver="${1:-"7.14.0"}"
    local _user="${2-"bitbucket"}"
    local _data_dir="${3-"/var/bitbucket-home"}" # some persistent location if docker
    # rm -rf /opt/bitbucket/* /var/bitbucket-home/*
    # Git version 2 or higher is required
    if ! git --version | grep -qE 'git version [2345]'; then
        # TODO: this script is for Ubuntu or generic, but using 'yum' (but as Ubuntu doesn't use git v1, should be OK)
        yum install -y https://repo.ius.io/ius-release-el7.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
        local _git_ver="$(yum list available | grep -E '^git[0-9]+\.x86_64\s+.+\s+ius' | sort | tail -n1 | awk '{print $1}')"
        if [ -z "${_git_ver}" ]; then
            _log "ERROR" "Cannot install Git v2"
            return 1
        fi
        yum remove -y git*
        yum insatll ${_git_ver} -y   # even if fails, keep going...
    fi
    _download_and_extract "https://product-downloads.atlassian.com/software/stash/downloads/atlassian-bitbucket-${_ver}.tar.gz" "/opt/bitbucket" "" "" "${_user}" || return $?
    if [ -n "${_user}" ]; then
        f_useradd "${_user}" || return $?
        chown -R "${_user}:" "/opt/bitbucket/atlassian-bitbucket-${_ver}"
    fi
    local _java_home="$(dirname $(dirname $(readlink -f $(which java))))"
    if [ -z "${_java_home%/}" ]; then
        _log "ERROR" "No java home detected."
        return 1
    fi
    sudo -i -u ${_user} bash -c 'grep -q "export JAVA_HOME=" $HOME/.bash_profile || echo "export JAVA_HOME='${_java_home%/}'" >> $HOME/.bash_profile'
    [ -d "${_data_dir%/}" ] || mkdir -p -m 777 "${_data_dir%/}"
    sudo -i -u ${_user} bash -c 'grep -q "export BITBUCKET_HOME=" $HOME/.bash_profile || echo "export BITBUCKET_HOME='${_data_dir%/}'" >> $HOME/.bash_profile'
    sudo -i -u "${_user}" bash /opt/bitbucket/atlassian-bitbucket-${_ver}/bin/start-bitbucket.sh || return $?
    _log "INFO" "Access http://$(hostname -f):7990/
For trial license: https://developer.atlassian.com/platform/marketplace/timebomb-licenses-for-testing-server-apps/
Then, '3 hour expiration for all Atlassian host products'"
}

function p_basic_setup() {
    if which apt-get &>/dev/null; then
        _log "INFO" "Executing apt-get install packages"
        f_install_packages || return $?
        _log "INFO" "Executing f_docker_setup"
        f_docker_setup || return $?
        _log "INFO" "Executing f_sysstat_setup"
        f_sysstat_setup
        _log "INFO" "Executing f_apache_proxy"
        f_apache_proxy
        #_log "INFO" "Executing f_squid_proxy"
        #f_squid_proxy
        #_log "INFO" "Executing f_socks5_proxy"
        #f_socks5_proxy
        #_log "INFO" "Executing f_shellinabox" (this will create 'webuser' which can login to any container as root)
        #f_shellinabox

        _log "INFO" "Executing f_dnsmasq"
        f_dnsmasq || return $?
    fi

    _log "INFO" "Executing f_ssh_setup"
    f_ssh_setup || return $?

    _log "INFO" "Executing f_host_misc"
    f_host_misc

    _log "INFO" "Executing f_host_performance"
    f_host_performance

    _log "INFO" "Trusting rootCA_standalone.crt"
    _trust_ca
}

### Utility type functions #################################################

# At this moment, not much difference from _echo and _warn, might change later
function _info() {
    _log "INFO" "$@"
}
function _warn() {
    _log "WARN" "$@"
    local _msg="$1"
}
function _error() {
    _log "ERROR" "$@"
}


function _port_wait() {
    local _host="$1"
    local _port="$2"
    local _times="$3"
    local _interval="$4"

    if [ -z "$_times" ]; then
        _times=10
    fi

    if [ -z "$_interval" ]; then
        _interval=5
    fi

    if [ -z "$_host" ]; then
        _error "No _host specified"
        return 1
    fi

    for i in $(seq 1 $_times); do
        nc -z $_host $_port && return 0
        _info "$_host:$_port is unreachable. Waiting..."
        sleep $_interval
    done
    _warn "$_host:$_port is unreachable."
    return 1
}


function _sed_escape() {
    # Only works with "/" delimiter
    echo "$1" | sed -e 's/[\/&]/\\&/g'
}

function _insert_line() {
    local __doc__="Insert a line into the given file. TODO: should escape _line for sed"
    local _file_path="$1"
    local _line="$2"
    local _before="$3"

    local _line_escaped="$(_sed_escape "${_line}")"
    [ -z "${_line_escaped}" ] && return 1
    local _before_escaped="$(_sed_escape "${_before}")"

    # If no file, create and insert
    if [ ! -s ${_file_path} ]; then
        if [ -n "${_before}" ]; then
            echo -e "${_line}\n${_before}" >${_file_path}
        else
            echo "${_line}" >${_file_path}
        fi
    elif grep -qF "${_line}" ${_file_path}; then
        # Would need to escape special chars, so saying "almost"
        _info "(almost) same line exists, skipping..."
        return
    else
        if [ -n "${_before}" ]; then
            sed -i "/^${_before}/i ${_line}" ${_file_path}
        else
            echo -e "\n${_line}" >>${_file_path}
        fi
    fi
}
