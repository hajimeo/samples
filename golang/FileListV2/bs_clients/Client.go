package bs_clients

import (
	"database/sql"
	"time"
)

// Client : Like an OOP interface
type Client interface {
	//NewClient() Client	// like new Xxxxxxx() in OOP
	GetBsClient() interface{}
	ReadPath(string) (string, error)
	WriteToPath(string, string) error
	RemoveDeleted(string, string) error
	GetDirs(string, string, int) ([]string, error)
	ListObjects(string, string, *sql.DB, func(interface{}, BlobInfo, *sql.DB)) int64
	Convert2BlobInfo(interface{}) BlobInfo
}

type BlobInfo struct {
	Path     string
	ModTime  time.Time
	Size     int64
	BlobSize int64 // This is updated when .bytes is read
	Owner    string
	Tags     map[string]string
}
