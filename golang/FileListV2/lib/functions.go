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
	u, err := url.Parse(urlString)
	if err != nil {
		return "" // Return empty string if parsing fails
	}
	return u.Scheme
}

func GetContentPath(blobStoreWithPrefix string) string {
	if common.BsType == "s3" {
		// TODO: If S3, common.BaseDir is an S3 bucket + prefix, assuming no need to include those in the content path (test needed)
		return common.CONTENT
	} else if common.BsType == "file" || common.BsType == "" {
		return GetUpToContent(blobStoreWithPrefix)
	} else {
		h.Log("TODO", "Do something for Azure/Google etc. blob store content path")
		return ""
	}
}

func GetUpToContent(blobStoreWithPrefix string) string {
	blobStoreWithPrefix = strings.TrimSuffix(blobStoreWithPrefix, string(filepath.Separator))
	searchWord := string(filepath.Separator) + common.CONTENT + string(filepath.Separator)
	if strings.Contains(blobStoreWithPrefix, searchWord) {
		// 'dummy/content/sonatype-work/nexus3/blobs/default/content/vol-NN' -> 'dummy/content/sonatype-work/nexus3/blobs/default/content'
		lastIndex := strings.LastIndex(blobStoreWithPrefix, searchWord)
		lengthOfContent := len(searchWord)
		return blobStoreWithPrefix[:lastIndex+lengthOfContent-1]
	} else if strings.HasSuffix(blobStoreWithPrefix, string(filepath.Separator)+common.CONTENT) {
		// 'sonatype-work/nexus3/blobs/default/content' -> 'sonatype-work/nexus3/blobs/default/content'
		return blobStoreWithPrefix
	} else if len(blobStoreWithPrefix) == 0 {
		// '' -> 'content'
		return common.CONTENT
	} else {
		// 'sonatype-work/nexus3/blobs/default' -> 'sonatype-work/nexus3/blobs/default/content'
		return blobStoreWithPrefix + string(filepath.Separator) + common.CONTENT
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
