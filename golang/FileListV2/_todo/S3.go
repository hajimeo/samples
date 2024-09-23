package bs_clients

import (
	"FileListV2/common"
	"bytes"
	"context"
	"database/sql"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	h "github.com/hajimeo/samples/golang/helpers"
	"strings"
	"sync"
	"time"
)

type S3Client struct{}

var s3Api *s3.Client

func (c *S3Client) GetBsClient() interface{} {
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

func (c *S3Client) ReadPath(path string) (string, error) {
	// TODO: Implement
	return "", nil
}

func (c *S3Client) WriteToPath(path string, contents string) error {
	if common.Debug {
		defer h.Elapsed(time.Now().UnixMilli(), "DEBUG Wrote "+path, 0)
	} else {
		defer h.Elapsed(time.Now().UnixMilli(), "WARN  slow file write for path:"+path, 400)
	}
	client := c.GetBsClient().(*s3.Client)
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

func (c *S3Client) RemoveDeleted(path string, contents string) error {
	err := c.WriteToPath(path, contents)
	if err != nil {
		return err
	}
	client := c.GetBsClient().(*s3.Client)
	err = removeTags(path, client)
	if err != nil {
		return err
	}
	bPath := h.PathWithoutExt(path) + ".bytes"
	err = removeTags(bPath, client)
	if err != nil {
		return err
	}
	h.Log("INFO", fmt.Sprintf("Removed 'deleted=true' and S3 tag for path:%s", path))
	return nil
}

func removeTags(path string, client *s3.Client) error {
	baseDir := common.BaseDir
	inputTag := &s3.PutObjectTaggingInput{
		Bucket: &baseDir,
		Key:    &path,
		Tagging: &types.Tagging{
			TagSet: []types.Tag{},
		},
	}
	respTag, err := client.PutObjectTagging(context.TODO(), inputTag)
	if err != nil {
		h.Log("WARN", fmt.Sprintf("Deleting Tag with PutObjectTagging failed. Path: %s. Resp: %v", path, respTag))
	}
	return err
}

func (c *S3Client) ListObjects(dir string, db *sql.DB, printLine func(interface{}, interface{}, *sql.DB)) int64 {
	var subTtl int64
	baseDir := common.BaseDir
	input := &s3.ListObjectsV2Input{
		Bucket:     &baseDir,
		MaxKeys:    aws.Int32(int32(common.MaxKeys)),
		FetchOwner: aws.Bool(common.WithOwner),
		Prefix:     &dir,
	}
	// TODO: below does not seem to be working, as StartAfter should be Key
	if common.ModFromDateTS > 0 {
		input.StartAfter = aws.String(time.Unix(common.ModFromDateTS, 0).UTC().Format("2006-01-02T15:04:05.000Z"))
	}

	client := c.GetBsClient().(*s3.Client)
	for {
		resp, err := client.ListObjectsV2(context.TODO(), input)
		if err != nil {
			println("Got error retrieving list of objects:")
			// Fail immediately
			panic(err.Error())
		}

		//https://stackoverflow.com/questions/25306073/always-have-x-number-of-goroutines-running-at-any-time
		wgTags := sync.WaitGroup{}                     // *
		guardTags := make(chan struct{}, common.Conc2) // **
		for _, item := range resp.Contents {
			if len(common.Filter4FileName) == 0 || strings.Contains(*item.Key, common.Filter4FileName) {
				subTtl++
				guardTags <- struct{}{}                                     // **
				wgTags.Add(1)                                               // *
				go func(client *s3.Client, item types.Object, db *sql.DB) { // **
					printLine(item, client, db)
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

// TODO: implement
/*func main() {
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String("us-west-2"),
	})
	if err != nil {
		log.Fatalf("Failed to create session: %v", err)
	}

	svc := s3.New(sess)

	ctx := context.Background()

	var params *s3.ListObjectsInput
	params = &s3.ListObjectsInput{
		Bucket: aws.String(bucketName),
		Prefix: aws.String(prefix),
	}

	for {
		result, err := svc.ListObjects(ctx, params)
		if err != nil {
			log.Fatalf("Failed to list objects: %v", err)
		}

		for _, obj := range result.Contents {
			dirName := *obj.Key
			if len(dirName) > len(prefix) && dirName[len(prefix)-1] == '/' {
				fmt.Printf("Directory: %s\n", dirName[len(prefix):])

				// Apply your filter here
				if applyFilter(dirName[len(prefix):]) {
					fmt.Printf("  Matching filter: %s\n", dirName[len(prefix):])
				}

				// Recursively process child directories
				processChildren(svc, ctx, dirName[len(prefix)+1:], prefix)
			}
		}

		// Check if there are more objects
		if result.IsTruncated {
			params.Marker = result.NextMarker
		} else {
			break
		}
	}
}

func applyFilter(name string) bool {
	// Implement your filter logic here
	// For example, to match directories starting with 'test':
	return strings.HasPrefix(name, "test")
}

func processChildren(svc *s3.S3, ctx context.Context, keyPrefix string, basePrefix string) {
	var params *s3.ListObjectsInput
	params = &s3.ListObjectsInput{
		Bucket: aws.String(bucketName),
		Prefix: aws.String(keyPrefix + "/"),
	}

	for {
		result, err := svc.ListObjects(ctx, params)
		if err != nil {
			log.Fatalf("Failed to list objects: %v", err)
		}

		for _, obj := range result.Contents {
			fullPath := keyPrefix + "/" + *obj.Key
			if len(fullPath) > len(basePrefix) && fullPath[len(basePrefix)-1] == '/' {
				fmt.Printf("Subdirectory: %s\n", fullPath[len(basePrefix):])

				// Apply your filter here
				if applyFilter(fullPath[len(basePrefix):]) {
					fmt.Printf("  Matching filter: %s\n", fullPath[len(basePrefix):])
				}

				// Recursively process child directories
				processChildren(svc, ctx, fullPath, basePrefix)
			}
		}

		// Check if there are more objects
		if result.IsTruncated {
			params.Marker = result.NextMarker
		} else {
			break
		}
	}
}*/
