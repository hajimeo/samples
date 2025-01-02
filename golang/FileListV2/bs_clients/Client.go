package bs_clients

import (
	"FileListV2/common"
	"database/sql"
	"time"
)

// Client : Like an OOP interface
type Client interface {
	ReadPath(string) (string, error)
	WriteToPath(string, string) error
	RemoveDeleted(string, string) error
	GetDirs(string, string, int) ([]string, error)
	ListObjects(string, *sql.DB, func(interface{}, BlobInfo, *sql.DB)) int64
	GetFileInfo(string) (BlobInfo, error)
	Convert2BlobInfo(interface{}) BlobInfo
}

type BlobInfo struct {
	Path    string
	ModTime time.Time
	Size    int64
	Owner   string
	Tags    string // JSON string
}

func GetClient() Client {
	if common.BsType == "s3" {
		return &S3Client{}
	}
	// TODO: add more types
	// Default is FileClient
	return &FileClient{}
}
