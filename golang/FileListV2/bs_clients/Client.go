package bs_clients

import (
	"FileListV2/common"
	"database/sql"
	"time"
)

// Client : Like an OOP interface
type Client interface {
	// ReadPath : Read the contents of the file path
	ReadPath(string) (string, error)
	// WriteToPath : Write the contents to the file path
	WriteToPath(string, string) error
	// RemoveDeleted : Remove the deleted=true line
	RemoveDeleted(string, string) error
	// GetDirs : Get the directories in the path
	GetDirs(string, string, int) ([]string, error)
	// ListObjects : List the objects in the path. DB is used in the func
	ListObjects(string, *sql.DB, func(PrintLineArgs) bool) int64
	// GetFileInfo : Get the information (metadata) of the file path
	GetFileInfo(string) (BlobInfo, error)
	// Convert2BlobInfo : Convert the object into BlobInfo object
	Convert2BlobInfo(interface{}) BlobInfo
}

type BlobInfo struct {
	Path    string
	ModTime time.Time
	Size    int64
	Owner   string
	Tags    string // JSON string
}

type PrintLineArgs struct {
	Path    interface{}
	BInfo   BlobInfo
	DB      *sql.DB
	SaveDir string
}

func GetClient() Client {
	if common.BsType == "s3" {
		return &S3Client{}
	}
	if common.BsType == "az" {
		return &AzClient{}
	}
	// TODO: add more types
	// Default is FileClient
	return &FileClient{}
}
