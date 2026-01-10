import groovy.json.JsonSlurper
import org.sonatype.nexus.common.log.LogManager
import org.sonatype.nexus.common.log.LoggerLevel
import groovy.json.JsonOutput

def main(params) {
    def blobIdPtnNew = '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})@([0-9]{4})-([0-9]{2})-([0-9]{2}).([0-9]{2}):([0-9]{2}).*'
    // 2025/09/08/06/07/aac3683b-111f-4d3d-96da-811e8cf23a0f
    def blobIdPtnNewPath = '/?([0-9]{4})/([0-9]{2})/([0-9]{2})/([0-9]{2})/([0-9]{2})/([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}).*'
    def blobIdPtn = '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}).*'
    def lineCounter = 0
    def deletedNum = 0
    def repositoryManager = container.lookup(org.sonatype.nexus.repository.manager.RepositoryManager)
    def store = container.lookup(org.sonatype.nexus.blobstore.api.BlobStoreManager.class.name).get(params.blobStore)
    if (!store) {
        def logMsg = "params.blobStore: ${params.blobStore} is invalid"
        if (params.noBsChk) {
            log.warn(logMsg + ", but continuing as noBsChk is true")
        } else {
            log.error(logMsg)
            return ['error': logMsg]
        }
    }
    def blobIDs = (params.blobIDs as String).split(",")
    if (!blobIDs || blobIDs.size() == 0) {
        def logMsg = "params.blobIDs is empty"
        log.error(logMsg)
        return ['error': logMsg]
    }
    // 'params' should contain 'blobIDs', 'blobStore', 'noBsChk', 'dryRun', and 'debug'
    log.info("Checking ${blobIDs.length} blobIds with blobStore: ${params.blobStore}, noBsChk: ${params.noBsChk}, dryRun: ${params.dryRun}, debug: ${params.debug}")

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
            def blobRefStr = params.blobStore + "@" + blobId
            if (blobCreatedRef) {
                blobRefStr = blobRefStr + "@" + blobCreatedRef.toString()
            }
            log.debug("Deleting blobRef:{}", blobRefStr)

            def isDeleted = false
            repositoryManager.browse().each {
                def repoBlobStore = it.getConfiguration().attributes.storage.blobStoreName
                if (!params.noBsChk && params.blobStore && params.blobStore.trim().length() > 0 && repoBlobStore != params.blobStore) {
                    log.debug("Skipping repository {} as blobStore {} does not match {}", it.name, repoBlobStore, params.blobStore)
                    return
                }
                def repositoryId = org.sonatype.nexus.repository.content.store.InternalIds.contentRepositoryId(it).get()
                def content = it.facet(org.sonatype.nexus.repository.content.facet.ContentFacet)
                def maybeAsset = ((org.sonatype.nexus.repository.content.facet.ContentFacetSupport) content).stores().assetStore.findByBlobRef(repositoryId, org.sonatype.nexus.blobstore.api.BlobRef.parse(blobRefStr))
                if (maybeAsset.isPresent()) {
                    def asset = maybeAsset.get()
                    if (!params.dryRun) {
                        it.facet(org.sonatype.nexus.repository.content.maintenance.ContentMaintenanceFacet).deleteAsset(asset)
                    }
                    log.info("Deleted path:{}, blobRef:{} from repository {} (DryRun:{})", asset.path(), blobRefStr, it.name, params.dryRun)
                    deletedNum++
                    isDeleted = true
                    return  // break out of repo loop for performance
                }
            }
            if (!isDeleted) {
                // Already deleted?
                log.warn("No asset in DB with blobRef: {} from any repository", blobRefStr)
            }
        }
        catch (Exception e) {
            log.warn("Exception while deleting blob from line:{} - {}", line, e.getMessage())
            if (params.dryRun) {    // If dryRun stops at the exception
                throw e
            }
        }
        // NOTE: not doing blobStoreIntegrityCheck as wouldn't need for this script
    }
    log.info("Deleted {}/{}", deletedNum, blobIDs.size())
    return ['checked': lineCounter, 'deleted': deletedNum, 'dryRun': params.dryRun]
}

log.info("Delete by Blob IDs script started.")
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
    log.info("Delete by Blob IDs script completed.")
}
