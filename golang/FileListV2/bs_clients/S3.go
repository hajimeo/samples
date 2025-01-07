package bs_clients

import (
	"FileListV2/common"
	"FileListV2/lib"
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	h "github.com/hajimeo/samples/golang/helpers"
	"github.com/pkg/errors"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

type S3Client struct{}

var S3Api *s3.Client

func getS3Api() *s3.Client {
	if S3Api != nil {
		return S3Api
	}
	cfg, err := config.LoadDefaultConfig(context.TODO())
	if common.Debug2 {
		// https://aws.github.io/aws-sdk-go-v2/docs/configuring-sdk/logging/
		cfg, err = config.LoadDefaultConfig(context.TODO(), config.WithClientLogMode(aws.LogRetries|aws.LogRequest))
	}
	if err != nil {
		panic("configuration error, " + err.Error())
	}
	S3Api = s3.NewFromConfig(cfg)
	return S3Api
}

func getS3Object(key string) (*s3.GetObjectOutput, error) {
	if len(common.Container) == 0 {
		common.Container, common.Prefix = lib.GetContainerAndPrefix(common.BaseDir)
	}
	input := &s3.GetObjectInput{
		Bucket: &common.Container,
		Key:    &key,
	}
	return getS3Api().GetObject(context.TODO(), input)
}

func (s S3Client) ReadPath(key string) (string, error) {
	if common.Debug {
		// Record the elapsed time
		defer h.Elapsed(time.Now().UnixMilli(), "Read "+key, int64(0))
	} else {
		// As S3, using *2
		defer h.Elapsed(time.Now().UnixMilli(), "Slow file read for key:"+key, common.SlowMS*2)
	}

	obj, err := getS3Object(key)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("getS3Object for %s failed with %s.", key, err.Error()))
		return "", err
	}
	buf := new(bytes.Buffer)
	_, err = buf.ReadFrom(obj.Body)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("ReadFrom for %s failed with %s.", key, err.Error()))
		return "", err
	}
	contents := strings.TrimSpace(buf.String())
	return contents, nil
}

func (s S3Client) WriteToPath(key string, contents string) error {
	if common.Debug {
		defer h.Elapsed(time.Now().UnixMilli(), "Wrote "+key, 0)
	} else {
		defer h.Elapsed(time.Now().UnixMilli(), "Slow file write for key:"+key, common.SlowMS*2)
	}
	client := getS3Api()
	bucket := common.Container
	input := &s3.PutObjectInput{
		Bucket: &bucket,
		Key:    &key,
		Body:   bytes.NewReader([]byte(contents)),
	}
	resp, err := client.PutObject(context.TODO(), input)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("Key: %s. Resp: %v", key, resp))
		return err
	}
	return nil
}

func replaceTag(key string, tagKey string, tagVal string) error {
	// NOTE: currently not appending but replacing with just one tag
	tagging := types.Tagging{
		TagSet: []types.Tag{},
	}
	if len(tagKey) > 0 {
		tagging = types.Tagging{
			TagSet: []types.Tag{{Key: aws.String(tagKey), Value: aws.String(tagVal)}},
		}
	}
	bucket := common.Container
	inputTag := &s3.PutObjectTaggingInput{
		Bucket:  &bucket,
		Key:     &key,
		Tagging: &tagging,
	}
	respTag, err := getS3Api().PutObjectTagging(context.TODO(), inputTag)
	if err != nil {
		h.Log("WARN", fmt.Sprintf("PutObjectTagging failed. Path: %s. Resp: %v", key, respTag))
	}
	return err
}

func (s S3Client) RemoveDeleted(key string, contents string) error {
	// Remove "deleted=true" line from the contents
	updatedContents := common.RxDeleted.ReplaceAllString(contents, "")
	if len(contents) == len(updatedContents) {
		if common.RxDeleted.MatchString(contents) {
			return errors.Errorf("ReplaceAllString may failed for key:%s, as the size is same (%d vs. %d)", key, len(contents), len(updatedContents))
		} else {
			h.Log("DEBUG", fmt.Sprintf("No 'deleted=true' found in %s", key))
			return nil
		}
	}
	err := s.WriteToPath(key, updatedContents)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("WriteToPath for %s failed with %s", key, err.Error()))
		return err
	}
	err = replaceTag(key, "", "")
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("replaceTag for %s failed with %s", key, err.Error()))
		return err
	}
	bKey := h.PathWithoutExt(key) + ".bytes"
	err = replaceTag(bKey, "", "")
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("replaceTag for %s failed with %s", bKey, err.Error()))
		return err
	}

	h.Log("INFO", fmt.Sprintf("Removed 'deleted=true' and S3 tag for key:%s", key))
	return nil
}

func (s S3Client) GetDirs(baseDir string, pathFilter string, maxDepth int) ([]string, error) {
	var dirs []string
	if len(common.Container) == 0 {
		common.Container, _ = lib.GetContainerAndPrefix(common.BaseDir)
	}
	var bucket = common.Container
	// baseDir is the path to 'content' directory.
	var prefix = baseDir
	var filterRegex = regexp.MustCompile(pathFilter)

	h.Log("DEBUG", fmt.Sprintf("Retriving sub folders under %s %s", bucket, prefix))
	// Not expecting more than 1000 sub folders, so no MaxKeys
	input := &s3.ListObjectsV2Input{
		Bucket:    &bucket,
		Prefix:    aws.String(h.AppendSlash(prefix)),
		Delimiter: aws.String("/"),
	}
	resp, err := getS3Api().ListObjectsV2(context.TODO(), input)
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
		//h.Log("DEBUG", fmt.Sprintf("*item.Prefix %s", *item.Prefix))
		if len(strings.TrimSpace(*item.Prefix)) == 0 {
			continue
		}
		if len(pathFilter) > 0 && !filterRegex.MatchString(*item.Prefix) {
			h.Log("DEBUG", fmt.Sprintf("Skipping %s as it does not match with %s", *item.Prefix, pathFilter))
			continue
		}
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
		if common.TopN > 0 && common.TopN <= common.PrintedNum {
			h.Log("INFO", fmt.Sprintf("Found %d and reached to %d", common.PrintedNum, common.TopN))
			break
		}

		p := s3.NewListObjectsV2Paginator(client, input, func(o *s3.ListObjectsV2PaginatorOptions) {
			if v := int32(common.MaxKeys); v != 0 {
				o.Limit = v
			}
		})

		//https://stackoverflow.com/questions/25306073/always-have-x-number-of-goroutines-running-at-any-time
		wgTags := sync.WaitGroup{}                      // *
		guardFiles := make(chan struct{}, common.Conc2) // **

		var i int
		for p.HasMorePages() {
			if common.TopN > 0 && common.TopN <= common.PrintedNum {
				h.Log("DEBUG", fmt.Sprintf("Printed %d >= %d", common.PrintedNum, common.TopN))
				break
			}

			i++
			resp, err := p.NextPage(context.Background())
			if err != nil {
				println("Got error retrieving list of objects:")
				panic(err.Error())
			}
			if i > 1 {
				h.Log("INFO", fmt.Sprintf("%s: Page %d, %d objects", dir, i, len(resp.Contents)))
			}

			for _, item := range resp.Contents {
				if common.TopN > 0 && common.TopN <= common.PrintedNum {
					h.Log("DEBUG", fmt.Sprintf("Printed %d >= %d for %s", common.PrintedNum, common.TopN, *item.Key))
					break
				}

				subTtl++
				guardFiles <- struct{}{} // **
				wgTags.Add(1)            // *
				go func(client *s3.Client, item types.Object, db *sql.DB) {
					perLineFunc(*item.Key, s.Convert2BlobInfo(item), db)
					<-guardFiles  // **
					wgTags.Done() // *
				}(client, item, db)

			}
		}
		wgTags.Wait() // *
		break
	}
	return subTtl
}

func (s S3Client) GetFileInfo(key string) (BlobInfo, error) {
	if len(common.Container) == 0 {
		common.Container, common.Prefix = lib.GetContainerAndPrefix(common.BaseDir)
	}
	owner := ""
	tags := ""

	input := &s3.HeadObjectInput{
		Bucket: &common.Container,
		Key:    &key,
	}
	headObj, err := getS3Api().HeadObject(context.TODO(), input)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("Retrieving %s failed with %s. Ignoring...", key, err.Error()))
		return BlobInfo{}, err
	}

	// for Owner
	if common.WithOwner {
		input2 := &s3.GetObjectAclInput{
			Bucket: &common.Container,
			Key:    &key,
		}
		ownerObj, err2 := getS3Api().GetObjectAcl(context.TODO(), input2)
		if err2 != nil {
			h.Log("WARN", fmt.Sprintf("GetObjectAcl for %s failed with %v", key, err2))
		}
		if ownerObj != nil && ownerObj.Owner != nil && ownerObj.Owner.DisplayName != nil {
			owner = *ownerObj.Owner.DisplayName
		}
	}

	// for Tags
	if common.WithTags {
		input3 := &s3.GetObjectTaggingInput{
			Bucket: &common.Container,
			Key:    &key,
		}
		tagObj, err3 := getS3Api().GetObjectTagging(context.TODO(), input3)
		if err3 != nil {
			h.Log("WARN", fmt.Sprintf("GetObjectTagging for %s failed with %v", key, err3))
		}
		if tagObj != nil && tagObj.TagSet != nil && len(tagObj.TagSet) > 0 {
			jsonTags, _ := json.Marshal(tagObj.TagSet)
			tags = string(jsonTags)
		}
	}

	blobInfo := BlobInfo{
		Path:    key,
		ModTime: *headObj.LastModified,
		Size:    *headObj.ContentLength,
		Owner:   owner,
		Tags:    tags,
	}
	return blobInfo, nil
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
