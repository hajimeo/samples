#!/usr/bin/env bash
# NOTE: replace _user, _proxy_port, _net_addr with
#   sed -i 's/%xxx%/yyy/g' /usr/local/bin/shellinabox_login

echo "Welcome $USER !"
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
        echo "SSH login to a running container:"
        docker ps --format "{{.Names}}" | grep -E "^(node|atscale|cdh|hdp)" | sort | sed "s/^/  ssh root@/g"
        echo ""

        if [ -x /usr/local/bin/setup_standalone.sh ]; then
            echo "To start a container (setup_standalone.sh -h for help):"
            (docker images --format "{{.Repository}}";docker ps -a --format "{{.Names}}" --filter "status=exited") | grep -E "^atscale" | sort | uniq | sed "s/^/  setup_standalone.sh -n /g"
            echo ""
        fi

        echo "URLs (NOTE: need Proxy or Routing by using one of below commands):"
        for _n in `docker ps --format "{{.Names}}" | grep -E "^(node|atscale|cdh|hdp)" | sort`; do for _p in 10500 8080 7180; do if nc -z $_n $_p; then echo "  http://$_n:$_p/"; fi done done
        echo ""
    fi

    if nc -z localhost %_proxy_port%; then
        _URL=""; [ -n "${_NAME}" ] && _URL="${_NAME}:10500"
        echo "If you are using VPN, paste below into *Mac* terminal to access web UIs:"
        echo "  open -na \"Google Chrome\" --args --user-data-dir=\$HOME/.chrome_pxy --proxy-server=socks5://`hostname -I | cut -d" " -f1`:%_proxy_port% ${_URL}"
        echo ""
    fi

    if [ -n "%_net_addr%" ]; then
        echo "If not using VPN, a route command example for Mac:"
        echo "  sudo route add -net %_net_addr% `hostname -I | cut -d" " -f1`"
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