# Based on https://levelup.gitconnected.com/how-to-build-a-super-simple-http-proxy-in-python-in-just-17-lines-of-code-a1a09192be00
# Too simple, so that doesn't support CONNECT method
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import socketserver
import http.server
import urllib
from datetime import time

PORT = 28080
#DELAY = 3


class SimpleHttpProxy(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        url = self.path[1:]
        self.send_response(200)
        self.end_headers()
        #time.sleep(float(DELAY))
        self.copyfile(urllib.urlopen(url), self.wfile)


httpd = socketserver.ForkingTCPServer(('', PORT), SimpleHttpProxy)
print("Now serving at " + str(PORT))
httpd.serve_forever()
