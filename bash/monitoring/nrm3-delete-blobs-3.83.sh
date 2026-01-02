#!/usr/bin/env bash
usage() {
    cat << 'EOF'
PURPOSE:
    Delete one or multiple blob IDs (call this script concurrently for many blob IDs)
    This script is for Nexus version 3.83 and higher.

LIMITATION:
    May not be able to delete from group blob store or group member as the blob name in blob_ref can be different.

REQUIREMENTS:
    'curl' for uploading the script and initiating the script
    'nexus.scripts.allowCreation=true' in nexus.properties

EXAMPLES:
    cd /some/workDir
    curl --compressed -o nrm3-delete-blobs.sh -L https://raw.githubusercontent.com/sonatype/nexus-monitoring/main/scripts/nrm3-delete-blobs-3.83.sh
    export _ADMIN_USER="admin" _ADMIN_PWD="******" _NEXUS_URL="http://localhost:8081/" #_NO_BS_CHK="true" _DRY_RUN="true" _USE_SED="false"
    bash ./nrm3-undelete.sh -I  -s <blobStoreName> -b <blobIDs>

OPTIONS:
    -I  Installing the groovy script for deleting blobs (only once per Nexus)
    -s  blob store name, which is beginning of the blob ref (before '@')
    -b  blob IDs (comma separated), or a file contains lines of blobIDs
EOF
}


### Global variables #################
: "${_ADMIN_USER:="admin"}"
: "${_ADMIN_PWD:="admin123"}"
: "${_NEXUS_URL:="http://localhost:8081/"}"
: "${_INSTALL:=""}"
: "${_BATCH_SIZE:="10"}"   # for xargs -L
: "${_PARALLEL:="2"}"   # for xargs -P
: "${_USE_SED:="true"}"   # If the blobIds file contains extra strings, use sed to extract valid blob IDs
: "${_TMP:="/tmp"}"
_SCRIPT_NAME="deleteByBlobIDs"
# Below is used in the POST json string
: "${_BLOB_STORE:=""}"
: "${_BLOB_IDS:=""}"    # comma separated blobIds
: "${_NO_BS_CHK:="false"}"
: "${_DRY_RUN:="false"}"
: "${_DEBUG:="false"}"


### Functions ########################
function genScriptContent() {
    # How to generate the below (NOTE: remove the beginning and ending double-quotes):
    #   python3 -c "import sys,json;print(json.dumps(open('nrm3-delete-blobs_draft.groovy').read()))"
    cat <<'EOF'
import groovy.json.JsonSlurper\nimport org.sonatype.nexus.common.log.LogManager\nimport org.sonatype.nexus.common.log.LoggerLevel\nimport groovy.json.JsonOutput\n\ndef main(params) {\n    def blobIdPtnNew = '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})@([0-9]{4})-([0-9]{2})-([0-9]{2}).([0-9]{2}):([0-9]{2}).*'\n    // 2025/09/08/06/07/aac3683b-111f-4d3d-96da-811e8cf23a0f\n    def blobIdPtnNewPath = '/?([0-9]{4})/([0-9]{2})/([0-9]{2})/([0-9]{2})/([0-9]{2})/([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}).*'\n    def blobIdPtn = '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}).*'\n    def lineCounter = 0\n    def deletedNum = 0\n    def repositoryManager = container.lookup(org.sonatype.nexus.repository.manager.RepositoryManager)\n    def store = container.lookup(org.sonatype.nexus.blobstore.api.BlobStoreManager.class.name).get(params.blobStore)\n    if (!store) {\n        def logMsg = \"params.blobStore: ${params.blobStore} is invalid\"\n        if (params.noBsChk) {\n            log.warn(logMsg + \", but continuing as noBsChk is true\")\n        } else {\n            log.error(logMsg)\n            return ['error': logMsg]\n        }\n    }\n    def blobIDs = (params.blobIDs as String).split(\",\")\n    if (!blobIDs || blobIDs.size() == 0) {\n        def logMsg = \"params.blobIDs is empty\"\n        log.error(logMsg)\n        return ['error': logMsg]\n    }\n    // 'params' should contain 'blobIDs', 'blobStore', 'noBsChk', 'dryRun', and 'debug'\n    log.info(\"Checking ${blobIDs.length} blobIds with blobStore: ${params.blobStore}, noBsChk: ${params.noBsChk}, dryRun: ${params.dryRun}, debug: ${params.debug}\")\n\n    for (line in blobIDs) {\n        log.debug(\"line = ${line}\")\n        lineCounter++\n        try {\n            def blobCreatedRef = null\n            def blobId = \"\"\n            def match = line =~ blobIdPtnNewPath\n            if (match) {\n                blobId = match[0][6] as String\n                def year = match[0][1] as Integer\n                def month = match[0][2] as Integer\n                def day = match[0][3] as Integer\n                def hour = match[0][4] as Integer\n                def minute = match[0][5] as Integer\n                blobCreatedRef = java.time.OffsetDateTime.of(year, month, day, hour, minute, 0, 0, java.time.ZoneOffset.UTC)\n            } else {\n                match = line =~ blobIdPtnNew\n                if (match) {\n                    blobId = match[0][1] as String\n                    def year = match[0][2] as Integer\n                    def month = match[0][3] as Integer\n                    def day = match[0][4] as Integer\n                    def hour = match[0][5] as Integer\n                    def minute = match[0][6] as Integer\n                    blobCreatedRef = java.time.OffsetDateTime.of(year, month, day, hour, minute, 0, 0, java.time.ZoneOffset.UTC)\n                } else {\n                    match = line =~ blobIdPtn\n                    if (match) {\n                        blobId = match[0][1] as String\n                    } else {\n                        log.warn(\"#${lineCounter}: '${line}' does not contain blobId\")\n                        continue\n                    }\n                }\n            }\n            log.debug(\"match[0] = ${match[0]}\")\n            def blobRefStr = params.blobStore + \"@\" + blobId\n            if (blobCreatedRef) {\n                blobRefStr = blobRefStr + \"@\" + blobCreatedRef.toString()\n            }\n            log.debug(\"Deleting blobRef:{}\", blobRefStr)\n\n            def isDeleted = false\n            repositoryManager.browse().each {\n                def repoBlobStore = it.getConfiguration().attributes.storage.blobStoreName\n                if (!params.noBsChk && params.blobStore && params.blobStore.trim().length() > 0 && repoBlobStore != params.blobStore) {\n                    log.debug(\"Skipping repository {} as blobStore {} does not match {}\", it.name, repoBlobStore, params.blobStore)\n                    return\n                }\n                def repositoryId = org.sonatype.nexus.repository.content.store.InternalIds.contentRepositoryId(it).get()\n                def content = it.facet(org.sonatype.nexus.repository.content.facet.ContentFacet)\n                def maybeAsset = ((org.sonatype.nexus.repository.content.facet.ContentFacetSupport) content).stores().assetStore.findByBlobRef(repositoryId, org.sonatype.nexus.blobstore.api.BlobRef.parse(blobRefStr))\n                if (maybeAsset.isPresent()) {\n                    def asset = maybeAsset.get()\n                    if (!params.dryRun) {\n                        it.facet(org.sonatype.nexus.repository.content.maintenance.ContentMaintenanceFacet).deleteAsset(asset)\n                    }\n                    log.info(\"Deleted path:{}, blobRef:{} from repository {} (DryRun:{})\", asset.path(), blobRefStr, it.name, params.dryRun)\n                    deletedNum++\n                    isDeleted = true\n                    return  // break out of repo loop for performance\n                }\n            }\n            if (!isDeleted) {\n                // Already deleted?\n                log.warn(\"No asset in DB with blobRef: {} from any repository\", blobRefStr)\n            }\n        }\n        catch (Exception e) {\n            log.warn(\"Exception while deleting blob from line:{} - {}\", line, e.getMessage())\n            if (params.dryRun) {    // If dryRun stops at the exception\n                throw e\n            }\n        }\n        // NOTE: not doing blobStoreIntegrityCheck as wouldn't need for this script\n    }\n    log.info(\"Deleted {}/{}\", deletedNum, blobIDs.size())\n    return ['checked': lineCounter, 'deleted': deletedNum, 'dryRun': params.dryRun]\n}\n\nlog.info(\"Delete by Blob IDs script started.\")\ndef logMgr = container.lookup(LogManager.class.name) as LogManager\ndef currentLevel = logMgr.getLoggerLevel(\"org.sonatype.nexus.internal.script.ScriptTask\")\ntry {\n    def params = (args) ? new JsonSlurper().parseText(args as String) : null\n    if (params.debug && (params.debug == \"true\" || params.debug == true)) {\n        logMgr.setLoggerLevel(\"org.sonatype.nexus.internal.script.ScriptTask\", LoggerLevel.DEBUG)\n        logMgr.setLoggerLevel(\"org.sonatype.nexus.script.plugin.internal.rest.ScriptResource\", LoggerLevel.DEBUG)\n    }\n    return JsonOutput.toJson(main(params))\n} finally {\n    logMgr.setLoggerLevel(\"org.sonatype.nexus.internal.script.ScriptTask\", currentLevel)\n    logMgr.setLoggerLevel(\"org.sonatype.nexus.script.plugin.internal.rest.ScriptResource\", currentLevel)\n    log.info(\"Delete by Blob IDs script completed.\")\n}\n
EOF
}

main() {
    local _blobIDs="${1:-"${_BLOB_IDS}"}"
    local _blobStore="${2:-"${_BLOB_STORE}"}"
    local _install="${3:-"${_INSTALL}"}"

    if [[ "${_install}" =~ ^[yY] ]]; then
        echo "{\"name\":\"${_SCRIPT_NAME}\",\"content\":\"$(genScriptContent)\",\"type\":\"groovy\"}" > ${_TMP%/}/${_SCRIPT_NAME}.json || return $?
        # Delete if exists, and not showing error if not exists, but if install fails, it will show error and exit
        curl -s -L -k -u "${_ADMIN_USER}:${_ADMIN_PWD}" -H 'Content-Type: application/json' "${_NEXUS_URL%/}/service/rest/v1/script/${_SCRIPT_NAME}" -X DELETE
        curl -sSf -L -k -u "${_ADMIN_USER}:${_ADMIN_PWD}" -H 'Content-Type: application/json' "${_NEXUS_URL%/}/service/rest/v1/script" -d@${_TMP%/}/${_SCRIPT_NAME}.json || return $?
    fi
    if [ -z "${_blobIDs}" ]; then
        echo "No blobIDs (-b)" >&2
        return
    fi
    if [ -z "${_blobStore}" ]; then
        echo "No blobStore name (-s)" >&2
        return
    fi
    # If _blobIDs is a file, read the file and convert to comma separated string
    if [ -s "${_blobIDs}" ]; then
        # In case the line contains unnecessary strings, like file-list result
        if [ "${_USE_SED}" == "true" ] && type sed >/dev/null 2>&1; then
            # As the order might matter, not using 'sort'... but running two sed for YYYY dir and vol-NN.
            sed -n -E 's/.*\/([0-9]{4}\/[0-9]{2}\/[0-9]{2}\/[0-9]{2}\/[0-9]{2}\/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[xa-f0-9]{4}-[a-f0-9]{12}).*/\1/p' ${_blobIDs} > ${_TMP%/}/blobIDs_$$.tmp
            sed -n -E 's/.*\/content\/vol-[0-9]{2}\/chap-[0-9]{2}\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}).*/\1/p' ${_blobIDs} >> ${_TMP%/}/blobIDs_$$.tmp
            if [ ! -s "${_TMP%/}/blobIDs_$$.tmp" ]; then
                echo "No valid blobIDs found in file ${_blobIDs} (${_TMP%/}/blobIDs_$$.tmp)" >&2
                echo "If ${_blobIDs} contains only blob IDs (no '.properties'), may want to use _USE_SED=\"false\"" >&2
                return
            fi
            _blobIDs="${_TMP%/}/blobIDs_$$.tmp"
        fi
        if type xargs >/dev/null 2>&1; then
            cat << EOF > "${_TMP%/}/${_SCRIPT_NAME}_batch.sh"
#!/usr/bin/env bash
_blobIDs="\$(echo "\$@" | tr " " ",")"
curl -sSf -L -k -u '${_ADMIN_USER}:${_ADMIN_PWD}' -H 'Content-Type: application/json' "${_NEXUS_URL%/}/service/rest/v1/script/${_SCRIPT_NAME}/run" -d"{\"blobIDs\":\"\${_blobIDs%,}\",\"blobStore\":\"${_blobStore}\",\"noBsChk\":${_NO_BS_CHK:-"false"},\"dryRun\":${_DRY_RUN:-"false"},\"debug\":${_DEBUG:-"false"}}"
echo ""
EOF
            if [ "${_DEBUG}" == "true" ]; then
                echo "Created ${_TMP%/}/${_SCRIPT_NAME}_batch.sh with content:"
                cat "${_TMP%/}/${_SCRIPT_NAME}_batch.sh"
                cat "${_blobIDs}" | xargs -P ${_PARALLEL:-1} -L ${_BATCH_SIZE:-1} -t bash -x ${_TMP%/}/${_SCRIPT_NAME}_batch.sh
            else
                cat "${_blobIDs}" | xargs -P ${_PARALLEL:-1} -L ${_BATCH_SIZE:-1} bash ${_TMP%/}/${_SCRIPT_NAME}_batch.sh
            fi
            # TODO: xargs do not stop at the first error
            return $?
        fi
    fi
    curl -sSf -L -k -u "${_ADMIN_USER}:${_ADMIN_PWD}" -H 'Content-Type: application/json' "${_NEXUS_URL%/}/service/rest/v1/script/${_SCRIPT_NAME}/run" -d'{"blobIDs":"'${_blobIDs%,}'","blobStore":"'${_blobStore}'","dryRun":'${_DRY_RUN:-"false"}',"debug":'${_DEBUG:-"false"}'}'
}


if [ "$0" = "${BASH_SOURCE[0]}" ]; then
    if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ]; then
        usage
        exit 0
    fi

    while getopts "Ib:s:" opts; do
        case $opts in
        I)
            _INSTALL="Y"
            ;;
        b)
            [ -n "$OPTARG" ] && _BLOB_IDS="$OPTARG"
            ;;
        s)
            [ -n "$OPTARG" ] && _BLOB_STORE="$OPTARG"
            ;;
        *)
            echo "$opts $OPTARG is not supported. Ignored." >&2
            ;;
        esac
    done

    main
    echo "" >&2
    echo "Completed." >&2
fi
