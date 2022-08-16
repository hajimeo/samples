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

func TestPrintLine(t *testing.T) {
	err := _writeToFile(DUMMY_FILE_PATH, DUMMY_PROP_TXT)
	if err != nil {
		t.Errorf("Preparing test failed with %s", err)
	}
	fInfo, _ := os.Lstat(DUMMY_FILE_PATH)
	_setGlobals()
	if !printLine(DUMMY_FILE_PATH, fInfo, nil) {
		t.Errorf("printLine failed with all default global variables")
		flag.PrintDefaults()
	}
}

func TestGetBaseName(t *testing.T) {
	fileName := getBaseName(DUMMY_FILE_PATH)
	if fileName != "00000000-abcd-ef00-12345-123456789abc" {
		t.Errorf("getBaseName with %s didn't return '00000000-abcd-ef00-12345-123456789abc'", DUMMY_FILE_PATH)
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
	*_DB_CON_STR = ""
	rtn := queryDb("This should return nil", nil)
	if len(*_DB_CON_STR) == 0 && rtn != nil {
		t.Errorf("queryDb should return nil when no _DB_CON_STR")
	}
	// TODO: Use mock to test this function properly
}

func TestGenBlobIdCheckingQuery(t *testing.T) {
	_writeToFile(DUMMY_FILE_PATH, DUMMY_PROP_TXT)
	_setGlobals()
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
	_setGlobals()
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

func TestGenOutputForReconcile(t *testing.T) {
	err := _writeToFile(DUMMY_FILE_PATH, DUMMY_PROP_TXT)
	if err != nil {
		t.Errorf("Preparing test failed with %s", err)
	}
	currentTime := time.Now()
	isoFmtDate := currentTime.Format("2006-01-02")
	fInfo, _ := os.Lstat(DUMMY_FILE_PATH)
	modTime := fInfo.ModTime()
	modTimeMs := modTime.Unix()
	flag.Set("dF", isoFmtDate)
	flag.Set("dT", isoFmtDate)
	flag.Set("RF", "true")

	output, errNo := genOutputForReconcile(DUMMY_FILE_PATH, modTimeMs)
	if strings.Contains(output, ",00000000-abcd-ef00-12345-123456789abc") {
		t.Errorf("genOutputForReconcile didn't return deletedDateTime value (%s)", output)
	}
	if errNo > 0 {
		t.Errorf("genOutputForReconcile return errorNo %d", errNo)
	}
	// TODO: add more test by changing date from/to
}

// TODO: TestGenOutputFromProp (and some others)
