// Package lib: functions which are not *heavily* (a bit is OK) related to the main (business) logic and not blob store related functions.
package lib

import (
	"FileListV2/common"
	h "github.com/hajimeo/samples/golang/helpers"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

func GetSchema(urlString string) string {
	if strings.HasPrefix(urlString, string(filepath.Separator)) {
		return "file"
	}
	u, err := url.Parse(urlString)
	if err != nil {
		return "" // Return empty string if parsing fails
	}
	return u.Scheme
}

func GetContentPath(blobStoreWithPrefix string) string {
	bsType := GetSchema(blobStoreWithPrefix)
	h.Log("DEBUG", "GetContentPath - bsType:"+bsType)
	// Default (empty) is "file"
	if bsType == "" || bsType == "file" {
		if strings.Contains(blobStoreWithPrefix, "://") {
			blobStoreWithPrefix = strings.SplitAfter(blobStoreWithPrefix, "://")[1]
			h.Log("DEBUG", "GetContentPath - blobStoreWithPrefix:"+blobStoreWithPrefix)
		}
		return GetUpToContent(blobStoreWithPrefix)
	} else if bsType == "s3" {
		// TODO: If S3, common.BaseDir is an S3 bucket + prefix, assuming no need to include those in the content path (test needed)
		return common.CONTENT
	} else {
		h.Log("TODO", "Do something for Azure/Google etc. blob store content path")
		return ""
	}
}

func GetUpToContent(path string) string {
	path = strings.TrimSuffix(path, string(filepath.Separator))
	searchWord := string(filepath.Separator) + common.CONTENT + string(filepath.Separator)
	if strings.Contains(path, searchWord) {
		// 'dummy/content/sonatype-work/nexus3/blobs/default/content/vol-NN' -> 'dummy/content/sonatype-work/nexus3/blobs/default/content'
		lastIndex := strings.LastIndex(path, searchWord)
		lengthOfSearchWord := len(searchWord)
		return path[:lastIndex+lengthOfSearchWord-1]
	} else if strings.HasSuffix(path, string(filepath.Separator)+common.CONTENT) {
		// 'sonatype-work/nexus3/blobs/default/content' -> 'sonatype-work/nexus3/blobs/default/content'
		return path
	} else if len(path) == 0 {
		// '' -> 'content'
		return common.CONTENT
	} else {
		// 'sonatype-work/nexus3/blobs/default' -> 'sonatype-work/nexus3/blobs/default/content'
		return path + string(filepath.Separator) + common.CONTENT
	}
}

func OpenStdInOrFIle(path string) *os.File {
	f := os.Stdin
	if path != "-" {
		var err error
		f, err = os.Open(path)
		if err != nil {
			h.Log("ERROR", "path:"+path+" cannot be opened. "+err.Error())
			return nil
		}
	}
	return f
}

func SortToSingleLine(contents string) string {
	// To use simpler regex, sorting line and converting to single line first
	lines := strings.Split(contents, "\n")
	sort.Strings(lines)
	// Trimming unnecessary `,` (if "deleted=true" is removed, the properties file may have empty line)
	return strings.Trim(strings.Join(lines, ","), ",")
}
