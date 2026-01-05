package bs_clients

// @see: https://docs.aws.amazon.com/sdk-for-go/v2/developer-guide/welcome.html

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
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	h "github.com/hajimeo/samples/golang/helpers"
	"github.com/pkg/errors"
	"io"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

type S3Client struct {
	ClientNum int
}

var S3Api *s3.Client
var S3Api2 *s3.Client

func (s *S3Client) SetClientNum(num int) {
	s.ClientNum = num
}

func getS3Api(clientNum int) *s3.Client {
	if clientNum < 2 && S3Api != nil {
		return S3Api
	}
	if clientNum == 2 && S3Api2 != nil {
		return S3Api2
	}

	// if AWS_REGION environment variable is DEFAULT or default, unset AWS_REGION
	currentAwsRegion := h.GetEnv("AWS_REGION", "")
	if strings.EqualFold(currentAwsRegion, "DEFAULT") {
		h.Log("DEBUG", fmt.Sprintf("Unsetting AWS_REGION environment variable as it is set to DEFAULT"))
		_ = os.Unsetenv("AWS_REGION")
	}
	var specificEndpointUrl string
	var specificRegion string
	var specificCAPath string
	var orginalCAPath string
	if clientNum > 1 {
		h.Log("DEBUG", fmt.Sprintf("Setting up S3 clientNum:%d", clientNum))
		specificEndpointUrl = h.GetEnv("AWS_ENDPOINT_URL_"+strconv.Itoa(clientNum), "")
		specificRegion = h.GetEnv("AWS_REGION_"+strconv.Itoa(clientNum), "")
		specificCAPath = h.GetEnv("AWS_CA_BUNDLE_"+strconv.Itoa(clientNum), "")
		if len(specificCAPath) > 0 {
			h.Log("INFO", fmt.Sprintf("Using custom CA bundle path: %s for clientNum:%d", specificCAPath, clientNum))
			// Set AWS_CA_BUNDLE environment variable
			h.SetEnv("AWS_CA_BUNDLE", specificCAPath)
			orginalCAPath = h.GetEnv("AWS_CA_BUNDLE", "")
		}
		h.Log("DEBUG", fmt.Sprintf("specificEndpointUrl: %s, specificRegion: %s for clientNum:%d", specificEndpointUrl, specificRegion, clientNum))
	}

	cfg, err := getS3Config(clientNum)
	if len(specificCAPath) > 0 {
		// Restore original AWS_CA_BUNDLE environment variable
		if len(orginalCAPath) == 0 {
			h.Log("DEBUG", fmt.Sprintf("Unsetting AWS_CA_BUNDLE for clientNum:%d", clientNum))
			_ = os.Unsetenv("AWS_CA_BUNDLE")
		} else {
			h.Log("DEBUG", fmt.Sprintf("Restoring AWS_CA_BUNDLE to %s for clientNum:%d", orginalCAPath, clientNum))
			h.SetEnv("AWS_CA_BUNDLE", orginalCAPath)
		}
	}
	if err != nil {
		panic("configuration error, " + err.Error())
	}
	// To stop 'WARN Response has no supported checksum. Not validating response payload.'
	cfg.ResponseChecksumValidation = 2

	if common.S3PathStyle {
		h.Log("INFO", "Using legacy S3 Path-Style access")
	}
	var maybeS3Api *s3.Client
	if len(specificEndpointUrl) > 0 {
		h.Log("INFO", fmt.Sprintf("Using custom endpoint URL: %s for clientNum:%d", specificEndpointUrl, clientNum))
		if len(specificRegion) > 0 {
			h.Log("INFO", fmt.Sprintf("Using custom region: %s for clientNum:%d", specificRegion, clientNum))
			maybeS3Api = s3.NewFromConfig(cfg, func(o *s3.Options) {
				o.UsePathStyle = common.S3PathStyle
				o.BaseEndpoint = &specificEndpointUrl
				o.Region = specificRegion
			})
		} else {
			maybeS3Api = s3.NewFromConfig(cfg, func(o *s3.Options) {
				o.UsePathStyle = common.S3PathStyle
				o.BaseEndpoint = &specificEndpointUrl
			})
		}
	} else {
		maybeS3Api = s3.NewFromConfig(cfg, func(o *s3.Options) {
			o.UsePathStyle = common.S3PathStyle
		})
	}
	if clientNum == 2 {
		S3Api2 = maybeS3Api
		return S3Api2
	}
	S3Api = maybeS3Api
	return S3Api
}

func getS3Config(clientNum int) (aws.Config, error) {
	var specificAccessKeyID string
	var specificSecretAccessKey string

	if clientNum > 1 {
		specificAccessKeyID = h.GetEnv("AWS_ACCESS_KEY_ID_"+strconv.Itoa(clientNum), "")
		specificSecretAccessKey = h.GetEnv("AWS_SECRET_ACCESS_KEY_"+strconv.Itoa(clientNum), "")
	}
	// Override with specific credentials if provided, otherwise, use default credentials
	if len(specificAccessKeyID) > 0 {
		h.Log("INFO", fmt.Sprintf("Creating S3 credential for clientNum:%d", clientNum))
		creds := credentials.NewStaticCredentialsProvider(specificAccessKeyID, specificSecretAccessKey, "")
		if common.Debug2 {
			h.Log("DEBUG", fmt.Sprintf("Enabling extra LogMode for clientNum:%d", clientNum))
			return config.LoadDefaultConfig(context.TODO(),
				config.WithCredentialsProvider(creds),
				config.WithClientLogMode(aws.LogRetries|aws.LogRequest),
			)
		}
		return config.LoadDefaultConfig(context.TODO(),
			config.WithCredentialsProvider(creds),
		)
	}
	if common.Debug2 {
		// https://aws.github.io/aws-sdk-go-v2/docs/configuring-sdk/logging/
		h.Log("DEBUG", fmt.Sprintf("Enabling extra LogMode"))
		return config.LoadDefaultConfig(context.TODO(), config.WithClientLogMode(aws.LogRetries|aws.LogRequest))
	}
	return config.LoadDefaultConfig(context.TODO())
}

// should use this method instead of common.Container
func getBucket(clientNum int) string {
	if clientNum == 2 {
		if len(common.Container2) == 0 {
			common.Container2, common.Prefix2 = lib.GetContainerAndPrefix(common.BaseDir2)
		}
		if len(common.Container2) == 0 {
			panic("Container is not set (baseDir2: " + common.BaseDir2 + ", prefix2: " + common.Prefix2 + ")")
		}
		return common.Container2
	}

	if len(common.Container) == 0 {
		common.Container, common.Prefix = lib.GetContainerAndPrefix(common.BaseDir)
	}
	if len(common.Container) == 0 {
		panic("Container is not set (baseDir: " + common.BaseDir + ", prefix: " + common.Prefix + ")")
	}
	return common.Container
}

func getS3ObjectInput(key string, container string) *s3.GetObjectInput {
	// S3 key should contain the S3 prefix, so using container as bucket
	return &s3.GetObjectInput{
		Bucket: &container,
		Key:    &key,
	}
}

func (s *S3Client) ReadPath(key string) (string, error) {
	if common.Debug {
		// Record the elapsed time
		defer h.Elapsed(time.Now().UnixMilli(), "Read "+key, int64(0))
	} else {
		// As S3, using *2
		defer h.Elapsed(time.Now().UnixMilli(), "Slow file read for key:"+key, common.SlowMS*2)
	}
	bucket := getBucket(s.ClientNum)
	input := getS3ObjectInput(key, bucket)
	obj, err := getS3Api(s.ClientNum).GetObject(context.TODO(), input)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("getS3ObjectInput for %s failed with %s.", key, err.Error()))
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

func (s *S3Client) WriteToPath(key string, contents string) error {
	if common.Debug {
		defer h.Elapsed(time.Now().UnixMilli(), "Wrote "+key, 0)
	} else {
		defer h.Elapsed(time.Now().UnixMilli(), "Slow file write for key:"+key, common.SlowMS*2)
	}
	bucket := getBucket(s.ClientNum)
	input := &s3.PutObjectInput{
		Bucket: &bucket,
		Key:    &key,
		Body:   bytes.NewReader([]byte(contents)),
	}
	resp, err := getS3Api(s.ClientNum).PutObject(context.TODO(), input)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("Key: %s. Resp: %v", key, resp))
		return err
	}
	// if 'contents' contain 'deleted=true', then add tag
	if common.RxDeleted.MatchString(contents) {
		h.Log("DEBUG", fmt.Sprintf("Key: %s. Adding deletion marker tag", key))
		// Currently do not care about the error. Also replaceTagInput() will log the warn.
		_ = replaceTagInput(key, "deleted", "true", bucket)
	}
	return nil
}

func (s *S3Client) GetReader(key string) (interface{}, error) {
	bucket := getBucket(s.ClientNum)
	if common.Debug2 {
		h.Log("DEBUG", fmt.Sprintf("Got bucket:%s for key:%s, clientNum:%d", bucket, key, s.ClientNum))
	}
	input := getS3ObjectInput(key, bucket)
	obj, err := getS3Api(s.ClientNum).GetObject(context.TODO(), input)
	if err != nil {
		h.Log("DEBUG", fmt.Sprintf("GetReader: %s failed with %s.", key, err.Error()))
		return nil, err
	}
	return obj.Body, nil
}

// Instead of returning a pipe, buffer the data before upload
func (s *S3Client) GetWriter(key string) (interface{}, error) {
	buf := new(bytes.Buffer)
	writer := &s3BufferedWriter{
		buf:    buf,
		key:    key,
		s3:     s,
		bucket: getBucket(s.ClientNum),
	}
	return writer, nil
}

type s3BufferedWriter struct {
	buf    *bytes.Buffer
	key    string
	s3     *S3Client
	bucket string
}

func (w *s3BufferedWriter) Write(p []byte) (int, error) {
	return w.buf.Write(p)
}

func (w *s3BufferedWriter) Close() error {
	bucket := w.bucket
	input := &s3.PutObjectInput{
		Bucket: &bucket,
		Key:    &w.key,
		Body:   bytes.NewReader(w.buf.Bytes()),
	}
	_, err := getS3Api(w.s3.ClientNum).PutObject(context.TODO(), input)
	return err
}

func (s *S3Client) GetPath(key string, localPath string) error {
	if common.Debug {
		defer h.Elapsed(time.Now().UnixMilli(), "Get "+key, int64(0))
	} else {
		defer h.Elapsed(time.Now().UnixMilli(), "Slow file copy for key:"+key, common.SlowMS*2)
	}

	outFile, err := CreateLocalFile(localPath)
	if err != nil {
		h.Log("WARN", err.Error())
		return err
	}
	defer outFile.Close()

	bucket := getBucket(s.ClientNum)
	input := getS3ObjectInput(key, bucket)
	inFile, err := getS3Api(s.ClientNum).GetObject(context.TODO(), input)
	if err != nil {
		err2 := fmt.Errorf("failed to get key: %s %s with error: %s", bucket, key, err.Error())
		return err2
	}
	defer inFile.Body.Close()

	bytesWritten, err := io.Copy(outFile, inFile.Body)
	if err != nil {
		err2 := fmt.Errorf("failed to copy key: %s into %s with error: %s", key, localPath, err.Error())
		return err2
	}
	h.Log("DEBUG", fmt.Sprintf("Wrote %d bytes to %s", bytesWritten, localPath))
	return err
}

func replaceTagInput(key string, tagKey string, tagVal string, bucket string) *s3.PutObjectTaggingInput {
	// NOTE: currently not appending but replacing with just one tag
	tagging := types.Tagging{
		TagSet: []types.Tag{},
	}
	if len(tagKey) > 0 {
		tagging = types.Tagging{
			TagSet: []types.Tag{{Key: aws.String(tagKey), Value: aws.String(tagVal)}},
		}
	}
	return &s3.PutObjectTaggingInput{
		Bucket:  &bucket,
		Key:     &key,
		Tagging: &tagging,
	}
}

func (s *S3Client) RemoveDeleted(key string, contents string) error {
	// if the contents is empty, read from the key
	if len(contents) == 0 {
		var err error
		contents, err = s.ReadPath(key)
		if err != nil {
			h.Log("DEBUG", fmt.Sprintf("ReadPath for %s failed with %s.", key, err.Error()))
			return fmt.Errorf("contents of %s is empty and can not read", key)
		}
	}
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
	bucket := getBucket(s.ClientNum)
	inputTag := replaceTagInput(key, "", "", bucket)
	respTag, err := getS3Api(s.ClientNum).PutObjectTagging(context.TODO(), inputTag)
	if err != nil {
		h.Log("WARN", fmt.Sprintf("PutObjectTagging failed. Path: %s. Resp: %v, Error: %s", key, respTag, err.Error()))
		return err
	}
	bKey := h.PathWithoutExt(key) + ".bytes"
	inputTag = replaceTagInput(bKey, "", "", bucket)
	respTag, err = getS3Api(s.ClientNum).PutObjectTagging(context.TODO(), inputTag)
	if err != nil {
		h.Log("WARN", fmt.Sprintf("PutObjectTagging failed. Path: %s. Resp: %v, Error: %s", key, respTag, err.Error()))
		return err
	}
	h.Log("INFO", fmt.Sprintf("Removed 'deleted=true' and S3 tag for key:%s", key))
	return nil
}

func (s *S3Client) GetDirs(baseDir string, pathFilter string, maxDepth int) ([]string, error) {
	if common.Debug {
		defer h.Elapsed(time.Now().UnixMilli(), "Walked "+baseDir, int64(0))
	} else {
		defer h.Elapsed(time.Now().UnixMilli(), "Slow directory walk for "+baseDir, common.SlowMS*2)
	}
	var dirs []string
	if maxDepth == -1 {
		maxDepth = 1
		h.Log("DEBUG", fmt.Sprintf("maxDepth was -1 (auto), changing to %d for S3", maxDepth))
	}
	var bucket = getBucket(s.ClientNum)
	// if baseDir is missing 'content', appending
	var prefix = lib.GetContentPath(baseDir, bucket)
	var filterRegex = regexp.MustCompile(pathFilter)
	baseDepth := strings.Count(prefix, "/") + 1 // +1 to count the trailing slash

	h.Log("DEBUG", fmt.Sprintf("Retrieving sub folders under %s %s", bucket, prefix))
	// Not expecting more than 1000 subfolders, so no MaxKeys
	input := &s3.ListObjectsV2Input{
		Bucket:    &bucket,
		Prefix:    aws.String(h.AppendSlash(prefix)),
		Delimiter: aws.String("/"),
	}
	resp, err := getS3Api(s.ClientNum).ListObjectsV2(context.TODO(), input)
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
		if common.Debug2 {
			h.Log("DEBUG", fmt.Sprintf("*item.Prefix %s", *item.Prefix))
		}
		if len(strings.TrimSpace(*item.Prefix)) == 0 {
			continue
		}
		if len(pathFilter) > 0 && !filterRegex.MatchString(*item.Prefix) {
			h.Log("DEBUG", fmt.Sprintf("Skipping %s as it does not match with %s", *item.Prefix, pathFilter))
			continue
		}
		// if maxDepth is greater than -1, then check the current path with the maxDepth (0 means current directory depth)
		currentDepth := strings.Count(*item.Prefix, "/") - baseDepth
		if maxDepth >= 0 && currentDepth > maxDepth {
			if maxDepth > 1 {
				h.Log("DEBUG", fmt.Sprintf("Skipping %s as %d exceeds max depth %d", *item.Prefix, currentDepth, maxDepth))
			}
			continue
		}
		// TODO: Currently not checking the sub directories if current is directory
		h.Log("DEBUG", fmt.Sprintf("Appending %s in dirs", *item.Prefix))
		dirs = append(dirs, *item.Prefix)
	}
	sort.Strings(dirs)
	return dirs, nil
}

func (s *S3Client) ListObjects(dir string, db *sql.DB, perLineFunc func(PrintLineArgs) bool) int64 {
	var subTtl int64
	bucket := getBucket(s.ClientNum)
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

	client := getS3Api(s.ClientNum)
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
			page, err := p.NextPage(context.Background())
			if err != nil {
				println("Got error retrieving list of objects:")
				panic(err.Error())
			}
			if i > 1 {
				h.Log("INFO", fmt.Sprintf("%s: Page %d, %d objects", dir, i, len(page.Contents)))
			}

			for _, item := range page.Contents {
				if common.TopN > 0 && common.TopN <= common.PrintedNum {
					h.Log("DEBUG", fmt.Sprintf("Printed %d >= %d for %s", common.PrintedNum, common.TopN, *item.Key))
					break
				}

				subTtl++
				guardFiles <- struct{}{} // **
				wgTags.Add(1)            // *
				go func(client *s3.Client, item types.Object, db *sql.DB) {
					args := PrintLineArgs{
						Path:    *item.Key,
						BInfo:   s.Convert2BlobInfo(item),
						DB:      db,
						SaveDir: dir,
					}
					if !perLineFunc(args) {
						<-guardFiles  // **
						wgTags.Done() // *
						return
					}
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

func (s *S3Client) GetFileInfo(key string) (BlobInfo, error) {
	bucket := getBucket(s.ClientNum)
	owner := ""
	tags := ""

	input := &s3.HeadObjectInput{
		Bucket: &bucket,
		Key:    &key,
	}
	headObj, err := getS3Api(s.ClientNum).HeadObject(context.TODO(), input)
	if err != nil {
		if common.Debug2 {
			h.Log("DEBUG", fmt.Sprintf("Retrieving %s/%s failed with %s. Ignoring...", bucket, key, err.Error()))
		}
		return BlobInfo{Error: true}, err
	}

	// for Owner
	if common.WithOwner {
		//h.Log("DEBUG", fmt.Sprintf("Retrieving Owner for %s ...", key))
		input2 := &s3.GetObjectAclInput{
			Bucket: &bucket,
			Key:    &key,
		}
		ownerObj, err2 := getS3Api(s.ClientNum).GetObjectAcl(context.TODO(), input2)
		if err2 != nil {
			h.Log("WARN", fmt.Sprintf("GetObjectAcl for %s failed with %v", key, err2))
		}
		if ownerObj != nil && ownerObj.Owner != nil && ownerObj.Owner.DisplayName != nil {
			owner = *ownerObj.Owner.DisplayName
		}
	}

	// for Tags
	if common.WithTags {
		tags = getTags(key, s)
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

func (s *S3Client) Convert2BlobInfo(f interface{}) BlobInfo {
	item := f.(types.Object)
	owner := ""
	tags := ""
	if item.Owner != nil && item.Owner.DisplayName != nil {
		owner = *item.Owner.DisplayName
	}
	// S3 item does not have tags, so need to retrieve it separately
	if common.WithTags {
		tags = getTags(*item.Key, s)
	}
	blobInfo := BlobInfo{
		Path:    *item.Key,
		ModTime: *item.LastModified,
		Size:    *item.Size,
		Owner:   owner,
		Tags:    tags,
	}
	return blobInfo
}

func getTags(key string, s *S3Client) string {
	tags := ""
	bucket := getBucket(s.ClientNum)
	//h.Log("DEBUG", fmt.Sprintf("Retrieving tags from %s ...", key))
	input3 := &s3.GetObjectTaggingInput{
		Bucket: &bucket,
		Key:    &key,
	}
	tagObj, err3 := getS3Api(s.ClientNum).GetObjectTagging(context.TODO(), input3)
	if err3 != nil {
		h.Log("WARN", fmt.Sprintf("GetObjectTagging for %s failed with %v", key, err3))
	}
	if tagObj != nil && tagObj.TagSet != nil && len(tagObj.TagSet) > 0 {
		h.Log("DEBUG", fmt.Sprintf("Retrieved tags %v ", tagObj.TagSet))
		jsonTags, _ := json.Marshal(tagObj.TagSet)
		tags = string(jsonTags)
	}
	return tags
}
