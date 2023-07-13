package helpers

import (
	"os"
	"testing"
)

// To create DB, an easy way is running ./FileList_test.sh
// var TEST_DB_CONN_STR = "host=localhost port=5432 user=nxrm password=nxrm123 dbname=nxrmtest"
var TEST_DB_CONN_STR = ""
var DUMMY_FILE_PATH = "/tmp/00000000-abcd-ef00-12345-123456789abc.properties"
var DUMMY_PROP_TXT = `#2021-06-02 22:56:12,617+0000
#Wed Jun 02 22:56:12 UTC 2021
deletedDateTime=1622674572617
deleted=true
@BlobStore.created-by=system
creationTime=1622674572509
@BlobStore.created-by-ip=system
@BlobStore.content-type=text/x-yaml
sha1=c6b3eecd723b7b26fd92308e7ff25d1142059521
@BlobStore.blob-name=index.yaml
deletedReason=Updating asset AttachedEntityId{asset->\#24\:3384}
@Bucket.repo-name=nuget.org-proxy
size=63`

func TestMain(m *testing.M) {
	err := writeContentsFile(DUMMY_FILE_PATH, DUMMY_PROP_TXT)
	if err != nil {
		panic(err)
	}
	err = writeContentsFile(DUMMY_DB_PROPS_PATH, DUMMY_DB_PROP_TXT)
	if err != nil {
		panic(err)
	}
	_setGlobals()
	// Run tests
	exitVal := m.Run()
	// Write code here to run after tests
	// Exit with exit value from tests
	os.Exit(exitVal)
}

func TestReadPropertiesFile(t *testing.T) {
	props, _ := readPropertiesFile(DUMMY_DB_PROPS_PATH)
	dbConnStr := genDbConnStr(props)
	if !strings.Contains(dbConnStr, "host=192.168.1.1 port=5433 user=nxrm3pg password=xxxxxxxx dbname=nxrm3pg") {
		t.Errorf("DB connection string: %s is incorrect.", dbConnStr)
	}
}
