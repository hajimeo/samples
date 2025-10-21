package bs_clients

import (
	"FileListV2/common"
	"FileListV2/lib"
	"cloud.google.com/go/storage"
	"context"
	"database/sql"
	"fmt"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/container"
	h "github.com/hajimeo/samples/golang/helpers"
	"github.com/pkg/errors"
	"google.golang.org/api/iterator"
	"io"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

type GcClient struct{}

var GcApi *storage.Client
var GcBucket *storage.BucketHandle

func getGcApi() *storage.Client {
	if GcApi != nil {
		return GcApi
	}
	appCredentials := h.GetEnv("GOOGLE_APPLICATION_CREDENTIALS", "") // Json file path
	if appCredentials == "" {
		panic("Missing GOOGLE_APPLICATION_CREDENTIALS")
	}
	var err error
	GcApi, err = storage.NewClient(context.TODO())
	if err != nil {
		panic("configuration error, " + err.Error())
	}
	return GcApi
}

func getGcContainer() *storage.BucketHandle {
	if GcBucket != nil && GcBucket.BucketName() != "" {
		return GcBucket
	}
	if len(common.Container) == 0 {
		common.Container, common.Prefix = lib.GetContainerAndPrefix(common.BaseDir)
	}
	if len(common.Container) == 0 {
		panic("container (bucket) is not set")
	}

	GcBucket = getGcApi().Bucket(common.Container)
	if GcBucket == nil || GcBucket.BucketName() == "" {
		panic("container: " + common.Container + " is empty")
	}
	return GcBucket
}

func getGcObject(path string) ([]byte, error) {
	if len(common.Container) == 0 {
		common.Container, common.Prefix = lib.GetContainerAndPrefix(common.BaseDir)
	}
	if len(common.Container) == 0 {
		return nil, fmt.Errorf("container is not set")
	}

	handle := getGcContainer().Object(path)
	// Read the contents of the object
	reader, err := handle.NewReader(context.TODO())
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("NewReader for %s failed with %s.", path, err.Error()))
		return nil, err
	}
	defer reader.Close()
	// Read the contents into a buffer
	data, err := io.ReadAll(reader)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("ReadFrom for %s failed with %s.", path, err.Error()))
		return nil, err
	}
	return data, nil
}

func setGcObject(path string, contents string) error {
	if len(common.Container) == 0 {
		common.Container, common.Prefix = lib.GetContainerAndPrefix(common.BaseDir)
	}
	if len(common.Container) == 0 {
		return fmt.Errorf("container is not set")
	}
	obj := getGcContainer().Object(path)
	writer := obj.NewWriter(context.TODO())
	if _, err := writer.Write([]byte(contents)); err != nil {
		return fmt.Errorf("failed to write %s: %v", path, err)
	}
	return nil
}

func (a *GcClient) ReadPath(path string) (string, error) {
	if common.Debug {
		// Record the elapsed time
		defer h.Elapsed(time.Now().UnixMilli(), "Read "+path, int64(0))
	} else {
		// As S3, using *2
		defer h.Elapsed(time.Now().UnixMilli(), "Slow file read for path:"+path, common.SlowMS*2)
	}

	data, err := getGcObject(path)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("getGcObject for %s failed with %s.", path, err.Error()))
		return "", err
	}
	// at this moment, assuming the content is text for this method (.properties file)
	return string(data), nil
}

func (a *GcClient) WriteToPath(path string, contents string) error {
	if common.Debug {
		defer h.Elapsed(time.Now().UnixMilli(), "Wrote "+path, 0)
	} else {
		defer h.Elapsed(time.Now().UnixMilli(), "Slow file write for path:"+path, common.SlowMS*2)
	}

	err := setGcObject(path, contents)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("Path: %s. err: %v", path, err))
		return err
	}
	return nil
}

func (a *GcClient) GetPath(path string, localPath string) error {
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

	data, err := getGcObject(path)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("getGcObject for %s failed with %s.", path, err.Error()))
		return err
	}

	// Copy the data to the local file
	_, err = outFile.Write(data)
	return err
}

func (a *GcClient) RemoveDeleted(path string, contents string) error {
	// if the contents is empty, read from the key
	if len(contents) == 0 {
		var err error
		contents, err = a.ReadPath(path)
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
	return a.WriteToPath(path, updatedContents)
}

func (a *GcClient) GetDirs(baseDir string, pathFilter string, maxDepth int) ([]string, error) {
	if common.Debug {
		defer h.Elapsed(time.Now().UnixMilli(), "Walked "+baseDir, int64(0))
	} else {
		defer h.Elapsed(time.Now().UnixMilli(), "Slow directory walk for "+baseDir, common.SlowMS)
	}
	var matchingDirs []string
	filterRegex := regexp.MustCompile(pathFilter)
	// Just in case, remove the ending slash
	baseDir = strings.TrimSuffix(baseDir, "/")
	depth := strings.Count(baseDir, "/")
	realMaxDepth := maxDepth + depth

	// Walk through the directory structure
	h.Log("DEBUG", fmt.Sprintf("Walking directory: %s with pathFilter: %s", baseDir, pathFilter))
	query := &storage.Query{
		Prefix:    baseDir,
		Delimiter: "/", // This is key to getting "directories"
		// TODO: utilise MatchGlob
	}
	it := getGcContainer().Objects(context.TODO(), query)
	var dirs []string
	for {
		attrs, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			h.Log("DEBUG", fmt.Sprintf("Objects() failed with %s.", err.Error()))
			return nil, err
		}

		if attrs.Prefix != "" {
			dirs = append(dirs, attrs.Prefix) // should remove the ending '/'?
		}

		// Process virtual directories (directories) and blobs
		for _, prefix := range resp.Segment.BlobPrefixes {
			path := *prefix.Name
			// Not sure if this is a good way to limit the depth
			count := strings.Count(path, string(filepath.Separator))
			if realMaxDepth > 0 && count > realMaxDepth {
				h.Log("DEBUG", fmt.Sprintf("Reached to the real max depth %d / %d (path: %s)", count, realMaxDepth, *prefix.Name))
				break
			}
			if len(pathFilter) == 0 || filterRegex.MatchString(path) {
				h.Log("DEBUG", fmt.Sprintf("Matching directory: %s (Depth: %d)", path, depth))
				// NOTE: As ListObjects for File type is not checking the subdirectories, it's OK to contain the parent directories.
				matchingDirs = append(matchingDirs, path)
			} else {
				h.Log("DEBUG", fmt.Sprintf("Not matching directory: %s (Depth: %d)", path, depth))
			}
		}
	}

	if len(matchingDirs) < 10 {
		h.Log("DEBUG", fmt.Sprintf("Matched directories: %v", matchingDirs))
	} else {
		h.Log("DEBUG", fmt.Sprintf("Matched %d directories", len(matchingDirs)))
	}
	// Sorting would make resuming easier, I think
	sort.Strings(matchingDirs)
	return matchingDirs, nil
}

func (a *GcClient) ListObjects(dir string, db *sql.DB, perLineFunc func(PrintLineArgs) bool) int64 {
	return 0
	/*
		ctx := context.Background()
		client, err := storage.NewClient(ctx)
		if err != nil {
			return fmt.Errorf("storage.NewClient: %v", err)
		}
		defer client.Close()

		ctx, cancel := context.WithTimeout(ctx, time.Second*10)
		defer cancel()

		// Create iterator with prefix and delimiter
		it := client.Bucket(bucketName).Objects(ctx, &storage.Query{
			Prefix:    directoryPrefix,
			Delimiter: "/",
		})

		fmt.Printf("Objects in directory %q:\n", directoryPrefix)
		for {
			attrs, err := it.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				return fmt.Errorf("Bucket(%q).Objects(): %v", bucketName, err)
			}
			fmt.Println(attrs.Name)
		}

		subTtl := int64(0)
		return subTtl */
}

func (a *GcClient) GetFileInfo(name string) (BlobInfo, error) {
	blobClient := getGcContainer().NewBlobClient(name)
	blobItemProps, err := blobClient.GetProperties(context.Background(), nil)
	if err != nil {
		return BlobInfo{Error: true}, err
	}
	owner := ""

	if blobItemProps.Metadata != nil {
		owner = *blobItemProps.Metadata["owner"]
	}
	blobInfo := BlobInfo{
		Path:    name,
		ModTime: *blobItemProps.LastModified,
		Size:    *blobItemProps.ContentLength, // TODO: this may not be correct if .bytes
		Owner:   owner,                        // TODO: this is not working
	}
	return blobInfo, nil
}

func (a *GcClient) Convert2BlobInfo(f interface{}) BlobInfo {
	item := f.(*container.BlobItem)
	owner := ""
	if item.Properties.Owner != nil {
		owner = *item.Properties.Owner
	}
	blobInfo := BlobInfo{
		Path:    *item.Name,
		ModTime: *item.Properties.LastModified,
		Size:    *item.Properties.ContentLength, // TODO: this may not be correct
		Owner:   owner,
	}
	return blobInfo
}
