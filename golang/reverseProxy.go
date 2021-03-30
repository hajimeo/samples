/**
 * Based on https://gist.github.com/JalfResi/6287706
 *          https://hackernoon.com/writing-a-reverse-proxy-in-just-one-line-with-go-c1edfa78c84b
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

DOWNLOAD and INSTALL:
    sudo curl -o /usr/local/bin/reverseproxy -L https://github.com/hajimeo/samples/raw/master/misc/reverseproxy_$(uname)
    sudo chmod a+x /usr/local/bin/reverseproxy
    
USAGE EXAMPLE:
    reverseproxy 0.0.0.0:8080 http://remote_url:port/path [/]
`)
}

var proxy_pass string

func handler(p *httputil.ReverseProxy) func(http.ResponseWriter, *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		rd, err := httputil.DumpRequest(r, true)
		if err != nil {
			log.Printf("DumpRequest error: %s", err)
		} else {
			log.Printf("proxy_url: %s\nrequest: %s\n", proxy_pass, string(rd))
		}
		//w.Header().Set("X-Forwarded-Host", r.Header.Get("Host"))
		//w.Header().Set("X-Real-IP", r.RemoteAddr)
		//w.Header().Set("X-Forwarded-For", r.RemoteAddr)
		//w.Header().Set("X-Forwarded-Proto", r.URL.Scheme)
		p.ServeHTTP(w, r)
	}
}

func main() {
	if len(os.Args) < 2 || os.Args[1] == "-h" || os.Args[1] == "--help" {
		help()
		os.Exit(0)
	}

	port := "0.0.0.0:8080"
	if len(os.Args) > 1 {
		port = os.Args[1]
	}
	if len(os.Args) > 2 {
		proxy_pass = os.Args[2]
	}
	ptn := "/"
	if len(os.Args) > 3 {
		ptn = os.Args[3]
	}

	remote, err := url.Parse(proxy_pass)
	if err != nil {
		panic(err)
	}

	proxy := httputil.NewSingleHostReverseProxy(remote)
	http.HandleFunc(ptn, handler(proxy))
	err = http.ListenAndServe(port, nil)
	if err != nil {
		panic(err)
	}
}
