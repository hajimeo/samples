/* DEPRECATED: Use ../java/blobpath, because not tested
 *
 * 	go build -o blobdummygen_Darwin blobdummygen.go
 * 	env GOOS=linux GOARCH=amd64 go build -o blobdummygen_Linux blobdummygen.go
 */
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"math"
	"os"
	"regexp"
	"strings"
)

func usage() {
	fmt.Println(`
*** DEPRECATED ***
Generate a dummy .property and .byte files

DOWNLOAD and INSTALL:
    sudo curl -o /usr/local/bin/blobdummygen -L https://github.com/hajimeo/samples/raw/master/misc/blobdummygen_$(uname)
    sudo chmod a+x /usr/local/bin/blobdummygen
    
USAGE EXAMPLE:
    cat '{"blob_ref":"default@9C281...:56df5d9d-a...","created_by":"admin","size":1461,"repository_name":"maven-releases","blob_created":"2020-01-23 01:46:07","created_by_ip":"192.168.1.31","content_type":"application/java-archive","name":"com/example/nexus-proxy/1.1/nexus-proxy-1.1.jar","sha1":"9c024..."}' | blobdummygen [out_dir]
`)
}

/*** Implementing Java String.hashCode() ***/
func _myHashCode(s string) int32 {
	h := int32(0)
	// position, rune
	for _, c := range s {
		h = (31 * h) + int32(c)
		//fmt.Printf("%d\n", h)
	}
	return h
}

/*** End of Java String.hashCode() ***/

func blobdir(blobId string) string {
	// org.sonatype.nexus.blobstore.VolumeChapterLocationStrategy#location
	hashInt := _myHashCode(blobId)
	vol := math.Abs(math.Mod(float64(hashInt), 43)) + 1
	chap := math.Abs(math.Mod(float64(hashInt), 47)) + 1
	return fmt.Sprintf("vol-%02d/chap-%02d", int(vol), int(chap))
}

func fullpath(outDir string, blobName string, path string) string {
	outDir = strings.Trim(outDir, "/")
	blobName = strings.Trim(blobName, "/")
	path = strings.Trim(path, "/")
	return fmt.Sprintf("%s/%s/content/%s", outDir, blobName, path)
}

func createDummyBlob(path string, size int64) {
	f, err := os.Create(path)
	if err != nil {
		fmt.Println(err)
		return
	}

	if err := f.Truncate(size); err != nil {
		fmt.Println(err)
		return
	}
}

func main() {
	if len(os.Args) > 1 {
		if os.Args[1] == "-h" || os.Args[1] == "--help" {
			usage()
			os.Exit(0)
		}
	}

	outDir := "."
	if len(os.Args) > 2 {
		outDir = os.Args[2]
	}
	useRealSzie := false
	if len(os.Args) > 2 {
		if os.Args[3] == "--use-real-size" {
			useRealSzie = true
		}
	}

	BLOB_REF_PATTERN := regexp.MustCompile(`([^@]+)@([^:]+):(.*)`)
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		var js map[string]interface{}
		err := json.Unmarshal([]byte(scanner.Text()), &js)
		if err != nil {
			fmt.Println(err)
			os.Exit(3)
		}
		//fmt.Println(scanner.Text())
		blobRef := fmt.Sprintf("%s", js["blob_ref"])
		matches := BLOB_REF_PATTERN.FindStringSubmatch(blobRef)
		blobName := matches[1]
		blobId := matches[3]
		path := blobdir(blobId)
		finalPath := fullpath(outDir, blobName, path)
		// TODO: creationTime should be Unix Timestamp with milliseconds
		// TODO: The first line (modified date) is using last_updated which does not have milliseconds and timezone
		// TODO: The second line does not match with the first line
		propsStr := fmt.Sprintf(
			`#%s,000+0000
#Mon Jan 01 00:00:00 UTC 2020
@BlobStore.created-by=%s
size=%d
@Bucket.repo-name=%s
creationTime=%s
@BlobStore.created-by-ip=%s
@BlobStore.content-type=%s
@BlobStore.blob-name=%s
sha1=%s
`, js["last_updated"], js["created_by"], int64(int(js["size"].(float64))), js["repository_name"], js["blob_created"], js["created_by_ip"], js["content_type"], js["name"], js["sha1"])
		os.MkdirAll(finalPath, os.ModePerm)
		err2 := ioutil.WriteFile(finalPath+"/"+blobId+".properties", []byte(propsStr), 0644)
		if err2 != nil {
			fmt.Println(err2)
			os.Exit(4)
		}

		blobSize := int64(0)
		if useRealSzie {
			blobSize = int64(int(js["size"].(float64)))
		}
		// It's OK if fails
		createDummyBlob(finalPath+"/"+blobId+".bytes", blobSize)
		fmt.Fprintln(os.Stderr, "Created "+finalPath+"/"+blobId+".properties")
	}
}
