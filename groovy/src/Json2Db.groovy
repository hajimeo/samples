#!/usr/bin/env groovy
/**
 *  groovy -DjsonDir="<dir which contains .json files>" ./Json2Db.groovy
 *
 *  Optional properties:
 *    -h2File=./ods
 *    -outputPath=/tmp/generated_sqls.sql
 *    -DlogLevel=DEBUG
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

def logLevel = System.properties.getProperty('logLevel', "INFO")
log = LoggerFactory.getLogger("")
log.level = Level.toLevel(logLevel)


/**
 * Old style main
 * @param args
 */
def main() {
  log.debug(System.properties.toString())
  // Defaults
  def dbSchema = System.properties.getProperty('dbSchema', "insight_brain_ods")
  def jsonDir = System.properties.getProperty('jsonDir', "./")
  def h2File = System.properties.getProperty('h2File', "")
  def outputPath = System.properties.getProperty('outputPath', "./json2db.sql")
  def dbUser = System.properties.getProperty('dbUser', "sa")
  def dbPwd = System.properties.getProperty('dbPwd', "")

  log.info("JSON dir = ${jsonDir}")
  def f = new File(outputPath)
  if (f.exists() && f.length() > 0) {
    log.error("${outputPath} exists and not empty.")
    return false
  }
  def result = generateSqlStmts(jsonDir, f, dbSchema)

  if (result && f.exists() && f.length() > 0 && h2File.size() > 0) {
    def h2f = new File(h2File).getAbsolutePath().replaceFirst(~/\.h2\.db$/, '')
    def url = "jdbc:h2:${h2f};DATABASE_TO_UPPER=FALSE;IFEXISTS=true;MV_STORE=FALSE;SCHEMA=${dbSchema};MODE=PostgreSQL"
    log.info("URL = ${url}")
    def sql = Sql.newInstance("${url}", dbUser, dbPwd, "org.h2.Driver")
    result = executeScript(outputPath, sql)
    sql.close()
  }

  return result
}

/**
 * Generate a file which contains SQL statements
 * @param jsonDir String Path to a directory which contains JSON files (.json)
 * @param fileObj File Statements will be written into this file
 * @param dbSchema DB Schema
 * @return Boolean
 */
def generateSqlStmts(jsonDir, fileObj, dbSchema) {
  def files = new File(jsonDir).listFiles().findAll { it.file && it.name.endsWith('.json') }
  log.info("Found ${files.size()} json files")

  if (files.size() > 0) {
    //fileObj.append("SET DATABASE_TO_UPPER FALSE;\n")
    save2file("SET REFERENTIAL_INTEGRITY FALSE;", fileObj)

    // NOTE: files[0].getClass() => java.io.File
    def jser = new JsonSlurper()
    for (file in files) {
      def js = jser.parse(file)
      //def fileBase = (js.keySet() as List)[0].toString()
      def fileBase = file.name.replaceFirst(~/\.json$/, '')
      def tableName = fileBase.replaceAll(~/([A-Z])/, '_$1').toLowerCase()
      log.info("File base ${fileBase} / Table name = ${tableName}")

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

      // If no validation error, then save TRUNCATE
      save2file("TRUNCATE TABLE ${tableName};", fileObj)

      // TODO: 'id' column to 'table_id'
      def cols_str = (rows[0].keySet() as List).join(', ')
      def query_prefix = "INSERT INTO \"${dbSchema}\".\"${tableName}\""

      rows.eachWithIndex { row, i ->
        if (row.isEmpty()) {
          log.warn("Index ${i} is empty.")
        }
        else {
          //row['table'] = "${tableName}"
          save2file(query_prefix, fileObj, row, tableName)
        }
      }
    }
  }
  return true
}

/**
 * Execute a statement and/or save to a file
 * @param queryTmpl Query string, which may include ? or :variable
 * @param file File object
 * @param row Map which contain one row data
 * @param tableName Table name
 * @return void
 */
def save2file(queryTmpl, file, row = null, tableName=null) {
  if (row) {
    //def vals = row.collect { cel -> cel.value } as List
    def cols = []
    def vals = []
    // I'm suspecting some json object might not have same columns, so checking columns and values every time.
    row.each{ key, val ->
      // ownerId, threadLevel etc
      def col = key.replaceAll(~/([A-Z])/, '_$1').toLowerCase()
      if (tableName && key == "id") {
        col = "${tableName}_id"
      }
      cols.add(col)
      if (val ==~ /^[0-9]+$/ ) {
        vals.add(val)
      } else if (val ==~ /^(true|false|null)$/ ) {
        vals.add(val)
      } else {
        vals.add("'${val}'")
      }
    }
    def cols_str = cols.join(",")
    def vals_str = vals.join(",")
    log.debug("values: ${vals_str}")
    file.append("${queryTmpl} (${cols_str}) VALUES (${vals_str});\n")
  }
  else {
    file.append("${queryTmpl}\n")
  }
}

/**
 * Read file and execute (but with one execute statement...)
 * @param filePath String
 * @param sql Database connection object
 * @return sql.execute( ) result
 */
def executeScript(filePath, sql) {
  def fPath = new File(filePath).getAbsolutePath()
  log.debug("RUNSCRIPT FROM '${fPath}'")
  return sql.execute("RUNSCRIPT FROM '?'", [fPath])
}

log.debug("Calling main ...")
main()