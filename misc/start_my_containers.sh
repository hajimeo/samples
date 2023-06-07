#!/usr/bin/env bash

export _SERVICE="sonatype"

main() {
    # Run one-by-one
    bash /usr/local/bin/setup_standalone.sh -N -n node-freeipa &>/tmp/setup_standalone_node-freeipa.out || return 1
    sleep 1
    for n in node-nxiq node-nxrm-ha1; do
        bash /usr/local/bin/setup_standalone.sh -n $n &>/tmp/setup_standalone_$n.out || return 1
        sleep 1
    done
    bash /usr/local/bin/setup_standalone.sh -n node-nxrm2 &>/tmp/setup_standalone_node-nxrm2.out #|| return 1
    sleep 1

    # If -ha2 -ha3 exist, run but without starting
    for n in $(docker ps -a --format "{{.Names}}" | grep -E "^(node-nxrm-ha2|node-nxrm-ha3|nexus-client)$" | sort); do
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

main || main