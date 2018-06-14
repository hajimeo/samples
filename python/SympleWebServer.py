#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# Based on https://pymotw.com/2/BaseHTTPServer/
#   python SympleWebServer.py 0.0.0.0 38080 verbose
#
from BaseHTTPServer import BaseHTTPRequestHandler
from BaseHTTPServer import HTTPServer
import urllib, urllib2
import urlparse, sys, os, imp, json


class SympleWebServer(BaseHTTPRequestHandler):
    '''
    REST *like* simple web server (no dependent module)
    At this moment only GET is supported
    Expecting "/category/method?key1=val1&key2=val2" style path
    '''
    verbose= ""
    creds=None

    def do_GET(self):
        self._log_message()
        self._process()
        return

    @staticmethod
    def handle_slack_search(query_args):
        query_args['token']=SympleWebServer.creds.slack_search_token
        data = urllib.urlencode(query_args)
        request = urllib2.Request(SympleWebServer.creds.slack_search_baseurl+"/api/search.messages", data)
        response = urllib2.urlopen(request)
        json_str=response.read()
        # TODO: need more prettier format (eg: utilize highlight=true, convert unixtimestamp, use 'previous')
        json_parsed = json.loads(json_str)
        try:
            rtn_tmp = json_parsed['messages']['matches']
            rtn = []
            for o in rtn_tmp:
                rtn.append({"username":o['username']+" ("+o['user']+")", "permalink":o['permalink'], "text":o['text'], "ts":o['ts']})
        except KeyError:
            rtn = json_parsed
        return json.dumps(rtn, indent=4)

    def _process(self):
        output = ""
        self.__setup()
        try:
            (category, method, args) = self._get_category_method_and_args_from_path()
            if category.lower() == 'slack':
                if method.lower() == 'search':
                    output = SympleWebServer.handle_slack_search(args)

            self.send_response(200)
            self.end_headers()
            self.wfile.write(output)
        except:
            self._log_message()
            #self._log(sys.exc_info()[1], "ERROR")
            #import traceback
            #self._log(traceback.format_stack(), "ERROR")
            self.send_response(500)
            self.end_headers()
            self.wfile.write("ERROR!")


    def __setup(self):
        if bool(SympleWebServer.creds) is False:
            credpath = "."+os.path.basename(os.path.splitext(__file__)[0]).lower()+".pyc"
            SympleWebServer.creds = imp.load_compiled("*", credpath)

    def _get_category_method_and_args_from_path(self):
        parsed_path = urlparse.urlparse(self.path)
        dirs=parsed_path.path.split("/")
        args=urlparse.parse_qs(parsed_path.query)
        return (dirs[1], dirs[2], args)

    def _log_message(self, force=False):
        if SympleWebServer.verbose.lower() == 'verbose' or force:
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
            self._log(message, "DEBUG")

    def _log(self, msg, level):
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
        SympleWebServer.verbose=sys.argv[3]

    server = HTTPServer((listen_host, listen_port), SympleWebServer)
    print('Starting server, use <Ctrl-C> to stop')
    server.serve_forever()
