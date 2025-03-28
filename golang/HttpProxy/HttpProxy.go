// Copy of https://medium.com/@mlowicki/http-s-proxy-in-golang-in-less-than-100-lines-of-code-6a51c2f2c38c
/*
	curl -o /usr/local/bin/httpproxy -L https://github.com/hajimeo/samples/raw/master/misc/httpproxy_$(uname)_$(uname -m)
	chmod a+x /usr/local/bin/httpproxy

	curl -sSf -v --proxy http://localhost:8888/ -k -L https://www.google.com -o/dev/null
*/

package main

import (
	"crypto/tls"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"strings"
	"time"
)

var DelaySec int64
var Debug bool

func out(format string, v ...any) {
	log.Printf(format, v...)
}

func debug(format string, v ...any) {
	if Debug {
		out("DEBUG: "+format, v...)
	}
}

func dumpKeyValues(m map[string][]string) []string {
	var list []string
	for name, values := range m {
		for _, value := range values {
			list = append(list, fmt.Sprintf("%s: \"%s\"", name, value))
		}
	}
	return list
}

func handleTunneling(w http.ResponseWriter, r *http.Request) {
	out("Tunneling to %s\n", r.RequestURI)
	if Debug {
		debug("ReqHeaders %s\n", "["+strings.Join(dumpKeyValues(r.Header), ", ")+"]")
	}
	dest_conn, err := net.DialTimeout("tcp", r.Host, 10*time.Second)
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
	client_conn, _, err := hijacker.Hijack()
	if err != nil {
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
	}
	if DelaySec > 0 {
		debug("Delay %s for %d seconds\n", r.RequestURI, DelaySec)
		// sleep delay seconds
		time.Sleep(time.Duration(DelaySec) * time.Second)
	}
	go transfer(dest_conn, client_conn)
	go transfer(client_conn, dest_conn)
	debug("Completed %s\n", r.RequestURI)
}

func transfer(destination io.WriteCloser, source io.ReadCloser) {
	defer destination.Close()
	defer source.Close()
	io.Copy(destination, source)
}

func handleHTTP(w http.ResponseWriter, req *http.Request) {
	out("Connecting to %s\n", req.RequestURI)
	if Debug {
		debug("ReqHeaders %s\n", "["+strings.Join(dumpKeyValues(req.Header), ", ")+"]")
	}
	resp, err := http.DefaultTransport.RoundTrip(req)
	if err != nil {
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}
	defer resp.Body.Close()
	copyHeader(w.Header(), resp.Header)
	if Debug {
		debug("RspHeaders %s\n", "["+strings.Join(dumpKeyValues(resp.Header), ", ")+"]")
	}
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
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
	var pemPath string
	flag.StringVar(&pemPath, "pem", "server.pem", "path to pem file")
	var keyPath string
	flag.StringVar(&keyPath, "key", "server.key", "path to key file")
	var proto string
	flag.StringVar(&proto, "proto", "http", "Proxy protocol (http or https)")
	var port string
	flag.StringVar(&port, "port", "8888", "Listen port")
	flag.Int64Var(&DelaySec, "delay", -1, "Intentional delay in seconds")
	flag.BoolVar(&Debug, "debug", false, "Debug / verbose output")
	flag.Parse()
	if proto != "http" && proto != "https" {
		log.Fatal("Protocol must be either http or https")
	}
	log.Printf("Listening on port: %s\n", port)
	server := &http.Server{
		Addr: ":" + port,
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method == http.MethodConnect {
				handleTunneling(w, r)
			} else {
				handleHTTP(w, r)
			}
		}),
		// Disable HTTP/2.
		TLSNextProto: make(map[string]func(*http.Server, *tls.Conn, http.Handler)),
	}
	if proto == "http" {
		log.Fatal(server.ListenAndServe())
	} else {
		log.Fatal(server.ListenAndServeTLS(pemPath, keyPath))
	}
}
