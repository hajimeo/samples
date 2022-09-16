/*
#go mod init github.com/hajimeo/samples/golang/FileList
#go mod tidy
go build -o ../../misc/file-list_$(uname) FileList.go && env GOOS=linux GOARCH=amd64 go build -o ../../misc/file-list_Linux FileList.go

echo 3 > /proc/sys/vm/drop_caches

$HOME/IdeaProjects/samples/misc/file-list_$(uname) -b <workingDirectory>/blobs/default/content -p "vol-" -c1 10

cd /opt/sonatype/sonatype-work/nexus3/blobs/default/
/var/tmp/share/file-list_Linux -b ./content -p vol- -c 4 -db /opt/sonatype/sonatype-work/nexus3/etc/fabric/nexus-store.properties -RF -bsName default > ./$(date '+%Y-%m-%d') 2> ./file-list_$(date +"%Y%m%d").log &
*/

package main

import (
	"bufio"
	"bytes"
	"context"
	"database/sql"
	"flag"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	_ "github.com/lib/pq"
	"github.com/pkg/errors"
	"io"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

func _usage() {
	fmt.Println(`
List .properties and .bytes files as *Tab* Separated Values (Path,LastModified,Size).
    
HOW TO and USAGE EXAMPLES:
    https://github.com/hajimeo/samples/tree/master/golang/FileList`)
	fmt.Println("")
}

// Arguments / global variables
var _BASEDIR *string
var _PREFIX *string
var _FILTER *string
var _FILTER_P *string
var _TOP_N *int64
var _CONC_1 *int
var _LIST_DIRS *bool
var _WITH_PROPS *bool
var _NO_HEADER *bool
var _USE_REGEX *bool

//var _EXCLUDE_FILE *string
//var _INCLUDE_FILE *string

// Reconcile related
var _RECON_FMT *bool
var _REMOVE_DEL *bool
var _WITH_BLOB_SIZE *bool
var _DB_CON_STR *string
var _TRUTH *string
var _BS_NAME *string
var _NODE_ID *string
var _DEL_DATE_FROM *string
var _DEL_DATE_FROM_ts int64
var _DEL_DATE_TO *string
var _DEL_DATE_TO_ts int64
var _MOD_DATE_FROM *string
var _MOD_DATE_FROM_ts int64
var _MOD_DATE_TO *string
var _MOD_DATE_TO_ts int64
var _START_TIME_ts int64
var _REPO_TO_FMT map[string]string

// AWS related
var _IS_S3 *bool
var _MAXKEYS *int
var _WITH_OWNER *bool
var _WITH_TAGS *bool
var _CONC_2 *int

// Regular expressions
var _R *regexp.Regexp
var _R_DEL_DT *regexp.Regexp
var _R_DELETED *regexp.Regexp
var _R_REPO_NAME *regexp.Regexp
var _R_BLOB_NAME *regexp.Regexp

var _DEBUG *bool
var _DEBUG2 *bool
var _CHECKED_N int64 // Atomic (maybe slower?)
var _PRINTED_N int64 // Atomic (maybe slower?)
var _TTL_SIZE int64  // Atomic (maybe slower?)
var _SEP = "	"
var _PROP_EXT = ".properties"

type StoreProps map[string]string

func _setGlobals() {
	_BASEDIR = flag.String("b", ".", "Base directory (default: '.') or S3 Bucket name")
	//_BASEDIR = flag.String("b", "", "S3 Bucket name")
	_PREFIX = flag.String("p", "", "Prefix of sub directories (eg: 'vol-')")
	_WITH_PROPS = flag.Bool("P", false, "If true, read and output the .properties files")
	_FILTER = flag.String("f", "", "Filter file paths (eg: '.properties')")
	_WITH_BLOB_SIZE = flag.Bool("BSize", false, "If true, includes .bytes size (When -f is '.properties')")
	_FILTER_P = flag.String("fP", "", "Filter .properties contents (eg: 'deleted=true')")
	_USE_REGEX = flag.Bool("R", false, "If true, .properties content is *sorted* and _FILTER_P string is treated as regex")
	//_EXCLUDE_FILE = flag.String("sk", "", "Blob IDs in this file will be skipped from the check") // TODO
	//_INCLUDE_FILE = flag.String("sk", "", "ONLY blob IDs in this file will be checked")           // TODO
	_TOP_N = flag.Int64("n", 0, "Return first N lines (0 = no limit). (TODO: may return more than N)")
	_CONC_1 = flag.Int("c", 1, "Concurrent number for sub directories (may not need to use with very fast disk)")
	_LIST_DIRS = flag.Bool("L", false, "If true, just list directories and exit")
	_NO_HEADER = flag.Bool("H", false, "If true, no header line")
	_DEBUG = flag.Bool("X", false, "If true, verbose logging")
	_DEBUG2 = flag.Bool("XX", false, "If true, more verbose logging")

	// Reconcile related
	_TRUTH = flag.String("src", "BS", "Using database or blobstore as source [BS|DB]") // TODO: not implemented "DB" yet
	_DB_CON_STR = flag.String("db", "", "DB connection string or path to properties file")
	_BS_NAME = flag.String("bsName", "", "Eg. 'default'. If provided, the query will be faster")
	_NODE_ID = flag.String("nodeId", "", "Advanced option.")
	_RECON_FMT = flag.Bool("RF", false, "Output for the Reconcile task (any_string,blob_ref). -P will be ignored")
	_REMOVE_DEL = flag.Bool("RDel", false, "Remove 'deleted=true' from .properties. Requires -RF *and* -dF") // TODO: also think about restore plan
	_DEL_DATE_FROM = flag.String("dF", "", "Deleted date YYYY-MM-DD (from). Used to search deletedDateTime")
	_DEL_DATE_TO = flag.String("dT", "", "Deleted date YYYY-MM-DD (to). To exclude newly deleted assets")
	_MOD_DATE_FROM = flag.String("mF", "", "File modification date YYYY-MM-DD from")
	_MOD_DATE_TO = flag.String("mT", "", "File modification date YYYY-MM-DD to")

	// AWS S3 related
	_CONC_2 = flag.Int("c2", 16, "Concurrent number for retrieving AWS Tags")
	_IS_S3 = flag.Bool("S3", false, "If true, access S3 bucket with AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_REGION")
	_MAXKEYS = flag.Int("m", 1000, "Integer value for Max Keys (<= 1000)")
	_WITH_OWNER = flag.Bool("O", false, "If true, also get owner display name")
	_WITH_TAGS = flag.Bool("T", false, "If true, also get tags of each object")

	flag.Parse()

	if _DEBUG2 != nil && *_DEBUG2 {
		*_DEBUG = true
	}
	// If _FILTER_P is given, automatically populate other related variables
	if len(*_FILTER_P) > 0 {
		*_FILTER = _PROP_EXT
		//*_WITH_PROPS = true
		if *_USE_REGEX {
			_R, _ = regexp.Compile(*_FILTER_P)
		}
	}
	if len(*_DB_CON_STR) > 0 {
		if _, err := os.Stat(*_DB_CON_STR); err == nil {
			props, _ := readPropertiesFile(*_DB_CON_STR)
			*_DB_CON_STR = genDbConnStr(props)
		}
		*_FILTER = _PROP_EXT
		*_WITH_PROPS = false
		_REPO_TO_FMT = genRepoFmtMap()

		if len(*_NODE_ID) > 0 {
			if !validateNodeId(*_NODE_ID) {
				_log("ERROR", fmt.Sprintf("_NODE_ID: %s may not be correct.", *_NODE_ID))
				_log("ERROR", fmt.Sprintf("Ctrl + c to cancel now ..."))
				time.Sleep(8 * time.Second)
			}
		}
	}
	_START_TIME_ts = time.Now().Unix()
	_R_DEL_DT, _ = regexp.Compile("[^#]?deletedDateTime=([0-9]+)")
	_R_DELETED, _ = regexp.Compile("deleted=true") // should not use ^ as replacing one-line text
	_R_REPO_NAME, _ = regexp.Compile("[^#]?@Bucket.repo-name=(.+)")
	_R_BLOB_NAME, _ = regexp.Compile("[^#]?@BlobStore.blob-name=(.+)")
	if *_RECON_FMT {
		*_FILTER = _PROP_EXT
		if len(*_FILTER_P) == 0 {
			*_FILTER_P = "deleted=true"
		}
		if len(*_DEL_DATE_FROM) > 0 {
			_DEL_DATE_FROM_ts = datetimeStrToTs(*_DEL_DATE_FROM)
		}
		if len(*_DEL_DATE_TO) > 0 {
			_DEL_DATE_TO_ts = datetimeStrToTs(*_DEL_DATE_TO)
		}
		if len(*_MOD_DATE_FROM) > 0 {
			_MOD_DATE_FROM_ts = datetimeStrToTs(*_MOD_DATE_FROM)
		}
		if len(*_MOD_DATE_TO) > 0 {
			_MOD_DATE_TO_ts = datetimeStrToTs(*_MOD_DATE_TO)
		}
	}
	if *_REMOVE_DEL {
		if !*_RECON_FMT || len(*_DEL_DATE_FROM) == 0 {
			_log("WARN", "Ignoring -RDel as no -RF or no -dF.")
		} else if _IS_S3 != nil && *_IS_S3 {
			panic("TODO: -RDel is not implemented for S3.")
		}
	}
	_log("DEBUG", "_setGlobals completed.")
}

func _log(level string, message string) {
	if level != "DEBUG" && level != "DEBUG2" {
		log.Printf("%-5s %s\n", level, message)
		return
	}
	if level == "DEBUG" && _DEBUG != nil && *_DEBUG {
		log.Printf("%-5s %s\n", level, message)
		return
	}
	if level == "DEBUG2" && _DEBUG2 != nil && *_DEBUG2 {
		log.Printf("%-5s %s\n", level, message)
		return
	}
}

// TODO: this may output too frequently
func _elapsed(startTsMs int64, message string, thresholdMs int64) {
	//elapsed := time.Since(start)
	elapsed := time.Now().UnixMilli() - startTsMs
	if elapsed >= thresholdMs {
		log.Printf("%s (%dms)", message, elapsed)
	}
}

func writeContents(path string, contents string, client *s3.Client) error {
	if _IS_S3 != nil && *_IS_S3 {
		return writeContentsS3(path, contents, client)
	}
	return writeContentsFile(path, contents)
}

func writeContentsFile(path string, contents string) error {
	if _DEBUG != nil && *_DEBUG {
		defer _elapsed(time.Now().UnixMilli(), "DEBUG Wrote "+path, 0)
	} else {
		defer _elapsed(time.Now().UnixMilli(), "WARN  slow file write for path:"+path, 100)
	}
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

func writeContentsS3(path string, contents string, client *s3.Client) error {
	if _DEBUG != nil && *_DEBUG {
		defer _elapsed(time.Now().UnixMilli(), "DEBUG Wrote "+path, 0)
	} else {
		defer _elapsed(time.Now().UnixMilli(), "WARN  slow file write for path:"+path, 400)
	}
	input := &s3.PutObjectInput{
		Bucket: _BASEDIR,
		Key:    &path,
		Body:   bytes.NewReader([]byte(contents)),
	}
	resp, err := client.PutObject(context.TODO(), input)
	if err != nil {
		_log("DEBUG", fmt.Sprintf("Path: %s. Resp: %v", path, resp))
		return err
	}
	return nil
}

func removeTagsS3(path string, client *s3.Client) error {
	inputTag := &s3.PutObjectTaggingInput{
		Bucket: _BASEDIR,
		Key:    &path,
		Tagging: &types.Tagging{
			TagSet: []types.Tag{},
		},
	}
	respTag, errTag := client.PutObjectTagging(context.TODO(), inputTag)
	if errTag != nil {
		_log("WARN", fmt.Sprintf("Deleting Tag failed. Path: %s. Resp: %v", path, respTag))
	}
	return errTag
}

func datetimeStrToTs(datetimeStr string) int64 {
	if len(datetimeStr) == 0 {
		panic("datetimeStr is empty")
	}
	if len(datetimeStr) <= 10 {
		datetimeStr = datetimeStr + " 00:00:00"
	}
	tmpTimeFrom, err := time.Parse("2006-01-02 15:04:03", datetimeStr)
	if err != nil {
		panic(err)
	}
	return tmpTimeFrom.Unix()
}

func readPropertiesFile(path string) (StoreProps, error) {
	props := StoreProps{}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if equal := strings.Index(line, "="); equal >= 0 {
			if key := strings.TrimSpace(line[:equal]); len(key) > 0 {
				value := ""
				if len(line) > equal {
					value = strings.TrimSpace(line[equal+1:])
				}
				props[key] = value
			}
		}
	}
	if err = scanner.Err(); err != nil {
		return nil, err
	}
	return props, nil
}

func genRepoFmtMap() map[string]string {
	// temporarily opening a DB connection only for this query
	db := openDb(*_DB_CON_STR)
	if db != nil {
		defer db.Close()
	}
	rows := queryDb("SELECT name, REGEXP_REPLACE(recipe_name, '-.+', '') AS fmt FROM repository", db)
	if rows == nil { // For unit tests
		return nil
	}
	defer rows.Close()
	reposToFmts := make(map[string]string)
	for rows.Next() {
		var name string
		var fmt string
		err := rows.Scan(&name, &fmt)
		if err != nil {
			panic(err)
		}
		reposToFmts[name] = fmt
	}
	_log("DEBUG", fmt.Sprintf("reposToFmts = %v", reposToFmts))
	return reposToFmts
}

func validateNodeId(nodeId string) bool {
	// temporarily opening a DB connection only for this query
	db := openDb(*_DB_CON_STR)
	if db != nil {
		defer db.Close()
	}
	tableNames := getAssetTables(db, "", nil)
	query := "SELECT SUM(c) as numInvalid"
	query = query + " FROM (" + genAssetBlobUnionQuery(tableNames, "1 as c", "ab.blob_ref NOT like '%@"+nodeId+"' LIMIT 1", true) + ") t_unions"
	//query = "SELECT tableName, REGEXP_REPLACE(blob_ref, '^[^@]+@', '') AS nodeId, count(*) FROM ("+query+") t_unions GROUP BY 1, 2"
	rows := queryDb(query, db)
	defer rows.Close()
	var numInvalid int64
	for rows.Next() {
		err := rows.Scan(&numInvalid)
		if err != nil {
			panic(err)
		}
	}
	return !(numInvalid > 1)
}

func genDbConnStr(props StoreProps) string {
	jdbcPtn := regexp.MustCompile(`jdbc:postgresql://([^/:]+):?(\d*)/([^?]+)\??(.*)`)
	props["jdbcUrl"] = strings.ReplaceAll(props["jdbcUrl"], "\\", "")
	matches := jdbcPtn.FindStringSubmatch(props["jdbcUrl"])
	if matches == nil {
		props["password"] = "********"
		panic(fmt.Sprintf("No 'jdbcUrl' in props: %v", props))
	}
	hostname := matches[1]
	port := matches[2]
	database := matches[3]
	if len(port) == 0 {
		port = "5432"
	}
	params := ""
	if len(matches) > 3 {
		// TODO: probably need to escape?
		params = " " + strings.ReplaceAll(matches[4], "&", " ")
	}
	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s%s", hostname, port, props["username"], props["password"], database, params)
	props["password"] = "********"
	_log("INFO", fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s%s", hostname, port, props["username"], props["password"], database, params))
	return connStr
}

func getBlobSize(propPath string) int64 {
	blobPath := getPathWithoutExt(propPath) + ".bytes"
	info, err := os.Stat(blobPath)
	if err != nil {
		return 0
	}
	return info.Size()
}

func getBlobSizeS3(propPath string, client *s3.Client) int64 {
	blobPath := getPathWithoutExt(propPath) + ".bytes"
	if _DEBUG != nil && *_DEBUG {
		defer _elapsed(time.Now().UnixMilli(), "DEBUG HeadObject to "+blobPath, 0)
	} else {
		defer _elapsed(time.Now().UnixMilli(), "WARN  slow file access for path:"+blobPath, 300)
	}
	headObj := s3.HeadObjectInput{
		Bucket: _BASEDIR,
		Key:    &blobPath,
	}
	result, err := client.HeadObject(context.TODO(), &headObj)
	if err != nil {
		_log("WARN", "Failed to request "+blobPath)
	}
	return result.ContentLength
}

func tags2str(tagset []types.Tag) string {
	str := ""
	for _, _t := range tagset {
		if len(str) == 0 {
			str = fmt.Sprintf("%s=%s", *_t.Key, *_t.Value)
		} else {
			str = fmt.Sprintf("%s&%s=%s", str, *_t.Key, *_t.Value)
		}
	}
	return str
}

func printLineS3(client *s3.Client, item types.Object, db *sql.DB) {
	path := *item.Key
	//_log("DEBUG", fmt.Sprintf("printLine-ing for path:%s", path))
	modTime := item.LastModified
	modTimeTs := modTime.Unix()
	output := ""
	var blobSize int64 = 0

	atomic.AddInt64(&_CHECKED_N, 1)

	if _MOD_DATE_FROM_ts > 0 && modTimeTs < _MOD_DATE_FROM_ts {
		_log("DEBUG2", fmt.Sprintf("path:%s modTime %d is less than %d", path, modTimeTs, _MOD_DATE_FROM_ts))
		return
	}
	if _MOD_DATE_TO_ts > 0 && modTimeTs > _MOD_DATE_TO_ts {
		_log("DEBUG2", fmt.Sprintf("path:%s modTime %d is newer than %d", path, modTimeTs, _MOD_DATE_TO_ts))
		return
	}

	// If not for Reconciliation YYYY-MM-DD log, output normally.
	if !*_RECON_FMT {
		output = fmt.Sprintf("%s%s%s%s%d", path, _SEP, modTime, _SEP, item.Size)
	}

	// If .properties file is checked and _WITH_BLOB_SIZE, then get the size of .bytes file
	if *_WITH_BLOB_SIZE && *_FILTER == _PROP_EXT && strings.HasSuffix(path, _PROP_EXT) {
		blobSize = getBlobSizeS3(path, client)
		output = fmt.Sprintf("%s%s%d", output, _SEP, blobSize)
	}

	// If .properties file is checked, depending on other flags, output can be changed.
	if strings.HasSuffix(path, _PROP_EXT) {
		output = _printLineExtra(output, path, modTimeTs, db, client)
	}

	if *_WITH_OWNER {
		output = fmt.Sprintf("%s%s%s", output, _SEP, *item.Owner.DisplayName)
	}

	// Get tags if -with-tags is presented.
	if *_WITH_TAGS {
		_log("DEBUG", fmt.Sprintf("Getting tags for %s", path))
		_inputT := &s3.GetObjectTaggingInput{
			Bucket: _BASEDIR,
			Key:    &path,
		}
		_tag, err := client.GetObjectTagging(context.TODO(), _inputT)
		if err != nil {
			_log("DEBUG", fmt.Sprintf("Retrieving tags for %s failed with %s. Ignoring...", path, err.Error()))
			output = fmt.Sprintf("%s%s", output, _SEP)
		} else {
			//_log("DEBUG", fmt.Sprintf("Retrieved tags for %s", path))
			tag_output := tags2str(_tag.TagSet)
			output = fmt.Sprintf("%s%s%s", output, _SEP, tag_output)
		}
	}

	// Updating counters and return
	if len(output) > 0 {
		atomic.AddInt64(&_PRINTED_N, 1)
		atomic.AddInt64(&_TTL_SIZE, item.Size+blobSize)
		fmt.Println(output)
		return
	}
	return
}

func printLine(path string, fInfo os.FileInfo, db *sql.DB) {
	//_log("DEBUG", fmt.Sprintf("printLine-ing for path:%s", path))
	modTime := fInfo.ModTime()
	modTimeTs := modTime.Unix()
	output := ""
	var blobSize int64 = 0

	atomic.AddInt64(&_CHECKED_N, 1)

	if _MOD_DATE_FROM_ts > 0 && modTimeTs < _MOD_DATE_FROM_ts {
		_log("DEBUG2", fmt.Sprintf("path:%s modTime %d is less than %d", path, modTimeTs, _MOD_DATE_FROM_ts))
		return
	}
	if _MOD_DATE_TO_ts > 0 && modTimeTs > _MOD_DATE_TO_ts {
		_log("DEBUG2", fmt.Sprintf("path:%s modTime %d is newer than %d", path, modTimeTs, _MOD_DATE_TO_ts))
		return
	}

	// If not for Reconciliation YYYY-MM-DD log, output normally.
	if !*_RECON_FMT {
		output = fmt.Sprintf("%s%s%s%s%d", path, _SEP, modTime, _SEP, fInfo.Size())
	}

	// If .properties file is checked and _WITH_BLOB_SIZE, then get the size of .bytes file
	if *_WITH_BLOB_SIZE && *_FILTER == _PROP_EXT && strings.HasSuffix(path, _PROP_EXT) {
		blobSize = getBlobSize(path)
		output = fmt.Sprintf("%s%s%d", output, _SEP, blobSize)
	}

	// If .properties file is checked, depending on other flags, output can be changed.
	if strings.HasSuffix(path, _PROP_EXT) {
		output = _printLineExtra(output, path, modTimeTs, db, nil)
	}

	// Updating counters and return
	if len(output) > 0 {
		atomic.AddInt64(&_PRINTED_N, 1)
		atomic.AddInt64(&_TTL_SIZE, fInfo.Size()+blobSize)
		fmt.Println(output)
		return
	}
	return
}

// To handle a bit complicated conditions
func _printLineExtra(output string, path string, modTimeTs int64, db *sql.DB, client *s3.Client) string {
	skipCheck := false

	if *_RECON_FMT {
		if _START_TIME_ts > 0 && modTimeTs > _START_TIME_ts {
			_log("DEBUG2", "path:"+path+" is recently modified, so skipping ("+strconv.FormatInt(modTimeTs, 10)+" > "+strconv.FormatInt(_START_TIME_ts, 10)+")")
			return ""
		}
		if _DEL_DATE_FROM_ts > 0 && modTimeTs < _DEL_DATE_FROM_ts {
			_log("DEBUG2", "path:"+path+" mod time is older than _DEL_DATE_FROM_ts, so skipping ("+strconv.FormatInt(modTimeTs, 10)+" < "+strconv.FormatInt(_DEL_DATE_FROM_ts, 10)+")")
			return ""
		}
		// NOTE: Not doing same for _DEL_DATE_TO_ts as some task may touch.
	}

	// If _NODE_ID is given and no deleted date from/to, should not need to open a file
	if len(*_DB_CON_STR) > 0 && len(*_TRUTH) > 0 && len(*_NODE_ID) > 0 && _DEL_DATE_FROM_ts == 0 && _DEL_DATE_TO_ts == 0 {
		if *_TRUTH == "BS" {
			if !isBlobIdMissingInDB("", path, db) {
				//_log("DEBUG", "path:"+path+" exists in Database. Skipping.")
				return ""
			}
			reconOutput, reconErr := genOutputForReconcile("", path, _DEL_DATE_FROM_ts, _DEL_DATE_TO_ts, true, client)
			if reconErr != nil {
				_log("DEBUG", reconErr.Error())
			}
			return reconOutput
		}
		// TODO: if *_TRUTH == "DB" { if !isBlobIdMissingInBlobStore() {
	}

	// Excluding above special condition, usually needs to read the file
	contents, err := getContents(path, client)
	if err != nil {
		_log("ERROR", "No contents from "+path)
		// if no content, no point of restoring
		return ""
	}

	if len(*_DB_CON_STR) > 0 && len(*_TRUTH) > 0 {
		// Script is asked to output if this blob is missing in DB
		if *_TRUTH == "BS" {
			if !isBlobIdMissingInDB(contents, path, db) {
				return ""
			}
			skipCheck = true
		}
	}

	if *_RECON_FMT {
		// If reconciliation output format is requested, should not use 'output'
		reconOutput, reconErr := genOutputForReconcile(contents, path, _DEL_DATE_FROM_ts, _DEL_DATE_TO_ts, skipCheck, client)
		if reconErr != nil {
			_log("DEBUG", reconErr.Error())
		}
		return reconOutput
	}

	if *_WITH_PROPS {
		props, propErr := genOutputFromProp(contents, path)
		if propErr != nil {
			_log("DEBUG", propErr.Error())
			// If this can't read .properties file, still return the original "output"
			return output
		}
		if len(props) > 0 {
			output = fmt.Sprintf("%s%s%s", output, _SEP, props)
		}
	}
	return output
}

// as per google, this would be faster than using TrimSuffix
func getPathWithoutExt(path string) string {
	return path[:len(path)-len(filepath.Ext(path))]
}

func getBaseNameWithoutExt(path string) string {
	fileName := filepath.Base(path)
	return getPathWithoutExt(fileName)
}

func getNowStr() string {
	currentTime := time.Now()
	return currentTime.Format("2006-01-02 15:04:05")
}

func getContents(path string, client *s3.Client) (string, error) {
	if _IS_S3 != nil && *_IS_S3 {
		return getContentsS3(path, client)
	}
	return getContentsFile(path)
}

func getContentsFile(path string) (string, error) {
	if _DEBUG != nil && *_DEBUG {
		defer _elapsed(time.Now().UnixMilli(), "DEBUG Read "+path, 0)
	} else {
		defer _elapsed(time.Now().UnixMilli(), "WARN  slow file read for path:"+path, 100)
	}
	bytes, err := os.ReadFile(path)
	if err != nil {
		_log("DEBUG", fmt.Sprintf("ReadFile for %s failed with %s. Ignoring...", path, err.Error()))
		return "", err
	}
	contents := strings.TrimSpace(string(bytes))
	return contents, nil
}

func getContentsS3(path string, client *s3.Client) (string, error) {
	if _DEBUG != nil && *_DEBUG {
		defer _elapsed(time.Now().UnixMilli(), "DEBUG Read "+path, 0)
	} else {
		defer _elapsed(time.Now().UnixMilli(), "WARN  slow file read for path:"+path, 400)
	}
	input := &s3.GetObjectInput{
		Bucket: _BASEDIR,
		Key:    &path,
	}
	obj, err := client.GetObject(context.TODO(), input)
	if err != nil {
		_log("DEBUG", fmt.Sprintf("Retrieving %s failed with %s. Ignoring...", path, err.Error()))
		return "", err
	}
	buf := new(bytes.Buffer)
	_, err = buf.ReadFrom(obj.Body)
	if err != nil {
		_log("DEBUG", fmt.Sprintf("Reading object for %s failed with %s. Ignoring...", path, err.Error()))
		return "", err
	}
	contents := strings.TrimSpace(buf.String())
	return contents, nil
}

func openDb(dbConnStr string) *sql.DB {
	if len(dbConnStr) == 0 {
		return nil
	}
	if !strings.Contains(dbConnStr, "sslmode") {
		dbConnStr = dbConnStr + " sslmode=disable"
	}
	db, err := sql.Open("postgres", dbConnStr)
	if err != nil {
		// If DB connection issue, let's stop the script
		panic(err.Error())
	}
	//db.SetMaxOpenConns(*_CONC_1)
	//err = db.Ping()
	return db
}

func queryDb(query string, db *sql.DB) *sql.Rows {
	if _DEBUG != nil && *_DEBUG {
		defer _elapsed(time.Now().UnixMilli(), "DEBUG Executed "+query, 0)
	} else {
		defer _elapsed(time.Now().UnixMilli(), "WARN  slow query:"+query, 100)
	}
	if db == nil { // For unit tests
		return nil
	}
	rows, err := db.Query(query)
	if err != nil {
		_log("ERROR", query)
		panic(err.Error())
	}
	return rows
}

func genAssetBlobUnionQuery(tableNames []string, columns string, where string, includeTableName bool) string {
	if len(columns) == 0 {
		columns = "*"
	}
	if len(where) > 0 {
		where = " WHERE " + where
	}
	queryPrefix := "SELECT " + columns
	elements := make([]string, 0)
	for _, tableName := range tableNames {
		element := queryPrefix
		if includeTableName {
			element = element + ", '" + tableName + "' as tableName"
		}
		element = fmt.Sprintf("%s FROM %s a", element, tableName)
		// NOTE: Join is required otherwise when Cleanup unused asset blob task has not been run, this script thinks that blob exists
		element = fmt.Sprintf("%s JOIN %s_blob ab ON a.asset_blob_id = ab.asset_blob_id", element, tableName)
		element = fmt.Sprintf("%s%s", element, where)
		elements = append(elements, "("+element+")")
	}
	query := strings.Join(elements, " UNION ALL ")
	//_log("DEBUG", query)
	return query
}

func genBlobIdCheckingQuery(path string, tableNames []string) string {
	blobId := getBaseNameWithoutExt(path)
	where := "blob_ref LIKE '%:" + blobId + "@%'"
	if len(*_BS_NAME) > 0 {
		if len(*_NODE_ID) > 0 {
			// NOTE: node-id or deployment id can be anything...
			where = "blob_ref = '" + *_BS_NAME + ":" + blobId + "@" + *_NODE_ID + "'"
		} else {
			// PostgreSQL still uses index for 'like' with forward search, so much faster than above
			where = "blob_ref like '" + *_BS_NAME + ":" + blobId + "@%'"
		}
	}
	query := genAssetBlobUnionQuery(tableNames, "asset_id", where, false)
	return query
}

// only works on postgres
func getAssetTables(db *sql.DB, contents string, reposToFmt map[string]string) []string {
	result := make([]string, 0)
	if len(contents) > 0 {
		m := _R_REPO_NAME.FindStringSubmatch(contents)
		if len(m) < 2 {
			_log("WARN", "No _R_REPO_NAME in "+contents)
			// At this moment, if no blobName, assuming NOT missing...
			return result
		}
		repoName := m[1]
		if repoFmt, ok := reposToFmt[repoName]; ok {
			result = append(result, repoFmt+"_asset")
			return result
		} else {
			_log("WARN", fmt.Sprintf("repoName: %s is not in reposToFmt\n%v\n", repoName, reposToFmt))
		}
	}

	query := "SELECT table_name FROM information_schema.tables WHERE table_name like '%_asset'"
	rows := queryDb(query, db)
	if rows == nil { // For unit tests
		return nil
	}
	defer rows.Close()
	for rows.Next() {
		var name string
		err := rows.Scan(&name)
		if err != nil {
			panic(err)
		}
		result = append(result, name)
	}
	return result
}

// TODO: Checking from DB to blobstore, like Orphaned blob finder
func isBlobIdMissingInBlobStore() bool {
	return false
}

func isBlobIdMissingInDB(contents string, path string, db *sql.DB) bool {
	// TODO: Current UNION query is a bit slow. Providing "path" generates the repoFmt but too slow
	tableNames := getAssetTables(db, contents, _REPO_TO_FMT)
	if tableNames == nil { // Mainly for unit test
		_log("WARN", "tableNames is nil for contents: "+contents)
		return false
	}
	query := genBlobIdCheckingQuery(path, tableNames)
	if len(query) == 0 { // Mainly for unit test
		_log("WARN", fmt.Sprintf("query is empty for path: %s and tableNames: %v\n", path, tableNames))
		return false
	}
	// Ref: https://go.dev/doc/database/querying
	rows := queryDb(query, db)
	if rows == nil { // Mainly for unit test
		_log("WARN", "rows is nil for query: "+query)
		return false
	}
	defer rows.Close()
	noRows := true
	for rows.Next() {
		noRows = false
		break
	}
	return noRows
}

func genOutputForReconcile(contents string, path string, delDateFromTs int64, delDateToTs int64, skipCheck bool, client *s3.Client) (string, error) {
	deletedMsg := ""
	deletedDtMsg := ""

	// If skipCheck is true and no deletedDateFrom/To and _REMOVE_DEL are specified, just return the output for reconcile
	if skipCheck && !*_REMOVE_DEL && delDateFromTs == 0 {
		_log("INFO", fmt.Sprintf("Found path:%s .", path))
		// Not using _SEP for this output
		return fmt.Sprintf("%s,%s", getNowStr(), getBaseNameWithoutExt(path)), nil
	}

	// if _DEL_DATE_FROM or _DEL_DATE_TO, examine deletedDateTime
	if delDateFromTs > 0 || delDateToTs > 0 {
		m := _R_DEL_DT.FindStringSubmatch(contents)
		// stop in here with error, only when skipCheck is false
		if !skipCheck && len(m) < 2 {
			return "", errors.New(fmt.Sprintf("path:%s dos not match with %s (%s)", path, _R_DEL_DT.String(), m))
		}

		// Current logic is Check and Remove deleted=true only when deletedDatetime is set in the properties file
		if len(m) > 1 {
			deletedTSMsec, _ := strconv.ParseInt(m[1], 10, 64)
			if !isTimestampBetween(deletedTSMsec, delDateFromTs*1000, delDateToTs*1000) {
				return "", errors.New(fmt.Sprintf("%d is not between %d and %d", deletedTSMsec, delDateFromTs*1000, delDateToTs*1000))
			}
			deletedDtMsg = fmt.Sprintf(" deletedDateTime=%d", deletedTSMsec)

			// Currently, for the safety, _REMOVE_DEL requires delDateFromTs
			if *_REMOVE_DEL && delDateFromTs > 0 {
				updatedContents := removeLines(contents, _R_DELETED)
				err := writeContents(path, updatedContents, client)
				if err != nil {
					_log("ERROR", fmt.Sprintf("Updating path:%s failed with %s", path, err))
				} else if len(contents) == len(updatedContents) {
					_log("WARN", fmt.Sprintf("Removed 'deleted=true' from path:%s but size is same (%d => %d)", path, len(contents), len(updatedContents)))
				} else {
					deletedMsg = " (removed 'deletedMsg=true')"

					if _IS_S3 != nil && *_IS_S3 {
						errTag := removeTagsS3(path, client)
						if errTag == nil {
							_ = removeTagsS3(getPathWithoutExt(path)+".bytes", client)
						}
					}
				}
			}
		}
		_log("INFO", fmt.Sprintf("Found path:%s%s%s", path, deletedDtMsg, deletedMsg))
	} else {
		_log("DEBUG", fmt.Sprintf("Found path:%s%s%s", path, deletedDtMsg, deletedMsg))
	}

	// Not using _SEP for this output
	return fmt.Sprintf("%s,%s", getNowStr(), getBaseNameWithoutExt(path)), nil
}

// one line but for unit testing
func removeLines(contents string, rex *regexp.Regexp) string {
	return rex.ReplaceAllString(contents, "")
}

func isTimestampBetween(tMsec int64, fromTsMsec int64, toTsMsec int64) bool {
	if fromTsMsec > 0 && fromTsMsec > tMsec {
		return false
	}
	if toTsMsec > 0 && (toTsMsec*1000) < tMsec {
		return false
	}
	if toTsMsec == 0 && (_START_TIME_ts*1000) < tMsec {
		_log("DEBUG", fmt.Sprintf("deletedDateTime=%d is greater than the this script's start time:%d", tMsec, _START_TIME_ts))
		return false
	}
	return true
}

func genOutputFromProp(contents string, path string) (string, error) {
	if len(*_FILTER_P) == 0 {
		// If no _FILETER2, just return the contents as single line. Should also escape '"'?
		return strings.ReplaceAll(contents, "\n", ","), nil
	}

	if *_USE_REGEX {
		// If asked to use regex, return properties lines only if matches.
		if _R == nil || len(_R.String()) == 0 { //
			return "", errors.New("_USE_REGEX is specified but no regular expression (_R)")
		}
		// To allow to use simpler regex, sorting line and converting to single line firt
		lines := strings.Split(contents, "\n")
		sort.Strings(lines)
		contents = strings.Join(lines, ",")
		if _R.MatchString(contents) {
			return contents, nil
		}
		return "", errors.New(fmt.Sprintf("%s does not contain %s (with Regex). Not outputting entire line.", path, *_FILTER_P))
	}

	// If not regex (eg: 'deleted=true')
	if !strings.Contains(contents, *_FILTER_P) {
		return "", errors.New(fmt.Sprintf("%s does not contain %s.", path, *_FILTER_P))
	}
	return contents, nil
}

// get *all* directories under basedir and which name starts with prefix
func getDirsS3(client *s3.Client) []string {
	dirs := make([]string, 1)
	dirs = append(dirs, *_PREFIX)

	_log("DEBUG", fmt.Sprintf("Retriving sub folders under %s", *_PREFIX))
	delimiter := "/"
	inputV1 := &s3.ListObjectsInput{
		Bucket:    _BASEDIR,
		Prefix:    _PREFIX,
		MaxKeys:   int32(*_MAXKEYS),
		Delimiter: &delimiter,
	}
	resp, err := client.ListObjects(context.TODO(), inputV1)
	if err != nil {
		println("Got error retrieving list of objects:")
		panic(err.Error())
	}
	// replacing dirs with the result (excluding 1 as it would make slower)
	if *_CONC_1 > 1 && len(resp.CommonPrefixes) > 1 {
		dirs = make([]string, len(resp.CommonPrefixes))
	}
	for _, item := range resp.CommonPrefixes {
		// TODO: somehow empty value is added into dirs even below
		if len(strings.TrimSpace(*item.Prefix)) == 0 {
			continue
		}
		if *_CONC_1 > 1 && len(resp.CommonPrefixes) > 1 {
			dirs = append(dirs, *item.Prefix)
		}
	}

	sort.Strings(dirs)
	return dirs
}

// get *all* directories under basedir and which name starts with prefix
func getDirs(basedir string, prefix string) []string {
	var dirs []string
	basedir = strings.TrimSuffix(basedir, string(filepath.Separator))
	fp, err := os.Open(basedir)
	if err != nil {
		println("os.Open for " + basedir + " failed.")
		panic(err.Error())
	}
	list, _ := fp.Readdir(0) // 0 to read all files and folders
	for _, f := range list {
		if f.IsDir() {
			if len(prefix) == 0 || strings.HasPrefix(f.Name(), prefix) {
				dirs = append(dirs, basedir+string(filepath.Separator)+f.Name())
			}
		}
	}
	// it seems Readdir does not return sorted directories
	sort.Strings(dirs)
	return dirs
}

func listObjectsS3(client *s3.Client, prefix string) {
	var subTtl int64
	db := openDb(*_DB_CON_STR)
	if db != nil {
		defer db.Close()
	}
	input := &s3.ListObjectsV2Input{
		Bucket:     _BASEDIR,
		MaxKeys:    int32(*_MAXKEYS),
		FetchOwner: *_WITH_OWNER,
		Prefix:     &prefix,
	}

	for {
		resp, err := client.ListObjectsV2(context.TODO(), input)
		if err != nil {
			println("Got error retrieving list of objects:")
			panic(err.Error())
		}

		//https://stackoverflow.com/questions/25306073/always-have-x-number-of-goroutines-running-at-any-time
		wgTags := sync.WaitGroup{}                 // *
		guardTags := make(chan struct{}, *_CONC_2) // **

		for _, item := range resp.Contents {
			if len(*_FILTER) == 0 || strings.Contains(*item.Key, *_FILTER) {
				subTtl++
				guardTags <- struct{}{}                                     // **
				wgTags.Add(1)                                               // *
				go func(client *s3.Client, item types.Object, db *sql.DB) { // **
					printLineS3(client, item, db)
					<-guardTags   // **
					wgTags.Done() // *
				}(client, item, db)
			}

			if *_TOP_N > 0 && *_TOP_N <= _PRINTED_N {
				_log("DEBUG", fmt.Sprintf("Printed %d >= %d", _PRINTED_N, *_TOP_N))
				break
			}
		}
		wgTags.Wait() // *

		// Continue if truncated (more data available) and if not reaching to the top N.
		if *_TOP_N > 0 && *_TOP_N <= _PRINTED_N {
			_log("DEBUG", fmt.Sprintf("Found %d and reached %d", _PRINTED_N, *_TOP_N))
			break
		} else if resp.IsTruncated {
			_log("DEBUG", fmt.Sprintf("Set ContinuationToken to %s", *resp.NextContinuationToken))
			input.ContinuationToken = resp.NextContinuationToken
		} else {
			_log("DEBUG", "NOT Truncated (completed).")
			break
		}
	}
}

func listObjects(basedir string) {
	var subTtl int64
	db := openDb(*_DB_CON_STR)
	if db != nil {
		defer db.Close()
	}
	// Below line does not work because currently Glob does not support ./**/*
	//list, err := filepath.Glob(basedir + string(filepath.Separator) + *_FILTER)
	// Somehow WalkDir is slower in this code
	//err := filepath.WalkDir(basedir, func(path string, f fs.DirEntry, err error) error {
	err := filepath.Walk(basedir, func(path string, f os.FileInfo, err error) error {
		if err != nil {
			return errors.Wrap(err, "failed filepath.WalkDir")
		}
		if !f.IsDir() {
			if len(*_FILTER) == 0 || strings.Contains(f.Name(), *_FILTER) {
				subTtl++
				printLine(path, f, db)
				if *_TOP_N > 0 && *_TOP_N <= _PRINTED_N {
					_log("DEBUG", fmt.Sprintf("Printed %d >= %d", _PRINTED_N, *_TOP_N))
					return io.EOF
				}
			}
		}
		return nil
	})
	if err != nil && err != io.EOF {
		println("Got error retrieving list of files:")
		panic(err.Error())
	}
	_log("INFO", fmt.Sprintf("Checked %d for %s (total: %d)", subTtl, basedir, _CHECKED_N))
}

// Define, set, and validate command arguments
func main() {
	log.SetFlags(log.Lmicroseconds)
	if len(os.Args) == 1 || os.Args[1] == "-h" || os.Args[1] == "--help" {
		_usage()
		_setGlobals()
		os.Exit(0)
	}
	_setGlobals()

	// Validations
	if !*_NO_HEADER && *_WITH_PROPS {
		_log("WARN", "With Properties (-P), listing can be slower.")
	}
	if *_CONC_1 < 1 {
		_log("ERROR", "-c is lower than 1.")
		os.Exit(1)
	}

	// Start outputting ..
	var subDirs []string
	var client *s3.Client

	_log("DEBUG", fmt.Sprintf("Retriving sub directories under %s", *_BASEDIR))
	if _IS_S3 != nil && *_IS_S3 {
		cfg, err := config.LoadDefaultConfig(context.TODO())
		if _DEBUG2 != nil && *_DEBUG2 {
			// https://aws.github.io/aws-sdk-go-v2/docs/configuring-sdk/logging/
			cfg, err = config.LoadDefaultConfig(context.TODO(), config.WithClientLogMode(aws.LogRetries|aws.LogRequest))
		}
		if err != nil {
			panic("configuration error, " + err.Error())
		}
		client = s3.NewFromConfig(cfg)
		subDirs = getDirsS3(client)
	} else {
		subDirs = getDirs(*_BASEDIR, *_PREFIX)
	}
	if *_LIST_DIRS {
		fmt.Printf("%v", subDirs)
		return
	}
	_log("DEBUG", fmt.Sprintf("Sub directories: %v", subDirs))

	// Printing headers if requested
	if !*_RECON_FMT && !*_NO_HEADER {
		fmt.Print("Path,LastModified,Size")
		if *_WITH_BLOB_SIZE && *_FILTER == _PROP_EXT {
			fmt.Print(",BlobSize")
		}
		if *_WITH_PROPS {
			fmt.Print(",Properties")
		}
		if *_WITH_OWNER {
			fmt.Print(",Owner")
		}
		if *_WITH_TAGS {
			fmt.Print(",Tags")
		}
		fmt.Println("")
	}

	_log("INFO", fmt.Sprintf("Generating list from %s ...", *_BASEDIR))
	wg := sync.WaitGroup{}
	guard := make(chan struct{}, *_CONC_1)
	for _, s := range subDirs {
		if len(s) == 0 {
			//_log("DEBUG", "Ignoring empty sub directory.")
			continue
		}
		_log("DEBUG", "subDir: "+s)
		guard <- struct{}{}
		wg.Add(1)
		if _IS_S3 != nil && *_IS_S3 {
			go func(client *s3.Client, prefix string) {
				listObjectsS3(client, prefix)
				<-guard
				wg.Done()
			}(client, s)
		} else {
			go func(basedir string) {
				listObjects(basedir)
				<-guard
				wg.Done()
			}(s)
		}
	}

	wg.Wait()
	println("")
	_log("INFO", fmt.Sprintf("Printed %d of %d (size:%d) in %s and sub-dir starts with %s (elapsed:%ds)", _PRINTED_N, _CHECKED_N, _TTL_SIZE, *_BASEDIR, *_PREFIX, time.Now().Unix()-_START_TIME_ts))
	//_log("INFO", fmt.Sprintf("Printed %d items (size: %d) in bucket: %s with prefix: %s", _PRINTED_N, _TTL_SIZE, *_BASEDIR, *_PREFIX))
}
