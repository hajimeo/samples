// https://go.dev/doc/tutorial/add-a-test
package main

import (
	"os"
	"strings"
	"testing"
	"time"
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
var DUMMY_DB_PROPS_PATH = "/tmp/dummy-store.properties"
var DUMMY_DB_PROP_TXT = `#2022-08-14 20:58:43,970+0000
#Sun Aug 14 20:58:43 UTC 2022
password=xxxxxxxx
maximumPoolSize=10
jdbcUrl=jdbc\:postgresql\://192.168.1.1\:5433/nxrm3pg?ssl\=true&sslfactory\=org.postgresql.ssl.NonValidatingFactory
advanced=maxLifetime\=600000
username=nxrm3pg`

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
	if err != nil {
		t.Log("db.Ping failed with " + err.Error() + ". Skipping the test.")
		return
	}
}

func TestGenRpoFmtMap(t *testing.T) {
	if len(TEST_DB_CONN_STR) == 0 {
		t.Log("No DB conn string provided in TEST_DB_CONN_STR. Skipping TestGenRpoFmtMap.")
		return
	}
	*_DB_CON_STR = TEST_DB_CONN_STR
	reposToFmts := genRepoFmtMap()
	t.Log(reposToFmts)
	if reposToFmts == nil || len(reposToFmts) == 0 {
		t.Errorf("genRepoFmtMap didn't return any reposToFmts.")
	}
}

// TODO: think about good testing
func TestPrintLine(t *testing.T) {
	//_setGlobals()
	fInfo, _ := os.Lstat(DUMMY_FILE_PATH)
	printLine(DUMMY_FILE_PATH, fInfo, nil)
	//t.Errorf("printLine failed with all default global variables")
	//flag.PrintDefaults()
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
	contents, err := getContents(DUMMY_FILE_PATH, nil)
	if err != nil {
		t.Errorf("getContents failed with %s", err)
	}
	if contents != DUMMY_PROP_TXT {
		t.Errorf("getContents didn't return expected txt (length:%d vs. %d)", len(contents), len(DUMMY_PROP_TXT))
	}
}

func TestGenDbConnStr(t *testing.T) {
	props, _ := readPropertiesFile(DUMMY_DB_PROPS_PATH)
	dbConnStr := genDbConnStr(props)
	if !strings.Contains(dbConnStr, "host=192.168.1.1 port=5433 user=nxrm3pg password=xxxxxxxx dbname=nxrm3pg") {
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
	tableNames = append(tableNames, "maven2_asset_blob")
	tableNames = append(tableNames, "pypi_asset_blob")
	query := genAssetBlobUnionQuery(tableNames, "", "", false)
	if !strings.Contains(query, "pypi_asset_blob") {
		t.Errorf("Returned query query:%s is not expected result", query)
	}
	query = genAssetBlobUnionQuery(tableNames, "test, test2", "aaaa like 'bbbb'", false)
	if !strings.Contains(query, "aaaa like 'bbbb'") {
		t.Errorf("Returned query query:%s is not expected result", query)
	}
	query = genAssetBlobUnionQuery(tableNames, "", "", true)
	if !strings.Contains(query, "'maven2_asset_blob' as tableName") {
		t.Errorf("Returned query query:%s is not expected result", query)
	}
}

func TestGenBlobIdCheckingQuery(t *testing.T) {
	tableNames := make([]string, 0)
	tableNames = append(tableNames, "maven2_asset_blob")
	tableNames = append(tableNames, "pypi_asset_blob")
	*_BS_NAME = "testtest"
	query := genBlobIdCheckingQuery(DUMMY_FILE_PATH, tableNames)
	// Could not test without DB || !strings.Contains(query, " helm_asset_blob ") || !strings.Contains(query, " helm_asset ")
	if !strings.Contains(query, " UNION ALL ") || !strings.Contains(query, ":00000000-abcd-ef00-12345-123456789abc") {
		t.Errorf("Generated query:%s might be incorrect", query)
	}
}

func TestGetAssetBlobTables(t *testing.T) {
	rtn := getAssetTables(nil, "", _REPO_TO_FMT)
	if len(*_DB_CON_STR) == 0 && rtn != nil {
		t.Errorf("If no _DB_CON_STR, getAssetTables should return nil")
	}
	if len(TEST_DB_CONN_STR) == 0 {
		t.Log("No DB conn string provided in TEST_DB_CONN_STR. Skipping TestGetAssetBlobTables.")
		return
	}
	*_DB_CON_STR = TEST_DB_CONN_STR
	db := openDb(*_DB_CON_STR)
	_REPO_TO_FMT := genRepoFmtMap()
	rtn = getAssetTables(db, DUMMY_PROP_TXT, _REPO_TO_FMT)
	t.Log(rtn)
	if len(*_DB_CON_STR) == 0 && rtn == nil {
		t.Errorf("Even if no _DB_CON_STR, getAssetTables should NOT return nil")
	}
}

// TODO: fix below test
//func TestIsBlobIdMissingInDB(t *testing.T) {
//	rtn := isBlobIdMissingInDB(DUMMY_FILE_PATH, nil)
//	if len(*_DB_CON_STR) == 0 && rtn {
//		t.Errorf("If no _DB_CON_STR, isBlobIdMissingInDB should not return true")
//	}
//}

func TestGenValidateNodeIdQuery(t *testing.T) {
	if len(TEST_DB_CONN_STR) == 0 {
		t.Log("No DB conn string provided in TEST_DB_CONN_STR. Skipping TestGenRpoFmtMap.")
		return
	}
	*_DB_CON_STR = TEST_DB_CONN_STR
	db := openDb(*_DB_CON_STR)
	query := genValidateNodeIdQuery("aaaaa", db)
	if !strings.Contains(query, "aaaaa") {
		t.Errorf("genValidateNodeIdQuery should return a query containing 'aaaaa'")
		t.Log(query)
	}
}

func TestValidateNodeId(t *testing.T) {
	if len(TEST_DB_CONN_STR) == 0 {
		t.Log("No DB conn string provided in TEST_DB_CONN_STR. Skipping TestGenRpoFmtMap.")
		return
	}
	*_DB_CON_STR = TEST_DB_CONN_STR
	if validateNodeId("aaaaa") {
		t.Errorf("validateNodeId should not return true with 'aaaaa'")
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
	delDateFrom := datetimeStrToTs("2021-06-02")
	delDateTo := datetimeStrToTs("2021-06-03")
	output, err := genOutputForReconcile(DUMMY_PROP_TXT, DUMMY_FILE_PATH, delDateFrom, delDateTo, false, nil)
	if err != nil {
		t.Errorf("genOutputForReconcile return error %s", err.Error())
	}
	if !strings.Contains(output, ",00000000-abcd-ef00-12345-123456789abc") {
		t.Errorf("output should contain '00000000-abcd-ef00-12345-123456789abc'\n(%s)", output)
	}

	delDateFrom = datetimeStrToTs("2022-06-02")
	delDateTo = datetimeStrToTs("2022-07-02")
	output, err = genOutputForReconcile(DUMMY_PROP_TXT, DUMMY_FILE_PATH, delDateFrom, delDateTo, false, nil)
	if err == nil || !strings.Contains(err.Error(), "is not between") {
		t.Errorf("genOutputForReconcile return unexpected error %s", err.Error())
	}
	if strings.Contains(output, ",00000000-abcd-ef00-12345-123456789abc") {
		t.Errorf("As 'deletedDateTime=1622674572617' (2021-06-02T22:56:12.617Z), should not return anything (%s)", output)
	}
}

// TODO: TestGenOutputFromProp (and some others)
