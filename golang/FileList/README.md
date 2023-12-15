# File List
Demo script to list all files from a File type blob store with tab delimiter format (not csv).

## DOWNLOAD and INSTALL:
```bash
curl -o ./file-list -L https://github.com/hajimeo/samples/raw/master/misc/filelist_$(uname)_$(uname -m)
chmod a+x ./file-list
```
```bash
curl -o /usr/local/bin/file-list -L https://github.com/hajimeo/samples/raw/master/misc/filelist_$(uname)_$(uname -m)
chmod a+x /usr/local/bin/file-list
```

## ARGUMENTS:
```
$ file-list --help

List .properties and .bytes files as *Tab* Separated Values (Path LastModified Size).

HOW TO and USAGE EXAMPLES:
    https://github.com/hajimeo/samples/blob/master/golang/FileList/README.md

Usage of file-list:
  -BSize
        If true, includes .bytes size (When -f is '.properties')
  -Dry
        If true, RDel does not do anything
  -H    If true, no header line
  -L    If true, just list directories and exit
  -O    AWS S3: If true, get the owner display name
  -P    If true, read and output the .properties files
  -R    If true, .properties content is *sorted* and -fP|-fPX string is treated as regex
  -RDel
        Remove 'deleted=true' from .properties. Requires -dF
  -S3
        AWS S3: If true, access S3 bucket with AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_REGION
  -T    AWS S3: If true, get tags of each object
  -X    If true, verbose logging
  -XX
        If true, more verbose logging
  -b string
        Base directory (default: '.') or S3 Bucket name (default ".")
  -bF string
        file path whic contains the list of blob IDs
  -bsName string
        eg. 'default'. If provided, the SQL query will be faster. 3.47 and higher only
  -c int
        Concurrent number for reading directories (default 1)
  -c2 int
        AWS S3: Concurrent number for retrieving AWS Tags (default 8)
  -dF string
        Deleted date YYYY-MM-DD (from). Used to search deletedDateTime
  -dT string
        Deleted date YYYY-MM-DD (to). To exclude newly deleted assets
  -db string
        DB connection string or path to DB connection properties file
  -dd int
        NOT IN USE: Directory Depth to find sub directories (eg: 'vol-NN', 'chap-NN') (default 2)
  -f string
        Filter for the file path (eg: '.properties' to include only this extension)
  -fP string
        Filter for the content of the .properties files (eg: 'deleted=true')
  -fPX string
        Excluding Filter for .properties (eg: 'BlobStore.blob-name=.+/maven-metadata.xml.*')
  -m int
        AWS S3: Integer value for Max Keys (<= 1000) (default 1000)
  -mF string
        File modification date YYYY-MM-DD from
  -mT string
        File modification date YYYY-MM-DD to
  -n int
        Return first N lines (0 = no limit). (TODO: may return more than N)
  -p string
        Prefix of sub directories (eg: 'vol-') This is not recursive
  -repoFmt string
        eg. 'maven2'. If provided, the SQL query will be faster
  -s string
        Save the output (TSV text) into the specified path
  -src string
        Using database or blobstore as source [BS|DB] (default "BS")
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
$ file-list -b ./content -p 'vol-' -f ".bytes" >/dev/null
2021/12/31 14:24:15 INFO: Generating list with ./sonatype-work/nexus3/blobs/default ...
... (snip) ...
13:52:46.972949 INFO  Printed 136895 of 136895 (size:2423593014) in ./content and sub-dir starts with vol- (elapsed:26s)
```

### List all files which properties contain 'repo-name=docker-proxy' and 'deleted=true'
```
file-list -b ./content -p "vol-" -c 10 -f ".properties" -P -fP "@Bucket\.repo-name=docker-proxy.+deleted=true" -R -s ./docker-proxy_soft_deleted.tsv
```
NOTE: the attributes in a .properties file are sorted in memory, so that attributes start with "@" comes before "deleted=true" line.

### List all files which does NOT contain 'maven-metadata.xml'
```
file-list -b ./content -p "vol-" -c 10 -f ".properties" -P -fPX "BlobStore\.blob-name=.+/maven-metadata.xml.*" -R -s ./all_excluding_maven-metadata.tsv
```

### List files which were modified since 1 day ago (-mF "YYYY-MM-DD")
```
file-list -b ./content -p "vol-" -c 10 -mF "$(date -d "1 day ago" +%Y-%m-%d)" -s ./$(date '+%Y-%m-%d').tsv
```

### List files which were soft-deleted since one day ago (-dF "YYYY-MM-DD")
```
file-list -b ./content -p "vol-" -c 10 -dF "$(date -d "1 day ago" +%Y-%m-%d)" -s ./$(date '+%Y-%m-%d').tsv
```
To use the output for the Reconcile Task's Since log, remove `-s` and append ` | rg '/([0-9a-f\-]+)\..+(\d\d\d\d.\d\d.\d\d.\d\d:\d\d:\d\d)' -o -r '$2,$1'`

### **DANGEROUS** Remove 'deleted=true' (-RDel and -dF "YYYY-MM-DD")
```
file-list -b ./content -p "vol-" -c 10 -dF "$(date -d "1 day ago" +%Y-%m-%d)" -RDel -s ./$(date '+%Y-%m-%d').tsv
```

### Check files, which were soft-deleted since 1 day ago (-dF), including .properties file contents (-P -f ".properties")
```
$ file-list -b ./content -p vol- -c 10 -dF "$(date -d "1 day ago" +%Y-%m-%d)" -P -f ".properties" -s ./$(date '+%Y-%m-%d').tsv 2>./file-list_$(date +"%Y%m%d%H%M%S").log
```
NOTE: If using -RDel to remove "deleted=true", recommend to save the STDERR into a file (like above) in case of reverting.

### Remove 'deleted=true' (-RDel) which soft-deleted within 1 day (-dF <YYYY-MM-DD>) against S3 (-S3 -b <bucket> -p <prefix>/content/vol-) but only "raw-s3-hosted" (-R -fP <regex>) , and outputs the contents of .properties (-P) to check, but *Dry Run* (-Dry)
```
file-list -RDel -dF "$(date -d "1 day ago" +%Y-%m-%d)" -S3 -b "apac-support-bucket" -p "node-nxrm-ha1/content/vol-" -R -fP "@Bucket\.repo-name=raw-s3-hosted,.+deleted=true" -P -c 10 -s ./undelete_raw-s3-hosted.out -Dry
```

### Check orphaned files by querying against PostgreSQL (-db "\<conn string or nexus-store.properties file path) with max 10 DB connections (-c 10), and using -P as it's faster because of generating better SQL query
```
file-list -b ./content -p vol- -c 10 -db "host=localhost port=5432 user=nxrm3pg password=******** dbname=nxrm3pg" -P
# or
file-list -b ./content -p vol- -c 10 -db /nexus-data/etc/fabric/nexus-store.properties -P
```
NOTE: the above outputs blobs with properties content, which are not in <format>_asset table, which means it doesn't check the asset_blobs which are soft-deleted by Cleanup unused asset blobs task.

### Check orphaned files from the text file (-bF ./blobIds.txt), which contains Blob IDs, against 'default' blob store (-bsName 'default')
```
file-list -b ./content -p vol- -c 10 -db "host=localhost port=5432 user=nxrm3pg password=******** dbname=nxrm3pg" -bF ./blobIds.txt -bsName "default" 2>/tmp/orphaned_verify.log 1>/tmp/orphaned_list.out
# If the file contains unnecessary lines (eg: .bytes), use '-bf -'
cat ./blobIds.txt | grep -v '.bytes' | file-list -b ./content -p vol- -c 10 -db "host=localhost port=5432 user=nxrm3pg password=******** dbname=nxrm3pg" -bsName default -bF - -s ./orphaned.out
```
Above /tmp/result.err contains the line `17:58:13.814063 WARN  blobId:81ab5a69-e099-44a1-af1a-7a406bc305e9 does not exist in database.`, or `INFO` if the blobId exists in the DB.

###  List specific .properties/.bytes files then delete with xargs + rm:
```
$ file-list -b ./sonatype-work/nexus3/blobs/default/content -p "vol-" -c 4 -fP "@BlobStore\.blob-name=/@sonatype/policy-demo,.+@Bucket\.repo-name=npm-hosted" -R -H | cut -d '.' -f1 | xargs -I{} -t rm -v -f {}.{properties,bytes}
```
