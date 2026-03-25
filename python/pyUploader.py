import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler

class PUTHandler(SimpleHTTPRequestHandler):
    def do_PUT(self):
        path = self.translate_path(self.path)
        try:
            length = int(self.headers['Content-Length'])
            with open(path, 'wb') as f:
                f.write(self.rfile.read(length))
            self.send_response(201, "Created")
            self.end_headers()
            print(f" Successfully uploaded: {path}")
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            print(f" Error: {e}")

if __name__ == "__main__":
    # Default values if no arguments are provided
    host = sys.argv[1] if len(sys.argv) > 1 else '0.0.0.0'
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8000

    print(f"🚀 Server starting at http://{host}:{port}")
    print(f"📂 Upload files using: curl -X PUT --upload-file <file> http://{host}:{port}/<filename>")

    try:
        HTTPServer((host, port), PUTHandler).serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Server stopped.")