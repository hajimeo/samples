// Package lib: functions which are not *heavily* (a bit is OK) related to the main (business) logic and not blob store related functions.
package lib

import (
	"FileListV2/common"
	"fmt"
	h "github.com/hajimeo/samples/golang/helpers"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
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

func GetContentPath(blobStoreWithPrefix string, container string) string {
	// Return the relative path starting from 'content' folder
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
		if len(container) == 0 {
			return contentPath
		}
		//h.Log("DEBUG", "(GetContentPath) contentPath:"+contentPath+", container:"+container)
		return strings.SplitAfter(contentPath, container+"/")[1]
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

func IsExactPath(pathFilter string) bool {
	if common.RxVolDir.MatchString(pathFilter) ||
		common.RxVolChapDir.MatchString(pathFilter) ||
		common.RxYyyyDir.MatchString(pathFilter) ||
		common.RxYyyyyMmDir.MatchString(pathFilter) ||
		common.RxYyyyyMmDdDir.MatchString(pathFilter) ||
		common.RxYyyyyMmDdHhDir.MatchString(pathFilter) ||
		common.RxYyyyyMmDdHhMmDir.MatchString(pathFilter) {
		return true
	}
	return false
}

func IsLeafDir(dirPath string, depth int) bool {
	// If depth is 0, no check at all
	if depth == 0 {
		return true
	}
	// If depth is more than 5, always return true as long as dirPath is not empty
	if len(dirPath) > 0 && depth > 5 {
		return true
	}

	switch depth {
	case 1:
		return common.RxVolDir.MatchString(dirPath) || common.RxYyyyDir.MatchString(dirPath)
	case 2:
		return common.RxVolChapDir.MatchString(dirPath) || common.RxYyyyyMmDir.MatchString(dirPath)
	case 3:
		return common.RxVolChapDir.MatchString(dirPath) || common.RxYyyyyMmDdDir.MatchString(dirPath)
	case 4:
		return common.RxVolChapDir.MatchString(dirPath) || common.RxYyyyyMmDdHhDir.MatchString(dirPath)
	case 5:
		return common.RxVolChapDir.MatchString(dirPath) || common.RxYyyyyMmDdHhMmDir.MatchString(dirPath)
	default:
		return false
	}
}

func ComputeSubDirs(path string, pathFilter string) (matchingDirs []string) {
	//h.Log("DEBUG", fmt.Sprintf("Computing sub-directories for %s ...", path))
	// Just in case, trim the trailing slash
	path = strings.TrimSuffix(path, string(os.PathSeparator))
	filterRegex := regexp.MustCompile(pathFilter)

	if common.RxVolDir.MatchString(path) {
		//h.Log("DEBUG", fmt.Sprintf("'vol-{n}' directory found: %s", path))
		// Generate /vol-NN/chap-MM (01 to 47)
		for i := 1; i <= 47; i++ {
			chapDir := fmt.Sprintf("chap-%02d", i)
			chapPath := filepath.Join(path, chapDir)
			if len(pathFilter) == 0 || filterRegex.MatchString(chapPath) {
				matchingDirs = append(matchingDirs, chapPath)
			}
		}
		h.Log("DEBUG", fmt.Sprintf("Computed %d sub-directories for: %s", len(matchingDirs), path))
		return matchingDirs
	}

	if common.RxYyyyDir.MatchString(path) {
		// Generate /YYYY/MM (01 to 12)/DD (01 to 31), but not exceed tomorrow's date
		//h.Log("DEBUG", fmt.Sprintf("'YYYY' directory found: %s", path))
		year := filepath.Base(path)
		yearInt, err := strconv.Atoi(year)
		if err != nil {
			panic(err)
		}

		isFuture := false
		today := time.Now()
		loc := today.Location()
		tObj := time.Date(today.Year(), today.Month(), today.Day(), 23, 59, 59, 0, loc)

		for m := 1; m <= 12; m++ {
			month_last_day := 31
			if m == 4 || m == 6 || m == 9 || m == 11 {
				month_last_day = 30
			} else if m == 2 {
				// Check leap year
				if (yearInt%4 == 0 && yearInt%100 != 0) || (yearInt%400 == 0) {
					month_last_day = 29
				} else {
					month_last_day = 28
				}
			}
			for d := 1; d <= month_last_day; d++ {
				// Check if year-m-d is future date
				if tObj.Before(time.Date(yearInt, time.Month(m), d, 0, 0, 0, 0, loc)) {
					// Future date, skip
					//h.Log("INFO", fmt.Sprintf("Skipping future date: %04d-%02d-%02d", yearInt, m, d))
					isFuture = true
					break
				}

				dayPath := fmt.Sprintf("%s/%02d/%02d", path, m, d)
				if len(pathFilter) == 0 || filterRegex.MatchString(dayPath) {
					matchingDirs = append(matchingDirs, dayPath)
				} else {
					h.Log("DEBUG", fmt.Sprintf("No match for dayPath: %s with filter: %s", dayPath, pathFilter))
				}
			}
			if isFuture {
				//h.Log("INFO", fmt.Sprintf("Skipping future date: %04d-%02d-", yearInt, m))
				break
			}
		}
		h.Log("DEBUG", fmt.Sprintf("Computed %d sub-directories for: %s", len(matchingDirs), path))
		return matchingDirs
	}

	h.Log("DEBUG", fmt.Sprintf("No computed sub-directories for: %s", path))
	return matchingDirs
}
