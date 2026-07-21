import groovy.json.JsonSlurper
import groovy.json.JsonOutput
import org.sonatype.nexus.common.log.LogManager
import org.sonatype.nexus.common.log.LoggerLevel


def processRepository(final repository, final String filterCondition, final batchSize, final dryRun) {
    try {
        def fluentComponents = repository.facet(org.sonatype.nexus.repository.content.facet.ContentFacet.class).components();
        def filteredQuery = fluentComponents.byFilter(filterCondition, java.util.Collections.emptyMap());

        return reindexFilteredComponents(repository, filteredQuery, batchSize, dryRun);
    }
    catch (Exception e) {
        log.error("Error processing repository {}: {}", repository.getName(), e.getMessage(), e);
        return 0;
    }
}

def reindexFilteredComponents(
        final repository,
        final filteredQuery,
        final batchSize,
        final dryRun) {
    long processed = 0;
    Collection<org.sonatype.nexus.repository.content.fluent.FluentComponent> components = filteredQuery.browse(batchSize, null);
    if (components.isEmpty()) {
        log.info("No components matching filter in repository {}", repository.getName());
        return 0;
    }
    def sqlSearchIndexService = container.lookup(org.sonatype.nexus.repository.search.sql.index.SqlSearchIndexService.class.name);
    while (!components.isEmpty()) {
        if (dryRun) {
            components.each { component ->
                log.info("Dry run: would re-index component: {} in repository: {}", component, repository.getName());
            }
        } else {
            sqlSearchIndexService.indexBatch(components, repository);
        }
        processed += components.size();
        log.info("Re-indexed {} components in {} (dryRun: {})", processed, repository.getName(), dryRun);
        components = filteredQuery.browse(batchSize, components.nextContinuationToken());
    }

    log.info("Completed re-indexing {} components for repository {}", processed, repository.getName());
    return processed;
}

def main(params) {
    // params = {"repo_name":"maven-releases","component":"com.group","name":"artifact","version":"0.0.1","batch_size":100,"dryRun":false,"debug":false}
    if (params.repo_name == null || params.repo_name.isEmpty()) {
        log.warn("Repository name is not provided. Please provide a valid repository name.")
        return
    }
    // component is also mandatory for now (if no component, not much different form normal task)
    if (params.component == null || params.component.isEmpty()) {
        log.warn("Component/Group/Namespace is not provided. Please provide a valid component.")
        return
    }
    def processed = 0L
    def batchSize = (params.batch_size != null && params.batch_size > 0) ? params.batch_size : 100
    def compOperator = (params.component?.contains('%')) ? 'like' : '='
    def condition = "namespace ${compOperator} '${params.component}'"
    if (params.name != null && !params.name.isEmpty()) {
        def nameOperator = (params.name?.contains('%')) ? 'like' : '='
        condition += " and name ${nameOperator} '${params.name}'"
    }
    if (params.version != null && !params.version.isEmpty()) {
        def versionOperator = (params.version?.contains('%')) ? 'like' : '='
        condition += " and version ${versionOperator} '${params.version}'"
    }
    try {
        repository.repositoryManager.browse().each { repo ->
            if (repo.name == params.repo_name) {
                log.info('Checking repository: {}, type: {}, format: {}', repo.name, repo.type.value, repo.format.value)
                processed = processRepository(repo, condition, batchSize, params.dryRun)
            }
        }
    }
    catch (Exception e) {
        log.warn('Exception details: {}', e.getMessage())
        log.debug("{}", e.printStackTrace())
        if (params.dryRun) {    // If dryRun stops at the exception
            throw e
        }
    }
    return [processed: processed, condition: condition, batchSize: batchSize, dryRun: params.dryRun, debug: params.debug]
}

log.info("Rebuilding specific search index script started.")
def logMgr = container.lookup(LogManager.class.name) as LogManager
def currentLevel = logMgr.getLoggerLevel("org.sonatype.nexus.internal.script.ScriptTask")
try {
    def params = (args) ? new JsonSlurper().parseText(args as String) : null
    if (params.debug && (params.debug == "true" || params.debug == true)) {
        logMgr.setLoggerLevel("org.sonatype.nexus.internal.script.ScriptTask", LoggerLevel.DEBUG)
        logMgr.setLoggerLevel("org.sonatype.nexus.script.plugin.internal.rest.ScriptResource", LoggerLevel.DEBUG)
        //logMgr.setLoggerLevel("org.sonatype.nexus.content.maven.store.Maven2ComponentDAO.browseComponents", LoggerLevel.DEBUG)
        logMgr.setLoggerLevel("org.sonatype.nexus.repository.search.sql.store.SearchTableDAO.saveBatch", LoggerLevel.DEBUG)
    }
    return JsonOutput.toJson(main(params))
} finally {
    logMgr.setLoggerLevel("org.sonatype.nexus.internal.script.ScriptTask", currentLevel)
    logMgr.setLoggerLevel("org.sonatype.nexus.script.plugin.internal.rest.ScriptResource", currentLevel)
    logMgr.setLoggerLevel("org.sonatype.nexus.repository.search.sql.store.SearchTableDAO.saveBatch", currentLevel)
    log.info("Rebuilding specific search index script completed.")
}
