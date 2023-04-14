/*
sysPath="/opt/sonatype/nexus/system"
java -Dgroovy.classpath="$(find ${sysPath%/}/org/postgresql/postgresql -type f -name 'postgresql-42.*.jar' | tail -n1)" -jar "${sysPath%/}/org/codehaus/groovy/groovy-all/2.4.17/groovy-all-2.4.17.jar" \
    ./DbConnTest.groovy /nexus-data/etc/fabric/nexus-store.properties
 */
import org.postgresql.*
import groovy.sql.Sql
import java.time.Duration
import java.time.Instant

def elapse(Instant start, String word) {
    Instant end = Instant.now()
    Duration d = Duration.between(start, end)
    println("# '${word}' took ${d}")
}

def p = new Properties()
if (!args) p = System.getenv()  //username, password, jdbcUrl
else {
    def pf = new File(args[0])
    pf.withInputStream { p.load(it) }
}
def query = (args.length > 1 && !args[1].empty) ? args[1] : "SELECT 'ok' as test"
def driver = Class.forName('org.postgresql.Driver').newInstance() as Driver
def dbP = new Properties()
dbP.setProperty("user", p.username)
dbP.setProperty("password", p.password)
def start = Instant.now()
def conn = driver.connect(p.jdbcUrl, dbP)
elapse(start, "connect")
def sql = new Sql(conn)
try {
    def queries = query.split(";")
    queries.each { q ->
        start = Instant.now()
        sql.eachRow(q) { println(it) }
        elapse(start, q)
    }
} finally {
    sql.close()
    conn.close()
}