/*
source /nexus-data/etc/fabric/nexus-store.properties
sysDir="/opt/sonatype/nexus/system"
java -Dgroovy.classpath="$(find ${installDir%/}/org/postgresql/postgresql -type f -name 'postgresql-42.*.jar' | tail -n1)" -jar "${installDir%/}/org/codehaus/groovy/groovy-all/2.4.17/groovy-all-2.4.17.jar" /tmp/DbConnTest.groovy "${jdbcUrl}" "${username}" "${password}"
 */
import org.postgresql.*
import groovy.sql.Sql

def driver = Class.forName('org.postgresql.Driver').newInstance() as Driver
def query = (args.length > 3) ? args[3] : "SELECT 'ok' as test"
def props = new Properties()
props.setProperty("DB_user", args[1])
props.setProperty("DB_password", args[2])
def conn = driver.connect(args[0], props)
def sql = new Sql(conn)
try {
    sql.eachRow(query) {
        println(it)
    }
} finally {
    sql.close()
    conn.close()
}