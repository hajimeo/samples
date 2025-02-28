#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# Tiny proxy for testing connection (only python2)
# Based on https://code.google.com/p/python-proxy/
#
import argparse, sys, socket, select, datetime, os
import time

try:
    # TODO: Test this script with python3
    import _thread as thread
    from urllib.parse import urlparse, parse_qs
    import errno
except ImportError:
    sys.stderr.write("Python 3 is required.\n")
    exit(1)
#    import thread
#    from urlparse import urlparse, parse_qs
#    from socket import errno

__version__ = '0.1.0 Draft 1 +modified by Hajime'
BUFLEN = 8192
VERSION = 'Python Proxy/' + __version__
HTTPVER = 'HTTP/1.1'
DEBUG = False
DELAY = 0


class ConnectionHandler:
    def __init__(self, connection, address, timeout):
        self.client = connection
        self.client_buffer = ''
        self.timeout = timeout
        self.method, self.path, self.protocol = self.get_base_header()
        if self.method == 'CONNECT':
            self.method_CONNECT()
        elif self.method in ('OPTIONS', 'GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'TRACE'):
            self.method_others()
        self.client.close()
        self.target.close()

    def log(self, msg):
        sys.stdout.write('[%s] %s\n' % (datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'), str(msg)))
        sys.stdout.flush()

    def debug(self, msg):
        if DEBUG is False:
            return
        sys.stdout.write('[%s] DEBUG %s\n' % (datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'), str(msg)))
        sys.stdout.flush()

    def get_base_header(self):
        while 1:
            self.client_buffer += str(self.client.recv(BUFLEN))
            end = self.client_buffer.find('\n')
            if end != -1:
                break
        self.log(self.client_buffer)
        data = (self.client_buffer[:end + 1]).split()
        self.client_buffer = self.client_buffer[end + 1:]
        return data

    def method_CONNECT(self):
        # TODO: this is not working
        self._connect_target(self.path)
        _str = HTTPVER + ' 200 Connection established\n' + 'Proxy-agent: %s\n\n' % VERSION
        self.client.send(_str)
        self.log(_str)
        self.client_buffer = ''
        self._read_write()

    def method_others(self):
        self.path = self.path[7:]
        i = self.path.find('/')
        # protocol = self.protocol   # TODO: https?
        host = self.path[:i]
        path = self.path[i:]
        self._connect_target(host)
        _str = '%s %s %s\n' % (self.method, path, self.protocol) + self.client_buffer
        self.log(_str)
        self.client_buffer = ''
        self._read_write()

    def _connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i + 1:])
            host = host[:i]
        else:
            port = 80
        # (soc_family, _, _, _, address) = socket.getaddrinfo(host, port)[0]
        (soc_family, _, _, _, address) = \
            socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM, socket.SOL_TCP)[0]
        self.target = socket.socket(soc_family)
        self.target.connect(address)

    def _read_write(self):
        time_out_max = self.timeout / 3
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
                        self.log("Delaying %d seconds ..." % DELAY)
                        time.sleep(float(DELAY))
                        out.send(data)
                        self.log(data[:200])
                        count = 0
            if count == time_out_max:
                break


def start_server(host='localhost', port=8080, IPv6=False, timeout=60, handler=ConnectionHandler):
    if IPv6 == True:
        soc_type = socket.AF_INET6
    else:
        soc_type = socket.AF_INET
    soc = socket.socket(soc_type)
    ts = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    try:
        soc.bind((host, port))
    except socket.error as e:
        sys.stdout.write("Socket Exception = %s \n" % e)
        return 0
    print("[%s] Serving on %s:%d (delay:%d)" % (ts, host, port, DELAY))  # debug
    soc.listen(0)
    while 1:
        try:
            thread.start_new_thread(handler, soc.accept() + (timeout,))
        except KeyboardInterrupt:
            ts = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            sys.stdout.write("[%s] Keyboard Interrupted (ctrl-c). Exiting ...\n" % (ts))
            sys.stdout.flush()
            return 0
        except:
            raise


def main():
    global DELAY
    global DEBUG
    parser = argparse.ArgumentParser(description='Simple Proxy / Reverse proxy')
    parser.add_argument('--host', required=False, default="0.0.0.0", help='Listening IP or hostname (default 0.0.0.0)')
    parser.add_argument('--port', required=False, default="8080", help='Listening port number (default 8080)')
    parser.add_argument('--timeout', required=False, default="60", help='socket timeout (default 60)')
    parser.add_argument('--delay', required=False, default="0", help='intentional delay (default 0)')
    parser.add_argument('--debug', required=False, action=argparse.BooleanOptionalAction, help='debug/verbose mode')
    args = parser.parse_args()
    host = args.host
    port = int(args.port)
    timeout = int(args.timeout)
    DELAY = int(args.delay)
    return start_server(host=host, port=port, timeout=timeout)


if __name__ == '__main__':
    main()
