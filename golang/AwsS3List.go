/*
https://docs.aws.amazon.com/code-samples/latest/catalog/gov2-s3-ListObjects-ListObjectsv2.go.html
https://docs.aws.amazon.com/AmazonS3/latest/userguide/ListingKeysUsingAPIs.html

#go mod init github.com/hajimeo/samples/golang
#go mod tidy
go build -o ../misc/aws-s3-list_$(uname) AwsS3List.go
env GOOS=linux GOARCH=amd64 go build -o ../misc/aws-s3-list_Linux AwsS3List.go
export AWS_REGION=ap-southeast-2 AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=yyyy
../misc/aws-s3-list_Darwin -b apac-support-bucket -p node-nxrm-ha1/
*/

// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX - License - Identifier: Apache - 2.0

package main

import (
	"context"
	"flag"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"log"
	"os"
	"strings"
	"sync"
	"time"
)

func usage() {
	fmt.Println(`
List AWS S3 objects as CSV (Key,LastModified,Size,Owner,Tags)

DOWNLOAD and INSTALL:
    curl -o /usr/local/bin/aws-s3-list -L https://github.com/hajimeo/samples/raw/master/misc/aws-s3-list_$(uname)
    chmod a+x /usr/local/bin/aws-s3-list
    
USAGE EXAMPLE:
    # Preparation: set AWS environment variables
    $ export AWS_REGION=ap-southeast-2 AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=yyyy

    # List all objects under Backet-name bucket 
    $ aws-s3-list -b Backet-name

    # List sub directories (-L) under nxrm3/content/vol* 
    $ aws-s3-list -b Backet-name -p "nxrm3/content/vol-" -L

    # Parallel execution
    $ aws-s3-list -b Backet-name -p "nxrm3/content/vol-" -L | xargs -I{} -P4 aws-s3-list -b Backet-name -H -p "{}" > all_objects.csv

    # Parallel execution with Owner & Tags and 100 concurrency
    $ aws-s3-list -b Backet-name -p "nxrm3/content/vol-" -L | xargs -I{} -P4 aws-s3-list -b Backet-name -H -p "{}" -T -O -c 100 > all_with_tags.csv

OPTIONAL SWITCHES:
    -p Prefix_str  Return objects which key starts with this prefix
    -f Filter_str  Return objects which key contains this string (much slower than prefix)
    -n topN_num    Return first/top N results only
    -m MaxKeys_num Batch size number. Default is 1000
    -c concurrency Utilised only for retrieving Tags (-T)
    -L             With -p, list sub folders under prefix
    -O             To get Owner display name (might be slightly slower)
    -T             To get Tags (will be slower)
    -H             No Header line output
    -X             Verbose log output
    -XX            More verbose log output
`)
}

func _log(level string, message string, debug bool) {
	if level != "DEBUG" || debug {
		log.Printf("%s: %s\n", level, message)
	}
}

func tags2str(tagset []types.Tag) string {
	str := ""
	for _, _t := range tagset {
		if len(str) == 0 {
			str = fmt.Sprintf("%s=%s", *_t.Key, *_t.Value)
		} else {
			str = fmt.Sprintf("%s&%s=%s", str, *_t.Key, *_t.Value)
		}
	}
	return str
}

func printLine(client *s3.Client, bucket *string, item types.Object, withOwner *bool, withTags *bool, debug *bool) {
	output := fmt.Sprintf("\"%s\",\"%s\",%d", *item.Key, item.LastModified, item.Size)
	if *withOwner {
		output = fmt.Sprintf("%s,\"%s\"", output, *item.Owner.DisplayName)
	}
	// Get tags if -with-tags is presented.
	if *withTags {
		_log("DEBUG", fmt.Sprintf("Getting tags for %s", *item.Key), *debug)
		_input := &s3.GetObjectTaggingInput{
			Bucket: bucket,
			Key:    item.Key,
		}
		_log("DEBUG", "before GetObjectTagging", *debug)
		_tag, err := client.GetObjectTagging(context.TODO(), _input)
		if err != nil {
			_log("DEBUG", fmt.Sprintf("Retrieving tags for %s failed. Ignoring...", *item.Key), *debug)
		} else {
			_log("DEBUG", output, *debug)
			tag_output := tags2str(_tag.TagSet)
			_log("DEBUG", tag_output, *debug)
			output = fmt.Sprintf("%s,\"%s\"", output, tag_output)
		}
	}
	_log("DEBUG", output, *debug)
	fmt.Println(output)
}

func main() {
	if len(os.Args) == 1 || os.Args[1] == "-h" || os.Args[1] == "--help" {
		usage()
		os.Exit(0)
	}

	bucket := flag.String("b", "", "The name of the Bucket")
	prefix := flag.String("p", "", "The name of the Prefix")
	filter := flag.String("f", "", "Filter string for keys")
	cNum := flag.Int("c", 16, "Experimental: Concurrent number for Tags")
	listDirs := flag.Bool("L", false, "If true, just list directories and exit")
	withOwner := flag.Bool("O", false, "If true, also get owner display name")
	withTags := flag.Bool("T", false, "If true, also get tags of each object")
	noHeader := flag.Bool("H", false, "If true, no header line")
	debug := flag.Bool("X", false, "If true, verbose logging")
	debug2 := flag.Bool("XX", false, "If true, more verbose logging")
	topN := flag.Int("n", 0, "Return only first N keys (0 = no limit)")
	// Casting/converting int to int32 is somehow hard ...
	maxkeys := flag.Int("m", 1000, "Integer value for Max Keys (<= 1000)")
	flag.Parse()

	if *debug2 {
		debug = debug2
	}

	if *bucket == "" {
		_log("ERROR", "You must supply the name of a bucket (-b BUCKET_NAME)", *debug)
		os.Exit(1)
	}

	if !*noHeader && *prefix == "" {
		_log("WARN", "Without prefix (-p PREFIX_STRING), this might take longer.", *debug)
		time.Sleep(2 * time.Second)
	}

	if !*noHeader && *withTags {
		_log("WARN", "With Tags (-T), this will be extremely slower.", *debug)
		time.Sleep(2 * time.Second)
	}

	cfg, err := config.LoadDefaultConfig(context.TODO())
	if *debug2 {
		// https://aws.github.io/aws-sdk-go-v2/docs/configuring-sdk/logging/
		cfg, err = config.LoadDefaultConfig(context.TODO(), config.WithClientLogMode(aws.LogRetries|aws.LogRequest))
	}
	if err != nil {
		panic("configuration error, " + err.Error())
	}

	client := s3.NewFromConfig(cfg)

	if *listDirs {
		_log("INFO", fmt.Sprintf("Retriving sub folders under %s", *prefix), *debug)
		delimiter := "/"
		inputV1 := &s3.ListObjectsInput{
			Bucket:    bucket,
			Prefix:    prefix,
			MaxKeys:   int32(*maxkeys),
			Delimiter: &delimiter,
		}
		resp, err := client.ListObjects(context.TODO(), inputV1)
		if err != nil {
			println("Got error retrieving list of objects:")
			panic(err.Error())
		}
		for _, item := range resp.CommonPrefixes {
			fmt.Println(*item.Prefix)
		}
		return
	}

	input := &s3.ListObjectsV2Input{
		Bucket:     bucket,
		Prefix:     prefix,
		MaxKeys:    int32(*maxkeys),
		FetchOwner: *withOwner,
	}

	found_ttl := 0
	if !*noHeader {
		fmt.Print("Key,LastModified,Size")
		if *withOwner {
			fmt.Print(",Owner")
		}
		if *withTags {
			fmt.Print(",Tags")
		}
		fmt.Println("")
	}

	//https://stackoverflow.com/questions/25306073/always-have-x-number-of-goroutines-running-at-any-time
	var wg = sync.WaitGroup{}           // *
	guard := make(chan struct{}, *cNum) // **

	for {
		resp, err := client.ListObjectsV2(context.TODO(), input)
		if err != nil {
			println("Got error retrieving list of objects:")
			panic(err.Error())
		}

		i := 0
		for _, item := range resp.Contents {
			if len(*filter) == 0 || strings.Contains(*item.Key, *filter) {
				i++                 // counting how many printed
				guard <- struct{}{} // **
				wg.Add(1)           // *
				go func(client *s3.Client, bucket *string, item types.Object, withOwner *bool, withTags *bool, debug *bool) {
					printLine(client, bucket, item, withOwner, withTags, debug)
					<-guard   // **
					wg.Done() // *
				}(client, bucket, item, withOwner, withTags, debug)
			}

			if *topN > 0 && *topN <= (found_ttl+i) {
				_log("DEBUG", fmt.Sprintf("Printed %d >= %d", (found_ttl+i), *topN), *debug)
				break
			}
		}

		found_ttl += len(resp.Contents)
		if *topN > 0 && *topN <= found_ttl {
			_log("DEBUG", fmt.Sprintf("Printed %d >= %d .", (found_ttl), *topN), *debug)
			break
		}
		if !resp.IsTruncated {
			_log("DEBUG", "Truncated, so stopping.", *debug)
			break
		}
		input.ContinuationToken = resp.NextContinuationToken
		_log("DEBUG", fmt.Sprintf("Set ContinuationToken to %s", *resp.NextContinuationToken), *debug)
	}

	wg.Wait() // *
	println("")
	_log("INFO", fmt.Sprintf("Found %d items in bucket: %s with prefix: %s", found_ttl, *bucket, *prefix), *debug)
}
