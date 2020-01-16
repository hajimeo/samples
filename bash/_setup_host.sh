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

function f_host_misc() {
    local __doc__="Misc. changes for Ubuntu OS"

    [ ! -d ${_WORK_DIR} ] && mkdir -p -m 777 ${_WORK_DIR}
    
    # AWS / Openstack only change
    if [ -s /home/ubuntu/.ssh/authorized_keys ] && [ ! -f $HOME/.ssh/authorized_keys.bak ]; then
        cp -p $HOME/.ssh/authorized_keys $HOME/.ssh/authorized_keys.bak
        grep 'Please login as the user' $HOME/.ssh/authorized_keys && cat /home/ubuntu/.ssh/authorized_keys > $HOME/.ssh/authorized_keys
    fi

    # If you would like to use the default, comment PasswordAuthentication or PermitRootLogin
    grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config && sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config || return $?
    grep -q '^PermitRootLogin ' /etc/ssh/sshd_config && sed -i 's/^PermitRootLogin .\+/PermitRootLogin no/' /etc/ssh/sshd_config
    if [ $? -eq 0 ]; then
        service ssh restart
    fi

    if [ ! -s /etc/update-motd.d/99-start-hdp ]; then
        echo '#!/bin/bash
ls -lt ~/*.resp
docker ps
screen -ls' > /etc/update-motd.d/99-start-hdp
        chmod a+x /etc/update-motd.d/99-start-hdp
        run-parts --lsbsysinit /etc/update-motd.d > /run/motd.dynamic
    fi

    if [ ! -f /etc/cron.daily/ipchk ]; then
        echo '#!/usr/bin/env bash
_ID="$(hostname -s | tail -c 8)"
_IP="$(hostname -I | cut -d" " -f1)"
curl -s -f "http://www.osakos.com/tools/info.php?id=${_ID}&LOCAL_ADDR=${_IP}"' > /etc/cron.daily/ipchk
        chmod a+x /etc/cron.daily/ipchk
    fi

    f_del_log_cron "${_WORK_DIR%/}/*/logs" "28"
}

function f_del_log_cron() {
    local __doc__="Add a *daily* cron for deleting 'log' files."
    local _dir="${1:-"${_WORK_DIR%/}/*/logs"}"
    local _days="${2:-"7"}"
    local _name="del-${_dir//[^[:alnum:]]/_}-${_days}_days"
    if [ -s /etc/cron.daily/${_name}.cron ]; then
        echo "/etc/cron.daily/${_name}.cron exists"
        return 1
    fi
    # NOTE: I'm using -print to output what will be deleted into STDOUT (but hiding error), which may generate cron email to root
    echo '#!/bin/bash
find '${_dir%/}' -type f -name "*log*" -mtime +'${_days}' -print -delete 2>/dev/null
exit $?' > /etc/cron.daily/${_name}.cron
    chmod a+x /etc/cron.daily/${_name}.cron
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
    local _net_addr="`docker inspect bridge | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['IPAM']['Config'][0]['Subnet'])"`"
    _net_addr="`echo "${_net_addr}" | sed 's/\.[1-9]\+\/[1-9]\+/.0/'`"

    curl -s -f --retry 3 -o /usr/local/bin/shellinabox_login https://raw.githubusercontent.com/hajimeo/samples/master/misc/shellinabox_login.sh || return $?
    sed -i "s/%_user%/${_user}/g" /usr/local/bin/shellinabox_login
    sed -i "s/%_proxy_port%/${_proxy_port}/g" /usr/local/bin/shellinabox_login
    sed -i "s@%_net_addr%@${_net_addr}@g" /usr/local/bin/shellinabox_login
    chmod a+x /usr/local/bin/shellinabox_login

    sleep 1
    local _port=`sed -n -r 's/^SHELLINABOX_PORT=([0-9]+)/\1/p' /etc/default/shellinabox`
    lsof -i:${_port}
    _log "INFO" "To access: 'http://`hostname -I | cut -d" " -f1`:${_port}/${_user}/'"
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
    # To generate '_nodes': docker ps --format "{{.Names}}" | grep -E "^node-(nxrm-ha.|nxiq)$" | sort | sed 's/$/.standalone.localdomain/' | tr '\n' ' '
    # HAProxy needs a concatenated cert: cat ./server.crt ./rootCA.pem ./server.key > certificates.pem'
    local _nodes="${1}"             # Space delimited. If empty, generated from 'docker ps'
    local _ports="${2:-"8081 8443=8081 8070 8071 8444=8070 18079=8081"}" # Space delimited # 18082=18082 18079=18079 18075=18075
    local _skipping_chk="${3}"      # Not to check each backend port (handy when you will start backend later)
    local _certificate="${4}"       # Expecting same (concatenated) cert for front and backend
    local _haproxy_custom_cfg_dir="${5:-"${_WORK_DIR%/}/haproxy"}" # Under this directory, create haproxy.PORT.cfg file
    local _domain="${6:-"standalone.localdomain"}"  # `hostname -d`
    #local _haproxy_tmpl_conf="${_WORK_DIR%/}/haproxy.tmpl.cfg}"

    local _cfg="/etc/haproxy/haproxy.cfg"
    if which haproxy &>/dev/null; then
        _info "INFO" "HAProxy is already installed. To update, run apt-get|yum manually."
    else
        apt-get install haproxy -y || return $?
    fi

    if [ -z "${_nodes}" ]; then
        # I'm using FreeIPA and that container name includes 'freeipa'
        _nodes="$(for _n in `docker ps --format "{{.Names}}" | grep -E "^node-(nxrm-ha.|nxiq)$" | sort`;do docker inspect ${_n} | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['Config']['Hostname'])"; done | tr '\n' ' ')"
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
        mv -v "${_cfg}" "/tmp/`basename ${_cfg}`".$(date +"%Y%m%d%H%M%S") || return $?
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
" > ${_cfg}

    # If dnsmask is installed, utilise it
    local _resolver=""
    if which dnsmasq &>/dev/null; then
        echo "resolvers dnsmasq
  nameserver dns1 localhost:53
  accepted_payload_size 8192
" >> "${_cfg}"
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
            echo "  server ${_n} ${_n}:${_b_port}${_https_opts} check ${_resolver}"  # not using 'cookie' for now.
        done > /tmp/f_haproxy_backends_$$.out

        if [ ! -s /tmp/f_haproxy_backends_$$.out ]; then
            _info "No backend servers found for ${_p} ..."
            continue
        fi

        if [ -s "${_haproxy_custom_cfg_dir%/}/haproxy.${_f_port}.cfg" ]; then
            _info "Found ${_haproxy_custom_cfg_dir%/}/haproxy.${_f_port}.cfg. Appending ..."
            cat "${_haproxy_custom_cfg_dir%/}/haproxy.${_f_port}.cfg" >> "${_cfg}"
            cat /tmp/f_haproxy_backends_$$.out >> "${_cfg}"
            echo "" >> "${_cfg}"
        else
            # If frontend port is already configured somehow (which shouldn't be possible though), skipping
            if ! grep -qE "^frontend frontend_p${_f_port}$" "${_cfg}"; then
                local _frontend_ssl_crt=""
                # NOTE: Enabling HTTP/2 as newer HAProxy supports.
                [ -n "${_certificate}" ] && [ "${_frontend_proto}" = "https" ] && _frontend_ssl_crt=" ssl crt ${_certificate} alpn h2,http/1.1"
                echo "frontend frontend_p${_f_port}
  bind *:${_f_port}${_frontend_ssl_crt}
  reqadd X-Forwarded-Proto:\ ${_frontend_proto}
  default_backend backend_p${_b_port}" >> "${_cfg}"
                echo "" >> "${_cfg}"
            fi

            # If backend port is already configured, not adding as hapxory won't start
            if ! grep -qE "^backend backend_p${_b_port}$" "${_cfg}"; then
                # NOTE: not using 'roundrobin' as I'm not sure if sticky session with cookie is working.
                #       so, also removed 'cookie NXSESSIONID prefix nocache' and 'cookie' from server line
                echo "backend backend_p${_b_port}
  balance source
  option forwardfor
  http-request set-header X-Forwarded-Port %[dst_port]
  option httpchk" >> "${_cfg}"
            #  http-request add-header X-Forwarded-Proto ${_backend_proto}
                cat /tmp/f_haproxy_backends_$$.out >> "${_cfg}"
                echo "" >> "${_cfg}"
            fi
        fi
    done

    # NOTE: May need to configure rsyslog.conf for log if CentOS
    service haproxy reload || return $?
    _info "Installing/Re-configuring HAProxy completed."
}

function f_chrome() {
    local __doc__="Install Google Chrome on Ubuntu"
    if ! grep -q "http://dl.google.com" /etc/apt/sources.list.d/google-chrome.list; then
        echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list || return $?
    fi
    curl -fsSL "https://dl.google.com/linux/linux_signing_key.pub" | apt-key add - || return $?
    apt-get update || return $?
    apt-get install google-chrome-stable -y
}

function f_x2go_setup() {
    local __doc__="Install and setup next generation remote desktop X2Go"
    local _user="${1-$USER}"
    local _pass="${2:-"${_user}"}"

    if ! which apt-get &>/dev/null; then
        _warn "No apt-get"
        return 1
    fi

    apt-add-repository ppa:x2go/stable -y
    apt-get update
    apt-get install xfce4 xfce4-goodies firefox x2goserver x2goserver-xsession -y || return $?

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

    local _current="`cat /etc/hostname`"
    hostname $_new_name
    echo "$_new_name" > /etc/hostname
    sed -i.bak "s/\b${_current}\b/${_new_name}/g" /etc/hosts
    diff /etc/hosts.bak /etc/hosts
}

function f_ip_set() {
    local __doc__="Set IP Address (TODO: Ubuntu 18 only)"
    local _ip_mask="$1"
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

    local _conf_file="/etc/netplan/$(ls -1tr /etc/netplan | tail -n1)"
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
" > ${_conf_file} || return $?
    netplan apply   #--debug apply
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
    [ ! -s /etc/rc.lcoal ] && echo -e '#!/bin/bash\nexit 0' > /etc/rc.local
    _insert_line /etc/rc.local "${_cmd}" "exit 0"
    lsof -nPi:${_port} -s TCP:LISTEN | grep "^ssh" && return 0
    eval "${_cmd}"
}

function f_apache_proxy() {
    local __doc__="Generate proxy.conf and restart apache2"
    local _proxy_dir="/var/www/proxy"
    local _cache_dir="/var/cache/apache2/mod_cache_disk"
    local _port="${r_PROXY_PORT-28080}"

    if ! which apt-get &>/dev/null; then
        _warn "No apt-get"
        return 1
    fi

    # TODO: 777...
    [ ! -d "${_proxy_dir}" ] && mkdir -p -m 777 "${_proxy_dir}"
    [ ! -d "${_cache_dir}" ] && mkdir -p -m 777 "${_cache_dir}"

    if [ -s /etc/apache2/sites-available/proxy.conf ]; then
        _info "/etc/apache2/sites-available/proxy.conf already exists. Skipping..."
        return 0
    fi

    apt-get install -y apache2 apache2-utils
    a2enmod proxy proxy_http proxy_connect proxy_wstunnel cache cache_disk ssl

    grep -i "^Listen ${_port}" /etc/apache2/ports.conf || echo "Listen ${_port}" >> /etc/apache2/ports.conf

    echo "<VirtualHost *:${_port}>
    DocumentRoot ${_proxy_dir}
    LogLevel warn
    ErrorLog \${APACHE_LOG_DIR}/proxy_error.log
    CustomLog \${APACHE_LOG_DIR}/proxy_access.log combined" > /etc/apache2/sites-available/proxy.conf

    echo "    <IfModule mod_proxy.c>
        SSLProxyEngine On
        SSLProxyVerify none
        SSLProxyCheckPeerCN off
        SSLProxyCheckPeerName off
        SSLProxyCheckPeerExpire off

        ProxyRequests On
        <Proxy *>
            AddDefaultCharset off
            Order deny,allow
            Allow from all
        </Proxy>

        ProxyVia On

        <IfModule mod_cache_disk.c>
            CacheRoot ${_cache_dir}
            CacheIgnoreCacheControl On
            CacheEnable disk /
            CacheEnable disk http://
            CacheDirLevels 2
            CacheDirLength 1
            CacheMaxFileSize 256000000
        </IfModule>
    </IfModule>
</VirtualHost>" >> /etc/apache2/sites-available/proxy.conf

    a2ensite proxy || return $?
    # Due to 'ssl' module, using restart rather than reload
    _info "reloading ..."
    service apache2 reload
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
    local _sever_host="${3:-`hostname -f`}"
    local _keytab_file="${4}"   # /etc/security/keytabs/HTTP.service.keytab
    local _ssl_ca_file="${5}"   # /var/tmp/share/cert/rootCA_standalone.crt

    [ -z "${_redirect}" ] && return 1
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

    # How to check loaded modules: apache2ctl -M
    apt-get install -y apache2 apache2-utils libapache2-mod-auth-kerb || return $?
    a2enmod proxy headers proxy_http proxy_connect proxy_wstunnel ssl rewrite auth_kerb || return $?

    grep -i "^Listen ${_port}" /etc/apache2/ports.conf || echo "Listen ${_port}" >> /etc/apache2/ports.conf

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
" > ${_conf}

    # Proxy/Reverse Proxy related settings
    echo "
    #connectiontimeout=5 timeout=90 retry=0
    ProxyPass / ${_redirect%/}/ nocanon
    ProxyPassReverse / ${_redirect%/}/
    #ProxyRequests Off
    #ProxyPreserveHost On
" >> ${_conf}

    # If this apache uses https (if server.key and cert exists)
    if [ -s /etc/apache2/ssl/server.key ]; then
    echo "
    SSLEngine on
    SSLCertificateFile /etc/apache2/ssl/server.crt
    SSLCertificateKeyFile /etc/apache2/ssl/server.key
    RequestHeader set X-Forwarded-Proto https
" >> ${_conf}
    fi

    if [ -n "${_keytab_file}" ] && [ ! -s "${_keytab_file}" ]; then
        _log "INFO" "No HTTP keytab: ${_keytab_file}"
        echo "    kadmin -p admin@\${_realm} -q 'add_principal -randkey HTTP/${_sever_host}'
    kadmin -p admin@\${_realm} -q "xst -k ${_keytab_file} HTTP/`hostname -f`"
    # If freeIPA, after 'kinit admin':
    ipa-getkeytab -s node-freeipa.standalone.localdomain -p \"HTTP/${_sever_host}\" -k ${_keytab_file}
    chmod a+r ${_keytab_file}"
    elif [ -s "${_keytab_file}" ]; then
        # http://www.microhowto.info/howto/configure_apache_to_use_kerberos_authentication.html
        #local _realm="`sed -n -e 's/^ *default_realm *= *\b\(.\+\)\b/\1/p' /etc/krb5.conf`"
        local _realm="`klist -kt ${_keytab_file} | grep -m1 -oP '@.+' | sed 's/@//'`"
        echo "    <Location />
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
" >> ${_conf}
        # @see: https://httpd.apache.org/docs/2.4/rewrite/intro.html & https://httpd.apache.org/docs/2.4/rewrite/flags.html
    fi

    # TODO: https://stackoverflow.com/questions/7635380/apache-ssl-client-certificate-ldap-authorizations
    if [ -s "${_ssl_ca_file}" ]; then
        echo "
    SSLProxyEngine On
    SSLProxyVerify none
    SSLProxyCheckPeerCN off
    SSLProxyCheckPeerName off
    #SSLProxyCheckPeerExpire off

    SSLOptions +StdEnvVars
    SSLVerifyClient require
    SSLCACertificateFile ${_ssl_ca_file}
    # set header to upstream, SSL_CLIENT_S_DN_CN can change to use other identifiers
    RequestHeader set X-SSO-USER \"%{SSL_CLIENT_S_DN_CN}\"
" >> ${_conf}
    fi

    echo "</VirtualHost>" >> ${_conf}

    a2ensite rproxy${_port} || return $?
    # Due to 'ssl' module, using restart rather than reload
    _info "reloading ..."
    service apache2 reload
}

function f_ssh_setup() {
    local __doc__="Create a private/public keys and setup authorized_keys ssh config & permissions on host"
    which ssh-keygen &>/dev/null || return $?

    if [ ! -e $HOME/.ssh/id_rsa ]; then
        ssh-keygen -f $HOME/.ssh/id_rsa -q -N "" || return 11
    fi

    if [ ! -e $HOME/.ssh/id_rsa.pub ]; then
        ssh-keygen -y -f $HOME/.ssh/id_rsa > $HOME/.ssh/id_rsa.pub || return 12
    fi

    _key="`cat $HOME/.ssh/id_rsa.pub | awk '{print $2}'`"
    grep "$_key" $HOME/.ssh/authorized_keys &>/dev/null
    if [ $? -ne 0 ] ; then
        cat $HOME/.ssh/id_rsa.pub >> $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys
        [ $? -ne 0 ] && return 13
    fi

    if [ ! -e $HOME/.ssh/config ]; then
        echo "Host node* *.localdomain
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
  User root" > $HOME/.ssh/config
    fi

    # If current user isn't 'root', copy this user's ssh keys to root
    if [ ! -e /root/.ssh/id_rsa ]; then
        mkdir /root/.ssh &>/dev/null
        cp $HOME/.ssh/id_rsa /root/.ssh/id_rsa
        chmod 600 /root/.ssh/id_rsa
        chown -R root:root /root/.ssh
    fi

    # To make 'ssh root@localhost' work
    grep -q "^`cat $HOME/.ssh/id_rsa.pub`" /root/.ssh/authorized_keys || echo "`cat $HOME/.ssh/id_rsa.pub`" >> /root/.ssh/authorized_keys

    if [ -d ${_WORK_DIR%/} ] && [ ! -f ${_WORK_DIR%/}/.ssh/authorized_keys ]; then
        [ ! -d ${_WORK_DIR%/}/.ssh ] && mkdir -m 700 ${_WORK_DIR%/}/.ssh
        ln -s /root/.ssh/authorized_keys ${_WORK_DIR%/}/.ssh/authorized_keys
    fi
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
        if grep -qi 'Ubuntu 18\.' /etc/issue.net; then
            apt-get remove -y docker docker-engine docker.io containerd runc || return $?
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
            apt-key fingerprint 0EBFCD88 || return $?
            add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
            apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io
        else
            # Old (14.04 and 16.04) way
            apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D || _info "Did not add key for docker"
            grep -q "deb https://apt.dockerproject.org/repo" /etc/apt/sources.list.d/docker.list || echo "deb https://apt.dockerproject.org/repo ubuntu-`cat /etc/lsb-release | grep CODENAME | cut -d= -f2` main" >> /etc/apt/sources.list.d/docker.list
            apt-get update && apt-get purge lxc-docker*; apt-get install docker-engine -y
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
        iptables -P INPUT ACCEPT;iptables -P FORWARD ACCEPT;iptables -P OUTPUT ACCEPT;iptables -t nat -F;iptables -t mangle -F;iptables -F;iptables -X
        iptables-save > /etc/iptables.up.rules
        #which docker &>/dev/null && service docker restart
    fi
}

function f_vnc_setup() {
    local __doc__="Install X and VNC Server. NOTE: this uses about 400MB space"
    # https://www.digitalocean.com/community/tutorials/how-to-install-and-configure-vnc-on-ubuntu-16-04
    local _user="${1:-vncuser}"
    local _vpass="${2:-${_user}}"
    local _pass="${3:-${_user}}"
    local _portXX="${4:-"10"}"

    if ! which apt-get &>/dev/null; then
        _warn "No apt-get"
        return 1
    fi

    if ! id -u $_user &>/dev/null; then
        f_useradd "$_user" "$_pass" || return $?
    fi

    f_chrome
    apt-get install -y xfce4 xfce4-goodies tightvncserver autocutsel
    # TODO: also disable screensaver and sleep (eg: /home/hajime/.xscreensaver
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

    local _host_ip="`hostname -I | cut -d" " -f1`"
    #echo "TightVNC client: https://www.tightvnc.com/download.php"
    echo "START VNC:
    su - $_user -c 'vncserver -geometry 1600x960 -depth 16 :${_portXX}'
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
    local _pwd="$2"
    local _copy_ssh_config="$3"

    if id -u $_user &>/dev/null; then
        _info "$_user already exists. Skipping useradd command..."
    else
        # should specify home directory just in case?
        useradd -d "/home/$_user/" -s `which bash` -p $(echo "$_pwd" | openssl passwd -1 -stdin) "$_user"
        mkdir "/home/$_user/" && chown "$_user":"$_user" "/home/$_user/"
    fi

    if _isYes "$_copy_ssh_config"; then
        if [ ! -f ${HOME%/}/.ssh/id_rsa ]; then
            _error "${HOME%/}/.ssh/id_rsa does not exist. Not copying ssh configs ..."
            return 1
        fi

        if [ ! -d "/home/$_user/" ]; then
            _error "No /home/$_user/ . Not copying ssh configs ..."
            return 1
        fi

        mkdir "/home/$_user/.ssh" && chown "$_user":"$_user" "/home/$_user/.ssh"
        cp ${HOME%/}/.ssh/id_rsa* "/home/$_user/.ssh/"
        cp ${HOME%/}/.ssh/config "/home/$_user/.ssh/"
        cp ${HOME%/}/.ssh/authorized_keys "/home/$_user/.ssh/"
        chown "$_user":"$_user" /home/$_user/.ssh/*
        chmod 600 "/home/$_user/.ssh/id_rsa"
    fi
}

function f_dnsmasq() {
    local __doc__="Install and set up dnsmasq"
    local _how_many="${1-$r_NUM_NODES}"
    local _start_from="${2-$r_NODE_START_NUM}"
    local _domain_suffix="${3:-${g_DOMAIN_SUFFIX:-".localdomian"}}"

    # TODO: If Ubuntu 18.04 may want to stop systemd-resolved
    #sudo systemctl stop systemd-resolved
    #sudo systemctl disable systemd-resolved
    apt-get -y install dnsmasq || return $?

    # For Ubuntu 18.04 name resolution slowness (ssh and sudo too).
    # Also local hostname needs to be resolved @see: https://linuxize.com/post/how-to-change-hostname-on-ubuntu-18-04/
    grep -q '^no-resolv' /etc/dnsmasq.conf || echo 'no-resolv' >> /etc/dnsmasq.conf
    grep -q '^server=1.1.1.1' /etc/dnsmasq.conf || echo 'server=1.1.1.1' >> /etc/dnsmasq.conf
    #grep -q '^domain-needed' /etc/dnsmasq.conf || echo 'domain-needed' >> /etc/dnsmasq.conf
    #grep -q '^bogus-priv' /etc/dnsmasq.conf || echo 'bogus-priv' >> /etc/dnsmasq.conf
    grep -q '^local=' /etc/dnsmasq.conf || echo 'local=/'${_domain_suffix#.}'/' >> /etc/dnsmasq.conf
    #grep -q '^expand-hosts' /etc/dnsmasq.conf || echo 'expand-hosts' >> /etc/dnsmasq.conf
    #grep -q '^domain=' /etc/dnsmasq.conf || echo 'domain='${g_DOMAIN_SUFFIX#.} >> /etc/dnsmasq.conf
    grep -q '^addn-hosts=' /etc/dnsmasq.conf || echo 'addn-hosts=/etc/banner_add_hosts' >> /etc/dnsmasq.conf
    grep -q '^resolv-file=' /etc/dnsmasq.conf || (echo 'resolv-file=/etc/resolv.dnsmasq.conf' >> /etc/dnsmasq.conf; echo 'nameserver 1.1.1.1' > /etc/resolv.dnsmasq.conf)

    touch /etc/banner_add_hosts || return $?
    chmod 664 /etc/banner_add_hosts
    which docker &>/dev/null && chown root:docker /etc/banner_add_hosts

    if [ -n "$_how_many" ]; then
        f_dnsmasq_banner_reset "$_how_many" "$_start_from" || return $?
    fi

    # Not sure if this is still needed
    if [ -d /etc/docker ] && [ ! -f /etc/docker/daemon.json ]; then
        local _docker_bridge_net="$(docker inspect bridge | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['IPAM']['Config'][0]['Subnet'])" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')"
        if [ -n "${_docker_bridge_net}" ]; then
            echo '{
    "dns": ["'${_docker_bridge_net}.1'", "1.1.1.1"]
}' > /etc/docker/daemon.json
            _warn "daemon.json updated. 'systemctl daemon-reload && service docker restart' required"
        fi
    fi

    # @see https://bugs.launchpad.net/ubuntu/+source/systemd/+bug/1624320
    if [ -L /etc/resolv.conf ] && grep -q '^nameserver 127.0.0.53' /etc/resolv.conf; then
        systemctl disable systemd-resolved || return $?
        rm -f /etc/resolv.conf
        echo 'nameserver 127.0.0.1' > /etc/resolv.conf
        _warn "systemctl disable systemd-resolved was run. Please reboot"
        #reboot
    fi
}

function f_dnsmasq_banner_reset() {
    local __doc__="Regenerate /etc/banner_add_hosts"
    local _how_many="${1-$r_NUM_NODES}"             # Or hostname
    local _start_from="${2-$r_NODE_START_NUM}"
    local _ip_prefix="${3-$r_DOCKER_NETWORK_ADDR}"  # Or exact IP address
    local _remote_dns_host="${4}"
    local _remote_dns_user="${5:-$USER}"

    local _node="${r_NODE_HOSTNAME_PREFIX-$g_NODE_HOSTNAME_PREFIX}"
    local _domain="${r_DOMAIN_SUFFIX-$g_DOMAIN_SUFFIX}"
    local _base="${g_DOCKER_BASE}:$_os_ver"

    local _docker0="`f_docker_ip`"
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
            echo "$_docker0     ${r_DOCKER_PRIVATE_HOSTNAME}${_domain} ${r_DOCKER_PRIVATE_HOSTNAME}" > /tmp/banner_add_hosts
        else
            grep -vE "$_docker0|${r_DOCKER_PRIVATE_HOSTNAME}${_domain}" /tmp/banner_add_hosts > /tmp/banner
            echo "$_docker0     ${r_DOCKER_PRIVATE_HOSTNAME}${_domain} ${r_DOCKER_PRIVATE_HOSTNAME}" >> /tmp/banner
            cat /tmp/banner > /tmp/banner_add_hosts
        fi
    fi

    if ! [[ "$_how_many" =~ ^[0-9]+$ ]]; then
        local _hostname="$_how_many"
        local _ip_address="${_ip_prefix}"
        local _shortname="`echo "${_hostname}" | cut -d"." -f1`"
        grep -vE "${_hostname}|${_ip_address}" /tmp/banner_add_hosts > /tmp/banner
        echo "${_ip_address}    ${_hostname} ${_shortname}" >> /tmp/banner
        cat /tmp/banner > /tmp/banner_add_hosts
    else
        for _n in `_docker_seq "$_how_many" "$_start_from"`; do
            local _hostname="${_node}${_n}${_domain}"
            local _ip_address="${_ip_prefix%\.}.${_n}"
            local _shortname="${_node}${_n}"
        grep -vE "${_hostname}|${_ip_address}" /tmp/banner_add_hosts > /tmp/banner
            echo "${_ip_address}    ${_hostname} ${_shortname}" >> /tmp/banner
            cat /tmp/banner > /tmp/banner_add_hosts
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
        _if="$(ifconfig | grep `hostname -i` -B 1 | grep -oE '^e[^ ]+')"
    fi
    # https://pupli.net/2018/01/24/setup-pptp-server-on-ubuntu-16-04/
    apt-get install pptpd ppp pptp-linux -y || return $?
    systemctl enable pptpd
    grep -q '^logwtmp' /etc/pptpd.conf || echo -e "logwtmp" >> /etc/pptpd.conf
    grep -q '^localip' /etc/pptpd.conf || echo -e "localip ${_vpn_net}.1\nremoteip ${_vpn_net}.100-200" >> /etc/pptpd.conf
    # NOTE: not setting up DNS by editing pptpd-options, and net.ipv4.ip_forward=1 should have been done

    if ! id -u $_user &>/dev/null; then
        f_useradd "$_user" "$_pass" || return $?
    fi
    grep -q "^${_user}" /etc/ppp/chap-secrets || echo "${_user} * ${_pass} *" >> /etc/ppp/chap-secrets

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

    local _vpn_net="10.0.1"
    if [ -z "${_if}" ]; then
        _if="$(ifconfig | grep `hostname -i` -B 1 | grep -oE '^e[^ ]+')"
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
    rightauth=psk' > /etc/ipsec.conf || return $?

    if [ ! -e /etc/ipsec.secrets.orig ]; then
        cp -p /etc/ipsec.secrets /etc/ipsec.secrets.orig || return $?
    else
        cp -p /etc/ipsec.secrets /etc/ipsec.secrets.$(date +"%Y%m%d%H%M%S")
    fi
    echo ': PSK "longlongpassword"' > /etc/ipsec.secrets

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
  pppoptfile = /etc/ppp/options.l2tpd.lns   ; * ppp options file' > /etc/xl2tpd/xl2tpd.conf

    if [ -f /etc/ppp/options.l2tpd.lns ]; then
        cp -p /etc/ppp/options.l2tpd.lns /etc/ppp/options.l2tpd.lns.$(date +"%Y%m%d%H%M%S")
    fi
    echo 'name l2tp
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
nodefaultroute
lock
nobsdcomp
mtu 1100
mru 1100
logfile /var/log/xl2tpd.log' > /etc/ppp/options.l2tpd.lns

    if ! id -u $_user &>/dev/null; then
        f_useradd "$_user" "$_pass" || return $?
    fi
    grep -q "^${_user}" /etc/ppp/chap-secrets || echo "${_user} * ${_pass} *" >> /etc/ppp/chap-secrets

    # NOTE: net.ipv4.ip_forward=1 should have been set already
    #iptables -t nat -A POSTROUTING -s ${_vpn_net}.0/24 -o ${_if} -j MASQUERADE # make sure interface is correct
    #iptables -A FORWARD -p tcp --syn -s ${_vpn_net}.0/24 -j TCPMSS --set-mss 1356

    systemctl restart strongswan
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
WantedBy=multi-user.target' > /etc/systemd/system/vpnserver.service || return $?
    systemctl daemon-reload
    systemctl enable vpnserver.service
    systemctl start vpnserver.service || return $?

    # TODO
    return 1
}

function f_tunnel() {
    local __doc__="TODO: Create a tunnel between this host and a target host. Requires ppp and password-less SSH"
    local _connecting_to="$1" # Remote host IP
    local _container_network_to="$2" # ex: 172.17.140.0 or 172.17.140.
    local _container_network_from="${3-${r_DOCKER_NETWORK_ADDR%.}.0}"
    local _container_net_mask="${4-24}"
    local _outside_nic_name="${5-ens3}"

    # NOTE: normally below should be OK but doesn't work with our VMs in the lab
    #[ -z "$_connecting_from" ] && _connecting_from="`hostname -i`"
    local _connecting_from="`ifconfig ${_outside_nic_name} | grep -oP 'inet addr:\d+\.\d+\.\d+\.\d+' | cut -d":" -f2`"

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
            break;
        fi
    done
    if [ -z "$_tunnel_nic_from_ip" ];then
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
    local __doc__="TODO: Install KVM on Ubuntu (16.04) host"
    local _virt_user="${1-"virtuser"}"
    local _virt_pass="${2:-"${_virt_user}"}"
    # @see: https://computingforgeeks.com/use-virt-manager-as-non-root-user/

    apt-get -y install qemu-kvm libvirt-bin virtinst bridge-utils libosinfo-bin libguestfs-tools virt-top virt-manager qemu-system
    if ! grep -qw "vhost_ned" /etc/modules; then
        modprobe vhost_net
        echo vhost_net >> /etc/modules
        _info "You may need to reboot before using KVM."
    fi

    if [ -n "${_virt_user}" ] && ! id -u ${_virt_user} &>/dev/null; then
        f_useradd "${_virt_user}" "${_virt_pass}" || return $?

        local _group="$(getent group | grep -Ew '^(libvirt|libvirtd)' | cut -d":" -f1)"
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
    mkdir /media/cdrom; mount /dev/cdrom /media/cdrom && cd /media/cdrom && cp VMwareTools-*.tar.gz /tmp/ && cd /tmp/ && tar xzvf VMwareTools-*.tar.gz && cd vmware-tools-distrib/ && ./vmware-install.pl -d
}

function f_host_performance() {
    local __doc__="Performance related changes on the host. Eg: Change kernel parameters on Docker Host (Ubuntu)"
    grep -q '^vm.swappiness' /etc/sysctl.conf || echo "vm.swappiness = 0" >> /etc/sysctl.conf
    sysctl -w vm.swappiness=0

    grep -q '^net.core.somaxconn' /etc/sysctl.conf || echo "net.core.somaxconn = 16384" >> /etc/sysctl.conf
    sysctl -w net.core.somaxconn=16384

    # also ip forwarding as well
    grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf || echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -w net.ipv4.ip_forward=1
    grep -q '^net.ipv4.conf.all.forwarding' /etc/sysctl.conf || echo "net.ipv4.conf.all.forwarding = 1" >> /etc/sysctl.conf
    sysctl -w net.ipv4.conf.all.forwarding=1
    grep -q '^net.bridge.bridge-nf-call-iptables' /etc/sysctl.conf || echo "net.bridge.bridge-nf-call-iptables = 0" >> /etc/sysctl.conf
    sysctl -w net.bridge.bridge-nf-call-iptables=0

    grep -q '^kernel.panic' /etc/sysctl.conf || echo "kernel.panic = 20" >> /etc/sysctl.conf
    sysctl -w kernel.panic=60
    grep -q '^kernel.panic_on_oops' /etc/sysctl.conf || echo "kernel.panic_on_oops = 1" >> /etc/sysctl.conf
    sysctl -w kernel.panic_on_oops=1

    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    echo never > /sys/kernel/mm/transparent_hugepage/defrag

    [ ! -s /etc/rc.lcoal ] && echo -e '#!/bin/bash\nexit 0' > /etc/rc.local

    if grep -q '^echo never > /sys/kernel/mm/transparent_hugepage/enabled' /etc/rc.local; then
        sed -i.bak '/^exit 0/i echo never > /sys/kernel/mm/transparent_hugepage/enabled\necho never > /sys/kernel/mm/transparent_hugepage/defrag\n' /etc/rc.local
    fi
    chmod a+x /etc/rc.local
}

function f_install_packages() {
    which apt-get &>/dev/null || return $?
    apt-get update || return $?
    apt-get -y install sysv-rc-conf     # Not stopping if error because Ubuntu 18 does not have this
    apt-get -y install python ntpdate curl wget sshfs tcpdump sharutils unzip postgresql-client libxml2-utils \
        expect netcat nscd mysql-client libmysql-java ppp at resolvconf
}

function f_sshfs_mount() {
    local __doc__="Mount sshfs. May need root priv"
    local _remote_src="${1}"
    local _local_dir="${2}"

    if mount | grep -qw "${_local_dir%/}"; then
        _info "Un-mounting ${_local_dir%/} ..."; sleep 3
        umount -f "${_local_dir%/}" || return $?
    fi
    if [ ! -d "${_local_dir}" ]; then
        mkdir -p -m 777 "${_local_dir}" || return $?
    fi

    _info "Mounting ${_remote_src%/}/ to ${_local_dir} ..."
    _info "If it asks password, please stop and use ssh-copy-id."
    local _cmd="sshfs -o allow_other,uid=0,gid=0,umask=002,reconnect,follow_symlinks ${_remote_src%/}/ ${_local_dir%/}"
    eval ${_cmd} || return $?
    [ ! -s /etc/rc.lcoal ] && echo -e '#!/bin/bash\nexit 0' > /etc/rc.local
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
    local _pid="`lsof -ti:$_local_port`"
    if [ -n "$_pid" ] ; then
        _warn "Local port $_local_port is already used by PID $_pid."
        if _isYes "$_kill_process" ; then
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

function f_add_cert() {
    local _crt_file="$1"
    local _file_name="$(basename ${_crt_file})"
    # NOTE: /usr/share/ca-certificates didn't work
    local _ca_dir="/usr/local/share/ca-certificates/extra"
    if [ -s ${_ca_dir%/}/${_file_name} ]; then
        _info "${_ca_dir%/}/${_file_name} exists."
        return 0
    fi
    if [ ! -d ${_ca_dir%/} ]; then
        mkdir -m 755 -p ${_ca_dir%/} || return $?
    fi
    cp -v "${_crt_file}" ${_ca_dir%/}/ || return $?
    update-ca-certificates
}

function f_kdc_install() {
    local __doc__="Install KDC server packages on Ubuntu (may take long time)"
    local _realm="${1:-$g_KDC_REALM}"
    local _password="${2:-${g_DEFAULT_PASSWORD:-"hadoop"}}"
    local _server="${3:-`hostname -i | awk '{print $1}'`}"

    if [ -z "${_realm}" ]; then
        _realm="`hostname -s`" && _realm="${_realm^^}"
        _info "Using ${_realm} for realm"
    fi
    if [ -z "${_server}" ]; then
        _error "No server IP/name for KDC"
        return 1
    fi
    if [ ! `which apt-get` ]; then
        _warn "No apt-get"
        return 1
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y krb5-kdc krb5-admin-server libapache2-mod-auth-kerb || return $?

    if [ -s /etc/krb5kdc/kdc.conf ] && [ -s /var/lib/krb5kdc/principal_${_realm} ]; then
        if grep -qE '^\s*'${_realm}'\b' /etc/krb5kdc/kdc.conf; then
            _info "Realm: ${_realm} may already exit in /etc/krb5kdc/kdc.conf. Not try creating..."
            return 0
        fi
    fi
    echo '    '${_realm}' = {
        database_name = /var/lib/krb5kdc/principal_'${_realm}'
        admin_keytab = FILE:/etc/krb5kdc/kadm5_'${_realm}'.keytab
        acl_file = /etc/krb5kdc/kadm5_'${_realm}'.acl
        key_stash_file = /etc/krb5kdc/stash_'${_realm}'
        kdc_ports = 750,88
        max_life = 10h 0m 0s
        max_renewable_life = 7d 0h 0m 0s
        master_key_type = des3-hmac-sha1
        supported_enctypes = aes256-cts:normal arcfour-hmac:normal des3-hmac-sha1:normal des-cbc-crc:normal des:normal des:v4 des:norealm des:onlyrealm des:afs3
        default_principal_flags = +preauth
    }
'  > /tmp/f_kdc_install_on_host_kdc_$$.tmp
    sed -i "/\[realms\]/r /tmp/f_kdc_install_on_host_kdc_$$.tmp" /etc/krb5kdc/kdc.conf

    # KDC process seems to use default_realm, and sed needs to escape + somehow
    cp -p /etc/krb5.conf /etc/krb5.conf.$(date +"%Y%m%d%H%M%S") || return $?

    echo '[libdefaults]
  default_realm = '${_realm}'
  dns_lookup_realm = false
  dns_lookup_kdc = false

[realms]
  '${_realm}' = {
   kdc = '${_server}'
   admin_server = '${_server}'
 }
' > /etc/krb5.conf

    kdb5_util create -r ${_realm} -s -P ${_password} || return $?  # or krb5_newrealm
    mv /etc/krb5kdc/kadm5_${_realm}.acl /etc/krb5kdc/kadm5_${_realm}.orig &>/dev/null
    echo '*/admin *' > /etc/krb5kdc/kadm5_${_realm}.acl
    service krb5-kdc restart && service krb5-admin-server restart
    sleep 3
    kadmin.local -r ${_realm} -q "add_principal -pw ${_password} admin/admin@${_realm}"
    # AMBARI-24869
    kadmin.local -r ${_realm} -q "add_principal -pw ${_password} kadmin/${_server}@${_realm}"
    kadmin.local -r ${_realm} -q "add_principal -pw ${_password} kadmin/admin@${_realm}" &>/dev/null    # this should exist already
    _info "Testing ..."
    kadmin -p admin/admin@${_realm} -w "${_password}" -q "get_principal admin/admin@${_realm}"
}

function f_gen_keytab() {
    local __doc__="Generate keytab(s). NOTE: NOT for FreeIPA"
    local _principal="${1}" # HTTP/`hosntame -f`@REALM
    local _kadmin_usr="${2:-"admin/admin"}"
    local _kadmin_pwd="${3:-${g_DEFAULT_PASSWORD:-"hadoop"}}"
    local _keytab_dir="${4:-"/etc/security/keytabs"}"
    local _delete_first="${5-${_DELETE_FIRST}}"    # default is just creating keytab if already exists
    local _tmp_dir="${_WORK_DIR}"

    # This function will create the following keytabs:
    # ${_tmp_dir%/}/keytabs/${_user}.headless.keytab
    # ${_keytab_dir%/}/${_user}.service.keytab (contains both headless and service)
    local _service="${_principal}"
    local _host="`hostname -f`"
    local _realm="`sed -n -e 's/^ *default_realm *= *\b\(.\+\)\b/\1/p' /etc/krb5.conf`"
    if [[ "${_principal}" =~ ^([^ @/]+)/([^ @]+)$ ]]; then
        [ -n "${BASH_REMATCH[1]}" ] && _service="${BASH_REMATCH[1]}"
        [ -n "${BASH_REMATCH[2]}" ] && _host="${BASH_REMATCH[2]}"
    elif [[ "${_principal}" =~ ^([^ @/]+)/([^ @]+)@([^ ]+)$ ]]; then
        [ -n "${BASH_REMATCH[1]}" ] && _service="${BASH_REMATCH[1]}"
        [ -n "${BASH_REMATCH[2]}" ] && _host="${BASH_REMATCH[2]}"
        [ -n "${BASH_REMATCH[3]}" ] && _realm="${BASH_REMATCH[3]}"    # NOT using at this moment
    fi

    if [ ! -d "${_tmp_dir%/}/keytabs" ]; then
        mkdir -p ${_tmp_dir%/}/keytabs || return $?
    fi

    if [[ "${_delete_first}" =~ ^(y|Y) ]]; then
        _log "WARN" "Deleting principals ${_service} ${_service}/${_host} ..."; sleep 3
        kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "delete_principal -force ${_service}@${_realm}"
        kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "delete_principal -force ${_service}/${_host}@${_realm}"
        kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "delete_principal -force ${_principal}"

        # if successfully deleted, remove keytabs too
        if [ -s "${_tmp_dir%/}/keytabs/${_service}.headless.keytab" ]; then
            _log "WARN" "Removing ${_tmp_dir%/}/keytabs/${_service}.headless.keytab ..."; sleep 3
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
        _log "INFO" "Moving ${_keytab_dir%/}/${_service}.service.keytab to .orig ..."; sleep 1
        mv "${_keytab_dir%/}/${_service}.service.keytab" "${_keytab_dir%/}/${_service}.service.keytab.orig" || return $?
    fi
    kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "xst -k ${_keytab_dir%/}/${_service}.service.keytab ${_service}/${_host}" || return $?

    # backup
    if [ -s "${_keytab_dir%/}/${_service}.combined.keytab" ] && [ ! -f "${_keytab_dir%/}/${_service}.combined.keytab.orig" ]; then
        _log "INFO" "Moving ${_keytab_dir%/}/${_service}.combined.keytab to .orig ..."; sleep 1
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


function p_basic_setup() {
    _log "INFO" "Executing f_ssh_setup"
    f_ssh_setup || return $?

    if which apt-get &>/dev/null; then
        # NOTE: psql (postgresql-client) is required
        _log "INFO" "Executing apt-get install packages"
        f_install_packages || return $?
        #mailutils postfix htop
        _log "INFO" "Executing f_docker_setup"
        f_docker_setup || return $?
        _log "INFO" "Executing f_sysstat_setup"
        f_sysstat_setup
        _log "INFO" "Executing f_apache_proxy"
        f_apache_proxy
        _log "INFO" "Executing f_socks5_proxy"
        f_socks5_proxy
        _log "INFO" "Executing f_shellinabox"
        f_shellinabox

        _log "INFO" "Executing f_dnsmasq"
        f_dnsmasq || return $?
    fi

    _log "INFO" "Executing f_host_misc"
    f_host_misc
    
    _log "INFO" "Executing f_host_performance"
    f_host_performance

    if [ -s ${_WORK_DIR%/}/cert/rootCA_standalone.crt ]; then
        _log "INFO" "Trusting rootCA_standalone.crt"
        f_add_cert
    fi
}






























### Utility type functions #################################################
_YES_REGEX='^(y|Y)'
_IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
_IP_RANGE_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(/[0-3]?[0-9])$'
_HOSTNAME_REGEX='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
_URL_REGEX='(https?|ftp|file|svn)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'
_TEST_REGEX='^\[.+\]$'

_WORK_DIR="/var/tmp/share"

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
function _log() {
    if [ -n "${g_LOG_FILE_PATH}" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" | tee -a ${g_LOG_FILE_PATH} 1>&2
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" 1>&2
    fi
}
function _echo() {
    local _msg="$1"
    local _stderr="$2"

    if _isYes "$_stderr" ; then
        echo -e "$_msg" 1>&2
    else
        echo -e "$_msg"
    fi
}
function _ask() {
    local _question="$1"
    local _default="$2"
    local _var_name="$3"
    local _is_secret="$4"
    local _is_mandatory="$5"
    local _validation_func="$6"

    local _default_orig="$_default"
    local _cmd=""
    local _full_question="${_question}"
    local _trimmed_answer=""
    local _previous_answer=""

    if [ -z "${_var_name}" ]; then
        __LAST_ANSWER=""
        _var_name="__LAST_ANSWER"
    fi

    # currently only checking previous value of the variable name starting with "r_"
    if [[ "${_var_name}" =~ ^r_ ]]; then
        _previous_answer=`_trim "${!_var_name}"`
        if [ -n "${_previous_answer}" ]; then _default="${_previous_answer}"; fi
    fi

    if [ -n "${_default}" ]; then
        if _isYes "$_is_secret" ; then
            _full_question="${_question} [*******]"
        else
            _full_question="${_question} [${_default}]"
        fi
    fi

    if _isYes "$_is_secret" ; then
        local _temp_secret=""

        while true ; do
            read -p "${_full_question}: " -s "${_var_name}"; echo ""

            if [ -z "${!_var_name}" -a -n "${_default}" ]; then
                eval "${_var_name}=\"${_default}\""
                break;
            else
                read -p "${_question} (again): " -s "_temp_secret"; echo ""

                if [ "${!_var_name}" = "${_temp_secret}" ]; then
                    break;
                else
                    echo "1st value and 2nd value do not match."
                fi
            fi
        done
    else
        read -p "${_full_question}: " "${_var_name}"

        _trimmed_answer=`_trim "${!_var_name}"`

        if [ -z "${_trimmed_answer}" -a -n "${_default}" ]; then
            # if new value was only space, use original default value instead of previous value
            if [ -n "${!_var_name}" ]; then
                eval "${_var_name}=\"${_default_orig}\""
            else
                eval "${_var_name}=\"${_default}\""
            fi
        else
            eval "${_var_name}=\"${_trimmed_answer}\""
        fi
    fi

    # if empty value, check if this is a mandatory field.
    if [ -z "${!_var_name}" ]; then
        if _isYes "$_is_mandatory" ; then
            echo "'${_var_name}' is a mandatory parameter."
            _ask "$@"
        fi
    else
        # if not empty and if a validation function is given, use function to check it.
        if _isValidateFunc "$_validation_func" ; then
            $_validation_func "${!_var_name}"
            if [ $? -ne 0 ]; then
                _ask "Given value does not look like correct. Would you like to re-type?" "Y"
                if _isYes; then
                    _ask "$@"
                fi
            fi
        fi
    fi
}
function _backup() {
    local __doc__="Backup the given file path into ${g_BACKUP_DIR} or /tmp."
    local _file_path="$1"
    local _force="$2"
    local _file_name="`basename $_file_path`"
    local _new_file_name=""
    local _backup_dir="${g_BACKUP_DIR:-"/tmp"}"

    if [ ! -e "$_file_path" ]; then
        _warn "$FUNCNAME: Not taking a backup as $_file_path does not exist."
        return 1
    fi

    local _mod_dt="`stat -c%y $_file_path`"
    local _mod_ts=`date -d "${_mod_dt}" +"%Y%m%d-%H%M%S"`

    _new_file_name="${_file_name}_${_mod_ts}"
    if ! _isYes "$_force"; then
        if [ -e "${_backup_dir%/}/${_new_file_name}" ]; then
            _info "$_file_name has been already backed up. Skipping..."
            return 0
        fi
    fi

    _makeBackupDir
    cp -p ${_file_path} ${_backup_dir%/}/${_new_file_name} || return $?
}
function _makeBackupDir() {
    local _backup_dir="${g_BACKUP_DIR:-"/tmp"}"
    if [ -n "${_backup_dir}" ] && [ ! -d "${_backup_dir}" ]; then
        mkdir -p -m 700 "${_backup_dir}"
        #[ -n "$SUDO_USER" ] && chown $SUDO_UID:$SUDO_GID ${_backup_dir}
    fi
}
function _isEnoughDisk() {
    local __doc__="Check if entire system or the given path has enough space with GB."
    local _dir_path="${1-/}"
    local _required_gb="$2"
    local _available_space_gb=""

    _available_space_gb=`_freeSpaceGB "${_dir_path}"`

    if [ -z "$_required_gb" ]; then
        echo "${_available_space_gb}GB free space"
        _required_gb=`_totalSpaceGB`
        _required_gb="`expr $_required_gb / 10`"
    fi

    if [ $_available_space_gb -lt $_required_gb ]; then return 1; fi
    return 0
}
function _freeSpaceGB() {
    local __doc__="Output how much space for given directory path."
    local _dir_path="$1"
    if [ ! -d "$_dir_path" ]; then _dir_path="-l"; fi
    df -P --total ${_dir_path} | grep -i ^total | awk '{gb=sprintf("%.0f",$4/1024/1024);print gb}'
}
function _totalSpaceGB() {
    local __doc__="Output how much space for given directory path."
    local _dir_path="$1"
    if [ ! -d "$_dir_path" ]; then _dir_path="-l"; fi
    df -P --total ${_dir_path} | grep -i ^total | awk '{gb=sprintf("%.0f",$2/1024/1024);print gb}'
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

    for i in `seq 1 $_times`; do
      nc -z $_host $_port && return 0
      _info "$_host:$_port is unreachable. Waiting..."
      sleep $_interval
    done
    _warn "$_host:$_port is unreachable."
    return 1
}
function _isYes() {
    # Unlike other languages, 0 is nearly same as True in shell script
    local _answer="$1"

    if [ $# -eq 0 ]; then
        _answer="${__LAST_ANSWER}"
    fi

    if [[ "${_answer}" =~ $_YES_REGEX ]]; then
        #_log "$FUNCNAME: \"${_answer}\" matchs."
        return 0
    elif [[ "${_answer}" =~ $_TEST_REGEX ]]; then
        eval "${_answer}" && return 0
    fi

    return 1
}
function _isCmd() {
    local _cmd="$1"

    if command -v "$_cmd" &>/dev/null ; then
        return 0
    else
        return 1
    fi
}
function _isNotEmptyDir() {
    local _dir_path="$1"

    # If path is empty, treat as eampty
    if [ -z "$_dir_path" ]; then return 1; fi

    # If path is not directory, treat as eampty
    if [ ! -d "$_dir_path" ]; then return 1; fi

    if [ "$(ls -A ${_dir_path})" ]; then
        return 0
    else
        return 1
    fi
}
function _isUrl() {
    local _url="$1"

    if [ -z "$_url" ]; then
        return 1
    fi

    if [[ "$_url" =~ $_URL_REGEX ]]; then
        return 0
    fi

    return 1
}
function _isUrlButNotReachable() {
    local _url="$1"

    if ! _isUrl "$_url" ; then
        return 1
    fi

    if curl --output /dev/null --silent --head --fail "$_url" ; then
        return 1
    fi

    # Return true only if URL is NOT reachable
    return 0
}
function _isValidateFunc() {
    local _function_name="$1"

    # FIXME: not good way
    if [[ "$_function_name" =~ ^_is ]]; then
        typeset -F | grep "^declare -f $_function_name$" &>/dev/null
        return $?
    fi
    return 1
}

# Deprecated: use sed, like for _s in `echo "HDFS MR2 YARN" | sed 's/ /\n/g'`; do echo $_s "Y"; done
function _split() {
    local _rtn_var_name="$1"
    local _string="$2"
    local _delimiter="${3-,}"
    local _original_IFS="$IFS"
    eval "IFS=\"$_delimiter\" read -a $_rtn_var_name <<< \"$_string\""
    IFS="$_original_IFS"
}

function _trim() {
    local _string="$1"
    echo "${_string}" | sed -e 's/^ *//g' -e 's/ *$//g'
}

function _upsert() {
    local __doc__="Modify the given file with given parameter name and value."
    local _file_path="$1"
    local _name="$2"
    local _value="$3"
    local _if_not_exist_append_after="$4"    # This needs to be a line, not search keyword
    local _between_char="${5-=}"
    local _comment_char="${6-#}"
    # NOTE & TODO: Not sure why /\\\&/ works, should be /\\&/ ...
    local _name_esc_sed=`echo "${_name}" | sed 's/[][\.^$*\/"&]/\\\&/g'`
    local _name_esc_sed_for_val=`echo "${_name}" | sed 's/[\/]/\\\&/g'`
    local _name_escaped=`printf %q "${_name}"`
    local _value_esc_sed=`echo "${_value}" | sed 's/[\/]/\\\&/g'`
    local _value_escaped=`printf %q "${_value}"`

    [ ! -f "${_file_path}" ] && return 11
    # Make a backup
    local _file_name="`basename "${_file_path}"`"
    [ ! -f "/tmp/${_file_name}.orig" ] && cp -p "${_file_path}" "/tmp/${_file_name}.orig"

    # If name=value is already set, all good
    grep -qP "^\s*${_name_escaped}\s*${_between_char}\s*${_value_escaped}\b" "${_file_path}" && return 0

    # If name= is already set, replace all with /g
    if grep -qP "^\s*${_name_escaped}\s*${_between_char}" "${_file_path}"; then
        sed -i -r "s/^([[:space:]]*${_name_esc_sed})([[:space:]]*${_between_char}[[:space:]]*)[^${_comment_char} ]*(.*)$/\1\2${_value_esc_sed}\3/g" "${_file_path}"
        return $?
    fi

    # If name= is not set and no _if_not_exist_append_after, just append in the end of line (TODO: it might add extra newline)
    if [ -z "${_if_not_exist_append_after}" ]; then
        echo -e "\n${_name}${_between_char}${_value}" >> ${_file_path}
        return $?
    fi

    # If name= is not set and _if_not_exist_append_after is set, inserting
    if [ -n "${_if_not_exist_append_after}" ]; then
        local _if_not_exist_append_after_sed="`echo "${_if_not_exist_append_after}" | sed 's/[][\.^$*\/"&]/\\\&/g'`"
        sed -i -r "0,/^(${_if_not_exist_append_after_sed}.*)$/s//\1\n${_name_esc_sed_for_val}${_between_char}${_value_esc_sed}/" ${_file_path}
        return $?
    fi
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

    local _line_escaped="`_sed_escape "${_line}"`"
    [ -z "${_line_escaped}" ] && return 1
    local _before_escaped="`_sed_escape "${_before}"`"

    # If no file, create and insert
    if [ ! -s ${_file_path} ]; then
        if [ -n "${_before}" ]; then
            echo -e "${_line}\n${_before}" > ${_file_path}
        else
            echo "${_line}" > ${_file_path}
        fi
    elif grep -qF "${_line}" ${_file_path}; then
        # Would need to escape special chars, so saying "almost"
        _info "(almost) same line exists, skipping..."
        return
    else
        if [ -n "${_before}" ]; then
            sed -i "/^${_before}/i ${_line}" ${_file_path}
        else
            echo -e "\n${_line}" >> ${_file_path}
        fi
    fi
}
