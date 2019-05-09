'''
chunked_server_test.py
@ref: (original) https://gist.github.com/josiahcarlson/3250376

To use gzip, -H "Accept-Encoding: gzip" or /filename?gzip=true
'''

import BaseHTTPServer, gzip, SocketServer, time, urlparse, os, sys, zipfile


class ChunkingHTTPServer(SocketServer.ThreadingMixIn,
                         BaseHTTPServer.HTTPServer):
    daemon_threads = True


class ListBuffer(object):
    __slots__ = 'buffer',

    def __init__(self):
        self.buffer = []

    def __nonzero__(self):
        return len(self.buffer)

    def write(self, data):
        if data:
            self.buffer.append(data)

    def flush(self):
        pass

    def getvalue(self):
        data = ''.join(self.buffer)
        self.buffer = []
        return data


class ChunkingRequestHandler(BaseHTTPServer.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def do_GET(self):
        parsed_path = urlparse.urlparse(self.path)
        sys.stderr.write('    parsed_path = %s \n' % str(parsed_path))
        if not os.path.isfile('.' + parsed_path.path):
            sys.stderr.write('    .%s is not accessible. Ignoring... \n' % str(parsed_path.path))
            return

        args = urlparse.parse_qs(parsed_path.query)
        ae = self.headers.get('accept-encoding') or ''
        use_gzip = 'gzip' in ae or 'gzip' in args
        # TODO: zip doesn't work becaues mode doesn't accept wb.
        use_zip = False #'zip' in ae or 'zip' in args

        # send some headers
        self.send_response(200)
        self.send_header('Transfer-Encoding', 'chunked')

        # use gzip as requested
        if use_gzip:
            self.send_header('Content-type', 'text/plain')
            self.send_header('Content-Encoding', 'gzip')
            buffer = ListBuffer()
            output = gzip.GzipFile(mode='wb', fileobj=buffer)
        #elif use_zip:
        #    self.send_header('Content-type', 'application/zip')
        #    buffer = ListBuffer()
        #    output = zipfile.ZipFile(mode='wb', file=buffer)
        else:
            self.send_header('Content-type', 'text/plain')

        self.end_headers()

        def write_chunk():
            tosend = '%X\r\n%s\r\n' % (len(chunk), chunk)
            self.wfile.write(tosend)

        f = open('.' + parsed_path.path, "rb")
        while True:
            chunk = f.read(1024 * 1024)  # 1MB
            if not chunk:
                break

            # we've got to compress the chunk
            if use_gzip or use_zip:
                output.write(chunk)
                # we'll force some output from gzip if necessary
                if not buffer:
                    output.flush()
                chunk = buffer.getvalue()

                # not forced, and gzip isn't ready to produce
                if not chunk:
                    continue

            write_chunk()

        if use_gzip or use_zip:
            # force the ending of the gzip stream
            output.close()
            chunk = buffer.getvalue()
            if chunk:
                write_chunk()

        # send the chunked trailer
        self.wfile.write('0\r\n\r\n')


if __name__ == '__main__':
    listen_host = '0.0.0.0'
    listen_port = 38080

    if len(sys.argv) > 1:
        listen_host = sys.argv[1]
    if len(sys.argv) > 2:
        listen_port = int(sys.argv[2])

    server = ChunkingHTTPServer(
        (listen_host, listen_port), ChunkingRequestHandler)
    sys.stderr.write('Starting server on %s:%s, use <Ctrl-C> to stop. \n' % (listen_host, listen_port))
    server.serve_forever()
