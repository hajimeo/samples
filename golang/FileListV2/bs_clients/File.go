package bs_clients

import (
	"FileListV2/common"
	"FileListV2/lib"
	"database/sql"
	"fmt"
	h "github.com/hajimeo/samples/golang/helpers"
	"github.com/pkg/errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

type FileClient struct {
	ClientNum int
}

func (c *FileClient) SetClientNum(num int) {
	c.ClientNum = num
}

func (c *FileClient) ReadPath(path string) (string, error) {
	if common.Debug {
		// Record the elapsed time
		defer h.Elapsed(time.Now().UnixMilli(), "Read "+path, int64(0))
	} else {
		// If File type blob store, shouldn't take more than 1 second (could be NFS)
		defer h.Elapsed(time.Now().UnixMilli(), "Slow file read for path:"+path, common.SlowMS)
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
		defer h.Elapsed(time.Now().UnixMilli(), "Wrote "+path, int64(0))
	} else {
		defer h.Elapsed(time.Now().UnixMilli(), "Slow file write for path:"+path, common.SlowMS*2)
	}
	// OpenFile fails if the directory does not exist, so create it first
	dir := filepath.Dir(path)
	err := os.MkdirAll(dir, 0755)
	if err != nil {
		return err
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

func (c *FileClient) GetReader(path string) (interface{}, error) {
	reader, err := os.Open(path)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("GetReader: %s failed with %s.", path, err.Error()))
		return nil, err
	}
	return reader, nil
}

func (c *FileClient) GetWriter(path string) (interface{}, error) {
	// For File type blob store, same as CreateLocalFile
	return CreateLocalFile(path)
}

func (c *FileClient) GetPath(path string, localPath string) error {
	if common.Debug {
		defer h.Elapsed(time.Now().UnixMilli(), "Get "+path, int64(0))
	} else {
		defer h.Elapsed(time.Now().UnixMilli(), "Slow file copy for path:"+path, common.SlowMS*2)
	}

	outFile, err := CreateLocalFile(localPath)
	if err != nil {
		h.Log("WARN", err.Error())
		return err
	}
	defer outFile.Close()

	inFile, err := os.Open(path)
	if err != nil {
		err2 := fmt.Errorf("failed to open path: %s with %s", path, err.Error())
		return err2
	}
	defer inFile.Close()
	bytesCopied, err := io.Copy(outFile, inFile)
	h.Log("DEBUG", fmt.Sprintf("Copied %d bytes from %s to %s", bytesCopied, path, localPath))
	return err
}

func (c *FileClient) RemoveDeleted(path string, contents string) error {
	// if the contents is empty, read from the key
	if len(contents) == 0 {
		var err error
		contents, err = c.ReadPath(path)
		if err != nil {
			h.Log("DEBUG", fmt.Sprintf("ReadPath for %s failed with %s.", path, err.Error()))
			return fmt.Errorf("contents of %s is empty and can not read", path)
		}
	}

	// Remove "deleted=true" line from the contents
	updatedContents := common.RxDeleted.ReplaceAllString(contents, "")
	if len(contents) == len(updatedContents) {
		if common.RxDeleted.MatchString(contents) {
			return errors.Errorf("ReplaceAllString may failed for path:%s, as the size is same (%d vs. %d)", path, len(contents), len(updatedContents))
		} else {
			h.Log("DEBUG", fmt.Sprintf("No 'deleted=true' found in %s", path))
			return nil
		}
	}
	return c.WriteToPath(path, updatedContents)
}

func (c *FileClient) GetDirs(baseDir string, pathFilter string, maxDepth int) ([]string, error) {
	if common.Debug {
		defer h.Elapsed(time.Now().UnixMilli(), "Walked "+baseDir, int64(0))
	} else {
		defer h.Elapsed(time.Now().UnixMilli(), "Slow directory walk for "+baseDir, common.SlowMS)
	}
	if maxDepth == -1 {
		maxDepth = 3
		h.Log("DEBUG", fmt.Sprintf("Changing maxDepth: -1 (auto) to %d for File blob store", maxDepth))
	}
	var matchingDirs []string
	// Get up to content baseDir
	baseDir = lib.GetUpToContent(baseDir)
	// Just in case, remove the ending slash
	baseDir = strings.TrimSuffix(baseDir, string(filepath.Separator))
	baseSepCount := strings.Count(baseDir, string(filepath.Separator))
	realMaxDepth := maxDepth + baseSepCount
	startingWithDot := false
	// If baseDir starts with ".", decrease the realMaxDepth by 1 because WalkDir doesn't seem to include "./"
	if strings.HasPrefix(baseDir, "."+string(filepath.Separator)) {
		startingWithDot = true
	}
	filterRegex := regexp.MustCompile(pathFilter)

	// Walk through the directory structure
	h.Log("DEBUG", fmt.Sprintf("Walking directory: %s with pathFilter: %s, maxDepth: %d, realMaxDepth: %d", baseDir, pathFilter, maxDepth, realMaxDepth))
	err := filepath.WalkDir(baseDir, func(dirPath string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			// Not sure if this is a good way to limit the baseSepCount as dirPath may start or may not start with "./"
			sepCount := strings.Count(dirPath, string(filepath.Separator))
			if startingWithDot && !strings.HasPrefix(dirPath, "."+string(filepath.Separator)) {
				sepCount++
			}
			if realMaxDepth > 0 && sepCount > realMaxDepth {
				// If not walking recursively is set, ListObjects should check recursively.
				if !common.WalkRecursive { // && !filterRegex.MatchString(dirPath)
					h.Log("WARN", fmt.Sprintf("Sub-directories may still exist but won't be checked: %s", dirPath))
				}
				if common.Debug2 {
					h.Log("DEBUG", fmt.Sprintf("Reached to the real max depth %d > %d (dirPath: %s)", sepCount, realMaxDepth, dirPath))
				}
				return filepath.SkipDir
			}

			if len(pathFilter) == 0 || filterRegex.MatchString(dirPath) {
				// Currently, WalkRecursive is always true. But if non-recursive mode, the directory needs to be the leaf of the tree.
				if !common.WalkRecursive || lib.IsLeafDir(dirPath, maxDepth) || sepCount == realMaxDepth {
					h.Log("DEBUG", fmt.Sprintf("Matching directory: %s (depth: %d / maxDepth: %d)", dirPath, sepCount, maxDepth))
					// NOTE: As ListObjects for File type is not checking the subdirectories, it's OK to contain the parent directories.
					matchingDirs = append(matchingDirs, dirPath)
				} else {
					h.Log("DEBUG", fmt.Sprintf("Skipping non-leaf directory: %s (maxDepth: %d)", dirPath, maxDepth))
				}
			} else {
				h.Log("DEBUG", fmt.Sprintf("%s does not match with %s (Depth: %d)", dirPath, pathFilter, sepCount))
			}
		}
		return nil
	})

	if err != nil {
		h.Log("ERROR", fmt.Sprintf("%s (base dir: %s, baseSepCount: %d)", err, baseDir, baseSepCount))
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
		return BlobInfo{Error: true}, err
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

func (c *FileClient) ListObjects(dir string, db *sql.DB, perLineFunc func(PrintLineArgs) bool) int64 {
	// ListObjects: List all files in one directory, NOT recursively (different from other blob stores).
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
			args := PrintLineArgs{
				Path:    path,
				BInfo:   c.Convert2BlobInfo(f),
				DB:      db,
				SaveDir: dir,
			}
			if !perLineFunc(args) {
				return io.EOF
			}
		} else {
			// If it's a directory, if walk recursively is not set and if the current path is not the base dir, skip.
			if !common.WalkRecursive && dir != path {
				// Because GetDirs for "File" type returns all directories, this should not check recursively unlike other blob stores
				h.Log("DEBUG", fmt.Sprintf("Skipping directory: %s (dir:%s)", path, dir))
				return filepath.SkipDir
			}
		}
		return nil
	})

	if err != nil && err != io.EOF {
		if common.NotCompSubDirs {
			h.Log("ERROR", "Got error: "+err.Error()+" from "+dir)
		} else if common.Debug2 {
			h.Log("DEBUG", "Got error: "+err.Error()+" from "+dir)
		}
	}
	return subTtl
}
