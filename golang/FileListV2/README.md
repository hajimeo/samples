# File List V2

`filelist2` is a troubleshooting and data-maintenance utility for Nexus blob stores.

## What this tool does

- Lists files from supported blob stores (`file://`, `s3://`, `az://`)
- Filters by path, file name, dates, and `.properties` content (regex)
- Detects blob inconsistencies:
  - blob exists in blob store but not DB (`-src BS`, orphaned blobs)
  - blob exists in DB but not blob store (`-src DB`, dead blobs)
- Removes `deleted=true` markers from selected `.properties` files (`-RDel`)
- Copies selected blobs between stores (`-bTo`, experimental)

## Install

Example download and install as `filelist2`:

```bash
curl -o ./filelist2 -L "https://github.com/sonatype/nexus-monitoring/raw/refs/heads/main/resources/filelistv2_$(uname)_$(uname -m)"
chmod a+x ./filelist2
```

## Help

```bash
filelist2 --help
```

Note: flags that start with a capital letter are boolean switches (no value), for example `-X`, `-XX`.

## Conventions

- Default blob URI scheme is `file://`, so both of these work:
  - `-b ./sonatype-work/nexus3/blobs/default/content`
  - `-b file://sonatype-work/nexus3/blobs/default/content`
- `-pRx` applies regex to normalized `.properties` content.
- `-pRxExcl` is evaluated before `-pRx`.
- `-BytesChk` is useful when deletion markers are ambiguous.

## Quick Start

### 1) List files in a blob store

```bash
BLOB_STORE="./sonatype-work/nexus3/blobs/default/content"
filelist2 -b "$BLOB_STORE"
```

### 2) Save results with concurrency

```bash
filelist2 -b "$BLOB_STORE" -c 80 -s /tmp/filelist_under-path.tsv
```

Recommended `-c`: usually less than `(CPU / 2) * 10`, unless storage/network behavior suggests otherwise. For S3, `-c 1 -c2 8` can improve throughput in some environments.

### 3) List matching `.properties` lines

```bash
filelist2 -b "$BLOB_STORE" -pRx ",deleted=true" -P -c 10 -s /tmp/filelist_soft-deleted.tsv
```

## Blob Store Backends

### S3

```bash
export AWS_ACCESS_KEY_ID="*******" AWS_SECRET_ACCESS_KEY="********" AWS_REGION="ap-southeast-2"

filelist2 -b "s3://${AWS_BLOB_STORE_NAME}/filelist-test/content"
```

### MinIO (S3-compatible)

```bash
export AWS_ACCESS_KEY_ID="*******" AWS_SECRET_ACCESS_KEY="********" AWS_REGION="" AWS_ENDPOINT_URL="http://127.0.0.1:19000"

filelist2 -b "s3://MinIO_bucket_name/prefix_name/content"
```

### Azure Blob

```bash
export AZURE_STORAGE_ACCOUNT_NAME="********" AZURE_STORAGE_ACCOUNT_KEY="*********************"

filelist2 -b "az://${AZURE_STORAGE_CONTAINER_NAME}/content"
```

For Azure SDK debug logs:

```bash
export AZURE_SDK_GO_LOGGING="all"
```

### GCS

Not yet implemented:

```bash
# TODO
filelist2 -b "gs://google-test-storage/google-test-prefix/content"
```

## Common Workflows

### List by repository and modified date

```bash
BLOB_STORE="./sonatype-work/nexus3/blobs/default/content"
filelist2 -b "$BLOB_STORE" -P -pRx "@Bucket.repo-name=raw-hosted," -mDF "$(date -d "1 day ago" +%Y-%m-%d)" 2>/dev/null

# As .properties and .bytes timestamps can differ, use -BytesChk to check .bytes timestamp
filelist2 -b "$BLOB_STORE" -P -pRx "@Bucket.repo-name=raw-hosted," -mDF "$(date -d "1 day ago" +%Y-%m-%d)" -BytesChk 2>/dev/null
```

### Restrict by file extension while saving output

```bash
filelist2 -b "$BLOB_STORE" -f ".properties" -P -c 80 -s /tmp/filelist_props-only.tsv
```

### Include and exclude regex together

```bash
filelist2 -b "$BLOB_STORE" \
  -pRxExcl "BlobStore\.blob-name=.+/maven-metadata.xml.*" \
  -pRx "@Bucket\.repo-name=maven-proxy," \
  -P -c 80 -s /tmp/filelist_maven-proxy_excl_metadata.tsv
```

### Reuse a previous result file

Read blob IDs from a saved file and list only `.properties`:

```bash
filelist2 -b "$BLOB_STORE" -f ".properties" -P -s /tmp/filelist_reused_result.tsv -rF ./reuse_some_previous_result.tsv
```

If `-f ".properties"` is omitted, the output can include `.bytes` paths too.

### Count total `.bytes` files and size

```bash
filelist2 -b "$BLOB_STORE" -f ".bytes" >/dev/null
```

Example end-of-run log:

```text
INFO  Printed 136895 of 273790 files, size: 2423593014 bytes (elapsed:26s)
```

Meaning: 273790 scanned, 136895 matched `.bytes`, total matched size = 2423593014 bytes.

### Sum size from `.properties` `size={n}`

```bash
filelist2 -b "$BLOB_STORE" -pRx "@Bucket\.repo-name=raw-hosted" -P -s /tmp/filelist_raw-hosted_props.tsv
rg -o -r '$1' ',size=(\d+)' /tmp/filelist_raw-hosted_props.tsv | awk '{ c+=1;s+=$1 }; END { print "blobCount:"c", totalSize:"s" bytes" }'
```

## Remove `deleted=true` Markers

Dry-run style collection first (`-H` no header):

```bash
filelist2 -b "$BLOB_STORE" -pRx "@Bucket\.repo-name=raw-hosted,.+deleted=true" -P -H -BytesChk -c 80 -s /tmp/filelist_raw-hosted_soft-deleted.tsv
```

Then review the TSV (for example, remove `BYTES_MISSING` lines), and apply marker removal with `-RDel`:

```bash
filelist2 -b "$BLOB_STORE" -rF /tmp/filelist_raw-hosted_soft-deleted.tsv -RDel -P -c 80 -s /tmp/filelist_raw-hosted_undeleted.tsv
```

## Consistency Checks Against DB

### Orphaned blobs: exists in blob store, missing in DB (`-src BS`)

```bash
NOT_NEWER_THAN_DATE="$(date -d "1 day ago" +%Y-%m-%d)"  # `gdate` if Mac
filelist2 -b "$BLOB_STORE" -c 10 -src BS \
  -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties \
  -mDT "${NOT_NEWER_THAN_DATE}" \
  -P -pRxExcl "deleted=true" -BytesChk \
  -s /tmp/filelist_orphaned_blobs.tsv
```

Notes:

- Run cleanup unused asset blobs tasks first; query logic depends on INNER JOIN of `asset_blob` and `asset`.
- Keep concurrency moderate when `-db` is used.
- `-db` also supports connection strings, e.g.:
  - `host=localhost user=nexus dbname=nexus` (with `PGPASSWORD`)
  - Reference: https://pkg.go.dev/github.com/lib/pq#hdr-Connection_String_Parameters
- In newer Nexus versions, `originalLocation` behavior may change. If needed:
  - `-pRxExcl "(deleted=true|originalLocation)"`

#### No blob-store access mode (comparing blob IDs in `-rF` and DB):

```bash
filelist2 -src BS -rF ./some_filelist_result.tsv \
  -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties \
  -bsName default -s /tmp/filelist_orphaned-blobs_no-BS-access.tsv
```

Optional archive workflow:

```bash
cd /To/Blobstore
cut -d '.' -f1 ./some_filelist_result.tsv | while read -r id; do tar -rvf /tmp/test.tar --remove-files ${id}.*; done
```

### Dead blobs: exists in DB, missing in blob store (`-src DB`)

```bash
filelist2 -b "$BLOB_STORE" \
  -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties \
  -c 10 \
  -query "SELECT blob_ref as blob_id from raw_asset_blob ab join raw_asset a using (asset_blob_id) where repository_id IN (select cr.repository_id from raw_content_repository cr join repository r on r.id = cr.config_repository_id where r.name in ('raw-hosted'))" \
  -src DB -s /tmp/filelist_potentially_dead-blobs.tsv
```

Alternative repo shortcut:

```bash
filelist2 -b "$BLOB_STORE" -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -c 10 -qRepos "raw-hosted,raw-filestore-hosted" -src DB -s /tmp/filelist_potentially_dead-blobs.tsv
```

## Soft-Deleted Blob Recovery Workflow

Generate candidate blob IDs from `soft_deleted_blobs` and prepare input for undeleter:

```bash
filelist2 -b "$BLOB_STORE" \
  -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties \
  -query "SELECT blob_id||'@'||TO_CHAR(date_path_ref AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI') as blob_id FROM soft_deleted_blobs WHERE source_blob_store_name = 'default' AND deleted_date > NOW() - INTERVAL '3 days' ORDER BY deleted_date LIMIT 1000" \
  -s ./restoring_blobs.tsv

# After review the result:
bash ./nrm3-undelete-3.83.sh -I -s default -b ./restoring_blobs.tsv
```

If you only need the query output quickly:

```bash
filelist2 -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -query "SELECT blob_id, * FROM soft_deleted_blobs WHERE source_blob_store_name = 'default' and deleted_date > NOW() - INTERVAL '300 days' ORDER BY deleted_date limit 1000" -rF /tmp/filelist_query-result.out
```

Another example query with REPO_ID and some `path` fileter:

```bash
filelist2 -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties -query "SELECT ab.blob_ref as blob_id FROM raw_asset_blob ab JOIN raw_asset a USING (asset_blob_id) WHERE repository_id IN (${REPO_ID}) and path like '/test%' LIMIT 1000" -rF /tmp/filelist_query-result_2.out
```

## Experimental Copy Between Blob Stores (`-bTo`)

Example S3 to MinIO copy for selected blobs:

```bash
# Assuming necessary envs for the source blob store are set already. XXXX_2 is for the destination
export AWS_ACCESS_KEY_ID_2="admin"
export AWS_SECRET_ACCESS_KEY_2="admin123"
export AWS_REGION_2=""
export AWS_ENDPOINT_URL_2="https://local.standalone.localdomain:19000"
export AWS_CA_BUNDLE_2="$HOME/minio_data/certs/public.crt"

filelist2 -b "s3://apac-support-bucket/filelist-test/" \
  -bTo "s3://test-bucket/filelist-test_copied/" \
  -PathStyle -P \
  -pRx "@Bucket.repo-name=raw-s3-hosted," \
  -pRxExcl ",(deleted=true|originalLocation=)" \
  -H -s ./copied_blobs.tsv
```

`AWS_CA_BUNDLE` can interfere with normal AWS S3 TLS; use with care. May also require to use `-PathStyle` if not wildcard certificate.

Example S3 to Azurite:

```bash
export AZURE_STORAGE_CONNECTION_STRING_2="DefaultEndpointsProtocol=http;AccountName=admin;AccountKey=YWRtaW4xMjM=;BlobEndpoint=http://localhost:10000/admin;"
az storage container create --name "apac-support-bucket-filelist-test-copied" --connection-string "${AZURE_STORAGE_CONNECTION_STRING_2}"

filelist2 -b "s3://apac-support-bucket/filelist-test/" \
  -bTo "az://apac-support-bucket-filelist-test-copied/" \
  -P -pRx "@Bucket.repo-name=raw-s3-hosted," \
  -pRxExcl ",(deleted=true|originalLocation=)" \
  -H -s ./copied_blobs.tsv

# Validate copied blobs
AZURE_STORAGE_CONNECTION_STRING="${AZURE_STORAGE_CONNECTION_STRING_2}" filelist2 -b "az://apac-support-bucket-filelist-test-copied/" -rF ./copied_blobs.tsv
```

After review, run the undeleter against another Nexus instance to populate the DB:

```bash
bash ./nrm3-undelete-3.83.sh -I -s default -b ./copied_blobs.tsv
```

SQL-generated list copy example:

```bash
filelist2 -b ./sonatype-work/nexus3/blobs/default \
  -db ./sonatype-work/nexus3/etc/fabric/nexus-store.properties \
  -query "select blob_ref as blob_id from raw_asset_blob ab join raw_asset a using (asset_blob_id) where repository_id IN (select cr.repository_id from raw_content_repository cr join repository r on r.id = cr.config_repository_id where r.name in ('raw-hosted')) LIMIT 1" \
  -c 100 -bTo "s3://apac-support-bucket/filelist-test_copied/" -P -s copied_from_local_blobs.tsv
```

## Utilities and Notes

### Generate comma-separated blob IDs from saved output

```bash
sed -n -E 's/.+([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\..+/\1/p' ./docker-proxy_soft_deleted.tsv | paste -sd, -
```

Get `datetime,blobId` pairs (for reconciliation input):

```bash
sed -n -E 's/.+([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\..+([0-9]{4}.[0-9]{2}.[0-9]{2}.[0-9]{2}:[0-9]{2}:[0-9]{2}).+/\2,\1/p' ./$(date +"%Y%m%d%H%M%S").tsv > "./reconciliation/$(date '+%Y-%m-%d')"
```

### Hard-delete files from a saved list (file blob store)

```bash
cat ./docker-proxy_soft_deleted.tsv | cut -d '.' -f1 | xargs -I{} -t rm -v -f {}.{properties,bytes}
```

This assumes the text before the first `.` is the full or relative blob file path.

### OrientDB example (`blob_ref` list)

```bash
cd ./sonatype-work/nexus3/
echo "select blob_ref from asset where bucket.repository_name = 'xxxxxxx'" | orient-console ./db/component/
```

### Update or restore deletion marker string with `-wStr` (under `2025` directory)

```bash
filelist2 -b s3://apac-support-bucket/filelist-test/content/ -p 2025 -pRx "deleted=true" -wStr "deleted=true"

# Confirm (Without `-T` is faster and not needed for newer Nexus)
filelist2 -b s3://apac-support-bucket/filelist-test -pRx "deleted=true" -T
```

## Safety

- Review generated TSV files before destructive operations (`-RDel`, `rm`, or external restore scripts).
- Start with lower concurrency for DB-backed or blob-store which utilis some connection pool.
- For very large DB queries, split with `LIMIT/OFFSET` or range conditions.
