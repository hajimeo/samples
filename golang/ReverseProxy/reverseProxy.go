/**
 * Based on https://gist.github.com/JalfResi/6287706
 *          https://qiita.com/convto/items/64e8f090198a4cf7a4fc (japanese)
 * go build -o ../../misc/reverseproxy_$(uname) reverseProxy.go && env GOOS=linux GOARCH=amd64 go build -o ../../misc/reverseproxy_Linux reverseProxy.go
 */
package main

import (
	"bytes"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strconv"
	"time"
)

func help() {
	fmt.Println(`
Simple reverse proxy server for troubleshooting.
This script outputs REQUEST and RESPONSE headers.

DOWNLOAD and INSTALL:
    sudo curl -o /usr/local/bin/reverseproxy -L https://github.com/hajimeo/samples/raw/master/misc/reverseproxy_$(uname)
    sudo chmod a+x /usr/local/bin/reverseproxy
    
USAGE EXAMPLE:
    reverseproxy <listening address:port> <listening pattern> <remote-URL> [certFile] [keyFile] 
    reverseproxy $(hostname -f):28443 / http://search.osakos.com/ /var/tmp/share/cert/standalone.localdomain.crt /var/tmp/share/cert/standalone.localdomain.key

Use as a web server (receiver) with netcat command:
    while true; do nc -nlp 2222 &>/dev/null; done
    reverseproxy $(hostname -f):8080 / http://localhsot:2222

Also, this script utilise the following environment variables:
	_DUMP_BODY    boolean If true, dump the request/response body
	_SAVE_BODY_TO string  Save body strings into this location
`)
}

var server_addr string  // Listening server address eg: $(hostname -f):8080
var proxy_pass string   // forwarding proxy URL
var scheme string       // http or https (decided by given certificate)
var dump_body bool      // If true, output
var save_body_to string // if dump_body is true, save request/response bodies into files

func handler(p *httputil.ReverseProxy) func(http.ResponseWriter, *http.Request) {
	return func(w http.ResponseWriter, req *http.Request) {
		req.URL.Host = server_addr
		req.URL.Scheme = scheme
		req.Header.Set("X-Real-IP", r.RemoteAddr)
		//r.Header.Set("X-Forwarded-For", req.RemoteAddr)	// TODO: not sure which value to use for client addr
		req.Header.Set("X-Forwarded-Proto", scheme)
		reqHeader, err := httputil.DumpRequest(req, dump_body)
		if err != nil {
			log.Printf("DumpRequest error: %s\n", err)
		} else {
			log.Printf("REQUEST HEAD to %s\n%s\n", proxy_pass, string(reqHeader))
			req.Body = logBody(req.Body, "REQUEST")
		}
		p.ServeHTTP(w, req)
	}
}

func logResponseHeader(resp *http.Response) (err error) {
	respHeader, err := httputil.DumpResponse(resp, dump_body)
	if err != nil {
		log.Printf("DumpResponse error: %s\n", err)
	} else {
		log.Printf("RESPONSE HEAD from %s\n%s\n", proxy_pass, string(respHeader))
		resp.Body = logBody(resp.Body, "RESPONSE")
	}
	return nil
}

func logBody(body io.ReadCloser, prefix string) (bodyRewinded io.ReadCloser) {
	bodyBytes, err := ioutil.ReadAll(body)
	if err != nil {
		log.Printf("ioutil.ReadAll error: %s\n", err)
		return
	}
	var log_msg string
	if len(save_body_to) > 0 {
		time_ms_str := strconv.FormatInt(time.Now().UnixNano()/1000000, 10)
		fname := save_body_to + "/" + time_ms_str + "_" + prefix + ".out"
		err := ioutil.WriteFile(fname, bodyBytes, 0644)
		if err != nil {
			panic(err)
		}
		log_msg = "saved into " + fname
	} else if len(bodyBytes) > 512 {
		log_msg = string(bodyBytes)[0:512] + "\n..."
	} else {
		log_msg = string(bodyBytes)
	}
	log.Printf("%s BODY: %s\n", prefix, log_msg)
	//https://stackoverflow.com/questions/33532374/in-go-how-can-i-reuse-a-readcloser
	return ioutil.NopCloser(bytes.NewReader(bodyBytes))
}

func main() {
	// Not enough args or help is asked, show help()
	if len(os.Args) < 4 || os.Args[1] == "-h" || os.Args[1] == "--help" {
		help()
		os.Exit(0)
	}
	// using microseconds (couldn't find how-to for milliseconds)
	log.SetFlags(log.LstdFlags | log.Lmicroseconds)

	// handling args
	if len(os.Args) > 1 {
		server_addr = os.Args[1]
	}
	ptn := "/"
	if len(os.Args) > 2 {
		ptn = os.Args[2]
	}
	if len(os.Args) > 3 {
		proxy_pass = os.Args[3]
	}
	certFile := ""
	if len(os.Args) > 4 {
		certFile = os.Args[4]
	}
	keyFile := ""
	if len(os.Args) > 5 {
		keyFile = os.Args[5]
	}
	dump_body = false
	if os.Getenv("_DUMP_BODY") == "true" {
		dump_body = true
		log.Printf("dump_body is set to true.\n")
	}
	save_body_to = os.Getenv("_SAVE_BODY_TO")
	if len(save_body_to) > 0 {
		log.Printf("save_body_to is set to #{save_body_to}.\n")
	}

	// start reverse proxy
	remote, err := url.Parse(proxy_pass)
	if err != nil {
		panic(err)
	}
	proxy := httputil.NewSingleHostReverseProxy(remote)
	proxy.ModifyResponse = logResponseHeader
	// registering handler function for this pattern
	http.HandleFunc(ptn, handler(proxy))
	log.Printf("Starting listener on %s\n\n", server_addr)
	if len(keyFile) > 0 {
		scheme = "https"
		err = http.ListenAndServeTLS(server_addr, certFile, keyFile, nil)
	} else {
		scheme = "http"
		err = http.ListenAndServe(server_addr, nil)
	}
	if err != nil {
		panic(err)
	}
}
