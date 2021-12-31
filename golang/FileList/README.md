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

## ARGUMENTS:
```
    -b BaseDir_str  Base directory path (eg: <workingDirectory>/blobs/default/content)
    -p Prefix_str   List only objects which directory *name* starts with this prefix (eg: val-)
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
List all objects which proerties contain 'repo-name=docker-proxy' and 'deleted=true'
```
$ file-list -b ./sonatype-work/nexus3/blobs/default/content -p "vol-" -c 10 -f ".properties" -P -fP "@Bucket\.repo-name=docker-proxy.+deleted=true" -R > docker-proxy_soft_deleted.csv
```

## Misc.
Listing relatively larger blob store **with all properties contents and with 200 concurrency**:
```
# time file-list -b ./content -P -c 200 >/tmp/files2.csv
2021/12/31 14:54:12 WARN: With Properties (-P), listing can be slower.
2021/12/31 14:54:12 INFO: Generating list with ./content ...

2021/12/31 14:54:14 INFO: Printed 113939 items (size: 16658145001) in ./content with prefix: ''

real    0m1.908s    <<< very fast!
user    0m1.733s
sys     0m1.775s
```