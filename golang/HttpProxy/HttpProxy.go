/*
Originally based on https://medium.com/@mlowicki/http-s-proxy-in-golang-in-less-than-100-lines-of-code-6a51c2f2c38c
@see: https://eli.thegreenplace.net/2022/go-and-proxy-servers-part-2-https-proxies/
      https://github.com/eliben/code-for-blog/blob/main/2022/go-and-proxies/connect-mitm-proxy.go

# INSTALL:
	curl -o /usr/local/bin/httpproxy -L https://github.com/hajimeo/samples/raw/master/misc/httpproxy_$(uname)_$(uname -m)
	chmod a+x /usr/local/bin/httpproxy

# Optional step:
	openssl genrsa -out "proxy.key" 4096
	openssl req -x509 -new -nodes -key "proxy.key" -sha256 -days 3650 -out "proxy.crt" -subj "/CN=My Proxy CA"

# Normal HTTP proxy (it works with https):
    httpproxy [--delay {n} --debug --debug2]
	# Test
	curl -v --proxy localhost:8080 -k -L http://search.osakos.com/index.php

# TODO: HTTPS proxy (without replacing certificate):
	# If no --key/--crt, automatically uses standalone.localdomain.crt/.key.
	httpproxy --proto https --debug [--crt <path to pem certificate> --key <path to key>]
	# Test (need to trust rootCA_standalone.crt or with --proxy-insecure)
	curl -v --proxy https://localhost:8080/ --proxy-insecure -L https://search.osakos.com/index.php

# TODO: HTTPS proxy with replacing certificate:
	httpproxy --proto https --replCert --debug
	# Test (as replaced, --insecure/-k is needed)
	curl -v --proxy https://localhost:8080/ --proxy-insecure -k -L https://search.osakos.com/index.php

	TODO: Write proper tests
	TODO: '--proto https' is not working.
		  TLS handshake error from 127.0.0.1:64364: tls: first record does not look like a TLS handshake
*/

package main

import (
	"bytes"
	"context"
	"crypto/md5"
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"flag"
	"fmt"
	"io"
	"log"
	"math/big"
	"net"
	"net/http"
	"net/http/httputil"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

var DelaySec int64
var Proto string
var KeyPath string
var PemPath string
var CachePath string
var Debug bool
var Debug2 bool

func out(format string, v ...any) {
	// Make sure outputs newline
	if !strings.HasSuffix(format, "\n") {
		format += "\n"
	}
	log.Printf(format, v...)
}

func debug(format string, v ...any) {
	if Debug {
		out("DEBUG: "+format, v...)
	}
}

/* Not in use currently
func dumpKeyValues(m map[string][]string) []string {
	var list []string
	for name, values := range m {
		for _, value := range values {
			list = append(list, fmt.Sprintf("%s: \"%s\"", name, value))
		}
	}
	return list
}
*/

func handleDefault(w http.ResponseWriter, req *http.Request) {
	hash := ""
	if Debug {
		reqDump, err := httputil.DumpRequest(req, false)
		if err != nil {
			debug("DumpRequest failed for %s: %v", req.RequestURI, err)
		} else {
			hash = fmt.Sprintf("%x", md5.Sum(reqDump))
			debug("Request: %s\n%s", hash, reqDump)
			if Debug2 {
				req.Body = saveBodyToFile(req.Body, hash+".req")
			}
		}
	}
	resp, err := http.DefaultTransport.RoundTrip(req)
	if err != nil {
		out("RoundTrip for %s failed with %v", req.RequestURI, err)
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}
	if Debug {
		// If Debug, dump response (and may save body if Debug2)
		copyHeader(w.Header(), resp.Header)
		w.WriteHeader(resp.StatusCode)
		defer resp.Body.Close()
		respDump, err := httputil.DumpResponse(resp, false)
		if err != nil {
			debug("DumpResponse failed for %s failed. %v", req.RequestURI, err)
		} else {
			debug("Response %s", respDump)
			if Debug2 {
				resp.Body = saveBodyToFile(resp.Body, hash+".resp")
			}
		}
		io.Copy(w, resp.Body)
	}
}

func copyHeader(dst, src http.Header) {
	for k, vv := range src {
		for _, v := range vv {
			dst.Add(k, v)
		}
	}
}

func saveBodyToFile(body io.ReadCloser, filename string) io.ReadCloser {
	if filename == "" {
		// if no filename, just return the body as is
		return body
	}
	save, newBody, err := drainBody(body)
	if body == nil || body == http.NoBody {
		//debug("Not saving body as empty")
		return save
	}
	data, err := io.ReadAll(newBody)
	if err != nil {
		log.Printf("ERROR: Failed to read the body: %v", err)
		return save
	}
	// TODO: this may overwrite an existing file? as md5 includes header, maybe OK?
	fullpath := filepath.Join(CachePath, filename)
	err = os.WriteFile(fullpath, data, 0644)
	if err != nil {
		log.Printf("ERROR: Failed to write the body to %s: %v", fullpath, err)
	} else {
		debug("Saved body to %s", fullpath)
	}
	return save
}

func readFromRemote(downloadUrl string, saveTo string) []byte {
	resp, err := http.Get(downloadUrl)
	if err != nil {
		log.Fatalf("Failed to download PEM file from %s: %v", downloadUrl, err)
	}
	defer resp.Body.Close()
	debug("Downloaded PEM file from %s", downloadUrl)
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Fatalf("Failed to read PEM file from %s: %v", downloadUrl, err)
	}

	if len(saveTo) > 0 {
		// write to specified file
		err = os.WriteFile(saveTo, data, 0644)
		if err != nil {
			log.Printf("ERROR: Failed to write the body to %s: %v", saveTo, err)
		} else {
			debug("Saved body to %s", saveTo)
		}
	}
	return data
}

func drainBody(b io.ReadCloser) (r1, r2 io.ReadCloser, err error) {
	if b == nil || b == http.NoBody {
		// No copying needed. Preserve the magic sentinel meaning of NoBody.
		return http.NoBody, http.NoBody, nil
	}
	var buf bytes.Buffer
	if _, err = buf.ReadFrom(b); err != nil {
		return nil, b, err
	}
	if err = b.Close(); err != nil {
		return nil, b, err
	}
	return io.NopCloser(&buf), io.NopCloser(bytes.NewReader(buf.Bytes())), nil
}

func handleRequest(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	// TODO: the URL.String should return the full URL, but doesn't work if HTTPS. Tried reqToUrlStr()
	reqURLStr := r.URL.String()

	// To simulate slowness
	if DelaySec > 0 {
		debug("Delay %s for %d seconds", reqURLStr, DelaySec)
		// sleep delay seconds
		time.Sleep(time.Duration(DelaySec) * time.Second)
	}

	debug("%s: %s (host: %s)", r.Method, reqURLStr, r.Host)
	if r.Method == http.MethodConnect {
		handleConnect(w, r)
	} else {
		handleDefault(w, r)
	}

	elapsed := time.Since(start)
	// Show the elapsed time in seconds with 3 decimal places
	out("Completed %s (%.3f s)", reqURLStr, elapsed.Seconds())
}

func handleConnect(w http.ResponseWriter, req *http.Request) {
	hash := ""
	if Debug {
		reqDump, err := httputil.DumpRequest(req, false)
		if err != nil {
			debug("DumpRequest failed for %s: %v", req.RequestURI, err)
		} else {
			// Use md5sum of reqDump as the hash because 'body' is false
			hash = fmt.Sprintf("%x", md5.Sum(reqDump))
			debug("Request: %s\n%s", hash, reqDump)
			if Debug2 {
				req.Body = saveBodyToFile(req.Body, hash+".req")
			}
		}
	}

	hijacker, ok := w.(http.Hijacker)
	if !ok {
		out("ERROR: Hijacking not supported.")
		http.Error(w, "Hijacking not supported", http.StatusInternalServerError)
		return
	}

	clientConn, _, err := hijacker.Hijack()
	if err != nil {
		out("ERROR: Hijacking error: %v", err)
		return
	}

	host := req.Host
	_, err = clientConn.Write([]byte("HTTP/1.1 200 Connection established\r\n\r\n"))
	if err != nil {
		out("ERROR: clientConn.Write %s failed: %v", host, err)
		clientConn.Close()
		return
	}

	// Create a server-side TLS connection using a generated cert for the host
	tlsCert, err := getCertForHost(host)
	if err != nil {
		out("ERROR: getCertForHost %s error: %v", host, err)
		clientConn.Close()
		return
	}

	tlsConn := tls.Server(clientConn, &tls.Config{
		Certificates: []tls.Certificate{*tlsCert},
	})
	err = tlsConn.Handshake()
	if err != nil {
		out("ERROR: TLS handshake %s error: %v", host, err)
		tlsConn.Close()
		return
	}

	// Serve HTTP over the single TLS connection so we can inspect/forward requests.
	server := &http.Server{
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Ensure the request is routable by RoundTrip:
			// - RequestURI must be empty for client requests passed to Transport.
			// - URL.Scheme must be "https"
			// - URL.Host must be the target host (without proxy-info)
			r.RequestURI = ""
			// Some clients send absolute-form or origin-form; make sure Host is set
			if r.Host == "" {
				r.Host = strings.Split(host, ":")[0]
			}
			// Ensure URL has scheme and host
			r.URL.Scheme = "https"
			r.URL.Host = host

			out("→ %s %s (host: %s)", r.Method, r.URL.String(), host)

			// Use fresh transport for the outgoing connection
			resp, err := roundTripWithTLSFallback(r, host)
			if err != nil {
				out("ERROR: RoundTrip %s error: %v", host, err)
				http.Error(w, err.Error(), http.StatusServiceUnavailable)
				return
			}
			defer resp.Body.Close()

			if Debug {
				respDump, err := httputil.DumpResponse(resp, false)
				if err != nil {
					debug("DumpResponse failed for %s failed. %v", req.RequestURI, err)
				} else {
					debug("Response: %s", respDump)
					if Debug2 {
						resp.Body = saveBodyToFile(resp.Body, hash+".resp")
					}
				}
			}

			// Copy response headers and status
			for k, v := range resp.Header {
				w.Header()[k] = v
			}
			w.WriteHeader(resp.StatusCode)
			_, _ = io.Copy(w, resp.Body)
		}),
	}

	// Serve will accept exactly one connection from this listener wrapper
	_ = server.Serve(&singleUseListener{Conn: tlsConn})
}

var (
	caCert    *x509.Certificate
	caKey     *rsa.PrivateKey
	certCache = struct {
		sync.Mutex
		m map[string]*tls.Certificate
	}{m: make(map[string]*tls.Certificate)}
)

func getCertForHost(host string) (*tls.Certificate, error) {
	certCache.Lock()
	defer certCache.Unlock()
	if cert, ok := certCache.m[host]; ok {
		return cert, nil
	}

	// Generate leaf certificate
	serial, _ := rand.Int(rand.Reader, big.NewInt(1<<62))
	template := x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: host}, // Request hostname
		NotBefore:    time.Now(),
		NotAfter:     time.Now().Add(365 * 24 * time.Hour),
		KeyUsage:     x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		DNSNames:     []string{strings.Split(host, ":")[0]},
	}

	priv, _ := rsa.GenerateKey(rand.Reader, 2048)
	debug("x509.CreateCertificate caCert: %v", caCert.Subject)
	derBytes, err := x509.CreateCertificate(rand.Reader, &template, caCert, &priv.PublicKey, caKey)
	if err != nil {
		out("ERROR: x509.CreateCertificate %s error: %v", host, err)
		return nil, err
	}

	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: derBytes})
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(priv)})

	cert, err := tls.X509KeyPair(certPEM, keyPEM)
	if err != nil {
		out("ERROR: tls.X509KeyPair %s error: %v", host, err)
		return nil, err
	}

	certCache.m[host] = &cert
	return &cert, nil
}

func roundTripWithTLSFallback(req *http.Request, host string) (*http.Response, error) {
	versions := []uint16{tls.VersionTLS13, tls.VersionTLS12, tls.VersionTLS11, tls.VersionTLS10}

	var lastErr error
	for _, v := range versions {
		var tr *http.Transport
		if Debug {
			debug("Trying TLS %s for host %s", tlsVersionString(v), host)
			tr = makeTransportWithLogging(host, v)
		} else {
			tr = &http.Transport{
				ForceAttemptHTTP2: true,
				TLSClientConfig: &tls.Config{
					MinVersion:         v,
					MaxVersion:         v,
					ServerName:         strings.Split(host, ":")[0],
					InsecureSkipVerify: true, // TODO: not sure if this is a good idea
				},
			}
		}

		resp, err := tr.RoundTrip(req)
		if err != nil {
			if strings.Contains(err.Error(), "handshake failure") ||
				strings.Contains(err.Error(), "protocol version") {
				out("TLS %s failed, retrying with lower version...", tlsVersionString(v))
				lastErr = err
				continue // try next lower
			}
			return nil, err // other errors, don't retry
		}
		return resp, nil
	}
	return nil, fmt.Errorf("all TLS versions failed: %v", lastErr)
}

func makeTransportWithLogging(host string, v uint16) *http.Transport {
	return &http.Transport{
		ForceAttemptHTTP2: true,
		DialTLSContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			dialer := &net.Dialer{Timeout: 10 * time.Second}
			rawConn, err := dialer.DialContext(ctx, network, addr)
			if err != nil {
				return nil, err
			}

			conf := &tls.Config{
				ServerName:         strings.Split(host, ":")[0],
				MinVersion:         v,
				MaxVersion:         v,
				InsecureSkipVerify: true, // TODO: not sure if this is a good idea
			}

			tlsConn := tls.Client(rawConn, conf)
			if err := tlsConn.Handshake(); err != nil {
				rawConn.Close()
				return nil, err
			}

			state := tlsConn.ConnectionState()
			out("⇄ Upstream TLS: %s → %s | TLS %s | Cipher: %s",
				tlsConn.LocalAddr(), addr,
				tlsVersionString(state.Version),
				tls.CipherSuiteName(state.CipherSuite))

			return tlsConn, nil
		},
	}
}

func genCaCertFromFile(caPath string) {
	// Generate CA cert from the given caPath
	certData, err := os.ReadFile(caPath)
	if err != nil {
		log.Fatalf("Failed to read PEM file %s: %v", caPath, err)
	}
	block, _ := pem.Decode(certData)
	if block == nil {
		log.Fatalf("Failed to decode PEM file %s: %v", caPath, err)
	}
	caCert, err = x509.ParseCertificate(block.Bytes)
	if err != nil {
		log.Fatalf("Failed to parse PEM file %s: %v", caPath, err)
	}
}

func genCaKeyFromFile(keyPath string) {
	// Generate CA key from the given keyPath
	keyData, err := os.ReadFile(keyPath)
	if err != nil {
		log.Fatalf("Failed to read Key file %s: %v", keyPath, err)
	}
	block, _ := pem.Decode(keyData)
	if block == nil {
		log.Fatalf("Failed to decode Key file %s: %v", keyPath, err)
	}
	caKey, err = x509.ParsePKCS1PrivateKey(block.Bytes)
	if err != nil {
		log.Fatalf("Failed to parse Key file %s: %v", keyPath, err)
	}
}

func tlsVersionString(v uint16) string {
	switch v {
	case tls.VersionTLS13:
		return "1.3"
	case tls.VersionTLS12:
		return "1.2"
	case tls.VersionTLS11:
		return "1.1"
	case tls.VersionTLS10:
		return "1.0"
	default:
		return fmt.Sprintf("0x%x", v)
	}
}

/*
	  This implements net.Listener by:
		Returning your single tls.Conn once from Accept()
		Returning io.EOF afterward (so http.Server exits cleanly when done)
		Providing dummy Close() and Addr() implementations
*/
type singleUseListener struct {
	net.Conn
}

func (l *singleUseListener) Accept() (net.Conn, error) {
	if l.Conn == nil {
		return nil, io.EOF
	}
	c := l.Conn
	l.Conn = nil
	return c, nil
}

func (l *singleUseListener) Close() error   { return nil }
func (l *singleUseListener) Addr() net.Addr { return l.Conn.LocalAddr() }

func main() {
	var port string
	flag.StringVar(&port, "port", "8080", "Listen port")
	flag.StringVar(&KeyPath, "key", "", "path to key file. If empty, use a dummy self-signed certificate")
	flag.StringVar(&PemPath, "crt", "", "path to pem certificate file for the key.")
	flag.StringVar(&Proto, "proto", "http", "Proxy protocol (http or https)")
	flag.StringVar(&CachePath, "cache", "", "Cache directory path (default: OS temp dir)")
	flag.Int64Var(&DelaySec, "delay", -1, "Intentional delay in seconds for testing slowness")
	flag.BoolVar(&Debug, "debug", false, "Debug / verbose output (e.g. req/resp headers)")
	flag.BoolVar(&Debug2, "debug2", false, "More verbose output (e.g. dump req/resp body)")
	flag.Parse()

	if Debug2 {
		Debug = true
	}
	if Proto != "http" && Proto != "https" {
		log.Fatal("Currently Protocol must be either http or https")
	}
	// Save the respDump into a file under the CachePath if specified, if not specified, use OS's temp dir
	if CachePath == "" {
		CachePath = os.TempDir()
	}

	out("Listening on Proto: %s, port: %s", Proto, port)
	server := &http.Server{
		Addr:    ":" + port,
		Handler: http.HandlerFunc(handleRequest),
	}
	downloadPath := "https://raw.githubusercontent.com/hajimeo/samples/refs/heads/master/misc/"
	if len(KeyPath) == 0 {
		// If the file PemPath doesn't exist, automatically use https://raw.githubusercontent.com/hajimeo/samples/refs/heads/master/misc/...
		KeyPath = "./proxy.key"
		PemPath = "./proxy.crt"

		pemUrl := downloadPath + "standalone.localdomain.crt"
		debug("Downloading %s ...", pemUrl)
		readFromRemote(pemUrl, PemPath)

		keyUrl := downloadPath + "standalone.localdomain.key"
		debug("Downloading %s ...", keyUrl)
		readFromRemote(keyUrl, KeyPath)

		rootData := readFromRemote(downloadPath+"rootCA_standalone.crt", "./proxyCA.crt")
		out("Please make sure to trust the following certificate:\n%s", string(rootData))
	}

	genCaKeyFromFile(KeyPath)
	genCaCertFromFile(PemPath)

	if Proto == "http" {
		log.Fatal(server.ListenAndServe())
	} else {
		// To override TLS config to accept old versions and insecure skip verify
		tlsConfig := &tls.Config{
			MinVersion:         tls.VersionTLS10, // VersionTLS13
			InsecureSkipVerify: true,             // TODO: not sure if this is a good idea
			//Certificates:       []tls.Certificate{Cert},
		}
		server.TLSConfig = tlsConfig
		log.Fatal(server.ListenAndServeTLS(PemPath, KeyPath))
	}
}
