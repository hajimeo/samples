/**
 * Based on https://gist.github.com/JalfResi/6287706
 *          https://qiita.com/convto/items/64e8f090198a4cf7a4fc (japanese)
 *          https://pkg.go.dev/github.com/edaniels/go-saml
 */
package main

import (
	"context"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"github.com/crewjam/saml"
	"github.com/crewjam/saml/samlsp"
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
    reverseproxy $(hostname -f):8080 / http://search.osakos.com/

Use as a web server (receiver) with netcat command:
    while true; do nc -nlp 2222 &>/dev/null; done
    reverseproxy $(hostname -f):8080 / http://localhsot:2222

Also, this script utilise the following environment variables:
    _DUMP_BODY    boolean If true, dump the request/response body
    _SAVE_BODY_TO string  Save body strings into this location
SAML related:
    _SAML_ENABLED
    _SAML_IDP_URL or _SAML_SP_ENTITY_ID, _SAML_SP_URL, _SAML_SP_BINDING, _SAML_SP_SIGN_CERT`)
}

var serverAddr string // Listening server address eg: $(hostname -f):8080
var proxyPass string  // forwarding proxy URL
var scheme string     // http or https (decided by given certificate)
var dumpBody bool     // If true, output
var saveBodyTo string // if dumpBody is true, save request/response bodies into files
var samlIdpUrl string // If true, run as SAML SP testing mode

func deferPanic() {
	// recover from panic if one occured. Set err to nil otherwise.
	if err := recover(); err != nil {
		log.Println("panic occurred:", err)
	}
}

func handler(p *httputil.ReverseProxy) func(http.ResponseWriter, *http.Request) {
	return func(w http.ResponseWriter, req *http.Request) {
		req.URL.Host = serverAddr
		req.URL.Scheme = scheme
		req.Header.Set("X-Real-IP", req.RemoteAddr)
		//req.Header.Set("X-Forwarded-For", req.RemoteAddr)	// TODO: not sure which value to use
		req.Header.Set("X-Forwarded-Proto", scheme)
		_, err := httputil.DumpRequest(req, dumpBody)
		log.Printf("REQUEST HEAD: %s\n", req.Header)
		if err != nil {
			log.Printf("DumpRequest error: %s\n", err)
		} else {
			logBody(req.Body, "REQUEST")
		}
		p.ServeHTTP(w, req)
	}
}

func logResponseHeader(resp *http.Response) (err error) {
	_, err = httputil.DumpResponse(resp, dumpBody)
	log.Printf("RESPONSE HEAD: %s\n", resp.Header)
	if err != nil {
		log.Printf("DumpResponse error: %s\n", err)
	} else {
		logBody(resp.Body, "RESPONSE")
	}
	return nil
}

func logBody(body io.ReadCloser, prefix string) {
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
		logMsg = string(bodyBytes)[0:512] + " ..."
	} else {
		logMsg = string(bodyBytes)
	}
	log.Printf("%s BODY: %s\n", prefix, logMsg)
}

func Env(key string, fallback string) string {
	value, exists := os.LookupEnv(key)
	if exists {
		return value
	}
	return fallback
}

func EnvB(key string, fallback bool) bool {
	value, exists := os.LookupEnv(key)
	if exists {
		switch value {
		case
			"TRUE",
			"True",
			"true",
			"Y",
			"Yes",
			"YES":
			return true
		}
	}
	return fallback
}

func readRsaKeyCert(keyFile string, certFile string) (*rsa.PrivateKey, *x509.Certificate) {
	defer deferPanic()
	keyStr, err := ioutil.ReadFile(keyFile)
	if err != nil {
		log.Printf("keyFile %s is not readable", keyFile)
		return nil, nil
	}
	certStr, err := ioutil.ReadFile(certFile)
	if err != nil {
		log.Printf("certFile %s is not readable", certFile)
		return nil, nil
	}
	block, _ := pem.Decode([]byte(keyStr))
	key, err := x509.ParsePKCS1PrivateKey(block.Bytes)
	if err != nil {
		log.Printf("keyFile %s is not a valid key", keyFile)
		return nil, nil
	}
	block, _ = pem.Decode([]byte(certStr))
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		log.Printf("certFile %s is not a valid xwer", certFile)
		return nil, nil
	}
	return key, cert
}

// Dummy page displayed after authentication
func samlHello(w http.ResponseWriter, r *http.Request) {
	_, err := fmt.Fprintf(w, "Hello, %s!", r.Header.Get("X-Saml-Cn"))
	if err != nil {
		panic(err)
	}
}

// _SAML_IDP_URL, _SAML_SP_ENTITY_ID, _SAML_SP_URL, _SAML_SP_BINDING, _SAML_SP_SIGN_CERT
func samlLoadConfig(serverUrl string, keyFile string, certFile string) samlsp.Options {
	samlOptions := samlsp.Options{
		AllowIDPInitiated: true,
	}
	samlOptions.EntityID = Env("_SAML_SP_ENTITY_ID", "saml-test-sp")
	ssoURL := Env("_SAML_SP_URL", "")
	metadataURL := Env("_SAML_IDP_URL", "")
	if len(metadataURL) > 0 {
		log.Printf("Will attempt to load metadata from %s", metadataURL)
		idpMetadataURL, err := url.Parse(metadataURL)
		if err != nil {
			panic(err)
		}
		desc, err := samlsp.FetchMetadata(context.TODO(), http.DefaultClient, *idpMetadataURL)
		if err != nil {
			log.Printf("Failed to fetch the metadata from %s with err %+v", metadataURL, err)
		} else {
			samlOptions.IDPMetadata = desc
		}
	} else {
		//`urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST` or `urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect`
		binding := Env("_SAML_SP_BINDING", saml.HTTPPostBinding)
		samlOptions.IDPMetadata = &saml.EntityDescriptor{
			EntityID: samlOptions.EntityID,
			IDPSSODescriptors: []saml.IDPSSODescriptor{
				{
					SingleSignOnServices: []saml.Endpoint{
						{
							Binding:  binding,
							Location: ssoURL,
						},
					},
				},
			},
		}
		// PEM-encoded Certificate used for signing, with the PEM Header and all newlines removed.
		if signingCert := Env("_SAML_SP_SIGN_CERT", ""); signingCert != "" {
			samlOptions.IDPMetadata.IDPSSODescriptors[0].KeyDescriptors = []saml.KeyDescriptor{
				{
					Use: "singing",
					KeyInfo: saml.KeyInfo{
						X509Data: saml.X509Data{
							X509Certificates: []saml.X509Certificate{
								{
									Data: signingCert,
								},
							},
						},
					},
				},
			}
		}
	}
	urlStr := "https://" + serverUrl
	if len(keyFile) > 0 {
		urlStr = "http://" + serverUrl
	}
	spUrl, err := url.Parse(urlStr)
	if err != nil {
		panic(err)
	}
	samlOptions.URL = *spUrl
	// TODO: use https://github.com/hajimeo/saml-test-sp/blob/master/pkg/helpers/generate.go
	key, cert := readRsaKeyCert(keyFile, certFile)
	samlOptions.Key = key
	samlOptions.Certificate = cert
	log.Printf("Configuration Options: %+v", samlOptions)
	return samlOptions
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
	dumpBody = EnvB("_DUMP_BODY", false)
	saveBodyTo = Env("_SAVE_BODY_TO", "")
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
	samlEnabled := EnvB("_SAML_ENABLED", false)
	if samlEnabled {
		log.Printf("samlEnabled is set, so configuring this proxy for SAML.\n")
		samlSP, _ := samlsp.New(samlLoadConfig(serverAddr, keyFile, certFile))
		http.Handle("/hello", samlSP.RequireAccount(http.HandlerFunc(samlHello)))
		http.Handle("/saml/", samlSP)
	}
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
