#!/usr/bin/env bash

_SERVICE="sonatype"

main() {
    if ! systemctl restart dnsmasq.service; then
        systemctl status dnsmasq.service
        return 1
    fi
    for n in `docker ps -a --format "{{.Names}}" | grep -E "^node-?(nxrm-ha2|nxrm-ha3)$" | sort`; do
        bash -l /usr/local/bin/setup_standalone.sh -N -n $n &>/tmp/setup_standalone_$n.out &
        sleep 1;
    done
    for n in `docker ps -a --format "{{.Names}}" | grep -E "^node-?(nxrm-ha1|nxiq|freeipa||nxrm2)$" | sort`; do
        bash -l /usr/local/bin/setup_standalone.sh -n $n &>/tmp/setup_standalone_$n.out &
        sleep 1
    done
    bash -l /usr/local/bin/setup_standalone.sh -N -n nexus-client &>/tmp/setup_standalone_nexus-client
    wait
}

main