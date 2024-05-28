#!/usr/bin/env bash
usage() {
    cat <<EOF
bash <(curl -sfL https://raw.githubusercontent.com/sonatype-nexus-community/nexus-monitoring/main/scripts/nrm3-undelete.sh --compressed)

PURPOSE:
    Undelete one or multiple blob IDs (call this script concurrently for many blob IDs)

REQUIREMENTS:
    curl
    python to handle (escape) JSON string.

EXAMPLES:
    cd /some/workDir
    curl --compressed -O -L https://raw.githubusercontent.com/sonatype-nexus-community/nexus-monitoring/main/scripts/nrm3-undelete.sh
    export _ADMIN_USER="admin" _ADMIN_PWD="admin123" _NEXUS_URL="http://localhost:8081/"
    bash ./nrm3-undelete.sh -I                      # To install the necessary script into first time
    bash ./nrm3-undelete.sh -s default -b <blobIDs>

OPTIONS:
    -I  Installing the groovy script for undeleting
    -b  blob IDs (comma separated), or a file contains lines of blobIDs
    -s  blob store name
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
function f_register_script() {
    local _script_file="$1"
    local _script_name="$2"
    [ -s "${_script_file%/}" ] || return 1
    [ -z "${_script_name}" ] && _script_name="$(basename ${_script_file} .groovy)"
    echo "{\"name\":\"${_script_name}\",\"content\":$(python -c "import sys,json;print(json.dumps(open('${_script_file}').read()))"),\"type\":\"groovy\"}" > ${_TMP%/}/${_script_name}_$$.json
    # Delete if exists
    curl -s -u "${_ADMIN_USER}:${_ADMIN_PWD}" -H 'Content-Type: application/json' "${_NEXUS_URL%/}/service/rest/v1/script/${_script_name}" -X DELETE
    curl -sSf -u "${_ADMIN_USER}:${_ADMIN_PWD}" -H 'Content-Type: application/json' "${_NEXUS_URL%/}/service/rest/v1/script" -d@${_TMP%/}/${_script_name}_$$.json
}

function genScript() {
    local _saveTo="${1:-"${_TMP%/}/${_SCRIPT_NAME}.groovy"}"
    # TODO: replace below
    cat <<'EOF' >"${_saveTo}"
import groovy.json.JsonSlurper
import org.sonatype.nexus.blobstore.restore.RestoreBlobStrategy
import org.sonatype.nexus.common.log.LogManager
import org.sonatype.nexus.common.log.LoggerLevel
import java.time.Instant
import groovy.json.JsonOutput
import org.sonatype.nexus.blobstore.api.Blob
import org.sonatype.nexus.blobstore.api.BlobAttributes
import org.sonatype.nexus.blobstore.api.BlobId
import org.sonatype.nexus.blobstore.api.BlobStore
import org.sonatype.nexus.blobstore.api.BlobStoreManager
import static org.sonatype.nexus.blobstore.api.BlobAttributesConstants.HEADER_PREFIX
import static org.sonatype.nexus.blobstore.api.BlobAttributesConstants.DELETED_DATETIME_ATTRIBUTE
import static org.sonatype.nexus.blobstore.api.BlobStore.REPO_NAME_HEADER

class RBSs {
    /**
     * RBSs.restoreBlobStrategyClassNames need to be checked/changed if older Nexus version is used.
     *  # After checking out customer's Nexus version:
     *  find . -type f -name '*RestoreBlobStrategy.java' | sed -E 's@^.+/src/main/java/(.+)\.java@"\1",@p' | sort | uniq | tr '/' '.'
     */
    static restoreBlobStrategyClassNames = ["com.sonatype.nexus.blobstore.restore.conan.ConanRestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.datastore.RubygemsRestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.helm.internal.HelmRestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.helm.internal.orient.OrientHelmRestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.internal.datastore.DockerRestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.internal.datastore.NpmRestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.internal.datastore.YumRestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.internal.orient.OrientDockerRestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.internal.orient.OrientNpmRestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.internal.orient.OrientYumRestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.nuget.internal.NugetRestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.nuget.internal.orient.OrientNugetRestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.orient.OrientRubygemsRestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.p2.internal.datastore.P2RestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.p2.internal.orient.OrientP2RestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.pypi.internal.PyPiRestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.pypi.internal.orient.OrientPyPiRestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.r.internal.datastore.RRestoreBlobStrategy",
                                            "com.sonatype.nexus.blobstore.restore.r.internal.orient.OrientRRestoreBlobStrategy",
                                            "org.sonatype.nexus.blobstore.restore.RestoreBlobStrategy",
                                            "org.sonatype.nexus.blobstore.restore.apt.internal.AptRestoreBlobStrategy",
                                            "org.sonatype.nexus.blobstore.restore.apt.internal.orient.OrientAptRestoreBlobStrategy",
                                            "org.sonatype.nexus.blobstore.restore.datastore.BaseRestoreBlobStrategy",
                                            "org.sonatype.nexus.blobstore.restore.maven.internal.MavenRestoreBlobStrategy",
                                            "org.sonatype.nexus.blobstore.restore.maven.internal.orient.OrientMavenRestoreBlobStrategy",
                                            "org.sonatype.nexus.blobstore.restore.orient.OrientBaseRestoreBlobStrategy",
                                            "org.sonatype.nexus.blobstore.restore.raw.internal.RawRestoreBlobStrategy",
                                            "org.sonatype.nexus.blobstore.restore.raw.internal.orient.OrientRawRestoreBlobStrategy",]

    static String lookupRestoreBlobStrategy(formatName, isOrient) {
        def className = fmt(formatName) + "RestoreBlobStrategy"
        if (isOrient) {
            className = "Orient${className}"
        }
        // .every { it.contains("name") }
        return restoreBlobStrategyClassNames.find { it.endsWith(".${className}") }
    }

    static String fmt(word = "", camelling = true) {
        if (word.isEmpty())
            return word
        if (camelling)
            return String.valueOf(Character.toUpperCase(word.charAt(0))) + word.substring(1).toLowerCase()
        return word.toLowerCase()
    }
}

def main(params) {
    // 'params' should contain 'blobIDs', 'blobStore', 'isOrient', 'dryRun'
    log.debug("params = ${params}")
    def blobIdPtn = '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})'
    def lineCounter = 0
    def restoredNum = 0
    // Blobs deleted after this time will be ignored
    def startedMsec = Instant.now().getEpochSecond() * 1000

    BlobStore store = container.lookup(BlobStoreManager.class.name).get(params.blobStore)
    if (!store) {
        def logMsg = "blobStore from params: ${params} is invalid"
        log.error(logMsg)
        return ['error': logMsg]
    }

    def blobIDs = (params.blobIDs as String).split(",")
    for (line in blobIDs) {
        lineCounter++
        try {
            def match = line =~ blobIdPtn
            if (!match) {
                log.warn("#${lineCounter}: '${line}' does not contain blobId")
                continue
            }
            log.debug("match = ${match}")
            String blobId = match[0][1]
            BlobId blobIdObj = new BlobId(blobId)
            Blob blob = store.get(blobIdObj, true)
            if (!blob) {
                log.warn("No actual blob file for ${blobId}")
                continue
            }
            log.debug("Checking blobId:{}, headers:{}", blobId, blob.getHeaders())
            def blobAttributes = store.getBlobAttributes(blobIdObj) as BlobAttributes
            if (!blobAttributes.load()) {
                log.warn("Failed to load {}.", blobAttributes.toString())
                continue
            }
            def properties = blobAttributes.getProperties() as Properties
            def repoName = properties.getProperty(HEADER_PREFIX + REPO_NAME_HEADER)
            if (!repoName) {
                log.warn("No repo-name found for ${blobId}")
                continue
            }
            def formatName = repository.repositoryManager[repoName].getFormat().getValue()
            if (!formatName) {
                log.warn("No format found for repo-name:${repoName}, ${blobId}")
                continue
            }
            def deletedDateTime = properties.getProperty(DELETED_DATETIME_ATTRIBUTE) as Long
            if (startedMsec < deletedDateTime) {
                log.warn("deletedDateTime:{} is greater than startedMsec:{}", deletedDateTime, startedMsec)
                continue
            }

            // Remove soft delete flag then restore blob
            if (!params.dryRun) {
                log.info("Un-deleting blobId:{}", blobId)
                // from org.sonatype.nexus.blobstore.BlobStoreSupport.undelete
                blobAttributes.setDeleted(false)
                //blobAttributes.setDeletedReason(null);    // Keeping this one so that can find the props edited by this task
                store.doUndelete(blobIdObj, blobAttributes)
                blobAttributes.store()
                log.debug("blobAttributes:{}", blobAttributes)
            }
            log.info("Restoring blobId:{} (DryRun:{})", blobId, params.dryRun)
            def className = RBSs.lookupRestoreBlobStrategy(formatName, params.isOrient)
            if (className == null) {
                log.error("Didn't find restore blob strategy className for format:{}, isOrient:{}", formatName, params.isOrient)
                continue
            }
            log.debug("className:{} for blobId:{}, format:{}, isOrient:{}", className, blobId, formatName, params.isOrient)
            def restoreBlobStrategy = container.lookup(className) as RestoreBlobStrategy
            if (restoreBlobStrategy == null) {
                log.error("Didn't find restore blob strategy for format:{}, isOrient:{}", formatName, params.isOrient)
                continue
            }
            restoreBlobStrategy.restore(properties, blob, store, params.dryRun)
            restoredNum++
        }
        catch (Exception e) {
            log.warn("Exception while un-deleting from line:{}\n{}", line, e.getMessage())
            if (params.dryRun) {    // If dryRun stops at the exception
                throw e
            }
        }
        // NOTE: not doing blobStoreIntegrityCheck as wouldn't need for this script
    }
    log.info("Undeleted {}/{}", restoredNum, blobIDs.size())
    return ['checked': lineCounter, 'restored': restoredNum, 'dryRun': params.dryRun]
}


log.info("Undeleting Blobs script started.")
def logMgr = container.lookup(LogManager.class.name) as LogManager
def currentLevel = logMgr.getLoggerLevel("org.sonatype.nexus.internal.script.ScriptTask")
try {
    def params = (args) ? new JsonSlurper().parseText(args as String) : null
    if (params.debug && (params.debug == "true" || params.debug == true)) {
        logMgr.setLoggerLevel("org.sonatype.nexus.internal.script.ScriptTask", LoggerLevel.DEBUG)
        logMgr.setLoggerLevel("org.sonatype.nexus.script.plugin.internal.rest.ScriptResource", LoggerLevel.DEBUG)
    }
    return JsonOutput.toJson(main(params))
} finally {
    logMgr.setLoggerLevel("org.sonatype.nexus.internal.script.ScriptTask", currentLevel)
    logMgr.setLoggerLevel("org.sonatype.nexus.script.plugin.internal.rest.ScriptResource", currentLevel)
    log.info("Undeleting Blobs script completed.")
}
EOF
}


main() {
    local _blobIDs="${1:-"${_BLOB_IDS}"}"
    local _blobStore="${2:-"${_BLOB_STORE}"}"
    local _install="${3:-"${_INSTALL}"}"

    if [[ "${_install}" =~ ^[yY] ]]; then
        genScript "${_TMP%/}/${_SCRIPT_NAME}.groovy"
        f_register_script "${_TMP%/}/${_SCRIPT_NAME}.groovy"
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
