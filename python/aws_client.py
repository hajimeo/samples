#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
Test / demo / example of AWS client in Python

aws_client.py <access-key> <secret-key> <bucket> [<prefix>]
'''

import sys, pprint
import boto3

accessKey = sys.argv[1]
secretKey = sys.argv[2]
s3_bucket = sys.argv[3]
s3_prefix = ""
if len(sys.argv) > 4:
    s3_prefix = sys.argv[4]

contents = None
s3 = boto3.client('s3', aws_access_key_id=accessKey, aws_secret_access_key=secretKey)
# @see: https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3.html#S3.Client.list_objects_v2
response = s3.list_objects_v2(Bucket=s3_bucket, Prefix=s3_prefix)

if 'Contents' in response:
    contents = response['Contents']

if 'IsTruncated' in response:
    while response['IsTruncated']:
        next_token = response['NextContinuationToken']
        response = s3.list_objects_v2(Bucket=s3_bucket, Prefix=s3_prefix, ContinuationToken=next_token)
        contents.extend(response['Contents'])

pprint.pprint(contents)
