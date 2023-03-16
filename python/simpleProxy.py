# Based on https://levelup.gitconnected.com/how-to-build-a-super-simple-http-proxy-in-python-in-just-17-lines-of-code-a1a09192be00
import socketserver
import http.server
import urllib

PORT = 8080

class MyProxy(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        url = self.path[1:]
        self.send_response(200)
        self.end_headers()
        self.copyfile(urllib.urlopen(url), self.wfile)


httpd = socketserver.ForkingTCPServer(('', PORT), MyProxy)
print("Now serving at " + str(PORT))
httpd.serve_forever()
