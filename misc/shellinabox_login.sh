#!/usr/bin/env bash
# NOTE: replace _user, _proxy_port, _net_addr with
#   sed -i 's/%xxx%/yyy/g' /usr/local/bin/shellinabox_login

_SERVICE="atscale"
_HOST_IP="`hostname -I | cut -d" " -f1`"
echo "Welcome $USER ! (You logged in ${_HOST_IP})"
echo ""

# If the logged in user is an expected user, show more information.
if [ "$USER" = "%_user%" ]; then
    # Note sure if this env is officially supported, but Ubuntu's 2.19 has this
    if [[ "$SHELLINABOX_URL" =~ \? ]]; then
        _CMD="`python -c 'import os
try:
        from urllib import parse
except ImportError:
        import urlparse as parse
url = os.environ["SHELLINABOX_URL"]
rs = parse.parse_qs(parse.urlsplit(url).query)
_ss_args = ""
_n = ""
for k, v in rs.iteritems():
    if k == "n": _n=v[0]
    if k in ["c", "N"]:
        _ss_args += "-%s " % (k)
    elif k in ["n", "v"]:
        _ss_args += "-%s %s " % (k, v[0])
if len(_ss_args) > 0:
    print("_SS_ARGS=\\"%s\\";_NAME=\\"%s\\"" % (_ss_args, _n))
'`"
        [ -n "${_CMD}" ] && eval "${_CMD}"
    else
        echo "# SSH login to a running container:"
        docker ps --format "{{.Names}}" | grep -E "^(node|${_SERVICE}|cdh|hdp)" | sort | sed "s/^/  ssh root@/g"
        echo ""

        if [ -x /usr/local/bin/setup_standalone.sh ]; then
            echo "# To start a container (setup_standalone.sh -h for help):"
            (docker images --format "{{.Repository}}";docker ps -a --format "{{.Names}}" --filter "status=exited") | grep -E "^${_SERVICE}" | sort | uniq | sed "s/^/  setup_standalone.sh -n /g"
            echo ""
        fi

        echo "# URLs (NOTE: Chrome via proxy or route or VNC is required):"
        for _n in `docker ps --format "{{.Names}}" | grep -E "^(node|${_SERVICE}|cdh|hdp)" | sort`; do
            for _p in 10500 8080 7180; do
                _hostname="$(docker inspect ${_n} | python -c "import sys,json;a=json.loads(sys.stdin.read());print(a[0]['Config']['Hostname'])")"
                # intentionally using different hostname due to HSTS
                if timeout 1 curl -s -f "http://${_n}:${_p}/" &>/dev/null; then
                    echo "  http://${_n}:${_p}/"
                elif timeout 1 curl -s -f -k "https://${_hostname}:${_p}/" &>/dev/null; then
                    echo "  https://${_hostname}:${_p}/"
                fi
            done
        done
        echo ""
    fi

    if nc -z localhost %_proxy_port%; then
        _URL=""; [ -n "${_NAME}" ] && _URL="http://${_NAME}:10500"
        echo "# Start Chrome via proxy to access web UIs:"
        echo "  Mac: open -na \"Google Chrome\" --args --user-data-dir=\$HOME/.chrome_pxy --proxy-server=socks5://${_HOST_IP}:%_proxy_port% ${_URL}"
        echo '  Win: "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" --user-data-dir=%USERPROFILE%\.chrome_pxy --proxy-server=socks5://'${_HOST_IP}':%_proxy_port% '${_URL}
        echo ""
    fi

    if [ -n "%_net_addr%" ]; then
        echo "# Route command examples (root/admin privilege required):"
        echo "  Mac: route add -net %_net_addr%/24 ${_HOST_IP}"
        echo "  Win: route add -net %_net_addr% mask 255.255.255.0 ${_HOST_IP}"
        echo ""
    fi

    _vnc_port="`ps auxwww | sed -n -r 's/^webuser.+Xtightvnc.+rfbport ([0-9]+).+/\1/p'`"
    if [ -n "${_vnc_port}" ]; then
        echo "# Remote desktop access (VNC):"
        echo "  vnc://webuser:webuser@${_HOST_IP}:${_vnc_port}"
        echo ""
    fi

    if [ -n "${_SS_ARGS}" ]; then
        echo ""
        echo "Executing 'setup_standalone.sh ${_SS_ARGS}' ..."
        if eval "setup_standalone.sh ${_SS_ARGS}" && [ -n "${_NAME}" ]; then
            ssh root@${_NAME}
            exit $?
        fi
    fi
fi

if [ -z "$SHLVL" ] || [ "$SHLVL" = "1" ]; then
    /usr/bin/env bash
fi