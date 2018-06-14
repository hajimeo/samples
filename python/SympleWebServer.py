#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Based on https://pymotw.com/2/BaseHTTPServer/
#
from BaseHTTPServer import BaseHTTPRequestHandler
from BaseHTTPServer import HTTPServer
import urlparse
import sys


class SympleWebServer(BaseHTTPRequestHandler):
    '''
    REST *like* simple web server (no dependent module)
    At this moment only GET is supported
    Expecting "/method/arg1/arg2" style path
    '''
    log_level=""

    def do_GET(self):
        '''
        Handle GET method
        '''
        self.debug_log()
        self.send_response(200)
        self.end_headers()
        self.wfile.write("GET!")
        return

    def get_method_and_args_from_path(self):
        '''
        Get a method name and arg values from the URL path
        '''
        parsed_path = urlparse.urlparse(self.path)

    def debug_log(self):
        if SympleWebServer.log_level.lower() == 'debug':
            parsed_path = urlparse.urlparse(self.path)
            message_parts = [
                'CLIENT VALUES:',
                'client_address=%s (%s)' % (self.client_address,
                                            self.address_string()),
                'command=%s' % self.command,
                'path=%s' % self.path,
                'real path=%s' % parsed_path.path,
                'query=%s' % parsed_path.query,
                'request_version=%s' % self.request_version,
                '',
                'SERVER VALUES:',
                'server_version=%s' % self.server_version,
                'sys_version=%s' % self.sys_version,
                'protocol_version=%s' % self.protocol_version,
                '',
                'HEADERS RECEIVED:',
                ]
            for name, value in sorted(self.headers.items()):
                message_parts.append('%s=%s' % (name, value.rstrip()))
            message_parts.append('')
            message = '\r\n'.join(message_parts)
            self.log(message, "DEBUG")

    def log(self, msg, level):
        # sys.stderr.write(level+" "+msg + '\n')
        self.log_message(level+" %s", msg)


if __name__ == '__main__':
    # TODO: error handling

    listen_host = '0.0.0.0'
    listen_port = 38080

    if len(sys.argv) > 1:
        listen_host = sys.argv[1]
    if len(sys.argv) > 2:
        listen_port = int(sys.argv[2])
    if len(sys.argv) > 3:
        SympleWebServer.log_level=sys.argv[3]

    server = HTTPServer((listen_host, listen_port), SympleWebServer)
    print('Starting server, use <Ctrl-C> to stop')
    server.serve_forever()
