# AWS S3 List
Demo script to list all objects from a S3 bucket with CSV format.  
The plan was generating the list of blobRef IDs and compare with the blobRef IDs stored in the OrientDB to find the inconsistency.  
The reason of using GoLang is because I hoped this would be faster than Java or Python.

## DOWNLOAD and INSTALL:
```bash
curl -o /usr/local/bin/aws-s3-list -L https://github.com/hajimeo/samples/raw/master/misc/aws-s3-list_$(uname)
chmod a+x /usr/local/bin/aws-s3-list
```

## Example output
List all objects under node-nxrm-ha1/content/vol-* for the bucket (apac-support-bucket) with 20 concurrency:
```
$ time aws-s3-list -b apac-support-bucket -p "node-nxrm-ha1/content/vol-" -c1 20 > /tmp/all_objects.csv
2021/08/31 15:44:45 INFO: Generating list from bucket: apac-support-bucket ...

2021/08/31 15:44:57 INFO: Printed 20030 items (size: 3426012) in bucket: apac-support-bucket with prefix: node-nxrm-ha1/content/vol-

real	0m11.933s
user	0m1.027s
sys	0m0.471s
```
As you can see, with 20K objects, usually it takes about 10 ~ 20 seconds (very fast!)  
NOTE: When the bucket is small, *without* -c1 is faster.

### ARGUMENTS:
```
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
    -R              Treat -fP value as regex
    -H              No Header line output
    -X              Verbose log output
    -XX             More verbose log output
```

## USAGE EXAMPLE:
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

## ADVANCE USAGE EXAMPLE:
```
aws-s3-list -b apac-support-bucket -p "node-nxrm-ha1/content/vol-" -c1 20 > /tmp/s3-test_objects.csv
# Extract blob ref IDs only:
grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' /tmp/s3-test_objects.csv | sort | uniq > s3-test_blob_refs.out

# Get blob ref IDs from a database backup file:
curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/orient-console.jar"
echo "SELECT blob_ref FROM asset WHERE blob_ref LIKE 's3-test@%'" | java -DexportPath=/tmp/result.json -jar ./orient-console.jar ../sonatype/backups/component-2021-08-30-22-00-00-3.33.0-01.bak
grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' /tmp/result.json | sort | uniq > s3-test_blob_refs_from_db.out

# Check missing blobs:
diff -wy --suppress-common-lines s3-test_blob_refs.out s3-test_blob_refs_from_db.out
1ab44c7d-553a-416c-b0ec-a1e06088f984			      <
234e1975-2e5a-4d0c-9e06-bf85e33de422			      <
23bdb564-a670-4925-81ee-4ba70a33a672			      <
...
```
All above commands would complete within 10 seconds, and the last result means no dead blobs.

NOTE: AWS CLI example to get size, but it's not same as Nexus because it includes *.properties
```
aws s3api list-objects --bucket apac-support-bucket --prefix node-nxrm-ha1/content --output json --query "[sum(Contents[].Size), length(Contents[])]"
```