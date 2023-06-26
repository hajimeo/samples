#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys
import time
from http.server import HTTPServer
from http.server import BaseHTTPRequestHandler


def write_with_delay(s, sec=3, repeat=100, message=""):
    for x in range(repeat):
        time.sleep(float(sec))
        s.wfile.write(bytes(message + " " + str(x) + "\n", 'utf-8'))


class SlowserverRequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        write_with_delay(self)


if __name__ == '__main__':
    listen_host = "127.0.0.1"
    listen_port = 9999

    if len(sys.argv) > 1:
        listen_host = sys.argv[1]
    if len(sys.argv) > 2:
        listen_port = int(sys.argv[2])

    try:
        server = HTTPServer((listen_host, listen_port), SlowserverRequestHandler)
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nAborting ... Keyboard Interrupt.")
        pass
