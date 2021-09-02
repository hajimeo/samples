/*
https://docs.aws.amazon.com/code-samples/latest/catalog/gov2-s3-ListObjects-ListObjectsv2.go.html
https://docs.aws.amazon.com/AmazonS3/latest/userguide/ListingKeysUsingAPIs.html

#go mod init github.com/hajimeo/samples/golang
#go mod tidy
go build -o ../misc/aws-s3-list_$(uname) AwsS3List.go && env GOOS=linux GOARCH=amd64 go build -o ../misc/aws-s3-list_Linux AwsS3List.go
export AWS_REGION=ap-southeast-2 AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=yyyy
../misc/aws-s3-list_Darwin -b apac-support-bucket -p "node-nxrm-ha1/content/vol-"
*/

package main

import (
	"bytes"
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
	"sync/atomic"
)

func usage() {
	fmt.Println(`
List AWS S3 objects as CSV (Key,LastModified,Size,Owner,Tags).
Usually it takes about 1 second for 1000 objects.

DOWNLOAD and INSTALL:
    curl -o /usr/local/bin/aws-s3-list -L https://github.com/hajimeo/samples/raw/master/misc/aws-s3-list_$(uname)
    chmod a+x /usr/local/bin/aws-s3-list
    
USAGE EXAMPLES:
    # Preparation: set AWS environment variables
    $ export AWS_REGION=ap-southeast-2 AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=yyyy

    # List all objects under the Backet-name bucket 
    $ aws-s3-list -b Backet-name

    # Check the count and size of all .bytes file under nxrm3/content/ (including tmp)
    $ aws-s3-list -b Backet-name -p "nxrm3/content/" -f ".bytes" -c1 50 >/dev/null

    # List sub directories (-L) under nxrm3/content/vol* 
    $ aws-s3-list -b Backet-name -p "nxrm3/content/vol-" -L

    # Parallel execution (concurrency 10)
    $ aws-s3-list -b Backet-name -p "nxrm3/content/vol-" -c1 10 > all_objects.csv

    # Parallel execution (concurrency 4 * 100) with Tags and Owner (approx. 300 lines per sec)
    $ aws-s3-list -b Backet-name -p "nxrm3/content/vol-" -T -O -c1 4 -c2 100 > all_with_tags.csv

    # Parallel execution (concurrency 4 * 100) with all properties (approx. 250 lines per sec)
    $ aws-s3-list -b Backet-name -p "nxrm3/content/vol-" -f ".properties" -P -c1 4 -c2 100 > all_with_props.csv

    # List all objects which proerties contain 'deleted=true'
    $ aws-s3-list -b Backet-name -p "nxrm3/content/vol-" -fP "deleted=true" -P -c1 4 -c2 100 > soft_deleted.csv

ARGUMENTS:
    -p Prefix_str   List objects which key starts with this prefix
    -f Filter_str   List objects which key contains this string (much slower)
    -fP Filter_str  List .properties file (no .bytes files) which contains this string (much slower)
                    Equivalent of -f ".properties" and -P.
    -n topN_num     Return first/top N results only
    -m MaxKeys_num  Batch size number. Default is 1000
    -c1 concurrency Concurrency number for Prefix (-p xxxx/content/vol-), execute in parallel per sub directory
    -c2 concurrency Concurrency number for Tags (-T) and also Properties (-P)
    -L              With -p, list sub folders under prefix
    -O              Get Owner display name (can be slightly slower)
    -T              Get Tags (can be slower)
    -P              Get properties (can be very slower)
    -H              No Header line output
    -X              Verbose log output
    -XX             More verbose log output`)
}

// Arguments
var _BUCKET *string
var _PREFIX *string
var _FILTER *string
var _FILTER2 *string
var _MAXKEYS *int
var _TOP_N *int64
var _CONC_1 *int
var _CONC_2 *int
var _LIST_DIRS *bool
var _WITH_OWNER *bool
var _WITH_TAGS *bool
var _WITH_PROPS *bool
var _NO_HEADER *bool
var _DEBUG *bool
var _DEBUG2 *bool

var _PRINTED_N int64 // Atomic (maybe slower?)
var _TTL_SIZE int64  // Atomic (maybe slower?)

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

	// Checking props first because if _FILTER2 is given and match, do not check others.
	props := ""
	if *_WITH_PROPS && strings.HasSuffix(*item.Key, ".properties") {
		_log("DEBUG", fmt.Sprintf("Getting properties for %s", *item.Key))
		_inputO := &s3.GetObjectInput{
			Bucket: _BUCKET,
			Key:    item.Key,
		}
		_obj, err := client.GetObject(context.TODO(), _inputO)
		if err != nil {
			_log("DEBUG", fmt.Sprintf("Retrieving %s failed with %s. Ignoring...", *item.Key, err.Error()))
		} else {
			buf := new(bytes.Buffer)
			_, err := buf.ReadFrom(_obj.Body)
			if err != nil {
				_log("DEBUG", fmt.Sprintf("Readubg object for %s failed with %s. Ignoring...", *item.Key, err.Error()))
			} else {
				if len(*_FILTER2) == 0 || strings.Contains(buf.String(), *_FILTER2) {
					// Should also escape '"'?
					props = strings.ReplaceAll(strings.TrimSpace(buf.String()), "\n", ",")
				} else {
					_log("DEBUG", fmt.Sprintf("Properties of %s does not contain %s. Not outputting entire line...", *item.Key, *_FILTER2))
					return
				}
			}
		}
	}

	if *_WITH_OWNER {
		output = fmt.Sprintf("%s,\"%s\"", output, *item.Owner.DisplayName)
	}

	// Get tags if -with-tags is presented.
	if *_WITH_TAGS {
		_log("DEBUG", fmt.Sprintf("Getting tags for %s", *item.Key))
		_inputT := &s3.GetObjectTaggingInput{
			Bucket: _BUCKET,
			Key:    item.Key,
		}
		_tag, err := client.GetObjectTagging(context.TODO(), _inputT)
		if err != nil {
			_log("DEBUG", fmt.Sprintf("Retrieving tags for %s failed with %s. Ignoring...", *item.Key, err.Error()))
			output = fmt.Sprintf("%s,\"\"", output)
		} else {
			//_log("DEBUG", fmt.Sprintf("Retrieved tags for %s", *item.Key))
			tag_output := tags2str(_tag.TagSet)
			output = fmt.Sprintf("%s,\"%s\"", output, tag_output)
		}
	}

	if *_WITH_PROPS {
		output = fmt.Sprintf("%s,\"%s\"", output, props)
	}
	atomic.AddInt64(&_PRINTED_N, 1)
	atomic.AddInt64(&_TTL_SIZE, item.Size)
	fmt.Println(output)
}

func listObjects(client *s3.Client, prefix string) {
	input := &s3.ListObjectsV2Input{
		Bucket:     _BUCKET,
		MaxKeys:    int32(*_MAXKEYS),
		FetchOwner: *_WITH_OWNER,
		Prefix:     &prefix,
	}

	for {
		resp, err := client.ListObjectsV2(context.TODO(), input)
		if err != nil {
			println("Got error retrieving list of objects:")
			panic(err.Error())
		}

		//https://stackoverflow.com/questions/25306073/always-have-x-number-of-goroutines-running-at-any-time
		wgTags := sync.WaitGroup{}                 // *
		guardTags := make(chan struct{}, *_CONC_2) // **

		for _, item := range resp.Contents {
			if len(*_FILTER) == 0 || strings.Contains(*item.Key, *_FILTER) {
				guardTags <- struct{}{}                         // **
				wgTags.Add(1)                                   // *
				go func(client *s3.Client, item types.Object) { // **
					printLine(client, item)
					<-guardTags   // **
					wgTags.Done() // *
				}(client, item)
			}

			if *_TOP_N > 0 && *_TOP_N <= _PRINTED_N {
				_log("DEBUG", fmt.Sprintf("Printed %d >= %d", _PRINTED_N, *_TOP_N))
				break
			}
		}
		wgTags.Wait() // *

		// Continue if truncated (more data available) and if not reaching to the top N.
		if *_TOP_N > 0 && *_TOP_N <= _PRINTED_N {
			_log("DEBUG", fmt.Sprintf("Found %d and reached %d", _PRINTED_N, *_TOP_N))
			break
		} else if resp.IsTruncated {
			_log("DEBUG", fmt.Sprintf("Set ContinuationToken to %s", *resp.NextContinuationToken))
			input.ContinuationToken = resp.NextContinuationToken
		} else {
			_log("DEBUG", "NOT Truncated (completed).")
			break
		}
	}
}

func main() {
	if len(os.Args) == 1 || os.Args[1] == "-h" || os.Args[1] == "--help" {
		usage()
		os.Exit(0)
	}

	_BUCKET = flag.String("b", "", "The name of the Bucket")
	_PREFIX = flag.String("p", "", "The name of the Prefix")
	_FILTER = flag.String("f", "", "Filter string for keys")
	_FILTER2 = flag.String("fP", "", "Filter string for properties (-P is required)")
	_MAXKEYS = flag.Int("m", 1000, "Integer value for Max Keys (<= 1000)")
	_TOP_N = flag.Int64("n", 0, "Return only first N keys (0 = no limit)")
	_CONC_1 = flag.Int("c1", 1, "Concurrent number for Prefix")
	_CONC_2 = flag.Int("c2", 16, "Concurrent number for Tags")
	_LIST_DIRS = flag.Bool("L", false, "If true, just list directories and exit")
	_WITH_OWNER = flag.Bool("O", false, "If true, also get owner display name")
	_WITH_TAGS = flag.Bool("T", false, "If true, also get tags of each object")
	_WITH_PROPS = flag.Bool("P", false, "If true, also get the contents of .properties files")
	_NO_HEADER = flag.Bool("H", false, "If true, no header line")
	_DEBUG = flag.Bool("X", false, "If true, verbose logging")
	_DEBUG2 = flag.Bool("XX", false, "If true, more verbose logging")
	flag.Parse()

	if *_DEBUG2 {
		_DEBUG = _DEBUG2
	}

	if *_BUCKET == "" {
		_log("ERROR", "You must supply the name of a bucket (-b BUCKET_NAME)")
		os.Exit(1)
	}

	if len(*_FILTER2) > 0 {
		*_FILTER = ".properties"
		*_WITH_PROPS = true
	}

	if !*_NO_HEADER && *_PREFIX == "" {
		_log("WARN", "Without prefix (-p PREFIX_STRING), it can take longer.")
		//time.Sleep(3 * time.Second)
	}

	if !*_NO_HEADER && *_WITH_TAGS {
		_log("WARN", "With Tags (-T), it can be much slower.")
	}

	if !*_NO_HEADER && *_WITH_PROPS {
		_log("WARN", "With Properties (-P), it can be extremely slower.")
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
	subDirs := make([]string, 1)
	subDirs = append(subDirs, *_PREFIX)

	_log("INFO", fmt.Sprintf("Generating list from bucket: %s ...", *_BUCKET))

	if *_LIST_DIRS || *_CONC_1 > 1 {
		_log("DEBUG", fmt.Sprintf("Retriving sub folders under %s", *_PREFIX))
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
		// replacing subDirs with the result (excluding 1 as it would make slower)
		if *_CONC_1 > 1 && len(resp.CommonPrefixes) > 1 {
			subDirs = make([]string, len(resp.CommonPrefixes))
		}
		for _, item := range resp.CommonPrefixes {
			// TODO: somehow empty value is added into subDirs even below
			if len(strings.TrimSpace(*item.Prefix)) == 0 {
				continue
			}
			if *_CONC_1 > 1 && len(resp.CommonPrefixes) > 1 {
				subDirs = append(subDirs, *item.Prefix)
			}
			if *_LIST_DIRS {
				fmt.Println(*item.Prefix)
			}
		}

		if *_LIST_DIRS {
			return
		}
		_log("DEBUG", fmt.Sprintf("Sub directories: %v", subDirs))
	}

	if *_CONC_1 < 1 {
		_log("ERROR", "_CONC_1 is lower than 1.")
		os.Exit(1)
	}

	if !*_NO_HEADER {
		fmt.Print("Key,LastModified,Size")
		if *_WITH_OWNER {
			fmt.Print(",Owner")
		}
		if *_WITH_TAGS {
			fmt.Print(",Tags")
		}
		if *_WITH_PROPS {
			fmt.Print(",Properties")
		}
		fmt.Println("")
	}

	wg := sync.WaitGroup{}
	guard := make(chan struct{}, *_CONC_1)

	for _, s := range subDirs {
		if len(s) == 0 {
			//_log("DEBUG", "Ignoring empty prefix.")
			continue
		}
		_log("DEBUG", "Prefix: "+s)
		guard <- struct{}{}
		wg.Add(1) // *
		go func(client *s3.Client, prefix string) {
			_log("DEBUG", fmt.Sprintf("Listing objects for %s ...", prefix))
			listObjects(client, prefix)
			<-guard
			wg.Done()
		}(client, s)
	}

	wg.Wait()
	println("")
	_log("INFO", fmt.Sprintf("Printed %d items (size: %d) in bucket: %s with prefix: %s", _PRINTED_N, _TTL_SIZE, *_BUCKET, *_PREFIX))
}
