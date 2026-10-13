#!/usr/bin/env bash
# PURPOSE:
#   List of the common commands used after restarting (or after hibernating) m5mac
#

# Currently everytime the Mac sleeps, some services can't be reached until restarted
# If this hostname:8000 and :11435 are not reachable, then restart the services below
_BRIDGE_IP="$(ipconfig getifaddr bridge0)"
if ! curl -sf -m5 -o/dev/null http://${_BRIDGE_IP}:8000/v1/models -H "Authorization: Bearer admin123"; then
    echo "# Restarting omlx on $(hostname) because ${_BRIDGE_IP}:8000 is not reachable" >&2; sleep 2
    /opt/homebrew/bin/brew services restart omlx
fi
if ! curl -sf -m5 -o/dev/null http://${_BRIDGE_IP}:11435/v1/models -H "Authorization: Bearer apfel"; then
    echo "# Restarting apfel on $(hostname) because ${_BRIDGE_IP}:11435 is not reachable" >&2; sleep 2
    /opt/homebrew/bin/brew services restart apfel
    # TODO: Want to use 'fm' but it currently doesn't have --cors option
    #/usr/bin/fm serve --host 0.0.0.0 --port 14345 > /tmp/fm.log 2>&1 &
fi

# zvac-grep
if /opt/homebrew/bin/zg server status | grep -q -w 'ready'; then
    echo "# Stopping zvac-grep on $(hostname) ..." >&2; sleep 2
    /opt/homebrew/bin/zg server off
fi

# For Apple Container k8s
if ! /opt/homebrew/bin/container system status; then
    /opt/homebrew/bin/container system restart; sleep 10
    /opt/homebrew/bin/kubectl proxy --address='0.0.0.0' --port=16445 --accept-hosts='^.*$' &> /tmp/kubectl_proxy_http_16445.out &
fi
# If Kiac (no longer needed with 'container')
#/opt/homebrew/bin/kiac resume cluster > /tmp/kiac-resume.log 2>&1 && sleep 30
#/opt/homebrew/bin/kubectl proxy --address='0.0.0.0' --port=16443 --accept-hosts='^.*$' > /tmp/kiac-proxy.log 2>&1 &

# If the SSD drive is mounted on m1mac
if [ ! -d "/Volumes/Samsung_T5" ]; then
    echo "# Mounting /Volumes/Samsung_T5 from m1mac" >&2
    timeout 10 open "smb://m1mac/Samsung_T5"
fi