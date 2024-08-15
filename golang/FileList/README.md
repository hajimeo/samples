# File List
Demo script to list all files from a File type blob store with tab delimiter format (not csv).

## DOWNLOAD and INSTALL:
```bash
curl -o ./file-list -L https://github.com/hajimeo/samples/raw/master/misc/filelist_$(uname)_$(uname -m)
chmod a+x ./file-list
```

## ARGUMENTS:
Display help:
```
$ file-list --help
```

## Usage Examples
Optional: For accurate performance testing, may need to clear Linux file cache (as 'root'):
```
echo 3 > /proc/sys/vm/drop_caches
```

### List all files under the ./sonatype-work/nexus3/blobs/default
```
file-list -b ./sonatype-work/nexus3/blobs/default/content
... (snip) ...
"sonatype-work/nexus3/blobs/default/content/vol-43/chap-29/3488648f-d5f8-45f8-8314-10681fcaf0ce.properties","2021-09-17 08:35:03.907951265 +1000 AEST",352
"sonatype-work/nexus3/blobs/default/metadata.properties","2021-09-17 08:34:00.625028548 +1000 AEST",73

2021/12/31 14:23:09 INFO: Printed 185 items (size: 75910509) in ./sonatype-work/nexus3/blobs/default with prefix:
```
```
file-list -b ./content -p 'vol-' -c 4 -s /tmp/file-list_$(date +"%Y%m%d%H%M%S").out
```

### Listing blob store items with .properties file contents (-P) with 10 concurrency (-c 10):
```
file-list -b ./content -p 'vol-' -c 10 -P -s /tmp/file-list_$(date +"%Y%m%d%H%M%S").out
```
#### Excluding .bytes files, so that .properties file only:
NOTE: .bytes modified date is usually same as created date.
```
file-list -b ./content -p 'vol-' -c 10 -P -f ".properties" -s /tmp/file-list_$(date +"%Y%m%d%H%M%S").out
```

### Finding first 1 'deleted=true' (-fP "\<expression\>")
```
file-list -b ./content -p 'vol-' -c 10 -fP "deleted=true" -n 1 -s /tmp/file-list_$(date +"%Y%m%d%H%M%S").out
```

### Check the total count and size of all .bytes files
This would be useful to compare with the counters in the Blobstore page.
```
file-list -b ./content -p 'vol-' -f ".bytes" >/dev/null
2021/12/31 14:24:15 INFO: Generating list with ./sonatype-work/nexus3/blobs/default ...
... (snip) ...
13:52:46.972949 INFO  Printed 136895 of 136895 (size:2423593014) in ./content and sub-dir starts with vol- (elapsed:26s)
```

### List all files which properties contain 'repo-name=docker-proxy' and 'deleted=true' 
```
file-list -b ./content -p "vol-" -c 10 -f ".properties" -P -R -fP "@Bucket.repo-name=docker-proxy,.+deleted=true" -s ./docker-proxy_soft_deleted.tsv
```
NOTE: the attributes in a .properties file are sorted in memory and concatenated with ",", so that the repo-name ends with ",". Also attributes start with "@" comes before "deleted=true" line.

Then generate blobIDs with comma separated:
```
sed -n -E 's/.+([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\..+/\1/p' ./docker-proxy_soft_deleted.tsv | tr '\n', ','
```
### List all files which does NOT contain 'maven-metadata.xml'
```
file-list -b ./content -p "vol-" -c 10 -f ".properties" -P -R -fPX "BlobStore\.blob-name=.+/maven-metadata.xml.*" -s ./all_excluding_maven-metadata.tsv
```

### List files which were modified since 1 day ago (-mF "YYYY-MM-DD")
```
file-list -b ./content -p "vol-" -c 10 -mF "$(date -d "1 day ago" +%Y-%m-%d)" -s ./$(date +"%Y%m%d%H%M%S").tsv
```

### Check files, which were soft-deleted since 1 day ago (-dF), including .properties file contents (-P -f ".properties")
```
file-list -b ./content -p vol- -c 10 -dF "$(date -d "1 day ago" +%Y-%m-%d)" -P -f ".properties" -s ./$(date +"%Y%m%d%H%M%S").tsv
```

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
S3_BUCKET="apac-support-bucket" S3_PREFIX="$(hostname -s)_s3-test"
file-list -RDel -dF "$(date -d "1 day ago" +%Y-%m-%d)" -bsType S -b "${S3_BUCKET}" -p "${S3_PREFIX}/content/vol-" -R -fP "@Bucket\.repo-name=raw-s3-hosted,.+deleted=true" -P -c 10 -s ./undelete_raw-s3-hosted.out -Dry
```
Just get the list
```
S3_BUCKET="apac-support-bucket" S3_PREFIX="$(hostname -s)_s3-test"
file-list -bsType S -b "${S3_BUCKET}" -p "${S3_PREFIX}/content/vol-" -R -fP "@Bucket\.repo-name=raw-s3-hosted,.+deleted=true" -P -c 10 -s ./raw-s3-hosted_deleted.out
```

### Remove 'deleted=true' (-RDel) which @BlobStore.blob-name=/test/test_1k.img but only "raw-hosted" (-R -fP <regex>) , and outputs the contents of .properties (-P) to check, but *Dry Run* (-Dry)
```
file-list -RDel -dF "$(date +%Y-%m-%d)" -b ./content -p "vol-" -R -fP "@BlobStore\.blob-name=/test/test_1k.img,.+@Bucket\.repo-name=raw-hosted,.+deleted=true" -P -c 10 -s ./undelete_raw-hosted.out
```
### Check orphaned files by querying against PostgreSQL (-db "\<conn string or nexus-store.properties file path) with max 10 DB connections (-c 10), and using -P as it's faster because of generating better SQL query, and checking only *.properties files with -f (excluding .bytes files)
```
file-list -b ./content -p vol- -c 10 -db "host=localhost port=5432 user=nxrm3pg password=******** dbname=nxrm3pg" -P -f ".properties"
# or
file-list -b ./content -p vol- -c 10 -db /nexus-data/etc/fabric/nexus-store.properties -P -f ".properties"
```
NOTE: the above outputs blobs with properties content, which are not in <format>_asset table, which means it doesn't check the asset_blobs which are soft-deleted by Cleanup unused asset blobs task.

### Check orphaned files from the text file (-bF ./blobIds.txt), which contains Blob IDs, instead of walking blobs directory, against 'default' blob store (-bsName 'default')
```
file-list -b ./content -p vol- -c 10 -db "host=localhost port=5432 user=nxrm3pg password=******** dbname=nxrm3pg" -bF ./blobIds.txt -bsName "default" -s ./orphaned_list.out 2>./orphaned_verify.log
# If the file contains unnecessary lines (eg: .bytes), use '-bf -'
cat ./blobIds.txt | grep -v '.bytes' | file-list -b ./content -p vol- -c 10 -db "host=localhost port=5432 user=nxrm3pg password=******** dbname=nxrm3pg" -bsName default -bF - -s ./orphaned.out
```
Above /tmp/result.err contains the line `17:58:13.814063 WARN  blobId:81ab5a69-e099-44a1-af1a-7a406bc305e9 does not exist in database.`, or `INFO` if the blobId exists in the DB.

### Check dead files from the database (-src DB -db <connection>), which contains Blob IDs, against 'default' blob store (-bsName 'default')
```
cd ./sonatype-work/nexus3/
file-list -b ./blobs/default/content -p vol- -c 10 -src DB -db ./etc/fabric/nexus-store.properties -repos "raw-hosted" -X -s ./dead-list.out 2>./dead-list.log 
file-list -b ./blobs/default/content -p vol- -c 10 -src DB -db "host=localhost port=5432 user=nxrm3pg dbname=nxrm3pg password=********" -bsName default -X -s ./dead-list.out 2>./dead-list.log 
```
```
file-list -bsType S -b "apac-support-bucket" -p "filelist_test/content/vol-" -c 10 -src DB -db ./etc/fabric/nexus-store.properties -bsName "s3-test" -s ./dead-list_s3.out -X 2>./dead-list_s3.log 
```
In above example, `filelist_test` is the S3 bucket prefix and `-X` is for debug (verbose) output.
### For OrientDB
```
cd ./sonatype-work/nexus3/
echo "select blob_ref from asset" | orient-console ./db/component/ | file-list -b ./blobs/default/content -p vol- -c 10 -src DB -bF "-" -bsName default -X -s ./dead-list_fromOrient.out 2>./dead-list_fromOrient.log
```
###  List specific .properties/.bytes files then delete with xargs + rm:
```
file-list -b ./sonatype-work/nexus3/blobs/default/content -p "vol-" -c 4 -R -fP "@BlobStore\.blob-name=/@sonatype/policy-demo,.+@Bucket\.repo-name=npm-hosted," -H | cut -d '.' -f1 | xargs -I{} -t rm -v -f {}.{properties,bytes}
```
