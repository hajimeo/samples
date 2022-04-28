/**
 * Based on https://pkg.go.dev/github.com/edaniels/go-saml#section-readme but it's too old and broken
 *
 * go build -o ../../misc/simplesamlsp_$(uname) SimpleSamlSP.go && env GOOS=linux GOARCH=amd64 go build -o ../../misc/simplesamlsp_Linux SimpleSamlSP.go;date
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
	"github.com/hajimeo/samples/golang/helpers"
	"io/ioutil"
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
    simplesamlsp $(hostname -f):8080 https://dh1.standalone.localdomain:8444/simplesaml/saml2/idp/metadata.php ./myservice.cert ./myservice.key
    simplesamlsp dh1.standalone.localdomain:8081 https://dh1.standalone.localdomain:8444/simplesaml/saml2/idp/metadata.php

ENVIRONMENT VARIABLES (all optional):
    _SAML_SP_META_URL  string  eg: http://dh1.standalone.localdomain:8081/service/rest/v1/security/saml/metadata
    _SAML_SP_ENTITY_ID string  eg: http://dh1.standalone.localdomain:8081/service/rest/v1/security/saml/metadata
    _SAML_SP_BIND_URL  string  eg: http://dh1.standalone.localdomain:8081/saml
    _SAML_SP_BINDING   string  eg: urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST
    _SAML_SP_SIGN_CERT string  TODO: PEM-encoded Certificate used for signing, without the PEM Header and all newlines.`)
}

var HOST_PORT string        // Listening server address eg: $(hostname -f):8080
var IDP_METADATA_URL string // https://dh1.standalone.localdomain:8444/simplesaml/saml2/idp/metadata.php
var CERT_PATH string
var KEY_PATH string

func login(w http.ResponseWriter, r *http.Request) {
	_, _ = fmt.Fprintf(w, "REQUEST HEADERS:\n%+v\n", r.Header)
	// TODO: add ore debugging output
}

func setArgs() {
	if os.Args[1] == "-h" || os.Args[1] == "--help" {
		simplesamlsp_help()
		os.Exit(0)
	}
	helpers.DEBUG = helpers.UEnvB("_DEBUG", false)
	if len(os.Args) > 1 {
		HOST_PORT = os.Args[1]
		helpers.ULog("DEBUG", "HOST_PORT = "+HOST_PORT)
	}
	if len(os.Args) > 2 {
		IDP_METADATA_URL = os.Args[2]
		helpers.ULog("DEBUG", "IDP_METADATA_URL = "+IDP_METADATA_URL)
	}
	if len(os.Args) > 3 {
		CERT_PATH = os.Args[3]
		helpers.ULog("DEBUG", "CERT_PATH = "+CERT_PATH)
	}
	if len(os.Args) > 4 {
		KEY_PATH = os.Args[4]
		helpers.ULog("DEBUG", "KEY_PATH = "+KEY_PATH)
	}
}

func GetSpUrlStr(hostPort string) string {
	urlStr := "http://" + hostPort
	if len(KEY_PATH) > 0 {
		urlStr = "https://" + hostPort
	}
	return urlStr + ""
}

func ReadRsaKeyCert(keyFile string, certFile string) (*rsa.PrivateKey, *x509.Certificate) {
	defer helpers.DeferPanic()
	var key *rsa.PrivateKey
	var cert *x509.Certificate
	if len(keyFile) > 0 {
		keyStr, err := ioutil.ReadFile(keyFile)
		if err != nil {
			helpers.ULog("ERROR", fmt.Sprintf("keyFile %s is not readable", keyFile))
			return nil, nil
		}
		blockKey, _ := pem.Decode([]byte(keyStr))
		key, err = x509.ParsePKCS1PrivateKey(blockKey.Bytes)
		if err != nil {
			helpers.ULog("ERROR", fmt.Sprintf("keyFile %s is not a valid key", keyFile))
			return nil, nil
		}
	}
	if len(certFile) > 0 {
		certStr, err := ioutil.ReadFile(certFile)
		if err != nil {
			helpers.ULog("ERROR", fmt.Sprintf("certFile %s is not readable", certFile))
			return nil, nil
		}
		blockCert, _ := pem.Decode([]byte(certStr))
		cert, err = x509.ParseCertificate(blockCert.Bytes)
		if err != nil {
			helpers.ULog("ERROR", fmt.Sprintf("certFile %s is not a valid certificate", certFile))
			return nil, nil
		}
	}
	return key, cert
}

func SamlLoadConfig(spUrlStr string, spBindUrlStr string, keyFile string, certFile string) samlsp.Options {
	// NOTE: Accept environment variables: _SAML_SP_META_URL, _SAML_SP_ENTITY_ID, _SAML_SP_BINDING, _SAML_SP_SIGN_CERT
	samlOptions := samlsp.Options{AllowIDPInitiated: true}
	samlOptions.EntityID = helpers.UEnv("_SAML_SP_ENTITY_ID", "saml-test-sp")
	spMetadataUrlStr := helpers.UEnv("_SAML_SP_META_URL", "")
	if len(spMetadataUrlStr) > 0 {
		helpers.ULog("DEBUG", "Getting SP metadata from "+spMetadataUrlStr)
		spMetadataUrl, err := url.Parse(spMetadataUrlStr)
		if err != nil {
			helpers.ULog("WARN", fmt.Sprintf("%s may not be a valid URL string. Ignoring ...", spMetadataUrlStr))
		} else {
			desc, err := samlsp.FetchMetadata(context.TODO(), http.DefaultClient, *spMetadataUrl)
			if err != nil {
				helpers.ULog("ERROR", fmt.Sprintf("Failed to fetch the metadata from %s", spMetadataUrlStr))
				panic(err)
			}
			helpers.ULog("DEBUG", fmt.Sprintf("FetchMetadata result: %+v", desc))
			samlOptions.IDPMetadata = desc
		}
	} else {
		//`urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST` or `urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect`
		binding := helpers.UEnv("_SAML_SP_BINDING", saml.HTTPPostBinding)
		samlOptions.IDPMetadata = &saml.EntityDescriptor{
			EntityID: samlOptions.EntityID,
			IDPSSODescriptors: []saml.IDPSSODescriptor{
				{
					SingleSignOnServices: []saml.Endpoint{
						{
							Binding:  binding,
							Location: spBindUrlStr,
						},
					},
				},
			},
		}
		// PEM-encoded Certificate used for signing, with the PEM Header and all newlines removed.
		if signCertPath := helpers.UEnv("_SAML_SP_SIGN_CERT", ""); signCertPath != "" {
			signingCert, err := ioutil.ReadFile(signCertPath)
			if err != nil {
				helpers.ULog("ERROR", fmt.Sprintf("%s may not be a valid signing certificate", signCertPath))
				panic(err)
			}
			samlOptions.IDPMetadata.IDPSSODescriptors[0].KeyDescriptors = []saml.KeyDescriptor{
				{
					Use: "singing",
					KeyInfo: saml.KeyInfo{
						X509Data: saml.X509Data{
							X509Certificates: []saml.X509Certificate{
								{
									Data: string(signingCert),
								},
							},
						},
					},
				},
			}
		}
	}

	spUrl, err := url.Parse(spUrlStr)
	if err != nil {
		helpers.ULog("ERROR", fmt.Sprintf("%s is not a vaild URL string", spUrlStr))
		panic(err)
	}
	samlOptions.URL = *spUrl
	key, cert := ReadRsaKeyCert(keyFile, certFile)
	samlOptions.Key = key
	samlOptions.Certificate = cert
	helpers.ULog("DEBUG", fmt.Sprintf("Configuration Options: %+v", samlOptions))
	return samlOptions
}

func main() {
	setArgs()
	bindPath := "/saml"
	spUrlStr := GetSpUrlStr(HOST_PORT)
	spBindUrlStr := helpers.UEnv("_SAML_SP_BIND_URL", spUrlStr+bindPath)
	helpers.ULog("DEBUG", "Generating SAML Config then MiddleWare with "+spBindUrlStr+", "+KEY_PATH+", "+CERT_PATH)
	config := SamlLoadConfig(spUrlStr, spBindUrlStr, KEY_PATH, CERT_PATH)
	myMiddleWare, err := samlsp.New(config)
	if err != nil {
		helpers.ULog("ERROR", fmt.Sprintf("samlsp.New failed with %+v", config))
		panic(err)
	}
	//myMiddleWare.OnError = func(w http.ResponseWriter, r *http.Request, err error) {/* Do something */}

	http.Handle(bindPath, myMiddleWare)
	http.Handle("/login", myMiddleWare.RequireAccount(http.HandlerFunc(login)))
	helpers.ULog("INFO", "Starting Simple SP on "+spUrlStr+"/login ("+config.URL.Path+"/metadata for metadata)")
	if len(KEY_PATH) > 0 {
		err = http.ListenAndServeTLS(HOST_PORT, CERT_PATH, KEY_PATH, nil)
	} else {
		err = http.ListenAndServe(HOST_PORT, nil)
	}
	if err != nil {
		helpers.ULog("ERROR", "ListenAndServe failed with "+HOST_PORT)
		panic(err)
	}
}
