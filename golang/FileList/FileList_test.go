// https://go.dev/doc/tutorial/add-a-test
package main

import (
	"flag"
	"os"
	"strings"
	"testing"
	"time"
)

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
@Bucket.repo-name=helm-hosted
size=63`

func TestMain(m *testing.M) {
	_setGlobals()
	// Run tests
	exitVal := m.Run()
	// Write code here to run after tests
	// Exit with exit value from tests
	os.Exit(exitVal)
}

func TestPrintLine(t *testing.T) {
	err := _writeToFile(DUMMY_FILE_PATH, DUMMY_PROP_TXT)
	if err != nil {
		t.Errorf("Preparing test failed with %s", err)
	}
	fInfo, _ := os.Lstat(DUMMY_FILE_PATH)
	if !printLine(DUMMY_FILE_PATH, fInfo, nil) {
		t.Errorf("printLine failed with all default global variables")
		flag.PrintDefaults()
	}
}

func TestGetPathWithoutExt(t *testing.T) {
	pathWoExt := getPathWithoutExt(DUMMY_FILE_PATH)
	if pathWoExt != "/tmp/00000000-abcd-ef00-12345-123456789abc" {
		t.Errorf("getPathWithoutExt with %s didn't return '/tmp/00000000-abcd-ef00-12345-123456789abc'", DUMMY_FILE_PATH)
	}
}

func TestGetBaseNameWithoutExt(t *testing.T) {
	fileName := getBaseNameWithoutExt(DUMMY_FILE_PATH)
	if fileName != "00000000-abcd-ef00-12345-123456789abc" {
		t.Errorf("getBaseNameWithoutExt with %s didn't return '00000000-abcd-ef00-12345-123456789abc'", DUMMY_FILE_PATH)
	}
}

func TestGetBlobSize(t *testing.T) {
	size := getBlobSize(DUMMY_FILE_PATH)
	if size != 0 {
		t.Errorf("As no .bytes file, should be 0")
	}
}

func TestGetNowStr(t *testing.T) {
	isoFmtStr := getNowStr()
	currentTimeStr := time.Now().Format("2006-01-02")
	if !strings.Contains(isoFmtStr, currentTimeStr) {
		t.Errorf("getNowStr may not return ISO format datetime: %s", isoFmtStr)
	}
}

func TestGetContents(t *testing.T) {
	err := _writeToFile(DUMMY_FILE_PATH, DUMMY_PROP_TXT)
	if err != nil {
		t.Errorf("Preparing test failed with %s", err)
	}
	contents, err := getContents(DUMMY_FILE_PATH)
	if err != nil {
		t.Errorf("getContents failed with %s", err)
	}
	if contents != DUMMY_PROP_TXT {
		t.Errorf("getContents didn't return expected txt (length:%d vs. %d)", len(contents), len(DUMMY_PROP_TXT))
	}
}

func TestQueryDb(t *testing.T) {
	rtn := queryDb("This should return nil", nil)
	if len(*_DB_CON_STR) == 0 && rtn != nil {
		t.Errorf("queryDb should return nil when no _DB_CON_STR")
	}
	// TODO: Use mock to test this function properly
}

func TestGenBlobIdCheckingQuery(t *testing.T) {
	_writeToFile(DUMMY_FILE_PATH, DUMMY_PROP_TXT)
	query, errNo := genBlobIdCheckingQuery(DUMMY_FILE_PATH)
	if errNo != -1 {
		t.Errorf("errNo should be -1 but god %d", errNo)
	}
	// Could not test without DB || !strings.Contains(query, " helm_asset_blob ") || !strings.Contains(query, " helm_asset ")
	if !strings.Contains(query, "/index.yaml") || !strings.Contains(query, ":00000000-abcd-ef00-12345-123456789abc@") {
		t.Errorf("Generated query:%s might be incorrect", query)
	}
}

func TestIsBlobIdMissingInDB(t *testing.T) {
	_writeToFile(DUMMY_FILE_PATH, DUMMY_PROP_TXT)
	rtn := isBlobIdMissingInDB(DUMMY_FILE_PATH, nil)
	if len(*_DB_CON_STR) == 0 && rtn {
		t.Errorf("If no _DB_CON_STR, isBlobIdMissingInDB should not return true")
	}
}

func TestRemoveLines(t *testing.T) {
	updatedContents := removeLines(DUMMY_PROP_TXT, _R_DELETED)
	if len(updatedContents) == len(DUMMY_FILE_PATH) {
		t.Errorf("removeLines does not look like removed anything (%d vs. %d)", len(updatedContents), len(DUMMY_PROP_TXT))
	}
	if strings.Contains(updatedContents, "deleted=true") {
		t.Errorf("removeLines does not look like removed 'deleted=true' (%d vs. %d)", len(updatedContents), len(DUMMY_PROP_TXT))
	}
}

func TestIsTimestampBetween(t *testing.T) {
	result := isTimestampBetween(1622674572617, 1622592000000, 1622592000)
	if result {
		t.Errorf("should not be return for %d < %d < %d", 1622592000000, 1622674572617, 1622592000)
	}
}

func TestGenOutputForReconcile(t *testing.T) {
	err := _writeToFile(DUMMY_FILE_PATH, DUMMY_PROP_TXT)
	if err != nil {
		t.Errorf("Preparing test failed with %s", err)
	}
	delDateFrom := datetimeStrToTs("2021-06-02")
	delDateTo := datetimeStrToTs("2021-06-03")
	output, errNo := genOutputForReconcile(DUMMY_FILE_PATH, delDateFrom, delDateTo)
	if errNo > 0 {
		t.Errorf("genOutputForReconcile return errorNo %d", errNo)
	}
	if !strings.Contains(output, ",00000000-abcd-ef00-12345-123456789abc") {
		t.Errorf("output should contain '00000000-abcd-ef00-12345-123456789abc'\n(%s)", output)
	}

	delDateFrom = datetimeStrToTs("2022-06-02")
	delDateTo = datetimeStrToTs("2022-07-02")
	output, errNo = genOutputForReconcile(DUMMY_FILE_PATH, delDateFrom, delDateTo)
	if errNo != 15 {
		t.Errorf("genOutputForReconcile return errorNo %d", errNo)
	}
	if strings.Contains(output, ",00000000-abcd-ef00-12345-123456789abc") {
		t.Errorf("As 'deletedDateTime=1622674572617' (2021-06-02T22:56:12.617Z), should not return anything (%s)", output)
	}
}

// TODO: TestGenOutputFromProp (and some others)
