package bs_clients

import (
	"FileListV2/common"
	"FileListV2/lib"
	"bytes"
	"context"
	"database/sql"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	h "github.com/hajimeo/samples/golang/helpers"
	"github.com/pkg/errors"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

type S3Client struct{}

var s3Api *s3.Client

func getS3Api() *s3.Client {
	if s3Api != nil {
		return s3Api
	}
	cfg, err := config.LoadDefaultConfig(context.TODO())
	if common.Debug2 {
		// https://aws.github.io/aws-sdk-go-v2/docs/configuring-sdk/logging/
		cfg, err = config.LoadDefaultConfig(context.TODO(), config.WithClientLogMode(aws.LogRetries|aws.LogRequest))
	}
	if err != nil {
		panic("configuration error, " + err.Error())
	}
	s3Api = s3.NewFromConfig(cfg)
	return s3Api
}

func getObjectS3(key string) (*s3.GetObjectOutput, error) {
	value := h.CacheGetObj(key)
	if value != nil {
		return value.(*s3.GetObjectOutput), nil
	}
	if common.Debug {
		defer h.Elapsed(time.Now().UnixMilli(), "DEBUG Read key:"+key, 0)
	} else {
		defer h.Elapsed(time.Now().UnixMilli(), "WARN  slow file read for key:"+key, 1000)
	}
	if len(common.Container) == 0 {
		common.Container, common.Prefix = lib.GetContainerAndPrefix(common.BaseDir)
	}
	input := &s3.GetObjectInput{
		Bucket: &common.Container,
		Key:    &key,
	}
	client := getS3Api()
	value, err := client.GetObject(context.TODO(), input)
	if err == nil {
		cacheSize := 16
		if common.Conc2 > cacheSize {
			cacheSize = common.Conc2
		}
		h.CacheAddObject(key, value, cacheSize)
	}
	return value.(*s3.GetObjectOutput), err
}

func (s S3Client) ReadPath(path string) (string, error) {
	// For S3, 'path' is the key
	obj, err := getObjectS3(path)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("Retrieving %s failed with %s. Ignoring...", path, err.Error()))
		return "", err
	}
	buf := new(bytes.Buffer)
	_, err = buf.ReadFrom(obj.Body)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("Reading object for %s failed with %s. Ignoring...", path, err.Error()))
		return "", err
	}
	contents := strings.TrimSpace(buf.String())
	return contents, nil
}

func (s S3Client) WriteToPath(path string, contents string) error {
	if common.Debug {
		defer h.Elapsed(time.Now().UnixMilli(), "DEBUG Wrote "+path, 0)
	} else {
		defer h.Elapsed(time.Now().UnixMilli(), "WARN  slow file write for path:"+path, 400)
	}
	client := getS3Api()
	baseDir := common.BaseDir
	input := &s3.PutObjectInput{
		Bucket: &baseDir,
		Key:    &path,
		Body:   bytes.NewReader([]byte(contents)),
	}
	resp, err := client.PutObject(context.TODO(), input)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("Path: %s. Resp: %v", path, resp))
		return err
	}
	return nil
}

func removeTag(path string) error {
	return replaceTag(path, "", "")
}

func replaceTag(path string, key string, value string) error {
	// NOTE: currently not appending but replacing with just one tag
	var tagSet []types.Tag
	if len(key) > 0 {
		tagSet = []types.Tag{
			{Key: aws.String(key), Value: aws.String(value)},
		}
	}
	bucket := common.Container
	inputTag := &s3.PutObjectTaggingInput{
		Bucket: &bucket,
		Key:    &path,
		Tagging: &types.Tagging{
			TagSet: tagSet,
		},
	}
	respTag, err := getS3Api().PutObjectTagging(context.TODO(), inputTag)
	if err != nil {
		h.Log("WARN", fmt.Sprintf("PutObjectTagging failed. Path: %s. Resp: %v", path, respTag))
	}
	return err
}

func (s S3Client) RemoveDeleted(path string, contents string) error {
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
	err := s.WriteToPath(path, contents)
	if err != nil {
		return err
	}
	err = removeTag(path)
	if err != nil {
		return err
	}
	bPath := h.PathWithoutExt(path) + ".bytes"
	err = removeTag(bPath)
	if err != nil {
		return err
	}
	h.Log("INFO", fmt.Sprintf("Removed 'deleted=true' and S3 tag for path:%s", path))
	return nil
}

func (s S3Client) GetDirs(baseDir string, pathFilter string, maxDepth int) ([]string, error) {
	// TODO: not utilising baseDir and pathFilter
	// baseDir is the path to 'content' directory.
	var dirs []string
	if len(common.Container) == 0 {
		common.Container, _ = lib.GetContainerAndPrefix(common.BaseDir)
	}
	var bucket = common.Container
	var prefix = baseDir
	var contain string
	//var filterRegex = regexp.MustCompile(pathFilter)

	// Prefix not ending / does not work with S3 API, for example: ${S3_PREFIX}/content/vol-, so trying to handle this in here
	if !strings.HasSuffix(prefix, "/") {
		if !strings.HasPrefix(prefix, "/") && strings.Contains(prefix, "/") {
			prefix_tmp := filepath.Dir(prefix)
			if len(prefix_tmp) > 0 {
				prefix = prefix_tmp
				contain = filepath.Base(prefix) // like 'vol-'
				h.Log("DEBUG", fmt.Sprintf("S3 prefix = %s, contain = %s", prefix, contain))
			}
		}
	}

	//prefix = lib.GetUpToContent(prefix + "/" + bucket)
	h.Log("DEBUG", fmt.Sprintf("Retriving sub folders under %s %s", bucket, prefix))
	// Not expecting more than 1000 sub folders, so no MaxKeys
	input := &s3.ListObjectsV2Input{
		Bucket:    &bucket,
		Prefix:    aws.String(strings.TrimSuffix(prefix, "/") + "/"),
		Delimiter: aws.String("/"),
	}
	client := getS3Api()
	resp, err := client.ListObjectsV2(context.TODO(), input)
	if err != nil {
		return dirs, err
	}

	if len(resp.CommonPrefixes) == 0 {
		h.Log("DEBUG", fmt.Sprintf("resp.CommonPrefixes (matching directories) is empty for %s (baseDir: %s)", prefix, baseDir))
		// if no CommonPrefixes means, probably the end of the path = starting point of searching, so appending this 'prefix'
		dirs = append(dirs, prefix)
		return dirs, nil
	}

	for _, item := range resp.CommonPrefixes {
		if len(strings.TrimSpace(*item.Prefix)) == 0 {
			continue
		}
		if len(contain) > 0 && !strings.Contains(*item.Prefix, contain) {
			h.Log("DEBUG", fmt.Sprintf("Skipping %s as it doss not contain %s", *item.Prefix, contain))
			continue
		}
		/*if len(pathFilter) > 0 && !filterRegex.MatchString(*item.Prefix) {
			h.Log("DEBUG", fmt.Sprintf("Skipping %s as it does not match with %s", *item.Prefix, pathFilter))
			continue
		}*/
		// if maxDepth is greater than -1, then check the depth (0 means current directory depth)
		if maxDepth >= 0 && strings.Count(*item.Prefix, "/") > maxDepth {
			h.Log("DEBUG", fmt.Sprintf("Skipping %s as it exceeds max depth %d", *item.Prefix, maxDepth))
			continue
		}
		h.Log("DEBUG", fmt.Sprintf("Appending %s in dirs", *item.Prefix))
		dirs = append(dirs, *item.Prefix)
	}
	sort.Strings(dirs)
	return dirs, nil
}

func (s S3Client) ListObjects(dir string, db *sql.DB, perLineFunc func(interface{}, BlobInfo, *sql.DB)) int64 {
	var subTtl int64
	//common.Container, common.Prefix = lib.GetContainerAndPrefix(common.BaseDir)
	bucket := common.Container
	input := &s3.ListObjectsV2Input{
		Bucket:     &bucket,
		MaxKeys:    aws.Int32(int32(common.MaxKeys)),
		FetchOwner: aws.Bool(common.WithOwner),
		Prefix:     &dir,
	}
	// TODO: below does not seem to be working, maybe because StartAfter should be Key
	if common.ModDateFromTS > 0 {
		input.StartAfter = aws.String(time.Unix(common.ModDateFromTS, 0).UTC().Format("2006-01-02T15:04:05.000Z"))
	}

	client := getS3Api()
	for {
		resp, err := client.ListObjectsV2(context.TODO(), input)
		if err != nil {
			println("Got error retrieving list of objects:")
			// Fail immediately
			panic(err.Error())
		}
		// Somehow KeyCount is extremely large, like 1374389592920, so not using it.
		//h.Log("DEBUG", fmt.Sprintf("ListObjectsV2 returned %d (max: %d)", resp.KeyCount, common.MaxKeys))

		//https://stackoverflow.com/questions/25306073/always-have-x-number-of-goroutines-running-at-any-time
		wgTags := sync.WaitGroup{}                     // *
		guardTags := make(chan struct{}, common.Conc2) // **
		if input.ContinuationToken != nil {
			h.Log("DEBUG", fmt.Sprintf("Spawning a new routine for Token %s", h.TruncateStr(*input.ContinuationToken, 32)))
		}
		for _, item := range resp.Contents {
			// TODO: this should check the file name, not path
			if common.RxFilter4FileName == nil || common.RxFilter4FileName.MatchString(*item.Key) {
				subTtl++
				guardTags <- struct{}{} // **
				wgTags.Add(1)           // *
				go func(client *s3.Client, item types.Object, db *sql.DB) {
					perLineFunc(*item.Key, s.Convert2BlobInfo(item), db)
					<-guardTags   // **
					wgTags.Done() // *
				}(client, item, db)
			}

			if common.TopN > 0 && common.TopN <= common.PrintedNum {
				h.Log("DEBUG", fmt.Sprintf("Printed %d >= %d", common.PrintedNum, common.TopN))
				break
			}
		}
		wgTags.Wait() // *

		// Continue if truncated (more data available) and if not reaching to the top N.
		if common.TopN > 0 && common.TopN <= common.PrintedNum {
			h.Log("DEBUG", fmt.Sprintf("Found %d and reached to %d", common.PrintedNum, common.TopN))
			break
		} else if *resp.IsTruncated {
			h.Log("DEBUG", fmt.Sprintf("Set ContinuationToken to %s", *resp.NextContinuationToken))
			input.ContinuationToken = resp.NextContinuationToken
		} else {
			break
		}
	}
	return subTtl
}

func (s S3Client) GetFileInfo(path string) (BlobInfo, error) {
	obj, err := getObjectS3(path)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("Retrieving %s failed with %s. Ignoring...", path, err.Error()))
		return BlobInfo{}, err
	}
	if err != nil {
		return BlobInfo{}, err
	}
	return s.Convert2BlobInfo(obj), nil
}

func (s S3Client) Convert2BlobInfo(f interface{}) BlobInfo {
	item := f.(types.Object)
	owner := ""
	if item.Owner != nil && item.Owner.DisplayName != nil {
		owner = *item.Owner.DisplayName
	}
	blobInfo := BlobInfo{
		Path:    *item.Key,
		ModTime: *item.LastModified,
		Size:    *item.Size,
		Owner:   owner,
	}
	return blobInfo
}
