# File List
Demo script to list all objects from a File type blob store with CSV format.  
The expected usage is generating the list of blobRef IDs and compare with the blobRef IDs stored in Nexus DB (OrientDB / PostgreSQL) to find the inconsistency.
Basically rewrite of below bash function:
```bash
function f_blobs_csv() {
    local __doc__="Generate CSV for Key,LastModified,Size + properties"
    local _dir="$1"         # "blobs/default/content/vol-*"
    local _with_props="$2"  # Y to check properties file, but extremely slow
    local _filter="${3}"    # "*.properties"
    local _P="${4}"         #
    printf "Key,LastModified,Size"
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

### ARGUMENTS:
```
    -p Prefix_str   List objects which path starts with this prefix
    -f Filter_str   List objects which path contains this string (much slower)
    -fP Filter_str  List .properties file (no .bytes files) which contains this string (much slower)
                    Equivalent of -f ".properties" and -P.
    -n topN_num     Return first/top N results only
    -m MaxKeys_num  Batch size number. Default is 1000
    -c1 concurrency Concurrency number for Prefix (-p xxxx/content/vol-), execute in parallel per sub directory
    -c2 concurrency Concurrency number for Tags (-T) and also Properties (-P)
    -L              With -p, list sub folders under prefix
    -P              Get properties (can be very slower)
    -H              No column Header line
    -X              Verbose log output
    -XX             More verbose log output
```

## USAGE EXAMPLE:
TODO: below is incorrect
```
./aws-s3-list_Darwin -b apac-support-bucket -p "default/content/vol-" -c1 20 > /tmp/all_objects.csv
# Extract blob ref IDs only:
grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' /tmp/all_objects.csv | sort | uniq > all_blob_refs_s3.out

# Get blob ref IDs from a database backup file:
curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/orient-console.jar"
echo "SELECT blob_ref FROM asset WHERE blob_ref LIKE 's3-test@%'" | java -DexportPath=/tmp/result.json -jar ./orient-console.jar ../sonatype/backups/component-2021-08-30-22-00-00-3.33.0-01.bak
grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' /tmp/result.json | sort > all_blob_refs_from_db.out

# Check missing blobs:
diff -wy --suppress-common-lines all_blob_refs_s3.out all_blob_refs_from_db.out | head -n3
1ab44c7d-553a-416c-b0ec-a1e06088f984			      <
234e1975-2e5a-4d0c-9e06-bf85e33de422			      <
23bdb564-a670-4925-81ee-4ba70a33a672			      <
```
All above commands would complete within 10 seconds, and the last result means no dead blobs.