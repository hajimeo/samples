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
				// NOTE: As ListObjects for File type is not checking the subdirectories, it's OK to contain the parent directories.
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
	if len(matchingDirs) < 10 {
		h.Log("DEBUG", fmt.Sprintf("Matched directories: %v", matchingDirs))
	} else {
		h.Log("DEBUG", fmt.Sprintf("Matched %d directories", len(matchingDirs)))
	}
	// Sorting would make resuming easier, I think
	sort.Strings(matchingDirs)
	return matchingDirs, err
}

func (c *FileClient) GetFileInfo(path string) (BlobInfo, error) {
	fileInfo, err := os.Stat(path)
	if err != nil {
		return BlobInfo{}, err
	}
	return c.Convert2BlobInfo(fileInfo), nil
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

func (c *FileClient) ListObjects(dir string, db *sql.DB, perLineFunc func(interface{}, BlobInfo, *sql.DB)) int64 {
	// ListObjects: List all files in one directory.
	// Global variables should be only TopN, PrintedNum, MaxDepth
	var subTtl int64
	// NOTE: `filepath.Glob` does not work because currently Glob does not support ./**/*
	//       Also, somehow filepath.WalkDir is slower in this code
	err := filepath.Walk(dir, func(path string, f os.FileInfo, err error) error {
		if common.TopN > 0 && common.TopN <= common.PrintedNum {
			h.Log("DEBUG", fmt.Sprintf("Printed %d >= %d", common.PrintedNum, common.TopN))
			return io.EOF
		}
		if err != nil {
			return err
		}
		if !f.IsDir() {
			subTtl++
			perLineFunc(path, c.Convert2BlobInfo(f), db)
		} else {
			if common.MaxDepth > 1 && dir != path {
				//TODO: Because GetDirs for "File" type returns all directories, this should not recursively check sub-directories. But if other blob store types will implement GetDirs differently, may need to change this line.
				h.Log("DEBUG", fmt.Sprintf("Skipping sub directory: %s as it will be checked from the parent dir.", path))
				return filepath.SkipDir
			}
		}
		return nil
	})
	if err != nil && err != io.EOF {
		h.Log("ERROR", "Got error: "+err.Error()+" from "+dir)
	}
	return subTtl
}
