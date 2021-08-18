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
List AWS S3 objects as CSV (Key,LastModified,Size,Owner,Tags).
Usually it takes about 1 second for 1000 objects.

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
    -Lp            With -p, get the list of sub folders from prefix, then get objects in parallel
    -O             To get Owner display name (might be slightly slower)
    -T             To get Tags (will be slower)
    -H             No Header line output
    -X             Verbose log output
    -XX            More verbose log output`)
}

// Arguments
var _BUCKET *string
var _PREFIX *string
var _FILTER *string
var _MAXKEYS *int
var _TOP_N *int
var _CON_N *int
var _LIST_DIRS *bool
var _PARALLEL *bool
var _WITH_OWNER *bool
var _WITH_TAGS *bool
var _NO_HEADER *bool
var _DEBUG *bool
var _DEBUG2 *bool

var found_ttl = 0
var isNotTruncated = false

func _log(level string, message string) {
	if level != "DEBUG" || *_DEBUG {
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

func printLine(client *s3.Client, item types.Object) {
	output := fmt.Sprintf("\"%s\",\"%s\",%d", *item.Key, item.LastModified, item.Size)
	if *_WITH_OWNER {
		output = fmt.Sprintf("%s,\"%s\"", output, *item.Owner.DisplayName)
	}
	// Get tags if -with-tags is presented.
	if *_WITH_TAGS {
		_log("DEBUG", fmt.Sprintf("Getting tags for %s", *item.Key))
		_input := &s3.GetObjectTaggingInput{
			Bucket: _BUCKET,
			Key:    item.Key,
		}
		_log("DEBUG", "before GetObjectTagging")
		_tag, err := client.GetObjectTagging(context.TODO(), _input)
		if err != nil {
			_log("DEBUG", fmt.Sprintf("Retrieving tags for %s failed. Ignoring...", *item.Key))
		} else {
			_log("DEBUG", output)
			tag_output := tags2str(_tag.TagSet)
			_log("DEBUG", tag_output)
			output = fmt.Sprintf("%s,\"%s\"", output, tag_output)
		}
	}
	_log("DEBUG", output)
	fmt.Println(output)
}

func listObjects(client *s3.Client, input *s3.ListObjectsV2Input, _PREFIX *string, ttl *int) bool {
	input.Prefix = _PREFIX
	resp, err := client.ListObjectsV2(context.TODO(), input)
	if err != nil {
		println("Got error retrieving list of objects:")
		panic(err.Error())
	}

	//https://stackoverflow.com/questions/25306073/always-have-x-number-of-goroutines-running-at-any-time
	var wgTags = sync.WaitGroup{}         // *
	guard := make(chan struct{}, *_CON_N) // **

	for _, item := range resp.Contents {
		if len(*_FILTER) == 0 || strings.Contains(*item.Key, *_FILTER) {
			*ttl++
			guard <- struct{}{} // **
			wgTags.Add(1)       // *
			go func(client *s3.Client, item types.Object) {
				printLine(client, item)
				<-guard       // **
				wgTags.Done() // *
			}(client, item)
		}

		if *_TOP_N > 0 && *_TOP_N <= *ttl {
			_log("DEBUG", fmt.Sprintf("Printed %d >= %d", *ttl, *_TOP_N))
			break
		}
	}
	wgTags.Wait() // *

	if resp.IsTruncated {
		_log("DEBUG", fmt.Sprintf("Set ContinuationToken to %s", *resp.NextContinuationToken))
		input.ContinuationToken = resp.NextContinuationToken
	}

	return resp.IsTruncated
}

func main() {
	if len(os.Args) == 1 || os.Args[1] == "-h" || os.Args[1] == "--help" {
		usage()
		os.Exit(0)
	}

	_BUCKET = flag.String("b", "", "The name of the Bucket")
	_PREFIX = flag.String("p", "", "The name of the Prefix")
	_FILTER = flag.String("f", "", "Filter string for keys")
	_MAXKEYS = flag.Int("m", 1000, "Integer value for Max Keys (<= 1000)")
	_TOP_N = flag.Int("n", 0, "Return only first N keys (0 = no limit)")
	_CON_N = flag.Int("c", 16, "Experimental: Concurrent number for Tags")
	_LIST_DIRS = flag.Bool("L", false, "If true, just list directories and exit")
	_PARALLEL = flag.Bool("Lp", false, "If true, parallel execution per sub directory")
	_WITH_OWNER = flag.Bool("O", false, "If true, also get owner display name")
	_WITH_TAGS = flag.Bool("T", false, "If true, also get tags of each object")
	_NO_HEADER = flag.Bool("H", false, "If true, no header line")
	_DEBUG = flag.Bool("X", false, "If true, verbose logging")
	_DEBUG2 = flag.Bool("XX", false, "If true, more verbose logging")
	flag.Parse()

	if *_DEBUG2 {
		_DEBUG = _DEBUG2
	}

	if *_PARALLEL {
		_LIST_DIRS = _PARALLEL
	}

	if *_BUCKET == "" {
		_log("ERROR", "You must supply the name of a bucket (-b BUCKET_NAME)")
		os.Exit(1)
	}

	if !*_NO_HEADER && *_PREFIX == "" {
		_log("WARN", "Without prefix (-p PREFIX_STRING), this might take longer.")
		time.Sleep(2 * time.Second)
	}

	if !*_NO_HEADER && *_WITH_TAGS {
		_log("WARN", "With Tags (-T), this will be extremely slower.")
		time.Sleep(2 * time.Second)
	}

	cfg, err := config.LoadDefaultConfig(context.TODO())
	if *_DEBUG2 {
		// https://aws.github.io/aws-sdk-go-v2/docs/configuring-sdk/logging/
		cfg, err = config.LoadDefaultConfig(context.TODO(), config.WithClientLogMode(aws.LogRetries|aws.LogRequest))
	}
	if err != nil {
		panic("configuration error, " + err.Error())
	}

	client := s3.NewFromConfig(cfg)

	// TODO: create list of prefix
	if *_LIST_DIRS {
		_log("INFO", fmt.Sprintf("Retriving sub folders under %s", *_PREFIX))
		delimiter := "/"
		inputV1 := &s3.ListObjectsInput{
			Bucket:    _BUCKET,
			Prefix:    _PREFIX,
			MaxKeys:   int32(*_MAXKEYS),
			Delimiter: &delimiter,
		}
		resp, err := client.ListObjects(context.TODO(), inputV1)
		if err != nil {
			println("Got error retrieving list of objects:")
			panic(err.Error())
		}
		for _, item := range resp.CommonPrefixes {
			// TODO: populate list of prefix
			fmt.Println(*item.Prefix)
		}

		if !*_PARALLEL {
			return
		}
	}

	input := &s3.ListObjectsV2Input{
		Bucket:     _BUCKET,
		MaxKeys:    int32(*_MAXKEYS),
		FetchOwner: *_WITH_OWNER,
	}

	if !*_NO_HEADER {
		fmt.Print("Key,LastModified,Size")
		if *_WITH_OWNER {
			fmt.Print(",Owner")
		}
		if *_WITH_TAGS {
			fmt.Print(",Tags")
		}
		fmt.Println("")
	}

	var wg = sync.WaitGroup{}

	// TODO: Loop the list of prefix
	//for {
	for {
		if !listObjects(client, input, _PREFIX, &found_ttl) {
			_log("DEBUG", "NOT Truncated (completed).")
			break
		}
		if *_TOP_N > 0 && *_TOP_N <= found_ttl {
			_log("DEBUG", fmt.Sprintf("Printed %d which is greater equal than %d.", found_ttl, *_TOP_N))
			break
		}
	}
	//}

	wg.Wait()
	println("")
	_log("INFO", fmt.Sprintf("Found %d items in bucket: %s with prefix: %s", found_ttl, *_BUCKET, *_PREFIX))
}
