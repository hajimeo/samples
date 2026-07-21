#!/usr/bin/env bash
usage() {
    cat << 'EOF'
PURPOSE:
    Rebuild specific components' search indexes.

NOTE:
    This script is not guaranteed to work for all Nexus versions. Please test this script on a test system first.

REQUIREMENTS:
    'curl' for uploading the script and initiating the script
    'nexus.scripts.allowCreation=true' in nexus.properties

EXAMPLES:
    cd /some/workDir
    curl --compressed -o nrm3-undelete.sh -L https://raw.githubusercontent.com/sonatype/nexus-monitoring/main/scripts/nrm3-rebuild-search.sh
    export _ADMIN_USER="admin" _ADMIN_PWD="******" _NEXUS_URL="http://localhost:8081/" #_DRY_RUN="true" _DEBUG="true"
    bash ./nrm3-rebuild-search.sh -I      # only once to register the script
    bash ./nrm3-rebuild-search.sh -r {repo-name} [-c {component-name}] [-n {artifact-name}] [-v {artifact-version}] [-b {batch-size}]

OPTIONS:
    -I  Installing the groovy script (only once per Nexus)
    -r  repository name
    -c  component/group/namespace name
    -n  artifact name
    -v  artifact version
    -b  batch size (default 100)
EOF
}


### Global variables #################
: "${_ADMIN_USER:="admin"}"
: "${_ADMIN_PWD:="admin123"}"
: "${_NEXUS_URL:="http://localhost:8081/"}"
: "${_INSTALL:=""}"
: "${_TMP:="/tmp"}"
_SCRIPT_NAME="rebuildSpecificSearch"
# Below is used in the POST json string
: "${_REPO_NAME:=""}"
: "${_COMPONENT:=""}"
: "${_NAME:=""}"
: "${_VERSION:=""}"
: "${_BATCH_SIZE:="100"}"
: "${_DRY_RUN:="false"}"
: "${_DEBUG:="false"}"


### Functions ########################
function genScriptContent() {
    # How to generate the below (NOTE: remove the beginning and ending double-quotes):
    #   python3 -c "import sys,json;print(json.dumps(open('nrm3-rebuild-search_draft.groovy').read()))"
    cat <<'EOF'
import groovy.json.JsonSlurper\nimport groovy.json.JsonOutput\nimport org.sonatype.nexus.common.log.LogManager\nimport org.sonatype.nexus.common.log.LoggerLevel\n\n\ndef processRepository(final repository, final String filterCondition, final batchSize, final dryRun) {\n    try {\n        def fluentComponents = repository.facet(org.sonatype.nexus.repository.content.facet.ContentFacet.class).components();\n        def filteredQuery = fluentComponents.byFilter(filterCondition, java.util.Collections.emptyMap());\n\n        return reindexFilteredComponents(repository, filteredQuery, batchSize, dryRun);\n    }\n    catch (Exception e) {\n        log.error(\"Error processing repository {}: {}\", repository.getName(), e.getMessage(), e);\n        return 0;\n    }\n}\n\ndef reindexFilteredComponents(\n        final repository,\n        final filteredQuery,\n        final batchSize,\n        final dryRun) {\n    long processed = 0;\n    Collection<org.sonatype.nexus.repository.content.fluent.FluentComponent> components = filteredQuery.browse(batchSize, null);\n    if (components.isEmpty()) {\n        log.info(\"No components matching filter in repository {}\", repository.getName());\n        return 0;\n    }\n    def sqlSearchIndexService = container.lookup(org.sonatype.nexus.repository.search.sql.index.SqlSearchIndexService.class.name);\n    while (!components.isEmpty()) {\n        if (dryRun) {\n            components.each { component ->\n                log.info(\"Dry run: would re-index component: {} in repository: {}\", component, repository.getName());\n            }\n        } else {\n            sqlSearchIndexService.indexBatch(components, repository);\n        }\n        processed += components.size();\n        log.info(\"Re-indexed {} components in {} (dryRun: {})\", processed, repository.getName(), dryRun);\n        components = filteredQuery.browse(batchSize, components.nextContinuationToken());\n    }\n\n    log.info(\"Completed re-indexing {} components for repository {}\", processed, repository.getName());\n    return processed;\n}\n\ndef main(params) {\n    // params = {\"repo_name\":\"maven-releases\",\"component\":\"com.group\",\"name\":\"artifact\",\"version\":\"0.0.1\",\"batch_size\":100,\"dryRun\":false,\"debug\":false}\n    if (params.repo_name == null || params.repo_name.isEmpty()) {\n        log.warn(\"Repository name is not provided. Please provide a valid repository name.\")\n        return\n    }\n    // component is also mandatory for now (if no component, not much different form normal task)\n    if (params.component == null || params.component.isEmpty()) {\n        log.warn(\"Component/Group/Namespace is not provided. Please provide a valid component.\")\n        return\n    }\n    def processed = 0L\n    def batchSize = (params.batch_size != null && params.batch_size > 0) ? params.batch_size : 100\n    def compOperator = (params.component?.contains('%')) ? 'like' : '='\n    def condition = \"namespace ${compOperator} '${params.component}'\"\n    if (params.name != null && !params.name.isEmpty()) {\n        def nameOperator = (params.name?.contains('%')) ? 'like' : '='\n        condition += \" and name ${nameOperator} '${params.name}'\"\n    }\n    if (params.version != null && !params.version.isEmpty()) {\n        def versionOperator = (params.version?.contains('%')) ? 'like' : '='\n        condition += \" and version ${versionOperator} '${params.version}'\"\n    }\n    try {\n        repository.repositoryManager.browse().each { repo ->\n            if (repo.name == params.repo_name) {\n                log.info('Checking repository: {}, type: {}, format: {}', repo.name, repo.type.value, repo.format.value)\n                processed = processRepository(repo, condition, batchSize, params.dryRun)\n            }\n        }\n    }\n    catch (Exception e) {\n        log.warn('Exception details: {}', e.getMessage())\n        log.debug(\"{}\", e.printStackTrace())\n        if (params.dryRun) {    // If dryRun stops at the exception\n            throw e\n        }\n    }\n    return [processed: processed, condition: condition, batchSize: batchSize, dryRun: params.dryRun, debug: params.debug]\n}\n\nlog.info(\"Rebuilding specific search index script started.\")\ndef logMgr = container.lookup(LogManager.class.name) as LogManager\ndef currentLevel = logMgr.getLoggerLevel(\"org.sonatype.nexus.internal.script.ScriptTask\")\ntry {\n    def params = (args) ? new JsonSlurper().parseText(args as String) : null\n    if (params.debug && (params.debug == \"true\" || params.debug == true)) {\n        logMgr.setLoggerLevel(\"org.sonatype.nexus.internal.script.ScriptTask\", LoggerLevel.DEBUG)\n        logMgr.setLoggerLevel(\"org.sonatype.nexus.script.plugin.internal.rest.ScriptResource\", LoggerLevel.DEBUG)\n        //logMgr.setLoggerLevel(\"org.sonatype.nexus.content.maven.store.Maven2ComponentDAO.browseComponents\", LoggerLevel.DEBUG)\n        logMgr.setLoggerLevel(\"org.sonatype.nexus.repository.search.sql.store.SearchTableDAO.saveBatch\", LoggerLevel.DEBUG)\n    }\n    return JsonOutput.toJson(main(params))\n} finally {\n    logMgr.setLoggerLevel(\"org.sonatype.nexus.internal.script.ScriptTask\", currentLevel)\n    logMgr.setLoggerLevel(\"org.sonatype.nexus.script.plugin.internal.rest.ScriptResource\", currentLevel)\n    logMgr.setLoggerLevel(\"org.sonatype.nexus.repository.search.sql.store.SearchTableDAO.saveBatch\", currentLevel)\n    log.info(\"Rebuilding specific search index script completed.\")\n}\n
EOF
}

main() {
    local _repo_name="${1:-"${_REPO_NAME}"}"
    local _component="${2:-"${_COMPONENT}"}"
    local _name="${3:-"${_NAME}"}"
    local _version="${4:-"${_VERSION}"}"
    local _batch_size="${5:-"${_BATCH_SIZE:-100}"}"
    local _install="${6:-"${_INSTALL}"}"

    if [[ "${_install}" =~ ^[yY] ]]; then
        echo "{\"name\":\"${_SCRIPT_NAME}\",\"content\":\"$(genScriptContent)\",\"type\":\"groovy\"}" > ${_TMP%/}/${_SCRIPT_NAME}.json || return $?
        # Delete if exists, and not showing error if not exists, but if install fails, it will show error and exit
        curl -s -L -k -u "${_ADMIN_USER}:${_ADMIN_PWD}" -H 'Content-Type: application/json' "${_NEXUS_URL%/}/service/rest/v1/script/${_SCRIPT_NAME}" -X DELETE
        sleep 1
        curl -sSf -L -k -u "${_ADMIN_USER}:${_ADMIN_PWD}" -H 'Content-Type: application/json' "${_NEXUS_URL%/}/service/rest/v1/script" -d@${_TMP%/}/${_SCRIPT_NAME}.json || return $?
        echo "Script installed" >&2
        sleep 1
    fi

    if [ -z "${_repo_name}" ]; then
        echo "No repository name specified (-r)" >&2
        return
    fi

    if [ -z "${_component}" ]; then
        # At least component is required
        echo "No component (namespace) specified (-c)" >&2
        return
    fi

    curl -sSf -L -k -u "${_ADMIN_USER}:${_ADMIN_PWD}" -H 'Content-Type: application/json' "${_NEXUS_URL%/}/service/rest/v1/script/${_SCRIPT_NAME}/run" -d'{"repo_name":"'${_repo_name}'","component":"'${_component}'","name":"'${_name}'","version":"'${_version}'","batch_size":'${_batch_size}',"dryRun":'${_DRY_RUN:-"false"}',"debug":'${_DEBUG:-"false"}'}'
}


if [ "$0" = "${BASH_SOURCE[0]}" ]; then
    if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ]; then
        usage
        exit 0
    fi

    while getopts "Ir:c:n:v:b:h" opts; do
        case $opts in
        I)
            _INSTALL="Y"
            ;;
        r)
            [ -n "$OPTARG" ] && _REPO_NAME="$OPTARG"
            ;;
        c)
            [ -n "$OPTARG" ] && _COMPONENT="$OPTARG"
            ;;
        n)
            [ -n "$OPTARG" ] && _NAME="$OPTARG"
            ;;
        v)
            [ -n "$OPTARG" ] && _VERSION="$OPTARG"
            ;;
        b)
            [ -n "$OPTARG" ] && _BATCH_SIZE="$OPTARG"
            ;;
        h)
            usage
            exit 0
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
