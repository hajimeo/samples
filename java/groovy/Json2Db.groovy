#!/usr/bin/env groovy
/**
 *  groovy -DjsonDir="<dir which contains .json files>" [-Durl="jdbc:h2:xxxxx"] ./Json2Db.groovy
 *
 *    -Dorg.slf4j.simpleLogger.defaultLogLevel=INFO
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
  def jsonDir = System.properties.getProperty('jsonDir', "./")
  def url = System.properties.getProperty('url', "")
  def outputPath = System.properties.getProperty('outputPath', "./json2db.sql")
  def dbUser = System.properties.getProperty('dbUser', "sa")
  def dbPwd = System.properties.getProperty('dbPwd', "")

  log.info("JSON dir = ${jsonDir}")
  log.info("URL = ${url}")
  def f = new File(outputPath)
  if (f.exists() && f.length() > 0) {
    log.error("${outputPath} exists and not empty.")
    return false
  }
  def result = generateSqlStmts(jsonDir, f)

  if (result && f.exists() && f.length() > 0 && url.size() > 0) {
    result = updateDb(f, url, dbUser, dbPwd)
  }
  return result
}

/**
 * Generate a file which contains SQL statements
 * @param jsonDir String Path to a directory which contains JSON files (.json)
 * @param fileObj File Statements will be written into this file
 * @return Boolean
 */
def generateSqlStmts(jsonDir, fileObj) {
  def files = new File(jsonDir).listFiles().findAll { it.file && it.name.endsWith('.json') }
  log.info("Found ${files.size()} json files")

  if (files.size() > 0) {
    // NOTE: files[0].getClass() => java.io.File
    def jser = new JsonSlurper()
    for (file in files) {
      def js = jser.parse(file)
      //def fileBase = (js.keySet() as List)[0].toString()
      def fileBase = file.name.replaceFirst(~/\.json$/, '')
      def tableName = fileBase.replaceAll(~/([A-Z])/, '_$1').toLowerCase()
      log.info("File base ${fileBase} / Table name = ${tableName}")

      fileObj.append("TRUNCATE TABLE ${tableName};\n")

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

      def cols = (rows[0].keySet() as List)
      def cols_str = cols.join(', ')
      def query_prefix = "INSERT INTO ${tableName} (${cols_str}) VALUES"

      rows.eachWithIndex { row, i ->
        def vals = row.collect { cel -> cel.value } as List
        if (vals.size() == 0) {
          log.warn("Index ${i} is empty.")
        }
        else {
          def vals_str = vals.join("','")
          log.trace("values: '${vals_str}'")
          fileObj.append("${query_prefix} ('${vals_str}');\n")
        }
      }
    }
  }
  return true
}

/**
 * Read file and execute (but with one execute statement...)
 * @param fileObj
 * @param url
 * @param dbUser
 * @param dbPwd
 * @return
 */
def updateDb(fileObj, url, dbUser, dbPwd) {
  def sql = Sql.newInstance(url, dbUser, dbPwd, "org.h2.Driver")
  String sqlString = fileObj.text
  sql.execute(sqlString)
  sql.close()
}

log.debug("Calling main ...")
main()