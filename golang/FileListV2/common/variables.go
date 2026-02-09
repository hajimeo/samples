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
var NoDateBsLayout = false // To support new created date based blobstore layout
var TopN int64

var WithOwner bool   // AWS S3: Display owner
var WithTags bool    // AWS S3: Display tags
var S3PathStyle bool // AWS S3: Use Path-Style access

// Paths/Directories related. End with "/", so that no need to append  string(filepath.Separator)
var BaseDir = ""
var BaseDir2 = ""
var B2RepoName = ""
var B2NewBlobId = false
var B2PropsOnly = false
var BsType = ""     // 'file' for File, 's3' for AWS S3, 'az' for Azure, (TODO) 'gs' for Google
var BsType2 = ""    // 'file' for File, 's3' for AWS S3, 'az' for Azure, (TODO) 'gs' for Google
var Container = ""  // Azure: Container name, S3: Bucket name, Google: Bucket name
var Container2 = "" // Azure: Container name, S3: Bucket name, Google: Bucket name
var Prefix = ""
var Prefix2 = ""
var ContentPath = ""  // BaseDirWithPrefix + "/content/"
var ContentPath2 = "" // BaseDirWithPrefix + "/content/"
var Filter4Path = ""
var SaveToFile = ""
var SavePerDir = false
var SaveToPointer *os.File
var NotCompSubDirs = false
var WalkRecursive = true // Should not be exposed (testing purpose). Probably only for File type
var MaxDepth int         // `vol-YY/chap-XX/` vs. `YYYY/MM/DD/`

// Blob store related
var BsName = ""
var BlobIDFIle = ""
var BlobIDFIleType = ""
var RemoveDeleted bool
var BytesChk bool
var NoExtraChk bool
var WriteIntoStr = ""
var Query = ""
var QRepoNames = ""
var QRepoNameList []string
var RxSelect = regexp.MustCompile(`(?i)^ *SELECT ?.* +blob_id *,? *[^;]+;?$`) // Currently max only one ';'
var RxAnd = regexp.MustCompile(`(?i)^ *AND `)
var GetFile = ""
var GetTo = ""

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
var Filter4PropsNot = ""
var RxNot *regexp.Regexp // As Golang does not support negative lookahead (?!)
var Filter4BytesIncl = ""
var RxInclBytes *regexp.Regexp
var Filter4BytesExcl = ""
var RxExclBytes *regexp.Regexp

var DelDateFromStr = ""
var DelDateFromTS int64
var DelDateToStr = ""
var DelDateToTS int64
var ModDateFromStr = ""
var ModDateFromTS int64
var ModDateToStr = ""
var ModDateToTS int64

var RxDeletedDT = regexp.MustCompile("[^#]?deletedDateTime=([0-9]+)") // When this regex is used, *not* against the sorted one line text
var RxSizeByte = regexp.MustCompile(",size=([0-9]+)")                 // When this regex is used, against the sorted one line text
var RxDeleted = regexp.MustCompile("deleted=true")                    // should not use ^ as replacing one-line text
var RxRepoName = regexp.MustCompile(`(@Bucket\.repo-name=)([^\s\n\r,$]+)`)
var RxBlobName = regexp.MustCompile(`(@BlobStore\.blob-name=)([^\s\n\r,$]+)`)

// RxBlobRef : Not considering "space" in blobRef (TODO: may need to add more characters)
var RxBlobRef = regexp.MustCompile(`([^\s,'"]+@[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})`) // Not considering very old blobRef (using `:` or including nodeId)
var RxBlobRefNew = regexp.MustCompile(`([^\s,'"]+@[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}@\d{4}-\d{2}-\d{2}.\d{2}:\d{2})`)
var RxBlobId = regexp.MustCompile("[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}")
var RxBlobIdNew = regexp.MustCompile(`.*([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})@(\d{4})-(\d{2})-(\d{2}).(\d{2}):(\d{2}).*`)
var RxBlobIdNew2 = regexp.MustCompile(`/?([0-9]{4})/([0-9]{2})/([0-9]{2})/([0-9]{2})/([0-9]{2})/([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}).*`)
var RxVolDir = regexp.MustCompile(`\b/?vol-[0-9][0-9]/?$`)
var RxVolChapDir = regexp.MustCompile(`\b/?vol-[0-9][0-9]/chap-[0-9][0-9]/?$`)
var RxYyyyDir = regexp.MustCompile(`\b/?[0-9][0-9][0-9][0-9]/?$`)
var RxYyyyyMmDir = regexp.MustCompile(`\b/?[0-9][0-9][0-9][0-9]/[0-9][0-9]/?$`)
var RxYyyyyMmDdDir = regexp.MustCompile(`\b/?[0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]/?$`)
var RxYyyyyMmDdHhDir = regexp.MustCompile(`\b/?[0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]/[0-9][0-9]/?$`)
var RxYyyyyMmDdHhMmDir = regexp.MustCompile(`\b/?[0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]/[0-9][0-9]/[0-9][0-9]/?$`)

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
