/* Trying to do same as java.lang.String.hashCode
 *
 * 	go build -o ../misc/blobpath_Darwin blobpath.go
 * 	env GOOS=linux GOARCH=amd64 go build -o ../misc/blobpath_Linux blobpath.go
 * 	sudo curl -o /usr/local/bin/blobpath -L https://github.com/hajimeo/samples/raw/master/misc/blobpath_$(uname)
 * 	sudo chmod a+x /usr/local/bin/blobpath
 */
package main

import (
	"fmt"
	"math"
	"os"
)

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
	blobId := os.Args[1]
	ext := ".properties"
	if len(os.Args) > 2 {
		ext = os.Args[2]
	}
	hashInt := myHashCode(blobId)
	// org.sonatype.nexus.blobstore.VolumeChapterLocationStrategy#location
	vol := math.Abs(math.Mod(float64(hashInt), 43)) + 1
	chap := math.Abs(math.Mod(float64(hashInt), 47)) + 1
	fmt.Printf("vol-%02d/chap-%02d/%s%s\n", int(vol), int(chap), blobId, ext)
}
