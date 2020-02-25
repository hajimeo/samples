#!/usr/bin/env groovy
/**
 * ./Json2Db.groovy "../support-20200224-010636-1/db" \
 *    ["jdbc:h2:./sonatype-work/clm-server/data/ods;SCHEMA=insight_brain_ods;IFEXISTS=true;DATABASE_TO_UPPER=FALSE;
 *    MV_STORE=FALSE"]
 *
 * NOTE: ('x' means not needed at this moment)
 *  x This script requires nexus-iq-server-*.jar in the CLASSPATH to convert the filename into H2 table name.
 *    This script does NOT create any table.
 *    This script does NOT check or stop the application which might be using the h2 file.
 */

@GrabConfig(systemClassLoader = true)
@Grab(group = 'com.h2database', module = 'h2', version = '1.4.200')
import java.util.logging.Logger
import groovy.sql.Sql
import groovy.json.JsonSlurper

def logger = Logger.getLogger("J2D")

// Update below variables (or should use args), TODO: should do some validation.
def json_dirs = "../support-20200224-010636-1/db"
// Example
if (args.size() > 0) {
  json_dirs = args[0]
}
//def url = "jdbc:h2:./sonatype-work/clm-server/data/ods;SCHEMA=insight_brain_ods;IFEXISTS=true;
// DATABASE_TO_UPPER=FALSE;MV_STORE=FALSE"
def url = ""
if (args.size() > 1) {
  url = args[1]
}
logger.info("JSON dir = ${json_dirs}")
logger.info("URL = ${url}")

def files = new File(json_dirs).listFiles().findAll { it.file && it.name.endsWith('.json') }
logger.info("Found ${files.size()} json files")

if (files.size() > 0) {
  def sql
  if (url.size() > 0) {
    sql = Sql.newInstance(url, 'sa', '', "org.h2.Driver")
  }

  // NOTE: files[0].getClass() => java.io.File
  def jser = new JsonSlurper()
  for (file in files) {
    def js = jser.parse(file)
    //def fileBase = (js.keySet() as List)[0].toString()
    def fileBase = file.name.replaceFirst(~/\.json$/, '')
    def tableName = fileBase.replaceAll(~/([A-Z])/, '_$1').toLowerCase()
    def query_t = "TRUNCATE TABLE ${tableName};"
    println(query_t)
    if (sql) {
      sql.execute(query_t)
    }
    def row_num = js[fileBase].size()
    logger.info("Num rows = ${row_num}")
    def cols_str_h2 = ":" + (js[fileBase][0].keySet() as List).join(', :')
    def cols_str = (js[fileBase][0].keySet() as List).join(', ')
    def query_prefix = "INSERT INTO ${tableName} (${cols_str_h2}) VALUES "
    logger.info(query_prefix)

    for (row in js[fileBase]) {
      try {
        sql.withTransaction {
          sql.execute(query_prefix, row)
        }
      }
      catch (e) {
        logger.info("row = ${row.toString()}")
        logger.warning(e.message)
      }
    }
  }
}
