/**
 * Based on https://gist.github.com/JalfResi/6287706
 *          https://qiita.com/convto/items/64e8f090198a4cf7a4fc (japanese)
 */
package main

import (
	"fmt"
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
    reverseproxy $(hostname -f):8080 / http://search.osakos.com/

Also, this script utilise the following environment variables:
	_DUMP_BODY    boolean Whether dump the request/response body
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
		req.Header.Set("X-Real-IP", req.RemoteAddr)
		//req.Header.Set("X-Forwarded-For", req.RemoteAddr)	// TODO: not sure which value to use
		req.Header.Set("X-Forwarded-Proto", scheme)
		bodyBytes, err := httputil.DumpRequest(req, dump_body)
		if err != nil {
			log.Printf("DumpRequest error: %s\n", err)
		} else {
			_logBody(bodyBytes, "REQUEST")
		}
		p.ServeHTTP(w, req)
	}
}

func logResponseHeader(resp *http.Response) (err error) {
	bodyBytes, err := httputil.DumpResponse(resp, dump_body)
	if err != nil {
		log.Printf("DumpResponse error: %s\n", err)
	} else {
		_logBody(bodyBytes, "RESPONSE")
	}
	return nil
}

func _logBody(bodyBytes []byte, prefix string) {
	var log_msg string
	if len(save_body_to) > 0 {
		tus := strconv.FormatInt(time.Now().Unix(), 10)
		fname := save_body_to + "/" + prefix + "_" + tus + ".out"
		err := ioutil.WriteFile(fname, bodyBytes, 0644)
		if err != nil {
			panic(err)
		}
		log_msg = "Saved into " + fname
	} else if len(bodyBytes) > 512 {
		log_msg = string(bodyBytes)[0:512] + " ..."
	} else {
		log_msg = string(bodyBytes)
	}
	log.Printf("%s: %s\n%s\n", prefix, proxy_pass, log_msg)
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
