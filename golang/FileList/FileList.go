/*
#go mod init github.com/hajimeo/samples/golang/FileList
#go mod tidy
go build -o ../../misc/file-list_$(uname) FileList.go && env GOOS=linux GOARCH=amd64 go build -o ../../misc/file-list_Linux FileList.go

$HOME/IdeaProjects/samples/misc/file-list_$(uname) -b <workingDirectory>/blobs/default/content -p "vol-" -c1 10
*/

package main

import (
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
List .properties and .bytes files as CSV (Path,LastModified,Size).
    
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

func _setGlobals() {
	_BASEDIR = flag.String("b", ".", "Base directory (default: '.')")
	_PREFIX = flag.String("p", "", "Prefix of sub directories (eg: 'vol-')")
	_WITH_PROPS = flag.Bool("P", false, "If true, read and output the .properties files")
	_FILTER = flag.String("f", "", "Filter file paths (eg: '.properties')")
	_FILTER_P = flag.String("fP", "", "Filter .properties contents (eg: 'deleted=true')")
	_DB_CON_STR = flag.String("db", "", "DB connection string")
	_USE_REGEX = flag.Bool("R", false, "If true, .properties content is *sorted* and _FILTER_P string is treated as regex")
	_RECON_FMT = flag.Bool("RF", false, "Output for the Reconcile task (any_string,blob_ref). Requires -fP and ignores -P")
	_REMOVE_DEL = flag.Bool("RDel", false, "Remove 'deleted=true' from .properties. Requires -RF and -dF") // TODO: also think about restore plan
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
		*_FILTER = ".properties"
		//*_WITH_PROPS = true
		if *_USE_REGEX {
			_R, _ = regexp.Compile(*_FILTER_P)
		}
	}
	if len(*_DB_CON_STR) > 0 {
		*_FILTER = ".properties"
		*_WITH_PROPS = false
		db := openDb()
		rows := queryDb("select name, REGEXP_REPLACE(recipe_name, '-.+', '') as fmt from repository", db)
		_REPO_TO_FMT = make(map[string]string)
		for rows.Next() {
			var name string
			var fmt string
			err := rows.Scan(&name, &fmt)
			if err != nil {
				panic(err)
			}
			_REPO_TO_FMT[name] = fmt
		}
		rows.Close()
		db.Close()
		_log("DEBUG", fmt.Sprintf("_REPO_TO_FMT = %v", _REPO_TO_FMT))
	}
	_START_TIME_ts = time.Now().Unix()
	_R_DEL_DT, _ = regexp.Compile("[^#]?deletedDateTime=([0-9]+)")
	_R_DELETED, _ = regexp.Compile("deleted=true")
	_R_REPO_NAME, _ = regexp.Compile("[^#]?@Bucket.repo-name=(.+)")
	_R_BLOB_NAME, _ = regexp.Compile("[^#]?@BlobStore.blob-name=(.+)")
	if *_RECON_FMT {
		*_FILTER = ".properties"
		if len(*_DEL_DATE_FROM) > 0 {
			tmpTimeFrom, err := time.Parse("2006-01-02", *_DEL_DATE_FROM)
			if err != nil {
				_log("ERROR", fmt.Sprintf("_DEL_DATE_FROM:%s is incorrect", *_DEL_DATE_FROM))
				os.Exit(1)
			}
			_DEL_DATE_FROM_ts = tmpTimeFrom.Unix()
		}
		if len(*_DEL_DATE_TO) > 0 {
			tmpTimeTo, err := time.Parse("2006-01-02", *_DEL_DATE_TO)
			if err != nil {
				_log("ERROR", fmt.Sprintf("_DEL_DATE_TO:%s is incorrect", *_DEL_DATE_TO))
				os.Exit(1)
			}
			_DEL_DATE_TO_ts = tmpTimeTo.Unix()
		}
	}
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

func printLine(path string, fInfo os.FileInfo, db *sql.DB) bool {
	//_log("DEBUG", fmt.Sprintf("printLine-ing for path:%s", path))
	modTime := fInfo.ModTime()
	modTimeTs := modTime.Unix()
	output := ""
	props := ""
	errNo := 0
	if !*_RECON_FMT {
		output = fmt.Sprintf("\"%s\",\"%s\",%d", path, modTime, fInfo.Size())
	}

	if strings.HasSuffix(path, ".properties") && (*_WITH_PROPS || len(*_FILTER_P) > 0 || *_RECON_FMT || len(*_DB_CON_STR) > 0) {
		if *_RECON_FMT {
			output, errNo = genOutputForReconcile(path, modTimeTs)
			_log("DEBUG", fmt.Sprintf("genOutputForReconcile returned output length:%d for path:%s modTimeTs:%d (%d)", len(output), path, modTimeTs, errNo))
		} else if len(*_DB_CON_STR) > 0 {
			if !isBlobIdMissingInDB(path, db) {
				output = ""
			}
		} else {
			props, errNo = genOutputFromProp(path)
			_log("DEBUG", fmt.Sprintf("genOutputFromProp returned props length:%d for path:%s (%d)", len(props), path, errNo))
			if errNo > 0 {
				output = ""
			} else if len(props) > 0 && *_WITH_PROPS {
				output = fmt.Sprintf("%s,\"%s\"", output, props)
			}
		}
	}

	atomic.AddInt64(&_CHECKED_N, 1)
	if len(output) > 0 {
		atomic.AddInt64(&_PRINTED_N, 1)
		atomic.AddInt64(&_TTL_SIZE, fInfo.Size())
		fmt.Println(output)
		return true
	}
	return false
}

// as per google, this would be faster than using TrimSuffix
func getBaseName(path string) string {
	fileName := filepath.Base(path)
	return fileName[:len(fileName)-len(filepath.Ext(fileName))]
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
	if len(*_DB_CON_STR) == 0 {
		return nil
	}
	rows, err := db.Query(query)
	if err != nil {
		panic(err.Error())
	}
	return rows
}

func genBlobIdCheckingQuery(path string) (string, int) {
	// Getting the blobName of asset, otherwise, the checking query will be slower.
	contents, err := getContents(path)
	if err != nil {
		_log("ERROR", "No contents from "+path)
		// if no content, assuming missing
		return "", 1
	}
	m := _R_REPO_NAME.FindStringSubmatch(contents)
	if len(m) < 2 {
		_log("WARN", "No _R_REPO_NAME match for "+path)
		// At this moment, if no blobName, assuming NOT missing...
		return "", 0
	}
	repoName := m[1]
	m = _R_BLOB_NAME.FindStringSubmatch(contents)
	if len(m) < 2 {
		_log("WARN", "No _R_BLOB_NAME match for "+path)
		// At this moment, if no blobName, assuming NOT missing...
		return "", 0
	}
	blobName := m[1]
	if !strings.HasPrefix(blobName, "/") {
		blobName = "/" + blobName
	}
	// TODO: Should be LEFT JOIN but the query will be slower...
	repoFmt := _REPO_TO_FMT[repoName]
	query := "SELECT ab.asset_blob_id FROM " + repoFmt + "_asset_blob ab INNER JOIN " + repoFmt + "_asset a on ab.asset_blob_id = a.asset_blob_id WHERE a.path = '" + blobName + "' and ab.blob_ref like '%:" + getBaseName(path) + "@%'"
	_log("DEBUG", query)
	return query, -1
}

func isBlobIdMissingInDB(path string, db *sql.DB) bool {
	// Ref: https://go.dev/doc/database/querying
	query, errNo := genBlobIdCheckingQuery(path)
	if errNo != -1 {
		return errNo == 1
	}
	rows := queryDb(query, db)
	if rows == nil {
		// For test
		_log("WARN", "rows is nil for "+path+". Ignoring.\nquery: "+query)
		return false
	}
	noRows := true
	for rows.Next() {
		noRows = false
		break
	}
	rows.Close()
	return noRows
}

func genOutputForReconcile(path string, modTimeMs int64) (string, int) {
	contents := ""
	var err error
	// NOTE: Even not accurate, to make this function faster, currently checking modTimeMs against _DEL_DATE_FROM_ts
	if _DEL_DATE_FROM_ts > 0 && modTimeMs < _DEL_DATE_FROM_ts {
		return "", 11
	}
	// NOT checking against _DEL_DATE_TO_ts as file might be touched accidentally (I may change my mind if slow)
	if _START_TIME_ts > 0 && modTimeMs > _START_TIME_ts {
		return "", 12
	}
	// if _DEL_DATE_FROM or DEL_DATE_TO is set, check deletedDateTime=
	if _DEL_DATE_FROM_ts > 0 || _DEL_DATE_TO_ts > 0 {
		contents, err = getContents(path)
		if err != nil {
			return "", 13
		}
		// capture group
		m := _R_DEL_DT.FindStringSubmatch(contents)
		if len(m) < 2 {
			_log("DEBUG", fmt.Sprintf("path:%s dos not match with %s (%s)", path, _R_DEL_DT.String(), m))
			return "", 14
		}
		deletedTS, _ := strconv.ParseInt(m[1], 10, 64)
		if isTimestampBetween(deletedTS) {
			_log("INFO", fmt.Sprintf("path:%s deletedDateTime=%d is between _DEL_DATE_FROM_ts:%d and _DEL_DATE_TO_ts:%d (%d)", path, deletedTS, _DEL_DATE_FROM_ts, _DEL_DATE_TO_ts, _START_TIME_ts))
			if _DEL_DATE_FROM_ts > 0 && *_REMOVE_DEL {
				// TODO: remove 'deleted=true'
				updatedContents := removeLines(contents, _R_DELETED)
				err := _writeToFile(path, updatedContents)
				if err != nil {
					_log("ERROR", fmt.Sprintf("Updating path:%s failed with %s", path, err))
				} else {
					_log("WARN", fmt.Sprintf("Removed 'deleted=true' from path:%s (%d => %d)", path, len(contents), len(updatedContents)))
				}
			}
			return fmt.Sprintf("%s,%s", getNowStr(), getBaseName(path)), 0
		}
		return "", 15
	}

	return fmt.Sprintf("%s,\"%s\"", getNowStr(), getBaseName(path)), 0
}

// one line but for unit testing
func removeLines(contents string, rex *regexp.Regexp) string {
	return rex.ReplaceAllString(contents, "")
}

func isTimestampBetween(tMsec int64) bool {
	if _DEL_DATE_FROM_ts > 0 && (_DEL_DATE_FROM_ts*1000) > tMsec {
		return false
	}
	if _DEL_DATE_TO_ts > 0 && (_DEL_DATE_TO_ts*1000) < tMsec {
		return false
	}
	if _DEL_DATE_TO_ts == 0 && (_START_TIME_ts*1000) < tMsec {
		_log("DEBUG", fmt.Sprintf("deletedDateTime=%d is greater than the this script's start time:%d", tMsec, _START_TIME_ts))
		return false
	}
	return true
}

func genOutputFromProp(path string) (string, int) {
	contents, err := getContents(path)
	if err != nil {
		return "", 21
	}

	// If no _FILTER_P, just returns the content as one line
	if len(*_FILTER_P) == 0 {
		// If no _FILETER2, just return the contents as single line. Should also escape '"'?
		return strings.ReplaceAll(contents, "\n", ","), 0
	}

	// If asked to use regex, return properties lines only if matches.
	if *_USE_REGEX {
		if _R == nil || len(_R.String()) == 0 { //
			//_log("DEBUG", fmt.Sprintf("_USE_REGEX is specified by no regular expression (_R)"))
			return "", 22
		}
		// To allow to use simpler regex, sorting line and converting to single line firt
		lines := strings.Split(contents, "\n")
		sort.Strings(lines)
		contents = strings.Join(lines, ",")
		if _R.MatchString(contents) {
			return contents, 0
		}
		_log("DEBUG", fmt.Sprintf("Properties of %s does not contain %s (with Regex). Not outputting entire line...", path, *_FILTER_P))
		return "", 23
	}

	// If not regex (eg: 'deleted=true')
	if strings.Contains(contents, *_FILTER_P) {
		//_log("DEBUG", fmt.Sprintf("path:%s contains %s", path, *_FILTER_P))
		return strings.ReplaceAll(contents, "\n", ","), 0
	}

	_log("DEBUG", fmt.Sprintf("Properties of %s does not contain %s. Not outputting entire line...", path, *_FILTER_P))
	return "", 24
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
			_log("DEBUG", fmt.Sprintf("Listing objects for %s ...", basedir))
			listObjects(basedir)
			<-guard
			wg.Done()
		}(s)
	}

	wg.Wait()
	println("")
	_log("INFO", fmt.Sprintf("Printed %d of %d (size:%d) in %s with prefix:%s", _PRINTED_N, _CHECKED_N, _TTL_SIZE, *_BASEDIR, *_PREFIX))
}
