# File List
Demo script to list all objects from a File type blob store with CSV format.  
The expected usage is generating the list of blobRef IDs and compare with the blobRef IDs stored in Nexus DB (OrientDB / PostgreSQL) to find the inconsistency.
Basically rewrite of below bash function:
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

## DOWNLOAD and INSTALL:
```bash
curl -o /usr/local/bin/file-list -L https://github.com/hajimeo/samples/raw/master/misc/file-list_$(uname)
chmod a+x /usr/local/bin/file-list
```

## Example output
Listing blob store items **with all properties contents** and with 10 concurrency:
```
[root@node-nxrm-ha1 sonatype]# echo 3 > /proc/sys/vm/drop_caches
[root@node-nxrm-ha1 sonatype]# file-list -b ./sonatype-work/nexus3/blobs/default/content -p 'vol-' -P -c 10 > /tmp/default_props.csv
2022/01/12 02:52:06 WARN: With Properties (-P), listing can be slower.
2022/01/12 02:52:06 INFO: Generating list with ./sonatype-work/nexus3/blobs/default/content ...

2022/01/12 02:53:49 INFO: Printed 35731 items (size: 5278777651) in ./sonatype-work/nexus3/blobs/default/content with prefix: 'vol-'
```
About 350 files per second on HDD (non SSD).

Finding deleted=true (just for testing as you should just grep against /tmp/default_props.csv)
```
[root@node-nxrm-ha1 sonatype]# file-list -b ./sonatype-work/nexus3/blobs/default/content -p 'vol-' -fP "deleted=true" -c 10 > /tmp/default_soft_deleted.csv
2022/01/12 02:56:44 WARN: With Properties (-P), listing can be slower.
2022/01/12 02:56:44 INFO: Generating list with ./sonatype-work/nexus3/blobs/default/content ...

2022/01/12 02:56:44 INFO: Printed 24 items (size: 19114) in ./sonatype-work/nexus3/blobs/default/content with prefix: 'vol-'
```
This time, it's much faster because of buffer/cache on Linux.

## ARGUMENTS:
```
    -b BaseDir_str  Base directory path (eg: <workingDirectory>/blobs/default/content)
    -p Prefix_str   List only objects which directory *name* starts with this prefix (eg: val-)
                    Require -c 2 or higher number. If -c 1, -p is not used.
    -f Filter_str   List only objects which path contains this string (eg. .properties)
    -fP Filter_str  List .properties file (no .bytes files) which contains this string (much slower)
                    Equivalent of -f ".properties" and -P.
    -n topN_num     Return first/top N results only
    -c concurrency  Executing walk per sub directory in parallel (may not need with very fast disk)
    -P              Get properties (can be very slower)
    -R              Treat -fP value as regex
    -H              No column Header line
    -X              Verbose log output
```

## USAGE EXAMPLE:
List all files under the ./sonatype-work/nexus3/blobs/default
```
$ file-list -b ./sonatype-work/nexus3/blobs/default
... (snip) ...
"sonatype-work/nexus3/blobs/default/content/vol-43/chap-29/3488648f-d5f8-45f8-8314-10681fcaf0ce.properties","2021-09-17 08:35:03.907951265 +1000 AEST",352
"sonatype-work/nexus3/blobs/default/metadata.properties","2021-09-17 08:34:00.625028548 +1000 AEST",73

2021/12/31 14:23:09 INFO: Printed 185 items (size: 75910509) in ./sonatype-work/nexus3/blobs/default with prefix:
```
Check the count and size of all .bytes file under "content" directory under "default" blob store (including tmp files).  
This would be useful to compare with the counters in the Blobstore page.
```
$ file-list -b ./sonatype-work/nexus3/blobs/default/content -f ".bytes" >/dev/null
2021/12/31 14:24:15 INFO: Generating list with ./sonatype-work/nexus3/blobs/default ...

2021/12/31 14:24:15 INFO: Printed 91 items (size: 75871811) in ./sonatype-work/nexus3/blobs/default with prefix: ''
```
Parallel execution (concurrency 10), and save to all_objects.csv file
```
$ file-list -b ./sonatype-work/nexus3/blobs/default/content -p "vol-" -c 10 > all_objects.csv
```
Parallel execution (concurrency 10) with all properties
```
$ file-list -b ./sonatype-work/nexus3/blobs/default/content -p "vol-" -c 10 -f ".properties" -P > all_with_props.csv
```
List all objects which proerties contain 'deleted=true'
```
$ file-list -b ./sonatype-work/nexus3/blobs/default/content -p "vol-" -c 10 -f ".properties" -P -fP "deleted=true" > soft_deleted.csv
```
List all objects which properties contain 'repo-name=docker-proxy' and 'deleted=true' (NOTE: properties are sorted)
```
$ file-list -b ./sonatype-work/nexus3/blobs/default/content -p "vol-" -c 10 -f ".properties" -P -fP "@Bucket\.repo-name=docker-proxy.+deleted=true" -R > docker-proxy_soft_deleted.csv
```

## ADVANCE USAGE EXAMPLE:
```
file-list -b /opt/sonatype/sonatype-work/nexus3/blobs/default/content -p 'vol-' -P -c 10 > default_props.csv
# Extract blob ref IDs only:
grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' default_props.csv | sort | uniq > /tmp/default_blob_refs.out

# Get blob ref IDs from a database backup file:
curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/orient-console.jar"
echo "SELECT blob_ref FROM asset WHERE blob_ref LIKE 'default@%'" | java -DexportPath=/tmp/result.json -jar ./orient-console.jar ../sonatype/backups/component-2022-01-04-22-00-00-3.37.0-01.bak
grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' /tmp/result.json | sort | uniq > /tmp/default_blob_refs_from_db.out

# Check missing blobs:
diff -wy --suppress-common-lines /tmp/default_blob_refs.out /tmp/default_blob_refs_from_db.out > default_blob_refs_diff.out

head -n3 default_blob_refs_diff.out
001c00d5-7a50-4412-9523-b5c080b21ea7                          <
0021bef4-139f-414d-93d6-8dc98b93ca1a                          <
00261d0f-0fa7-4d68-b354-7ff18b5dab62                          <

# Check details
grep "001c00d5-7a50-4412-9523-b5c080b21ea7.properties" default_props.csv | tr ',' '\n'
"/opt/sonatype/sonatype-work/nexus3/blobs/default/content/vol-05/chap-45/001c00d5-7a50-4412-9523-b5c080b21ea7.properties"
"2021-10-19 00:59:38.430595915 +0000 UTC"
1200
"#2021-10-19 00:59:38
435+0000
#Tue Oct 19 00:59:38 UTC 2021
@attributes.asset.npm.repository_url=https\://github.com/facebook/regenerator/tree/master/packages/regenerator-runtime
@BlobStore.created-by-ip=system
... (snip) ...
@BlobStore.blob-name=/regenerator-runtime/-/regenerator-runtime-0.11.1.tgz
@attributes.asset.npm.license=MIT
@attributes.asset.npm.tagged_not=
@attributes.asset.npm.name=regenerator-runtime"
```
All above commands would complete within 10 seconds, and the last result means no dead blobs but orphaned blobs (looks like because of PostgreSQL migration test as per "@BlobStore.blob-name=/").

Example of generating filepath list for deleting all orphaned:
```
grep -oE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' default_blob_refs_diff.out | while read -r _br; do
  # Below is slow, but just in case, to make sure all blob-name starts with "/"
  #grep -E "${_br}\.properties.+,@BlobStore\.blob-name=/" default_props.csv | grep -oE '^"[^"]+"' | sed -E 's/.properties/.*/g'
  grep -oE "[^\"]+${_br}[^\"]+" default_props.csv
done > orphaned_filepath.out
```

```
find ./vol-* -type f -name '*.bytes' > all_bytes_files.out
grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' all_bytes_files.out > blob_ids_only.out
```