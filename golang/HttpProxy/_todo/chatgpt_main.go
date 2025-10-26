package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"io"
	"log"
	"math/big"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

var (
	caCert    *x509.Certificate
	caKey     *rsa.PrivateKey
	certCache = struct {
		sync.Mutex
		m map[string]*tls.Certificate
	}{m: make(map[string]*tls.Certificate)}
)

func main() {
	loadCA("server.pem", "server.key")

	server := &http.Server{
		Addr:    ":8080",
		Handler: http.HandlerFunc(handleRequest),
	}

	log.Println("Proxy listening on :8080")
	log.Fatal(server.ListenAndServe())
}

func handleRequest(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodConnect {
		handleConnect(w, r)
	} else {
		log.Printf("%s %s (host: %s)", r.Method, r.URL.String(), r.Host)
		http.DefaultTransport.RoundTrip(r)
	}
}

func handleConnect(w http.ResponseWriter, r *http.Request) {
	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "Hijacking not supported", http.StatusInternalServerError)
		return
	}

	clientConn, _, err := hj.Hijack()
	if err != nil {
		log.Println("Hijack error:", err)
		return
	}

	host := r.Host
	_, err = clientConn.Write([]byte("HTTP/1.1 200 Connection established\r\n\r\n"))
	if err != nil {
		clientConn.Close()
		return
	}

	// Create a server-side TLS connection using a generated cert for the host
	tlsCert, err := getCertForHost(host)
	if err != nil {
		log.Println("Cert error:", err)
		clientConn.Close()
		return
	}

	tlsConn := tls.Server(clientConn, &tls.Config{
		Certificates: []tls.Certificate{*tlsCert},
	})
	err = tlsConn.Handshake()
	if err != nil {
		log.Println("TLS handshake error:", err)
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

			log.Printf("→ %s %s (host: %s)", r.Method, r.URL.String(), host)

			// Use a fresh transport for the outgoing connection
			tr := &http.Transport{
				// You can set InsecureSkipVerify to true to bypass server cert checks while debugging.
				// Do NOT use that in production unless you understand the consequences.
				TLSClientConfig: &tls.Config{InsecureSkipVerify: false},
			}

			resp, err := tr.RoundTrip(r)
			if err != nil {
				log.Printf("RoundTrip error: %v", err)
				http.Error(w, err.Error(), http.StatusServiceUnavailable)
				return
			}
			defer resp.Body.Close()

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
		Subject:      pkix.Name{CommonName: host},
		NotBefore:    time.Now(),
		NotAfter:     time.Now().Add(365 * 24 * time.Hour),
		KeyUsage:     x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		DNSNames:     []string{strings.Split(host, ":")[0]},
	}

	priv, _ := rsa.GenerateKey(rand.Reader, 2048)
	derBytes, err := x509.CreateCertificate(rand.Reader, &template, caCert, &priv.PublicKey, caKey)
	if err != nil {
		return nil, err
	}

	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: derBytes})
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(priv)})

	cert, err := tls.X509KeyPair(certPEM, keyPEM)
	if err != nil {
		return nil, err
	}

	certCache.m[host] = &cert
	return &cert, nil
}

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
