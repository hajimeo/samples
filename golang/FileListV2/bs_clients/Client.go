package bs_clients

import "database/sql"

// Client : Like an OOP interface
type Client interface {
	//NewClient() Client	// like new Xxxxxxx() in OOP
	GetBsClient() interface{}
	ReadPath(string) (string, error)
	WriteToPath(string, string) error
	RemoveDeleted(string, string) error
	GetDirs(string, string, int) ([]string, error)
	ListObjects(string, string, *sql.DB, func(interface{}, interface{}, *sql.DB)) int64
}
