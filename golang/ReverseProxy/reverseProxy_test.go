package main

import (
	"os"
	"testing"
)

func TestEnv(t *testing.T) {
	// Testing fallback
	fallback := Env("I_Should_not_exist", "No_You_Did_NOT")
	if fallback != "No_You_Did_NOT" {
		t.Errorf("Env with 'I_Should_not_exist', 'No_You_Did_NOT' didn't return No_You_Did_NOT.")
	}
	os.Setenv("I_Should_exist", "Yes_you_exist")
	fallback = Env("I_Should_exist", "You_should_not_get_this")
	if fallback != "Yes_you_exist" {
		t.Errorf("Env with 'I_Should_exist', 'You_should_not_get_this' didn't return Yes_you_exist.")
	}
	os.Unsetenv("I_Should_exist")
}

func TestEnvB(t *testing.T) {
	// Testing fallback
	fallback := EnvB("I_Should_not_exist", false)
	if fallback {
		t.Errorf("EnvB with 'I_Should_not_exist' did not return false.")
	}
	os.Setenv("I_Should_exist", "true")
	fallback = EnvB("I_Should_exist", false)
	if !fallback {
		t.Errorf("EnvB with 'I_Should_exist' didn't return true")
	}
	os.Unsetenv("I_Should_exist")
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
	key, cert := readRsaKeyCert(keyFile, certFile)
	if key == nil {
		t.Errorf("readRsaKeyCert returned nil Key")
	}
	if cert == nil {
		t.Errorf("readRsaKeyCert returned nil Cert")
	}
}

func TestSamlLoadConfig(t *testing.T) {
	//_SAML_IDP_URL or _SAML_SP_ENTITY_ID, _SAML_SP_URL, _SAML_SP_BINDING, _SAML_SP_SIGN_CERT
	os.Setenv("_SAML_IDP_URL", "https://dh1.standalone.localdomain:8444/simplesaml/saml2/idp/metadata.php")
	os.Setenv("_SAML_SP_ENTITY_ID", "SP-entity-id")
	os.Setenv("_SAML_SP_URL", "http://sp.test.local")
	os.Setenv("_SAML_SP_BINDING", "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST")
	//os.Setenv("_SAML_SP_SIGN_CERT", "")
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
	samlOptions := samlLoadConfig("localhost:8000", keyFile, certFile)
	//t.Logf("samlOptions = %v", samlOptions)
	if samlOptions.URL.Host != "localhost:8000" {
		t.Errorf("samlOptions.URL.Host:%s is not correct", samlOptions.URL.Host)
	}
}
