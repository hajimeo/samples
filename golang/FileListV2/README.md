# File List V2
- List files from specified location (File, S3, Azure, etc.)
- Find missing blobs in database (Dead Blobs)
- Find missing blobs in blob store (Orphaned Blobs)
- (no need any more?) Remove `deleted=true` lines from the specified files in a text file or while listing

## Download and Install:
Saving the binary as `filelist2` as an example:
```bash
curl -o ./filelist2 -L https://github.com/hajimeo/samples/raw/master/misc/filelistv2_$(uname)_$(uname -m)
chmod a+x ./filelist2
```

## Display help:
```
$ filelist2 --help
```
NOTE: The arguments, which name starts with a Capital letter, are boolean type. `-X` and `-XX` for Debug.

## Usage Examples

### List files under the Blob store content `-b "blob-store-uri"`
```
filelist2 -b "./sonatype-work/nexus3/blobs/default/content"
filelist2 -b "file://sonatype-work/nexus3/blobs/default/content"
TODO: filelist2 -b "s3://s3-test-bucket/s3-test-prefix/content"
TODO: filelist2 -b "az://azure-test-container/azure-test-prefix/content"
TODO: filelist2 -b "gs://google-test-storage/google-test-prefix/content"
```
#### List files which path matches with `-p "path-filter"` with the concurrency N `-c N`, and save to a file with `-s "save-to-file-path"`
```
filelist2 -b "$BLOB_STORE" -p "vol-" -c 80 -s "/tmp/file-list_$(date +"%Y%m%d%H%M%S").tsv"
```
NOTE: The recommended concurrency is less than (CPUs / 2) * 10, unless against slow disk/network. 
Also, the concurrency is based on the directories under `-b` (max depth 3), so even the "vol-NN" is less than 50, the concurrency higher than 50 would work.

#### Same as the above but only files which File name matches with `-f "file-filter"`, and including the Properties file content `-P` into the saving file
```
filelist2 -b "$BLOB_STORE" -p "vol-" -f ".propperties" -P -c 80 -s "/tmp/file-list_$(date +"%Y%m%d%H%M%S").tsv"
```
#### Above example with the Modified Date From `-mDF "YYYY-MM-DD"`
```
filelist2 -b "$BLOB_STORE" -p "vol-" -f ".propperties" -P -mDF "$(date -d "1 day ago" +%Y-%m-%d)" -c 80 -s "/tmp/modified_since_yesterday.tsv"
```
#### List .properties which matches `-pRx "regex"`, also including the properties content `-P` in the saving file, but only the first N `-n N`
NOTE: Using `-pRx` automatically does same as `-f ".propperties"`.  
NOTE: To make the regex simpler, in the internal memory, the content of .properties file becomes same as `cat <blobId>.properties | sort | tr '\n' ','`, so that `@xxxxx` lines come before `deletedYyyyy` lines.
```
filelist2 -b "$BLOB_STORE" -p 'vol-' -pRx ",deleted=true" -P -n 10 -c 10 -s /tmp/all_soft_deleted.tsv
filelist2 -b "$BLOB_STORE" -p "vol-" -pRx "@Bucket\.repo-name=docker-proxy,.+deleted=true" -P -c 80 -s ./docker-proxy_soft_deleted.tsv
```
#### List files which does NOT match with `-pRxNot "regex"` but matches with `-pRx "regex"`
NOTE: `-pRxNot` is evaluated before `-pRx`
```
filelist2 -b "$BLOB_STORE" -p "vol-" -pRxNot "BlobStore\.blob-name=.+/maven-metadata.xml.*" -pRx "@Bucket\.repo-name=maven-central,.+deleted=true" -P -c 80 -s ./maven-central_soft_deleteed_excluding_maven-metadata.tsv
```

#### Read the result File `-rF "file-path"`, which each lne contains a blobId, and list the .properties files only `-f "file-name-filter"` with the content `-P`
```
filelist2 -b "$BLOB_STORE" -p "vol-" -rF ./previous_result_without_properties_content.tsv -f ".properties" -P
```
NOTE: The above picks the blobID-like strings automatically, so no need to remove unnecessary strings. If no `-f ".properties"`, the result lines include ".bytes".

#### Use this tool to check the total count and size of all .bytes files
```
file-list -b "$BLOB_STORE" -p 'vol-' -f ".bytes" >/dev/null
... (in the end of the command it outputs the below) ...
13:52:46.972949 INFO  Printed 136895 of 273790 files, size: 2423593014 bytes (elapsed:26s)
```
NOTE: the above means it checked 273790 and 136895 matched with ".bytes" and the total size of the matching files was 2423593014 bytes
```
file-list -b "$BLOB_STORE" -p 'vol-' -pRx "@Bucket\.repo-name=npm-proxy" -P -s ./npm-proxy_all.tsv
rg -o -r '$1' ',size=(\d+)' ./npm-proxy_all.tsv | awk '{ c+=1;s+=$1 }; END { print "blobCount:"c", totalSize:"s" bytes" }'
```

### Remove `deleted=true` lines from the specified files in a text file or while listing
```
# Like dry-run
filelist2 -b "$BLOB_STORE" -p "vol-" -pRx "@Bucket\.repo-name=docker-proxy,.+deleted=true" -P -c 80 -s ./docker-proxy_soft_deleted.tsv
filelist2 -b "$BLOB_STORE" -rF ./docker-proxy_soft_deleted.tsv -RDel -P -c 80 -s docker-proxy_soft_deleted_undeleted.tsv 
```



TODO: The following usage examples are not rewritten yet

### Find blobs which exist in DB but not in Blob store (Dead Blobs)

### Find blobs which exist in Blob store but not in database (Orphaned Blobs)
```
file-list -b "$BLOB_STORE" -p 'vol-' -pRx "@Bucket\.repo-name=npm-proxy" -P -s ./npm-proxy_all.tsv
rg -o -r '$1' ',size=(\d+)' ./npm-proxy_all.tsv | awk '{ c+=1;s+=$1 }; END { print "blobCount:"c", totalSize:"s" bytes" }'
```



---------------------------------------------------------------------------
### (**DANGEROUS**) Remove 'deleted=true' (-RDel and -dF "YYYY-MM-DD") from all or only for 'raw-hosted' repository for undeleting with Reconcile 
NOTE: If using -RDel to remove "deleted=true", recommend to save the STDERR into a file (like above) in case of reverting.
```
file-list -b ./content -p "vol-" -c 10 -RDel -mF "$(date +%Y-%m-%d)" -s ./undelete_all_$(date +"%Y%m%d%H%M%S").tsv 2>./undelete_all.log
```
```
file-list -b ./content -p "vol-" -c 10 -P -R -fP "@Bucket.repo-name=raw-hosted,.+deleted=true" -dF "$(date -d "1 day ago" +%Y-%m-%d)" -RDel -s ./undelete_raw-hosted_$(date +"%Y%m%d%H%M%S").tsv 2>./undelete_raw-hosted.log
```
Create a text file for the Reconcile Task with **Since 0 day** (if S3, Since 1 day)
```
sed -n -E 's/.+([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\..+([0-9]{4}.[0-9]{2}.[0-9]{2}.[0-9]{2}:[0-9]{2}:[0-9]{2}).+/\2,\1/p' ./$(date +"%Y%m%d%H%M%S").tsv > "./reconciliation/$(date '+%Y-%m-%d')"
```

### Remove 'deleted=true' (-RDel) which soft-deleted within 1 day (-dF <YYYY-MM-DD>) against S3 (-bsType S -b <bucket> -p <prefix>/content/vol-) but only "raw-s3-hosted" (-R -fP <regex>) , and outputs the contents of .properties (-P) to check, but *Dry Run* (-Dry)
```
export AWS_REGION=us-east-1 AWS_ACCESS_KEY_ID="xxxxxxxxxxx" AWS_SECRET_ACCESS_KEY="yyyyyyyyyyyyy" #AWS_ENDPOINT_URL="http://127.0.0.1:9000"
S3_BUCKET="apac-support-bucket" S3_PREFIX="$(hostname -s)_s3-test"
file-list -RDel -dF "$(date -d "1 day ago" +%Y-%m-%d)" -bsType S -b "${S3_BUCKET}" -p "${S3_PREFIX}/content/vol-" -R -fP "@Bucket\.repo-name=raw-s3-hosted,.+deleted=true" -P -c 10 -s ./undelete_raw-s3-hosted.tsv -Dry
```
Just get the list
```
S3_BUCKET="apac-support-bucket" S3_PREFIX="$(hostname -s)_s3-test"
file-list -bsType S -b "${S3_BUCKET}" -p "${S3_PREFIX}/content/vol-" -R -fP "@Bucket\.repo-name=raw-s3-hosted,.+deleted=true" -P -c 10 -s ./raw-s3-hosted_deleted.tsv
```

### Remove 'deleted=true' (-RDel) which @BlobStore.blob-name=/test/test_1k.img but only "raw-hosted" (-R -fP <regex>) , and outputs the contents of .properties (-P) to check, but *Dry Run* (-Dry)
```
file-list -RDel -dF "$(date +%Y-%m-%d)" -b ./content -p "vol-" -R -fP "@BlobStore\.blob-name=/test/test_1k.img,.+@Bucket\.repo-name=raw-hosted,.+deleted=true" -P -c 10 -s ./undelete_raw-hosted.tsv
```
### Check orphaned files by querying against PostgresSQL (-db "conn string or nexus-store.properties file path") with max 10 DB connections (-c 10), and using -P as it's faster because of generating better SQL query, and checking only *.properties files with -f (excluding .bytes files)
```
file-list -b ./content -p vol- -c 10 -db "host=localhost port=5432 user=nxrm3pg password=******** dbname=nxrm3pg" -P -f ".properties"
# or
file-list -b ./content -p vol- -c 10 -db /nexus-data/etc/fabric/nexus-store.properties -P -f ".properties"
```
NOTE: the above outputs blobs with properties content, which are not in <format>_asset table, which means it doesn't check the asset_blobs which are soft-deleted by Cleanup unused asset blobs task.

### Check orphaned files from the text file (-bF ./blobIds.txt), which contains Blob IDs, instead of walking blobs directory, against 'default' blob store (-bsName 'default')
```
file-list -b ./content -p vol- -c 10 -db "host=localhost port=5432 user=nxrm3pg password=******** dbname=nxrm3pg" -bF ./blobIds.txt -bsName "default" -s ./orphaned_list.tsv 2>./orphaned_verify.log
# If the file contains unnecessary lines (eg: .bytes), use '-bf -'
cat ./blobIds.txt | grep -v '.bytes' | file-list -b ./content -p vol- -c 10 -db "host=localhost port=5432 user=nxrm3pg password=******** dbname=nxrm3pg" -bsName default -bF - -s ./orphaned.tsv
```
Above /tmp/result.err contains the line `17:58:13.814063 WARN  blobId:81ab5a69-e099-44a1-af1a-7a406bc305e9 does not exist in database.`, or `INFO` if the blobId exists in the DB.

### Check dead files from the database (-src DB -db <connection>), which contains Blob IDs, against 'default' blob store (-bsName 'default')
```
cd ./sonatype-work/nexus3/
file-list -b ./blobs/default/content -p vol- -c 10 -src DB -db ./etc/fabric/nexus-store.properties -repos "raw-hosted" -X -s ./dead-list.tsv 2>./dead-list.log 
file-list -b ./blobs/default/content -p vol- -c 10 -src DB -db "host=localhost port=5432 user=nxrm3pg dbname=nxrm3pg password=********" -bsName default -X -s ./dead-list.tsv 2>./dead-list.log 
```
```
file-list -bsType S -b "apac-support-bucket" -p "filelist_test/content/vol-" -c 10 -src DB -db ./etc/fabric/nexus-store.properties -bsName "s3-test" -s ./dead-list_s3.tsv -X 2>./dead-list_s3.log 
```
In above example, `filelist_test` is the S3 bucket prefix and `-X` is for debug (verbose) output.
### For OrientDB
```
cd ./sonatype-work/nexus3/
echo "select blob_ref from asset where bucket.repository_name = 'xxxxxxx'" | orient-console ./db/component/ | file-list -b ./blobs/default/content -p vol- -c 10 -src DB -bF "-" -bsName default -X -s ./dead-list_fromOrient.tsv 2>./dead-list_fromOrient.log
```
---------------------------------------------------------------------------



## Misc.
NOTE: For more accurate performance testing, may want to clear the Linux file cache (as 'root' user)
```
echo 3 > /proc/sys/vm/drop_caches
```
#### Generate blobIDs with comma separated from the saved result file:
```
sed -n -E 's/.+([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\..+/\1/p' ./docker-proxy_soft_deleted.tsv | tr '\n', ','
```
#### If File type blob store, re-use the saved file to delete the matching files with xargs + rm:
```
cat ./docker-proxy_soft_deleted.tsv | cut -d '.' -f1 | xargs -I{} -t rm -v -f {}.{properties,bytes}
```
Expecting the strings up to the first `.` is the full or relative path of the target files, then deleting both .properties and .bytes files.
