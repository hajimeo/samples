/* Trying to do same as java.lang.String.hashCode
 *
 * go build -o ../misc/blobpath_Darwin blobpath.go && env GOOS=linux GOARCH=amd64 go build -o ../misc/blobpath_Linux blobpath.go; date
 */
package main

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

func usage() {
	fmt.Println(`
Generate Nexus blob store path (from <blob name>/content/)
    blobpath <blobId-like-string> <extention> <blobstore-content-dir> <if-missing-only>

DOWNLOAD and INSTALL:
    sudo curl -o /usr/local/bin/blobpath -L https://github.com/hajimeo/samples/raw/master/misc/blobpath_$(uname)
    sudo chmod a+x /usr/local/bin/blobpath
    
USAGE EXAMPLE:
    $ blobpath "83e59741-f05d-4915-a1ba-7fc789be34b1"
    vol-31/chap-32/83e59741-f05d-4915-a1ba-7fc789be34b1.properties

    $ blobpath "83e59741-f05d-4915-a1ba-7fc789be34b1" ".bytes"
    vol-31/chap-32/83e59741-f05d-4915-a1ba-7fc789be34b1.bytes

    $ blobpath "83e59741-f05d-4915-a1ba-7fc789be34b1" ".properties" "/nexus-data/blobs/default/content/"
    /nexus-data/blobs/default/content/vol-31/chap-32/83e59741-f05d-4915-a1ba-7fc789be34b1.properties

    $ cat /tmp/blobIds.out | xargs -I{} -P3 ./blobpath "{}" "" "/nexus-data/blobs/default/content/" "Y"
    /nexus-data/blobs/default/content/vol-31/chap-32/83e59741-f05d-4915-a1ba-7fc789be34b1.properties
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
	if len(blobId) > 36 {
		BLOB_ID_PATTERN := regexp.MustCompile(`.*([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}).*`)
		matches := BLOB_ID_PATTERN.FindStringSubmatch(blobId)
		blobId = matches[1]
	}
	ext := ".properties"
	if len(os.Args) > 2 {
		ext = os.Args[2]
	}
	pathPfx := ""
	if len(os.Args) > 3 {
		pathPfx = os.Args[3]
	}
	isMissingOnly := false
	if len(os.Args) > 4 && strings.ToLower(os.Args[4]) == "y" {
		isMissingOnly = true
	}

	hashInt := myHashCode(blobId)
	// org.sonatype.nexus.blobstore.VolumeChapterLocationStrategy#location
	vol := math.Abs(math.Mod(float64(hashInt), 43)) + 1
	chap := math.Abs(math.Mod(float64(hashInt), 47)) + 1
	path := filepath.Join(pathPfx, fmt.Sprintf("vol-%02d", int(vol)), fmt.Sprintf("chap-%02d", int(chap)), blobId+ext)

	if isMissingOnly {
		if len(ext) == 0 {
			// If no extension specified, check ".properties" and ".bytes" both
			if _, err := os.Stat(path + ".properties"); err != nil {
				fmt.Println(path + ".properties")
			}
			if _, err := os.Stat(path + ".bytes"); err != nil {
				fmt.Println(path + ".bytes")
			}
		} else if _, err := os.Stat(path); err != nil {
			fmt.Println(path)
		}
	} else {
		fmt.Println(path)
	}
}
