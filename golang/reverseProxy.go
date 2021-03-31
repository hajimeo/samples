/**
 * Based on https://gist.github.com/JalfResi/6287706
 *          https://qiita.com/convto/items/64e8f090198a4cf7a4fc (japanese)
 */
package main

import (
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
)

func help() {
	fmt.Println(`
Simple reverse proxy server for troubleshooting.
Output REQUEST and RESPONSE headers.

DOWNLOAD and INSTALL:
    sudo curl -o /usr/local/bin/reverseproxy -L https://github.com/hajimeo/samples/raw/master/misc/reverseproxy_$(uname)
    sudo chmod a+x /usr/local/bin/reverseproxy
    
USAGE EXAMPLE:
    reverseproxy <listening address:port> <listening pattern> <remote-URL> [certFile] [keyFile] 
    reverseproxy $(hostname -f):8080 / http://search.osakos.com/

Also reads _DUMP_BODY environment variable. (TODO)
`)
}

var server_addr string
var proxy_pass string
var scheme string
var dump_body bool

func handler(p *httputil.ReverseProxy) func(http.ResponseWriter, *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		r.URL.Host = server_addr
		r.URL.Scheme = scheme
		r.Header.Set("X-Real-IP", r.RemoteAddr)
		//r.Header.Set("X-Forwarded-For", r.RemoteAddr)	// TODO: not sure which value to use
		r.Header.Set("X-Forwarded-Proto", scheme)
		reqHeader, err := httputil.DumpRequest(r, dump_body)
		if err != nil {
			log.Printf("DumpRequest error: %s\n", err)
		} else {
			log.Printf("REQUEST to: %s\n%s\n", proxy_pass, string(reqHeader))
		}
		p.ServeHTTP(w, r)
	}
}

func logResponseHeader(resp *http.Response) (err error) {
	respHeader, err := httputil.DumpResponse(resp, dump_body)
	if err != nil {
		log.Printf("DumpResponse error: %s\n", err)
	} else {
		log.Printf("RESPONSE from: %s\n%s\n", proxy_pass, string(respHeader))
	}
	return nil
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
