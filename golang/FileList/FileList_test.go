// https://go.dev/doc/tutorial/add-a-test
package main

import (
	regexp "github.com/wasilibs/go-re2"
	"log"
	"os"
	"strings"
	"testing"
	"time"
)

// To create DB, an easy way is running ./FileList_test.sh
// var TEST_DB_CONN_STR = "host=localhost port=5432 user=nxrm password=nxrm123 dbname=nxrmfilelisttest"
var tempDir = os.TempDir()
var TEST_DB_CONN_STR = ""
var DUMMY_FILE_PATH = tempDir + "00000000-abcd-ef00-1234-123456789abc.properties"
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
var DUMMY_DB_PROPS_PATH = tempDir + "/dummy-store.properties"
var DUMMY_DB_PROP_TXT = `#2022-08-14 20:58:43,970+0000
#Sun Aug 14 20:58:43 UTC 2022
password=nexus123
maximumPoolSize=10
jdbcUrl=jdbc\:postgresql\://localhost\:5432/nxrmfilelisttest?ssl\=true&sslfactory\=org.postgresql.ssl.NonValidatingFactory
advanced=maxLifetime\=600000
username=nexus`
var DUMMY_BLOB_IDS_PATH = tempDir + "/dummy-blobids.txt"
var DUMMY_BLOB_IDS_TXT = `./vol-25/chap-40/79a659c7-32a1-4a72-84e0-1a7d07a9f11f.properties
./vol-24/chap-01/d04770e3-cc0e-4a37-a562-1bfd6150cb8a.properties
./vol-24/chap-32/4a626c00-fbb7-4a96-826e-0b6c46465e5f.properties
./vol-09/chap-39/2ca4c2f9-c7f5-44ab-a30a-7b1cebc736af.properties
./vol-36/chap-43/a4ee5b0d-f9b3-4dd0-a95d-62feb2900694.properties
./vol-16/chap-36/b5e06792-4487-4925-bac8-3fbb78d3f561.properties`

func DeferPanic() {
	// Use this function with 'defer' to recover from panic if occurred. Set err to nil otherwise.
	if r := recover(); r != nil {
		log.Println("Panic occurred:", r)
	}
}

func TestMain(m *testing.M) {
	err := writeContentsFile(DUMMY_FILE_PATH, DUMMY_PROP_TXT)
	if err != nil {
		panic(err)
	}
	err = writeContentsFile(DUMMY_DB_PROPS_PATH, DUMMY_DB_PROP_TXT)
	if err != nil {
		panic(err)
	}
	err = writeContentsFile(DUMMY_BLOB_IDS_PATH, DUMMY_BLOB_IDS_TXT)
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

func TestOpenDb(t *testing.T) {
	if len(TEST_DB_CONN_STR) == 0 {
		t.Log("No DB conn string provided in TEST_DB_CONN_STR. Skipping TestOpenDb.")
		return
	}
	db := openDb(TEST_DB_CONN_STR)
	if db == nil {
		t.Errorf("openDb didn't return DB ojbect")
	}
	err := db.Ping()
	db.Close()
	if err != nil {
		t.Log("db.Ping failed with " + err.Error() + ". Skipping the test.")
		return
	}
}

func TestInitRpoFmtMap(t *testing.T) {
	*_BS_NAME = ""
	*_DEBUG = true
	conStr := "host=localhost port=5432 user=nexus password=nexus123 dbname=nxrmfilelisttest"
	defer DeferPanic()
	db := openDb(conStr)
	defer db.Close()

	initRepoFmtMap(db)
	t.Log(_REPO_TO_FMT)
	if _REPO_TO_FMT == nil || len(_REPO_TO_FMT) == 0 {
		t.Errorf("initRepoFmtMap didn't return any _REPO_TO_FMT.")
	}
	*_BS_NAME = "default"
	initRepoFmtMap(db)
	t.Log(_REPO_TO_FMT)
	if _REPO_TO_FMT == nil || len(_REPO_TO_FMT) == 0 {
		t.Errorf("initRepoFmtMap didn't return any _REPO_TO_FMT for default blobstore.")
	}
	*_BS_NAME = "aaaaaaaaaaaaaa"
	initRepoFmtMap(db)
	t.Log(_REPO_TO_FMT)
	if _REPO_TO_FMT != nil && len(_REPO_TO_FMT) > 0 {
		t.Errorf("initRepoFmtMap should not return any _REPO_TO_FMT.")
	}
}

// TODO: think about good testing
func TestGenOutput(t *testing.T) {
	//_setGlobals()
	fInfo, _ := os.Lstat(DUMMY_FILE_PATH)
	output := genOutput(DUMMY_FILE_PATH, fInfo.ModTime(), fInfo.Size(), 0, nil, nil)
	if !strings.Contains(output, DUMMY_FILE_PATH) {
		t.Errorf("%s didn't contain '%s'", output, DUMMY_FILE_PATH)
	}
	//t.Log(output)
}

func TestGetPathWithoutExt(t *testing.T) {
	pathWoExt := getPathWithoutExt(DUMMY_FILE_PATH)
	if pathWoExt != tempDir+"00000000-abcd-ef00-1234-123456789abc" {
		t.Errorf("getPathWithoutExt with %s didn't return '/tmp/00000000-abcd-ef00-1234-123456789abc'", DUMMY_FILE_PATH)
	}
}

func TestExtractBlobIdFromString(t *testing.T) {
	blobId := extractBlobIdFromString(DUMMY_FILE_PATH)
	if blobId != "00000000-abcd-ef00-1234-123456789abc" {
		t.Errorf("extractBlobIdFromString from %s didn't return '00000000-abcd-ef00-1234-123456789abc' but %s", DUMMY_FILE_PATH, blobId)
	}
	blobId = extractBlobIdFromString("00000000-abcd-ef00-1234-123456789abc")
	if blobId != "00000000-abcd-ef00-1234-123456789abc" {
		t.Errorf("extractBlobIdFromString didn't return '00000000-abcd-ef00-1234-123456789abc', but %s", blobId)
	}
}

func TestMyHashCode(t *testing.T) {
	h := myHashCode("b5e06792-4487-4925-bac8-3fbb78d3f561")
	if h != 116009242 {
		t.Errorf("result was not 116009242, but %v", h)
	}
}

func TestGenBlobPath(t *testing.T) {
	path := genBlobPath("b5e06792-4487-4925-bac8-3fbb78d3f561")
	if path != "vol-16/chap-36/b5e06792-4487-4925-bac8-3fbb78d3f561" {
		t.Errorf("path was not 'vol-16/chap-36/b5e06792-4487-4925-bac8-3fbb78d3f561', but %v", path)
	}
}

func TestPrintMissingBlobLines(t *testing.T) {
	// Just to test if panics
	printOrphanedBlobsFromIdFile("/not/existing/file", "not working DB conn", 1)
	t.Log("NOTE: 'blobIdsFile:/not/existing/file cannot be opened. open /not/existing/file: no such file or directory' is expected.")

	//TEST_DB_CONN_STR = ""
	conStr := "host=localhost port=5432 user=nexus password=nexus123 dbname=nxrmfilelisttest"
	// To improve the query speed
	*_BS_NAME = "default"
	//*_DEBUG = true
	defer DeferPanic()
	db := openDb(conStr)
	if db == nil {
		t.Logf("Connecting to the DB: %s failed.", TEST_DB_CONN_STR)
	} else {
		initRepoFmtMap(db)
		printOrphanedBlobsFromIdFile(DUMMY_BLOB_IDS_PATH, TEST_DB_CONN_STR, 2)
		db.Close()
	}
	if len(conStr) == 0 {
		t.Log("NOTE: 'ERROR Cannot open the database.' is expected.")
	}
}

func TestGetBlobSize(t *testing.T) {
	blobPath := getPathWithoutExt(DUMMY_FILE_PATH) + ".bytes"
	size := getBlobSizeFile(blobPath)
	if size != -1 {
		t.Errorf("As no .bytes file, should be -1: %v", size)
	}
	blobPath = getPathWithoutExt(DUMMY_FILE_PATH) + ".properties"
	size = getBlobSizeFile(blobPath)
	if size < 1 {
		t.Errorf("As .properties file should exist, should be positive integer: %v", size)
	}
	size = getBlobSize(blobPath, nil)
	if size < 1 {
		t.Errorf("As .properties file should exist, should be positive integer: %v", size)
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
	contents, err := getContents(DUMMY_FILE_PATH, nil)
	if err != nil {
		t.Errorf("getContents failed with %s", err)
	}
	if contents != DUMMY_PROP_TXT {
		t.Errorf("getContents didn't return expected txt (length:%d vs. %d)", len(contents), len(DUMMY_PROP_TXT))
	}
}

func TestGenDbConnStr(t *testing.T) {
	dbConnStr := genDbConnStrFromFile(DUMMY_DB_PROPS_PATH)
	if !strings.Contains(dbConnStr, "host=localhost port=5432 user=nexus password=nexus123 dbname=nxrmfilelisttest ssl=true sslfactory=org.postgresql.ssl.NonValidatingFactory") {
		t.Errorf("DB connection string: %s is incorrect.", dbConnStr)
	}
}

func TestQueryDb(t *testing.T) {
	rtn := queryDb("This should return nil", nil)
	if len(*_DB_CON_STR) == 0 && rtn != nil {
		t.Errorf("queryDb should return nil when no _DB_CON_STR")
	}
	// TODO: Use mock to test this function properly
}

func TestGenAssetBlobUnionQuery(t *testing.T) {
	tableNames := make([]string, 0)
	tableNames = append(tableNames, "maven2_asset")
	tableNames = append(tableNames, "pypi_asset")
	query := genAssetBlobUnionQuery(tableNames, "", "", false)
	if !strings.Contains(query, " pypi_asset_blob ") {
		t.Errorf("Returned query:%s is not expected result", query)
	}
	query = genAssetBlobUnionQuery(tableNames, "", "", true)
	if !strings.Contains(query, "'maven2_asset' as tableName") {
		t.Errorf("Returned query:%s is not expected result", query)
	}
	query = genAssetBlobUnionQuery(tableNames, "test, test2", "aaaa like 'bbbb' LIMIT 1", false)
	if !strings.Contains(query, "aaaa like 'bbbb' LIMIT 1") {
		t.Errorf("Returned query:%s is not expected result", query)
	}
	//t.Log(query)
	query = genAssetBlobUnionQuery(tableNames, "blob_ref", "", true)
	if !strings.Contains(query, "blob_ref") {
		t.Errorf("Returned query:%s is not expected result", query)
	}
}

func TestGenAssetBlobUnionQueryFromRepoNames(t *testing.T) {
	repoNames := make([]string, 0)
	repoNames = append(repoNames, "npm-proxy")
	repoNames = append(repoNames, "maven-hosted")

	query := genAssetBlobUnionQueryFromRepoNames(repoNames, "", "", false)
	if len(query) > 0 {
		t.Errorf("Returned query:%s should be empty", query)
	}

	_REPO_TO_FMT = make(map[string]string)
	_REPO_TO_FMT["npm-proxy"] = "raw"
	_REPO_TO_FMT["maven-hosted"] = "maven2"

	query = genAssetBlobUnionQueryFromRepoNames(repoNames, "", "", false)
	if !strings.Contains(query, " maven2_asset a ") {
		t.Errorf("Returned query:%s is not expected result", query)
	}
	query = genAssetBlobUnionQueryFromRepoNames(repoNames, "", "", true)
	if !strings.Contains(query, "'maven-hosted'") {
		t.Errorf("Returned query:%s is not expected result", query)
	}
	query = genAssetBlobUnionQueryFromRepoNames(repoNames, "blob_ref", "", true)
	if !strings.Contains(query, " blob_ref, ") {
		t.Errorf("Returned query:%s is not expected result", query)
	}
	query = genAssetBlobUnionQueryFromRepoNames(repoNames, "blob_ref", "1=1 LIMIT 1", true)
	if !strings.Contains(query, " LIMIT 1") {
		t.Errorf("Returned query:%s is not expected result", query)
	}
	//t.Log(query)
}

func TestGenBlobIdCheckingQuery(t *testing.T) {
	tableNames := make([]string, 0)
	tableNames = append(tableNames, "maven2_asset_blob")
	tableNames = append(tableNames, "pypi_asset_blob")
	*_BS_NAME = "testtest"
	query := genBlobIdCheckingQuery(DUMMY_FILE_PATH, tableNames)
	// Could not test without DB || !strings.Contains(query, " helm_asset_blob ") || !strings.Contains(query, " helm_asset ")
	if !strings.Contains(query, " UNION ALL ") || !strings.Contains(query, "00000000-abcd-ef00-1234-123456789abc") {
		t.Errorf("Generated query:%s might be incorrect", query)
	}
}

func TestGetFmtFromRepName(t *testing.T) {
	t.Log("TODO: as _REPO_TO_FMT needs to be populated first")
}

func TestConvRepoNamesToAssetTableName(t *testing.T) {
	t.Log("TODO: as _REPO_TO_FMT needs to be populated first (as getFmtFromRepName is used")
}

func TestIsSoftDeleted(t *testing.T) {
	r := isSoftDeleted(DUMMY_FILE_PATH, nil)
	if !r {
		t.Errorf("Should be soft-deleted")
	}
}

func TestShouldBeUnDeleted(t *testing.T) {
	//*_DEBUG = true
	result := shouldBeUnDeleted("aaaaa", "test/path")
	if !result {
		t.Errorf("Should be un-deleted")
	}
	result = shouldBeUnDeleted("deletedDateTime=notANumber", "test/path")
	if !result {
		t.Errorf("Should be un-deleted")
	}
	result = shouldBeUnDeleted("aaa,deletedDateTime=123456,bbb", "test/path")
	if !result {
		t.Errorf("Should be un-deleted")
	}
	_DEL_DATE_FROM_ts = datetimeStrToTs("2021-06-02")
	result = shouldBeUnDeleted("aaa,deletedDateTime=1622674572509,bbb", "test/path")
	if !result {
		t.Errorf("Should be un-deleted")
	}
	result = shouldBeUnDeleted(DUMMY_PROP_TXT, "test/path")
	if !result {
		t.Errorf("Should be un-deleted")
	}
	_DEL_DATE_FROM_ts = datetimeStrToTs("2024-05-20")
	result = shouldBeUnDeleted(DUMMY_PROP_TXT, "test/path")
	if result {
		t.Errorf("Should NOT be un-deleted %d", _DEL_DATE_FROM_ts)
	}
	_DEL_DATE_FROM_ts = datetimeStrToTs("2021-06-02")
	result = shouldBeUnDeleted(DUMMY_PROP_TXT, "test/path")
	if !result {
		t.Errorf("Should NOT be un-deleted %d", _DEL_DATE_FROM_ts)
	}
	_DEL_DATE_TO_ts = datetimeStrToTs("2021-06-02")
	result = shouldBeUnDeleted(DUMMY_PROP_TXT, "test/path")
	if result {
		t.Errorf("Should NOT be un-deleted %d %d", _DEL_DATE_FROM_ts, _DEL_DATE_TO_ts)
	}
}

func TestGetAssetTables(t *testing.T) {
	*_DEBUG = true
	rtn := getAssetTables("")
	t.Log("NOTE: 'ERROR getAssetTables requires _REPO_TO_FMT but empty.' can be ignored.")

	return
	// TODO: need to replace repo-name based on _REPO_TO_FMT
	rtn = getAssetTables(DUMMY_PROP_TXT)
	if len(_REPO_TO_FMT) > 0 && (rtn == nil || len(rtn) > 0) {
		t.Errorf("If _REPO_TO_FMT is not empty, getAssetTables should NOT return nil or empty.\n%v", _REPO_TO_FMT)
	} else {
		t.Log(rtn)
	}
}

// TODO: fix below test
//func TestIsBlobIdMissingInDB(t *testing.T) {
//	rtn := isBlobIdMissingInDB(DUMMY_FILE_PATH, nil)
//	if len(*_DB_CON_STR) == 0 && rtn {
//		t.Errorf("If no _DB_CON_STR, isBlobIdMissingInDB should not return true")
//	}
//}

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
	result := isTsMSecBetweenTs(1622674572617, 1622592000, 1622592000)
	if result {
		t.Errorf("should not be True for %d < %d < %d", 1622592000000, 1622674572, 1622592000)
	}
	result = isTsMSecBetweenTs(10000, 1, 11)
	if !result {
		t.Errorf("should not be False for %d < %d < %d", 10, 1, 11)
	}
	result = isTsMSecBetweenTs(10000, 1, 0)
	if !result {
		t.Errorf("should not be False for %d < %d < %d", 10, 1, 0)
	}
	result = isTsMSecBetweenTs(10000, 0, 110)
	if !result {
		t.Errorf("should not be False for %d < %d < %d", 10, 0, 110)
	}
	result = isTsMSecBetweenTs(10000, 0, 0)
	if !result {
		t.Errorf("should not be False for %d < %d < %d", 10, 0, 0)
	}
}

func TestGenOutputFromProp(t *testing.T) {
	contents := "#2024-01-03 10:19:21,102+1000,#Wed Jan 03 10:19:21 AEST 2024,@BlobStore.blob-name=/dummies/test_41.txt,@BlobStore.content-type=text/plain,@BlobStore.created-by-ip=127.0.0.1,@BlobStore.created-by=admin,@Bucket.repo-name=raw-hosted,creationTime=1704241147460,deleted=true,deletedDateTime=1704241161102,deletedReason=Removing unused asset blob,sha1=0b66bf353f0f43663786e1873b0714700dc5742f,size=48"
	props, skipReason := genOutputFromProp(contents)
	if len(props) == 0 {
		t.Errorf("'props' should not be empty")
		t.Logf("%v", props)
		t.Logf("%v", skipReason)
	}

	*_USE_REGEX = true
	regexStr := "@Bucket.repo-name=raw-hosted.+deleted=true"
	_RX = nil
	_R, _ = regexp.Compile(regexStr)
	props, skipReason = genOutputFromProp(contents)
	if len(props) == 0 {
		t.Errorf("'props' should not be empty with regex: %s", regexStr)
		t.Logf("%v", props)
		t.Logf("%v", skipReason)
	}
	_RX, _ = regexp.Compile(regexStr)
	_R = nil
	props, skipReason = genOutputFromProp(contents)
	if len(props) > 0 {
		t.Errorf("'props' should be empty with exclude regex: %s", regexStr)
		t.Logf("%v", props)
		t.Logf("%v", skipReason)
	}

	*_USE_REGEX = false
	_R = nil
	_RX = nil

	*_FILTER_PX = ""
	*_FILTER_P = "@Bucket.repo-name=raw-hosted.+deleted=true"
	props, skipReason = genOutputFromProp(contents)
	if len(props) > 0 {
		t.Errorf("'props' should be empty with string: %s (as '.+')", regexStr)
		t.Logf("%v", props)
		t.Logf("%v", skipReason)
	}
	*_FILTER_PX = ""
	*_FILTER_P = "@Bucket.repo-name=raw-hosted,creationTime="
	props, skipReason = genOutputFromProp(contents)
	if len(props) == 0 {
		t.Errorf("'props' should not be empty with string: %s", regexStr)
		t.Logf("%v", props)
		t.Logf("%v", skipReason)
	}

	*_FILTER_PX = "@Bucket.repo-name=raw-hosted.+deleted=true"
	*_FILTER_P = ""
	props, skipReason = genOutputFromProp(contents)
	if len(props) == 0 {
		t.Errorf("'props' should not be empty with string: %s", *_FILTER_PX)
		t.Logf("%v", props)
		t.Logf("%v", skipReason)
	}
	*_FILTER_PX = "@Bucket.repo-name=raw-hosted,creationTime="
	*_FILTER_P = ""
	props, skipReason = genOutputFromProp(contents)
	if len(props) > 0 {
		t.Errorf("'props' should be empty with string: %s", *_FILTER_PX)
		t.Logf("%v", props)
		t.Logf("%v", skipReason)
	}

	*_USE_REGEX = false
	*_FILTER_P = ""
	*_FILTER_PX = ""
}

func TestDatetimeStrToTs(t *testing.T) {
	result := datetimeStrToTs("2023-10-20")
	if result != 1697760000 {
		t.Errorf("Result should be timestanmp (int64) but got %v", result)
	}
	result = datetimeStrToTs("2023-10-20 12:12:12")
	if result != 1697803920 {
		t.Errorf("Result should be timestanmp (int64) but got %v", result)
	}
	//result = datetimeStrToTs("aaaaa")
}

func TestReadPropertiesFile(t *testing.T) {
	props, err := readPropertiesFile(DUMMY_FILE_PATH)
	if err != nil {
		t.Errorf("Error: %v", err)
	}
	if len(props) == 0 {
		t.Errorf("Error: %v", props)
	}
	//t.Log(props)
}

func TestWriteContents(t *testing.T) {
	err := writeContents(DUMMY_FILE_PATH, DUMMY_PROP_TXT, nil)
	if err != nil {
		t.Errorf("Error: failed to write into %v is not 'testValue'", DUMMY_FILE_PATH)
	}
}

func TestCacheAddObject(t *testing.T) {
	cacheAddObject("testKey", "testValue", 1)
	rtn := cacheReadObj("testKey").(string)
	if rtn != "testValue" {
		t.Errorf("Error: rtn %v is not 'testValue'", rtn)
	}
}

func TestChunkSlice(t *testing.T) {
	letters := []string{"a", "b", "c", "d", "e"}
	chunks := chunkSlice(letters, 2)
	if len(chunks) != 3 {
		t.Errorf("Error: chunks size should be 3 but %v", len(chunks))
	}
	if len(chunks[2]) != 1 {
		t.Errorf("Error: chunks[2] size should be 1 but %v", len(chunks[2]))
	}
	if chunks[2][0] != "e" {
		t.Errorf("Error: chunks[2][0] should be 'e' but %v", len(chunks[2][0]))
	}
}

func TestGetObjectS3(t *testing.T) {
	t.Log("TODO: TestGetObjectS3 is not implemented yet")
}

func TestPrintObjectByBlobId(t *testing.T) {
	t.Log("TODO: TestPrintObjectByBlobId is not implemented yet")
}
