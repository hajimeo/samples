#!/usr/bin/env bash

export _SERVICE="sonatype"

main() {
    # Run one-by-one
    for n in freeipa node-nxiq node-nxrm-ha1; do
        bash /usr/local/bin/setup_standalone.sh -n $n &>/tmp/setup_standalone_$n.out
        sleep 1
    done
    # If -ha2 -ha3 exist, run but without starting
    for n in $(docker ps -a --format "{{.Names}}" | grep -E "^(node-nxrm2|node-nxrm-ha2|node-nxrm-ha3|nexus-client)$" | sort); do
        bash /usr/local/bin/setup_standalone.sh -N -n $n &>/tmp/setup_standalone_$n.out &
        sleep 1
    done
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
