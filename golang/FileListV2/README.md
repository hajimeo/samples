# File List V2

## Purpose / Scope of this tool

- List files from specified location (File, S3, Azure, etc.)
- Remove `deleted=true` lines from the specified files
- Find missing blobs in blob store (similar to Orphaned Blobs Finder)
- Find missing blobs in database (similar to Dead Blobs Finder)
- Copy specific blobs to another Blob store (for slow Export/Import and Change Repository Blob Store, Docker GC
  investigation, etc.)

## Download and Install:

Saving the binary as `filelist2` as an example:

```bash
curl -o ./filelist2 -L "https://github.com/sonatype/nexus-monitoring/raw/refs/heads/main/resources/filelistv2_$(uname)_$(uname -m)"
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
export AWS_ACCESS_KEY_ID="*******" AWS_SECRET_ACCESS_KEY="********" AWS_REGION="ap-southeast-2"
filelist2 -b "s3://${AWS_BLOB_STORE_NAME}/filelist-test/content" -n 5

# If MinIO
export AWS_ACCESS_KEY_ID="*******" AWS_SECRET_ACCESS_KEY="********" AWS_REGION="" AWS_ENDPOINT_URL="http://127.0.0.1:19000"
filelist2 -b "s3://test2/aaaaaa/content" -n 5

# If Azure, use `az://` and also populate necessary environment variables
export AZURE_STORAGE_ACCOUNT_NAME="********" AZURE_STORAGE_ACCOUNT_KEY="*********************"
filelist2 -b "az://${AZURE_STORAGE_CONTAINER_NAME}/content" -n 5

TODO: filelist2 -b "gs://google-test-storage/google-test-prefix/content" -n 5
```

#### List files which matches with specific repo and modified from yesterday

```
BLOB_STORE="./sonatype-work/nexus3/blobs/default/content"
filelist2 -b "$BLOB_STORE" -P -pRx "@Bucket.repo-name=raw-hosted," -mDF "$(date -d "1 day ago" +%Y-%m-%d)" 2>/dev/null
# As .properties file's modified date can be different from the .bytes file's one, use `-BytesChk`
filelist2 -b "$BLOB_STORE" -P -pRx "@Bucket.repo-name=raw-hosted," -mDF "$(date -d "1 day ago" +%Y-%m-%d)" -BytesChk 2>/dev/null
```

#### List files which path matches with the concurrency N `-c N`, and save to a file with
`-s "save-to-file-path"`

```
filelist2 -b "$BLOB_STORE" -c 80 -s "/tmp/filelist_under-path.tsv"
```

NOTE: The recommended concurrency is less than (CPUs / 2) * 10, unless against some slow disk/network.  
Also, if the blob store type is S3, `-c 1 -c2 8` (changing 2nd concurrency higher/lower) may improve the throughput.

#### Same as the above but only files which File name matches with
`-f "file-filter"`, and including the Properties file content `-P` into the saving file

```
filelist2 -b "$BLOB_STORE" -f ".propperties" -P -c 80 -s "/tmp/filelist_under-path_props-only.tsv"
```

#### List .properties which matches with `-pRx "{regex}"`, also including the properties content `-P` in the saving file
`-s`, but only the first N `-n N`

```
filelist2 -b "$BLOB_STORE" -pRx ",deleted=true" -P -n 10 -c 10 -s /tmp/filelist_top10_soft-deleted.tsv
filelist2 -b "$BLOB_STORE" -pRx "@Bucket\.repo-name=raw-hosted,.+deleted=true" -P -c 80 -s /tmp/filelist_raw-hosted_soft-deleted.tsv
```

NOTE: Using `-pRx` automatically does same as `-f ".propperties"`.  
NOTE: To make the regex simpler, in the internal memory, the content of .properties file becomes same as
`cat <blobId>.properties | sort | tr '\n' ','`, so that `@xxxxx` lines come before `deleted=true` lines.

### List files which does NOT match with `-pRxNot "regex"` but matches with `-pRx "regex"`

NOTE: `-pRxNot` is evaluated before `-pRx`

```
filelist2 -b "$BLOB_STORE" -pRxNot "BlobStore\.blob-name=.+/maven-metadata.xml.*" -pRx "@Bucket\.repo-name=maven-proxy," -P -c 80 -s /tmp/filelist_maven-proxy_excl_maven-metadata.tsv
```

### Read the result File `-rF "file-path"`, which each lne contains a blobId, and list the .properties files only
`-f "file-name-filter"` with the content `-P`

```
filelist2 -b "$BLOB_STORE" -f ".properties" -P -s /tmp/filelist_reused_result.tsv -rF ./reuse_some_previous_result.tsv
```

NOTE: The above picks the blobID-like strings automatically, so no need to remove unnecessary strings. If no
`-f ".properties"`, the result lines include ".bytes".

### Use this tool to check the total count and size of all .bytes files

```
filelist2 -b "$BLOB_STORE" -f ".bytes" >/dev/null
... (in the end of the command it outputs the below) ...
13:52:46.972949 INFO  Printed 136895 of 273790 files, size: 2423593014 bytes (elapsed:26s)
```

NOTE: the above means it checked 273790 and 136895 matched with ".bytes" and the total size of the matching files was
2423593014 bytes

#### Check the bytes size from the .properties file's `size={n}`

```
filelist2 -b "$BLOB_STORE" -pRx "@Bucket\.repo-name=raw-hosted" -P -s /tmp/filelist_raw-hosted_props.tsv
rg -o -r '$1' ',size=(\d+)' /tmp/filelist_raw-hosted_props.tsv | awk '{ c+=1;s+=$1 }; END { print "blobCount:"c", totalSize:"s" bytes" }'
```

### Remove `deleted=true` lines from the specified files in a text file or while listing

Like dry-run (`-H` to not output headers, `-BytesChk` is to detect deletion markers as `originalLocation` is unreliable)
```
filelist2 -b "$BLOB_STORE" -pRx "@Bucket\.repo-name=raw-hosted,.+deleted=true" -P -H -BytesChk -c 80 -s /tmp/filelist_raw-hosted_soft-deleted.tsv
```
NOTE: As the `-p` default is `/(vol-\d\d|20\d\d)/`, excluding tmp/direcct-path etc.

After reviewing the tsv file (e.g. remove `BYTES_MISSING` lines)

```
filelist2 -b "$BLOB_STORE" -rF /tmp/filelist_raw-hosted_soft-deleted.tsv -RDel -P -c 80 -s /tmp/filelist_raw-hosted_undeleted.tsv
```
NOTE: -s

### Find blobs which exist in Blob store but not in database with `-src BS` (like Orphaned Blobs Finder)

NOTE: Cleanup unused asset blob tasks should be run before this script because asset_blob is INNER JOIN-ed with asset table. Also, `-c` shouldn't be too high with `-db`.

```
# Accessing DB by using the connection string and check all formats for orphaned blobs (-src BS)
# Also `-BytesChk` to exclude .properties files which do not have the .bytes file (deletion marker)
filelist2 -b "$BLOB_STORE" -c 10 -src BS -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -P -pRxNot "deleted=true" -BytesChk -s /tmp/filelist_orphaned_blobs.tsv
# NOTE: `-db` also accepts "host=localhost user=nexus dbname=nexus" (with export PGPASSWORD="*******")

# Nexus 3.86 may be going to have the originalLocation line for deletion markers, so may not need to use -BytesChk (TODO: if upgraded, could be confusing)
filelist2 -b "$BLOB_STORE" -p '/(20\d\d)/' -c 10 -src BS -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -P -pRxNot "(deleted=true|originalLocation)" -s /tmp/filelist_orphaned-blobs_without-byteschk.tsv
```

Can use a text file which contains Blob IDs, so that no Blobstore access is needed:

```
filelist2 -src BS -rF ./some_filelist_result.tsv -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -bsName default -s /tmp/filelist_orphaned-blobs_no-BS-access.tsv
```
TODO: If the tsv file contains only .properties file, to delete both .properties and .bytes files of the orphaned blobs:
```
cd /To/Blobstore/blobs   # As -C doesn't work with the wildcard
cut -d '.' -f1 ./some_filelist_result.tsv | while read -r _l; do tar -rvf /tmp/test.tar --remove-files ${_l}.*; done
```
NOTE: `-z` tar option may fail if the system does not have the gzip/gunzip command.

### Find blobs which exist in Database but not in Blob store with `-src DB` (like Dead Blobs Finder)

NOTE: if `query` result is large, may want to split the query into smaller parts (e.g. order by asset_id limit 100000
offset N)

```
filelist2 -b "$BLOB_STORE" -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -c 10 -query "select blob_ref as blob_id from raw_asset_blob ab join raw_asset a using (asset_blob_id) where repository_id IN (select cr.repository_id from raw_content_repository cr join repository r on r.id = cr.config_repository_id where r.name in ('raw-hosted'))" -src DB -s /tmp/filelist_potentially_dead-blobs.tsv
```

Can use a text file which contains Blob IDs, so that no DB access is needed:

```
filelist2 -src BS -rF ./db_exported_blobids.txt -b "$BLOB_STORE" -s /tmp/filelist_potentially_dead-blobs_no-DB-access.tsv
```

### With the undeleter script, like Point-In-Time-Recovery for blobs which exist in Blob store but not in DB

NOTE: if `query` result is large, may want to split the query into smaller parts (e.g. order by record_id (or
deleted_date) limit 100000 offset N)

```
filelist2 -b "$BLOB_STORE" -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -query "SELECT blob_id||'@'||TO_CHAR(date_path_ref AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI') as blob_id FROM soft_deleted_blobs WHERE source_blob_store_name = 'default' AND deleted_date > NOW() - INTERVAL '3 days' ORDER BY deleted_date LIMIT 1000" -s ./restoring_blobs.tsv
# After reviewing the tsv file (removing unnecessary lines), then:
bash ./nrm3-undelete-3.83.sh -I -s "default" -b ./restoring_blobs.tsv
```
NOTE: The above result can be directly path to the undeleter script.

#### Just saving the query result with `-rf`:
In case want to quickly check the soft_deleted_blobs table (just in case, using LIMIT):
```
filelist2 -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -query "SELECT blob_id, * FROM soft_deleted_blobs WHERE source_blob_store_name = 'default' and deleted_date > NOW() - INTERVAL '300 days' ORDER BY deleted_date limit 1000" -rF /tmp/filelist_query-result.out
```
Check / restore specific repository and specific path:
```
filelist2 -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -query "SELECT ab.blob_ref as blob_id FROM raw_asset_blob ab JOIN raw_asset a USING (asset_blob_id) WHERE repository_id IN (1) and path like '/test%' LIMIT 1000" -rF /tmp/filelist_query-result_2.out
```

### *Experimental* Copy specific blobs to another Blob store with `-bTo` (like Export/Import)

Excluding the soft-deleted blobs and including only specific repo. For bTo uses a different credential, appending _2 may work. (e.g. AWS S3 to MinIO)
```
# NOTE: MinIO example. HTTPS is required.
export AWS_ACCESS_KEY_ID_2="admin" AWS_SECRET_ACCESS_KEY_2="admin123" AWS_REGION_2="" AWS_ENDPOINT_URL_2="https://local.standalone.localdomain:19000" AWS_CA_BUNDLE_2="$HOME/minio_data/certs/public.crt"
filelist2 -b "s3://apac-support-bucket/filelist-test/" -bTo "s3://apac-support-bucket/filelist-test_copied/" -PathStyle -P -pRx "@Bucket.repo-name=raw-s3-hosted," -pRxNot "deleted=true" -H -s ./copied_blobs.tsv
```
NOTE: Using `AWS_CA_BUNDLE` may break HTTPS requests to the real AWS S3. May also need to use `-PathStyle` if not wildcard certificate.
```
# NOTE: Azurite example. Need to create a Container. Can not use '_' in the container name.
export AZURE_STORAGE_CONNECTION_STRING_2="DefaultEndpointsProtocol=http;AccountName=admin;AccountKey=YWRtaW4xMjM=;BlobEndpoint=http://localhost:10000/admin;"
az storage container create --name "apac-support-bucket-filelist-test-copied" --connection-string "${AZURE_STORAGE_CONNECTION_STRING_2}"
filelist2 -b "s3://apac-support-bucket/filelist-test/" -bTo "az://apac-support-bucket-filelist-test-copied/" -P -pRx "@Bucket.repo-name=raw-s3-hosted," -pRxNot "deleted=true" -H -s ./copied_blobs.tsv
# To validate
AZURE_STORAGE_CONNECTION_STRING="${AZURE_STORAGE_CONNECTION_STRING_2}" filelist2 -b "az://apac-support-bucket-filelist-test-copied/" -rF ./copied_blobs.tsv
```
After reviewing ./copied_blobs.tsv, execute the Undeleter against another Nexus instance
```
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

Expecting the strings up to the first `.` is the full or relative path of the target files, then deleting both
.properties and .bytes files.

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