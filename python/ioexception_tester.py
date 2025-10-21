import socket

HOST = 'localhost'
PORT = 8070

headers = [
    "HTTP/1.1 500 Internal Server Error",
    "Content-Type: text/plain",
    "Content-Length: 1000", # Intentional mismatch
    "Connection: close"
]
body = "This is a broken response."
# NOTE: \r\n is the required line ending for the HTTP protocol
response = "\r\n".join(headers) + "\r\n\r\n" + body

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1) # TODO: not sure what this is for
    s.bind((HOST, PORT))
    s.listen()
    print(f"Starting 'Content-Length Mismatch' server on {HOST}:{PORT}")

    while True:
        conn, addr = s.accept()
        with conn:
            print(f"Connected by {addr}")
            # Read the client's request (but we don't care what it is)
            conn.recv(1024)

            # Send our broken response
            conn.sendall(response.encode('utf-8'))
            print("Sent partial response and closed connection.")
            # The connection is closed by the 'with' block