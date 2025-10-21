package bs_clients

import (
	"database/sql"
	"fmt"
	"github.com/pkg/errors"
	"os"
	"path/filepath"
	"time"
)

// Client : Like an OOP interface
type Client interface {
	// GetDirs : Get the directories in the path
	GetDirs(string, string, int) ([]string, error)
	// ListObjects : List the objects in the path. DB is used in the func
	ListObjects(string, *sql.DB, func(PrintLineArgs) bool) int64
	// ReadPath : Read the contents of the file path
	ReadPath(string) (string, error)
	// WriteToPath : Write the contents to the file path
	WriteToPath(string, string) error
	// GetPath : Get the path and copy it to the local path
	GetPath(string, string) error
	// GetFileInfo : Get/Retrieve the information (metadata) of the file path / key
	GetFileInfo(string) (BlobInfo, error)
	// Convert2BlobInfo : Convert the object into BlobInfo object
	Convert2BlobInfo(interface{}) BlobInfo
	// RemoveDeleted : Remove the deleted=true line. This is not a right location but for S3
	RemoveDeleted(string, string) error
	// GetReader : Get the reader for the path. Used for io.Copy
	GetReader(string) (interface{}, error)
	// GetWriter : Get the writer for the path. Used for io.Copy. Make sure this method creates subdirectories
	GetWriter(string) (interface{}, error)
}

type BlobInfo struct {
	Path    string
	ModTime time.Time
	Size    int64
	Owner   string
	Tags    string // JSON string
	Error   bool
}

type PrintLineArgs struct {
	Path    string
	BInfo   BlobInfo
	DB      *sql.DB
	SaveDir string
}

func GetClient(bsType string) Client {
	if bsType == "s3" {
		return &S3Client{}
	}
	if bsType == "az" {
		return &AzClient{}
	}
	//if bsType == "gs" {
	//	return &GcClient{}
	//}
	// TODO: add more types
	// Default is FileClient
	return &FileClient{}
}

func CreateLocalFile(localPath string) (*os.File, error) {
	if len(localPath) == 0 {
		err2 := fmt.Errorf("localPath is not provided")
		return nil, err2
	}

	if _, err := os.Stat(localPath); !errors.Is(err, os.ErrNotExist) {
		err2 := fmt.Errorf("localPath %s already exists", localPath)
		return nil, err2
	}

	err := os.MkdirAll(filepath.Dir(localPath), os.ModePerm)
	if err != nil {
		err2 := fmt.Errorf("failed to make directory: %s with error: %s", localPath, err.Error())
		return nil, err2
	}

	outFile, err := os.Create(localPath)
	if err != nil {
		err2 := fmt.Errorf("failed to open: %s with error: %s", localPath, err.Error())
		return nil, err2
	}

	return outFile, err
}
