#!/usr/bin/env python
# https://github.com/EtiennePerot/misc-scripts/blob/master/udp-relay.py
# Super simple script that listens to a local UDP port and relays all packets to an arbitrary remote host.
# Packets that the host sends back will also be relayed to the local UDP client.
# Works with Python 2 and 3

import sys, socket

def fail(reason):
    sys.stderr.write(reason + '\n')
    sys.exit(1)

def start_server(localPort=88, remoteHost="", remotePort=88):
    try:
        localPort = int(localPort)
    except:
        fail('Invalid port number: ' + str(localPort))
    try:
        remotePort = int(remotePort)
    except:
        fail('Invalid port number: ' + str(remotePort))

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.bind(('', localPort))
    except:
        fail('Failed to bind on port ' + str(localPort))

    knownClient = None
    knownServer = (remoteHost, remotePort)
    sys.stderr.write('All set.\n')
    while True:
        data, addr = s.recvfrom(32768)

        if knownClient is None:
            knownClient = addr

        if addr == knownClient:
            sentTo = knownServer
        elif addr != knownServer:
            sentTo = knownClient
            knownClient = addr

        s.sendto(data, sentTo)
        sys.stderr.write('Sent to '+str(sentTo)+'\n')

if __name__ == '__main__':
    if len(sys.argv) != 2 or len(sys.argv[1].split(':')) != 3:
        fail('Usage: '+sys.argv[0]+' localPort:remoteHost:remotePort')

    localPort, remoteHost, remotePort = sys.argv[1].split(':')
    start_server(localPort=localPort, remoteHost=remoteHost, remotePort=remotePort)
