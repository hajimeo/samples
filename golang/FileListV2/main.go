package main

import (
	"FileListV2/bs_clients"
	"FileListV2/common"
	"FileListV2/lib"
	"bufio"
	"database/sql"
	"errors"
	"flag"
	"fmt"
	h "github.com/hajimeo/samples/golang/helpers"
	"log"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

func usage() {
	fmt.Println(`
List .properties and .bytes files as *Tab* Separated Values (Path LastModified Size).
    
HOW TO and USAGE EXAMPLES:
    https://github.com/hajimeo/samples/blob/master/golang/FileListV2/README.md`)
	fmt.Println("")
}

// Populate all global variables
func setGlobals() {
	common.StartTimestamp = time.Now().Unix()

	flag.StringVar(&common.BaseDir, "b", ".", "Blob store directory or URI (eg. 's3://s3-test-bucket/s3-test-prefix/'), which location contains 'content' directory (default: '.')")
	flag.StringVar(&common.Filter4Path, "p", "", "Filter for directory / file *path* (eg 'vol-'), or S3 prefix.")
	flag.StringVar(&common.Filter4FileName, "f", "", "Filter for the file *name* (eg: '.properties' to include only this extension)")
	flag.BoolVar(&common.WithProps, "P", false, "If true, the .properties file content is included in the output")
	flag.StringVar(&common.Filter4PropsIncl, "pRx", "", "Filter for the content of the .properties files (eg: 'deleted=true')")
	flag.StringVar(&common.Filter4PropsExcl, "pRxNot", "", "Excluding Filter for .properties (eg: 'BlobStore.blob-name=.+/maven-metadata.xml.*')")
	flag.StringVar(&common.SaveToFile, "s", "", "Save the output (TSV text) into the specified path")
	flag.Int64Var(&common.TopN, "n", 0, "Return first N lines (0 = no limit). (TODO: may return more than N because of concurrency)")
	flag.IntVar(&common.Conc1, "c", 1, "Concurrent number for reading directories")
	flag.IntVar(&common.Conc2, "c2", 8, "2nd Concurrent number. Currently used when retrieving AWS Tags")
	flag.BoolVar(&common.NoHeader, "H", false, "If true, no header line")
	// Reconcile / orphaned blob finding related
	flag.StringVar(&common.Truth, "src", "", "Using database or blobstore as source [BS|DB] (if Blob ID file is provided, DB conn is not required)")
	flag.StringVar(&common.DbConnStr, "db", "", "DB connection string or path to DB connection properties file")
	flag.StringVar(&common.BlobIDFIle, "rF", "", "file path to read the blob IDs")
	flag.StringVar(&common.BsName, "bsName", "", "eg. 'default'. If provided, the SQL query will be faster. 3.47 and higher only")
	flag.StringVar(&common.RepoNames, "repos", "", "Repository names. eg. 'maven-central,raw-hosted,npm-proxy', only with -src=DB")
	flag.BoolVar(&common.RemoveDeleted, "RDel", false, "TODO: Remove 'deleted=true' from .properties. Requires -dF")
	flag.StringVar(&common.DelDateFromStr, "dDF", "", "Deleted date YYYY-MM-DD (from). Used to search deletedDateTime")
	flag.StringVar(&common.DelDateToStr, "dDT", "", "Deleted date YYYY-MM-DD (to). To exclude newly deleted assets")
	flag.StringVar(&common.ModDateFromStr, "mDF", "", "File modification date YYYY-MM-DD (from). For DB, this is used against <format>_asset_blob.blob_created")
	flag.StringVar(&common.ModDateToStr, "mDT", "", "File modification date YYYY-MM-DD (to). For DB, this is used against <format>_asset_blob.blob_created")
	// TODO: SizeFrom and SizeTo should be used for both .properties and .bytes
	flag.IntVar(&common.SizeFrom, "sF", -1, "Finding files which size is same or larger by checking actual file size")
	flag.IntVar(&common.SizeTo, "sT", -1, "Finding files which size is same or smaller by checking actual file size")
	// AWS S3 / Azure related
	flag.IntVar(&common.MaxKeys, "m", 1000, "AWS S3: Integer value for Max Keys (<= 1000)")
	flag.BoolVar(&common.WithOwner, "O", false, "AWS S3: If true, get the owner display name")
	flag.BoolVar(&common.WithTags, "T", false, "AWS S3: If true, get tags of each object")

	flag.BoolVar(&common.Debug, "X", false, "If true, verbose logging")
	flag.BoolVar(&common.Debug2, "XX", false, "If true, more verbose logging (currently only for AWS")
	//flag.BoolVar(&common.DryRun, "Dry", false, "If true, RDel does not do anything")	# No longer needed as -rF can be used
	flag.Parse()

	if common.Debug2 {
		common.Debug2 = true
		common.Debug = true
	}
	h.DEBUG = common.Debug

	h.Log("DEBUG", "Starting setGlobals for "+strings.Join(os.Args[1:], " "))
	common.BaseDir = h.AppendSlash(common.BaseDir)
	h.Log("DEBUG", "common.BaseDir with slash = "+common.BaseDir)
	common.BsType = lib.GetSchema(common.BaseDir)
	h.Log("DEBUG", "common.BsType = "+common.BsType)
	common.ContentPath = lib.GetContentPath(common.BaseDir)
	h.Log("DEBUG", "common.ContentPath = "+common.ContentPath)

	// If _FILTER_P is given, automatically populate other related variables
	if len(common.Filter4PropsIncl) > 0 || len(common.Filter4PropsExcl) > 0 {
		common.Filter4FileName = common.PROP_EXT
		//*_WITH_PROPS = true
		if len(common.Filter4PropsIncl) > 0 {
			common.RxIncl, _ = regexp.Compile(common.Filter4PropsIncl)
		}
		if len(common.Filter4PropsExcl) > 0 {
			common.RxExcl, _ = regexp.Compile(common.Filter4PropsExcl)
		}
	}

	if len(common.DbConnStr) > 0 {
		// If DB connection is provided but the source (src) is not specified, using BlobStore as the source of the truth (this works like DeadBlobsFInder)
		if len(common.Truth) == 0 {
			h.Log("WARN", "Data base connection is provided but no -src, so this DB connection won't be used.")
			common.DbConnStr = ""
		} else {
			// If it's nexus-store.properties file, read the file and get the DB connection string
			if _, err := os.Stat(common.DbConnStr); err == nil {
				common.DbConnStr = lib.GenDbConnStrFromFile(common.DbConnStr)
			}
			// If Truth is set and DB connection is provided, probably want to check only .properties files
			common.Filter4FileName = common.PROP_EXT
			//common.WithProps = false	// but probably wouldn't need to automatically output the content of .properties

			// Try connecting to the DB to get the repository name and format
			db := lib.OpenDb(common.DbConnStr)
			if db == nil {
				panic("-db is provided but cannot open the database.") // Can't output _DB_CON_STR as it may include password
			}
			initRepoFmtMap(db) // TODO: copy the function from FileList
			db.Close()
		}

	}

	if len(common.DelDateFromStr) > 0 {
		common.DelDateFromTS = h.DatetimeStrToInt(common.DelDateFromStr)
	}
	if len(common.DelDateToStr) > 0 {
		common.DelDateToTS = h.DatetimeStrToInt(common.DelDateToStr)
	}
	if len(common.ModDateFromStr) > 0 {
		common.ModDateFromTS = h.DatetimeStrToInt(common.ModDateFromStr)
	}
	if len(common.ModDateToStr) > 0 {
		common.ModDateToTS = h.DatetimeStrToInt(common.ModDateToStr)
	}

	if common.RemoveDeleted {
		common.Filter4FileName = common.PROP_EXT
		if len(common.Filter4PropsIncl) == 0 {
			common.Filter4PropsIncl = "deleted=true"
		}

		if len(common.BlobIDFIle) == 0 && (len(common.DelDateFromStr) == 0 && len(common.ModDateFromStr) == 0) {
			panic("Currently -RDel requires -dF or -mF not to un-delete too many or unexpected files.")
		}
	}

	if len(common.SaveToFile) > 0 {
		var err error
		common.SaveToPointer, err = os.OpenFile(common.SaveToFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			panic(err)
		}
	}

	// Validating some flags
	if common.NoHeader && common.WithProps {
		h.Log("WARN", "With Properties (-P), listing can be slower.")
	}
	if common.Conc1 < 1 {
		h.Log("ERROR", "-c is lower than 1.")
		os.Exit(1)
	}
}

// Initialize _REPO_TO_FMT and _ASSET_TABLES
func initRepoFmtMap(db *sql.DB) {
	h.Log("TODO", "not implemented yet")
}

func getClient() bs_clients.Client {
	// TODO: add more types
	//if common.BsType == "s3" {
	//	return &bs_clients.S3Client{}
	//}
	// Default is FileClient
	return &bs_clients.FileClient{}
}

func printHeader() {
	if !common.NoHeader {
		header := fmt.Sprintf("Path%sLastModified%sSize", common.SEP, common.SEP)
		if common.WithProps {
			header += fmt.Sprintf("%sProperties", common.SEP)
		}
		if common.WithOwner {
			header += fmt.Sprintf("%sOwner", common.SEP)
		}
		if common.WithTags {
			header += fmt.Sprintf("%sTags", common.SEP)
		}
		printOrSave(header)
	}
}

func extractBlobIdFromString(path string) string {
	//fileName := filepath.Base(path)
	//return getPathWithoutExt(fileName)
	return common.RxBlobId.FindString(path)
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

func myHashCode(s string) int32 {
	h := int32(0)
	for _, c := range s {
		h = (31 * h) + int32(c)
	}
	return h
}

func genBlobPath(blobId string, extension string) string {
	// org.sonatype.nexus.blobstore.VolumeChapterLocationStrategy#location
	// TODO: this will be changed in a newer version, with DB <format>_asset_blob.use_date_path flag
	if len(blobId) == 0 {
		h.Log("WARN", "genBlobPath got empty blobId.")
		return ""
	}
	hashInt := myHashCode(blobId)
	vol := math.Abs(math.Mod(float64(hashInt), 43)) + 1
	chap := math.Abs(math.Mod(float64(hashInt), 47)) + 1
	return filepath.Join(fmt.Sprintf("vol-%02d", int(vol)), fmt.Sprintf("chap-%02d", int(chap)), blobId) + extension
}

func genOutput(path string, bi bs_clients.BlobInfo, db *sql.DB, client bs_clients.Client) string {
	// Increment checked number counter synchronously
	atomic.AddInt64(&common.CheckedNum, 1)

	modTimestamp := bi.ModTime.Unix()
	if !isTsMSecBetweenTs(modTimestamp*1000, common.ModDateFromTS, common.ModDateToTS) {
		h.Log("DEBUG", fmt.Sprintf("path:%s modTime %d is outside of the range %d to %d", path, modTimestamp, common.ModDateFromTS, common.ModDateToTS))
		return ""
	}

	output := fmt.Sprintf("%s%s%s%s%d", path, common.SEP, bi.ModTime, common.SEP, bi.Size)
	// If .properties file is checked, depending on other flags, need to generate extra output
	if isExtraInfoNeeded(path, modTimestamp) {
		props, skipReason := extraInfo(path, db, client)
		if skipReason != nil {
			h.Log("DEBUG", fmt.Sprintf("%s: %s", path, skipReason.Error()))
			return ""
		}
		if len(props) > 0 {
			output = fmt.Sprintf("%s%s%s", output, common.SEP, props)
		}
	}

	// Updating counters before returning
	if len(output) > 0 {
		atomic.AddInt64(&common.PrintedNum, 1)
		atomic.AddInt64(&common.TotalSize, bi.Size)
	}
	return output
}

func isExtraInfoNeeded(path string, modTimestamp int64) bool {
	// If the path is not properties file, no need to open the file
	if !strings.HasSuffix(path, common.PROP_EXT) {
		return false
	}
	if common.StartTimestamp > 0 && modTimestamp > common.StartTimestamp {
		h.Log("INFO", "Skipping path:"+path+" as recently modified ("+strconv.FormatInt(modTimestamp, 10)+" > "+strconv.FormatInt(common.StartTimestamp, 10)+")")
		return false
	}
	// no need to open the properties file if no _REMOVE_DEL, no _WITH_PROPS, and no _DEL_DATE_FROM/TO
	if common.RemoveDeleted || common.WithProps || len(common.Filter4FileName) > 0 || len(common.Filter4PropsIncl) > 0 || len(common.Filter4PropsExcl) > 0 || common.DelDateFromTS > 0 || common.DelDateToTS > 0 {
		return true
	}
	return false
}

func extraInfo(path string, db *sql.DB, client bs_clients.Client) (string, error) {
	// This function returns the extra information, and also does extra checks.
	contents, err := client.ReadPath(path)
	if err != nil {
		h.Log("ERROR", "extraInfo for "+path+" returned error:"+err.Error())
		// This is not skip reason, so returning nil
		return "", nil
	}
	if len(contents) == 0 {
		h.Log("WARN", "extraInfo for "+path+" returned 0 size.") // But still can check extra
	} else {
		// removeDel requires 'contents', so executing in here.
		if common.RemoveDeleted {
			_ = removeDel(contents, path, client)
		}

		// TODO: If DB connection is given and the truth is blob store side, check if the blob ID in the path exists in the DB
		if len(common.DbConnStr) > 0 && common.Truth == "BS" {
			blobId := extractBlobIdFromString(path)
			if isBlobMissingInDB(contents, blobId, db) {
				h.Log("ERROR", "Blob ID: "+blobId+" may not exist in the DB")
			}
		}
	}

	// Finally, generate the properties output
	props, skipReason := genOutputFromProp(contents)
	if skipReason != nil {
		return props, skipReason
	}
	// If With Properties output is specified, return the contents
	if common.WithProps && len(props) > 0 {
		return props, skipReason
	}
	return "", nil
}

func genOutputFromProp(contents string) (string, error) {
	sortedContents := lib.SortToSingleLine(contents)

	// Exclude check first
	if common.RxExcl != nil && len(common.RxExcl.String()) > 0 && common.RxExcl.MatchString(sortedContents) {
		return "", errors.New(fmt.Sprintf("Matched with the exclude regex: %s. Skipping.", common.RxExcl.String()))
	}
	if common.RxIncl != nil && len(common.RxIncl.String()) > 0 {
		if common.RxIncl.MatchString(sortedContents) {
			return sortedContents, nil
		} else {
			//h.Log("DEBUG", fmt.Sprintf("Sorted content: '%s'", sortedContents))
			return "", errors.New(fmt.Sprintf("Does NOT match with the regex: %s. Skipping.", common.RxIncl.String()))
		}
	}

	// If RxExcl is empty, this excluding fileter is not a regex
	if common.RxExcl == nil && len(common.Filter4PropsExcl) > 0 && strings.Contains(sortedContents, common.Filter4PropsExcl) {
		return "", errors.New(fmt.Sprintf("Contains excluding string '%s'. Skipping.", common.Filter4PropsExcl))
	}
	// If RxIncl is empty, this fileter is not a regex
	if common.RxIncl == nil && len(common.Filter4PropsIncl) > 0 && !strings.Contains(sortedContents, common.Filter4PropsIncl) {
		return "", errors.New(fmt.Sprintf("Does not contain '%s'. Skipping.", common.Filter4PropsIncl))
	}

	// As the text didn't match with any filters, just return the contents as single line
	return sortedContents, nil
}

func shouldBeUndeleted(contents string, path string) bool {
	matches := common.RxDeletedDT.FindStringSubmatch(contents)
	if matches == nil || len(matches) == 0 {
		h.Log("WARN", fmt.Sprintf("path:%s has incorrect deletedDateTime (but un-deleting)", path))
		return true
	}
	delTimeTs, err := strconv.ParseInt(matches[1], 10, 64)
	if err != nil {
		h.Log("WARN", fmt.Sprintf("path:%s has non numeric deletedDateTime %v (but un-deleting)", path, matches))
		return true
	}

	if isTsMSecBetweenTs(delTimeTs, common.DelDateFromTS, common.DelDateToTS) {
		return true
	}
	h.Log("DEBUG", fmt.Sprintf("path:%s delTimeTs %d (msec) is NOT in the range %d (sec) to %d (sec)", path, delTimeTs, common.DelDateFromTS, common.DelDateToTS))
	return false
}

func removeDel(contents string, path string, client bs_clients.Client) bool {
	if !shouldBeUndeleted(contents, path) {
		return false
	}

	updatedContents := removeLines(contents, common.RxDeleted)
	err := client.WriteToPath(path, updatedContents)
	if err != nil {
		h.Log("ERROR", fmt.Sprintf("Removing 'deleted=true' for path:%s failed with %s", path, err))
		return false
	}
	if len(contents) == len(updatedContents) {
		h.Log("WARN", fmt.Sprintf("Removed 'deleted=true' from path:%s but size is same (%d => %d)", path, len(contents), len(updatedContents)))
		return false
	}
	return true
}

// one line but for unit testing
func removeLines(contents string, rex *regexp.Regexp) string {
	return rex.ReplaceAllString(contents, "")
}

func isBlobMissingInDB(contents string, blobId string, db *sql.DB) bool {
	// TODO: implement this
	return false
}

func printLine(path interface{}, blobInfo bs_clients.BlobInfo, db *sql.DB, client bs_clients.Client) {
	output := genOutput(path.(string), blobInfo, db, client)
	printOrSave(output)
}

func printOrSave(line string) (n int, err error) {
	// At this moment, excluding empty line
	if len(line) == 0 {
		return
	}
	if len(common.SaveToFile) > 0 {
		return fmt.Fprintln(common.SaveToPointer, line)
	}
	return fmt.Println(line)
}

func listObjects(dir string, db *sql.DB, client bs_clients.Client) {
	startMs := time.Now().UnixMilli()
	subTtl := client.ListObjects(dir, common.Filter4FileName, db, printLine)
	// Always log this elapsed time by using 0 thresholdMs
	h.Elapsed(startMs, fmt.Sprintf("Checked %s for %d files (current total: %d)", dir, subTtl, common.CheckedNum), 0)
}

func printObjectByBlobId(blobId string, db *sql.DB, client bs_clients.Client) {
	if len(blobId) == 0 {
		h.Log("DEBUG", fmt.Sprintf("Empty blobId"))
		return
	}
	path := h.AppendSlash(common.ContentPath) + genBlobPath(blobId, common.PROP_EXT)
	h.Log("DEBUG", path)
	// TODO: populate blobInfo with client
	var blobInfo bs_clients.BlobInfo
	printLine(path, blobInfo, db, client)
}

func runParallel(chunks [][]string, client bs_clients.Client, f func(string, *sql.DB, bs_clients.Client), conc int) {
	startMs := time.Now().UnixMilli()

	wg := sync.WaitGroup{}
	guard := make(chan struct{}, conc)
	for _, chunk := range chunks {
		guard <- struct{}{}
		wg.Add(1)
		go func(items []string, client bs_clients.Client) {
			defer wg.Done()
			// Open a DB connection per chunk
			var db *sql.DB
			if len(common.DbConnStr) > 0 {
				db = lib.OpenDb(common.DbConnStr)
				defer db.Close()
			}
			for _, item := range items {
				f(item, db, client)
			}
			<-guard
		}(chunk, client)
	}
	wg.Wait()

	// Always log this elapsed time by using 0 thresholdMs
	h.Elapsed(startMs, fmt.Sprintf("Completed. Listed: %d (checked: %d), Size: %d bytes", common.PrintedNum, common.CheckedNum, common.TotalSize), 0)
}

func main() {
	if len(os.Args) == 1 || os.Args[1] == "-h" || os.Args[1] == "--help" {
		usage()
		setGlobals() // to show the flags
		flag.PrintDefaults()
		os.Exit(0)
	}

	// Configure logging and common variables
	log.SetFlags(log.Lmicroseconds)
	log.SetPrefix(time.Now().Format("2006-01-02 15:04:05"))
	setGlobals()
	printHeader()
	client := getClient()

	// If Truth is empty, just list the files
	if common.Truth == "" {
		// If the list of Blob IDs are provided, use it
		if len(common.BlobIDFIle) > 0 {
			f := lib.OpenStdInOrFIle(common.BlobIDFIle)
			defer f.Close()

			scanner := bufio.NewScanner(f)
			var blobIds []string
			for scanner.Scan() {
				blobId := extractBlobIdFromString(scanner.Text())
				blobIds = append(blobIds, blobId)
			}

			chunks := h.Chunk(blobIds, common.Conc1)
			runParallel(chunks, client, printObjectByBlobId, common.Conc1)
			return
		}

		// If the Blob ID file is not provided, run per directory
		subDirs, err := client.GetDirs(common.ContentPath, common.Filter4Path, common.MaxDepth)
		if err != nil {
			h.Log("ERROR", "Failed to list directories in "+common.ContentPath+" with filter: "+common.Filter4Path)
			panic(err)
		}
		chunks := h.Chunk(subDirs, 1) // To check per chap-XX
		runParallel(chunks, client, listObjects, common.Conc1)
		return
	}
	// TODO: the concurrency (-c) can be 100 or more
	// TODO: should be search-able by size

	// If Truth is DB, find unnecessary blobs from the Blob store (orphaned blobs)
	// Also, if the Blob ID file is provided, find the orphaned blobs by using it (no need to connect to DB)

	// If Truth is BS, find unnecessary DB records from the database (dead blobs)
	// Also, if the Blob ID file is provided, find the dead blobs by using it (no need to connect to DB)
}
