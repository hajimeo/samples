package bs_clients

import (
	"FileListV2/common"
	"FileListV2/lib"
	"database/sql"
	"fmt"
	h "github.com/hajimeo/samples/golang/helpers"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

type FileClient struct{}

func (c *FileClient) GetBsClient() interface{} {
	return nil
}

func (c *FileClient) ReadPath(path string) (string, error) {
	if common.Debug {
		// Record the elapsed time
		defer h.Elapsed(time.Now().UnixMilli(), "Read "+path, int64(0))
	} else {
		// If File type blob store, shouldn't take more than 1 second
		defer h.Elapsed(time.Now().UnixMilli(), "Slow file read for path:"+path, int64(1000))
	}
	bytes, err := os.ReadFile(path)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("ReadFile for %s failed with %s. Ignoring...", path, err.Error()))
		return "", err
	}
	contents := strings.TrimSpace(string(bytes))
	return contents, nil
}

func (c *FileClient) WriteToPath(path string, contents string) error {
	if common.Debug {
		defer h.Elapsed(time.Now().UnixMilli(), "Wrote "+path, 0)
	} else {
		defer h.Elapsed(time.Now().UnixMilli(), "Slow file write for path:"+path, 100)
	}
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		return err
	}
	defer f.Close()
	byteLen, err := f.WriteString(contents)
	if byteLen < 0 || err != nil {
		return err
	}
	return err
}

func (c *FileClient) RemoveDeleted(path string, contents string) error {
	// TODO: remove "deleted=true" from the contents
	return c.WriteToPath(path, contents)
}

func (c *FileClient) GetDirs(baseDir string, pathFilter string, maxDepth int) ([]string, error) {
	if common.Debug {
		defer h.Elapsed(time.Now().UnixMilli(), "Walked "+baseDir, 0)
	} else {
		defer h.Elapsed(time.Now().UnixMilli(), "Slow directory walk for "+baseDir, 1000)
	}
	var matchingDirs []string
	filterRegex := regexp.MustCompile(pathFilter)
	// Just in case, remove the ending slash
	baseDir = strings.TrimSuffix(baseDir, string(filepath.Separator))
	depth := strings.Count(baseDir, string(filepath.Separator))
	realMaxDepth := maxDepth + depth

	// Walk through the directory structure
	h.Log("DEBUG", fmt.Sprintf("Walking directory: %s with pathFilter: %s", baseDir, pathFilter))
	err := filepath.Walk(baseDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			// Not sure if this is a good way to limit the depth
			count := strings.Count(path, string(filepath.Separator))
			if realMaxDepth > 0 && count > realMaxDepth {
				h.Log("DEBUG", fmt.Sprintf("Reached to the max depth %d / %d (path: %s)\n", count, maxDepth, path))
				return filepath.SkipDir
			}

			if len(pathFilter) == 0 || filterRegex.MatchString(path) {
				h.Log("DEBUG", fmt.Sprintf("Matching directory: %s (Depth: %d)\n", path, depth))
				matchingDirs = append(matchingDirs, path)
			} else {
				h.Log("DEBUG", fmt.Sprintf("Not matching directory: %s (Depth: %d)\n", path, depth))
			}
		}
		return nil
	})

	if err != nil {
		h.Log("ERROR", fmt.Sprintf("%s (base dir: %s, depth: %d)\n", err, baseDir, depth))
	}
	h.Log("DEBUG", fmt.Sprintf("Matched directory: %s", matchingDirs))
	// Sorting would make resuming easier, I think
	sort.Strings(matchingDirs)
	return matchingDirs, err
}

func (c *FileClient) Convert2BlobInfo(f interface{}) BlobInfo {
	fileInfo := f.(os.FileInfo)
	// Below is for Unix only. Windows causes "undefined: syscall.Stat_t"
	// 	strconv.Itoa(int(fileInfo.Sys().(*syscall.Stat_t).Uid))
	uid, gid := lib.GetXid(fileInfo)
	blobInfo := BlobInfo{
		Path:    fileInfo.Name(),
		ModTime: fileInfo.ModTime(),
		Size:    fileInfo.Size(),
		Owner:   uid + ":" + gid,
	}
	return blobInfo
}

func (c *FileClient) ListObjects(baseDir string, fileFilter string, db *sql.DB, perLineFunc func(interface{}, BlobInfo, *sql.DB, Client)) int64 {
	// ListObjects: List all files in the baseDir directory. Include only common.Filter4FileName if set.
	var subTtl int64
	filterRegex := regexp.MustCompile(fileFilter)
	// NOTE: `filepath.Glob` does not work because currently Glob does not support ./**/*
	//       Also, somehow filepath.WalkDir is slower in this code
	err := filepath.Walk(baseDir, func(path string, f os.FileInfo, err error) error {
		if common.TopN > 0 && common.TopN <= common.PrintedNum {
			h.Log("DEBUG", fmt.Sprintf("Printed %d >= %d", common.PrintedNum, common.TopN))
			return io.EOF
		}
		if err != nil {
			return err
		}
		if !f.IsDir() {
			if len(fileFilter) == 0 || filterRegex.MatchString(f.Name()) {
				subTtl++
				perLineFunc(path, c.Convert2BlobInfo(f), db, c)
			}
		}
		return nil
	})
	if err != nil && err != io.EOF {
		h.Log("ERROR", "Got error: "+err.Error()+" from "+baseDir+" with filter: "+fileFilter)
	}
	return subTtl
}
