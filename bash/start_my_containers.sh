#!/usr/bin/env bash

export _SERVICE="sonatype"

main() {
    for n in $(docker ps -a --format "{{.Names}}" | grep -E "^node-?(nxrm-ha2|nxrm-ha3|nxiq|nxrm2|freeipa)$" | sort); do
        bash /usr/local/bin/setup_standalone.sh -N -n $n &>/tmp/setup_standalone_$n.out &
        sleep 1
    done
    bash -x /usr/local/bin/setup_standalone.sh -n node-nxrm-ha1 &>/tmp/setup_standalone_node-nxrm-ha1.out &
    sleep 1
    bash -l /usr/local/bin/setup_standalone.sh -N -n nexus-client &>/tmp/setup_standalone_nexus-client
    wait

    if ! systemctl restart dnsmasq.service; then
        systemctl status dnsmasq.service
        return 1
    fi
    if ! systemctl restart haproxy.service; then
        systemctl status haproxy.service
        return 1
    fi
}

main
