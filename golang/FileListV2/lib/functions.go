// Package lib: functions which are not *heavily* (a bit is OK) related to the main (business) logic and not blob store related functions.
package lib

import (
	"FileListV2/common"
	h "github.com/hajimeo/samples/golang/helpers"
	"net/url"
	"path/filepath"
	"sort"
	"strings"
)

func GetSchema(uri string) string {
	if strings.HasPrefix(uri, string(filepath.Separator)) {
		return "file"
	}
	u, err := url.Parse(uri)
	if err != nil {
		return "" // Return empty string if parsing fails
	}
	return u.Scheme
}

func GetContainerAndPrefix(uri string) (string, string) {
	// Get the Container/Bucket/hostname and prefix from URI
	u, err := url.Parse(uri)
	if err != nil {
		h.Log("ERROR", "GetHostnameAndPrefix - Error parsing URI: "+uri)
		return "", ""
	}
	prefix := u.Path
	if prefix != "" {
		prefix = GetUpToContent(prefix)
		prefix = strings.TrimPrefix(prefix, "/")
		prefix = strings.TrimSuffix(prefix, "/"+common.CONTENT)
	}
	return u.Hostname(), prefix
}

func GetContentPath(blobStoreWithPrefix string) string {
	bsType := GetSchema(blobStoreWithPrefix)
	h.Log("DEBUG", "(GetContentPath) bsType:"+bsType)
	if strings.Contains(blobStoreWithPrefix, "://") {
		blobStoreWithPrefix = strings.SplitAfter(blobStoreWithPrefix, "://")[1]
		h.Log("DEBUG", "(GetContentPath) blobStoreWithPrefix:"+blobStoreWithPrefix)
	}
	// Default (empty) is "file"
	if bsType == "" || bsType == "file" {
		return GetUpToContent(blobStoreWithPrefix)
	} else if bsType == "s3" || bsType == "az" {
		contentPath := GetUpToContent(blobStoreWithPrefix)
		if len(common.Container) == 0 {
			return contentPath
		}
		return strings.SplitAfter(contentPath, common.Container+"/")[1]
	} else {
		h.Log("TODO", "Do something for Google etc. blob store content path")
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

func GetAfterContent(path string) string {
	path = strings.TrimSuffix(path, string(filepath.Separator))
	searchWord := string(filepath.Separator) + common.CONTENT + string(filepath.Separator)
	if strings.Contains(path, searchWord) {
		// Get string after 'content/'
		// 'dummy/content/sonatype-work/nexus3/blobs/default/content/vol-NN' -> 'vol-NN'
		lastIndex := strings.LastIndex(path, searchWord)
		lengthOfSearchWord := len(searchWord)
		return path[lastIndex+lengthOfSearchWord:]
	}
	return ""
}

func GetPathWithoutExt(path string) string {
	return path[:len(path)-len(filepath.Ext(path))]
}

func SortToSingleLine(contents string) string {
	// To use simpler regex, sorting line and converting to single line first
	lines := strings.Split(contents, "\n")
	sort.Strings(lines)
	// Trimming unnecessary `,` (if "deleted=true" is removed, the properties file may have empty line)
	return strings.Trim(strings.Join(lines, ","), ",")
}

func HashCode(s string) int32 {
	i := int32(0)
	for _, c := range s {
		i = (31 * i) + int32(c)
	}
	return i
}

func IsTsMSecBetweenTs(tMsec int64, fromTs int64, toTs int64) bool {
	if fromTs > 0 && (fromTs*1000) > tMsec {
		return false
	}
	if toTs > 0 && (toTs*1000) < tMsec {
		return false
	}
	return true
}
