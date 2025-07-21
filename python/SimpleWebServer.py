#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Based on https://pymotw.com/2/BaseHTTPServer/
#   python ./SimpleWebServer.py 0.0.0.0 38080 verbose
#
# Then from browser, http://localhost:38080/slack/search?query=test
#                    http://localhost:38080/kapi/search?query=test
#
# TODO: add chats
#       add tests

from http.server import BaseHTTPRequestHandler
from http.server import HTTPServer
import urllib, sys, os, json, traceback, base64, datetime, math

import imp  # Deprecated in Python 3.4, but still works
# import importlib
import importlib.util
import importlib.machinery
import re

import requests
from urllib.request import urlopen, Request
from urllib import parse


def toDateStr(ts):
    return datetime.datetime.fromtimestamp(math.floor(float(ts))).strftime('%Y-%m-%d %H:%M:%S')


def loadSource(modname, filename):  # not in use yet
    loader = importlib.machinery.SourceFileLoader(modname, filename)
    spec = importlib.util.spec_from_file_location(modname, filename, loader=loader)
    module = importlib.util.module_from_spec(spec)
    # The module is always executed and not cached in sys.modules.
    # Uncomment the following line to cache the module.
    # sys.modules[module.__name__] = module
    loader.exec_module(module)
    return module


def get1stValue(arg):
    if type(arg) == list and len(arg) > 0:
        return arg[0]
    else:
        return arg


URL_PATTERN = re.compile(
    r'\b(?:https?://|www\.)\S+\b',
    re.IGNORECASE  # Make the matching case-insensitive (e.g., HTTP vs http)
)


def addLinksToText(text):
    """
    Finds URLs in the given text and wraps them in HTML <a> tags.
    """

    def replace_url_with_link(match):
        url = match.group(0)  # The entire matched URL
        # Ensure the URL has a protocol for the href attribute if it starts with 'www.'
        if not (url.startswith('http://') or url.startswith('https://')):
            return f'<a href="http://{url}">{url}</a>'
        return f'<a href="{url}">{url}</a>'

    # Use re.sub() with the compiled pattern and the replacement function
    linked_text = URL_PATTERN.sub(replace_url_with_link, text)
    return linked_text


class SimpleWebServer(BaseHTTPRequestHandler):
    '''
    REST *like* simple web server
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
        if 'query' in query_args:
            query_args['query'] = get1stValue(query_args['query'])
        data = parse.urlencode(query_args)
        SimpleWebServer.log('    data = ' + str(data))
        response = requests.get(url=str(SimpleWebServer._creds.slack_search_baseurl) + "/api/search.messages",
                                params=data)
        json_obj = response.json()
        SimpleWebServer.log('    response = ' + str(json_obj))
        # Decorate the output with HTML
        html = u"<h2>Hit " + str(json_obj['messages']['total']) + u" messages</h2>\n"
        # Add input field for query, so that user can change it
        html += u"<form method='get' action='/slack/search'>\n"
        html += u"Query:<input type='text' name='query' value='" + get1stValue(query_args['query']) + u"' size='60'>\n"
        html += u"<input type='submit' value='Search'><br/>\n"
        html += u"</form>\n"

        if len(json_obj['messages']['matches']) > 0:
            for o in json_obj['messages']['matches']:
                SimpleWebServer.log('    matchN = ' + json.dumps(o, indent=2, sort_keys=True))
                try:
                    username = str(o['username']) + " (" + str(o['user']) + ")"
                except:
                    username = "- (" + str(o['user']) + ")"
                html += u"<hr/>"
                html += u"<pre>"
                html += u"DATETIME : " + toDateStr(o['ts']) + " | CHANNEL: " + str(
                    o['channel']['name']) + " | USERNAME: " + username + "\n"
                html += u"PERMALINK: <a href='" + o['permalink'].replace('/archives/',
                                                                         '/messages/') + u"' target='_blank'>" + o[
                            'permalink'] + u"</a>\n"
                html += u"</pre>"
                html += u"<blockquote style='white-space:pre-wrap'><tt>" + o['text'] + u"</tt></blockquote>\n"
        # html = json.dumps(json_obj, indent=4)
        return html

    @staticmethod
    def handle_kapi_search(query_args):
        headers = {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-API-KEY': SimpleWebServer._creds.kapi_search_token
        }
        # SimpleWebServer.log('    headers = ' + str(headers))
        url = str(SimpleWebServer._creds.kapi_search_baseurl) + "/search/"
        SimpleWebServer.log('    url = ' + str(url))
        # query_args['highlight'] = "true"
        # Note: similar to PHP, query argument can be a list
        data = {}
        if 'query' in query_args:
            data['query'] = get1stValue(query_args['query'])
        if 'num_results' not in query_args:
            data['num_results'] = 40  # Default 10 might be too small
        else:
            data['num_results'] = int(get1stValue(query_args['num_results']))
        if 'include_source_names' in query_args:
            data['include_source_names'] = query_args['include_source_names']
        elif hasattr(SimpleWebServer._creds, 'kapi_search_default_sources') and len(
                SimpleWebServer._creds.kapi_search_default_sources) > 0:
            data['include_source_names'] = SimpleWebServer._creds.kapi_search_default_sources.split(',')
        SimpleWebServer.log('    data = ' + str(data))
        response = requests.post(url=url, json=data, headers=headers)
        json_obj = response.json()
        SimpleWebServer.log('    response = ' + str(json_obj))
        # Decorate the output with HTML
        html = u"<h2>Hit " + str(len(json_obj['search_results'])) + u" / " + str(
            get1stValue(data['num_results'])) + u" messages</h2>\n"
        # Add input field for query, so that user can change it
        html += u"<form method='get' action='/kapi/search'>\n"
        html += u"Query:<input type='text' name='query' value='" + get1stValue(query_args['query']) + u"' size='60'>\n"
        html += u"<input type='submit' value='Search'><br/>\n"
        # Generate checkboxes from the SimpleWebServer._creds.kapi_search_all_sources, which is the list of source names
        # For now, not using 'kapi_search_all_sources'
        if hasattr(SimpleWebServer._creds, 'kapi_search_default_sources') and len(
                SimpleWebServer._creds.kapi_search_default_sources) > 0:
            default_sources = SimpleWebServer._creds.kapi_search_default_sources.split(',')
            html += u"Source names:<br/>\n"
            for source_name in default_sources:
                html += u"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<input type='checkbox' name='include_source_names' value='" + source_name + "'"
                if 'include_source_names' in query_args and source_name in query_args['include_source_names']:
                    html += u" checked"
                html += u">" + source_name + "<br/>\n"
        html += u"</form>\n"
        if len(json_obj['search_results']) > 0:
            for o in json_obj['search_results']:
                SimpleWebServer.log('    matchN = ' + json.dumps(o, indent=2, sort_keys=True))
                html += u"<hr/>"
                html += u"<h3>" + o['title'] + "</h3>\n"  # looks like the 'content' always includes the title?
                html += u"URL: <a href='" + o['source_url'] + u"' target='_blank'>" + o['source_url'] + u"</a>\n"
                html += u"<blockquote style='white-space:pre-wrap'><tt>" + addLinksToText(
                    o['content']) + u"</tt></blockquote>\n"
        # html = json.dumps(json_obj, indent=4)
        return html

    def _process(self):
        (category, method, args) = self._get_category_method_and_args_from_path()
        self._log("args = " + str(args))
        output = u"<html><head><meta charset='utf-8'><title>" + category.upper() + ":" + method.upper() + "</title></head><body>"
        if category.lower() == 'slack':
            if method.lower() == 'search':
                output += SimpleWebServer.handle_slack_search(args)
        if category.lower() == 'kapi':
            if method.lower() == 'search':
                output += SimpleWebServer.handle_kapi_search(args)
        output += "</body></html>"
        self.send_response(200)
        self.end_headers()
        self.wfile.write(output.encode('utf-8'))

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
        if SimpleWebServer.verbose.lower() == 'verbose' or level.lower() in ["info", "error", "warn", "warning"]:
            self.log_message(level.upper() + ": %s", msg)

    @staticmethod
    def log(msg, level="DEBUG"):
        if SimpleWebServer.verbose.lower() == 'verbose' or level.lower() in ["info", "error", "warn", "warning"]:
            sys.stderr.write(level.upper() + ": " + str(msg) + '\n')

    @staticmethod
    def maybeReload():
        plain = False
        reload = False
        s = {}
        current_dir = os.path.dirname(__file__)
        if bool(current_dir) is False:
            current_dir = "."
        # If _creds object is already set and force reloading is not set, do not reload
        if bool(SimpleWebServer._creds) is True and os.path.exists(current_dir + "/.reload_cred") is False:
            return
        # in case of keeping reloading, removing now, regardless of the result
        if os.path.exists(current_dir + "/.reload_cred"):
            reload = True
            SimpleWebServer.log("Clearing reload_cred ...")
            os.remove(current_dir + "/.reload_cred")
        # Either _cred is empty or force reloading is set
        SimpleWebServer.log("Loading credentials ...")
        credpath = current_dir + "/" + "." + os.path.basename(os.path.splitext(__file__)[0]).lower()
        # try reading a compiled one first
        if reload == False and os.path.exists(credpath + "c"):
            credpath = credpath + "c"
        elif reload == False and os.path.exists(credpath + ".pyc"):
            credpath = credpath + ".pyc"
        elif os.path.exists(credpath + ".py"):
            credpath = credpath + ".py"
        else:
            SimpleWebServer.log("No credentials found at " + credpath + ", exiting ...", "ERROR")
            sys.exit(1)
        try:
            # c = importlib.import_module("*", credpath)
            c = imp.load_compiled("*", credpath)
        except ImportError:
            SimpleWebServer.log("load_source is called")
            # TODO: below function is not working
            # c = loadSource("*", credpath)
            c = imp.load_source("*", credpath)
            plain = True
        for p, v in vars(c).items():
            if not p.startswith('__'):
                if plain:
                    s[p] = base64.b64encode(v.encode("utf-8"))
                else:
                    setattr(c, p, base64.b64decode(v).decode("utf-8"))
        SimpleWebServer._creds = c
        # If it was plain, overwrite the compiled version
        if plain:
            f = open(credpath + ".tmp", "w")
            for p, v in s.items():
                # not sure from which version but single quotes stopped working
                line = str(p) + "=\"" + str(v, "utf-8") + "\"\n"
                # SimpleWebServer.log("Writing line = " + line)
                f.write(line)
            f.close()
            import py_compile
            py_compile.compile(credpath + ".tmp", credpath + "c")
            os.remove(credpath + ".tmp")
            SimpleWebServer.log(credpath + " should be deleted")


if __name__ == '__main__':
    # TODO: error handling
    listen_host = '0.0.0.0'
    listen_port = 38080

    if len(sys.argv) > 1 and len(sys.argv[1]) > 0:
        listen_host = sys.argv[1]
    if len(sys.argv) > 2 and len(sys.argv[2]) > 0:
        listen_port = int(sys.argv[2])
    if len(sys.argv) > 3 and len(sys.argv[3]) > 0:
        SimpleWebServer.verbose = sys.argv[3]
        SimpleWebServer.log(sys.argv)
    try:
        SimpleWebServer.maybeReload()
        server = HTTPServer((listen_host, listen_port), SimpleWebServer)
        print('Starting server, use <Ctrl-C> to stop')
        server.serve_forever()
    except (KeyboardInterrupt):
        print("\nAborting ... Keyboard Interrupt.")
        sys.exit(0)
