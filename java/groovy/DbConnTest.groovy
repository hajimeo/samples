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