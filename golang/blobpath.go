/*
Doing same as org.sonatype.nexus.blobstore.VolumeChapterLocationStrategy#location and java.lang.String.hashCode

To build:

	GO_SKIP_TESTS=Y goBuild blobpath.go
*/
package main

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"regexp"
)

func usage() {
	fmt.Println(`
Generate Nexus blob store path (from <blob name>/content/)
    blobpath <blobId-like-string> <extension> <blobstore-content-dir> <if-missing-only>

DOWNLOAD and INSTALL:
    sudo curl -o /usr/local/bin/blobpath -L https://github.com/hajimeo/samples/raw/master/misc/blobpath_$(uname)_$(uname -m)
    sudo chmod a+x /usr/local/bin/blobpath
    
USAGE EXAMPLE:
    $ blobpath "6c1d3423-ecbc-4c52-a0fe-01a45a12883a@2025-08-14T02:44"
    2025/08/14/02/44/6c1d3423-ecbc-4c52-a0fe-01a45a12883a.properties

    $ blobpath "83e59741-f05d-4915-a1ba-7fc789be34b1"
    vol-31/chap-32/83e59741-f05d-4915-a1ba-7fc789be34b1.properties

    $ blobpath "83e59741-f05d-4915-a1ba-7fc789be34b1" ".bytes"
    vol-31/chap-32/83e59741-f05d-4915-a1ba-7fc789be34b1.bytes

    $ blobpath "83e59741-f05d-4915-a1ba-7fc789be34b1" ".properties" "/nexus-data/blobs/default/content/"
    /nexus-data/blobs/default/content/vol-31/chap-32/83e59741-f05d-4915-a1ba-7fc789be34b1.properties

	# Report if .properties file is missing ("Y" in the 4th argument)
	$ psql -d nxrm3pg -c "\copy (SELECT REGEXP_REPLACE(ab.blob_ref, '.+@', '') as blobId FROM nuget_asset a JOIN nuget_asset_blob ab USING (asset_blob_id) JOIN nuget_content_repository cr USING (repository_id) JOIN repository r ON r.id = cr.config_repository_id and r.name IN ('nuget-proxy') WHERE ab.blob_created < (NOW() - interval '14 days') ORDER BY 1) to '/tmp/blobIds.out' csv;"
    $ cat /tmp/blobIds.out | xargs -I{} -P3 ./blobpath "{}" "" "/nexus-data/blobs/default/content/" "Y"
    /nexus-data/blobs/default/content/vol-31/chap-32/83e59741-f05d-4915-a1ba-7fc789be34b1.properties

ADVANCED USAGE:
NOTE: using xxxxxx@ as blobStore ID/name is not 100% accurate
	rg -s '\bblob_?[rR]ef[:=]([^@]+)@.*(([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})),' -o -r 'blobpath "$2" ".properties" "$1@content"' deadBlobResult-20*.json > ./eval.sh
	bash -v ./eval.sh > ./paths.tmp
    #rg -o '^.+@' ./paths.tmp | sort | uniq -c
	sed 's;^default@;/opt/sonatype/sonatype-work/blobs/default/;g' ./paths.tmp > final_paths.out
	sed -e 's;^Maven@;maven/;g' -e 's;^npm-blobstore@;npm/;g' ./paths.tmp > final_paths.out`)
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

func genPath(blobIdLikeString string, pathPfx string, ext string) string {
	NewBlobIdPattern := regexp.MustCompile(`.*([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})@(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}).*`)
	matches := NewBlobIdPattern.FindStringSubmatch(blobIdLikeString)
	if len(matches) > 6 {
		// 6c1d3423-ecbc-4c52-a0fe-01a45a12883a@2025-08-14T02:44
		// 2025/08/14/02/44/6c1d3423-ecbc-4c52-a0fe-01a45a12883a.properties
		return filepath.Join(pathPfx, matches[2], matches[3], matches[4], matches[5], matches[6], matches[1]+ext)
	}
	NewBlobIdPattern2 := regexp.MustCompile(`/?([0-9]{4})/([0-9]{2})/([0-9]{2})/([0-9]{2})/([0-9]{2})/([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}).*`)
	matches = NewBlobIdPattern2.FindStringSubmatch(blobIdLikeString)
	if len(matches) > 6 {
		return filepath.Join(pathPfx, matches[1], matches[2], matches[3], matches[4], matches[5], matches[6]+ext)
	}
	BlobIdPattern := regexp.MustCompile(`.*([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}).*`)
	matches = BlobIdPattern.FindStringSubmatch(blobIdLikeString)
	if matches == nil || len(matches) < 2 {
		return ""
	}

	hashInt := myHashCode(matches[1])
	// org.sonatype.nexus.blobstore.VolumeChapterLocationStrategy#location
	vol := math.Abs(math.Mod(float64(hashInt), 43)) + 1
	chap := math.Abs(math.Mod(float64(hashInt), 47)) + 1
	return filepath.Join(pathPfx, fmt.Sprintf("vol-%02d", int(vol)), fmt.Sprintf("chap-%02d", int(chap)), matches[1]+ext)
}

func main() {
	if len(os.Args) == 1 || os.Args[1] == "-h" || os.Args[1] == "--help" {
		usage()
		os.Exit(0)
	}

	blobId := os.Args[1]
	if len(blobId) < 36 {
		fmt.Fprintf(os.Stderr, "Invalid blobId: %s\n", blobId)
		os.Exit(1)
	}
	ext := ""
	if len(os.Args) > 2 {
		ext = os.Args[2]
	}
	pathPfx := ""
	if len(os.Args) > 3 {
		pathPfx = os.Args[3]
	}
	isMissingPropertiesOnly := false
	isMissingOnly := false
	if len(os.Args) > 4 {
		if os.Args[4] == "y" {
			isMissingOnly = true
			isMissingPropertiesOnly = true
			fmt.Fprintf(os.Stderr, "Missing Properties (no Bytes) check is enabled\n")
		} else if os.Args[4] == "Y" {
			isMissingOnly = true
			fmt.Fprintf(os.Stderr, "Missing Properties & Bytes check is enabled\n")
		}
	}

	path := genPath(blobId, pathPfx, ext)
	if path == "" {
		fmt.Fprintf(os.Stderr, "Invalid blobId format: %s\n", blobId)
		os.Exit(1)
	}

	if isMissingOnly {
		if len(ext) == 0 {
			// If no extension specified, check ".properties" and ".bytes" both
			if _, err := os.Stat(path + ".properties"); err != nil {
				fmt.Println(path + ".properties")
				if isMissingPropertiesOnly == false {
					if _, err := os.Stat(path + ".bytes"); err != nil {
						fmt.Println(path + ".bytes")
					}
				}
			}
		} else if _, err := os.Stat(path); err != nil {
			fmt.Println(path)
		}
	} else {
		if len(ext) == 0 {
			fmt.Println(path + ".properties")
			fmt.Println(path + ".bytes")
		} else {
			fmt.Println(path)
		}
	}
}
