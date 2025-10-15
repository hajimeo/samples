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
    static restoreBlobStrategyClassNames = [
            "com.sonatype.nexus.blobstore.restore.conan.ConanRestoreBlobStrategy",
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
            "org.sonatype.nexus.blobstore.restore.raw.internal.orient.OrientRawRestoreBlobStrategy",
            "com.sonatype.nexus.repository.cargo.internal.restore.CargoRestoreBlobStrategy",
            "com.sonatype.nexus.repository.composer.internal.restore.ComposerRestoreBlobStrategy",
            "com.sonatype.nexus.repository.golang.datastore.internal.restore.GoRestoreBlobStrategy",
            "com.sonatype.nexus.repository.huggingface.restore.HuggingFaceRestoreBlobStrategy",
    ]

    static String lookupRestoreBlobStrategy(formatName, isOrient) {
        def className = ""
        if (formatName.equalsIgnoreCase("maven2")) {
            className = "MavenRestoreBlobStrategy"
        } else if (formatName.equalsIgnoreCase("pypi")) {
            className = "PyPiRestoreBlobStrategy"
        } else {
            className = fmt(formatName) + "RestoreBlobStrategy"
        }
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
    def blobIdPtnNew = '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})@([0-9]{4})-([0-9]{2})-([0-9]{2}).([0-9]{2}):([0-9]{2}).*'
    // 2025/09/08/06/07/aac3683b-111f-4d3d-96da-811e8cf23a0f
    def blobIdPtnNewPath = '/?([0-9]{4})/([0-9]{2})/([0-9]{2})/([0-9]{2})/([0-9]{2})/([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}).*'
    def blobIdPtn = '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}).*'
    def lineCounter = 0
    def restoredNum = 0
    // Blobs deleted after this time will be ignored
    def startedMsec = Instant.now().getEpochSecond() * 1000
    BlobStore store = container.lookup(BlobStoreManager.class.name).get(params.blobStore)
    if (!store) {
        def logMsg = "params.blobStore: ${params.blobStore} is invalid"
        log.error(logMsg)
        return ['error': logMsg]
    }
    def blobIDs = (params.blobIDs as String).split(",")
    if (!blobIDs || blobIDs.size() == 0) {
        def logMsg = "params.blobIDs is empty"
        log.error(logMsg)
        return ['error': logMsg]
    }
    // 'params' should contain 'blobIDs', 'blobStore', 'isOrient', 'dryRun', and 'debug'
    log.info("Checking ${blobIDs.length} blobIds with blobStore: ${params.blobStore}, isOrient: ${params.isOrient}, dryRun: ${params.dryRun}, debug: ${params.debug}")
    for (line in blobIDs) {
        log.debug("line = ${line}")
        lineCounter++
        try {
            def blobCreatedRef = null
            def blobId = ""
            def match = line =~ blobIdPtnNewPath
            if (match) {
                blobId = match[0][6] as String
                def year = match[0][1] as Integer
                def month = match[0][2] as Integer
                def day = match[0][3] as Integer
                def hour = match[0][4] as Integer
                def minute = match[0][5] as Integer
                blobCreatedRef = java.time.OffsetDateTime.of(year, month, day, hour, minute, 0, 0, java.time.ZoneOffset.UTC)
            } else {
                match = line =~ blobIdPtnNew
                if (match) {
                    blobId = match[0][1] as String
                    def year = match[0][2] as Integer
                    def month = match[0][3] as Integer
                    def day = match[0][4] as Integer
                    def hour = match[0][5] as Integer
                    def minute = match[0][6] as Integer
                    blobCreatedRef = java.time.OffsetDateTime.of(year, month, day, hour, minute, 0, 0, java.time.ZoneOffset.UTC)
                } else {
                    match = line =~ blobIdPtn
                    if (match) {
                        blobId = match[0][1] as String
                    } else {
                        log.warn("#${lineCounter}: '${line}' does not contain blobId")
                        continue
                    }
                }
            }
            log.debug("match[0] = ${match[0]}")
            def blobIdStr = blobId + "@" + blobCreatedRef.toString()
            def blobIdObj = new BlobId(blobId, blobCreatedRef)
            Blob blob = store.get(blobIdObj, true)
            if (!blob) {
                log.warn("No actual blob file for ${blobIdStr}")
                continue
            }
            log.debug("Processing blobId:{}, headers:{}", blobIdStr, blob.getHeaders())
            def blobAttributes = store.getBlobAttributes(blobIdObj) as BlobAttributes
            if ((!blobAttributes) || (!blobAttributes.load())) {
                log.warn("Failed to load {} {}.", blobIdStr, blobAttributes.toString())
                continue
            }
            def properties = blobAttributes.getProperties() as Properties
            def repoName = properties.getProperty(HEADER_PREFIX + REPO_NAME_HEADER)
            if (!repoName) {
                log.warn("No repo-name found for ${blobIdStr}")
                continue
            }
            def formatName = repository.repositoryManager[repoName].getFormat().getValue()
            if (!formatName) {
                log.warn("No format found for repo-name:${repoName}, ${blobIdStr}")
                continue
            }
            def deletedDateTime = properties.getProperty(DELETED_DATETIME_ATTRIBUTE) as Long
            if (startedMsec < deletedDateTime) {
                log.warn("deletedDateTime:{} is greater than startedMsec:{}", deletedDateTime, startedMsec)
                continue
            }
            // Remove soft delete flag then restore blob
            if (!blobAttributes.deleted) {
                log.info("BlobId:{} does not have 'deleted=true'.", blobIdStr)
            } else {
                if (!params.dryRun) {
                    // From org.sonatype.nexus.blobstore.BlobStoreSupport.undelete
                    blobAttributes.setDeleted(false)
                    //blobAttributes.setDeletedReason(null)    // Keeping this one so that can find the props edited by this task
                    blobAttributes.setSoftDeletedLocation(null)
                    // For special blob stores such as S3.
                    store.doUndelete(blobIdObj, blobAttributes)
                    blobAttributes.store()
                }
                log.info("Undeleted blobId:{} (DryRun:{})\n{}", blobIdStr, params.dryRun, blobAttributes)
            }

            // Based on org.sonatype.nexus.blobstore.BlobStoreSupport#undelete and from 3.83.2
            def softDeletedLocation = blobAttributes.getSoftDeletedLocation();
            if (softDeletedLocation.isPresent()) {
                if (!params.dryRun) {
                    store.deleteCopiedAttributes(blobIdObj, softDeletedLocation.get())
                }
                log.info("Deleted softDeletedLocation:{} (DryRun:{})", softDeletedLocation.get(), params.dryRun)
            }

            def className = RBSs.lookupRestoreBlobStrategy(formatName, params.isOrient)
            if (!className) {
                // TODO: may not work with some minor formats such as bower, cocoapods, conda
                log.warn("Using 'Base' as didn't find restore blob strategy className for format:{}, isOrient:{}", formatName, params.isOrient)
                className = RBSs.lookupRestoreBlobStrategy("base", params.isOrient)
            }
            log.debug("Restoring with className:{} for blobId:{}, format:{}, isOrient:{}", className, blobIdStr, formatName, params.isOrient)
            def restoreBlobStrategy = container.lookup(className) as RestoreBlobStrategy
            if (restoreBlobStrategy == null) {
                log.error("Didn't find restore blob strategy for format:{}, isOrient:{}", formatName, params.isOrient)
                continue
            }
            restoreBlobStrategy.restore(properties, blob, store, params.dryRun)
            log.info("Restored blobId:{} (DryRun:{})", blobIdStr, params.dryRun)
            restoredNum++
        }
        catch (Exception e) {
            log.warn("Exception while undeleting and restoring from line:{} - {}", line, e.getMessage())
            if (params.dryRun) {    // If dryRun stops at the exception
                throw e
            }
        }
        // NOTE: not doing blobStoreIntegrityCheck as wouldn't need for this script
    }
    log.info("Restored {}/{}", restoredNum, blobIDs.size())
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
