package main

import (
	"FileListV2/bs_clients"
	"FileListV2/common"
	"FileListV2/lib"
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
	"slices"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

var Client bs_clients.Client

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

	// TODO: 'b' should accept the comma separated values for supporting the group blob store
	flag.StringVar(&common.BaseDir, "b", "", "Blob store directory or URI (eg. 's3://s3-test-bucket/s3-test-prefix/'), which location contains 'content' directory (default: '.')")
	flag.BoolVar(&common.DateBsLayout, "DateBS", false, "Created Date based Blob Store layout")
	flag.StringVar(&common.Filter4Path, "p", "", "Regular Expression for directory *path* (eg 'vol-'), or S3 prefix.")
	flag.StringVar(&common.Filter4FileName, "f", "", "Regular Expression for the file *name* (eg: '\\.properties' to include only this extension)")
	flag.BoolVar(&common.WithProps, "P", false, "If true, the .properties file content is included in the output")
	flag.StringVar(&common.Filter4PropsIncl, "pRx", "", "Regular Expression for the content of the .properties files (eg: 'deleted=true')")
	flag.StringVar(&common.Filter4PropsExcl, "pRxNot", "", "Excluding Regular Expression for .properties (eg: 'BlobStore.blob-name=.+/maven-metadata.xml.*')")
	flag.StringVar(&common.SaveToFile, "s", "", "Save the output (TSV text) into the specified path")
	flag.Int64Var(&common.TopN, "n", 0, "Return first N lines (0 = no limit). Can't be less than '-c'")
	flag.IntVar(&common.Conc1, "c", 1, "Concurrent number for reading directories")
	flag.IntVar(&common.Conc2, "c2", 8, "2nd Concurrent number. Currently used when retrieving object from AWS S3")
	flag.BoolVar(&common.NoHeader, "H", false, "If true, no header line")
	// Reconcile / orphaned blob finding related
	flag.StringVar(&common.Truth, "src", "", "Using database or blobstore as source [BS|DB|ALL] (if Blob ID file is provided, DB conn is not required)")
	flag.StringVar(&common.DbConnStr, "db", "", "DB connection string or path to DB connection properties file")
	flag.StringVar(&common.BlobIDFIle, "rF", "", "file path to read the blob IDs")
	flag.StringVar(&common.BsName, "bsName", "", "eg. 'default'. If provided, the SQL query will be faster")
	flag.StringVar(&common.Query, "query", "", "SQL statement (SELECT query only) to filter the data from the DB")
	flag.BoolVar(&common.RemoveDeleted, "RDel", false, "TODO: Remove 'deleted=true' from .properties. Requires -dF")
	flag.StringVar(&common.WriteIntoStr, "wStr", "", "For testing. Write the string into the file (eg. deleted=true) NOTE: not updating S3 tag")
	flag.StringVar(&common.DelDateFromStr, "dDF", "", "Deleted date YYYY-MM-DD (from). Used to search deletedDateTime")
	flag.StringVar(&common.DelDateToStr, "dDT", "", "Deleted date YYYY-MM-DD (to). To exclude newly deleted assets")
	flag.StringVar(&common.ModDateFromStr, "mDF", "", "File modification date YYYY-MM-DD (from)")
	flag.StringVar(&common.ModDateToStr, "mDT", "", "File modification date YYYY-MM-DD (to)")

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
	h.Log("DEBUG", "common.BaseDir = "+common.BaseDir)
	common.BaseDir = h.AppendSlash(common.BaseDir)
	h.Log("DEBUG", "common.BaseDir with slash = "+common.BaseDir)

	common.BsType = lib.GetSchema(common.BaseDir)
	h.Log("DEBUG", "common.BsType = "+common.BsType)
	// if the BaseDir starts with "s3://", get hostname as the bucket name, and the rest as the prefix
	common.Container, common.Prefix = lib.GetContainerAndPrefix(common.BaseDir)
	h.Log("DEBUG", "common.Container = "+common.Container)
	h.Log("DEBUG", "common.Prefix = "+common.Prefix)
	common.ContentPath = lib.GetContentPath(common.BaseDir)
	h.Log("DEBUG", "common.ContentPath = "+common.ContentPath)

	if common.Conc1 < 1 {
		h.Log("ERROR", "-c is lower than 1.")
		os.Exit(1)
	}

	if len(common.DbConnStr) > 0 {
		// If it's nexus-store.properties file, read the file and get the DB connection string
		if _, err := os.Stat(common.DbConnStr); err == nil {
			common.DbConnStr = lib.GenDbConnStrFromFile(common.DbConnStr)
		}
		if len(common.Filter4FileName) == 0 {
			// If Truth is set and DB connection is provided, probably want to check only .properties files
			common.Filter4FileName = `\.` + common.PROPERTIES + `$`
			h.Log("INFO", "Set '-f' to '"+common.Filter4FileName+"' as DB connection is provided.")
			//common.WithProps = false	// but probably wouldn't need to automatically output the content of .properties
		}

		// Try connecting to the DB to get the repository name and format
		common.DB = lib.OpenDb(common.DbConnStr)
		if common.Conc1 > 0 {
			common.DB.SetMaxOpenConns(common.Conc1 + 1)
			common.DB.SetMaxIdleConns(common.Conc1 + 1)
		}
		if common.DB == nil {
			panic("-db is provided but cannot open the database.") // Can't output _DB_CON_STR as it may include password
		}
		initRepoFmtMap(common.DB) // TODO: copy the function from FileList
	}

	if len(common.Query) > 0 {
		if !common.RxSelect.MatchString(common.Query) {
			panic("Query should start with 'SELECT'")
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
		// If RDel, probably want to check .properties files only
		common.Filter4FileName = `\.` + common.PROPERTIES + `$`
		if len(common.Filter4PropsIncl) == 0 {
			common.Filter4PropsIncl = "deleted=true"
		}

		if len(common.BlobIDFIle) == 0 && (len(common.DelDateFromStr) == 0 && len(common.ModDateFromStr) == 0) {
			panic("Currently -RDel requires -dF or -mF not to un-delete too many or unexpected files.")
		}
	}

	// If _FILTER_P is given, automatically populate other related variables
	if len(common.Filter4PropsIncl) > 0 || len(common.Filter4PropsExcl) > 0 {
		if len(common.Filter4FileName) == 0 {
			// TODO: currently this script can not include .bytes when the .properties is included or excluded
			common.Filter4FileName = `\.` + common.PROPERTIES + `$`
		}

		if len(common.Filter4PropsIncl) > 0 {
			common.RxIncl, _ = regexp.Compile(common.Filter4PropsIncl)
		}
		if len(common.Filter4PropsExcl) > 0 {
			common.RxExcl, _ = regexp.Compile(common.Filter4PropsExcl)
		}
	}

	// This property is automatically changed in the above, so RxFilter4FileName needs to be set in the end
	if len(common.Filter4FileName) > 0 {
		common.RxFilter4FileName, _ = regexp.Compile(common.Filter4FileName)
	}

	// If Truth is not set but BlobIDFIle is given, needs to set Truth
	if len(common.Truth) == 0 && len(common.BlobIDFIle) > 0 {
		if len(common.BaseDir) > 0 {
			h.Log("INFO", "-src is missing. Setting 'DB'")
			common.Truth = "DB"
		} else if len(common.DbConnStr) > 0 {
			h.Log("INFO", "-src is missing. Setting 'BS'")
			common.Truth = "BS"
		}
	}

	if common.Truth == "BS" || common.Truth == "DB" {
		if len(common.BlobIDFIle) == 0 && (len(common.DbConnStr) == 0 || len(common.BaseDir) == 0) {
			panic("-src without -rF requires -b and -db")
		}

		// If BlobIDFIle is given, DB connection or BaseDir is required
		if len(common.DbConnStr) == 0 && len(common.BaseDir) == 0 {
			panic("-src with -rF requires -b or -db")
		}
		if len(common.BlobIDFIle) > 0 {
			if len(common.DbConnStr) > 0 && len(common.BaseDir) > 0 {
				h.Log("DEBUG", "-rF, -b, and -db are given, so using Blob IDs in -rF as if BS output.")
				common.BlobIDFIleType = "BS"
			} else if len(common.DbConnStr) > 0 && len(common.BaseDir) == 0 {
				h.Log("DEBUG", "-rF and -db are given, so using Blob IDs in -rF as if BS output.")
				common.BlobIDFIleType = "BS"
			} else if len(common.DbConnStr) == 0 && len(common.BaseDir) > 0 {
				h.Log("DEBUG", "-rF and -b are given, so using Blob IDs in -rF as if DB output.")
				common.BlobIDFIleType = "DB"
			}
		}
	}

	// Validating some flags
	if common.NoHeader && common.WithProps {
		h.Log("WARN", "With Properties (-P), listing can be slower.")
	}

	if len(common.SaveToFile) > 0 {
		var err error
		common.SaveToPointer, err = os.OpenFile(common.SaveToFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			panic(err)
		}
	}
}

// Initialize _REPO_TO_FMT and _ASSET_TABLES
func initRepoFmtMap(db *sql.DB) {
	// Not sure if needed, but resetting the map and slice
	common.Repo2Fmt = make(map[string]string)
	common.AssetTables = make([]string, 0)

	query := "SELECT name, REGEXP_REPLACE(recipe_name, '-.+', '') AS fmt FROM repository"
	if len(common.BsName) > 0 {
		query += " WHERE attributes->'storage'->>'blobStoreName' = '" + common.BsName + "'"
	}
	rows := lib.Query(query, db, 50)
	if rows == nil { // For unit tests
		h.Log("DEBUG", fmt.Sprintf("No result with %s", query))
		return
	}
	defer rows.Close()
	for rows.Next() {
		var name string
		var format string
		err := rows.Scan(&name, &format)
		if err != nil {
			panic(err)
		}
		common.Repo2Fmt[name] = format
		if !slices.Contains(common.AssetTables, format+"_asset") {
			common.AssetTables = append(common.AssetTables, format+"_asset")
		}
	}
	h.Log("DEBUG", fmt.Sprintf("Repo2Fmt = %v", common.Repo2Fmt))
	logLevel := "DEBUG"
	if len(common.BsName) > 0 {
		logLevel = "INFO"
	}
	h.Log(logLevel, fmt.Sprintf("AssetTables = %v", common.AssetTables))
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

func extractBlobIdFromString(line string) string {
	//fileName := filepath.Base(line)
	//return getPathWithoutExt(fileName)
	return common.RxBlobId.FindString(line)
}

func genBlobPath(blobId string, extension string) string {
	// org.sonatype.nexus.blobstore.VolumeChapterLocationStrategy#location
	// TODO: this will be changed in a newer version, with DB <format>_asset_blob.use_date_path flag
	if len(blobId) == 0 {
		h.Log("WARN", "genBlobPath got empty blobId.")
		return ""
	}
	hashInt := lib.HashCode(blobId)
	vol := math.Abs(math.Mod(float64(hashInt), 43)) + 1
	chap := math.Abs(math.Mod(float64(hashInt), 47)) + 1
	return filepath.Join(fmt.Sprintf("vol-%02d", int(vol)), fmt.Sprintf("chap-%02d", int(chap)), blobId) + extension
}

func genOutput(path string, bi bs_clients.BlobInfo, db *sql.DB) string {
	// Increment checked number counter synchronously
	atomic.AddInt64(&common.CheckedNum, 1)
	if len(common.Filter4FileName) > 0 && !common.RxFilter4FileName.MatchString(path) {
		h.Log("DEBUG", fmt.Sprintf("path:%s does not match with the filter %s", path, common.RxFilter4FileName.String()))
		return ""
	}

	modTimestamp := bi.ModTime.Unix()
	if !lib.IsTsMSecBetweenTs(modTimestamp*1000, common.ModDateFromTS, common.ModDateToTS) {
		h.Log("DEBUG", fmt.Sprintf("path:%s modTime %d is outside of the range %d to %d", path, modTimestamp, common.ModDateFromTS, common.ModDateToTS))
		return ""
	}

	var props string
	var skipReason error
	output := fmt.Sprintf("%s%s%s%s%d", path, common.SEP, bi.ModTime, common.SEP, bi.Size)
	// If .properties file is checked, depending on other flags, need to generate extra output
	if isExtraInfoNeeded(path, modTimestamp) {
		//h.Log("DEBUG", fmt.Sprintf("Extra info from properties is needed for '%s'", path))
		props, skipReason = extraInfo(path)
		if skipReason != nil {
			h.Log("DEBUG", fmt.Sprintf("%s: %s", path, skipReason.Error()))
			return ""
		}
		// Append to the output only when WithProps is true even if the props is empty
		if common.WithProps {
			output = fmt.Sprintf("%s%s%s", output, common.SEP, props)
		} else if len(props) == 0 {
			h.Log("WARN", fmt.Sprintf("No property contents for %s", path))
		}
		//} else {
		//	h.Log("DEBUG", fmt.Sprintf("Extra info from properties is NOT needed for '%s'", path))
	}

	if common.Truth == "BS" {
		// If DB connection is given and the truth is blob store, check if the blob ID in the path exists in the DB
		if len(common.DbConnStr) > 0 {
			blobId := extractBlobIdFromString(path)
			// If props is empty, the below may use expensive query
			if isOrphanedBlob(props, blobId, db) {
				h.Log("ERROR", "Blob ID: "+blobId+" may not exist in the DB")
			} else {
				h.Log("DEBUG", "Blob ID: "+blobId+" exists in the DB. Not including in the output.")
				output = ""
			}
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
	if !strings.HasSuffix(path, common.PROP_EXT) {
		// If the path is not properties file, no need to open the file
		//h.Log("DEBUG", "Skipping path:"+path+" as not a properties file")
		return false
	}
	if common.StartTimestamp > 0 && modTimestamp > common.StartTimestamp {
		// If the file is very new, currently skipping
		h.Log("INFO", "Skipping path:"+path+" as recently modified ("+strconv.FormatInt(modTimestamp, 10)+" > "+strconv.FormatInt(common.StartTimestamp, 10)+")")
		return false
	}
	if common.RemoveDeleted || common.WithProps || len(common.WriteIntoStr) > 0 || len(common.Filter4FileName) > 0 || len(common.Filter4PropsIncl) > 0 || len(common.Filter4PropsExcl) > 0 || common.DelDateFromTS > 0 || common.DelDateToTS > 0 {
		// These common properties require to read the properties file
		return true
	}
	if common.Truth == "BS" {
		if common.BlobIDFIle == "" {
			// Returning true as the query used for checking orphaned blobs can be expensive without reading the properties
			return true
		}
		// If BlobIDFile is given, currently not reading unless -P or other options are given
	} else if common.Truth == "DB" {
		// Currently if Truth is DB, not reading the properties as not verifying the properties content
		// and even if BlobIDFIle is given, still no need to read the properties due to the same reason.
		return false // can remove this line but just for human readability
	}
	return false
}

func extraInfo(path string) (string, error) {
	// This function returns the extra information, and also does extra checks.
	// Returns the error only when RxIncl or RxExcl filtered the contents
	contents, err := Client.ReadPath(path)
	if err != nil {
		h.Log("ERROR", "extraInfo for "+path+" returned error:"+err.Error())
		// This is not skip reason, so returning nil
		return "", nil
	}
	if len(contents) == 0 {
		h.Log("WARN", "extraInfo for "+path+" returned 0 size.") // But still can check extra
	} else {
		// removeDel requires 'contents' (to avoid re-reading same file), so executing in the extraInfo.
		if common.RemoveDeleted {
			_ = removeDel(contents, path)
		}
	}

	if len(common.WriteIntoStr) > 0 {
		_ = appendStr(common.WriteIntoStr, contents, path)
	}

	// Finally, generate the properties output
	//h.Log("DEBUG", fmt.Sprintf("Sorting content for the path '%s'", path))
	return genOutputFromContents(contents)
}

func genOutputFromContents(contents string) (string, error) {
	// Returns error only when RxIncl or RxExcl filtered the contents
	sortedContents := lib.SortToSingleLine(contents)

	// Exclude check first
	if common.RxExcl != nil && common.RxExcl.MatchString(sortedContents) {
		return "", errors.New(fmt.Sprintf("Matched with the exclude regex: %s. Skipping.", common.RxExcl.String()))
	}
	if common.RxIncl != nil && len(common.RxIncl.String()) > 0 {
		if common.RxIncl.MatchString(sortedContents) {
			return sortedContents, nil
		} else {
			//h.Log("DEBUG", fmt.Sprintf("Sorted content did not match with '%s'", common.RxIncl.String()))
			return "", errors.New(fmt.Sprintf("Does NOT match with the regex: %s. Skipping.", common.RxIncl.String()))
		}
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

	if lib.IsTsMSecBetweenTs(delTimeTs, common.DelDateFromTS, common.DelDateToTS) {
		return true
	}
	h.Log("DEBUG", fmt.Sprintf("path:%s delTimeTs %d (msec) is NOT in the range %d (sec) to %d (sec)", path, delTimeTs, common.DelDateFromTS, common.DelDateToTS))
	return false
}

func removeDel(contents string, path string) bool {
	if !shouldBeUndeleted(contents, path) {
		return false
	}

	err := Client.RemoveDeleted(path, contents)
	if err != nil {
		h.Log("ERROR", fmt.Sprintf("Removing 'deleted=true' for path:%s failed with %s", path, err))
		return false
	}
	return true
}

func appendStr(appending string, contents string, path string) bool {
	var updatedContents string
	if strings.HasSuffix(contents, "\n") {
		updatedContents = fmt.Sprintf("%s%s\n", contents, appending)
	} else {
		updatedContents = fmt.Sprintf("%s\n%s\n", contents, appending)
	}
	err := Client.WriteToPath(path, updatedContents)
	if err != nil {
		h.Log("ERROR", fmt.Sprintf("Apeending '%s' into path:%s failed with %s", appending, path, err))
		return false
	}
	if len(contents) == len(updatedContents) {
		h.Log("WARN", fmt.Sprintf("Appended '%s' into path:%s but size is same (%d => %d)", appending, path, len(contents), len(updatedContents)))
		return false
	}
	return true
}

func printLineFromPath(path interface{}, blobInfo bs_clients.BlobInfo, db *sql.DB) {
	//h.Log("DEBUG", fmt.Sprintf("Generating the output for '%s'", path))
	output := genOutput(path.(string), blobInfo, db)
	printOrSave(output)
}

func printOrSave(line string) {
	// At this moment, excluding empty line
	if len(line) == 0 {
		return
	}
	if len(common.SaveToFile) > 0 {
		_, _ = fmt.Fprintln(common.SaveToPointer, line)
		return
	}
	_, _ = fmt.Println(line)
}

func listObjects(dir string, db *sql.DB) {
	startMs := time.Now().UnixMilli()
	//h.Log("INFO", fmt.Sprintf("Listing objects from %s", dir))
	subTtl := Client.ListObjects(dir, db, printLineFromPath)
	// Always log this elapsed time by using 0 thresholdMs
	h.Elapsed(startMs, fmt.Sprintf("Checked %s for %d files (current total: %d)", dir, subTtl, common.CheckedNum), 0)
}

func checkBlobIdDetailFromDB(maybeBlobId string) interface{} {
	blobId := extractBlobIdFromString(maybeBlobId)
	if len(blobId) == 0 {
		h.Log("DEBUG", fmt.Sprintf("Empty blobId in '%s'", maybeBlobId))
		return nil
	}

	// empty format returns all repository names in common.Repo2Fmt. The common.Repo2Fmt has all the repository names for the blob store.
	formatRepoNames := getFormats(getRepNames(""))
	foundInDB := false
	for format, repoNames := range formatRepoNames {
		output := getAssetWithBlobRefAsCsv(blobId, repoNames, format, common.DB)
		if output != "" {
			printOrSave(maybeBlobId + common.SEP + output)
			foundInDB = true
			break // Should I consider the blobId exists in multiple formats?
		}
	}
	if !foundInDB {
		// As this is the check function, if not exist report
		h.Log("WARN", fmt.Sprintf("No blobId:%s for %s in DB (Orphaned)", blobId, maybeBlobId))
	}
	return nil
}

func checkBlobIdDetailFromBS(maybeBlobId string) interface{} {
	blobId := extractBlobIdFromString(maybeBlobId)
	if len(blobId) == 0 {
		h.Log("DEBUG", fmt.Sprintf("Empty blobId in '%s'", maybeBlobId))
		return nil
	}

	if common.DateBsLayout {
		panic("Date Blob store layout is not implemented yet.")
		// TODO: Probably need to find the created date from the database?
	}

	// basePath is the file path without extension
	basePath := h.AppendSlash(common.ContentPath) + genBlobPath(blobId, "")
	propsPath := basePath + common.PROP_EXT
	// TODO: this is not accurate as it should be checking the file name, not the path
	if common.RxFilter4FileName == nil || common.RxFilter4FileName.MatchString(propsPath) {
		blobInfo, err := Client.GetFileInfo(propsPath)
		if err != nil {
			// As this is the check function, if not exist report
			h.Log("WARN", fmt.Sprintf("No %s in BS (DeadBlob)", propsPath))
		} else {
			printLineFromPath(propsPath, blobInfo, common.DB)
		}
	}
	if common.RxFilter4FileName == nil || common.RxFilter4FileName.MatchString(basePath+common.BYTES_EXT) {
		blobInfo, err := Client.GetFileInfo(basePath + common.BYTES_EXT)
		if err != nil {
			h.Log("WARN", fmt.Sprintf("No %s in BS", basePath+common.BYTES_EXT))
		} else {
			printLineFromPath(basePath+common.BYTES_EXT, blobInfo, common.DB)
		}
	}
	return nil
}

func getAssetWithBlobRefAsCsv(blobId string, rnPerFmt []string, format string, db *sql.DB) string {
	var tableNames []string
	query := genAssetBlobUnionQuery(tableNames, "", "blob_ref LIKE '%"+blobId+"' LIMIT 1", rnPerFmt, format)
	rows := lib.Query(query, db, int64(len(rnPerFmt)*1000))
	if rows == nil { // Mainly for unit test
		h.Log("WARN", "rows is nil for query: "+query)
		return ""
	}
	defer rows.Close()
	var cols []string
	var output string
	for rows.Next() {
		if cols == nil || len(cols) == 0 {
			cols, _ = rows.Columns()
			if cols == nil || len(cols) == 0 {
				h.Log("ERROR", "No columns against query:"+query)
				return ""
			}
			// sort cols to return always same order
			sort.Strings(cols)
		}
		row := lib.GetRow(rows, cols)
		for i := range cols {
			if i > 0 {
				output = fmt.Sprintf("%s%s", output, common.SEP)
			}
			output = fmt.Sprintf("%s%v", output, row[i])
		}
		// Should be only one row
		return output
	}
	return ""
}

func getRepNames(format string) []string {
	repNames := make([]string, 0)
	for repoName, repoFmt := range common.Repo2Fmt {
		if len(format) == 0 || repoFmt == format {
			repNames = append(repNames, repoName)
		}
	}
	return repNames
}

func getFormats(repoNames []string) map[string][]string {
	formats := make(map[string][]string)
	for _, repoName := range repoNames {
		repoFmt := getFmtFromRepName(repoName)
		if len(repoFmt) > 0 {
			formats[repoFmt] = append(formats[repoFmt], repoName)
		}
	}
	return formats
}

func getFmtFromRepName(repoName string) string {
	if repoFmt, ok := common.Repo2Fmt[repoName]; ok {
		if len(repoFmt) > 0 {
			return repoFmt
		}
	}
	h.Log("WARN", fmt.Sprintf("repoName: %s is not in Repo2Fmt\n%v", repoName, common.Repo2Fmt))
	return ""
}

func getAssetTableNamesFromRepoNames(repoNames string) (result []string) {
	rnSlice := strings.Split(repoNames, ",")
	u := make(map[string]bool)
	for _, repoName := range rnSlice {
		format := getFmtFromRepName(repoName)
		if len(format) > 0 {
			tableName := getFmtFromRepName(repoName) + "_asset"
			if len(tableName) > 0 {
				if _, ok := u[tableName]; !ok {
					result = append(result, tableName)
					u[tableName] = true
				}
			}
		}
	}
	return result
}

func getRepoName(contents string) string {
	if len(contents) > 0 {
		m := common.RxRepoName.FindStringSubmatch(contents)
		if len(m) < 2 {
			h.Log("WARN", "No repo-name in "+contents)
			return ""
		}
		return m[1]
	}
	return ""
}

func genAssetBlobUnionQuery(assetTableNames []string, columns string, afterWhere string, repoNames []string, format string) string {
	cte := ""
	cteJoin := ""
	if len(assetTableNames) == 0 {
		h.Log("DEBUG", fmt.Sprintf("No assetTableNames. Using the default AssetTables (%d)", len(common.AssetTables)))
		assetTableNames = common.AssetTables
	}
	if len(columns) == 0 {
		columns = "a.repository_id, a.asset_id, a.path, a.kind, a.component_id, ab.blob_ref, ab.blob_size, ab.blob_created"
	}
	if !h.IsEmpty(afterWhere) && !common.RxAnd.MatchString(afterWhere) {
		afterWhere = "AND " + afterWhere
	}
	if len(repoNames) > 0 {
		if len(format) == 0 {
			panic(fmt.Sprintf("No format provided for repositories: %s", repoNames))
		}
		repoIn := `'` + strings.Join(repoNames, `', '`) + `'`
		// As not using LEFT JOIN, no need to use ` or r.name is NULL`
		cte = "WITH r AS (select r.name, cr.repository_id from " + format + "_content_repository cr join repository r on r.id = cr.config_repository_id WHERE r.name IN (" + repoIn + ")) "
		cteJoin = "JOIN r USING (repository_id)"
		columns = "r.name as repo_name, " + columns
	}
	elements := make([]string, 0)
	for _, tableName := range assetTableNames {
		element := cte + "SELECT " + columns
		element = fmt.Sprintf("%s FROM %s_blob ab", element, tableName)
		// NOTE: Due to the performance concern, NOT using LEFT JOIN even though this script may think orphaned when Cleanup unused asset blob task hadn't been run
		element = fmt.Sprintf("%s JOIN %s a USING (asset_blob_id) %s", element, tableName, cteJoin)
		element = fmt.Sprintf("%s WHERE 1=1 %s", element, afterWhere)
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

func isOrphanedBlob(contents string, blobId string, db *sql.DB) bool {
	// Orphaned blob is the blob which is in the blob store but not in the DB
	// UNION ALL query against many tables is slow. so if contents is given, using specific table
	repoName := getRepoName(contents)
	format := getFmtFromRepName(repoName)
	tableNames := getAssetTableNamesFromRepoNames(repoName)
	if len(repoName) > 0 && len(tableNames) == 0 {
		h.Log("WARN", fmt.Sprintf("Repsitory: %s does not exist in the database, so assuming %s as orphan", repoName, blobId))
		return true
	}
	var repoNames []string
	if len(repoName) > 0 {
		repoNames = []string{repoName}
	}
	// Generating query to search the blobId from the blob_ref, and returning only asset_id column
	// Supporting only 3.47 and higher for performance (was adding ending %) (NEXUS-35934)
	// Not using common.BsName as can't trust blob store name in blob_ref, and may not work with group blob stores
	query := genAssetBlobUnionQuery(tableNames, "asset_id", "blob_ref LIKE '%"+blobId+"' LIMIT 1", repoNames, format)
	if len(query) == 0 { // Mainly for unit test
		h.Log("WARN", fmt.Sprintf("query is empty for blobId: %s and tableNames: %v", blobId, tableNames))
		return false
	}
	// This query can take longer so not showing too many WARNs
	rows := lib.Query(query, db, int64(len(tableNames)*100))
	if rows == nil { // Mainly for unit test
		h.Log("WARN", "rows is nil for query: "+query)
		return false
	}
	defer rows.Close()
	var cols []string
	noRows := true
	for rows.Next() {
		if common.Debug {
			// Expecting a lot of blobs in DB, so showing the result only if DEBUG is set
			if cols == nil || len(cols) == 0 {
				cols, _ = rows.Columns()
				if cols == nil || len(cols) == 0 {
					panic("No columns against query:" + query)
				}
				// sort cols to return always same order
				sort.Strings(cols)
			}
			vals := lib.GetRow(rows, cols)
			// As using LEFT JOIN 'asset_id' can be NULL (nil), but rows size is not 0
			h.Log("DEBUG", fmt.Sprintf("blobId: %s row: %v", blobId, vals))
		}
		noRows = false
		break
	}
	return noRows
}

func runParallel(chunks [][]string, f func(string, *sql.DB), conc int) {
	wg := sync.WaitGroup{}
	guard := make(chan struct{}, conc)
	for _, chunk := range chunks {
		guard <- struct{}{}
		wg.Add(1)
		go func(items []string) {
			//h.Log("INFO", fmt.Sprintf("(runParallel) Spawning a routine for %d items", len(items)))
			defer wg.Done()
			if common.TopN == 0 || common.PrintedNum < common.TopN {
				// Open a DB connection per chunk
				var db *sql.DB
				if len(common.DbConnStr) > 0 {
					db = lib.OpenDb(common.DbConnStr)
					defer db.Close()
				}
				for _, item := range items {
					f(item, db)
				}
			}
			<-guard
		}(chunk)
	}
	wg.Wait()
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

	Client = bs_clients.GetClient()

	var db *sql.DB
	if len(common.DbConnStr) > 0 {
		db = lib.OpenDb(common.DbConnStr)
		defer db.Close()
	}

	printHeader()

	// If the list of Blob IDs are provided, use it
	if len(common.BlobIDFIle) > 0 {
		// If Truth (src) is not set or Truth and BlobIDFile type are the same, reading this file as source
		if len(common.Truth) == 0 || (len(common.Truth) > 0 && common.Truth == common.BlobIDFIleType) {
			h.Log("DEBUG", "'rf' is provided and 'rf' type matches with 'src', so reading 'rf' as "+common.Truth+" result.")
			if common.BlobIDFIleType == "BS" {
				_ = h.StreamLines(common.BlobIDFIle, common.Conc1, checkBlobIdDetailFromDB)
				h.Log("INFO", "Completed 'checkBlobIdDetailFromDB' from "+common.BlobIDFIle+" ("+common.BlobIDFIleType+")")
			} else if common.BlobIDFIleType == "DB" {
				_ = h.StreamLines(common.BlobIDFIle, common.Conc1, checkBlobIdDetailFromBS)
				h.Log("INFO", "Completed 'checkBlobIdDetailFromBS' from "+common.BlobIDFIle+" ("+common.BlobIDFIleType+")")
			}
			return
		} else if len(common.Truth) > 0 && len(common.BlobIDFIleType) > 0 && common.Truth != common.BlobIDFIleType {
			panic("TODO: 'rf' is provided but 'rf' type:" + common.BlobIDFIleType + " does not match with 'src' type:" + common.Truth + ", so this file will be used against filelist result.")
			// TODO: implement this
		}
	}

	// If the Blob ID file is not provided, run per directory
	h.Log("DEBUG", fmt.Sprintf("Starting GetDirs with %s, %s, %d", common.ContentPath, common.Filter4Path, common.MaxDepth))
	startMs := time.Now().UnixMilli()
	subDirs, err := Client.GetDirs(common.ContentPath, common.Filter4Path, common.MaxDepth)
	if err != nil {
		h.Log("ERROR", "Failed to list directories in "+common.ContentPath+" with filter: "+common.Filter4Path)
		panic(err)
	}
	chunks := h.Chunk(subDirs, 1) // 1 is for spawning the routine per subDir.
	h.Elapsed(startMs, fmt.Sprintf("GetDirs got %d directories", len(subDirs)), 200)

	startMs = time.Now().UnixMilli()
	runParallel(chunks, listObjects, common.Conc1)
	// Always log this elapsed time by using 0 thresholdMs
	h.Elapsed(startMs, fmt.Sprintf("Completed. Listed: %d (checked: %d), Size: %d bytes", common.PrintedNum, common.CheckedNum, common.TotalSize), 0)
	return

	// If Truth is DB, find unnecessary blobs from the Blob store (orphaned blobs)
	// Also, if the Blob ID file is provided, find the orphaned blobs by using it (no need to connect to DB)

	// If Truth is BS, find unnecessary DB records from the database (dead blobs)
	// Also, if the Blob ID file is provided, find the dead blobs by using it (no need to connect to DB)
}
