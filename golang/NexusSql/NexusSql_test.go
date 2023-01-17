package main

import (
	"os"
	"testing"
)

var DUMMY_DB_PROPS_PATH = "/tmp/dummy-store.properties"
var DUMMY_DB_PROP_TXT = `#2022-08-14 20:58:43,970+0000
#Sun Aug 14 20:58:43 UTC 2022
password=xxxxxxxx
maximumPoolSize=10
jdbcUrl=jdbc\:postgresql\://192.168.1.1\:5433/nxrm3pg?ssl\=true&sslfactory\=org.postgresql.ssl.NonValidatingFactory
advanced=maxLifetime\=600000
username=nxrm3pg`

func writeContentsFile(path string, contents string) error {
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0666)
	if err != nil {
		return err
	}
	defer f.Close()
	byteLen, err := f.WriteString(contents)
	if byteLen < 0 || err != nil {
		return err
	}
	return err
}

func TestMain(m *testing.M) {
	// Prepare dummy file for tests
	err := writeContentsFile(DUMMY_DB_PROPS_PATH, DUMMY_DB_PROP_TXT)
	if err != nil {
		panic(err)
	}

	// Run tests
	exitVal := m.Run()
	// Write code here to run after tests
	// Exit with exit value from tests
	os.Exit(exitVal)
}

func TestReadPropertiesFile(t *testing.T) {
	props, err := readPropertiesFile(DUMMY_DB_PROPS_PATH)
	if err != nil {
		t.Errorf("readPropertiesFile failed with %s", err)
	}
	if props == nil {
		t.Errorf("DB connection props should not be empty")
	} else {
		t.Logf("props = %v", props)
	}
}
