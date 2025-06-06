/*
To store common variables
*/

package common

import (
	"database/sql"
	"os"
	"regexp"
	"time"
)

var Debug bool
var Debug2 bool // For AWS SDK

//var DryRun bool

const CONTENT = "content"
const PROPERTIES = "properties"
const PROP_EXT = "." + PROPERTIES
const BYTES = "bytes"
const BYTES_EXT = "." + BYTES
const SEP = "	" // Tab separator (should this be changeable?)

// Display / output related
var NoHeader bool
var WithProps bool
var DateBsLayout = false // To support new created date based blobstore layout

// var WithBlobSize bool
var TopN int64
var WithOwner bool // AWS S3: Display owner
var WithTags bool  // AWS S3: Display tags

// Paths/Directories related. End with "/", so that no need to append  string(filepath.Separator)
var BaseDir = ""
var Filter4Path = ""
var ContentPath = "" // BaseDirWithPrefix + "/content/"
var SaveToFile = ""
var SavePerDir = false
var SaveToPointer *os.File
var MaxDepth = 5 // `vol-YY/chap-XX/` vs. `YYYY/MM/DD/hh/mm/`

// Blob store related
var BsName = ""
var BsType = "" // 'file' for File, 's3' for AWS S3, (TODO) 'az' for Azure, 'g' for Google
var BlobIDFIle = ""
var BlobIDFIleType = ""
var RemoveDeleted bool
var WriteIntoStr = ""
var Query = ""
var RxSelect = regexp.MustCompile(`(?i)^ *SELECT .*(?:\A|\z|\s)blob_id(?:\A|\z|\s)[^;]+;?$`)
var RxAnd = regexp.MustCompile(`(?i)^ *AND `)
var Container = "" // Azure: Container name, S3: Bucket name
var Prefix = ""

// Database related
var DbConnStr = ""
var DB *sql.DB
var Truth = ""
var Repo2Fmt map[string]string
var AssetTables []string

// Search related
var Filter4FileName = ""
var RxFilter4FileName *regexp.Regexp
var Filter4PropsIncl = ""
var RxIncl *regexp.Regexp
var Filter4PropsExcl = ""
var RxExcl *regexp.Regexp

var DelDateFromStr = ""
var DelDateFromTS int64
var DelDateToStr = ""
var DelDateToTS int64
var ModDateFromStr = ""
var ModDateFromTS int64
var ModDateToStr = ""
var ModDateToTS int64

var RxDeletedDT = regexp.MustCompile("[^#]?deletedDateTime=([0-9]+)")
var RxDeleted = regexp.MustCompile("deleted=true") // should not use ^ as replacing one-line text
var RxRepoName = regexp.MustCompile(`[^#]?@Bucket\.repo-name=([^,$]+)`)
var RxBlobId = regexp.MustCompile("[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}")

// Counters and misc.
var Conc1 int
var Conc2 int
var MaxKeys = 1000 // AWS S3: Integer value for Max Keys (<= 1000)
var StartTimestamp = time.Now().Unix()
var CheckedNum int64 = 0 // Atomic (maybe slower?)
var PrintedNum int64 = 0 // Atomic (maybe slower?)
var TotalSize int64 = 0  // Atomic (maybe slower?)
var SlowMS int64 = 1000
var CacheSize int = 1000
