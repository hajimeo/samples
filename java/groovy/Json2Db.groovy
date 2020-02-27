#!/usr/bin/env groovy
/**
 *  groovy -DjsonDir="<dir which contains .json files>" ./Json2Db.groovy
 *
 *  Optionals:
 *    -Durl="jdbc:h2:${_sonatypeWork%/}/data/ods;DATABASE_TO_UPPER=FALSE"
 *    -Dorg.slf4j.simpleLogger.defaultLogLevel=DEBUG
 */

@GrabConfig(systemClassLoader = true)
@Grab('org.slf4j:slf4j-log4j12:1.7.30')
@Grab("ch.qos.logback:logback-classic:1.2.3")
@Grab('com.h2database:h2:1.4.196')

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import ch.qos.logback.classic.Level

import groovy.sql.Sql
import groovy.json.JsonSlurper

//LoggerFactory.getLogger(Logger.ROOT_LOGGER_NAME).level = Level.DEBUG
log = LoggerFactory.getLogger("-")

/**
 * Old style main
 * @param args
 */
def main() {
  log.debug(System.properties.toString())
  // Defaults
  def dbSchema = System.properties.getProperty('dbSchema', "insight_brain_ods")
  def jsonDir = System.properties.getProperty('jsonDir', "./")
  def url = System.properties.getProperty('url', "")
  def outputPath = System.properties.getProperty('outputPath', "./json2db.sql")
  def dbUser = System.properties.getProperty('dbUser', "sa")
  def dbPwd = System.properties.getProperty('dbPwd', "")
  def sql = (url.isEmpty()) ? null : Sql.newInstance("${url};SCHEMA=${dbSchema}", dbUser, dbPwd, "org.h2.Driver")

  log.info("JSON dir = ${jsonDir}")
  log.info("URL = ${url}")
  def f = new File(outputPath)
  if (f.exists() && f.length() > 0) {
    log.error("${outputPath} exists and not empty.")
    return false
  }
  def result = generateSqlStmts(jsonDir, f, dbSchema, sql)

  if (result && f.exists() && f.length() > 0 && url.size() > 0) {
    result = updateDb(f, url, dbUser, dbPwd)
  }
  return result
}

/**
 * Generate a file which contains SQL statements
 * @param jsonDir String Path to a directory which contains JSON files (.json)
 * @param fileObj File Statements will be written into this file
 * @param dbSchema DB Schema
 * @param sql DB connection object
 * @return Boolean
 */
def generateSqlStmts(jsonDir, fileObj, dbSchema, sql = null) {
  def files = new File(jsonDir).listFiles().findAll { it.file && it.name.endsWith('.json') }
  log.info("Found ${files.size()} json files")

  if (files.size() > 0) {
    //fileObj.append("SET DATABASE_TO_UPPER FALSE;\n")
    execute("SET REFERENTIAL_INTEGRITY FALSE;", fileObj, sql)
    //execute("SET SCHEMA ${dbSchema};", fileObj, sql)

    // NOTE: files[0].getClass() => java.io.File
    def jser = new JsonSlurper()
    for (file in files) {
      def js = jser.parse(file)
      //def fileBase = (js.keySet() as List)[0].toString()
      def fileBase = file.name.replaceFirst(~/\.json$/, '')
      def tableName = fileBase.replaceAll(~/([A-Z])/, '_$1').toLowerCase()
      log.info("File base ${fileBase} / Table name = ${tableName}")

      //execute("DELETE FROM :mytable;", fileObj, sql, [mytable: "${dbSchema}."])

      def rows = js[fileBase]
      log.trace(rows.getClass().toString())
      if (rows instanceof Map) {
        log.warn("${fileBase} is not List.")
        continue
      }
      def row_num = rows.size()
      log.info("Num rows = ${row_num}")
      if (row_num == 0) {
        log.debug("${fileBase} is empty, so skipping.")
        continue
      }

      // TODO: 'id' column to 'table_id'
      def cols_str = (rows[0].keySet() as List).join(', ')
      def query_prefix = "INSERT INTO \"${dbSchema}\".\"${tableName}\" VALUES"
      if (sql) {
        cols_str = ":" + (rows[0].keySet() as List).join(', :')
        query_prefix = "INSERT INTO ${tableName} VALUES (${cols_str})"
      }

      rows.eachWithIndex { row, i ->
        if (row.isEmpty()) {
          log.warn("Index ${i} is empty.")
        }
        else {
          //row['table'] = "${tableName}"
          execute(query_prefix, fileObj, sql, row)
        }
      }
    }
  }
  return true
}

def execute(queryTmpl, file = null, sql = null, row = null) {
  if (sql) {
    if (row) {
      log.debug("Query: ${queryTmpl} with ${row.toString()}")
      sql.execute(queryTmpl, row)
    }
    else {
      log.debug("Query: ${queryTmpl}")
      sql.execute(queryTmpl)
    }
  }
  else if (file) {
    if (row) {
      def vals = row.collect { cel -> cel.value } as List
      def vals_str = vals.join("','")
      log.debug("values: '${vals_str}'")
      file.append("${queryTmpl} ('${vals_str}');\n")
    }
    else {
      file.append("${queryTmpl}\n")
    }
  }
}


log.debug("Calling main ...")
main()