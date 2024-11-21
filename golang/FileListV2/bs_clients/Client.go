package bs_clients

import (
	"database/sql"
	"time"
)

// Client : Like an OOP interface
type Client interface {
	GetBsClient() interface{}
	ReadPath(string) (string, error)
	WriteToPath(string, string) error
	RemoveDeleted(string, string) error
	GetDirs(string, string, int) ([]string, error)
	ListObjects(string, *sql.DB, func(interface{}, BlobInfo, *sql.DB)) int64
	Convert2BlobInfo(interface{}) BlobInfo
}

type BlobInfo struct {
	Path    string
	ModTime time.Time
	Size    int64
	Owner   string
	Tags    map[string]string
}
