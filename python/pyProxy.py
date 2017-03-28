#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# Tiny proxy for testing connection
# Based on https://code.google.com/p/python-proxy/
#

import sys, socket, thread, select, datetime, os
from socket import errno

__version__ = '0.1.0 Draft 1 +modified by Hajime'
BUFLEN = 8192
VERSION = 'Python Proxy/'+__version__
HTTPVER = 'HTTP/1.1'

class ConnectionHandler:
    def __init__(self, connection, address, timeout):
        self.client = connection
        self.client_buffer = ''
        self.timeout = timeout
        self.method, self.path, self.protocol = self.get_base_header()
        if self.method=='CONNECT':
            self.method_CONNECT()
        elif self.method in ('OPTIONS', 'GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'TRACE'):
            self.method_others()
        self.client.close()
        self.target.close()

    def get_base_header(self):
        while 1:
            self.client_buffer += self.client.recv(BUFLEN)
            end = self.client_buffer.find('\n')
            if end!=-1:
                break
        ts = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        sys.stdout.write('[%s] %s\n' % (ts, self.client_buffer[:end])) #debug
        sys.stdout.flush()
        data = (self.client_buffer[:end+1]).split()
        self.client_buffer = self.client_buffer[end+1:]
        return data

    def method_CONNECT(self):
        self._connect_target(self.path)
        self.client.send(HTTPVER+' 200 Connection established\n'+
                         'Proxy-agent: %s\n\n'%VERSION)
        self.client_buffer = ''
        self._read_write()

    def method_others(self):
        self.path = self.path[7:]
        i = self.path.find('/')
        host = self.path[:i]
        path = self.path[i:]
        self._connect_target(host)
        self.target.send('%s %s %s\n'%(self.method, path, self.protocol)+
                         self.client_buffer)
        self.client_buffer = ''
        self._read_write()

    def _connect_target(self, host):
        i = host.find(':')
        if i!=-1:
            port = int(host[i+1:])
            host = host[:i]
        else:
            port = 80
        #(soc_family, _, _, _, address) = socket.getaddrinfo(host, port)[0]
        (soc_family, _, _, _, address) = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM, socket.SOL_TCP)[0]
        self.target = socket.socket(soc_family)
        self.target.connect(address)

    def _read_write(self):
        time_out_max = self.timeout/3
        socs = [self.client, self.target]
        count = 0
        while 1:
            count += 1
            (recv, _, error) = select.select(socs, [], socs, 3)
            if error:
                break
            if recv:
                for in_ in recv:
                    data = in_.recv(BUFLEN)
                    if in_ is self.client:
                        out = self.target
                    else:
                        out = self.client
                    if data:
                        out.send(data)
                        count = 0
            if count == time_out_max:
                break

def start_server(host='localhost', port=8080, IPv6=False, timeout=60, handler=ConnectionHandler):
    if IPv6==True:
        soc_type=socket.AF_INET6
    else:
        soc_type=socket.AF_INET

    soc = socket.socket(soc_type)
    ts = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    try:
        soc.bind((host, port))
    except socket.error, e:
        if e[0] == errno.EADDRINUSE:
            sys.stdout.write("[%s] Port %d in use. Do nothing...\n" % (ts, port))
            sys.stdout.flush()
            sys.exit(0)
        else:
            raise

    print "[%s] Serving on %s:%d"%(ts, host, port) #debug
    soc.listen(0)
    while 1:
        try:
            thread.start_new_thread(handler, soc.accept()+(timeout,))
        except KeyboardInterrupt:
            ts = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            sys.stdout.write("[%s] Keyboard Interrupted (ctrl-c). Exiting ...\n" % (ts))
            sys.stdout.flush()
            sys.exit(0)
        except:
            raise

def cron():
    cron_script_path="/etc/cron.d/pyProxy"
    script_full_path=os.path.abspath(__file__)
    os.chmod(script_full_path, 0755)
    if(os.path.isfile(cron_script_path)):
        sys.stdout.write("\"%s\" already exists. Skipping...\n")
        sys.stdout.flush()
        sys.exit(0)
    file = open(cron_script_path, "w")
    file.write("*/10 * * * * root %s >> /var/log/pyproxy.log\n" % script_full_path)
    file.close()
    sys.exit(0)

if __name__ == '__main__':
    host='0.0.0.0'
    port=8080

    if (len(sys.argv) == 3):
        host=sys.argv[1]
        port=sys.argv[2]
    elif (len(sys.argv) == 2):
        if (sys.argv[1] == "cron"):
            cron()
        else:
            host=sys.argv[1]
            port=8080

    start_server(host=host, port=port)
