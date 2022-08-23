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
	"database/sql"
	"flag"
	"fmt"
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
var _DB_CON_STR *string
var _TRUTH *string
var _BS_NAME *string
var _DEL_DATE_FROM *string
var _DEL_DATE_FROM_ts int64
var _DEL_DATE_TO *string
var _DEL_DATE_TO_ts int64
var _START_TIME_ts int64
var _TOP_N *int64
var _CONC_1 *int
var _LIST_DIRS *bool
var _WITH_PROPS *bool
var _NO_HEADER *bool
var _USE_REGEX *bool
var _RECON_FMT *bool
var _REMOVE_DEL *bool
var _NO_BLOB_SIZE *bool

//var _EXCLUDE_FILE *string
//var _INCLUDE_FILE *string
var _REPO_TO_FMT map[string]string
var _R *regexp.Regexp
var _R_DEL_DT *regexp.Regexp
var _R_DELETED *regexp.Regexp
var _R_REPO_NAME *regexp.Regexp
var _R_BLOB_NAME *regexp.Regexp
var _DEBUG *bool
var _CHECKED_N int64 // Atomic (maybe slower?)
var _PRINTED_N int64 // Atomic (maybe slower?)
var _TTL_SIZE int64  // Atomic (maybe slower?)
var _SEP = "	"
var _PROP_EXT = ".properties"

type StoreProps map[string]string

func _setGlobals() {
	_BASEDIR = flag.String("b", ".", "Base directory (default: '.')")
	_PREFIX = flag.String("p", "", "Prefix of sub directories (eg: 'vol-')")
	_WITH_PROPS = flag.Bool("P", false, "If true, read and output the .properties files")
	_FILTER = flag.String("f", "", "Filter file paths (eg: '.properties')")
	_NO_BLOB_SIZE = flag.Bool("NBSize", false, "When -f = '.properties', checks Blob size")
	_FILTER_P = flag.String("fP", "", "Filter .properties contents (eg: 'deleted=true')")
	_TRUTH = flag.String("src", "BS", "Using database or blobstore as source [DB|BS]") // TODO: not implemented "DB" yet
	_DB_CON_STR = flag.String("db", "", "DB connection string or path to properties file")
	_BS_NAME = flag.String("bsName", "", "Eg. 'default'. If provided, the query will be faster")
	_USE_REGEX = flag.Bool("R", false, "If true, .properties content is *sorted* and _FILTER_P string is treated as regex")
	_RECON_FMT = flag.Bool("RF", false, "Output for the Reconcile task (any_string,blob_ref). -P will be ignored")
	_REMOVE_DEL = flag.Bool("RDel", false, "Remove 'deleted=true' from .properties. Requires -RF *and* -dF") // TODO: also think about restore plan
	_DEL_DATE_FROM = flag.String("dF", "", "Deleted date YYYY-MM-DD (from). Used to search deletedDateTime")
	_DEL_DATE_TO = flag.String("dT", "", "Deleted date YYYY-MM-DD (to). To exclude newly deleted assets")
	//_EXCLUDE_FILE = flag.String("sk", "", "Blob IDs in this file will be skipped from the check") // TODO
	//_INCLUDE_FILE = flag.String("sk", "", "ONLY blob IDs in this file will be checked")           // TODO
	_TOP_N = flag.Int64("n", 0, "Return first N lines (0 = no limit). (TODO: may return more than N)")
	_CONC_1 = flag.Int("c", 1, "Concurrent number for sub directories (may not need to use with very fast disk)")
	_LIST_DIRS = flag.Bool("L", false, "If true, just list directories and exit")
	_NO_HEADER = flag.Bool("H", false, "If true, no header line")
	_DEBUG = flag.Bool("X", false, "If true, verbose logging")
	flag.Parse()

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
	}
	_log("DEBUG", "_setGlobals completed.")
}

func _log(level string, message string) {
	if level != "DEBUG" || *_DEBUG {
		log.Printf("%s: %s\n", level, message)
	}
}

func _writeToFile(path string, contents string) error {
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

func datetimeStrToTs(datetimeStr string) int64 {
	tmpTimeFrom, err := time.Parse("2006-01-02", datetimeStr)
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

// Not in use for now
func genRepoFmtMap() map[string]string {
	// temporarily opening a DB connection only for this query
	db := openDb()
	defer db.Close()
	rows := queryDb("SELECT name, REGEXP_REPLACE(recipe_name, '-.+', '') AS fmt FROM repository;", db)
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

func printLine(path string, fInfo os.FileInfo, db *sql.DB) bool {
	//_log("DEBUG", fmt.Sprintf("printLine-ing for path:%s", path))
	modTime := fInfo.ModTime()
	modTimeTs := modTime.Unix()
	output := ""
	var blobSize int64 = 0

	if !*_RECON_FMT {
		output = fmt.Sprintf("%s%s%s%s%d", path, _SEP, modTime, _SEP, fInfo.Size())
	}
	// listObjects() already checked _FILTER, but just in case...
	if !*_NO_BLOB_SIZE && *_FILTER == _PROP_EXT && strings.HasSuffix(path, _PROP_EXT) {
		blobSize = getBlobSize(path)
		output = fmt.Sprintf("%s%s%d", output, _SEP, blobSize)
	}
	if strings.HasSuffix(path, _PROP_EXT) {
		output = _printLineExtra(output, path, modTimeTs, db)
	}

	atomic.AddInt64(&_CHECKED_N, 1)
	if len(output) > 0 {
		atomic.AddInt64(&_PRINTED_N, 1)
		atomic.AddInt64(&_TTL_SIZE, fInfo.Size()+blobSize)
		fmt.Println(output)
		return true
	}
	return false
}

func _printLineExtra(output string, path string, modTimeTs int64, db *sql.DB) string {
	skipCheck := false
	if len(*_DB_CON_STR) > 0 && len(*_TRUTH) > 0 {
		// Script is asked to output if this blob is missing in DB
		if *_TRUTH == "BS" {
			if !isBlobIdMissingInDB(path, db) {
				return ""
			}
			skipCheck = true
		}
		if *_TRUTH == "DB" {
			// TODO: if !isBlobIdMissingInBlobStore() {
			//skipCheck = true
			return ""
		}
	}

	if *_RECON_FMT {
		// If reconciliation output format is requested, do not use 'output'
		if !skipCheck && _START_TIME_ts > 0 && modTimeTs > _START_TIME_ts {
			// NOT checking against _DEL_DATE_TO_ts as file might be touched accidentally (I may change my mind if slow)
			return ""
		}
		if !skipCheck && _DEL_DATE_FROM_ts > 0 && modTimeTs < _DEL_DATE_FROM_ts {
			// Even not accurate, to make this function faster, currently checking fileModMs against _DEL_DATE_FROM_ts
			return ""
		}
		reconOutput, reconErr := genOutputForReconcile(path, _DEL_DATE_FROM_ts, _DEL_DATE_TO_ts, skipCheck)
		if reconErr != nil {
			_log("DEBUG", reconErr.Error())
		}
		return reconOutput
	}

	if *_WITH_PROPS {
		props, propErr := genOutputFromProp(path)
		if propErr != nil {
			_log("DEBUG", propErr.Error())
			// If can't read .propreties file, still return the original "output", so not return-ing
			//return ""
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

func getContents(path string) (string, error) {
	_log("DEBUG", fmt.Sprintf("Getting contents from %s", path))
	bytes, err := os.ReadFile(path)
	if err != nil {
		_log("DEBUG", fmt.Sprintf("ReadFile for %s failed with %s. Ignoring...", path, err.Error()))
		return "", err
	}
	contents := strings.TrimSpace(string(bytes))
	return contents, nil
}

func openDb() *sql.DB {
	if len(*_DB_CON_STR) == 0 {
		return nil
	}
	if !strings.Contains(*_DB_CON_STR, "sslmode") {
		*_DB_CON_STR = *_DB_CON_STR + " sslmode=disable"
	}
	db, err := sql.Open("postgres", *_DB_CON_STR)
	if err != nil {
		// If DB connection issue, let's stop the script
		panic(err.Error())
	}
	//defer db.Close()
	//db.SetMaxOpenConns(*_CONC_1)
	//err = db.Ping()
	return db
}

func queryDb(query string, db *sql.DB) *sql.Rows {
	if db == nil { // For unit tests
		return nil
	}
	rows, err := db.Query(query)
	if err != nil {
		panic(err.Error())
	}
	return rows
}

func genBlobIdCheckingQuery(path string, tableNames []string) string {
	blobId := getBaseNameWithoutExt(path)
	queryPrefix := "SELECT asset_blob_id"
	where := "blob_ref LIKE '%:" + blobId + "@%'"
	if len(*_BS_NAME) > 0 {
		// PostgreSQL still uses index for 'like' with forward search, so much faster than above
		// NOTE: node-id or deployment id can vary
		where = "blob_ref like '" + *_BS_NAME + ":" + blobId + "@%'"
	}
	elements := make([]string, 0)
	for _, tableName := range tableNames {
		element := queryPrefix + " FROM " + tableName + " WHERE " + where
		elements = append(elements, element)
	}
	query := strings.Join(elements, " UNION ALL ")
	_log("DEBUG", query)
	return query
}

// only works on postgres
func getAssetBlobTables(path string, db *sql.DB) []string {
	result := make([]string, 0)
	if len(path) > 0 {
		contents, err := getContents(path)
		if err != nil {
			_log("ERROR", "No contents from "+path)
			// if no content, assuming missing
			return result
		}
		m := _R_REPO_NAME.FindStringSubmatch(contents)
		if len(m) < 2 {
			_log("WARN", "No _R_REPO_NAME match for "+path)
			// At this moment, if no blobName, assuming NOT missing...
			return result
		}
		repoName := m[1]
		if repoFmt, ok := _REPO_TO_FMT[repoName]; ok {
			result = append(result, repoFmt+"_asset_blob")
			return result
		} else {
			_log("WARN", "repoName: "+repoName+" is not in _REPO_TO_FMT")
		}
	}
	query := "SELECT table_name FROM information_schema.tables WHERE table_name like '%_asset_blob'"
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

func isBlobIdMissingInDB(path string, db *sql.DB) bool {
	// TODO: Current UNION query is bit slow. Providing "path" generates the repoFmt but too slow
	tableNames := getAssetBlobTables(path, db)
	query := genBlobIdCheckingQuery(path, tableNames)
	// Ref: https://go.dev/doc/database/querying
	rows := queryDb(query, db)
	if rows == nil {
		// For test
		_log("WARN", "rows is nil for "+path+". Ignoring.\nquery: "+query)
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

func genOutputForReconcile(path string, delDateFromTs int64, delDateToTs int64, skipCheck bool) (string, error) {
	deletedMsg := ""
	deletedDtMsg := ""

	// If skipCheck is true and no deletedDateFrom/To is specified, just return the output for reconcile
	if skipCheck && delDateFromTs == 0 && delDateToTs == 0 {
		_log("INFO", fmt.Sprintf("Found path:%s .", path))
		// Not using _SEP for this output
		return fmt.Sprintf("%s,%s", getNowStr(), getBaseNameWithoutExt(path)), nil
	}

	// if _DEL_DATE_FROM or _DEL_DATE_TO, examine deletedDateTime
	if delDateFromTs > 0 || delDateToTs > 0 {
		contents, err := getContents(path)
		if err != nil {
			return "", errors.New(fmt.Sprintf("Could not read the contents from %s for deletion date check", path))
		}

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

			if *_REMOVE_DEL {
				updatedContents := removeLines(contents, _R_DELETED)
				err := _writeToFile(path, updatedContents)
				if err != nil {
					_log("ERROR", fmt.Sprintf("Updating path:%s failed with %s", path, err))
				} else if len(contents) == len(updatedContents) {
					_log("WARN", fmt.Sprintf("Removed 'deleted=true' from path:%s but size is same (%d => %d)", path, len(contents), len(updatedContents)))
				} else {
					deletedMsg = " (removed 'deletedMsg=true')"
				}
			}
		}
	}

	_log("INFO", fmt.Sprintf("Found path:%s%s%s", path, deletedDtMsg, deletedMsg))
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

func genOutputFromProp(path string) (string, error) {
	contents, err := getContents(path)
	if err != nil {
		return "", errors.New(fmt.Sprintf("Couldn't read %s.", path))
	}

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

func listObjects(basedir string) {
	db := openDb()
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
	db.Close()
}

// Define, set, and validate command arguments
func main() {
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
	_log("DEBUG", fmt.Sprintf("Retriving sub directories under %s", *_BASEDIR))
	subDirs := getDirs(*_BASEDIR, *_PREFIX)
	if *_LIST_DIRS {
		fmt.Printf("%v", subDirs)
		return
	}
	_log("DEBUG", fmt.Sprintf("Sub directories: %v", subDirs))

	// Printing headers if requested
	if !*_RECON_FMT && !*_NO_HEADER {
		fmt.Print("Path,LastModified,Size")
		if !*_NO_BLOB_SIZE && *_FILTER == _PROP_EXT {
			fmt.Print(",BlobSize")
		}
		if *_WITH_PROPS {
			fmt.Print(",Properties")
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
		wg.Add(1) // *
		go func(basedir string) {
			listObjects(basedir)
			_log("INFO", fmt.Sprintf("Completed %s (total: %d)", basedir, _CHECKED_N))
			<-guard
			wg.Done()
		}(s)
	}

	wg.Wait()
	println("")
	_log("INFO", fmt.Sprintf("Printed %d of %d (size:%d) in %s and sub-dir starts with %s (elapsed:%ds)", _PRINTED_N, _CHECKED_N, _TTL_SIZE, *_BASEDIR, *_PREFIX, time.Now().Unix()-_START_TIME_ts))
}
