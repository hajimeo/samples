/*
To store common variables
*/

package common

import (
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

// var WithBlobSize bool
var TopN int64
var WithOwner bool // AWS S3: Display owner
var WithTags bool  // AWS S3: Display tags

// Paths/Directories related. End with "/", so that no need to append  string(filepath.Separator)
var BaseDir = ""
var Filter4Path = ""
var ContentPath = "" // BaseDirWithPrefix + "/content/"
var SaveToFile = ""
var SaveToPointer *os.File
var MaxDepth = 3

// Blob store related
var BsName = ""
var BsType = "" // 'file' for File, 's3' for AWS S3, (TODO) 'az' for Azure, 'g' for Google
var BlobIDFIle = ""
var RemoveDeleted bool
var RepoNames = ""
var WriteIntoStr = ""

// Database related
var DbConnStr = ""
var Truth = ""

// Search related
var Filter4FileName = ""
var RxFilter4FileName *regexp.Regexp
var Filter4PropsIncl = ""
var Filter4PropsExcl = ""

var DelDateFromStr = ""
var DelDateFromTS int64
var DelDateToStr = ""
var DelDateToTS int64
var ModDateFromStr = ""
var ModDateFromTS int64
var ModDateToStr = ""
var ModDateToTS int64
var SizeFrom int // TODO: is this in use?
var SizeTo int
var RxIncl *regexp.Regexp
var RxExcl *regexp.Regexp
var RxDeletedDT, _ = regexp.Compile("[^#]?deletedDateTime=([0-9]+)")
var RxDeleted, _ = regexp.Compile("deleted=true") // should not use ^ as replacing one-line text
// var RxRepoName, _ = regexp.Compile("[^#]?@Bucket.repo-name=(.+)")
var RxBlobId, _ = regexp.Compile("[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}")

// Counters and misc.
var Conc1 int
var Conc2 int
var MaxKeys int // AWS S3: Integer value for Max Keys (<= 1000)
var StartTimestamp = time.Now().Unix()
var CheckedNum int64 = 0 // Atomic (maybe slower?)
var PrintedNum int64 = 0 // Atomic (maybe slower?)
var TotalSize int64 = 0  // Atomic (maybe slower?)
//var SlowMS int64 = 100
/*var (
	ObjectOutputs = make(map[string]interface{})
	mu            sync.RWMutex
)*/
