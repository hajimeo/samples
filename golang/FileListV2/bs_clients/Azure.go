package bs_clients

import (
	"FileListV2/common"
	"FileListV2/lib"
	"bytes"
	"context"
	"database/sql"
	"fmt"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/container"
	h "github.com/hajimeo/samples/golang/helpers"
	"github.com/pkg/errors"
	"io"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"
	"time"
)

type AzClient struct{}

var AzApi *azblob.Client
var AzContainer *container.Client

func getAzApi() *azblob.Client {
	if AzApi != nil {
		method := reflect.ValueOf(AzApi).MethodByName("URL")
		if method.IsValid() {
			return AzApi
		}
	}

	// TODO: https://pkg.go.dev/github.com/Azure/azure-sdk-for-go/sdk/azidentity#readme-environment-variables
	accountName := h.GetEnv("AZURE_STORAGE_ACCOUNT_NAME", "")
	accountKey := h.GetEnv("AZURE_STORAGE_ACCOUNT_KEY", "")
	if accountName == "" || accountKey == "" {
		panic("Missing AZURE_STORAGE_ACCOUNT_NAME or AZURE_STORAGE_ACCOUNT_KEY")
	}
	var err error
	AzApi, err = azblob.NewClientFromConnectionString("DefaultEndpointsProtocol=https;AccountName="+accountName+";AccountKey="+accountKey+";EndpointSuffix=core.windows.net", nil)
	if err != nil {
		panic("configuration error, " + err.Error())
	}
	return AzApi
}

func getAzContainer() *container.Client {
	if AzContainer != nil && AzContainer.URL() != "" {
		return AzContainer
	}
	if len(common.Container) == 0 {
		common.Container, common.Prefix = lib.GetContainerAndPrefix(common.BaseDir)
	}
	if len(common.Container) == 0 {
		panic("container is not set")
	}

	AzContainer = getAzApi().ServiceClient().NewContainerClient(common.Container)
	if AzContainer == nil || AzContainer.URL() == "" {
		panic("container: " + common.Container + " is empty")
	}
	return AzContainer
}

func getAzObject(path string) (azblob.DownloadStreamResponse, error) {
	if len(common.Container) == 0 {
		common.Container, common.Prefix = lib.GetContainerAndPrefix(common.BaseDir)
	}
	if len(common.Container) == 0 {
		return azblob.DownloadStreamResponse{}, fmt.Errorf("container is not set")
	}
	return getAzApi().DownloadStream(context.TODO(), common.Container, path, nil)
}

func setAzObject(path string, contents string) (azblob.UploadStreamResponse, error) {
	if len(common.Container) == 0 {
		common.Container, common.Prefix = lib.GetContainerAndPrefix(common.BaseDir)
	}
	if len(common.Container) == 0 {
		return azblob.UploadStreamResponse{}, fmt.Errorf("container is not set")
	}
	return getAzApi().UploadStream(context.TODO(), common.Container, path, strings.NewReader(contents), nil)
}

func (a *AzClient) ReadPath(path string) (string, error) {
	if common.Debug {
		defer h.Elapsed(time.Now().UnixMilli(), "Read "+path, int64(0))
	} else {
		defer h.Elapsed(time.Now().UnixMilli(), "Slow file read for path:"+path, common.SlowMS*2)
	}
	resp, err := getAzObject(path)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("getAzObject for %s failed with %s.", path, err.Error()))
		return "", err
	}
	buf := new(bytes.Buffer)
	_, err = buf.ReadFrom(resp.Body)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("ReadFrom for %s failed with %s.", path, err.Error()))
		return "", err
	}
	contents := strings.TrimSpace(buf.String())
	return contents, nil
}

func (a *AzClient) WriteToPath(path string, contents string) error {
	if common.Debug {
		defer h.Elapsed(time.Now().UnixMilli(), "Wrote "+path, 0)
	} else {
		defer h.Elapsed(time.Now().UnixMilli(), "Slow file write for path:"+path, common.SlowMS*2)
	}

	resp, err := setAzObject(path, contents)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("Path: %s. Resp: %v", path, resp))
		return err
	}
	return nil
}

func (a *AzClient) GetReader(path string) (interface{}, error) {
	inFile, err := getAzObject(path)
	if err != nil {
		h.Log("ERROR", fmt.Sprintf("GetReader: %s failed with %s.", path, err.Error()))
		return nil, err
	}
	return inFile.Body, nil
}

func (a *AzClient) GetWriter(path string) (interface{}, error) {
	// For Azure blob store, we can use a pipe to write to the blob
	pr, pw := io.Pipe()
	go func() {
		_, err := getAzApi().UploadStream(context.TODO(), common.Container, path, pr, nil)
		if err != nil {
			h.Log("ERROR", fmt.Sprintf("GetWriter: UploadStream for %s failed with %s.", path, err.Error()))
			pr.CloseWithError(err)
		} else {
		}
		pr.Close()
	}()
	return pw, nil
}

func (a *AzClient) GetPath(path string, localPath string) error {
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

	inFile, err := getAzObject(path)
	if err != nil {
		err2 := fmt.Errorf("getAzObject for %s failed with %s", path, err.Error())
		return err2
	}
	defer inFile.Body.Close()

	bytesWritten, err := io.Copy(outFile, inFile.Body)
	if err != nil {
		err2 := fmt.Errorf("failed to copy path: %s into %s with error: %s", path, localPath, err.Error())
		return err2
	}
	h.Log("DEBUG", fmt.Sprintf("Wrote %d bytes to %s", bytesWritten, localPath))
	return err
}

func (a *AzClient) RemoveDeleted(path string, contents string) error {
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
	// Azure blob store has the metadata (like S3's tag) but Nexus is not using it.
	return a.WriteToPath(path, updatedContents)
}

func (a *AzClient) GetDirs(baseDir string, pathFilter string, maxDepth int) ([]string, error) {
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
	opts := container.ListBlobsHierarchyOptions{
		//Include:    container.ListBlobsInclude{Versions: true},
		//Marker:     nil,
		MaxResults: to.Ptr(int32(common.MaxKeys)),
		Prefix:     to.Ptr(baseDir + "/"),
	}
	pager := getAzContainer().NewListBlobsHierarchyPager("/", &opts)
	for pager.More() {
		resp, err := pager.NextPage(context.TODO())
		if err != nil {
			panic("Failed to get next page: " + err.Error())
		}

		// Process virtual directories (directories) and blobs
		for _, prefix := range resp.Segment.BlobPrefixes {
			path := *prefix.Name
			// Not sure if this is a good way to limit the depth
			count := strings.Count(path, string(filepath.Separator))
			if realMaxDepth > 0 && count > realMaxDepth {
				h.Log("DEBUG", fmt.Sprintf("Reached to the real max depth %d / %d (path: %s)", count, realMaxDepth, *prefix.Name))
				// Assuming Azure SDK returns the directories in order
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

func (a *AzClient) ListObjects(dir string, db *sql.DB, perLineFunc func(PrintLineArgs) bool) int64 {
	// ListObjects: List all files in one directory recursively.
	// Global variables should be only TopN, PrintedNum
	var subTtl int64
	prefix := h.AppendSlash(dir)

	// Walk through the directory structure
	h.Log("DEBUG", fmt.Sprintf("Walking directory: %s", dir))
	opts := container.ListBlobsFlatOptions{
		//Include:    container.ListBlobsInclude{Versions: true},
		//Marker:     nil,
		MaxResults: to.Ptr(int32(common.MaxKeys)),
		Prefix:     to.Ptr(prefix),
	}
	pager := getAzContainer().NewListBlobsFlatPager(&opts)
	for pager.More() {
		if common.TopN > 0 && common.TopN <= common.PrintedNum {
			h.Log("DEBUG", fmt.Sprintf("Printed %d >= %d", common.PrintedNum, common.TopN))
			break
		}
		resp, err := pager.NextPage(context.TODO())
		if err != nil {
			h.Log("ERROR", "Got error: "+err.Error()+" from "+dir)
			break
		}

		// Process virtual directories (directories) and blobs
		for _, blob := range resp.Segment.BlobItems {
			subTtl++
			args := PrintLineArgs{
				Path:    *blob.Name,
				BInfo:   a.Convert2BlobInfo(blob),
				DB:      db,
				SaveDir: dir,
			}
			if !perLineFunc(args) {
				break
			}
		}
	}
	return subTtl
}

func (a *AzClient) GetFileInfo(name string) (BlobInfo, error) {
	// Get one BlobItem from Azure container
	blobClient := getAzContainer().NewBlobClient(name)
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

func (a *AzClient) Convert2BlobInfo(f interface{}) BlobInfo {
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
