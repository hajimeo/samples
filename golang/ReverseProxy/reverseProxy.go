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
	_SAVE_BODY_TO string  Save body strings into this location`)
}

var serverAddr string // Listening server address eg: $(hostname -f):8080
var proxyPass string  // forwarding proxy URL
var scheme string     // http or https (decided by given certificate)
var dumpBody bool     // If true, output
var saveBodyTo string // if dumpBody is true, save request/response bodies into files

func handler(p *httputil.ReverseProxy) func(http.ResponseWriter, *http.Request) {
	return func(w http.ResponseWriter, req *http.Request) {
		req.URL.Host = serverAddr
		req.URL.Scheme = scheme
		req.Header.Set("X-Real-IP", req.RemoteAddr)
		//req.Header.Set("X-Forwarded-For", req.RemoteAddr)	// TODO: not sure which value to use for client addr
		req.Header.Set("X-Forwarded-Proto", scheme)
		reqHeader, err := httputil.DumpRequest(req, dumpBody)
		if err != nil {
			log.Printf("DumpRequest error: %s\n", err)
		} else {
			log.Printf("REQUEST HEAD to %s\n%s\n", proxyPass, string(reqHeader))
			req.Body = logBody(req.Body, "REQUEST")
		}
		p.ServeHTTP(w, req)
	}
}

func logResponseHeader(resp *http.Response) (err error) {
	respHeader, err := httputil.DumpResponse(resp, dumpBody)
	if err != nil {
		log.Printf("DumpResponse error: %s\n", err)
	} else {
		log.Printf("RESPONSE HEAD from %s\n%s\n", proxyPass, string(respHeader))
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
	var logMsg string
	if len(saveBodyTo) > 0 {
		timeMsStr := strconv.FormatInt(time.Now().UnixNano()/1000000, 10)
		fname := saveBodyTo + "/" + timeMsStr + "_" + prefix + ".out"
		err := ioutil.WriteFile(fname, bodyBytes, 0644)
		if err != nil {
			panic(err)
		}
		logMsg = "saved into " + fname
	} else if len(bodyBytes) > 512 {
		logMsg = string(bodyBytes)[0:512] + "\n..."
	} else {
		logMsg = string(bodyBytes)
	}
	log.Printf("%s BODY: %s\n", prefix, logMsg)
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
		serverAddr = os.Args[1]
	}
	ptn := "/"
	if len(os.Args) > 2 {
		ptn = os.Args[2]
	}
	if len(os.Args) > 3 {
		proxyPass = os.Args[3]
	}
	certFile := ""
	if len(os.Args) > 4 {
		certFile = os.Args[4]
	}
	keyFile := ""
	if len(os.Args) > 5 {
		keyFile = os.Args[5]
	}
	dumpBody = false
	if os.Getenv("_DUMP_BODY") == "true" {
		dumpBody = true
		log.Printf("dumpBody is set to true.\n")
	}
	saveBodyTo = os.Getenv("_SAVE_BODY_TO")
	if len(saveBodyTo) > 0 {
		log.Printf("saveBodyTo is set to #{saveBodyTo}.\n")
	}

	// start reverse proxy
	remote, err := url.Parse(proxyPass)
	if err != nil {
		panic(err)
	}
	proxy := httputil.NewSingleHostReverseProxy(remote)
	proxy.ModifyResponse = logResponseHeader
	// registering handler function for this pattern
	http.HandleFunc(ptn, handler(proxy))
	log.Printf("Starting listener on %s\n\n", serverAddr)
	if len(keyFile) > 0 {
		scheme = "https"
		err = http.ListenAndServeTLS(serverAddr, certFile, keyFile, nil)
	} else {
		scheme = "http"
		err = http.ListenAndServe(serverAddr, nil)
	}
	if err != nil {
		panic(err)
	}
}
