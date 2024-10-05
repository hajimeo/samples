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
            "org.sonatype.nexus.blobstore.restore.raw.internal.orient.OrientRawRestoreBlobStrategy",]

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
    def blobIdPtn = '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})'
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
                if (!blobAttributes.deleted) {
                    log.debug("BlobId:{} is not deleted, so not un-deleting.", blobId)
                } else {
                    log.info("Un-deleting blobId:{}", blobId)
                    // from org.sonatype.nexus.blobstore.BlobStoreSupport.undelete
                    blobAttributes.setDeleted(false)
                    //blobAttributes.setDeletedReason(null);    // Keeping this one so that can find the props edited by this task
                    store.doUndelete(blobIdObj, blobAttributes)
                    blobAttributes.store()
                    log.debug("blobAttributes:{}", blobAttributes)
                }
            }
            log.info("Restoring blobId:{} (DryRun:{})", blobId, params.dryRun)
            def className = RBSs.lookupRestoreBlobStrategy(formatName, params.isOrient)
            if (!className) {
                // TODO: may not work with some minor formats such as bower, cocoapods, conda
                log.warn("Using 'Base' as didn't find restore blob strategy className for format:{}, isOrient:{}", formatName, params.isOrient)
                className = RBSs.lookupRestoreBlobStrategy("base", params.isOrient)
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