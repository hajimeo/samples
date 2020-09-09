#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Based on https://pymotw.com/2/BaseHTTPServer/
#   python ./SimpleWebServer.py 0.0.0.0 38080 verbose
#
# Then from browser, http://localhost:38080/slack/search?query=test
#
from http.server import BaseHTTPRequestHandler
from http.server import HTTPServer
import urllib, sys, os, json, traceback, base64, datetime, math
import imp  # TODO: Deprecated

try:
    from urllib.request import urlopen, Request
except ImportError:
    from urllib2 import urlopen, Request
try:
    from urllib import parse
except ImportError:
    import urlparse as parse


def toDateStr(ts):
    return datetime.datetime.fromtimestamp(math.floor(float(ts))).strftime('%Y-%m-%d %H:%M:%S')


class SimpleWebServer(BaseHTTPRequestHandler):
    '''
    REST *like* simple web server (no dependent module)
    At this moment only GET is supported
    Expecting "/category/method?key1=val1&key2=val2" style path
    '''
    verbose = ""
    _creds = {}

    def do_GET(self):
        self._debug_message()
        self._process()
        return

    @staticmethod
    def handle_slack_search(query_args):
        query_args['token'] = SimpleWebServer._creds.slack_search_token
        # TODO: need some prettier format (eg: utilize highlight=true with replacing special characters)
        # query_args['highlight'] = "true"
        # Note: similar to PHP, query argument can be a list
        if 'query' in query_args and type(query_args['query']) == list and len(query_args['query']) == 1:
            query_args['query'] = query_args['query'][0]
        data = urllib.urlencode(query_args)
        SimpleWebServer.log('    data = ' + str(data))
        request = Request(SimpleWebServer._creds.slack_search_baseurl + "/api/search.messages", data)
        response = urlopen(request)
        json_str = response.read()
        json_obj = json.loads(json_str)
        html = u"<h2>Hit " + str(json_obj['messages']['total']) + u" messages</h2>\n"
        html += u"<p>Query <code>" + query_args['query'].decode('utf-8') + "</code></p>\n"
        if len(json_obj['messages']['matches']) > 0:
            for o in json_obj['messages']['matches']:
                SimpleWebServer.log('    matchN = ' + json.dumps(o, indent=2, sort_keys=True))
                html += u"<hr/>"
                html += u"<pre>"
                html += u"DATETIME : " + toDateStr(o['ts']) + " | CHANNEL: " + str(
                    o['channel']['name']) + " | USERNAME: " + str(o['username']) + " (" + str(o['user']) + ")\n"
                html += u"PERMALINK: <a href='" + o['permalink'].replace('/archives/',
                                                                         '/messages/') + u"' target='_blank'>" + o[
                            'permalink'] + u"</a>\n"
                html += u"</pre>"
                html += u"<blockquote style='white-space:pre-wrap'><tt>" + o['text'] + u"</tt></blockquote>\n"
        else:
            SimpleWebServer.log('    response = ' + str(json_str))
        # html = json.dumps(json_obj, indent=4)
        return html

    def _process(self):
        self._reload()
        (category, method, args) = self._get_category_method_and_args_from_path()
        output = u"<html><head><meta charset='utf-8'><title>" + category.upper() + ":" + method.upper() + "</title></head><body>"
        if category.lower() == 'slack':
            if method.lower() == 'search':
                output += SimpleWebServer.handle_slack_search(args)
        output += "</body></html>"
        self.send_response(200)
        self.end_headers()
        self.wfile.write(output.encode('utf-8'))

    def _reload(self):
        plain = False
        s = {}
        current_dir = os.path.dirname(__file__)
        if bool(current_dir) is False:
            current_dir = "."
        # if current_dir+"/.reload_cred" exist, force reloading credentials
        if bool(SimpleWebServer._creds) is True and os.path.exists(current_dir + "/.reload_cred") is False:
            return
        # in case of keeping reloading, removing now
        if os.path.exists(current_dir + "/.reload_cred"):
            os.remove(current_dir + "/.reload_cred")
        credpath = current_dir + "/" + "." + os.path.basename(os.path.splitext(__file__)[0]).lower()
        # try reading a compiled one first
        if os.path.exists(credpath + "c"):
            credpath = credpath + "c"
        elif os.path.exists(credpath + ".pyc"):
            credpath = credpath + ".pyc"
        elif os.path.exists(credpath + ".py"):
            credpath = credpath + ".py"
        self._log("Reloading " + credpath)
        try:
            c = imp.load_compiled("*", credpath)
        except ImportError:
            c = imp.load_source("*", credpath)
            plain = True
        for p, v in vars(c).iteritems():
            if not p.startswith('__'):
                if plain:
                    s[p] = base64.b64encode(v)
                else:
                    setattr(c, p, base64.b64decode(v))
        SimpleWebServer._creds = c
        # self._log(str(SimpleWebServer._creds.__dict__))
        if plain:
            f = open(credpath + ".tmp", "wb")
            for p, v in s.iteritems():
                f.write(p + "='" + v + "'\n")
            f.close()
            import py_compile
            py_compile.compile(credpath + ".tmp", credpath + "c")
            os.remove(credpath + ".tmp")
            self._log(credpath + " should be deleted", "WARN")

    def _get_category_method_and_args_from_path(self):
        parsed_path = parse.urlparse(self.path)
        args = parse.parse_qs(parsed_path.query)
        dirs = parsed_path.path.split("/")
        if len(dirs) < 3: return "", "", args
        return dirs[1], dirs[2], args

    def _debug_message(self, force=False):
        if SimpleWebServer.verbose.lower() == 'verbose' or force:
            parsed_path = parse.urlparse(self.path)
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
            self._log(message)

    def _log(self, msg, level="DEBUG"):
        if SimpleWebServer.verbose.lower() == 'verbose' or level.lower() in ["error", "warn", "warning"]:
            self.log_message(level.upper() + ": %s", msg)

    @staticmethod
    def log(msg, level="DEBUG"):
        if SimpleWebServer.verbose.lower() == 'verbose' or level.lower() in ["error", "warn", "warning"]:
            sys.stderr.write(level.upper() + ": " + msg + '\n')


if __name__ == '__main__':
    # TODO: error handling
    listen_host = '0.0.0.0'
    listen_port = 38080

    if len(sys.argv) > 1:
        listen_host = sys.argv[1]
    if len(sys.argv) > 2:
        listen_port = int(sys.argv[2])
    if len(sys.argv) > 3:
        SimpleWebServer.verbose = sys.argv[3]
        print("verbose mode is on")
    try:
        server = HTTPServer((listen_host, listen_port), SimpleWebServer)
        print('Starting server, use <Ctrl-C> to stop')
        server.serve_forever()
    except (KeyboardInterrupt):
        print("\nAborting ... Keyboard Interrupt.")
        sys.exit(0)
