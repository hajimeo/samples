/*
# INSTALL:
	curl -o /usr/local/bin/httpproxy -L https://github.com/hajimeo/samples/raw/master/misc/httpproxy_$(uname)_$(uname -m)
	chmod a+x /usr/local/bin/httpproxy

# Optional step (if didn't, generates self-signed CA automatically):
	openssl genrsa -out "./proxy.key" 4096
	openssl req -x509 -new -nodes -key "./proxy.key" -sha256 -days 3650 -out "./proxy.crt" -subj "/CN=My Proxy CA"

# Normal HTTP proxy (it works with https:// as well):
    httpproxy [--delay {n} --debug --debug2]
	# Test (no need to use -k)
	curl -v --proxy localhost:8080 http://search.osakos.com/index.php
	curl -v --proxy localhost:8080 https://search.osakos.com/index.php

# HTTP proxy but replacing certificate:
	# NOTE: If no --key/--crt, automatically uses self-signed CA
	httpproxy --replCert --debug --crt <path to pem certificate> --key <path to key>
	# Test (need -k as cert is replaced)
	curl -v --proxy localhost:8080 -k https://search.osakos.com/index.php

# TODO: HTTPS proxy with replacing certificate:
	# NOTE: If no --key/--crt, automatically uses self-signed CA
	httpproxy --replCert --proto https --debug [--crt <path to pem certificate> --key <path to key>]
	# Test (need --proxy-insecure and -k)
	curl -v --proxy https://localhost:8080/ --proxy-insecure -k https://search.osakos.com/index.php

	TODO: Write proper tests
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
var ReplCert bool
var KeyPath string
var CertPath string
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
func debug2(format string, v ...any) {
	if Debug2 {
		out("DEBUG2: "+format, v...)
	}
}

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
	//w.WriteHeader(http.StatusOK)	// TODO: not sure why this doesn't work
	_, err = clientConn.Write([]byte("HTTP/1.1 200 Connection established\r\n\r\n"))
	if err != nil {
		out("ERROR: clientConn.Write %s failed: %v", host, err)
		clientConn.Close()
		return
	}

	if !ReplCert {
		destConn, err := net.DialTimeout("tcp", req.Host, 20*time.Second)
		if err != nil {
			http.Error(w, err.Error(), http.StatusServiceUnavailable)
			return
		}

		go transfer(destConn, clientConn, hash+".req")
		go transfer(clientConn, destConn, hash+".resp")
		return
	}

	// TODO: Create a server-side TLS connection using a generated cert for the host
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

func transfer(destination io.WriteCloser, source io.ReadCloser, filename string) {
	defer destination.Close()
	defer source.Close()
	if Debug2 && filename != "" {
		fullpath := filepath.Join(CachePath, filename)
		// With io.TeeReader, instead of os.Stderr, write into a file
		// TODO: if .req, it becomes binary (https encrypted)
		w, _ := os.OpenFile(fullpath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		tee := io.TeeReader(source, w)
		debug("Saving body to %s\n", fullpath)
		io.Copy(destination, tee)
	} else {
		io.Copy(destination, source)
	}
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

	// TODO: Generate leaf certificate
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
	derBytes, err := x509.CreateCertificate(rand.Reader, &template, caCert, &priv.PublicKey, caKey)
	if err != nil {
		out("ERROR: x509.CreateCertificate %s error: %v", host, err)
		return nil, err
	}
	debug("Executed x509.CreateCertificate caCert: %v", caCert.Subject)

	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: derBytes})
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(priv)})

	debug2("Generated certificate for %s:\n%s", host, certPEM)
	debug2("Generated key for %s:\n%s", host, keyPEM)

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

func loadCA(certPath, keyPath string) {
	certPEM, err := os.ReadFile(certPath)
	if err != nil {
		log.Fatal("Failed to read CA cert:", err)
	}
	keyPEM, err := os.ReadFile(keyPath)
	if err != nil {
		log.Fatal("Failed to read CA key:", err)
	}

	// Parse CA certificate
	block, _ := pem.Decode(certPEM)
	if block == nil {
		log.Fatal("Failed to decode CA cert PEM")
	}
	caCert, err = x509.ParseCertificate(block.Bytes)
	if err != nil {
		log.Fatal("Failed to parse CA cert:", err)
	}

	// Parse CA private key (PKCS#1 or PKCS#8)
	block, _ = pem.Decode(keyPEM)
	if block == nil {
		log.Fatal("Failed to decode CA key PEM")
	}

	var parsedKey any
	parsedKey, err = x509.ParsePKCS1PrivateKey(block.Bytes)
	if err != nil {
		// Try PKCS#8 if PKCS#1 fails
		var pk any
		pk, err = x509.ParsePKCS8PrivateKey(block.Bytes)
		if err != nil {
			log.Fatal("Failed to parse CA key:", err)
		}
		parsedKey = pk
	}

	var ok bool
	caKey, ok = parsedKey.(*rsa.PrivateKey)
	if !ok {
		log.Fatal("CA key is not RSA type")
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

func generateSelfSignedCA(keyPath, crtPath string) error {
	// Generate RSA private key (4096 bits)
	priv, err := rsa.GenerateKey(rand.Reader, 4096)
	if err != nil {
		return err
	}

	// Create certificate template
	serialNumber, _ := rand.Int(rand.Reader, big.NewInt(1<<62))
	template := x509.Certificate{
		SerialNumber:          serialNumber,
		Subject:               pkix.Name{CommonName: "My Proxy CA"},
		NotBefore:             time.Now(),
		NotAfter:              time.Now().Add(3650 * 24 * time.Hour), // 10 years
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		IsCA:                  true,
		BasicConstraintsValid: true,
	}

	// Self-sign the certificate
	derBytes, err := x509.CreateCertificate(rand.Reader, &template, &template, &priv.PublicKey, priv)
	if err != nil {
		return err
	}

	// Write private key to file
	keyOut, err := os.Create(keyPath)
	if err != nil {
		return err
	}
	defer keyOut.Close()
	pem.Encode(keyOut, &pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(priv)})

	// Write certificate to file
	crtOut, err := os.Create(crtPath)
	if err != nil {
		return err
	}
	defer crtOut.Close()
	pem.Encode(crtOut, &pem.Block{Type: "CERTIFICATE", Bytes: derBytes})

	return nil
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
	flag.StringVar(&CertPath, "crt", "", "path to pem certificate file for the key.")
	flag.StringVar(&Proto, "proto", "http", "TODO: Proxy protocol (http or https)")
	flag.BoolVar(&ReplCert, "replCert", false, "Replacing the certificate for https:// requests")
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

	if ReplCert && len(KeyPath) == 0 {
		if _, err := os.Stat("./proxy.key"); err == nil {
			out("Using existing key file: proxy.key (and cert file)")
			KeyPath = "./proxy.key"
			CertPath = "./proxy.crt"
		}
	}

	if ReplCert && len(KeyPath) == 0 {
		KeyPath = "./proxy.key"
		CertPath = "./proxy.crt"
		err := generateSelfSignedCA(KeyPath, CertPath)
		if err != nil {
			log.Fatal("Failed to generate self-signed CA:", err)
		}
		out("Generated a self-signed certificate: %s, %s", KeyPath, CertPath)
	}

	if ReplCert {
		// Load CA cert and key for replacing certificate for HTTPS requests
		loadCA(CertPath, KeyPath)
		// Read CertPath data to show to user
		certBytes, err := os.ReadFile(CertPath)
		if err != nil {
			log.Fatal("Failed to read generated CA cert:", CertPath, err)
		}
		out("NOTE: Please make sure to trust the following certificate:\n%s", string(certBytes))
	}

	if Proto == "http" {
		log.Fatal(server.ListenAndServe())
	}

	out("WARN: Starting HTTPS with %s, %s (may not work)", CertPath, KeyPath)
	// To override TLS config to accept old versions and insecure skip verify
	/*
		tlsCert, err := tls.LoadX509KeyPair(CertPath, KeyPath)
		if err != nil {
			log.Fatal("Failed to load server certificate and key:", err)
		}
		tlsConfig := &tls.Config{
			MinVersion:         tls.VersionTLS10, // VersionTLS13
			InsecureSkipVerify: true,             // TODO: not sure if this is a good idea
			Certificates:       []tls.Certificate{tlsCert},
		}
		server.TLSConfig = tlsConfig
		log.Fatal(server.ListenAndServeTLS("", ""))
	*/
	log.Fatal(server.ListenAndServeTLS(CertPath, KeyPath))
}
