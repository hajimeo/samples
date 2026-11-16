#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import http.server
import http.client
#import urllib.parse

# --- CONFIGURATION ---
LOCAL_PORT = 11435
REMOTE_HOST = "169.254.20.20"
REMOTE_PORT = 11435
BEARER_TOKEN = "admin123"  # <-- Replace with your actual token
# ---------------------

class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.handle_request("POST")

    def do_GET(self):
        self.handle_request("GET")

    def do_OPTIONS(self):
        self.handle_request("OPTIONS")

    def handle_request(self, method):
        # Read incoming request body if present
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length) if content_length > 0 else None

        # Build connection to remote oMLX server
        conn = http.client.HTTPConnection(REMOTE_HOST, REMOTE_PORT)

        # Copy headers and force inject the Bearer Token
        headers = {key: val for key, val in self.headers.items() if key.lower() != 'host'}
        headers['Authorization'] = f"Bearer {BEARER_TOKEN}"
        headers['Host'] = f"{REMOTE_HOST}:{REMOTE_PORT}"

        try:
            # Forward the request to remote server
            conn.request(method, self.path, body, headers)
            response = conn.getresponse()

            # Send response back to IntelliJ
            self.send_response(response.status)
            for key, val in response.getheaders():
                # Avoid duplicating transfer encoding headers
                if key.lower() not in ['transfer-encoding', 'content-length']:
                    self.send_header(key, val)

            res_body = response.read()
            self.send_header('Content-Length', str(len(res_body)))
            self.end_headers()
            self.wfile.write(res_body)

        except Exception as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(f"Proxy Error: {str(e)}".encode())
        finally:
            conn.close()

if __name__ == '__main__':
    server = http.server.HTTPServer(('127.0.0.1', LOCAL_PORT), ProxyHandler)
    print(f"Proxy listening on http://localhost:{LOCAL_PORT} -> Forwarding to {REMOTE_HOST}:{REMOTE_PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down proxy.")
