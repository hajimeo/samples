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

### Find blobs which exist in Blob store but not in database (Orphaned Blobs)
NOTE: Cleanup unused asset blob tasks should be run before this script. Also, `-c` shouldn't be too high with `-db`.  
```
# Accessing DB by using the connection string and check all formats for orphaned blobs
export PGPASSWORD="*******"
filelist2 -b "$BLOB_STORE" -p 'vol-' -c 10 -src BS -db "host=localhost user=nexus dbname=nexus" -pRxNot "deleted=true" -s ./orphaned_blobs.tsv
```

Using Blob IDs file (TODO: confusing):
```
# Source is DB and no `-db`, so using -rF as if DB
filelist2 -src DB -rF ./sql_output_from_DB.txt -b "$BLOB_STORE" -p 'vol-' -c 80 -s ./missing_blobs_no-DB-access.tsv
# Source is BS and no `-b`, so using -rf as if BS (previous filelist) result
filelist2 -src BS -rF ./docker-proxy_blob_ids.tsv -db "host=localhost user=nexus dbname=nexus" -bsName default -s ./orphaned_blobs_no-BS-access.tsv
```


## Misc.
NOTE: For more accurate performance testing, may want to clear the Linux file cache (as 'root' user)
```
echo 3 > /proc/sys/vm/drop_caches
```
### Generate blobIDs with comma separated from the saved result file:
```
sed -n -E 's/.+([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\..+/\1/p' ./docker-proxy_soft_deleted.tsv | paste -sd, -
# Example for the Reconcile Task, get datetime and blobId
sed -n -E 's/.+([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\..+([0-9]{4}.[0-9]{2}.[0-9]{2}.[0-9]{2}:[0-9]{2}:[0-9]{2}).+/\2,\1/p' ./$(date +"%Y%m%d%H%M%S").tsv > "./reconciliation/$(date '+%Y-%m-%d')"
```
### Hard-delete files
If File type blob store, re-use the saved file to delete the matching files with xargs + rm:
```
cat ./docker-proxy_soft_deleted.tsv | cut -d '.' -f1 | xargs -I{} -t rm -v -f {}.{properties,bytes}
```
Expecting the strings up to the first `.` is the full or relative path of the target files, then deleting both .properties and .bytes files.

### For OrientDB
```
cd ./sonatype-work/nexus3/
echo "select blob_ref from asset where bucket.repository_name = 'xxxxxxx'" | orient-console ./db/component/
```