import groovy.json.JsonSlurper
import org.sonatype.nexus.common.log.LogManager
import org.sonatype.nexus.common.log.LoggerLevel
import groovy.json.JsonOutput
import org.sonatype.nexus.repository.manager.RepositoryManager
import org.sonatype.nexus.repository.content.fluent.FluentAsset

FORCE_BROWSE_DELETE = false

def main(params) {
    def blobIdPtnNew = '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})@([0-9]{4})-([0-9]{2})-([0-9]{2}).([0-9]{2}):([0-9]{2}).*'
    // 2025/09/08/06/07/aac3683b-111f-4d3d-96da-811e8cf23a0f
    def blobIdPtnNewPath = '/?([0-9]{4})/([0-9]{2})/([0-9]{2})/([0-9]{2})/([0-9]{2})/([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}).*'
    def blobIdPtn = '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}).*'
    def lineCounter = 0
    def deletedNum = 0

    def blobIDs = (params.blobIDs as String).split(",")
    if (!blobIDs || blobIDs.size() == 0) {
        def logMsg = "params.blobIDs is empty"
        log.error(logMsg)
        return ['error': logMsg]
    }
    // 'params' should contain 'blobIDs', 'blobStore', 'dryRun', and 'debug'
    log.info("Checking ${blobIDs.length} blobIds with blobStore: ${params.blobStore},  dryRun: ${params.dryRun}, debug: ${params.debug}")

    def repositoryManager = container.lookup(RepositoryManager)

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
            def blobIdStr = blobId
            if (blobCreatedRef) {
                // Actually no need to append createdRef to blobIdStr for searching but as deleting, to be safe
                blobIdStr = blobId + "@" + blobCreatedRef.toString()
            }
            log.debug("Deleting blobId:{}", blobIdStr)

            def isDeleted = false
            repositoryManager.browse().each { repo ->
                def repoBlobStore = repo.getConfiguration().attributes.storage.blobStoreName
                if (params.blobStore && params.blobStore.trim().length() > 0 && repoBlobStore != params.blobStore) {
                    log.debug("Skipping repository {} as blobStore {} does not match {}", repo.name, repoBlobStore, params.blobStore)
                    return
                }

                // Can not use findByBlobRef() as can't guess the blobname before @ to create blobRef.
                def facet = repo.facet(org.sonatype.nexus.repository.content.facet.ContentFacet) as org.sonatype.nexus.repository.content.facet.ContentFacetSupport
                facet.stores().assetStore.browseAssets(facet.contentRepositoryId(), null, null, "blob_ref like '%" + blobIdStr + "%'", null, 1).each {
                    def fa = (FluentAsset) (it instanceof FluentAsset ? (FluentAsset) it : new org.sonatype.nexus.repository.content.fluent.internal.FluentAssetImpl(facet, it))
                    if (!params.dryRun) {
                        if (FORCE_BROWSE_DELETE) { // Always False for now (Not using currently)
                            // FluentAsset.delete() generates the AssetDeletedEvent but the Browse is not cleaned with 3.82
                            def internalAssetId = org.sonatype.nexus.repository.content.store.InternalIds.internalAssetId(fa);
                            repo.optionalFacet(org.sonatype.nexus.repository.content.browse.BrowseFacet.class).ifPresent({ fc ->
                                log.info('Deleting browse node: {} internal asset id: {}', fa.path(), internalAssetId)
                                fc.deleteByAssetIdAndPath(internalAssetId, fa.path())
                            });
                        }
                        // repo.facet(org.sonatype.nexus.repository.content.maintenance.ContentMaintenanceFacet).deleteAsset(it)
                        fa.delete()
                    }
                    log.info("Deleted asset.path:{}, blobId:{} from repository {} (DryRun:{})", fa.path(), blobIdStr, repo.name, params.dryRun)
                    deletedNum++
                    isDeleted = true
                }
            }
            if (!isDeleted) {
                log.warn("No asset in DB with blobId: {} from any repository", blobIdStr)
            }
        }
        catch (Exception e) {
            log.warn("Exception while deleting blob from line:{} - {}", line, e.getMessage())
            if (params.dryRun) {    // If dryRun stops at the exception
                throw e
            }
        }
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
