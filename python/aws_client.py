import boto3
accessKey = "*********"
secretKey = "*********"
s3_bucket = "apac-support-bucket"
s3_prefix = "node-nxrm-haX"

s3 = boto3.client('s3', aws_access_key_id=accessKey, aws_secret_access_key=secretKey)

partial_list = s3.list_objects_v2(Bucket=s3_bucket, Prefix=s3_prefix)
obj_list = partial_list['Contents']
while partial_list['IsTruncated']:
    next_token = partial_list['NextContinuationToken']
    partial_list = s3.list_objects_v2(Bucket=s3_bucket, Prefix=s3_prefix, ContinuationToken=next_token)
    obj_list.extend(partial_list['Contents'])
print(obj_list)