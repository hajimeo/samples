package main

import (
	"os"
	"testing"
)

func TestGetSpUrlStr(t *testing.T) {
	KEY_PATH = "some_file_path"
	urlStr := GetSpUrlStr("localhost:8000", "/saml/")
	if urlStr != "https://localhost:8000/saml/" {
		t.Errorf("GetSpUrlStr did not return https://localhost:8000/saml/")
	}
	KEY_PATH = ""
	urlStr = GetSpUrlStr("localhost:8000", "/saml/")
	if urlStr != "http://localhost:8000/saml/" {
		t.Errorf("GetSpUrlStr did not return http://localhost:8000/saml/")
	}
}

func TestReadRsaKeyCert(t *testing.T) {
	keyFile := "/var/tmp/share/cert/standalone.localdomain.key"
	certFile := "/var/tmp/share/cert/standalone.localdomain.crt"
	_, err := os.Stat(keyFile)
	if err != nil {
		t.Logf("Skipping TestreadRsaKeyCert as no %s", keyFile)
		return
	}
	_, err = os.Stat(certFile)
	if err != nil {
		t.Logf("Skipping TestreadRsaKeyCert as no %s", certFile)
		return
	}
	key, cert := ReadRsaKeyCert(keyFile, certFile)
	if key == nil {
		t.Errorf("readRsaKeyCert returned nil Key")
	}
	if cert == nil {
		t.Errorf("readRsaKeyCert returned nil Cert")
	}
}

func TestSamlLoadConfig(t *testing.T) {
	keyFile := "/var/tmp/share/cert/standalone.localdomain.key"
	certFile := "/var/tmp/share/cert/standalone.localdomain.crt"
	_, err := os.Stat(keyFile)
	if err != nil {
		keyFile = ""
	}
	_, err = os.Stat(certFile)
	if err != nil {
		certFile = ""
	}
	samlOptions := SamlLoadConfig("http://sp.test.local", "test-entity-id", "https://dh1.standalone.localdomain:8444/simplesaml/saml2/idp/metadata.php", keyFile, certFile)
	//t.Logf("samlOptions = %v", samlOptions)
	if samlOptions.URL.String() != "http://sp.test.local" {
		t.Errorf("samlOptions.URL.Host:%s is not correct", samlOptions.URL.Host)
	}
}
