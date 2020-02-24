#!/usr/bin/env groovy
/**
 * ./Json2Db.groovy "../support-20200224-010636-1/db" "jdbc:h2:./sonatype-work/data/ods;DATABASE_TO_UPPER=FALSE"
 * NOTE:
 *    This script does NOT create any table if missing.
 *    This script does NOT stop the application which might be using the h2 file
 */

@GrabConfig(systemClassLoader = true)
@Grab(group = 'com.h2database', module = 'h2', version = '1.4.200')
import java.sql.*
import groovy.sql.Sql
import org.h2.jdbcx.JdbcConnectionPool
import groovy.json.JsonSlurper

// Update below variables (or should use args), TODO: should do some validation.
def json_dirs = "./db"
if (args.size() > 1) {
  json_dirs = args[1]
}
def url = "jdbc:h2:./sonatype-work/data/ods;DATABASE_TO_UPPER=FALSE"
if (args.size() > 2) {
  url = args[2]
}

def conn = Sql.newInstance(url, 'sa', '', "org.h2.Driver")
def files = new File(json_dirs).listFiles().findAll { it.file && it.name.endsWith('.json') }
def jser = new JsonSlurper()

// TODO: Catch exceptions
// NOTE: files[0].getClass() => java.io.File
for (file in files) {
  def js = jser.parse(file) as List
  def table = (js.keySet() as List)[0]
  conn.execute("TRUNCATE TABLE ${table}")
  def cols_str = ":"+(js[table][0].keySet() as List).join(', :')
  for (row in js[table]) {
    def sql = "INSERT INTO ${table} VALUES (${cols_str})"
    println(sql)
    conn.execute(sql, row)
  }
}
