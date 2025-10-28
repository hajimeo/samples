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
	"io"
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
var Client2 bs_clients.Client

func usage() {
	fmt.Println(`
List .properties and .bytes files as *Tab* Separated Values (Path LastModified Size ...).
    
HOW TO and USAGE EXAMPLES:
    https://github.com/hajimeo/samples/blob/master/golang/FileListV2/README.md`)
	fmt.Println("")
}

// Populate all global variables
func setGlobals() {
	common.StartTimestamp = time.Now().Unix()

	// TODO: 'b' should accept the comma separated values for supporting the group blob store
	flag.StringVar(&common.BaseDir, "b", "", "Blob store directory or URI (eg. 's3://s3-test-bucket/s3-test-prefix/'), which location contains 'content' directory (default: '.')")
	flag.StringVar(&common.BaseDir2, "bTo", "", "*Experimental* Blob store directory or URI (eg. 's3://s3-test-bucket/s3-test-prefix/') for copying files from -b")
	flag.BoolVar(&common.NoDateBsLayout, "NoDateBS", false, "Disable the date based blob store layout (YYYY/MM/DD/hh/mm/uuid) to force checking the old vol-XX/chap-XX/uuid layout")
	flag.StringVar(&common.Filter4Path, "p", "", "Regular Expression for directory *path* (eg '/(vol-\\d\\d|20\\d\\d)/'), or S3 prefix.")
	flag.StringVar(&common.Filter4FileName, "f", "", "Regular Expression for the file *name* (eg: '\\.properties' to include only this extension)")
	flag.BoolVar(&common.WithProps, "P", false, "If true, the .properties file content is included in the output")
	flag.StringVar(&common.Filter4PropsIncl, "pRx", "", "Regular Expression against the text of the .properties files (eg: 'deleted=true')")
	flag.StringVar(&common.Filter4PropsExcl, "pRxNot", "", "Excluding Regular Expression for .properties files (eg: 'BlobStore.blob-name=.+/maven-metadata.xml.*')")
	// TODO: not implemented yet
	flag.StringVar(&common.Filter4BytesIncl, "bRx", "", "Regular Expression for .bytes files (max size 32KB)")
	flag.StringVar(&common.Filter4BytesExcl, "bRxNot", "", "Excluding Regular Expression for .bytes files (max size 32KB)")
	flag.StringVar(&common.SaveToFile, "s", "", "Save the output (TSV text) into the specified path")
	flag.BoolVar(&common.SavePerDir, "SavePerDir", false, "If true and -s is given, save the output per sub-directory")
	flag.Int64Var(&common.TopN, "n", 0, "Return first N lines per *thread* (0 = no limit). Can't be less than '-c'")
	flag.IntVar(&common.Conc1, "c", 1, "Concurrent number for reading directories")
	flag.IntVar(&common.Conc2, "c2", 8, "2nd Concurrent number. Currently used when retrieving object from AWS S3")
	flag.IntVar(&common.MaxDepth, "depth", 5, "Max Depth for finding sub-directories only for File type (default: 5 for YYYY/MM/DD/hh/mm/)")
	flag.BoolVar(&common.NoHeader, "H", false, "If true, no header line")

	flag.StringVar(&common.BlobIDFIle, "rF", "", "Result File which contains the list of blob IDs")
	flag.StringVar(&common.GetFile, "get", "", "TODO: Get a single file/blob from the blob store")
	flag.StringVar(&common.GetTo, "getTo", "", "TODO: Get to the local path")
	// TODO: GetXxxx not used yet

	// DB / SQL related
	flag.StringVar(&common.DbConnStr, "db", "", "DB connection string or path to DB connection properties file")
	flag.StringVar(&common.BsName, "bsName", "", "eg. 'default'. If provided, the SQL query might become faster")
	flag.StringVar(&common.Query, "query", "", "SQL 'SELECT blob_id ...' or 'SELECT blob_ref as blob_id ...' to filter the data from the DB")

	// Reconcile / orphaned blob finding related
	flag.StringVar(&common.Truth, "src", "", "Using database or blobstore as source [BS|DB] for Dead or Orphaned blob finding")
	flag.BoolVar(&common.RemoveDeleted, "RDel", false, "Remove 'deleted=true' from .properties. Requires -dF")
	// TODO: Not tested `-RDel` with the new blob store layout and with S3 / Azure
	flag.StringVar(&common.WriteIntoStr, "wStr", "", "For testing. Write the string into the file (eg. deleted=true)")
	flag.StringVar(&common.DelDateFromStr, "dDF", "", "Deleted date YYYY-MM-DD (from). Used to search deletedDateTime")
	flag.StringVar(&common.DelDateToStr, "dDT", "", "Deleted date YYYY-MM-DD (to). To exclude newly deleted assets")
	flag.StringVar(&common.ModDateFromStr, "mDF", "", "File modification date YYYY-MM-DD (from)")
	flag.StringVar(&common.ModDateToStr, "mDT", "", "File modification date YYYY-MM-DD (to)")
	flag.BoolVar(&common.BytesChk, "BytesChk", false, "Check if .bytes file exists. Also the .bytes mod time is used for -mDF/-mDT")
	flag.BoolVar(&common.NoSizeChk, "NoSizeChk", false, "Do not check the file size (for non S3 such as MinIO)")

	// Blob store specifics (AWS S3 / Azure related)
	flag.IntVar(&common.MaxKeys, "m", 1000, "AWS S3: Integer value for Max Keys (<= 1000)")
	flag.BoolVar(&common.WithOwner, "O", false, "AWS S3: If true, get the owner display name")
	flag.BoolVar(&common.WithTags, "T", false, "AWS S3: If true, get tags of each object")

	// Other options for troubleshooting
	flag.Int64Var(&common.SlowMS, "slowMS", 1000, "Some methods show WARN log if that method takes more than this msec")
	flag.IntVar(&common.CacheSize, "cacheSize", 1000, "How many .properties files to cache")
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
	if len(common.BaseDir) > 0 {
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
	}

	if len(common.BaseDir2) > 0 {
		common.BaseDir2 = h.AppendSlash(common.BaseDir2)
		h.Log("DEBUG", "common.BaseDir2 with slash = "+common.BaseDir2)
		common.BsType2 = lib.GetSchema(common.BaseDir2)
		h.Log("DEBUG", "common.BsType2 = "+common.BsType2)
		common.Container2, common.Prefix2 = lib.GetContainerAndPrefix(common.BaseDir2)
		h.Log("DEBUG", "common.Container2 = "+common.Container2)
		h.Log("DEBUG", "common.Prefix2 = "+common.Prefix2)
		common.ContentPath2 = lib.GetContentPath(common.BaseDir2)
		h.Log("DEBUG", "common.ContentPath = "+common.ContentPath2)
	}

	if common.Conc1 < 1 {
		h.Log("ERROR", "-c is lower than 1.")
		os.Exit(1)
	}
	if common.TopN > 0 && common.Conc1 > int(common.TopN) {
		common.Conc1 = int(common.TopN)
		h.Log("INFO", "-c is larger than -n. Setting -c with -n: "+strconv.Itoa(common.Conc1))
	}

	if len(common.DbConnStr) > 0 {
		// If it's nexus-store.properties file, read the file and get the DB connection string
		if _, err := os.Stat(common.DbConnStr); err == nil {
			common.DbConnStr = lib.GenDbConnStrFromFile(common.DbConnStr)
		}
		if len(common.Truth) > 0 && len(common.Filter4FileName) == 0 {
			// If Truth is set and DB connection is provided, probably want to check only .properties files
			h.Log("INFO", "Setting '-f "+common.PROPERTIES+"' as DB connection is provided.")
			common.Filter4FileName = common.PROPERTIES
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
		initRepoFmtMap(common.DB)
	}

	if len(common.Query) > 0 {
		if !common.RxSelect.MatchString(common.Query) {
			panic("Query should start with 'SELECT' and contain 'blob_id': " + common.Query)
		}
		if len(common.DbConnStr) == 0 {
			panic("Query requires DB connection string")
		}
		//if len(common.BlobIDFIle) > 0 {
		//	panic("Currently -rF and -query can't be used togather")
		//}
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
	if len(common.Filter4BytesIncl) > 0 {
		common.RxInclBytes, _ = regexp.Compile(common.Filter4BytesIncl)
	}
	if len(common.Filter4BytesExcl) > 0 {
		common.RxExclBytes, _ = regexp.Compile(common.Filter4BytesExcl)
	}

	// This property is automatically changed in the above, so RxFilter4FileName needs to be set in the end
	if len(common.Filter4FileName) > 0 {
		common.RxFilter4FileName, _ = regexp.Compile(common.Filter4FileName)
	}

	// If Truth is not set but BlobIDFIle is given, needs to set Truth
	if len(common.Truth) == 0 && len(common.BlobIDFIle) > 0 {
		if common.RemoveDeleted == false && len(common.BaseDir) > 0 {
			h.Log("WARN", "BlobIDFIle and BaseDir are provided but '-src DB' is missing to find Dead blobs")
			//common.Truth = "DB"
		} else if len(common.DbConnStr) > 0 && len(common.Query) == 0 {
			// If BlobIDFIle is not empty, Query should be empty as Query usesBlobIDFIle to save the result.
			h.Log("WARN", "BlobIDFIle and DbConnStr are provided but no BaseDir and no '-src BS' to find Orphaned blobs")
			//common.Truth = "BS"
		}
	}

	if common.Truth == "BS" || common.Truth == "DB" {
		if len(common.BlobIDFIle) == 0 && len(common.Query) == 0 && (len(common.DbConnStr) == 0 || len(common.BaseDir) == 0) {
			panic("-src without -rF requires -b and -db")
		}
		//if common.Truth == "DB" {
		// If Dead Blobs finder mode, always check .bytes file
		//	common.BytesChk = true
		//}
	}

	// If BlobIDFIle is given, DB connection or BaseDir is required
	if len(common.DbConnStr) == 0 && len(common.BaseDir) == 0 {
		panic("-src with -rF requires -b or -db")
	}
	if len(common.BlobIDFIle) > 0 && len(common.BlobIDFIleType) == 0 {
		if len(common.DbConnStr) > 0 && len(common.BaseDir) > 0 {
			h.Log("DEBUG", "-b, and -db are given. Using Blob IDs in -rF as if saved BS output.")
			common.BlobIDFIleType = "BS"
		} else if len(common.DbConnStr) > 0 && len(common.BaseDir) == 0 {
			h.Log("DEBUG", "-db is given but no -b. Using Blob IDs in -rF as if saved BS output.")
			common.BlobIDFIleType = "BS"
		} else if len(common.DbConnStr) == 0 && len(common.BaseDir) > 0 {
			h.Log("DEBUG", "-b is given but no -db. Using Blob IDs in -rF as if saved DB output.")
			common.BlobIDFIleType = "DB"
		}
	}

	if len(common.SaveToFile) > 0 {
		// If the SaveToFile is a directory, set SavePerDir to true
		if fi, err := os.Stat(common.SaveToFile); err == nil && fi.IsDir() {
			h.Log("DEBUG", "Save to destination is directory. Setting SavePerDir to true. "+common.SaveToFile)
			common.SavePerDir = true
		}
		var err error
		if common.SavePerDir {
			// Header is written only when one file is used (otherwise, when concatenating files, it will be problem)
			common.NoHeader = true
			// if SaveToFile does not exist, create this directory
			if _, err = os.Stat(common.SaveToFile); os.IsNotExist(err) {
				if err = os.MkdirAll(common.SaveToFile, 0755); err != nil {
					panic(err)
				}
			}
			h.Log("INFO", "Output will be saved into the directory: "+common.SaveToFile)
		} else {
			common.SaveToPointer, err = os.OpenFile(common.SaveToFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
			if err != nil {
				panic(err)
			}
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
	if len(common.BsName) > 0 {
		h.Log("INFO", fmt.Sprintf("AssetTables = %v for '%s' blob store", common.AssetTables, common.BsName))
	} else {
		h.Log("DEBUG", fmt.Sprintf("AssetTables = %v", common.AssetTables))
	}
}

func printHeader(saveToPointer *os.File) {
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
		if len(common.Truth) > 0 || common.BytesChk {
			header += fmt.Sprintf("%sMisc.", common.SEP)
		}
		printOrSave(header, saveToPointer)
	}
}

func extractBlobIdFromString(pathLikeLine string) string {
	//fileName := filepath.Base(pathLikeLine)
	//return getPathWithoutExt(fileName)
	if !common.NoDateBsLayout {
		var matches []string
		// Checking the path like blob ID regex first
		matches = common.RxBlobIdNew2.FindStringSubmatch(pathLikeLine)
		if len(matches) > 6 {
			// 2025/08/14/02/44/6c1d3423-ecbc-4c52-a0fe-01a45a12883a
			return matches[6] + "@" + matches[1] + "-" + matches[2] + "-" + matches[3] + "T" + matches[4] + ":" + matches[5]
		}
		// Probably because the path like string is provide, no need to consider @2025-08-14T02:44 but just in case...
		matches = common.RxBlobIdNew.FindStringSubmatch(pathLikeLine)
		if len(matches) > 6 {
			// 6c1d3423-ecbc-4c52-a0fe-01a45a12883a@2025-08-14T02:44
			return matches[1] + "@" + matches[2] + "-" + matches[3] + "-" + matches[4] + "T" + matches[5] + ":" + matches[6]
		}
	}
	return common.RxBlobId.FindString(pathLikeLine)
}

func genBlobPath(blobIdLikeString string, extension string) string {
	// NOTE: this returns path without slash at the beginning
	blobId := blobIdLikeString
	if !common.NoDateBsLayout {
		var matches []string
		matches = common.RxBlobIdNew.FindStringSubmatch(blobIdLikeString)
		if len(matches) > 6 {
			// 6c1d3423-ecbc-4c52-a0fe-01a45a12883a@2025-08-14T02:44
			// 2025/08/14/02/44/6c1d3423-ecbc-4c52-a0fe-01a45a12883a.properties
			return filepath.Join(matches[2], matches[3], matches[4], matches[5], matches[6], matches[1]) + extension
		}
		matches = common.RxBlobIdNew2.FindStringSubmatch(blobIdLikeString)
		if len(matches) > 6 {
			return filepath.Join(matches[1], matches[2], matches[3], matches[4], matches[5], matches[6]) + extension
		}
	}

	blobId = common.RxBlobId.FindString(blobIdLikeString)
	if len(blobId) == 0 {
		h.Log("WARN", "genBlobPath got empty blobId for "+blobIdLikeString)
		return ""
	}
	// org.sonatype.nexus.blobstore.VolumeChapterLocationStrategy#location
	hashInt := lib.HashCode(blobId)
	vol := math.Abs(math.Mod(float64(hashInt), 43)) + 1
	chap := math.Abs(math.Mod(float64(hashInt), 47)) + 1
	return filepath.Join(fmt.Sprintf("vol-%02d", int(vol)), fmt.Sprintf("chap-%02d", int(chap)), blobId) + extension
}

func genOutput(path string, bi bs_clients.BlobInfo, db *sql.DB) string {
	if len(common.Filter4FileName) > 0 && !common.RxFilter4FileName.MatchString(path) {
		h.Log("DEBUG", fmt.Sprintf("path:%s does not match with the filter %s", path, common.RxFilter4FileName.String()))
		return ""
	}

	var bytesChkErr error
	var bytesInfo bs_clients.BlobInfo
	var bytesPath string
	if strings.HasSuffix(path, common.PROP_EXT) {
		// the properties file can not be empty (0 byte), but if already Error, no need another WARN
		if !common.NoSizeChk && !bi.Error && bi.Size == 0 {
			h.Log("WARN", fmt.Sprintf("path:%s has 0 byte size", path))
			// No need to exit
		}

		if common.BytesChk && !bi.Error {
			// If the path ends with .properties, replace with .bytes
			bytesPath = lib.GetPathWithoutExt(path) + common.BYTES_EXT
			bytesInfo, bytesChkErr = Client.GetFileInfo(bytesPath)
			if bytesChkErr != nil {
				if common.Truth != "BS" {
					h.Log("WARN", fmt.Sprintf("BYTES_MISSING for %s (error: %s)", bytesPath, bytesChkErr.Error()))
				} else {
					h.Log("DEBUG", fmt.Sprintf("BYTES_MISSING for %s (probably deletion marker?)", bytesPath))
				}
			}
		}
	}

	//TODO: use shouldSkipBecauseOfBytes()

	var output string
	var sortedOneLineProps string
	var skipReason error
	if bi.Error {
		if common.Truth != "DB" {
			h.Log("DEBUG", fmt.Sprintf("path:%s has error in getting BlobInfo. Skipping...", path))
			return ""
		}
		output = fmt.Sprintf("%s%s%s%s%d", path, common.SEP, bi.ModTime, common.SEP, bi.Size)
	} else {
		modTimestamp := bi.ModTime.Unix()
		// If BytesChk is false, use the .bytes file's modTime for the filter as the .properties mod time can be unexpected value
		if common.BytesChk && bytesChkErr == nil && !strings.HasSuffix(path, common.BYTES_EXT) {
			bytesModTimestamp := bytesInfo.ModTime.Unix()
			if !lib.IsTsMSecBetweenTs(bytesModTimestamp*1000, common.ModDateFromTS, common.ModDateToTS) {
				h.Log("DEBUG", fmt.Sprintf("Bytes path:%s modTime %d is outside of the range %d to %d", bytesPath, bytesModTimestamp, common.ModDateFromTS, common.ModDateToTS))
				return ""
			}
		} else {
			if !lib.IsTsMSecBetweenTs(modTimestamp*1000, common.ModDateFromTS, common.ModDateToTS) {
				h.Log("DEBUG", fmt.Sprintf("path:%s modTime %d is outside of the range %d to %d", path, modTimestamp, common.ModDateFromTS, common.ModDateToTS))
				return ""
			}
			output = fmt.Sprintf("%s%s%s%s%d", path, common.SEP, bi.ModTime, common.SEP, bi.Size)
			// If .properties file is checked, depending on other flags, need to generate extra output
			if shouldReadProps(path, modTimestamp) {
				//h.Log("DEBUG", fmt.Sprintf("Extra info from properties is needed for '%s'", path))
				sortedOneLineProps, skipReason = extraInfo(path)
				if skipReason != nil {
					h.Log("DEBUG", fmt.Sprintf("%s: %s", path, skipReason.Error()))
					return ""
				}
				if common.BytesChk && bytesChkErr == nil && strings.HasSuffix(path, common.PROP_EXT) {
					// If BytesChek is asked, compare the size with the size line in the .properties file (NOTE: 0 size is possible)
					matches := common.RxSizeByte.FindStringSubmatch(sortedOneLineProps)
					if matches == nil || len(matches) == 0 {
						// For now, if no size line found, just log warning
						h.Log("WARN", fmt.Sprintf("path:%s may not have the size", path))
					} else {
						sizeInProps, err := strconv.ParseInt(matches[1], 10, 64)
						if err != nil {
							h.Log("WARN", fmt.Sprintf("path:%s has non numeric size %v", path, matches))
						} else if !common.NoSizeChk && sizeInProps != bytesInfo.Size {
							h.Log("WARN", fmt.Sprintf("path:%s has size mismatch between size=%s and .bytes (%d)", path, matches[1], bytesInfo.Size))
						}
					}
				}
				//} else {
				//	h.Log("DEBUG", fmt.Sprintf("Extra info from properties is NOT needed for '%s'", path))
			}
		}
	}

	// NOTE: make sure the output order is same as the printHeader
	if common.WithProps {
		output = fmt.Sprintf("%s%s%s", output, common.SEP, sortedOneLineProps)
	}

	if common.WithOwner {
		output = fmt.Sprintf("%s%s%s", output, common.SEP, bi.Owner)
	}

	if common.WithTags {
		output = fmt.Sprintf("%s%s%s", output, common.SEP, bi.Tags)
	}

	// "Misc." column
	if common.Truth == "BS" {
		// If DB connection is given and the truth is blob store, check if the blob ID in the path exists in the DB
		// But if bytesChkErr is not nil, it's not considered as orphaned, rather missing blob.
		if len(common.DbConnStr) > 0 && bytesChkErr == nil {
			blobId := extractBlobIdFromString(path)
			// If sortedOneLineProps is empty, the below may use expensive query
			reason := isOrphanedBlob(sortedOneLineProps, blobId, db)
			if len(reason) > 0 {
				output = fmt.Sprintf("%s%s%s", output, common.SEP, reason)
			} else {
				h.Log("DEBUG", "Blob ID: "+blobId+" exists in the DB. Not including in the output.")
				output = ""
			}
		}
	} else if common.Truth == "DB" {
		// NOTE: Expecting when Truth is "DB", the BytesChk is always true
		if bi.Error && bytesChkErr != nil {
			h.Log("DEBUG", fmt.Sprintf("path:%s has error (missing) and misisng bytes. Considering as DEAD blob.", path))
			output = fmt.Sprintf("%s%s%s", output, common.SEP, "DEAD_BLOB:missing properties/bytes")
		} else if bi.Error {
			h.Log("DEBUG", fmt.Sprintf("path:%s has error (missing). Considering as DEAD blob.", path))
			output = fmt.Sprintf("%s%s%s", output, common.SEP, "DEAD_BLOB:missing properties")
		} else if bytesChkErr != nil {
			h.Log("DEBUG", fmt.Sprintf("path:%s has no .bytes file. Considering as DEAD blob.", path))
			output = fmt.Sprintf("%s%s%s", output, common.SEP, "DEAD_BLOB:missing bytes")
		}
	} else if bytesChkErr != nil {
		output = fmt.Sprintf("%s%s%s", output, common.SEP, "BYTES_MISSING")
	}

	return output
}

func shouldReadProps(path string, modTimestamp int64) bool {
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
	// This function returns the extra information (.properties contents) and the skip reason as error
	// Also does extra checks. For example, this may return "" with the error, when RxIncl or RxExcl filtered the contents.
	var contents string
	var err error
	var shouldInvalidateCache = false

	// If the contents is already cached, return it
	if common.CacheSize > 0 {
		valueInCache := h.CacheGetObj(path)
		if valueInCache != nil && len(valueInCache.(string)) > 0 {
			contents = valueInCache.(string)
			h.Log("DEBUG", fmt.Sprintf("Found %s in the cache (size:%d)", path, len(contents)))
		}
	}

	if len(contents) == 0 {
		contents, err = Client.ReadPath(path)
		if err != nil {
			h.Log("ERROR", "(extraInfo) "+path+" returned error:"+err.Error())
			// This (reading file error) is not the skip reason, so returning nil error.
			return "", nil
		}
	}

	if len(contents) == 0 {
		h.Log("ERROR", "(extraInfo) "+path+" returned 0 size.")
		// This (empty) is not the skip reason, so returning nil error.
		return "", nil
	}

	// removeDel requires to read the contents (to avoid re-reading same file), so executing in the extraInfo.
	if common.RemoveDeleted {
		_ = removeDel(contents, path)
		shouldInvalidateCache = true
	}

	if len(common.WriteIntoStr) > 0 {
		_ = appendStr(common.WriteIntoStr, contents, path)
		shouldInvalidateCache = true
	}

	if common.CacheSize > 0 {
		if shouldInvalidateCache {
			h.CacheDelObj(path)
		} else { // the content size is already checked
			h.CacheAddObject(path, contents, common.CacheSize)
		}
	}

	// For regex check, sorting the contents to single line first
	sortedContents := lib.SortToSingleLine(contents)
	err = shouldSkipThisContents(sortedContents)
	if err != nil {
		return "", err
	}
	return sortedContents, nil
}

func shouldSkipThisContents(sortedContents string) error {
	// NOTE: this function is only for the sorted one line contents
	// Exclude check first
	if common.RxExcl != nil && common.RxExcl.MatchString(sortedContents) {
		return errors.New(fmt.Sprintf("Matched with the exclude regex: %s. Skipping.", common.RxExcl.String()))
	}
	if common.RxIncl != nil && len(common.RxIncl.String()) > 0 {
		if common.RxIncl.MatchString(sortedContents) {
			return nil
		} else {
			//h.Log("DEBUG", fmt.Sprintf("Sorted content did not match with '%s'", common.RxIncl.String()))
			return errors.New(fmt.Sprintf("Does NOT match with the regex: %s. Skipping.", common.RxIncl.String()))
		}
	}

	if common.RxExclBytes != nil {
		if common.RxExclBytes.MatchString(sortedContents) {
			return errors.New(fmt.Sprintf("Matched with the exclude regex: %s. Skipping.", common.RxExcl.String()))
		}
	}
	if common.RxInclBytes != nil {
		if len(common.RxIncl.String()) > 0 {
			if common.RxIncl.MatchString(sortedContents) {
				return nil
			} else {
				//h.Log("DEBUG", fmt.Sprintf("Sorted content did not match with '%s'", common.RxIncl.String()))
				return errors.New(fmt.Sprintf("Does NOT match with the regex: %s. Skipping.", common.RxIncl.String()))
			}
		}
	}
	return nil
}

func shouldSkipBecauseOfBytes(bytesContents string) error {
	// TODO: not properly implemented and not tested
	if common.RxExclBytes != nil {
		if common.RxExclBytes.MatchString(bytesContents) {
			return errors.New(fmt.Sprintf("Matched with the exclude regex: %s. Skipping.", common.RxExcl.String()))
		}
	}
	if common.RxInclBytes != nil {
		if len(common.RxIncl.String()) > 0 {
			if common.RxIncl.MatchString(bytesContents) {
				return nil
			} else {
				//h.Log("DEBUG", fmt.Sprintf("Sorted content did not match with '%s'", common.RxIncl.String()))
				return errors.New(fmt.Sprintf("Does NOT match with the regex: %s. Skipping.", common.RxIncl.String()))
			}
		}
	}
	return nil
}

func shouldBeUndeleted(contents string, path string) bool {
	if len(contents) == 0 {
		h.Log("WARN", fmt.Sprintf("path:%s has no contents", path))
		return false
	}

	if !common.RxDeleted.MatchString(contents) {
		h.Log("DEBUG", fmt.Sprintf("path:%s does not have 'deleted=true' so that no need to un-delete", path))
		return false
	}

	matches := common.RxDeletedDT.FindStringSubmatch(contents)
	if matches == nil || len(matches) == 0 {
		h.Log("WARN", fmt.Sprintf("path:%s may not have the deletedDateTime (but un-deleting)", path))
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

func printLineFromPath(args bs_clients.PrintLineArgs) bool {
	path := args.Path
	blobInfo := args.BInfo
	db := args.DB
	saveToPointer := common.SaveToPointer
	var err error
	if common.SavePerDir {
		if len(args.SaveDir) == 0 || args.SaveDir == "." {
			panic("SavePerDir is true but SaveDir is nil or '.'")
		}
		saveFile := filepath.Base(args.SaveDir) + ".tsv"
		saveToPointer, err = os.OpenFile(filepath.Join(common.SaveToFile, saveFile), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			panic(err)
		}
		defer saveToPointer.Close()
	}

	// This function should control the all counters
	// and return 'false' when it reached the limit (TopN)
	if common.TopN > 0 && common.TopN <= common.PrintedNum {
		h.Log("DEBUG", fmt.Sprintf("printLineFromPath found Printed %d >= %d", common.PrintedNum, common.TopN))
		return false
	}
	// Incrementing the checked number counter *synchronously* (not sure if this causes some slowness)
	atomic.AddInt64(&common.CheckedNum, 1)

	//h.Log("DEBUG", fmt.Sprintf("Generating the output for '%s'", path))
	output := genOutput(path, blobInfo, db)

	// Updating counters before (saving and) returning
	if len(output) > 0 {
		atomic.AddInt64(&common.PrintedNum, 1)
		atomic.AddInt64(&common.TotalSize, blobInfo.Size)

		if len(common.BaseDir2) > 0 && strings.HasSuffix(path, common.PROP_EXT) {
			finalErrorCode := ""
			errorCode := copyToBaseDir2(path)
			// regardless of the errorCode, try to copy the .bytes file as well
			bytesPath := lib.GetPathWithoutExt(path) + common.BYTES_EXT
			errorCode2 := copyToBaseDir2(bytesPath)
			if len(errorCode) > 0 {
				finalErrorCode = errorCode
			}
			if len(errorCode2) > 0 {
				if len(finalErrorCode) > 0 {
					finalErrorCode = finalErrorCode + "|" + errorCode2
				} else {
					finalErrorCode = errorCode2
				}
			}
			if len(finalErrorCode) > 0 {
				output = fmt.Sprintf("%s%s%s", output, common.SEP, finalErrorCode)
			}
		}

		printOrSave(output, saveToPointer)
	}
	return true
}

func writeFromCache(path string, client bs_clients.Client) (bool, error) {
	if common.CacheSize > 0 {
		valueInCache := h.CacheGetObj(path)
		if valueInCache != nil && len(valueInCache.(string)) > 0 {
			contents := valueInCache.(string)
			h.Log("DEBUG", fmt.Sprintf("Found %s in the cache (size:%d)", path, len(contents)))
			err := client.WriteToPath(path, contents)
			if err != nil {
				return false, err
			}
			return true, nil
		}
	}
	return false, nil
}

func copyToBaseDir2(path string) string {
	writingPath := filepath.Join(common.ContentPath2, lib.GetAfterContent(path))
	// If the path is .properties, first try to write by using the cache
	if strings.HasSuffix(path, common.PROP_EXT) {
		result, err := writeFromCache(writingPath, Client2)
		if err != nil {
			h.Log("ERROR", fmt.Sprintf("Writing path:%s to BaseDir2:%s failed with %s", writingPath, common.BaseDir2, err))
			return "FROM_CACHE_FAILED"
		}
		if result {
			// nothing to append as it worked
			return ""
		}
	}

	// if no error but result is false, means no cache, so didn't write by using the cache, so copying by stream
	maybeWriter, errW := Client2.GetWriter(writingPath)
	if errW != nil {
		h.Log("ERROR", fmt.Sprintf("Getting writer for path:%s to BaseDir2:%s failed with %s", writingPath, common.BaseDir2, errW))
		return "WRITE_FAILED"
	}

	writer := maybeWriter.(io.WriteCloser)
	defer writer.Close()

	maybeReader, errR := Client.GetReader(path)
	if errR != nil {
		h.Log("ERROR", fmt.Sprintf("Getting reader for path:%s from BaseDir:%s failed with %s", path, common.BaseDir, errR))
		return "READ_FAILED"
	}
	reader := maybeReader.(io.ReadCloser)
	defer reader.Close()

	_, errC := io.Copy(writer, reader)
	if errC != nil {
		h.Log("ERROR", fmt.Sprintf("Copying data from path:%s to BaseDir2:%s failed with %s", path, common.BaseDir2, errC))
		return "COPY_FAILED"
	}

	h.Log("DEBUG", fmt.Sprintf("Copied data from path:%s to BaseDir2:%s", path, writingPath))
	return ""
}

func printOrSave(line string, saveToPointer *os.File) {
	// At this moment, excluding empty line
	if len(line) == 0 {
		return
	}
	if saveToPointer != nil {
		//h.Log("INFO", saveToPointer.Name())
		_, _ = fmt.Fprintln(saveToPointer, line)
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
			printOrSave(maybeBlobId+common.SEP+output, common.SaveToPointer)
			foundInDB = true
			break // Should I consider the blobId exists in multiple formats?
		}
	}
	if !foundInDB {
		// As this is the check function, if not exist, report as WARN
		h.Log("WARN", fmt.Sprintf("No blobId:%s for %s in DB (Orphaned)", blobId, maybeBlobId))
	}
	return nil
}

func checkBlobIdDetailFromBS(maybeBlobId string) interface{} {
	// Using this for the dead blobs check as well. If nil returned, means dead blob.
	if len(maybeBlobId) == 0 {
		h.Log("DEBUG", fmt.Sprintf("Empty blobId in '%s'", maybeBlobId))
		return nil
	}
	// basePath is the file path without extension
	basePath := h.AppendSlash(common.ContentPath) + genBlobPath(maybeBlobId, "")
	if common.BytesChk == false {
		// If BytesChk is true, no need to do the followings as checking .properties file checks .bytes
		bytesPath := basePath + common.BYTES_EXT
		if common.RxFilter4FileName == nil || common.RxFilter4FileName.MatchString(bytesPath) {
			blobInfo, err := Client.GetFileInfo(bytesPath)
			bytesArgs := bs_clients.PrintLineArgs{
				Path:  bytesPath,
				BInfo: blobInfo,
				DB:    common.DB,
			}
			if err != nil {
				h.Log("WARN", fmt.Sprintf("No %s in BS (error: %s)", bytesPath, err.Error()))
				// This combination shouldn't be possible but just in case (if "DB", the BytesChk should be always true)
				if common.Truth == "DB" {
					printLineFromPath(bytesArgs)
				}
			} else {
				printLineFromPath(bytesArgs)
			}
		}
	}

	propsPath := basePath + common.PROP_EXT
	// NOTE: this may not be accurate as it should be checking the base file name, not the path
	if common.RxFilter4FileName == nil || common.RxFilter4FileName.MatchString(propsPath) {
		blobInfo, err := Client.GetFileInfo(propsPath)
		args := bs_clients.PrintLineArgs{
			Path:  propsPath,
			BInfo: blobInfo,
			DB:    common.DB,
		}
		if err != nil {
			h.Log("WARN", fmt.Sprintf("No %s in BS (error: %s)", propsPath, err.Error()))
			if common.Truth == "DB" {
				printLineFromPath(args)
			}
			return nil
		}
		printLineFromPath(args)
		//return blobInfo	// Currently the line use this function is not using the return value
	}
	return nil
}

func getAssetWithBlobRefAsCsv(blobId string, reposPerFmt []string, format string, db *sql.DB) string {
	h.Log("DEBUG", fmt.Sprintf("repoNames: %v, format:%s", reposPerFmt, format))
	var tableNames []string
	blobIdTmp := blobId
	// If needs to consider the new blob store layout and if the blobId does not contain @, adding % to the blobId
	if !common.NoDateBsLayout && !strings.Contains(blobId, "@") {
		blobIdTmp = blobId + "%"
	}
	query := genAssetBlobUnionQuery(tableNames, "", "blob_ref LIKE '%"+blobIdTmp+"' LIMIT 1", reposPerFmt, format)
	slowMs := int64(1000)
	if len(reposPerFmt) > 0 {
		slowMs = int64(len(reposPerFmt) * 500)
	}
	rows := lib.Query(query, db, slowMs)
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

func genAssetBlobUnionQuery(assetTableNames []string, columns string, afterWhere string, reposPerFmt []string, format string) string {
	cte := ""
	cteJoin := ""
	if len(assetTableNames) == 0 {
		if len(format) > 0 {
			h.Log("DEBUG", fmt.Sprintf("No assetTableNames but format %s is provided.", format))
			assetTableNames = []string{format + "_asset"}
		} else {
			h.Log("DEBUG", fmt.Sprintf("No assetTableNames. Using the default AssetTables (%d)", len(common.AssetTables)))
			assetTableNames = common.AssetTables
		}
	}
	if len(columns) == 0 {
		columns = "a.repository_id, a.asset_id, a.path, a.kind, a.component_id, ab.blob_ref, ab.blob_size, ab.blob_created"
	}
	if !h.IsEmpty(afterWhere) && !common.RxAnd.MatchString(afterWhere) {
		afterWhere = "AND " + afterWhere
	}
	if len(reposPerFmt) > 0 {
		if len(format) == 0 {
			format = getFmtFromRepName(reposPerFmt[0])
			h.Log("DEBUG", fmt.Sprintf("No format for %v so using %s", reposPerFmt, format))
		}
		repoIn := `'` + strings.Join(reposPerFmt, `', '`) + `'`
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

func isOrphanedBlob(contents string, blobId string, db *sql.DB) string {
	// Orphaned blob is the blob which is in the blob store but not in the DB
	// UNION ALL query against many tables is slow. so if contents is given, using specific table
	repoName := getRepoName(contents)
	format := getFmtFromRepName(repoName)
	tableNames := getAssetTableNamesFromRepoNames(repoName)
	if len(repoName) > 0 && len(tableNames) == 0 {
		h.Log("WARN", fmt.Sprintf("Repsitory: %s does not exist in the database, so assuming %s as orphan", repoName, blobId))
		return "ORPHAN:" + repoName + "/" + format + "(NO_REPO)"
	}
	var repoNames []string
	if len(repoName) > 0 {
		repoNames = []string{repoName}
	}
	// Generating query to search the blobId from the blob_ref, and returning only asset_id column
	// Supporting only 3.47 and higher for performance (was adding ending %) (NEXUS-35934)
	// Not using common.BsName as can't trust blob store name in blob_ref, and may not work with group blob stores
	h.Log("DEBUG", fmt.Sprintf("repoNames: %v, format:%s", repoNames, format))
	// If blobId does not contain `@`, append '%' to match the old style blob IDs
	blobIdTmp := blobId
	if !common.NoDateBsLayout && !strings.Contains(blobId, "@") {
		blobIdTmp = blobId + "%"
	}
	query := genAssetBlobUnionQuery(tableNames, "asset_id", "blob_ref LIKE '%"+blobIdTmp+"' LIMIT 1", repoNames, format)
	if len(query) == 0 { // Mainly for unit test
		h.Log("WARN", fmt.Sprintf("query is empty for blobId: %s and tableNames: %v", blobId, tableNames))
		return "UNKNOWN1:" + repoName + "/" + format
	}
	// This query can take longer so not showing too many WARNs
	slowMs := int64(1000)
	if len(tableNames) > 0 {
		slowMs = int64(len(tableNames) * 300)
	}
	rows := lib.Query(query, db, slowMs)
	if rows == nil { // Mainly for unit test
		h.Log("WARN", "rows is nil for query: "+query)
		return "UNKNOWN2:" + repoName + "/" + format
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
			h.Log("DEBUG", fmt.Sprintf("blobId: %s row: %v", blobId, vals))
		}
		noRows = false
		break
	}
	if noRows {
		h.Log("WARN", fmt.Sprintf("Orphaned Blob Found:%s for repo:%s, format:%s", blobId, repoName, format))
		return "ORPHAN:" + repoName + "/" + format
	}
	return ""
}

func runParallel(chunks [][]string, apply func(string, *sql.DB), conc int) {
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
					apply(item, db)
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
	// As currently not supporting multiple blob store types, Client should be only one instance
	Client = bs_clients.GetClient(common.BsType)
	if len(common.BaseDir2) > 0 {
		Client2 = bs_clients.GetClient(common.BsType2)
	}
	// Currently only one DB object ...
	var db *sql.DB
	if len(common.DbConnStr) > 0 {
		db = lib.OpenDb(common.DbConnStr)
		defer db.Close()
	}

	// NOTE: when Query is set, BlobIdFile should be empty.
	if len(common.Query) > 0 {
		if len(common.BlobIDFIle) == 0 {
			var tempDir = os.TempDir()
			common.BlobIDFIle = filepath.Join(tempDir, "blob_ids_from_query.tsv")
			// If the *temp* file already exists, removing
			if _, err := os.Stat(common.BlobIDFIle); err == nil {
				h.Log("INFO", "Temp file "+common.BlobIDFIle+" exists. Deleting ...")
				err = os.Remove(common.BlobIDFIle)
				if err != nil {
					h.Log("ERROR", "Failed to remove the existing temp file: "+common.BlobIDFIle)
					panic(err)
				}
			}
			h.Log("DEBUG", "Query result will be saving into "+common.BlobIDFIle)
		} else {
			// If the file is not empty, exiting
			if info, err := os.Stat(common.BlobIDFIle); err == nil && info.Size() > 0 {
				panic("Currently -query and -rF {non empty file} can't be used togather")
			}
			// This is not so intuitive to use `-rF` for saving the query result, but probably better than adding another flag
			h.Log("INFO", "Query result will be *appending* into "+common.BlobIDFIle)
		}
		common.BlobIDFIleType = "DB" // assuming the query returns blobIDs (from blob_ref)
		lib.GetRows(common.Query, db, common.BlobIDFIle, 200)
	}

	startMs := time.Now().UnixMilli()

	// If the list of Blob IDs are provided, use it
	if len(common.BlobIDFIle) > 0 {
		// If Truth (src) is not set or Truth and BlobIDFile type are the same, reading this file as source
		if len(common.Truth) == 0 || (len(common.Truth) > 0 && common.Truth == common.BlobIDFIleType) {
			if common.BlobIDFIleType == "BS" && len(common.DbConnStr) > 0 {
				printHeader(common.SaveToPointer)
				h.Log("INFO", fmt.Sprintf("checkBlobIdDetailFromDB: path=%s, conc=%d", common.BlobIDFIle, common.Conc1))
				_ = h.StreamLines(common.BlobIDFIle, common.Conc1, checkBlobIdDetailFromDB)
			} else if common.BlobIDFIleType == "DB" && len(common.BaseDir) > 0 {
				printHeader(common.SaveToPointer)
				h.Log("INFO", fmt.Sprintf("checkBlobIdDetailFromBS: path=%s, conc=%d", common.BlobIDFIle, common.Conc1))
				_ = h.StreamLines(common.BlobIDFIle, common.Conc1, checkBlobIdDetailFromBS)
			} else {
				h.Log("DEBUG", fmt.Sprintf("No action was taken for path=%s (type:%s) as DbConnStr or BaseDir is missing", common.BlobIDFIle, common.BlobIDFIleType))
			}
			h.Elapsed(startMs, fmt.Sprintf("Completed. Listed: %d (checked: %d), Size: %d bytes", common.PrintedNum, common.CheckedNum, common.TotalSize), 0)
			return
		} else if len(common.Truth) > 0 && len(common.BlobIDFIleType) > 0 && common.Truth != common.BlobIDFIleType {
			panic("TODO: 'rF' is provided but 'rF' type:" + common.BlobIDFIleType + " does not match with 'src' type:" + common.Truth + ", so this file should be used to compare with the filelist result.")
			// TODO: implement this. Read the -src and check against the -rF file
		}
		// TODO: what should we do when BlobIDFIleType is empty?
		h.Log("INFO", fmt.Sprintf("No action was taken for path=%s (type:%s)", common.BlobIDFIle, common.BlobIDFIleType))
		return
	}

	if len(common.BaseDir) > 0 {
		printHeader(common.SaveToPointer)
		// If the Blob ID file is not provided, run per directory
		h.Log("INFO", fmt.Sprintf("Finding sub directories under %s with filter:%s, depth:%d (may take while)...", common.ContentPath, common.Filter4Path, common.MaxDepth))
		subDirs, err := Client.GetDirs(common.ContentPath, common.Filter4Path, common.MaxDepth)
		if err != nil {
			h.Log("ERROR", "Failed to list directories in "+common.ContentPath+" with filter: "+common.Filter4Path)
			panic(err)
		}
		chunks := h.Chunk(subDirs, 1) // 1 is for spawning the Go routine per subDir.
		h.Elapsed(startMs, fmt.Sprintf("GetDirs got %d directories", len(subDirs)), 200)
		if common.Debug2 {
			h.Log("DEBUG", fmt.Sprintf("Matched sub directories: %v", subDirs))
		}
		// Reset the start time for listing
		startMs = time.Now().UnixMilli()
		runParallel(chunks, listObjects, common.Conc1)
		// Always log this elapsed time by using 0 thresholdMs
		h.Elapsed(startMs, fmt.Sprintf("Completed. Listed: %d (checked: %d), Size: %d bytes", common.PrintedNum, common.CheckedNum, common.TotalSize), 0)
	}
	return
}
