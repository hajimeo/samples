/* Trying to do same as java.lang.String.hashCode
 *
 * go build -o ../misc/blobpath_Darwin blobpath.go && env GOOS=linux GOARCH=amd64 go build -o ../misc/blobpath_Linux blobpath.go
 */
package main

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
)

func usage() {
	fmt.Println(`
Generate Nexus blob store path (from <blob name>/content/)

DOWNLOAD and INSTALL:
    sudo curl -o /usr/local/bin/blobpath -L https://github.com/hajimeo/samples/raw/master/misc/blobpath_$(uname)
    sudo chmod a+x /usr/local/bin/blobpath
    
USAGE EXAMPLE:
    $ blobpath "83e59741-f05d-4915-a1ba-7fc789be34b1"
    vol-31/chap-32/83e59741-f05d-4915-a1ba-7fc789be34b1.properties

    $ blobpath "83e59741-f05d-4915-a1ba-7fc789be34b1" ".bytes"
    vol-31/chap-32/83e59741-f05d-4915-a1ba-7fc789be34b1.bytes

    $ blobpath "83e59741-f05d-4915-a1ba-7fc789be34b1" ".bytes" "/nexus-data/blobs/default/content/"
    /nexus-data/blobs/default/content/vol-31/chap-32/83e59741-f05d-4915-a1ba-7fc789be34b1.bytes`)
}

func myHashCode(s string) int32 {
	h := int32(0)
	// position, rune
	for _, c := range s {
		h = (31 * h) + int32(c)
		//fmt.Printf("%d\n", h)
	}
	return h
}

func main() {
	if len(os.Args) == 1 || os.Args[1] == "-h" || os.Args[1] == "--help" {
		usage()
		os.Exit(0)
	}

	blobId := os.Args[1]
	ext := ".properties"
	if len(os.Args) > 2 {
		ext = os.Args[2]
	}
	pathPfx := ""
	if len(os.Args) > 3 {
		pathPfx = os.Args[3]
	}
	hashInt := myHashCode(blobId)
	// org.sonatype.nexus.blobstore.VolumeChapterLocationStrategy#location
	vol := math.Abs(math.Mod(float64(hashInt), 43)) + 1
	chap := math.Abs(math.Mod(float64(hashInt), 47)) + 1
	path := filepath.Join(pathPfx, fmt.Sprintf("vol-%02d", int(vol)), fmt.Sprintf("chap-%02d", int(chap)), blobId+ext)
	fmt.Println(path)
}
