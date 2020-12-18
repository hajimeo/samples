/*
 * TODO: sometimes the result is not same as java.hashCode()
 * 
 * @see: https://gist.github.com/giautm/d79994acd796f3065903eccbc8d6e09b
 * 	env GOOS=linux GOARCH=amd64 go build blobpath.go
 * 	sudo curl -o /usr/local/bin/blobpath -L https://github.com/hajimeo/samples/raw/master/misc/blobpath_$(uname)
 * 	sudo chmod a+x /usr/local/bin/blobpath
 */
package main

import (
	"fmt"
	"hash"
	"math"
	"os"
)

const Size = 4

func NewHash() hash.Hash32 {
	var s sum32 = 0
	return &s
}

type sum32 uint32

func (sum32) BlockSize() int  { return 1 }
func (sum32) Size() int       { return Size }
func (h *sum32) Reset()       { *h = 0 }
func (h sum32) Sum32() uint32 { return uint32(h) }
func (h sum32) Sum(in []byte) []byte {
	s := h.Sum32()
	return append(in, byte(s>>24), byte(s>>16), byte(s>>8), byte(s))
}
func (h *sum32) Write(p []byte) (n int, err error) {
	s := h.Sum32()
	for _, pp := range p {
		s = 31*s + uint32(pp)
	}
	*h = sum32(s)
	return len(p), nil
}
func hashCode(s string) uint32 {
	h := NewHash()
	h.Write([]byte(s))
	return h.Sum32()
}
func main() {
	blobId := os.Args[1]
	ext := ".properties"
	if len(os.Args) > 2 {
		ext = os.Args[2]
	}
	hashInt := hashCode(blobId)
	// org.sonatype.nexus.blobstore.VolumeChapterLocationStrategy#location
	vol := math.Abs(math.Mod(float64(hashInt), 43)) + 1
	chap := math.Abs(math.Mod(float64(hashInt), 47)) + 1
	fmt.Printf("vol-%02d/chap-%02d/%s%s\n", int(vol), int(chap), blobId, ext)
}
