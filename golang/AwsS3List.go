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
	"encoding/json"
	"flag"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"log"
	"time"
)

// S3ListObjectsAPI defines the interface for the ListObjectsV2 function.
// We use this interface to test the function using a mocked service.
type S3ListObjectsAPI interface {
	ListObjectsV2(ctx context.Context,
		params *s3.ListObjectsV2Input,
		optFns ...func(*s3.Options)) (*s3.ListObjectsV2Output, error)
}

// GetObjects retrieves the objects in an Amazon Simple Storage Service (Amazon S3) bucket
// Inputs:
//     c is the context of the method call, which includes the AWS Region
//     api is the interface that defines the method call
//     input defines the input arguments to the service call.
// Output:
//     If success, a ListObjectsV2Output object containing the result of the service call and nil
//     Otherwise, nil and an error from the call to ListObjectsV2
func GetObjects(c context.Context, api S3ListObjectsAPI, input *s3.ListObjectsV2Input) (*s3.ListObjectsV2Output, error) {
	return api.ListObjectsV2(c, input)
}

func main() {
	bucket := flag.String("b", "", "The name of the Bucket")
	prefix := flag.String("p", "", "The name of the Prefix")
	// Casting/converting int to int32 is somehow hard ...
	maxkeys := 0
	flag.IntVar(&maxkeys, "m", 1000, "Integer value for Max Keys (<= 1000)")
	flag.Parse()

	if *bucket == "" {
		log.Printf("ERROR: You must supply the name of a bucket (-b BUCKET_NAME)")
		return
	}

	if *prefix == "" {
		log.Printf("INFO: No prefix (-p PREFIX_STRING). Getting all ...")
		time.Sleep(3 * time.Second)
	}

	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		panic("configuration error, " + err.Error())
	}

	client := s3.NewFromConfig(cfg)

	input := &s3.ListObjectsV2Input{
		Bucket:  bucket,
		Prefix:  prefix,
		MaxKeys: int32(maxkeys),
	}

	found_ttl := 0
	found := 0
	resp, err := GetObjects(context.TODO(), client, input)
	if err != nil {
		println("Got error retrieving list of objects:")
		panic(err.Error())
	}

	fmt.Println("[")
	found = len(resp.Contents)
	i := 0
	for _, item := range resp.Contents {
		j, err := json.Marshal(item)
		if err != nil {
			panic(err)
		}
		i++
		fmt.Print("  ", string(j))
		if !resp.IsTruncated && i < found {
			fmt.Println(",")
		}
	}

	found_ttl += found

	fmt.Println("")
	fmt.Println("]")

	println("")
	log.Printf("Found", found_ttl, "items in bucket", *bucket, "with prefix:", prefix)
}
