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
	"time"
)

func main() {
	http.HandleFunc("/", handleConnect)
	log.Println("HTTPS MITM Proxy Listening on :8443")
	log.Fatal(http.ListenAndServe(":8443", nil))
}

func handleConnect(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodConnect {
		http.Error(w, "Only CONNECT supported", http.StatusMethodNotAllowed)
		return
	}

	// Hijack connection
	hijacker, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "Hijacking not supported", http.StatusInternalServerError)
		return
	}
	clientConn, _, err := hijacker.Hijack()
	if err != nil {
		log.Println("Hijack error:", err)
		return
	}
	defer clientConn.Close()

	// Acknowledge CONNECT
	clientConn.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n"))

	// Generate domain cert
	cert, err := generateCert(r.Host)
	if err != nil {
		log.Println("Cert error:", err)
		return
	}

	// Start TLS with client
	tlsClient := tls.Server(clientConn, &tls.Config{Certificates: []tls.Certificate{*cert}})
	if err := tlsClient.Handshake(); err != nil {
		log.Println("TLS handshake with client failed:", err)
		return
	}

	// Connect to target server
	serverConn, err := tls.Dial("tcp", r.Host, &tls.Config{InsecureSkipVerify: true})
	if err != nil {
		log.Println("Connect to target failed:", err)
		return
	}
	defer serverConn.Close()

	// Relay traffic
	go io.Copy(serverConn, tlsClient)
	io.Copy(tlsClient, serverConn)
}

// generateCert creates an on-the-fly certificate signed by a self-signed CA
func generateCert(host string) (*tls.Certificate, error) {
	// Create a temporary CA (should be persisted once in production)
	caCert := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{Organization: []string{"MITM Proxy CA"}},
		NotBefore:    time.Now(),
		NotAfter:     time.Now().Add(365 * 24 * time.Hour),
		IsCA:         true, KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageDigitalSignature,
		BasicConstraintsValid: true,
	}
	caKey, _ := rsa.GenerateKey(rand.Reader, 2048)
	caDER, _ := x509.CreateCertificate(rand.Reader, caCert, caCert, &caKey.PublicKey, caKey)
	caPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: caDER})
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(caKey)})
	ca, _ := tls.X509KeyPair(caPEM, keyPEM)

	// Domain cert
	certTmpl := &x509.Certificate{
		SerialNumber: big.NewInt(time.Now().Unix()),
		Subject:      pkix.Name{CommonName: host},
		NotBefore:    time.Now(),
		NotAfter:     time.Now().Add(365 * 24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	certKey, _ := rsa.GenerateKey(rand.Reader, 2048)
	certDER, _ := x509.CreateCertificate(rand.Reader, certTmpl, caCert, &certKey.PublicKey, caKey)

	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certDER})
	certKeyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(certKey)})

	parsed, err := tls.X509KeyPair(append(certPEM, caPEM...), certKeyPEM)
	return &parsed, err
}
