# File List
Demo script to list all objects from a File type blob store with tab delimiter format.  
Basically rewriting below bash function and command:
```bash
function f_blobs_csv() {
    local __doc__="Generate CSV for Path,LastModified,Size + properties"
    local _dir="$1"         # "blobs/default/content/vol-*"
    local _with_props="$2"  # Y to check properties file, but extremely slow
    local _filter="${3}"    # "*.properties"
    local _P="${4}"         #
    printf "Path,LastModified,Size"
    local _find="find ${_dir%/} -type f"
    [ -n "${_filter}" ] && _find="${_find} -name '${_filter}'"
    if [[ "${_with_props}" =~ ^(y|Y) ]]; then
        printf ",Properties\n"
        # without _o=, it may output empty "" line.
        eval "${_find} -print0" | xargs -0 -P${_P:-"3"} -I {} sh -c '[ -f {} ] && _o="$(find {} -printf "\"%p\",\"%t\",%s," && printf "\"%s\"\n" "$(echo "{}" | grep -q ".properties" && cat {} | tr "\n" "," | sed "s/,$//")")" && echo ${_o}'
    else
        printf "\n"
        eval "${_find} -printf '\"%p\",\"%t\",%s\n'"
    fi
}
```
```
#echo -n > ./'${_output_date}'; # Only first time, otherwise optional in case you might want to append
#touch /tmp/checker;            # Only first time, otherwise optional in case of continuing 
# TODO: is using `????????-????-????-????-????????????.properties` faster?
find ${_content_dir%/}/vol-* -type f -name '*.properties' -mtime -${_days} -print0 -not -newer /tmp/checker | xargs -P${_P} -I{} -0 bash -c 'grep -q "^deleted=true" {} && sed -i -e "s/^deleted=true//" {} && echo "'${_output_date}' 00:00:01,$(basename {} .properties)" >> ./'${_output_date}';'
```

## DOWNLOAD and INSTALL:
```bash
curl -o /usr/local/bin/file-list -L https://github.com/hajimeo/samples/raw/master/misc/file-list_$(uname)
chmod a+x /usr/local/bin/file-list
```

## ARGUMENTS:
```
Usage of file-list:
  -BSize
    	If true, includes .bytes size (When -f is '.properties')
  -H	If true, no header line
  -L	If true, just list directories and exit
  -O	If true, also get owner display name
  -P	If true, read and output the .properties files
  -R	If true, .properties content is *sorted* and _FILTER_P string is treated as regex
  -RDel
    	Remove 'deleted=true' from .properties. Requires -RF *and* -dF
  -RF
    	Output for the Reconcile task (any_string,blob_ref). -P will be ignored
  -S3
    	If true, access S3 bucket with AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_REGION
  -T	If true, also get tags of each object
  -X	If true, verbose logging
  -XX
    	If true, more verbose logging
  -b string
    	Base directory (default: '.') or S3 Bucket name (default ".")
  -bsName string
    	Eg. 'default'. If provided, the query will be faster
  -c int
    	Concurrent number for sub directories (may not need to use with very fast disk) (default 1)
  -c2 int
    	Concurrent number for retrieving AWS Tags (default 16)
  -dF string
    	Deleted date YYYY-MM-DD (from). Used to search deletedDateTime
  -dT string
    	Deleted date YYYY-MM-DD (to). To exclude newly deleted assets
  -mF string
    	File modification date YYYY-MM-DD (from).
  -mT string
    	File modification date YYYY-MM-DD (to).
  -db string
    	DB connection string or path to properties file
  -f string
    	Filter file paths (eg: '.properties')
  -fP string
    	Filter .properties contents (eg: 'deleted=true')
  -m int
    	Integer value for Max Keys (<= 1000) (default 1000)
  -n int
    	Return first N lines (0 = no limit). (TODO: may return more than N)
  -nodeId string
    	Advanced option.
  -p string
    	Prefix of sub directories (eg: 'vol-')
  -src string
    	Using database or blobstore as source [BS|DB] (default "BS")
```

## Usage Examples
NOTE: For accurate performance testing, may need to clear Linux file cache (as 'root'):
```
echo 3 > /proc/sys/vm/drop_caches
```
### List all files under the ./sonatype-work/nexus3/blobs/default
```
file-list -b ./sonatype-work/nexus3/blobs/default
... (snip) ...
"sonatype-work/nexus3/blobs/default/content/vol-43/chap-29/3488648f-d5f8-45f8-8314-10681fcaf0ce.properties","2021-09-17 08:35:03.907951265 +1000 AEST",352
"sonatype-work/nexus3/blobs/default/metadata.properties","2021-09-17 08:34:00.625028548 +1000 AEST",73

2021/12/31 14:23:09 INFO: Printed 185 items (size: 75910509) in ./sonatype-work/nexus3/blobs/default with prefix:
```

### Listing blob store items with .properties file contents (-P) with 10 concurrency (-c 10):
```
file-list -b ./sonatype-work/nexus3/blobs/default/content -p 'vol-' -P -c 10 > /tmp/default_with_props.tsv
```

### Finding deleted=true (-fP "\<expression\>")
```
file-list -b ./sonatype-work/nexus3/blobs/default/content -p 'vol-' -fP "deleted=true" -c 10 > /tmp/default_soft_deleted.tsv
```

### Check the total count and size of all .bytes files
This would be useful to compare with the counters in the Blobstore page.
```
$ file-list -b ./sonatype-work/nexus3/blobs/default/content -p 'vol-' -f ".bytes" >/dev/null
2021/12/31 14:24:15 INFO: Generating list with ./sonatype-work/nexus3/blobs/default ...
... (snip) ...
13:52:46.972949 INFO  Printed 136895 of 136895 (size:2423593014) in ./sonatype-work/nexus3/blobs/default/content and sub-dir starts with vol- (elapsed:26s)
```

### List all objects which properties contain 'repo-name=docker-proxy' and 'deleted=true'
```
file-list -b ./sonatype-work/nexus3/blobs/default/content -p "vol-" -c 10 -f ".properties" -P -fP "@Bucket\.repo-name=docker-proxy.+deleted=true" -R > docker-proxy_soft_deleted.tsv
```
NOTE: the attributes in a .properties file are sorted in memory, so that attributes start with "@" comes before "deleted=true" line.

### Output lines for the reconciliation (blobstore.rebuildComponentDB) YYYY-MM-DD text (-RF) and for the files which were modified on and after 2022-05-19 (-mF "\<date\>")
```
file-list -b ./sonatype-work/nexus3/blobs/default/content -p "vol-" -c 10 -RF -mF "2022-05-19" > ./$(date '+%Y-%m-%d')
```

### Output lines for the reconciliation (blobstore.rebuildComponentDB) YYYY-MM-DD text (-RF) and deleted from 2022-05-19 (-dF "\<date\>")
```
file-list -b ./sonatype-work/nexus3/blobs/default/content -p "vol-" -c 10 -RF -dF "2022-05-19" > ./$(date '+%Y-%m-%d')
```

### Remove 'deleted=true' (-RDel), then output lines for the reconciliation YYYY-MM-DD text
```
file-list -b ./sonatype-work/nexus3/blobs/default/content -p "vol-" -c 10 -RF -dF "2022-07-19" -RDel > ./$(date '+%Y-%m-%d')
```

### Check orphaned files by querying against PostgreSQL (-db "\<conn string or nexus-store.properties file path) with max 10 DB connections (-c 10)
```
file-list -b ./default/content -p vol- -c 10 -db "host=localhost port=5432 user=nxrm3pg password=nxrm3pg dbname=nxrm3pg"
```
or
```
file-list -b ./default/content -p vol- -c 10 -db /nexus-data/etc/fabric/nexus-store.properties
```
NOTE: Above outputs blobs which are not in <format>_asset table, which includes assets which have not soft-deleted by Cleanup unused asset blobs task.

### Check orphaned files, and with the reconciliation YYYY-MM-DD format output (-RF), and deleted after 2022-05-19 (-dF)
```
$ file-list -b ./default/content -p vol- -c 10 -db /nexus-data/etc/fabric/nexus-store.properties -RF -dF "2022-05-19" > ./$(date '+%Y-%m-%d') 2> ./file-list_$(date +"%Y%m%d%H%M%S").log
```
NOTE: If using -RDel to delete "deleted=true", recommend to save the STDERR into a file like above.