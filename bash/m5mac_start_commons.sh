#!/usr/bin/env bash
# PURPOSE:
#   List of the common commands used after restarting (or after hibernating) m5mac
#

### Start oMlx OR Mirai OR Apfel if not reachable  #########################
# Currently everytime the Mac sleeps, some services can't be reached until restarted
# If this hostname:8000 and :11435 are not reachable, then restart the services below
_BRIDGE_IP="$(ipconfig getifaddr bridge0)"
if type /opt/homebrew/bin/omlx &>/dev/null; then
    if ! curl -sf -m5 -o/dev/null http://${_BRIDGE_IP}:8000/v1/models -H "Authorization: Bearer admin123"; then
        echo "# Restarting omlx on $(hostname) because ${_BRIDGE_IP}:8000 is not reachable" >&2; sleep 2
        /opt/homebrew/bin/brew services restart omlx
    fi
elif type /opt/homebrew/bin/mirai &>/dev/null; then
    # Mirai or oMlx even though the ports are different
    _mirai_model="trymirai/Qwen3.8-27B-S"   # or Qwen3.5-9B-M
    if ! curl -sf -m5 -o/dev/null http://${_BRIDGE_IP}:7999/v1/models; then
        echo "# Starting mirai uzu with '${_mirai_model}' on $(hostname) because ${_BRIDGE_IP}:7999 is not reachable" >&2; sleep 2
        /opt/homebrew/bin/mirai server --model ${_mirai_model} --host 0.0.0.0 --port 7999 &> /tmp/mirai_uzu.log &
        sleep 2
        tail -n 20 /tmp/mirai_uzu.log
    fi
elif type /opt/homebrew/bin/apfel &>/dev/null; then
    if ! curl -sf -m5 -o/dev/null http://${_BRIDGE_IP}:11435/v1/models -H "Authorization: Bearer apfel"; then
        echo "# Restarting apfel on $(hostname) because ${_BRIDGE_IP}:11435 is not reachable" >&2; sleep 2
        /opt/homebrew/bin/brew services restart apfel
        # TODO: Want to use 'fm' but it currently doesn't have --cors option
        #/usr/bin/fm serve --host 0.0.0.0 --port 14345 > /tmp/fm.log 2>&1 &
    fi
fi

# zvac-grep (not using at this moment)
if type /opt/homebrew/bin/zg &>/dev/null; then
    # && /opt/homebrew/bin/zg server status | grep -q -w 'ready'
    echo "# *Stopping* zvac-grep on $(hostname) ..." >&2; sleep 2
    /opt/homebrew/bin/zg --server off
fi

# No longer using Apple Container
#if ! /opt/homebrew/bin/container system status; then
#    if /opt/homebrew/bin/container system start; then
#        sleep 10
#        /opt/homebrew/bin/kubectl proxy --address='0.0.0.0' --port=16445 --accept-hosts='^.*$' &> /tmp/kubectl_proxy_http_16445.out &
#    fi
#fi
# If Kiac (no longer needed with 'container')
#/opt/homebrew/bin/kiac resume cluster > /tmp/kiac-resume.log 2>&1 && sleep 30
#/opt/homebrew/bin/kubectl proxy --address='0.0.0.0' --port=16443 --accept-hosts='^.*$' > /tmp/kiac-proxy.log 2>&1 &

# If the SSD drive is mounted on m1mac
if [ ! -d "/Volumes/Samsung_T5" ]; then
    echo "# Mounting /Volumes/Samsung_T5 from m1mac" >&2
    timeout 10 open "smb://m1mac/Samsung_T5"
fi