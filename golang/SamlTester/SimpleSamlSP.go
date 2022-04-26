/**
 * Based on https://pkg.go.dev/github.com/edaniels/go-saml#section-readme but it's too old and broken
 *
 * go build -o ../../misc/simplesamlsp_$(uname) SimpleSamlSP.go && env GOOS=linux GOARCH=amd64 go build -o ../../misc/simplesamlsp_Linux SimpleSamlSP.go
 */
package main

import (
	"context"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"github.com/crewjam/saml/samlsp"
	"github.com/hajimeo/samples/golang/helpers"
	"net/http"
	"net/url"
	"os"
)

func simplesamlsp_help() {
	fmt.Println(`
Simple SAML tester for troubleshooting.

DOWNLOAD and INSTALL:
    sudo curl -o /usr/local/bin/simplesamlsp -L https://github.com/hajimeo/samples/raw/master/misc/simplesamlsp_$(uname)
    sudo chmod a+x /usr/local/bin/simplesamlsp
    
USAGE EXAMPLE:
    simplesamlsp <listening address:port> <IDP metadata URL> [certFile] [keyFile]

    openssl req -x509 -newkey rsa:2048 -keyout myservice.key -out myservice.cert -days 365 -nodes -subj "/CN=$(hostname -f)"
    simplesamlsp $(hostname -f):8080 https://dh1.standalone.localdomain:8444/simplesaml/saml2/idp/metadata.php ./myservice.cert ./myservice.key`)
}

var _HOST_PORT string        // Listening server address eg: $(hostname -f):8080
var _IDP_METADATA_URL string // https://dh1.standalone.localdomain:8444/simplesaml/saml2/idp/metadata.php
var _CERT_PATH string
var _KEY_PATH string

func hello(w http.ResponseWriter, r *http.Request) {
	_, _ = fmt.Fprintf(w, "Hello, %s!", r.Header.Get("X-Saml-Cn"))
}

func setArgs() {
	if os.Args[1] == "-h" || os.Args[1] == "--help" {
		simplesamlsp_help()
		os.Exit(0)
	}
	helpers.DEBUG = helpers.UEnvB("_DEBUG", false)
	if len(os.Args) > 1 {
		_HOST_PORT = os.Args[1]
		helpers.ULog("DEBUG", "_HOST_PORT = "+_HOST_PORT)
	}
	if len(os.Args) > 2 {
		_IDP_METADATA_URL = os.Args[2]
		helpers.ULog("DEBUG", "_IDP_METADATA_URL = "+_IDP_METADATA_URL)
	}
	if len(os.Args) > 3 {
		_CERT_PATH = os.Args[3]
		helpers.ULog("DEBUG", "_CERT_PATH = "+_CERT_PATH)
	}
	if len(os.Args) > 4 {
		_KEY_PATH = os.Args[4]
		helpers.ULog("DEBUG", "_KEY_PATH = "+_KEY_PATH)
	}
}

func getSpURL(hostPort string) *url.URL {
	urlStr := "http://" + hostPort
	if len(_KEY_PATH) > 0 {
		urlStr = "https://" + hostPort
	}
	spUrl, err := url.Parse(urlStr)
	if err != nil {
		helpers.ULog("ERROR", "Could not generate URL from "+hostPort+" with "+_KEY_PATH)
		panic(err)
	}
	return spUrl
}

func main() {
	setArgs()

	helpers.ULog("DEBUG", "Getting IdP metadata from "+_IDP_METADATA_URL)
	idpMetadataURL, _ := url.Parse(_IDP_METADATA_URL)
	idpMetadata, err := samlsp.FetchMetadata(context.Background(), http.DefaultClient, *idpMetadataURL)
	if err != nil {
		helpers.ULog("ERROR", "Could not generate EntityDescriptor from _IDP_METADATA_URL:"+_IDP_METADATA_URL)
		panic(err)
	}

	keyPair, err := tls.LoadX509KeyPair(_CERT_PATH, _KEY_PATH)
	if err != nil {
		panic(err)
	}
	keyPair.Leaf, err = x509.ParseCertificate(keyPair.Certificate[0])
	if err != nil {
		panic(err)
	}

	spUrl := getSpURL(_HOST_PORT)
	samlSP, _ := samlsp.New(samlsp.Options{
		URL:         *spUrl,
		IDPMetadata: idpMetadata,
		Key:         keyPair.PrivateKey.(*rsa.PrivateKey),
		Certificate: keyPair.Leaf,
	})

	app := http.HandlerFunc(hello)
	http.Handle("/hello", samlSP.RequireAccount(app))
	http.Handle("/saml/", samlSP) // TODO: broken
	helpers.ULog("INFO", "Starting Simple SP on "+spUrl.String())
	if len(_KEY_PATH) > 0 {
		err = http.ListenAndServeTLS(_HOST_PORT, _CERT_PATH, _KEY_PATH, nil)
	} else {
		err = http.ListenAndServe(_HOST_PORT, nil)
	}
	if err != nil {
		helpers.ULog("ERROR", "ListenAndServe failed with "+_HOST_PORT)
		panic(err)
	}
	// TODO: 2022/04/26 18:14:37 http: TLS handshake error from 192.168.1.206:56149: remote error: tls: unknown certificate
}
