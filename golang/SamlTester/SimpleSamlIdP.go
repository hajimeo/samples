/**
Original: https://github.com/d-rk/mini-saml-idp

Example env variables:
	export IDP_KEY=../../misc/standalone.localdomain.key IDP_CERT=../../misc/standalone.localdomain.crt USER_JSON=./samlIdp-simple.json IDP_BASE_URL="http://localhost:2080/" SERVICE_METADATA_URL="./nxrm3-metadata.xml"

To get IdP metadata:
	${IDP_BASE_URL%/}/metadata

go build -o ../../misc/simplesamlidp_$(uname) ./SimpleSamlIdP.go && env GOOS=linux GOARCH=amd64 go build -o ../../misc/simplesamlidp_Linux ./SimpleSamlIdP.go
*/

package main

import (
	"crypto"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"flag"
	"fmt"
	"github.com/crewjam/saml/logger"
	"github.com/crewjam/saml/samlidp"
	"github.com/pkg/errors"
	"github.com/zenazn/goji"
	"golang.org/x/crypto/bcrypt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

var key = func() crypto.PrivateKey {
	var keyData []byte
	if os.Getenv("IDP_KEY") != "" {
		var err error
		keyData, err = ioutil.ReadFile(os.Getenv("IDP_KEY"))
		if err != nil {
			logger.DefaultLogger.Fatalf("reading idp key: %s", err)
		}
	}
	b, _ := pem.Decode(keyData)
	k, err := x509.ParsePKCS1PrivateKey(b.Bytes)
	if err != nil {
		// try one more time
		k2, err2 := x509.ParsePKCS8PrivateKey(b.Bytes)
		if err2 != nil {
			logger.DefaultLogger.Fatalf("parsing idp key: %s / %s", err, err2)
		}
		return k2
	}
	return k
}()

var cert = func() *x509.Certificate {
	var certData []byte
	if os.Getenv("IDP_CERT") != "" {
		var err error
		certData, err = ioutil.ReadFile(os.Getenv("IDP_CERT"))
		if err != nil {
			logger.DefaultLogger.Fatalf("reading idp cert: %s", err)
		}
	}
	b, _ := pem.Decode(certData)
	c, err := x509.ParseCertificate(b.Bytes)
	if err != nil {
		logger.DefaultLogger.Fatalf("parsing idp cert: %s", err)
	}
	return c
}()

func main() {
	logr := logger.DefaultLogger
	// TODO: Use same format as glauth
	userJsonFilename := os.Getenv("USER_JSON")
	idpBaseUrlString := os.Getenv("IDP_BASE_URL")
	serviceUrlOrXml := os.Getenv("SERVICE_METADATA_URL")

	// If URL ends with "/", many places won't work.
	idpBaseUrlString = strings.TrimRight(idpBaseUrlString, "/")
	idpBaseURL, err := url.Parse(idpBaseUrlString)
	if err != nil {
		logr.Fatalf("cannot parse base URL: %v", err)
	}

	idpServer, err := samlidp.New(samlidp.Options{
		URL:         *idpBaseURL,
		Key:         key,
		Logger:      logr,
		Certificate: cert,
		Store:       &samlidp.MemoryStore{},
	})
	if err != nil {
		logr.Fatalf("create idp: %s", err)
	}

	addUsers(userJsonFilename, idpServer, logr)
	addService(idpServer, idpBaseURL, serviceUrlOrXml, logr)

	flag.Set("bind", ":"+idpBaseURL.Port())

	goji.Handle("/*", idpServer)
	goji.Serve()
}

func submitService(idpBaseURL *url.URL, serviceName string, respBody io.Reader) error {
	req, err := http.NewRequest("PUT", fmt.Sprintf("%s/services/%s", strings.TrimRight(idpBaseURL.String(), "/"), serviceName), respBody)
	if err != nil {
		return err
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNoContent {
		data, _ := ioutil.ReadAll(resp.Body)
		return errors.Errorf("status not ok: %d: %s", resp.StatusCode, data)
	}
	return nil
}

func addService(idpServer *samlidp.Server, idpBaseURL *url.URL, serviceUrlOrXml string, logr *log.Logger) {
	serviceName := "sample-service"
	queryMetaData := func() error {
		return nil
	}
	if _, err := os.Stat(serviceUrlOrXml); err == nil {
		queryMetaData = func() error {
			logr.Println("Reading " + serviceUrlOrXml)
			serviceMetadataReader, err := os.Open(serviceUrlOrXml)
			defer serviceMetadataReader.Close()
			if err != nil {
				return err
			}
			return submitService(idpBaseURL, serviceName, serviceMetadataReader)
		}
	} else {
		serviceURL, err := url.Parse(serviceUrlOrXml)
		if err != nil || serviceURL == nil {
			logr.Fatalf("cannot parse service URL: %v", err)
		}

		queryMetaData = func() error {
			logr.Println("Accessing " + serviceURL.String())
			// read saml metadata from url
			samlResp, err := http.Get(serviceURL.String())
			if err != nil {
				return err
			}
			if samlResp.StatusCode != http.StatusOK {
				data, _ := ioutil.ReadAll(samlResp.Body)
				return errors.Errorf("status not ok: %d: %s", samlResp.StatusCode, data)
			}
			return submitService(idpBaseURL, serviceName, samlResp.Body)
		}
	}

	go func() {
		var err error
		delay := 1 * time.Second

		for {
			time.Sleep(delay)
			err = queryMetaData()

			if err != nil {
				logr.Printf("get saml metadata from service failed: %v", err)
				delay = delay * 2
			} else {
				service := samlidp.Service{}
				_ = idpServer.Store.Get(fmt.Sprintf("/services/%s", serviceName), &service)
				logr.Printf("registered service: name=%s entityId=%s", serviceName, service.Metadata.EntityID)
				break
			}
		}
	}()
}

func addUsers(filename string, idpServer *samlidp.Server, logr *log.Logger) {

	f, err := os.Open(filename)
	if err != nil {
		logr.Fatalf("open %s: %s", filename, err)
	}

	var users []samlidp.User
	dec := json.NewDecoder(f)
	err = dec.Decode(&users)
	if err != nil {
		logr.Fatalf("decode json: %s", err)
	}
	f.Close()

	for _, user := range users {

		if user.PlaintextPassword != nil {
			hashedPassword, _ := bcrypt.GenerateFromPassword([]byte(*user.PlaintextPassword), bcrypt.DefaultCost)
			user.HashedPassword = hashedPassword
		}

		err = idpServer.Store.Put("/users/"+user.Name, user)
		if err != nil {
			logr.Fatalf("put user: %s", err)
		}
		logr.Printf("created user %s", user.Name)
	}
}
