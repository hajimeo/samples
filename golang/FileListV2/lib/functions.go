// Package lib: functions which are not *heavily* (a bit is OK) related to the main (business) logic and not blob store related functions.
package lib

import (
	"FileListV2/common"
	h "github.com/hajimeo/samples/golang/helpers"
	"net/url"
	"os"
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
	blobStoreWithPrefix = h.AppendSlash(blobStoreWithPrefix)
	if common.BsType == "s3" {
		// If S3, common.BaseDir is an S3 bucket name so not need to include in the path.
		return common.CONTENT
	} else if common.BsType == "file" || common.BsType == "" {
		return blobStoreWithPrefix + common.CONTENT
	} else {
		h.Log("TODO", "Do something for Azure/Google etc. blob store content path")
		return ""
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
