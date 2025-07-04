#!/usr/bin/env bash
usage() {
    cat << 'EOF'
PURPOSE:
    Undelete one or multiple blob IDs (call this script concurrently for many blob IDs)

NOTE:
    As the name/path of RestoreBlobStrategy can be different by Nexus version, this script is not guaranteed to work for all Nexus versions. Please test it first.

REQUIREMENTS:
    'curl' for uploading the script and initiating the script
    'nexus.scripts.allowCreation=true' in nexus.properties

EXAMPLES:
    cd /some/workDir
    curl --compressed -O -L https://raw.githubusercontent.com/sonatype-nexus-community/nexus-monitoring/main/scripts/nrm3-undelete.sh
    export _ADMIN_USER="admin" _ADMIN_PWD="******" _NEXUS_URL="http://localhost:8081/" #_DRY_RUN="true" _IS_ORIENT="true"
    bash ./nrm3-undelete.sh -I      # only once
    bash ./nrm3-undelete.sh -s default -b <blobIDs>

To run concurrently:
    split -l 200 ./blobIDs.out blobIDs_
    bash ./nrm3-undelete.sh -I    # To install the groovy script
    for f in $(ls -1 ./blobIDs_a*); do
      bash ./nrm3-undelete.sh -b $f -s default &
    done; wait

OPTIONS:
    -I  Installing the groovy script for undeleting (only once per Nexus)
    -s  blob store name (if group blob store, use the group member name)
    -b  blob IDs (comma separated), or a file contains lines of blobIDs
EOF
}


### Global variables #################
: "${_ADMIN_USER:="admin"}"
: "${_ADMIN_PWD:="admin123"}"
: "${_NEXUS_URL:="http://localhost:8081/"}"
: "${_INSTALL:=""}"
: "${_TMP:="/tmp"}"
_SCRIPT_NAME="undeleteBlobIDs"
# Below is used in the POST json string
: "${_BLOB_STORE:=""}"
: "${_BLOB_IDS:=""}"    # comma separated blobIds
: "${_IS_ORIENT:="false"}"
: "${_DRY_RUN:="false"}"
: "${_DEBUG:="false"}"


### Functions ########################
function genScriptContent() {
    # RBSs.restoreBlobStrategyClassNames may need to updated per Nexus version.
    #   find . -type f -name '*RestoreBlobStrategy.java' | sed -E 's@^.+/src/main/java/(.+)\.java@"\1",@p' | sort | uniq | tr '/' '.'
    # How to generate the below (remove the beginning and ending double-quotes):
    #   python -c "import sys,json;print(json.dumps(open('nrm3-undelete_draft.groovy').read()))"
    cat <<'EOF'
import groovy.json.JsonSlurper\nimport org.sonatype.nexus.blobstore.restore.RestoreBlobStrategy\nimport org.sonatype.nexus.common.log.LogManager\nimport org.sonatype.nexus.common.log.LoggerLevel\nimport java.time.Instant\nimport groovy.json.JsonOutput\nimport org.sonatype.nexus.blobstore.api.Blob\nimport org.sonatype.nexus.blobstore.api.BlobAttributes\nimport org.sonatype.nexus.blobstore.api.BlobId\nimport org.sonatype.nexus.blobstore.api.BlobStore\nimport org.sonatype.nexus.blobstore.api.BlobStoreManager\nimport static org.sonatype.nexus.blobstore.api.BlobAttributesConstants.HEADER_PREFIX\nimport static org.sonatype.nexus.blobstore.api.BlobAttributesConstants.DELETED_DATETIME_ATTRIBUTE\nimport static org.sonatype.nexus.blobstore.api.BlobStore.REPO_NAME_HEADER\n\nclass RBSs {\n    static restoreBlobStrategyClassNames = [\n            \"com.sonatype.nexus.blobstore.restore.conan.ConanRestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.datastore.RubygemsRestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.helm.internal.HelmRestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.helm.internal.orient.OrientHelmRestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.internal.datastore.DockerRestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.internal.datastore.NpmRestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.internal.datastore.YumRestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.internal.orient.OrientDockerRestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.internal.orient.OrientNpmRestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.internal.orient.OrientYumRestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.nuget.internal.NugetRestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.nuget.internal.orient.OrientNugetRestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.orient.OrientRubygemsRestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.p2.internal.datastore.P2RestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.p2.internal.orient.OrientP2RestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.pypi.internal.PyPiRestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.pypi.internal.orient.OrientPyPiRestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.r.internal.datastore.RRestoreBlobStrategy\",\n            \"com.sonatype.nexus.blobstore.restore.r.internal.orient.OrientRRestoreBlobStrategy\",\n            \"org.sonatype.nexus.blobstore.restore.RestoreBlobStrategy\",\n            \"org.sonatype.nexus.blobstore.restore.apt.internal.AptRestoreBlobStrategy\",\n            \"org.sonatype.nexus.blobstore.restore.apt.internal.orient.OrientAptRestoreBlobStrategy\",\n            \"org.sonatype.nexus.blobstore.restore.datastore.BaseRestoreBlobStrategy\",\n            \"org.sonatype.nexus.blobstore.restore.maven.internal.MavenRestoreBlobStrategy\",\n            \"org.sonatype.nexus.blobstore.restore.maven.internal.orient.OrientMavenRestoreBlobStrategy\",\n            \"org.sonatype.nexus.blobstore.restore.orient.OrientBaseRestoreBlobStrategy\",\n            \"org.sonatype.nexus.blobstore.restore.raw.internal.RawRestoreBlobStrategy\",\n            \"org.sonatype.nexus.blobstore.restore.raw.internal.orient.OrientRawRestoreBlobStrategy\",\n            \"com.sonatype.nexus.repository.cargo.internal.restore.CargoRestoreBlobStrategy\",\n            \"com.sonatype.nexus.repository.composer.internal.restore.ComposerRestoreBlobStrategy\",\n            \"com.sonatype.nexus.repository.golang.datastore.internal.restore.GoRestoreBlobStrategy\",\n            \"com.sonatype.nexus.repository.huggingface.restore.HuggingFaceRestoreBlobStrategy\",\n    ]\n\n    static String lookupRestoreBlobStrategy(formatName, isOrient) {\n        def className = \"\"\n        if (formatName.equalsIgnoreCase(\"maven2\")) {\n            className = \"MavenRestoreBlobStrategy\"\n        } else if (formatName.equalsIgnoreCase(\"pypi\")) {\n            className = \"PyPiRestoreBlobStrategy\"\n        } else {\n            className = fmt(formatName) + \"RestoreBlobStrategy\"\n        }\n        if (isOrient) {\n            className = \"Orient${className}\"\n        }\n        // .every { it.contains(\"name\") }\n        return restoreBlobStrategyClassNames.find { it.endsWith(\".${className}\") }\n    }\n\n    static String fmt(word = \"\", camelling = true) {\n        if (word.isEmpty())\n            return word\n        if (camelling)\n            return String.valueOf(Character.toUpperCase(word.charAt(0))) + word.substring(1).toLowerCase()\n        return word.toLowerCase()\n    }\n}\n\ndef main(params) {\n    def blobIdPtn = '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})'\n    def lineCounter = 0\n    def restoredNum = 0\n    // Blobs deleted after this time will be ignored\n    def startedMsec = Instant.now().getEpochSecond() * 1000\n    BlobStore store = container.lookup(BlobStoreManager.class.name).get(params.blobStore)\n    if (!store) {\n        def logMsg = \"params.blobStore: ${params.blobStore} is invalid\"\n        log.error(logMsg)\n        return ['error': logMsg]\n    }\n    def blobIDs = (params.blobIDs as String).split(\",\")\n    if (!blobIDs || blobIDs.size() == 0) {\n        def logMsg = \"params.blobIDs is empty\"\n        log.error(logMsg)\n        return ['error': logMsg]\n    }\n    // 'params' should contain 'blobIDs', 'blobStore', 'isOrient', 'dryRun', and 'debug'\n    log.info(\"Checking ${blobIDs.length} blobIds with blobStore: ${params.blobStore}, isOrient: ${params.isOrient}, dryRun: ${params.dryRun}, debug: ${params.debug}\")\n    for (line in blobIDs) {\n        lineCounter++\n        try {\n            def match = line =~ blobIdPtn\n            if (!match) {\n                log.warn(\"#${lineCounter}: '${line}' does not contain blobId\")\n                continue\n            }\n            log.debug(\"match = ${match}\")\n            String blobId = match[0][1]\n            BlobId blobIdObj = new BlobId(blobId)\n            Blob blob = store.get(blobIdObj, true)\n            if (!blob) {\n                log.warn(\"No actual blob file for ${blobId}\")\n                continue\n            }\n            log.debug(\"Checking blobId:{}, headers:{}\", blobId, blob.getHeaders())\n            def blobAttributes = store.getBlobAttributes(blobIdObj) as BlobAttributes\n            if (!blobAttributes.load()) {\n                log.warn(\"Failed to load {}.\", blobAttributes.toString())\n                continue\n            }\n            def properties = blobAttributes.getProperties() as Properties\n            def repoName = properties.getProperty(HEADER_PREFIX + REPO_NAME_HEADER)\n            if (!repoName) {\n                log.warn(\"No repo-name found for ${blobId}\")\n                continue\n            }\n            def formatName = repository.repositoryManager[repoName].getFormat().getValue()\n            if (!formatName) {\n                log.warn(\"No format found for repo-name:${repoName}, ${blobId}\")\n                continue\n            }\n            def deletedDateTime = properties.getProperty(DELETED_DATETIME_ATTRIBUTE) as Long\n            if (startedMsec < deletedDateTime) {\n                log.warn(\"deletedDateTime:{} is greater than startedMsec:{}\", deletedDateTime, startedMsec)\n                continue\n            }\n            // Remove soft delete flag then restore blob\n            if (!params.dryRun) {\n                if (!blobAttributes.deleted) {\n                    log.debug(\"BlobId:{} is not deleted, so not un-deleting.\", blobId)\n                } else {\n                    log.info(\"Un-deleting blobId:{}\", blobId)\n                    // from org.sonatype.nexus.blobstore.BlobStoreSupport.undelete\n                    blobAttributes.setDeleted(false)\n                    //blobAttributes.setDeletedReason(null);    // Keeping this one so that can find the props edited by this task\n                    store.doUndelete(blobIdObj, blobAttributes)\n                    blobAttributes.store()\n                    log.debug(\"blobAttributes:{}\", blobAttributes)\n                }\n            }\n            log.info(\"Restoring blobId:{} (DryRun:{})\", blobId, params.dryRun)\n            def className = RBSs.lookupRestoreBlobStrategy(formatName, params.isOrient)\n            if (!className) {\n                // TODO: may not work with some minor formats such as bower, cocoapods, conda\n                log.warn(\"Using 'Base' as didn't find restore blob strategy className for format:{}, isOrient:{}\", formatName, params.isOrient)\n                className = RBSs.lookupRestoreBlobStrategy(\"base\", params.isOrient)\n            }\n            log.debug(\"className:{} for blobId:{}, format:{}, isOrient:{}\", className, blobId, formatName, params.isOrient)\n            def restoreBlobStrategy = container.lookup(className) as RestoreBlobStrategy\n            if (restoreBlobStrategy == null) {\n                log.error(\"Didn't find restore blob strategy for format:{}, isOrient:{}\", formatName, params.isOrient)\n                continue\n            }\n            restoreBlobStrategy.restore(properties, blob, store, params.dryRun)\n            restoredNum++\n        }\n        catch (Exception e) {\n            log.warn(\"Exception while un-deleting from line:{}\\n{}\", line, e.getMessage())\n            if (params.dryRun) {    // If dryRun stops at the exception\n                throw e\n            }\n        }\n        // NOTE: not doing blobStoreIntegrityCheck as wouldn't need for this script\n    }\n    log.info(\"Undeleted {}/{}\", restoredNum, blobIDs.size())\n    return ['checked': lineCounter, 'restored': restoredNum, 'dryRun': params.dryRun]\n}\n\nlog.info(\"Undeleting Blobs script started.\")\ndef logMgr = container.lookup(LogManager.class.name) as LogManager\ndef currentLevel = logMgr.getLoggerLevel(\"org.sonatype.nexus.internal.script.ScriptTask\")\ntry {\n    def params = (args) ? new JsonSlurper().parseText(args as String) : null\n    if (params.debug && (params.debug == \"true\" || params.debug == true)) {\n        logMgr.setLoggerLevel(\"org.sonatype.nexus.internal.script.ScriptTask\", LoggerLevel.DEBUG)\n        logMgr.setLoggerLevel(\"org.sonatype.nexus.script.plugin.internal.rest.ScriptResource\", LoggerLevel.DEBUG)\n    }\n    return JsonOutput.toJson(main(params))\n} finally {\n    logMgr.setLoggerLevel(\"org.sonatype.nexus.internal.script.ScriptTask\", currentLevel)\n    logMgr.setLoggerLevel(\"org.sonatype.nexus.script.plugin.internal.rest.ScriptResource\", currentLevel)\n    log.info(\"Undeleting Blobs script completed.\")\n}
EOF
}

main() {
    local _blobIDs="${1:-"${_BLOB_IDS}"}"
    local _blobStore="${2:-"${_BLOB_STORE}"}"
    local _install="${3:-"${_INSTALL}"}"

    if [[ "${_install}" =~ ^[yY] ]]; then
        echo "{\"name\":\"${_SCRIPT_NAME}\",\"content\":\"$(genScriptContent)\",\"type\":\"groovy\"}" > ${_TMP%/}/${_SCRIPT_NAME}.json || return $?
        # Delete if exists, and not showing error if not exists, but if install fails, it will show error and exit
        curl -s -u "${_ADMIN_USER}:${_ADMIN_PWD}" -H 'Content-Type: application/json' "${_NEXUS_URL%/}/service/rest/v1/script/${_SCRIPT_NAME}" -X DELETE
        curl -sSf -u "${_ADMIN_USER}:${_ADMIN_PWD}" -H 'Content-Type: application/json' "${_NEXUS_URL%/}/service/rest/v1/script" -d@${_TMP%/}/${_SCRIPT_NAME}.json || return $?
    fi
    if [ -z "${_blobIDs}" ]; then
        echo "No blobIDs (-b)" >&2
        return
    fi
    if [ -z "${_blobStore}" ]; then
        echo "No blobStore (-s)" >&2
        return
    fi
    if [ -s "${_blobIDs}" ]; then
        _blobIDs="$(cat "${_blobIDs}" | tr '\n' ',')"
    fi
    curl -sSf -u "${_ADMIN_USER}:${_ADMIN_PWD}" -H 'Content-Type: application/json' "${_NEXUS_URL%/}/service/rest/v1/script/${_SCRIPT_NAME}/run" -d'{"blobIDs":"'${_blobIDs%,}'","blobStore":"'${_blobStore}'","isOrient":'${_IS_ORIENT:-"false"}',"dryRun":'${_DRY_RUN:-"false"}',"debug":'${_DEBUG:-"false"}'}'
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
