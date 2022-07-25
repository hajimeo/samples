package main

import (
	"flag"
	"os"
	"strings"
	"testing"
	"time"
)

var DUMMY_FILE_PATH = "/tmp/dummy.properties"
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
	if !printLine(DUMMY_FILE_PATH, fInfo) {
		t.Errorf("printLine failed with all default global variables")
		flag.PrintDefaults()
	}
}

func TestGetBaseName(t *testing.T) {
	fileName := getBaseName(DUMMY_FILE_PATH)
	if fileName != "dummy" {
		t.Errorf("getBaseName with %s didn't return 'dummy'", DUMMY_FILE_PATH)
	}
}

func TestGetNowStr(t *testing.T) {
	isoFmtStr := getNowStr()
	currentTime := time.Now()
	if strings.Contains(isoFmtStr, currentTime.Format("2006-01-02")) {
		t.Errorf("getNowStr may not return ISO format datetime: %s", isoFmtStr)
	}
}

func TestGetContents(t *testing.T) {
	err := _writeToFile(DUMMY_FILE_PATH, DUMMY_PROP_TXT)
	if err != nil {
		t.Errorf("Preparing test failed with %s", err)
	}
	_setGlobals() // somehow '*_DEBUG = false' does not work
	contents, err := getContents(DUMMY_FILE_PATH)
	if err != nil {
		t.Errorf("getContents failed with %s", err)
	}
	if contents != DUMMY_PROP_TXT {
		t.Errorf("getContents didn't return expected txt (length:%d vs. %d)", len(contents), len(DUMMY_PROP_TXT))
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
	_setGlobals() // somehow '*_DEBUG = false' does not work

	output := genOutputForReconcile(DUMMY_FILE_PATH, modTimeMs)
	if strings.Contains(output, ",dummy") {
		t.Errorf("genOutputForReconcile didn't return deletedDateTime value (%s)", output)
	}
	// TODO: add more test by changing date from/to
}

// TODO: TestGenOutputFromProp (and some others)
