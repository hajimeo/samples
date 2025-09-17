/*
#go mod init github.com/hajimeo/samples/golang/FileList
#go mod tidy
goBuild ./FileList.go      <<< Check ../README.md

# Can drop the file cache for testing
#echo 3 > /proc/sys/vm/drop_caches
cd /opt/sonatype/sonatype-work/nexus3/blobs/default/
file-list -b ./content -p vol- -c 4 -db /opt/sonatype/sonatype-work/nexus3/etc/fabric/nexus-store.properties -bsName default > ./$(date '+%Y-%m-%d') 2> ./file-list_$(date +"%Y%m%d").log &

For S3:
	https://pkg.go.dev/github.com/aws/aws-sdk-go/service/s3
    https://aws.github.io/aws-sdk-go-v2/docs/configuring-sdk/#specifying-credentials
For Azure:
	https://learn.microsoft.com/en-us/azure/storage/blobs/storage-quickstart-blobs-go
	https://github.com/Azure-Samples/storage-blobs-go-quickstart/blob/master/storage-quickstart.go
	or:
	https://learn.microsoft.com/en-us/samples/azure-samples/azure-sdk-for-go-samples/azure-sdk-for-go-samples/
	git clone https://github.com/Azure-Samples/azure-sdk-for-go-samples.git
*/

package main

import (
	"bufio"
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"math"
	"os"
	"path/filepath"
	"slices" // 1.21 or higher
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	_ "github.com/lib/pq"
	"github.com/pkg/errors"
	regexp "github.com/wasilibs/go-re2"
)

func _usage() {
	fmt.Println(`
List .properties and .bytes files as *Tab* Separated Values (Path LastModified Size).
    
HOW TO and USAGE EXAMPLES:
    https://github.com/hajimeo/samples/blob/master/golang/FileList/README.md`)
	fmt.Println("")
}

// Arguments / global variables
var _DEBUG *bool
var _DEBUG2 *bool
var _DRY_RUN *bool

var _BASEDIR *string
var _DIR_DEPTH *int
var _PREFIX *string
var _CONTENT_PATH = "content"
var _FILTER *string
var _FILTER_P *string
var _FILTER_PX *string
var _TOP_N *int64
var _CONC_1 *int
var _LIST_DIRS *bool
var _WITH_PROPS *bool
var _NO_HEADER *bool
var _USE_REGEX *bool
var _SAVE_TO *string
var _SAVE_TO_F *os.File

var _DISABLE_DATE_BLOBPATH = true // for backward compatibility, TODO: remove this later

// as it should have only .bytes and .properties, probably not needed any more
//var _EXCLUDE_FILE *string
//var _INCLUDE_FILE *string

// Reconcile / orphaned related
var _REMOVE_DEL *bool
var _WITH_BLOB_SIZE *bool
var _DB_CON_STR *string
var _BLOB_IDS_FILE *string
var _TRUTH *string
var _BS_NAME *string
var _REPO_NAMES *string
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
var _ASSET_TABLES []string

// AWS / Azure related
var _BS_TYPE *string
var _IS_S3 *bool // TODO: remove this later
var _MAXKEYS *int
var _WITH_OWNER *bool
var _WITH_TAGS *bool
var _CONC_2 *int

// Regular expressions
var _R *regexp.Regexp
var _RX *regexp.Regexp
var _R_DELETED_DT, _ = regexp.Compile("[^#]?deletedDateTime=([0-9]+)")
var _R_DELETED, _ = regexp.Compile("deleted=true") // should not use ^ as replacing one-line text
var _R_REPO_NAME, _ = regexp.Compile("[^#]?@Bucket.repo-name=(.+)")
var _R_BLOB_ID, _ = regexp.Compile("[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}")

// Global variables
var _CHECKED_N int64 = 0 // Atomic (maybe slower?)
var _PRINTED_N int64 = 0 // Atomic (maybe slower?)
var _TTL_SIZE int64 = 0  // Atomic (maybe slower?)
var _SLOW_MS int64 = 100
var _SEP = "	"
var _PROP_EXT = ".properties"
var _BYTE_EXT = ".bytes"
var (
	_OBJECT_OUTPUTS = make(map[string]interface{})
	mu              sync.RWMutex
)

type StoreProps map[string]string

func _setGlobals() {
	_START_TIME_ts = time.Now().Unix()

	_BASEDIR = flag.String("b", ".", "Base directory (default: '.') or S3 Bucket name")
	_PREFIX = flag.String("p", "", "Prefix to 'vol-*' or S3 prefix. This is not recursive")
	_DIR_DEPTH = flag.Int("dd", 2, "(experimental) Directory Depth to find sub directories (eg: 'vol-NN', 'chap-NN')")
	_WITH_PROPS = flag.Bool("P", false, "If true, the .properties file content is included in the output")
	_FILTER = flag.String("f", "", "Filter for the file path (eg: '.properties' to include only this extension)")
	_WITH_BLOB_SIZE = flag.Bool("BSize", false, "If true, includes .bytes size (When -f is '.properties')")
	_FILTER_P = flag.String("fP", "", "Filter for the content of the .properties files (eg: 'deleted=true')")
	_FILTER_PX = flag.String("fPX", "", "Excluding Filter for .properties (eg: 'BlobStore.blob-name=.+/maven-metadata.xml.*')")
	_SAVE_TO = flag.String("s", "", "Save the output (TSV text) into the specified path")
	_USE_REGEX = flag.Bool("R", false, "If true, .properties content is *sorted* and -fP|-fPX string is treated as regex")
	// TODO: (at least) -n is not working with -bF
	_TOP_N = flag.Int64("n", 0, "Return first N lines (0 = no limit). (TODO: may return more than N)")
	_CONC_1 = flag.Int("c", 4, "Concurrent number for reading directories (default 4)")
	_LIST_DIRS = flag.Bool("L", false, "If true, just list directories and exit")
	_NO_HEADER = flag.Bool("H", false, "If true, no header line")
	_DEBUG = flag.Bool("X", false, "If true, verbose logging")
	_DEBUG2 = flag.Bool("XX", false, "If true, more verbose logging")
	_DRY_RUN = flag.Bool("Dry", false, "If true, RDel does not do anything")

	// Reconcile / orphaned blob finding related
	_TRUTH = flag.String("src", "", "Using database or blobstore as source [BS|DB]. If not specified and -db is given, 'BS' is set.")
	_DB_CON_STR = flag.String("db", "", "DB connection string or path to DB connection properties file")
	_BLOB_IDS_FILE = flag.String("bF", "", "file path contains the list of blob IDs. If -f is not specified, both .properties and .bytes are included")
	_BS_NAME = flag.String("bsName", "", "eg. 'default'. If provided, the SQL query will be faster. 3.47 and higher only")
	_REPO_NAMES = flag.String("repos", "", "Repository names. eg. 'maven-central,raw-hosted,npm-proxy', only with -src=DB")
	_REMOVE_DEL = flag.Bool("RDel", false, "Remove 'deleted=true' from .properties. Requires -dF")
	_DEL_DATE_FROM = flag.String("dF", "", "Deleted date YYYY-MM-DD (from). Used to search deletedDateTime")
	_DEL_DATE_TO = flag.String("dT", "", "Deleted date YYYY-MM-DD (to). To exclude newly deleted assets")
	_MOD_DATE_FROM = flag.String("mF", "", "File modification date YYYY-MM-DD (from). For DB, used against blob_created")
	_MOD_DATE_TO = flag.String("mT", "", "File modification date YYYY-MM-DD (to). For DB, used against blob_created")

	// AWS S3 / Azure related
	_BS_TYPE = flag.String("bsType", "F", "F (file) or S (s3) or A (azure)")
	_CONC_2 = flag.Int("c2", 8, "AWS S3: Concurrent number for retrieving files (default 8, max concurency = c * c2)")
	_IS_S3 = flag.Bool("S3", false, "AWS S3: If true, access S3 bucket with AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION and AWS_ENDPOINT_URL") // TODO: remove this
	_MAXKEYS = flag.Int("m", 1000, "AWS S3: Max Keys number for NewListObjectsV2Paginator (<= 1000, default 0)")
	_WITH_OWNER = flag.Bool("O", false, "AWS S3: If true, get the owner display name")
	_WITH_TAGS = flag.Bool("T", false, "AWS S3: If true, get tags of each object")

	flag.Parse()

	if _DEBUG2 != nil && *_DEBUG2 {
		*_DEBUG = true
	}

	basedir := ""
	if len(*_BASEDIR) > 0 {
		basedir = strings.TrimSuffix(*_BASEDIR, string(filepath.Separator)) + string(filepath.Separator)
	}
	prefix := ""
	if len(*_PREFIX) > 0 {
		parts := strings.SplitN(*_PREFIX, "/content", 2)
		if len(parts) > 1 {
			prefix = parts[0] + string(filepath.Separator)
		} else {
			prefix = strings.TrimSuffix(*_PREFIX, string(filepath.Separator)) + string(filepath.Separator)
		}
	}
	// for backward compatibility TODO: remove this
	if _IS_S3 != nil && *_IS_S3 {
		*_BS_TYPE = "S"
	}
	if _BS_TYPE != nil && *_BS_TYPE == "S" {
		// No basedir required for S3
		_CONTENT_PATH = prefix + "content"
	} else if _BS_TYPE != nil && *_BS_TYPE == "A" {
		_log("TODO", " Do something ")
	} else {
		// TODO: not perfect
		if !strings.Contains(basedir, "content") {
			_CONTENT_PATH = basedir + "content"
		} else if strings.HasSuffix(basedir, string(filepath.Separator)+"content") || strings.HasSuffix(basedir, string(filepath.Separator)+"content"+string(filepath.Separator)) {
			_CONTENT_PATH = basedir
		} else {
			_log("ERROR", "Could not decide the 'content' path.")
		}
	}
	_log("DEBUG", "_CONTENT_PATH = "+_CONTENT_PATH)

	// If _FILTER_P is given, automatically populate other related variables
	if len(*_FILTER_P) > 0 || len(*_FILTER_PX) > 0 {
		*_FILTER = _PROP_EXT
		//*_WITH_PROPS = true
		if *_USE_REGEX {
			if len(*_FILTER_P) > 0 {
				_R, _ = regexp.Compile(*_FILTER_P)
			}
			if len(*_FILTER_PX) > 0 {
				_RX, _ = regexp.Compile(*_FILTER_PX)
			}
		}
	}

	if len(*_DB_CON_STR) > 0 {
		// If DB connection is provided but the source is not specified, using BlobStore as the source of the truth (will work like DeadBlobsFInder)
		if len(*_TRUTH) == 0 {
			*_TRUTH = "BS"
			_log("INFO", "Setting -src=BS as -db is provided")
		}
		if _, err := os.Stat(*_DB_CON_STR); err == nil {
			*_DB_CON_STR = genDbConnStrFromFile(*_DB_CON_STR)
		}
		*_FILTER = _PROP_EXT
		//*_WITH_PROPS = false

		db := openDb(*_DB_CON_STR)
		if db == nil {
			panic("_DB_CON_STR is provided but cannot open the database.") // Can't output _DB_CON_STR as it may include password
		}
		initRepoFmtMap(db)
		db.Close()
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

	if *_REMOVE_DEL {
		*_FILTER = _PROP_EXT
		if len(*_FILTER_P) == 0 {
			*_FILTER_P = "deleted=true"
		}

		if len(*_BLOB_IDS_FILE) == 0 && (len(*_DEL_DATE_FROM) == 0 && len(*_MOD_DATE_FROM) == 0) {
			// If not from the blob ID file (-bf), just in case, the deleted from or the modified from is required
			panic("Currently '-RDel' requires '-dF YYYY-MM-DD' or '-mF YYYY-MM-DD' for safety.")
		}
	}

	if len(*_SAVE_TO) > 0 {
		var err error
		_SAVE_TO_F, err = os.OpenFile(*_SAVE_TO, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			panic(err)
		}
	}
	_log("DEBUG", "_setGlobals completed for "+strings.Join(os.Args[1:], " "))
}

func cacheAddObject(key string, value interface{}, maxSize int) {
	mu.Lock()
	for k := range _OBJECT_OUTPUTS {
		if len(_OBJECT_OUTPUTS) > maxSize {
			delete(_OBJECT_OUTPUTS, k)
		} else {
			break
		}
	}
	_OBJECT_OUTPUTS[key] = value
	mu.Unlock()
}

func cacheReadObj(key string) interface{} {
	mu.RLock()
	defer mu.RUnlock()
	value, exists := _OBJECT_OUTPUTS[key]
	if exists {
		return value
	}
	return nil
}

func chunkSlice(slice []string, chunkSize int) [][]string {
	var chunks [][]string
	for i := 0; i < len(slice); i += chunkSize {
		end := i + chunkSize
		if end > len(slice) {
			end = len(slice)
		}
		chunks = append(chunks, slice[i:end])
	}
	return chunks
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

func _println(line string) (n int, err error) {
	// At this moment, excluding empty line
	if len(line) == 0 {
		return
	}
	if _SAVE_TO_F != nil {
		return fmt.Fprintln(_SAVE_TO_F, line)
	}
	return fmt.Println(line)
}

// NOTE: this may output too frequently
func _elapsed(startTsMs int64, message string, thresholdMs int64) {
	//elapsed := time.Since(start)
	elapsed := time.Now().UnixMilli() - startTsMs
	if elapsed >= thresholdMs {
		log.Printf("%s (%d ms)", message, elapsed)
	}
}

func writeContents(path string, contents string, client interface{}) error {
	switch client.(type) {
	// TODO: add Azure
	case *s3.Client:
		return writeContentsS3(path, contents, client.(*s3.Client))
	default:
		return writeContentsFile(path, contents)
	}
}

func writeContentsFile(path string, contents string) error {
	if _DEBUG != nil && *_DEBUG {
		defer _elapsed(time.Now().UnixMilli(), "DEBUG Wrote "+path, 0)
	} else {
		defer _elapsed(time.Now().UnixMilli(), "WARN  slow file write for path:"+path, 100)
	}
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0644)
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
	//tmpTimeFrom, err := time.Parse("2006-01-02 15:04:03 -0700 MST", datetimeStr+" +0000 UTC")
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
		panic(err)
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

func initRepoFmtMap(db *sql.DB) {
	_REPO_TO_FMT = make(map[string]string)
	_ASSET_TABLES = make([]string, 0)

	query := "SELECT name, REGEXP_REPLACE(recipe_name, '-.+', '') AS fmt FROM repository"
	if len(*_BS_NAME) > 0 {
		query += " WHERE attributes->'storage'->>'blobStoreName' = '" + *_BS_NAME + "'"
	}
	rows := queryDb(query, db)
	if rows == nil { // For unit tests
		_log("DEBUG", fmt.Sprintf("No result with %s", query))
		return
	}
	defer rows.Close()
	for rows.Next() {
		var name string
		var fmt string
		err := rows.Scan(&name, &fmt)
		if err != nil {
			panic(err)
		}
		_REPO_TO_FMT[name] = fmt
		if !slices.Contains(_ASSET_TABLES, fmt+"_asset") {
			_ASSET_TABLES = append(_ASSET_TABLES, fmt+"_asset")
		}
	}
	_log("DEBUG", fmt.Sprintf("_REPO_TO_FMT = %v", _REPO_TO_FMT))
	_log("DEBUG", fmt.Sprintf("_ASSET_TABLES = %v", _ASSET_TABLES))
}

func genDbConnStrFromFile(filePath string) string {
	props, _ := readPropertiesFile(filePath)
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
		// NOTE: probably need to escape the 'params'?
		params = " " + strings.ReplaceAll(matches[4], "&", " ")
	}
	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s%s", hostname, port, props["username"], props["password"], database, params)
	props["password"] = "********"
	_log("INFO", fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s%s", hostname, port, props["username"], props["password"], database, params))
	return connStr
}

func getBlobSize(path string, client interface{}) int64 {
	switch client.(type) {
	// TODO: add Azure
	case *s3.Client:
		return getBlobSizeS3(path, client.(*s3.Client))
	default:
		return getBlobSizeFile(path)
	}
}

func getBlobSizeFile(blobPath string) int64 {
	info, err := os.Stat(blobPath)
	if err != nil {
		return -1
	}
	return info.Size()
}

func getBlobSizeS3(blobPath string, client *s3.Client) int64 {
	result, err := getObjectS3(blobPath, client)
	if err != nil {
		_log("WARN", "Failed to request "+blobPath)
		return -1
	}
	return *result.ContentLength
}

func tags2str(tagset []types.Tag) string {
	// Convert AWS S3 tags to string
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

// TODO: create another printLine for Azure
func printLineS3(item types.Object, client *s3.Client, db *sql.DB) {
	path := *item.Key
	modTime := item.LastModified
	propSize := item.Size
	owner := ""
	if item.Owner != nil && item.Owner.DisplayName != nil {
		owner = *item.Owner.DisplayName
	}
	var blobSize int64 = 0
	// If .properties file is checked and _WITH_BLOB_SIZE, then get the size of .bytes file
	if *_WITH_BLOB_SIZE && *_FILTER == _PROP_EXT && strings.HasSuffix(path, _PROP_EXT) {
		blobPath := getPathWithoutExt(path) + _BYTE_EXT
		blobSize = getBlobSizeS3(blobPath, client)
	}
	output := genOutput(path, *modTime, *propSize, blobSize, db, client)

	if *_WITH_OWNER {
		output = fmt.Sprintf("%s%s%s", output, _SEP, owner)
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
	_println(output)
}

func printLineFile(path string, fInfo os.FileInfo, db *sql.DB) {
	modTime := fInfo.ModTime()
	var blobSize int64 = 0
	// If .properties file is checked and _WITH_BLOB_SIZE, then get the size of .bytes file
	if *_WITH_BLOB_SIZE && *_FILTER == _PROP_EXT && strings.HasSuffix(path, _PROP_EXT) {
		blobPath := getPathWithoutExt(path) + _BYTE_EXT
		blobSize = getBlobSizeFile(blobPath)
	}
	output := genOutput(path, modTime, fInfo.Size(), blobSize, db, nil)
	_println(output)
}

func genOutput(path string, modTime time.Time, size int64, blobSize int64, db *sql.DB, client interface{}) string {
	atomic.AddInt64(&_CHECKED_N, 1)

	modTimeTs := modTime.Unix()
	if !isTsMSecBetweenTs(modTimeTs*1000, _MOD_DATE_FROM_ts, _MOD_DATE_TO_ts) {
		_log("DEBUG", fmt.Sprintf("path:%s modTime %d is outside of the range %d to %d", path, modTimeTs, _MOD_DATE_FROM_ts, _MOD_DATE_TO_ts))
		return ""
	}

	output := fmt.Sprintf("%s%s%s%s%d", path, _SEP, modTime, _SEP, size)

	if *_WITH_BLOB_SIZE {
		output = fmt.Sprintf("%s%s%d", output, _SEP, blobSize)
	}

	// If .properties file is checked, depending on other flags, output can be changed.
	if strings.HasSuffix(path, _PROP_EXT) {
		output = _printLineExtra(output, path, modTimeTs, db, client)
	}

	// Updating counters and return
	if len(output) > 0 {
		atomic.AddInt64(&_PRINTED_N, 1)
		atomic.AddInt64(&_TTL_SIZE, size+blobSize)
	}
	return output
}

// To handle a bit complicated conditions
func _printLineExtra(output string, path string, modTimeTs int64, db *sql.DB, client interface{}) string {
	if _START_TIME_ts > 0 && modTimeTs > _START_TIME_ts {
		_log("INFO", "path:"+path+" is recently modified, so skipping ("+strconv.FormatInt(modTimeTs, 10)+" > "+strconv.FormatInt(_START_TIME_ts, 10)+")")
		return ""
	}
	// no need to open the properties file if no _REMOVE_DEL, no _WITH_PROPS, no DB connection (or not BS) and no _DEL_DATE_FROM/TO
	if (!*_REMOVE_DEL) && (!*_WITH_PROPS) && (len(*_FILTER_P) == 0 && len(*_FILTER_PX) == 0) && (len(*_DB_CON_STR) == 0 || *_TRUTH != "BS") && _DEL_DATE_FROM_ts == 0 && _DEL_DATE_TO_ts == 0 {
		return output
	}

	// Excluding above special condition, usually needs to read the file
	contents, err := getContents(path, client)
	if err != nil {
		_log("ERROR", "getContents for "+path+" returned error:"+err.Error())
		// if no content, no point of restoring
		return ""
	}
	if len(contents) == 0 {
		_log("WARN", "getContents for "+path+" returned 0 size.") // But still can check orphan
	}

	// If 'contents' is given, get the repository name and use it in the query.
	if len(*_DB_CON_STR) > 0 && len(*_TRUTH) > 0 && *_TRUTH == "BS" {
		blobId := extractBlobIdFromString(path)
		if !isBlobMissingInDB(contents, blobId, db) {
			// In this line, this script is checking if this blob is missing in DB, so if it exists, just return empty
			return ""
		} else {
			_log("WARN", "blobId:"+blobId+" does not exist in database.")
		}
	}

	if *_WITH_PROPS || len(*_FILTER_P) > 0 || len(*_FILTER_PX) > 0 {
		props, skipReason := genOutputFromProp(contents)
		if skipReason != nil {
			_log("DEBUG", fmt.Sprintf("%s: %s", path, skipReason.Error()))
			return ""
		}
		if *_WITH_PROPS && len(props) > 0 {
			output = fmt.Sprintf("%s%s%s", output, _SEP, props)
		}
	}

	// removeDel requires 'contents', so executing in here.
	if *_REMOVE_DEL {
		_ = removeDel(contents, path, client)
	}

	return output
}

// as per google, this would be faster than using TrimSuffix
func getPathWithoutExt(path string) string {
	return path[:len(path)-len(filepath.Ext(path))]
}

func extractBlobIdFromString(path string) string {
	return _R_BLOB_ID.FindString(path)
	//fileName := filepath.Base(path)
	//return getPathWithoutExt(fileName)
}

func getNowStr() string {
	currentTime := time.Now()
	return currentTime.Format("2006-01-02 15:04:05")
}

func getContents(path string, client interface{}) (string, error) {
	switch client.(type) {
	// TODO: add Azure
	case *s3.Client:
		return getContentsS3(path, client.(*s3.Client))
	default:
		return getContentsFile(path)
	}
}

func getContentsFile(path string) (string, error) {
	thresholdMs := 0
	if _DEBUG != nil && *_DEBUG {
		defer _elapsed(time.Now().UnixMilli(), "DEBUG Read "+path, int64(thresholdMs))
	} else {
		// If cloud storage, increase the threshold
		if _BS_TYPE != nil && (*_BS_TYPE != "" && *_BS_TYPE != "F") {
			thresholdMs = 3000
		} else {
			thresholdMs = 1000
		}
		defer _elapsed(time.Now().UnixMilli(), "WARN  slow file read for path:"+path, int64(thresholdMs))
	}
	bytes, err := os.ReadFile(path)
	if err != nil {
		_log("DEBUG", fmt.Sprintf("ReadFile for %s failed with %s. Ignoring...", path, err.Error()))
		return "", err
	}
	contents := strings.TrimSpace(string(bytes))
	return contents, nil
}

func getObjectS3(path string, client *s3.Client) (*s3.GetObjectOutput, error) {
	value := cacheReadObj(path)
	if value != nil {
		return value.(*s3.GetObjectOutput), nil
	}
	if _DEBUG != nil && *_DEBUG {
		defer _elapsed(time.Now().UnixMilli(), "DEBUG Read "+path, 0)
	} else {
		defer _elapsed(time.Now().UnixMilli(), "WARN  slow file read for path:"+path, 1000)
	}
	input := &s3.GetObjectInput{
		Bucket: _BASEDIR,
		Key:    &path,
	}
	value, err := client.GetObject(context.TODO(), input)
	if err == nil {
		cacheAddObject(path, value, (1 + *_CONC_1*2))
	}
	return value.(*s3.GetObjectOutput), err
}

func getContentsS3(path string, client *s3.Client) (string, error) {
	obj, err := getObjectS3(path, client)
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
		_log("DEBUG2", "Empty DB connection string")
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
		defer _elapsed(time.Now().UnixMilli(), "WARN  slow query:"+query, _SLOW_MS)
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

func getRow(rowCur *sql.Rows, cols []string) []interface{} {
	if cols == nil || len(cols) == 0 {
		_log("ERROR", "No column information")
		return nil
	}
	vals := make([]interface{}, len(cols))
	for i := range cols {
		vals[i] = &vals[i]
	}
	err := rowCur.Scan(vals...)
	if err != nil {
		_log("WARN", "rows.Scan retuned error: "+err.Error())
		return nil
	}
	return vals
}

func genAssetBlobUnionQuery(assetTableNames []string, columns string, afterWhere string, includeTableName bool) string {
	if len(assetTableNames) == 0 {
		_log("DEBUG", "assetTableNames is empty.")
		return ""
	}
	if len(columns) == 0 {
		columns = "a.asset_id, a.repository_id, a.path, a.kind, a.component_id, a.last_downloaded, a.last_updated, ab.*"
	}
	if len(afterWhere) > 0 {
		afterWhere = " WHERE " + afterWhere
	}
	elements := make([]string, 0)
	for _, tableName := range assetTableNames {
		element := "SELECT " + columns
		if includeTableName {
			element = element + ", '" + tableName + "' as tableName"
		}
		element = fmt.Sprintf("%s FROM %s_blob ab", element, tableName)
		// NOTE: Left Join is required otherwise when Cleanup unused asset blob task has not been run, this script thinks that blob is orphaned, which is not true
		element = fmt.Sprintf("%s LEFT JOIN %s a USING (asset_blob_id)", element, tableName)
		element = fmt.Sprintf("%s%s", element, afterWhere)
		elements = append(elements, element)
	}
	query := ""
	if len(elements) == 1 {
		query = elements[0]
	} else if len(elements) > 1 {
		query = "(" + strings.Join(elements, ") UNION ALL (") + ")"
	}
	return query
}

func genAssetBlobUnionQueryFromRepoNames(repoNames []string, columns string, afterWhere string, includeRepoName bool) string {
	if len(columns) == 0 {
		columns = "a.asset_id, a.repository_id, a.path, a.kind, a.component_id, a.last_downloaded, a.last_updated, ab.*"
	}
	if len(afterWhere) > 0 {
		afterWhere = " WHERE " + afterWhere
	}
	elements := make([]string, 0)
	for _, repoName := range repoNames {
		element := "SELECT " + columns
		if includeRepoName {
			element = element + ", '" + repoName + "' as repoName"
		}
		format := getFmtFromRepName(repoName)
		if len(format) == 0 {
			continue
		}
		tableName := format + "_asset"
		tableNameCR := format + "_content_repository"
		element = fmt.Sprintf("%s FROM %s_blob ab", element, tableName)
		// NOTE: Using INNER Join otherwise can't get repository
		element = fmt.Sprintf("%s INNER JOIN %s a USING (asset_blob_id)", element, tableName)
		element = fmt.Sprintf("%s INNER JOIN %s cr USING (repository_id)", element, tableNameCR)
		element = fmt.Sprintf("%s INNER JOIN repository r ON cr.config_repository_id = r.id AND r.name = '%s'", element, repoName)
		element = fmt.Sprintf("%s%s", element, afterWhere)
		elements = append(elements, element)
	}

	query := ""
	if len(elements) == 1 {
		query = elements[0]
	} else if len(elements) > 1 {
		query = "(" + strings.Join(elements, ") UNION ALL (") + ")"
	}
	// TODO: UNION-ing per repo affects performance? (probably not or not siginificant)
	return query
}

func genBlobIdCheckingQuery(blobId string, tableNames []string) string {
	// Just in case, supporting older version by using "%'"
	where := "blob_ref LIKE '%" + blobId + "%' LIMIT 1"
	if len(*_BS_NAME) > 0 {
		// Supporting only 3.47 and higher for performance (NEXUS-35934 blobRef no longer contains NODE_ID)
		where = "blob_ref = '" + *_BS_NAME + "@" + blobId + "' LIMIT 1"
	}
	// As using LEFT JOIN 'asset_id' can be NULL (nil), but rows size is not 0
	query := genAssetBlobUnionQuery(tableNames, "asset_id", where, false)
	return query
}

func getFmtFromRepName(repoName string) string {
	if repoFmt, ok := _REPO_TO_FMT[repoName]; ok {
		if len(repoFmt) > 0 {
			return repoFmt
		}
	}
	_log("DEBUG", fmt.Sprintf("repoName: %s is not in reposToFmt\n%v", repoName, _REPO_TO_FMT))
	return ""
}

func convRepoNamesToAssetTableName(repoNames string) (result []string) {
	rnSlice := strings.Split(repoNames, ",")
	u := make(map[string]bool)
	for _, repoName := range rnSlice {
		format := getFmtFromRepName(repoName)
		if len(format) > 0 {
			tableName := format + "_asset"
			if _, ok := u[tableName]; !ok {
				result = append(result, tableName)
				u[tableName] = true
			}
		}
	}
	return result
}

func getAssetTables(contents string) []string {
	if _REPO_TO_FMT == nil || len(_REPO_TO_FMT) == 0 {
		// NOTE: should not initiarise/populate _REPO_TO_FMT in here because of coroutine
		_log("ERROR", "getAssetTables requires _REPO_TO_FMT but empty.")
		return nil
	}

	if len(contents) > 0 {
		m := _R_REPO_NAME.FindStringSubmatch(contents)
		if len(m) < 2 {
			_log("DEBUG", "No _R_REPO_NAME in "+contents)
			// At this moment, if no blobName, assuming NOT missing...
			return nil
		}
		return convRepoNamesToAssetTableName(m[1])
	}
	if len(_ASSET_TABLES) > 0 {
		return _ASSET_TABLES
	}
	return nil
}

func isBlobMissingInDB(contents string, blobId string, db *sql.DB) bool {
	// UNION ALL query against many tables is slow. so if contents is given, using specific table
	tableNames := getAssetTables(contents)
	if tableNames == nil || len(tableNames) == 0 { // Mainly for unit test
		_log("WARN", "Cannot identify the format from the repo-name for blobId: "+blobId)
		_log("DEBUG", contents)
		return true
	}
	query := genBlobIdCheckingQuery(blobId, tableNames)
	if len(query) == 0 { // Mainly for unit test
		_log("ERROR", fmt.Sprintf("Could not generate SQL for blobId: %s and tableNames: %v. Skipping (not treating as missing)", blobId, tableNames))
		return false
	}
	if _SLOW_MS == 100 {
		// This query can take longer so not showing too many WARNs
		_SLOW_MS = int64(len(tableNames) * 100)
	}
	rows := queryDb(query, db)
	_SLOW_MS = int64(100)
	if rows == nil { // Mainly for unit test
		_log("ERROR", fmt.Sprintf("Could not get the correct response from the DB for blobId: %s and tableNames: %v. Skipping (not treating as missing)", blobId, tableNames))
		_log("DEBUG", query)
		return false
	}
	defer rows.Close()
	var cols []string
	noRows := true
	for rows.Next() {
		// Expecting a lot blobs exist in DB, so showing the result only when DEBUG is set
		if *_DEBUG {
			if cols == nil || len(cols) == 0 {
				cols, _ = rows.Columns()
				if cols == nil || len(cols) == 0 {
					panic("No columns against query:" + query)
				}
			}
			vals := getRow(rows, cols)
			// As using LEFT JOIN 'asset_id' can be NULL (nil), but rows size is not 0
			_log("DEBUG", fmt.Sprintf("blobId: %s row: %v", blobId, vals))
		}
		noRows = false
		break
	}
	return noRows
}

func isSoftDeleted(path string, client interface{}) bool {
	contents, err := getContents(path, client)
	if err != nil {
		_log("WARN", fmt.Sprintf("isSoftDeleted for path:%s failed with '%s', assuming not soft-deleted.", path, err.Error()))
		return false
	}
	return _R_DELETED.MatchString(contents)
}

func shouldBeUnDeleted(contents string, path string) bool {
	// NOTE: currently undeleting if incorrect deletedDateTime in the properties file
	matches := _R_DELETED_DT.FindStringSubmatch(contents)
	if matches == nil || len(matches) == 0 {
		_log("WARN", fmt.Sprintf("path:%s has incorrect deletedDateTime (but un-deleting)", path))
		return true
	}
	delTimeTs, err := strconv.ParseInt(matches[1], 10, 64)
	if err != nil {
		_log("WARN", fmt.Sprintf("path:%s has incorrect deletedDateTime %v (but un-deleting)", path, matches))
		return true
	}
	if isTsMSecBetweenTs(delTimeTs, _DEL_DATE_FROM_ts, _DEL_DATE_TO_ts) {
		_log("DEBUG", fmt.Sprintf("path:%s delTimeTs %d (msec) is in the range %d (sec) to %d (sec)", path, delTimeTs, _DEL_DATE_FROM_ts, _DEL_DATE_TO_ts))
		return true
	}
	_log("DEBUG", fmt.Sprintf("path:%s delTimeTs %d (msec) is NOT in the range %d (sec) to %d (sec)", path, delTimeTs, _DEL_DATE_FROM_ts, _DEL_DATE_TO_ts))
	return false
}

func removeDel(contents string, path string, client interface{}) bool {
	if !shouldBeUnDeleted(contents, path) {
		return false
	}

	if *_DRY_RUN {
		_log("INFO", fmt.Sprintf("Removed 'deleted=true' for path:%s (DRY-RUN)", path))
		return true
	}

	updatedContents := removeLines(contents, _R_DELETED)
	err := writeContents(path, updatedContents, client)
	if err != nil {
		_log("ERROR", fmt.Sprintf("Removing 'deleted=true' for path:%s failed with %s", path, err))
		return false
	}
	if len(contents) == len(updatedContents) {
		_log("WARN", fmt.Sprintf("Removed 'deleted=true' from path:%s but size is same (%d => %d)", path, len(contents), len(updatedContents)))
		return false
	}

	switch client.(type) {
	// TODO: add Azure
	case *s3.Client:
		errTag := removeTagsS3(path, client.(*s3.Client))
		if errTag != nil {
			_log("ERROR", fmt.Sprintf("Removed 'deleted=true' but removeTagsS3 for path:%s failed with %s", path, errTag))
			return false
		}

		bPath := getPathWithoutExt(path) + _BYTE_EXT
		errTag = removeTagsS3(bPath, client.(*s3.Client))
		if errTag != nil {
			_log("WARN", fmt.Sprintf("Removed 'deleted=true' but removeTagsS3 for path:%s failed with %s", bPath, errTag))
			return true
		}
		_log("INFO", fmt.Sprintf("Removed 'deleted=true' and S3 tag for path:%s", path))
	default:
		_log("INFO", fmt.Sprintf("Removed 'deleted=true' for path:%s", path))
	}
	return true
}

// one line but for unit testing
func removeLines(contents string, rex *regexp.Regexp) string {
	return rex.ReplaceAllString(contents, "")
}

func isTsMSecBetweenTs(tMsec int64, fromTs int64, toTs int64) bool {
	if fromTs > 0 && (fromTs*1000) > tMsec {
		return false
	}
	if toTs > 0 && (toTs*1000) < tMsec {
		return false
	}
	return true
}

func genOutputFromProp(contents string) (string, error) {
	// To use simpler regex, sorting line and converting to single line first
	lines := strings.Split(contents, "\n")
	sort.Strings(lines)
	// if "deleted=true" is removed, the properties file may have empty line
	sortedContents := strings.Trim(strings.Join(lines, ","), ",")

	// Exclude check first
	if _RX != nil && len(_RX.String()) > 0 && _RX.MatchString(sortedContents) {
		return "", errors.New(fmt.Sprintf("Matched with the exclude regex: %s. Skipping.", _RX.String()))
	}

	if _R != nil && len(_R.String()) > 0 {
		if _R.MatchString(sortedContents) {
			return sortedContents, nil
		} else {
			_log("DEBUG2", fmt.Sprintf("Sorted content: '%s'", sortedContents))
			return "", errors.New(fmt.Sprintf("Does NOT match with the regex: %s. Skipping.", _R.String()))
		}
	}

	// Not treating as regex
	if _RX == nil && len(*_FILTER_PX) > 0 && strings.Contains(sortedContents, *_FILTER_PX) {
		return "", errors.New(fmt.Sprintf("Contains excluding string '%s'. Skipping.", *_FILTER_PX))
	}
	if _R == nil && len(*_FILTER_P) > 0 && !strings.Contains(sortedContents, *_FILTER_P) {
		return "", errors.New(fmt.Sprintf("Does not contain '%s'. Skipping.", *_FILTER_P))
	}

	// If no _FILTER_P, just return the contents as single line. Should also escape '"'?
	return sortedContents, nil
}

// get *all* directories under basedir and which name starts with prefix
func getDirsS3(client *s3.Client) []string {
	var dirs []string
	var prefix string = *_PREFIX
	var contain string

	// Prefix not ending / does not work, for example: ${S3_PREFIX}/content/vol-, so trying to handle in here
	if !strings.HasSuffix(prefix, "/") {
		if strings.Contains(prefix, "/") {
			prefix_tmp := filepath.Dir(prefix)
			if len(prefix_tmp) > 0 {
				prefix = prefix_tmp
				contain = filepath.Base(prefix)
				_log("DEBUG", fmt.Sprintf("S3 prefix = %s, contain = %s", prefix, contain))
			}
		}
	}

	_log("DEBUG", fmt.Sprintf("Retriving sub folders under %s", *_PREFIX))
	// Not expecting more than 1000 sub folders, so no MaxKeys
	input := &s3.ListObjectsV2Input{
		Bucket:    aws.String(*_BASEDIR),
		Prefix:    aws.String(strings.TrimSuffix(prefix, "/") + "/"),
		Delimiter: aws.String("/"),
	}
	resp, err := client.ListObjectsV2(context.TODO(), input)
	if err != nil {
		println("Got error retrieving list of objects:")
		panic(err.Error())
	}

	if len(resp.CommonPrefixes) == 0 {
		_log("DEBUG", fmt.Sprintf("resp.CommonPrefixes is empty for %s, so using this prefix.", *_PREFIX))
		dirs = append(dirs, *_PREFIX)
	} else {
		for _, item := range resp.CommonPrefixes {
			if len(strings.TrimSpace(*item.Prefix)) == 0 {
				continue
			}
			if len(contain) > 0 && !strings.Contains(*item.Prefix, contain) {
				_log("DEBUG", fmt.Sprintf("Skipping %s as it doss not contain %s", *item.Prefix, contain))
				continue
			}
			_log("DEBUG", fmt.Sprintf("Appending %s in dirs", *item.Prefix))
			dirs = append(dirs, *item.Prefix)
		}
		sort.Strings(dirs)
	}
	return dirs
}

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

func myHashCode(s string) int32 {
	h := int32(0)
	for _, c := range s {
		h = (31 * h) + int32(c)
	}
	return h
}

func genBlobPath(blobIdLikeString string) string {
	blobId := blobIdLikeString

	if !_DISABLE_DATE_BLOBPATH {
		var matches []string
		// NOTE: this returns path without slash at the beginning and no extension
		NewBlobIdPattern := regexp.MustCompile(`.*([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})@(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}).*`)
		matches = NewBlobIdPattern.FindStringSubmatch(blobIdLikeString)
		if len(matches) > 6 {
			// 6c1d3423-ecbc-4c52-a0fe-01a45a12883a@2025-08-14T02:44
			// 2025/08/14/02/44/6c1d3423-ecbc-4c52-a0fe-01a45a12883a.properties
			return filepath.Join(matches[2], matches[3], matches[4], matches[5], matches[6], matches[1])
		}
		NewBlobIdPattern2 := regexp.MustCompile(`/?([0-9]{4})/([0-9]{2})/([0-9]{2})/([0-9]{2})/([0-9]{2})/([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}).*`)
		matches = NewBlobIdPattern2.FindStringSubmatch(blobIdLikeString)
		if len(matches) > 6 {
			return filepath.Join(matches[1], matches[2], matches[3], matches[4], matches[5], matches[6])
		}
		BlobIdPattern := regexp.MustCompile(`.*([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}).*`)
		matches = BlobIdPattern.FindStringSubmatch(blobIdLikeString)
		if matches == nil || len(matches) < 2 {
			return ""
		}
		blobId = matches[1]
	}

	// org.sonatype.nexus.blobstore.VolumeChapterLocationStrategy#location
	hashInt := myHashCode(blobId)
	vol := math.Abs(math.Mod(float64(hashInt), 43)) + 1
	chap := math.Abs(math.Mod(float64(hashInt), 47)) + 1
	return filepath.Join(fmt.Sprintf("vol-%02d", int(vol)), fmt.Sprintf("chap-%02d", int(chap)), blobId)
}

func softDeletedCount(dbConStr string) {
	db := openDb(dbConStr)
	defer db.Close()

	query := "SELECT source_blob_store_name, count(*), min(deleted_date) FROM soft_deleted_blobs group by 1 order by 1"
	rows := queryDb(query, db)
	defer rows.Close()
	cols, _ := rows.Columns()
	if cols == nil || len(cols) == 0 {
		panic("No columns against query:" + query)
	}
	_log("INFO", query)
	for rows.Next() {
		vals := getRow(rows, cols)
		jsonVals, _ := json.Marshal(vals)
		_log("INFO", fmt.Sprintf("%s", jsonVals))
	}
}

func openInOrFIle(path string) *os.File {
	f := os.Stdin
	if path != "-" {
		var err error
		f, err = os.Open(path)
		if err != nil {
			_log("ERROR", "path:"+path+" cannot be opened. "+err.Error())
			return nil
		}
	}
	return f
}

func printDeadBlobsFromIdFile(blobIdsFile string, conc int, s3Client interface{}) {
	f := openInOrFIle(blobIdsFile)
	defer f.Close()
	var wg sync.WaitGroup
	guard := make(chan struct{}, conc)
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		_log("DEBUG2", fmt.Sprintf("printDeadBlobsFromDb line: %s", line))

		guard <- struct{}{}
		wg.Add(1)
		go func(line string, s3Client interface{}) {
			defer wg.Done()
			// TODO: Havn't decided how to retrieve the asset_id
			printDeadBlob(0, line, s3Client)
			<-guard
		}(line, s3Client)
	}
	wg.Wait()
}

func printDeadBlobsFromDb(dbConStr string, conc int, client interface{}) {
	db := openDb(dbConStr)
	if db == nil {
		panic("Cannot open the database.") // Can't output _DB_CON_STR as it may include password
	} else {
		defer db.Close()
	}

	if len(_ASSET_TABLES) == 0 {
		initRepoFmtMap(db)
	}
	query := ""
	var rnSlice []string
	if _REPO_NAMES != nil && len(*_REPO_NAMES) > 0 {
		rnSlice = strings.Split(*_REPO_NAMES, ",")
	} else if (_REPO_NAMES == nil || len(*_REPO_NAMES) == 0) && len(*_BS_NAME) > 0 {
		// If no repo name (empty rnSlice), should get only related repos of the blobstore
		for k := range _REPO_TO_FMT {
			rnSlice = append(rnSlice, k)
		}
	}

	afterWhere := ""
	if _MOD_DATE_FROM_ts > 0 {
		if len(afterWhere) > 0 {
			afterWhere += " and "
		}
		afterWhere += fmt.Sprintf("ab.blob_created >= TO_TIMESTAMP(%d)", _MOD_DATE_FROM_ts)
	}
	if _MOD_DATE_TO_ts > 0 {
		if len(afterWhere) > 0 {
			afterWhere += " and "
		}
		afterWhere += fmt.Sprintf("ab.blob_created <= TO_TIMESTAMP(%d)", _MOD_DATE_TO_ts)
	}
	_log("DEBUG", fmt.Sprintf("genAssetBlobUnionQueryFromRepoNames with %v and %s", rnSlice, afterWhere))

	query = genAssetBlobUnionQueryFromRepoNames(rnSlice, "a.asset_id, ab.blob_ref", afterWhere, false)
	rows := queryDb(query, db)
	defer rows.Close()
	cols, _ := rows.Columns()
	if cols == nil || len(cols) == 0 {
		panic("No columns against query:" + query)
	}

	var wg sync.WaitGroup
	guard := make(chan struct{}, conc)
	for rows.Next() {
		vals := getRow(rows, cols)
		_log("DEBUG2", fmt.Sprintf("printDeadBlobsFromDb vals: %v", vals))

		guard <- struct{}{}
		wg.Add(1)
		go func(vals []interface{}, client interface{}) {
			defer wg.Done()
			printDeadBlob(vals[0].(int64), vals[1].(string), client)
			<-guard
		}(vals, client)
	}
	wg.Wait()
}

func printDeadBlob(assetId int64, blobRef string, s3Client interface{}) {
	blobId := extractBlobIdFromString(blobRef)
	if len(blobId) == 0 {
		_log("DEBUG", fmt.Sprintf("printDeadBlobsFromDb, skipping %v", blobRef))
		return
	}
	_log("DEBUG", fmt.Sprintf("printDeadBlobsFromDb, checking blobId: %v", blobId))
	path := *_BASEDIR + string(filepath.Separator) + genBlobPath(blobId)
	size := getBlobSize(path+_PROP_EXT, s3Client)
	if size < 0 { // At this moment, accepting 0 bytes .properties file...
		// At this moment, not checkinb .bytes for performance
		/*size2 := getBlobSize(path+_BYTE_EXT, s3Client)
		if size2 >= 0 {
			_log("WARN", fmt.Sprintf("%s exists.", path+_BYTE_EXT))
		}*/
		_log("WARN", fmt.Sprintf("%s is unreadable.", path+_PROP_EXT))
		_println(fmt.Sprintf("%d%s%s", assetId, _SEP, blobRef))
	} else if isSoftDeleted(path+_PROP_EXT, s3Client) {
		_log("WARN", fmt.Sprintf("%s is soft-deleted.", path+_PROP_EXT))
	}
}

func printOrphanedBlobsFromIdFile(blobIdsFile string, dbConStr string, conc int) {
	f := openInOrFIle(blobIdsFile)
	defer f.Close()

	var wg sync.WaitGroup
	guard := make(chan struct{}, conc)
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		guard <- struct{}{}
		wg.Add(1)

		go func(line string) {
			defer wg.Done()
			_log("DEBUG", "Extracting blobId from '"+line+"' .")
			blobId := extractBlobIdFromString(line)
			if len(blobId) == 0 {
				_log("DEBUG", "line:"+line+" doesn't contain blibId.")
			} else {
				if *_TRUTH == "BS" {
					// NOTE: Suspecting `openDb` from the outside of Goroutine may not open concurrent connections, so doing in here
					db := openDb(dbConStr)
					if db == nil {
						panic("Cannot open the database.") // Can't output _DB_CON_STR as it may include password
					}
					defer db.Close()
					if isBlobMissingInDB("", blobId, db) {
						_log("WARN", "blobId:"+blobId+" does not exist in database.")
						if blobId != line {
							_println(line)
						} else {
							_println(genBlobPath(blobId) + ".*")
						}
					} else {
						_log("INFO", "blobId:"+blobId+" exists in database.")
					}
				} else {
					panic("_TRUSE == " + *_TRUTH + " is not implemented yet.")
				}
				_log("DEBUG", "Completed blobId '"+blobId+"' .")
			}
			<-guard
		}(line)
	}
	wg.Wait()

	if err := scanner.Err(); err != nil {
		_log("ERROR", err.Error())
	}
}

func listObjectsS3(dir string, db *sql.DB, client interface{}) int64 {
	var subTtl int64
	input := &s3.ListObjectsV2Input{
		Bucket:     _BASEDIR,
		FetchOwner: aws.Bool(*_WITH_OWNER),
		Prefix:     &dir,
	}
	// TODO: below does not seem to be working, as StartAfter should be Key
	//if _MOD_DATE_FROM_ts > 0 {
	//	input.StartAfter = aws.String(time.Unix(_MOD_DATE_FROM_ts, 0).UTC().Format("2006-01-02T15:04:05.000Z"))
	//}

	for {
		p := s3.NewListObjectsV2Paginator((client.(*s3.Client)), input, func(o *s3.ListObjectsV2PaginatorOptions) {
			if v := int32(*_MAXKEYS); v != 0 {
				o.Limit = v
			}
		})

		//https://stackoverflow.com/questions/25306073/always-have-x-number-of-goroutines-running-at-any-time
		wgTags := sync.WaitGroup{}                  // *
		guardFiles := make(chan struct{}, *_CONC_2) // **

		var i int
		for p.HasMorePages() {
			i++
			resp, err := p.NextPage(context.Background())
			if err != nil {
				println("Got error retrieving list of objects:")
				panic(err.Error())
			}
			if i > 1 {
				_log("INFO", fmt.Sprintf("%s: Page %d, %d objects", dir, i, len(resp.Contents)))
			}

			for _, item := range resp.Contents {
				if len(*_FILTER) == 0 || strings.Contains(*item.Key, *_FILTER) {
					subTtl++
					guardFiles <- struct{}{}                                    // **
					wgTags.Add(1)                                               // *
					go func(client *s3.Client, item types.Object, db *sql.DB) { // **
						printLineS3(item, client, db)
						<-guardFiles  // **
						wgTags.Done() // *
					}(client.(*s3.Client), item, db)
				}
				if *_TOP_N > 0 && *_TOP_N <= _PRINTED_N {
					break
				}
			}
			if *_TOP_N > 0 && *_TOP_N <= _PRINTED_N {
				break
			}
		}
		wgTags.Wait() // *

		// Continue if truncated (more data available) and if not reaching to the top N.
		if *_TOP_N > 0 && *_TOP_N <= _PRINTED_N {
			_log("INFO", fmt.Sprintf("Found total: %d and reached to %d", _PRINTED_N, *_TOP_N))
			break
		} else {
			break
		}
	}
	return subTtl
}

func listObjectsFile(dir string, db *sql.DB) int64 {
	var subTtl int64
	// As this method is used in the goroutine, open own DB and close
	// Below line does not work because currently Glob does not support ./**/*
	//list, err := filepath.Glob(dir + string(filepath.Separator) + *_FILTER)
	// Somehow WalkDir is slower in this code
	//err := filepath.WalkDir(dir, func(path string, f fs.DirEntry, err error) error {
	err := filepath.Walk(dir, func(path string, f os.FileInfo, err error) error {
		if err != nil {
			return errors.Wrap(err, "failed filepath.WalkDir")
		}
		if !f.IsDir() {
			if len(*_FILTER) == 0 || strings.Contains(f.Name(), *_FILTER) {
				subTtl++
				printLineFile(path, f, db)
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
	return subTtl
}

func listObjects(dir string, client interface{}) {
	startMs := time.Now().UnixMilli()
	var subTtl int64
	// As this method is used in the goroutine, open own DB and close
	db := openDb(*_DB_CON_STR)
	if db != nil {
		defer db.Close()
	}
	if _BS_TYPE != nil && *_BS_TYPE == "S" {
		subTtl = listObjectsS3(dir, db, client)
	} else {
		subTtl = listObjectsFile(dir, db)
	}
	// Always log this elapsed time by using 0 thresholdMs
	_elapsed(startMs, fmt.Sprintf("INFO  Completed %s for %d files (current total: %d)", dir, subTtl, _CHECKED_N), 0)
}

func printObjectByBlobId(blobId string, db *sql.DB, client interface{}) {
	if len(blobId) == 0 {
		_log("DEBUG2", fmt.Sprintf("Empty blobId"))
		return
	}
	path := _CONTENT_PATH + string(filepath.Separator) + genBlobPath(blobId) + _PROP_EXT
	if len(*_FILTER) == 0 || strings.Contains(path, *_FILTER) {
		printObjectByPath(path, db, client)
	}
	path = _CONTENT_PATH + string(filepath.Separator) + genBlobPath(blobId) + _BYTE_EXT
	if len(*_FILTER) == 0 || strings.Contains(path, *_FILTER) {
		printObjectByPath(path, db, client)
	}
}

func printObjectByPath(path string, db *sql.DB, client interface{}) {
	_log("DEBUG", path)
	switch client.(type) {
	// TODO: add Azure
	case *s3.Client:
		obj, err := getObjectS3(path, client.(*s3.Client))
		if err != nil {
			_log("ERROR", fmt.Sprintf("Failed to access %s", path))
			return
		}
		var item types.Object
		item.Key = &path
		item.LastModified = obj.LastModified
		item.Size = obj.ContentLength
		//item.Owner.DisplayName = nil // TODO: not sure how to get owner from header
		printLineS3(item, client.(*s3.Client), db)
	default:
		defer _elapsed(time.Now().UnixMilli(), "WARN  slow file read for path:"+path, 100)
		fileInfo, err := os.Stat(path)
		if err != nil {
			_log("ERROR", fmt.Sprintf("Failed to access %s", path))
			return
		}
		printLineFile(path, fileInfo, db)
	}
}

func mainFinally() {
	// If DB connection string is given, and if not S3, output soft-deleted count (not sure if Azure uses this table)
	if len(*_DB_CON_STR) > 0 && (_BS_TYPE == nil || *_BS_TYPE != "S") {
		println("")
		softDeletedCount(*_DB_CON_STR)
	}
	println("")
	//_log("INFO", fmt.Sprintf("Completed. (elapsed:%ds)", time.Now().Unix()-_START_TIME_ts))
	_log("INFO", fmt.Sprintf("Completed %d of %d (size:%d, elapsed:%ds)", _PRINTED_N, _CHECKED_N, _TTL_SIZE, time.Now().Unix()-_START_TIME_ts))
	os.Exit(0)
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

	var client interface{}
	if _BS_TYPE != nil && *_BS_TYPE == "S" {
		cfg, err := config.LoadDefaultConfig(context.TODO())
		if _DEBUG2 != nil && *_DEBUG2 {
			// https://aws.github.io/aws-sdk-go-v2/docs/configuring-sdk/logging/
			cfg, err = config.LoadDefaultConfig(context.TODO(), config.WithClientLogMode(aws.LogRetries|aws.LogRequest))
		}
		if err != nil {
			panic("configuration error, " + err.Error())
		}
		client = s3.NewFromConfig(cfg)
	}

	if len(*_TRUTH) > 0 && *_TRUTH == "DB" {
		if !*_NO_HEADER {
			_println(fmt.Sprintf("ASSET_ID%sBLOB_REF", _SEP))
		}
		if len(*_BLOB_IDS_FILE) > 0 {
			_log("INFO", "The source is 'DB' and Blobs ID file: "+*_BLOB_IDS_FILE+"")
			printDeadBlobsFromIdFile(*_BLOB_IDS_FILE, *_CONC_1, client)
		} else if len(*_DB_CON_STR) > 0 {
			_log("INFO", "The source is 'DB' and no Blobs ID file, so reading from DB")
			printDeadBlobsFromDb(*_DB_CON_STR, *_CONC_1, client)
		} else {
			_log("ERROR", "No DB connection or blob IDs file.")
			return
		}
		println("")
		_log("INFO", fmt.Sprintf("Completed. (elapsed:%ds)", time.Now().Unix()-_START_TIME_ts))
		return
	}

	// If a file which contains blob IDs, check those IDs are in the DB
	if len(*_TRUTH) > 0 && *_TRUTH == "BS" && len(*_BLOB_IDS_FILE) > 0 {
		if len(*_DB_CON_STR) == 0 {
			_log("WARN", "DB connection string (-db) is missing")
		}
		_log("INFO", "Reading "+*_BLOB_IDS_FILE)
		printOrphanedBlobsFromIdFile(*_BLOB_IDS_FILE, *_DB_CON_STR, *_CONC_1)
		mainFinally()
	}

	_log("INFO", fmt.Sprintf("Retriving sub directories under %s", *_BASEDIR))
	var subDirs []string
	if _BS_TYPE != nil && *_BS_TYPE == "S" {
		subDirs = getDirsS3(client.(*s3.Client))
	} else {
		subDirs = getDirs(*_BASEDIR, *_PREFIX)
	}
	if *_LIST_DIRS {
		fmt.Printf("%v", subDirs)
		os.Exit(0)
	}

	_log("INFO", fmt.Sprintf("Retrived %d sub directories", len(subDirs)))
	_log("DEBUG", fmt.Sprintf("Sub directories: %v", subDirs))

	// Printing headers (unless no header)
	if !*_NO_HEADER {
		header := fmt.Sprintf("Path%sLastModified%sSize", _SEP, _SEP)
		if *_WITH_BLOB_SIZE && *_FILTER == _PROP_EXT {
			header += fmt.Sprintf("%sBlobSize", _SEP)
		}
		if *_WITH_PROPS {
			header += fmt.Sprintf("%sProperties", _SEP)
		}
		if *_WITH_OWNER {
			header += fmt.Sprintf("%sOwner", _SEP)
		}
		if *_WITH_TAGS {
			header += fmt.Sprintf("%sTags", _SEP)
		}
		_println(header)
	}

	wg := sync.WaitGroup{}
	guard := make(chan struct{}, *_CONC_1)
	if len(*_BLOB_IDS_FILE) > 0 {
		f := openInOrFIle(*_BLOB_IDS_FILE)
		defer f.Close()

		scanner := bufio.NewScanner(f)
		var blobIds []string
		for scanner.Scan() {
			blobId := extractBlobIdFromString(scanner.Text())
			blobIds = append(blobIds, blobId)
		}

		chunks := chunkSlice(blobIds, *_CONC_1)
		for _, chunk := range chunks {
			guard <- struct{}{}
			wg.Add(1)
			go func(blobIds []string, client interface{}) {
				defer wg.Done()
				var db *sql.DB
				if len(*_DB_CON_STR) > 0 {
					db = openDb(*_DB_CON_STR)
					defer db.Close()
				}
				for _, blobId := range blobIds {
					printObjectByBlobId(blobId, db, client)
				}
				<-guard
			}(chunk, client)
		}
	} else {
		for _, s := range subDirs {
			if len(s) == 0 {
				//_log("DEBUG", "Ignoring empty sub directory.")
				continue
			}
			_log("INFO", "Starting "+s+" ...")
			guard <- struct{}{}
			wg.Add(1)
			go func(subdir string, client interface{}) {
				defer wg.Done()
				listObjects(subdir, client)
				<-guard
			}(s, client)
		}
	}
	wg.Wait()
	mainFinally()
}
