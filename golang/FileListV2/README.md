# File List V2
## Purpose / Scope of this tool
- List files from specified location (File, S3, Azure, etc.)
- Remove `deleted=true` lines from the specified files
- Find missing blobs in blob store (similar to Orphaned Blobs Finder)
- TODO: Find missing blobs in database (similar to Dead Blobs Finder)

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
NOTE: The argument name starts with a Capital letter is boolean type (no value). For example `-X` and `-XX` for Debug.

## Usage Examples

### List files under the Blob store content `-b "blob-store-uri"`
```
# The default is `file://` so with or without works
filelist2 -b "./sonatype-work/nexus3/blobs/default/content"
filelist2 -b "file://sonatype-work/nexus3/blobs/default/content"

# If S3, use `s3://` and populate necessary environment variables
export AWS_ACCESS_KEY_ID="*******" AWS_SECRET_ACCESS_KEY="*********************" AWS_REGION="ap-southeast-2"
filelist2 -b "s3://${AWS_BLOB_STORE_NAME}/filelist-test/content" -n 5

# If Azure, use `az://` and also populate necessary environment variables
export AZURE_STORAGE_ACCOUNT_NAME="********" AZURE_STORAGE_ACCOUNT_KEY="*********************"
filelist2 -b "az://${AZURE_STORAGE_CONTAINER_NAME}/content" -n 5

TODO: filelist2 -b "gc://google-test-storage/google-test-prefix/content" -n 5
```
#### List files which matches with specific repo and modified from today
```
filelist2 -b "$BLOB_STORE -P -pRx "@Bucket.repo-name=maven-group," -mDF $(date +%Y-%m-%d) 2>/dev/null
```
#### List files which path matches with `-p "path-filter"` with the concurrency N `-c N`, and save to a file with `-s "save-to-file-path"`
```
filelist2 -b "$BLOB_STORE" -p "/(vol-\d\d|20\d\d)/" -c 80 -s "/tmp/file-list_$(date +"%Y%m%d%H%M%S").tsv"
```
NOTE: The recommended concurrency is less than (CPUs / 2) * 10, unless against slow disk/network.  
Also, the concurrency is based on the directories under `-b` (max depth 4), so even the "vol-NN" is less than 50, the concurrency higher than 50 would work.  
Also, if S3, `-c 2 -c2 8` might be faster.

#### Same as the above but only files which File name matches with `-f "file-filter"`, and including the Properties file content `-P` into the saving file
```
filelist2 -b "$BLOB_STORE" -p "/(vol-\d\d|20\d\d)/" -f ".propperties" -P -c 80 -s "/tmp/file-list_$(date +"%Y%m%d%H%M%S").tsv"
```
#### Above example with the Modified Date From `-mDF "YYYY-MM-DD"`
```
filelist2 -b "$BLOB_STORE" -p "/(vol-\d\d|20\d\d)/" -f ".propperties" -P -mDF "$(date -d "1 day ago" +%Y-%m-%d)" -c 80 -s "/tmp/modified_since_yesterday.tsv"
```
#### List .properties which matches `-pRx "regex"`, also including the properties content `-P` in the saving file, but only the first N `-n N`
NOTE: Using `-pRx` automatically does same as `-f ".propperties"`.  
NOTE: To make the regex simpler, in the internal memory, the content of .properties file becomes same as `cat <blobId>.properties | sort | tr '\n' ','`, so that `@xxxxx` lines come before `deletedYyyyy` lines.
```
filelist2 -b "$BLOB_STORE" -p '/(vol-\d\d|20\d\d)/' -pRx ",deleted=true" -P -n 10 -c 10 -s /tmp/all_soft_deleted.tsv
filelist2 -b "$BLOB_STORE" -p "/(vol-\d\d|20\d\d)/" -pRx "@Bucket\.repo-name=docker-proxy,.+deleted=true" -P -c 80 -s ./docker-proxy_soft_deleted.tsv
```
#### List files which does NOT match with `-pRxNot "regex"` but matches with `-pRx "regex"`
NOTE: `-pRxNot` is evaluated before `-pRx`
```
filelist2 -b "$BLOB_STORE" -p "/(vol-\d\d|20\d\d)/" -pRxNot "BlobStore\.blob-name=.+/maven-metadata.xml.*" -pRx "@Bucket\.repo-name=maven-central,.+deleted=true" -P -c 80 -s ./maven-central_soft_deleteed_excluding_maven-metadata.tsv
```

#### Read the result File `-rF "file-path"`, which each lne contains a blobId, and list the .properties files only `-f "file-name-filter"` with the content `-P`
```
filelist2 -b "$BLOB_STORE" -p "/(vol-\d\d|20\d\d)/" -rF ./previous_result_without_properties_content.tsv -f ".properties" -P
```
NOTE: The above picks the blobID-like strings automatically, so no need to remove unnecessary strings. If no `-f ".properties"`, the result lines include ".bytes".

#### Use this tool to check the total count and size of all .bytes files
```
file-list -b "$BLOB_STORE" -p '/(vol-\d\d|20\d\d)/' -f ".bytes" >/dev/null
... (in the end of the command it outputs the below) ...
13:52:46.972949 INFO  Printed 136895 of 273790 files, size: 2423593014 bytes (elapsed:26s)
```
NOTE: the above means it checked 273790 and 136895 matched with ".bytes" and the total size of the matching files was 2423593014 bytes
```
file-list -b "$BLOB_STORE" -p '/(vol-\d\d|20\d\d)/' -pRx "@Bucket\.repo-name=npm-proxy" -P -s ./npm-proxy_all.tsv
rg -o -r '$1' ',size=(\d+)' ./npm-proxy_all.tsv | awk '{ c+=1;s+=$1 }; END { print "blobCount:"c", totalSize:"s" bytes" }'
```

### Remove `deleted=true` lines from the specified files in a text file or while listing
```
# Like dry-run
filelist2 -b "$BLOB_STORE" -p "/(vol-\d\d|20\d\d)/" -pRx "@Bucket\.repo-name=docker-proxy,.+deleted=true" -P -c 80 -s ./docker-proxy_soft_deleted.tsv
filelist2 -b "$BLOB_STORE" -rF ./docker-proxy_soft_deleted.tsv -RDel -P -c 80 -s docker-proxy_soft_deleted_undeleted.tsv 
```

### Find blobs which exist in Blob store but not in database with `-src BS` (like Orphaned Blobs Finder)
NOTE: Cleanup unused asset blob tasks should be run before this script. Also, `-c` shouldn't be too high with `-db`.  
```
# Accessing DB by using the connection string and check all formats for orphaned blobs (-src BS)
# Also `-BytesChk` to exclude .properties files which do not have the .bytes file (deletion marker)
export PGPASSWORD="*******"
filelist2 -b "$BLOB_STORE" -p '/(vol-\d\d|20\d\d)/' -c 10 -src BS -db "host=localhost user=nexus dbname=nexus" -P -pRxNot "deleted=true" -BytesChk -s ./orphaned_blobs.tsv
# NOTE: -db accepts the properties file: -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties

# TODO: Nexus 3.86 may have the originalLocation line for the deletion marker, so may not need to use -BytesChk (if upgraded, confusing)
filelist2 -b "$BLOB_STORE" -p '/(20\d\d)/' -c 10 -src BS -db "host=localhost user=nexus dbname=nexus" -P -pRxNot "(deleted=true|originalLocation)" -s ./orphaned_blobs.tsv
```

Can use a text file which contains Blob IDs, so that no Blobstore access is needed:
```
filelist2 -src BS -rF ./some_filelist_result.tsv -db "host=localhost user=nexus dbname=nexus" -bsName default -s ./orphaned_blobs_no-BS-access.tsv
```

### Find blobs which exist in Database but not in Blob store with `-src DB` (like Dead Blobs Finder)
NOTE: if `query` result is large, may want to split the query into smaller parts (e.g. order by asset_id limit 100000 offset N)
```
export PGPASSWORD="*******"
filelist2 -b "$BLOB_STORE" -db "host=localhost user=nexus dbname=nexus" -query "select blob_ref as blob_id from raw_asset_blob where repository_id = {n}" -s ./potentially_dead_blobs.tsv
# NOTE: -db accepts the properties file: -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties
```

Can use a text file which contains Blob IDs, so that no DB access is needed:
```
filelist2 -src BS -rF ./db_exported_blob_ids.txt -b "$BLOB_STORE" -p '/(vol-\d\d|20\d\d)/' -s ./dead_blobs_blobs_no-DB-access.tsv
```




### TEST: With undeleter, do similar to Point-In-Time-Recovery for blobs which exist in Blob store but not in DB
NOTE: if `query` result is large, may want to split the query into smaller parts (e.g. order by record_id (or deleted_date) limit 100000 offset N)
```
filelist2 -b "$BLOB_STORE" -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -query "SELECT blob_id||'@'||TO_CHAR(date_path_ref AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI') as blob_id FROM soft_deleted_blobs WHERE source_blob_store_name = 'default' AND deleted_date > NOW() - INTERVAL '3 days' ORDER BY deleted_date LIMIT 1000" -s ./restoring_blobs.tsv
# After reviewing ./restoring_blobs.tsv, removing unnecessary lines, then:
bash ./nrm3-undelete-3.83.sh -I -s "default" -b ./restoring_blobs.tsv
```
To juat save the query result without accessing the Blob store with reusing `-rf`:
```
filelist2 -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -query "SELECT 'test' as blob_id, * FROM soft_deleted_blobs WHERE source_blob_store_name = 'default' and deleted_date > NOW() - INTERVAL '300 days' ORDER BY deleted_date limit 2" -rF ./query_result.out
```

### TODO: Copy specific blobs to another Blob store with `-bTo` (like Export/Import)
Excluding the soft-deleted blobs and including only specific repo.
```
filelist2 -b "$BLOB_STORE" -bTo "$BLOB_STORE2" -P -pRx "@Bucket.repo-name=raw-hosted," -pRxNot "deleted=true" -s ./copied_blobs.tsv
# After reviewing ./copied_blobs.tsv, execute the undelter against another Nexus instance
bash ./nrm3-undelete-3.83.sh -I -s "default" -b ./copied_blobs.tsv
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

### Example of generating blob_ref|blobId from OrientDB
```
cd ./sonatype-work/nexus3/
echo "select blob_ref from asset where bucket.repository_name = 'xxxxxxx'" | orient-console ./db/component/
```

### Update|reset the deletion marker
```
filelist2 -b s3://apac-support-bucket/filelist-test/content/ -p 2025 -pRx "deleted=true" -wStr "deleted=true"
# To confirm
filelist2 -b s3://apac-support-bucket/filelist-test -pRx "deleted=true" -T
```

### Misc. note
```
filelist2 -b "s3://${AWS_BLOB_STORE_NAME}/filelist-test/content" -mDF 2025-08-06 -P -T -s all_props_since-6th.tsv
```