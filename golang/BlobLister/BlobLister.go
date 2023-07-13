package BlobLister

import "fmt"

func usage() {
	fmt.Println(`
List .properties and .bytes files as *Tab* Separated Values (Path LastModified Size).
This tool can be used for:
	- Search and list blobs with a filter string
	- Find orphaned blobs (exist in DB but no real file)
	- Find dead blobs (exist in a blob store but not in the DB)
    
HOW TO and USAGE EXAMPLES:
    https://github.com/hajimeo/samples/blob/master/golang/FileList/README.md`)
	fmt.Println("")
}
