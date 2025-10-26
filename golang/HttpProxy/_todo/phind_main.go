package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"net/http"
	"time"

	"github.com/pkg/errors"
)

// CertificateGenerator handles dynamic certificate generation
type CertificateGenerator struct {
	caKey  *rsa.PrivateKey
	caCert *x509.Certificate
}

// NewCertificateGenerator initializes a new certificate generator with a root CA
func NewCertificateGenerator() (*CertificateGenerator, error) {
	// Create CA private key
	caKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, errors.Wrap(err, "failed to generate CA key")
	}

	// Create CA certificate
	caCert := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject: pkix.Name{
			Organization: []string{"Proxy CA"},
		},
		NotBefore:             time.Now(),
		NotAfter:              time.Now().AddDate(10, 0, 0),
		IsCA:                  true,
		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		BasicConstraintsValid: true,
	}

	caBytes, err := x509.CreateCertificate(rand.Reader, caCert, caCert, &caKey.PublicKey, caKey)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create CA certificate")
	}

	caCert, err = x509.ParseCertificate(caBytes)
	if err != nil {
		return nil, errors.Wrap(err, "failed to parse CA certificate")
	}

	return &CertificateGenerator{
		caKey:  caKey,
		caCert: caCert,
	}, nil
}

// GetCertificate generates a certificate for the given hostname
func (cg *CertificateGenerator) GetCertificate(hostname string) (*tls.Config, error) {
	// Generate server private key
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, errors.Wrap(err, "failed to generate server key")
	}

	// Create certificate signing request
	cert := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject: pkix.Name{
			CommonName:   hostname,
			Organization: []string{"Proxy Server"},
		},
		DNSNames:    []string{hostname},
		NotBefore:   time.Now(),
		NotAfter:    time.Now().Add(time.Hour * 24 * 365),
		KeyUsage:    x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}

	// Sign certificate with CA
	certBytes, err := x509.CreateCertificate(rand.Reader, cert, cg.caCert, &key.PublicKey, cg.caKey)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create certificate")
	}

	// Create TLS config
	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{
			{
				Certificate: [][]byte{certBytes},
				PrivateKey:  key,
			},
		},
		MinVersion: tls.VersionTLS12,
	}

	return tlsConfig, nil
}

// InterceptHandler handles HTTPS CONNECT requests and performs certificate replacement
func InterceptHandler(cg *CertificateGenerator) func(w http.ResponseWriter, r *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodConnect {
			http.Error(w, "Only CONNECT method is supported", http.StatusMethodNotAllowed)
			return
		}

		destConn, err := net.DialTimeout("tcp", r.URL.Host, 10*time.Second)
		if err != nil {
			http.Error(w, err.Error(), http.StatusServiceUnavailable)
			return
		}
		defer destConn.Close()

		hijacker, ok := w.(http.Hijacker)
		if !ok {
			http.Error(w, "Hijacker not supported", http.StatusInternalServerError)
			return
		}

		clientConn, _, err := hijacker.Hijack()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		defer clientConn.Close()

		// Send success response to client
		w.WriteHeader(http.StatusOK)

		// Generate certificate for the target host
		hostname := r.URL.Hostname()
		tlsConfig, err := cg.GetCertificate(hostname)
		if err != nil {
			fmt.Fprintf(clientConn, "HTTP/1.0 502 Bad Gateway\r\n\r\nFailed to generate certificate")
			return
		}

		// Create TLS server connection
		tlsServer := tls.Server(clientConn, tlsConfig)

		// Handle connections concurrently
		go func() {
			if err := tlsServer.Handshake(); err != nil {
				return
			}
			defer tlsServer.Close()

			// Forward traffic between connections
			go transfer(tlsServer.NetConn(), destConn)
			transfer(destConn, tlsServer.NetConn())
		}()
	}
}

func transfer(destination io.Writer, source io.Reader) {
	defer destination.(*net.TCPConn).CloseRead()
	buf := make([]byte, 32*1024)
	for {
		n, err := source.Read(buf)
		if err != nil {
			return
		}
		if _, err := destination.Write(buf[:n]); err != nil {
			return
		}
	}
}

func main() {
	// Initialize certificate generator
	cg, err := NewCertificateGenerator()
	if err != nil {
		panic(err)
	}

	// Set up HTTP handler
	handler := http.HandlerFunc(InterceptHandler(cg))

	// Start server
	fmt.Println("Starting HTTPS proxy on :8080...")
	if err := http.ListenAndServe(":8080", handler); err != nil {
		panic(err)
	}
}
