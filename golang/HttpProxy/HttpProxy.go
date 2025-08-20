/*
Originally based on https://medium.com/@mlowicki/http-s-proxy-in-golang-in-less-than-100-lines-of-code-6a51c2f2c38c
@see: https://eli.thegreenplace.net/2022/go-and-proxy-servers-part-2-https-proxies/
      https://github.com/eliben/code-for-blog/blob/main/2022/go-and-proxies/connect-mitm-proxy.go

	curl -o /usr/local/bin/httpproxy -L https://github.com/hajimeo/samples/raw/master/misc/httpproxy_$(uname)_$(uname -m)
	chmod a+x /usr/local/bin/httpproxy
    httpproxy [--debug --delay 3]
	curl -v --proxy localhost:8888 -k -L http://search.osakos.com/index.php

    openssl req -x509 -newkey rsa:2048 -keyout server.key -out server.pem -days 365 -nodes -subj "/CN=$(hostname -f)"
    httpproxy --proto https --debug
	curl -v --proxy https://localhost:8888/ --proxy-insecure -k -L https://search.osakos.com/index.php
*/

package main

import (
	"bufio"
	"crypto/tls"
	"flag"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
	"time"
)

var DelaySec int64
var Proto string
var KeyPath string
var PemPath string
var Debug bool
var Debug2 bool

func out(format string, v ...any) {
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

func handleTunneling(w http.ResponseWriter, req *http.Request) {
	out("Tunneling to %s\n", req.RequestURI)
	if Debug {
		if reqdump, err := httputil.DumpRequest(req, Debug2); err == nil {
			debug("Request: %s\n", reqdump)
		}
	}
	destConn, err := net.DialTimeout("tcp", req.Host, 10*time.Second)
	if err != nil {
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusOK)
	hijacker, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "Hijacking not supported", http.StatusInternalServerError)
		return
	}
	clientConn, _, err := hijacker.Hijack()
	if err != nil {
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
	}

	if Proto == "https" && Debug {
		// TODO: this should use the certificate singed by some (root) CA
		cert, err := tls.LoadX509KeyPair(PemPath, KeyPath)
		if err != nil {
			log.Fatalf("Failed to load certificate and key: %v", err)
		}
		tlsConfig := &tls.Config{
			CurvePreferences: []tls.CurveID{tls.X25519, tls.CurveP256},
			MinVersion:       tls.VersionTLS10,
			Certificates:     []tls.Certificate{cert},
		}
		tlsConn := tls.Server(clientConn, tlsConfig)
		defer tlsConn.Close()

		connReader := bufio.NewReader(tlsConn)

		r, err := http.ReadRequest(connReader)
		debug("ReadRequest err = %v\n", err)
		if err == io.EOF {
			return
		} else if err != nil {
			debug("http.ReadRequest failed\n")
			log.Fatal(err)
		}

		//debug("r.URL = %s\n", r.URL)	// "/index.php"
		changeRequestToTarget(r, req.Host)
		//debug("r.URL = %s\n", r.URL)	// "https://search.osakos.com:443/index.php"

		resp, err := http.DefaultClient.Do(r)
		if err != nil {
			log.Fatal("error sending request to target:", err)
		}
		if respDump, err := httputil.DumpResponse(resp, Debug2); err == nil {
			debug("Response: %s\n", respDump)
		}
		defer resp.Body.Close()

		// Send the target server's response back to the client.
		if err := resp.Write(tlsConn); err != nil {
			log.Println("error writing response back:", err)
		}
	} else {
		go transfer(destConn, clientConn)
		go transfer(clientConn, destConn)
	}
	debug("Completed %s\n", req.RequestURI)
}

func changeRequestToTarget(req *http.Request, targetHost string) {
	targetUrl := addrToUrl(targetHost)
	targetUrl.Path = req.URL.Path
	targetUrl.RawQuery = req.URL.RawQuery
	req.URL = targetUrl
	// Make sure this is unset for sending the request through a client
	req.RequestURI = ""
}

func addrToUrl(addr string) *url.URL {
	if !strings.HasPrefix(addr, "https") {
		addr = "https://" + addr
	}
	u, err := url.Parse(addr)
	if err != nil {
		log.Fatal(err)
	}
	return u
}

func transfer(destination io.WriteCloser, source io.ReadCloser) {
	defer destination.Close()
	defer source.Close()
	if Debug2 {
		//debug("Creating TeeReader for %s\n", source)	// Not so informative
		tee := io.TeeReader(source, os.Stderr)
		io.Copy(destination, tee)
	} else {
		io.Copy(destination, source)
	}
}

func handleHTTP(w http.ResponseWriter, req *http.Request) {
	out("Connecting to %s\n", req.RequestURI)
	if Debug {
		if reqdump, err := httputil.DumpRequest(req, Debug2); err == nil {
			debug("Request: %s\n", reqdump)
		}
	}
	resp, err := http.DefaultTransport.RoundTrip(req)
	if err != nil {
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}
	copyHeader(w.Header(), resp.Header)
	w.WriteHeader(resp.StatusCode)
	defer resp.Body.Close()
	if Debug {
		if respdump, err := httputil.DumpResponse(resp, Debug2); err == nil {
			debug("Request %s\n", respdump)
		}
	}
	if Debug2 {
		tee := io.TeeReader(resp.Body, os.Stderr)
		io.Copy(w, tee)
	} else {
		io.Copy(w, resp.Body)
	}
	debug("Completed %s\n", req.RequestURI)
}

func copyHeader(dst, src http.Header) {
	for k, vv := range src {
		for _, v := range vv {
			dst.Add(k, v)
		}
	}
}

func main() {
	flag.StringVar(&PemPath, "pem", "server.pem", "path to pem file")
	flag.StringVar(&KeyPath, "key", "server.key", "path to key file")
	flag.StringVar(&Proto, "proto", "http", "Proxy protocol (http or https)")
	var port string
	flag.StringVar(&port, "port", "8888", "Listen port")
	flag.Int64Var(&DelaySec, "delay", -1, "Intentional delay in seconds")
	flag.BoolVar(&Debug, "debug", false, "Debug / verbose output")
	flag.BoolVar(&Debug2, "debug2", false, "More verbose output")
	flag.Parse()

	if Debug2 {
		Debug = true
	}
	if Proto != "http" && Proto != "https" {
		log.Fatal("Currently Protocol must be either http or https")
	}
	log.Printf("Listening on Proto: %s: port: %s\n", Proto, port)
	server := &http.Server{
		Addr: ":" + port,
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// To simulate slowness
			if DelaySec > 0 {
				debug("Delay %s for %d seconds\n", r.RequestURI, DelaySec)
				// sleep delay seconds
				time.Sleep(time.Duration(DelaySec) * time.Second)
			}
			if r.Method == http.MethodConnect {
				handleTunneling(w, r)
			} else {
				handleHTTP(w, r)
			}
		}),
		// Disable HTTP/2 for HJ
		//TLSNextProto: make(map[string]func(*http.Server, *tls.Conn, http.Handler)),
	}
	if Proto == "http" {
		log.Fatal(server.ListenAndServe())
	} else {
		debug("Using TLS with PEM: %s and Key: %s", PemPath, KeyPath)
		//log.Fatal(server.ListenAndServeTLS(PemPath, KeyPath))
		// The below lines would be probably almost same as the above line, except accepting old TLS version.
		cert, err := tls.LoadX509KeyPair(PemPath, KeyPath)
		if err != nil {
			log.Fatalf("Failed to load certificate and key: %v", err)
		}
		tlsConfig := &tls.Config{
			MinVersion:   tls.VersionTLS10, // VersionTLS13
			Certificates: []tls.Certificate{cert},
		}
		server.TLSConfig = tlsConfig
		log.Fatal(server.ListenAndServeTLS("", ""))
	}
}
