/*
Originally based on https://medium.com/@mlowicki/http-s-proxy-in-golang-in-less-than-100-lines-of-code-6a51c2f2c38c
@see: https://eli.thegreenplace.net/2022/go-and-proxy-servers-part-2-https-proxies/
      https://github.com/eliben/code-for-blog/blob/main/2022/go-and-proxies/connect-mitm-proxy.go

# INSTALL:
	curl -o /usr/local/bin/httpproxy -L https://github.com/hajimeo/samples/raw/master/misc/httpproxy_$(uname)_$(uname -m)
	chmod a+x /usr/local/bin/httpproxy

# Normal HTTP proxy (it works with https):
    httpproxy [--delay {n} --debug --debug2]
	# Test
	curl -v --proxy localhost:8888 -k -L http://search.osakos.com/index.php

# TODO: HTTPS proxy (without replacing certificate):
	# If no --key/--pem, automatically uses standalone.localdomain.crt/.key.
	httpproxy --proto https --debug [--pem <path to pem> --key <path to key>]
	# Test (need to trust rootCA_standalone.crt or with --proxy-insecure)
	curl -v --proxy https://localhost:8888/ --proxy-insecure -L https://search.osakos.com/index.php

# TODO: HTTPS proxy with replacing certificate:
	httpproxy --proto https --replCert --debug
	# Test (as replaced, --insecure/-k is needed)
	curl -v --proxy https://localhost:8888/ --proxy-insecure -k -L https://search.osakos.com/index.php

	TODO: Write proper tests
	TODO: '--proto https' is not working.
		  TLS handshake error from 127.0.0.1:64364: tls: first record does not look like a TLS handshake
*/

package main

import (
	"bufio"
	"bytes"
	"crypto/md5"
	"crypto/tls"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

var DelaySec int64
var Proto string
var KeyPath string
var PemPath string
var ReplCert bool
var Cert tls.Certificate
var CachePath string
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

func debug2(format string, v ...any) {
	if Debug2 {
		out("DEBUG2: "+format, v...)
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
	hash := ""
	if Debug {
		reqDump, err := httputil.DumpRequest(req, false)
		if err != nil {
			debug("DumpRequest failed for %s: %v\n", req.RequestURI, err)
		} else {
			// Use md5sum of reqDump as the hash because 'body' is false
			hash = fmt.Sprintf("%x", md5.Sum(reqDump))
			debug("Request: %s\n%s\n", hash, reqDump)
			if Debug2 {
				req.Body = saveBodyToFile(req.Body, hash+".req")
			}
		}
	}
	// Used only when Proto is https and Debug is true
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

	if Proto == "https" && ReplCert {
		// This TLS is for replacing the certificateextra debugging such as saving req/resp (`curl` needs --insecure/-k)
		// NOTE: the Cert should be generated with proper CN / SAN to avoid client errors
		//cert, err := tls.LoadX509KeyPair("server.pem", "server.key")
		tlsConfig := &tls.Config{
			CurvePreferences:   []tls.CurveID{tls.X25519, tls.CurveP256},
			MinVersion:         tls.VersionTLS10,
			Certificates:       []tls.Certificate{Cert},
			InsecureSkipVerify: true, // TODO: not sure if this is a good idea
		}
		tlsConn := tls.Server(clientConn, tlsConfig)
		defer tlsConn.Close()
		connReader := bufio.NewReader(tlsConn)
		r, err := http.ReadRequest(connReader)
		if err == io.EOF {
			return
		} else if err != nil {
			//log.Fatal(err)	// no need to stop, i think
			out("ERROR: ReadRequest to %s failed. %v\n", req.RequestURI, err)
			return
		}

		debug2("r.URL = %s\n", r.URL) // "/index.php"
		changeRequestToTarget(r, req.Host)
		debug2("r.URL = %s\n", r.URL) // "https://search.osakos.com:443/index.php"

		resp, err := http.DefaultClient.Do(r)
		if err != nil {
			out("ERROR: Sending request to %s failed. %v\n", req.RequestURI, err)
			return
		}
		respDump, err := httputil.DumpResponse(resp, false)
		if err != nil {
			debug("DumpResponse failed for %s failed. %v\n", req.RequestURI, err)
		} else {
			debug("Response: %s\n", respDump)
			if Debug2 {
				resp.Body = saveBodyToFile(resp.Body, hash+".resp")
			}
		}
		defer resp.Body.Close()

		// Send the target server's response back to the client.
		if err := resp.Write(tlsConn); err != nil {
			out("ERROR: Writing response back failed for %s failed. %v\n", req.RequestURI, err)
			return
		}
	} else {
		go transfer(destConn, clientConn, hash+".req")
		go transfer(clientConn, destConn, hash+".resp")
	}
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

// Not in use currently
func reqToUrlStr(req *http.Request) string {
	if req.URL.Scheme == "" {
		if req.TLS != nil {
			req.URL.Scheme = "https"
		} else {
			req.URL.Scheme = "http"
		}
	}
	fullURL := &url.URL{
		Scheme:   req.URL.Scheme,
		Host:     req.URL.Host,
		Path:     req.URL.Path,
		RawQuery: req.URL.RawQuery,
	}
	return fullURL.String()
}

func transfer(destination io.WriteCloser, source io.ReadCloser, filename string) {
	defer destination.Close()
	defer source.Close()
	if Debug2 && filename != "" {
		fullpath := filepath.Join(CachePath, filename)
		// With io.TeeReader, instead of os.Stderr, write into a file
		// TODO: if .req, it becomes binary (or https encrypted)
		w, _ := os.OpenFile(fullpath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		tee := io.TeeReader(source, w)
		debug("Saving body to %s\n", fullpath)
		io.Copy(destination, tee)
	} else {
		io.Copy(destination, source)
	}
}

func handleHTTP(w http.ResponseWriter, req *http.Request) {
	hash := ""
	if Debug {
		reqDump, err := httputil.DumpRequest(req, false)
		if err != nil {
			debug("DumpRequest failed for %s: %v\n", req.RequestURI, err)
		} else {
			hash = fmt.Sprintf("%x", md5.Sum(reqDump))
			debug("Request: %s\n%s\n", hash, reqDump)
			if Debug2 {
				req.Body = saveBodyToFile(req.Body, hash+".req")
			}
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
		respDump, err := httputil.DumpResponse(resp, false)
		if err != nil {
			debug("DumpResponse failed for %s failed. %v\n", req.RequestURI, err)
		} else {
			debug("Response %s\n", respDump)
			if Debug2 {
				resp.Body = saveBodyToFile(resp.Body, hash+".resp")
			}
		}
	}
	io.Copy(w, resp.Body)
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
		//debug("Not saving body as empty\n")
		return save
	}
	data, err := io.ReadAll(newBody)
	if err != nil {
		log.Printf("ERROR: Failed to read the body: %v\n", err)
		return save
	}
	// TODO: this may overwrite an existing file? as md5 includes header, maybe OK?
	fullpath := filepath.Join(CachePath, filename)
	err = os.WriteFile(fullpath, data, 0644)
	if err != nil {
		log.Printf("ERROR: Failed to write the body to %s: %v\n", fullpath, err)
	} else {
		debug("Saved body to %s\n", fullpath)
	}
	return save
}

func readFromRemote(downloadUrl string, saveTo string) []byte {
	resp, err := http.Get(downloadUrl)
	if err != nil {
		log.Fatalf("Failed to download PEM file from %s: %v", downloadUrl, err)
	}
	defer resp.Body.Close()
	debug("Downloaded PEM file from %s\n", downloadUrl)
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Fatalf("Failed to read PEM file from %s: %v", downloadUrl, err)
	}

	if len(saveTo) > 0 {
		// write to specified file
		err = os.WriteFile(saveTo, data, 0644)
		if err != nil {
			log.Printf("ERROR: Failed to write the body to %s: %v\n", saveTo, err)
		} else {
			debug("Saved body to %s\n", saveTo)
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

func main() {
	flag.StringVar(&KeyPath, "key", "", "path to key file. If empty, use a dummy self-signed certificate")
	flag.StringVar(&PemPath, "pem", "", "path to pem file for the key.")
	flag.StringVar(&Proto, "proto", "http", "Proxy protocol (http or https)")
	var port string
	flag.StringVar(&port, "port", "8888", "Listen port")
	flag.BoolVar(&ReplCert, "replCert", false, "with '-proto https', replacing the certificate on HTTPS tunneling")
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

	log.Printf("Listening on Proto: %s, port: %s\n", Proto, port)
	server := &http.Server{
		Addr: ":" + port,
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			// To simulate slowness
			if DelaySec > 0 {
				debug("Delay %s for %d seconds\n", r.RequestURI, DelaySec)
				// sleep delay seconds
				time.Sleep(time.Duration(DelaySec) * time.Second)
			}

			// TODO: the URL.String should return the full URL, but doesn't work if HTTPS. Tried reqToUrlStr()
			reqURLStr := r.URL.String()
			debug("Connecting to %s\n", reqURLStr)
			if r.Method == http.MethodConnect {
				handleTunneling(w, r)
			} else {
				handleHTTP(w, r)
			}
			elapsed := time.Since(start)
			// Show the elapsed time in seconds with 3 decimal places
			out("Completed %s (%.3f s)\n", reqURLStr, elapsed.Seconds())
		}),
		// Disable HTTP/2 for HJ
		//TLSNextProto: make(map[string]func(*http.Server, *tls.Conn, http.Handler)),
	}
	if Proto == "http" {
		log.Fatal(server.ListenAndServe())
	} else {
		var err error

		// If the file PemPath doesn't exist, automatically use https://raw.githubusercontent.com/hajimeo/samples/refs/heads/master/misc/...
		if len(KeyPath) == 0 {
			downloadPath := "https://raw.githubusercontent.com/hajimeo/samples/refs/heads/master/misc/"
			pemUrl := downloadPath + "standalone.localdomain.crt"
			out("Downloading %s ...\n", pemUrl)
			pemData := readFromRemote(pemUrl, "./server.pem")
			keyUrl := downloadPath + "standalone.localdomain.key"
			out("Downloading %s ...\n", keyUrl)
			keyData := readFromRemote(keyUrl, "./server.key")
			KeyPath = "./server.key"
			PemPath = "./server.pem"
			out("Using downloaded TLS with PEM: %s and Key: %s", PemPath, KeyPath)

			Cert, err = tls.X509KeyPair(pemData, keyData)
			if err != nil {
				log.Fatalf("Failed to generate certificate: %v", err)
			}
			rootData := readFromRemote(downloadPath+"rootCA_standalone.crt", "")
			out("Please make sure to trust the following certificate:\n%s\n", string(rootData))
		} else {
			out("Using TLS with PEM: %s and Key: %s", PemPath, KeyPath)
			//log.Fatal(server.ListenAndServeTLS(PemPath, KeyPath))
			// The below lines would be probably almost same as the above line, except accepting old TLS version.
			Cert, err = tls.LoadX509KeyPair(PemPath, KeyPath)
			if err != nil {
				log.Fatalf("Failed to load certificate and key: %v", err)
			}
		}

		tlsConfig := &tls.Config{
			MinVersion:         tls.VersionTLS10, // VersionTLS13
			Certificates:       []tls.Certificate{Cert},
			InsecureSkipVerify: true, // TODO: not sure if this is a good idea and not working
		}
		server.TLSConfig = tlsConfig
		log.Fatal(server.ListenAndServeTLS(PemPath, KeyPath))
	}
}
