#!/usr/bin/env python
# -*- coding: utf-8 -*-
import mimetypes
import sys
import time
from http.server import HTTPServer
from http.server import BaseHTTPRequestHandler

listen_host = "127.0.0.1"
listen_port = 9999
delay_sec = 3


def response_with_delay(httpServ, fp=None, chunk_size=32768, sec=1, repeat=100, message=""):
    if fp:
        while True:
            # Always wait first
            if sec > 0:
                time.sleep(float(sec))
            chunk = fp.read(chunk_size)
            if chunk:
                httpServ.wfile.write(chunk)
            else:
                break
    else:
        for x in range(repeat):
            httpServ.wfile.write(bytes(message + " " + str(x) + "\n", 'utf-8'))
            if sec > 0:
                time.sleep(float(sec))


class SlowserverRequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        p = "." + self.path  # not supporting all OS
        #time.sleep(float(60))   # was trying testing connection timeout but thi causes operational timeout
        try:
            with open(p, "rb") as fp:
                self.send_response(200)
                mtype, _ = mimetypes.guess_type(p)
                if mtype:
                    self.send_header("Content-type", mtype)
                self.end_headers()
                # If initial delay is needed, add sleep in here
                response_with_delay(self, fp=fp, sec=delay_sec)
        except IOError:
            self.send_response(404)
            self.end_headers()


if __name__ == '__main__':
    if len(sys.argv) > 1 and len(sys.argv[1]) > 0:
        listen_host = sys.argv[1]
    if len(sys.argv) > 2 and len(sys.argv[2]) > 0:
        listen_port = int(sys.argv[2])
    if len(sys.argv) > 3 and len(sys.argv[3]) > 0:
        delay_sec = int(sys.argv[3])

    try:
        print(f"Starting on {listen_host}:{listen_port} with delay_sec={delay_sec} ...")
        server = HTTPServer((listen_host, listen_port), SlowserverRequestHandler)
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nAborting ... Keyboard Interrupt.")
        pass
