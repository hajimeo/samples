/*
 * Test DB connection with a simple code
 *
 * curl -O https://raw.githubusercontent.com/hajimeo/samples/master/java/TestDBConn.java
 * javac TestDBConn.java
 * java -cp .:/some_jar_include_driver.jar TestDBConn org.postgresql.Driver jdbc:postgresql://`hostname -f`:5432/schema username password "select * from database.table where 1 = 1"
 *
 * java -jar ./target/TestDBConn-1.0-SNAPSHOT.jar org.postgresql.Driver jdbc:postgresql://node-nxiq.standalone.localdomain:5432/sonatype sonatype admin123 "select * from insight_brain_ods.schema_version"
 */

import java.sql.*;

public class TestDBConn {
    public static void main(String[] args) {
        if (args.length < 4) {
            System.err.println("Usage:");
            System.err.println("    java -cp .:path_to_jdbc.jar TestDBConn driver_class_name jdbc_str username password [sql]");
            System.err.println("    java -cp .:./postgresql-42.2.5.jar TestDBConn org.postgresql.Driver jdbc:postgresql://localhost:5432/template1 postgres ****** 'select * from some_table;'");
            System.exit(1);
        }

        String class_name = args[0];
        String jdbc_conn_str = args[1];
        String db_user = args[2];
        String db_pass = args[3];
        String sql = "";
        if (args.length > 4) {
            sql = args[4];
        }

        try {
            Class.forName(class_name);
            System.err.println("INFO: Connecting to " + jdbc_conn_str + " as " + db_user + "...");
            Connection conn = DriverManager.getConnection(jdbc_conn_str, db_user, db_pass);

            if (sql.length() > 0) {
                System.err.println("INFO: Executing " + sql + " ...");
                Statement stmt = conn.createStatement();
                ResultSet rs = stmt.executeQuery(sql);
                ResultSetMetaData metaData = rs.getMetaData();
                int columnCount = metaData.getColumnCount();

                int r = 1;
                while (rs.next()) {
                    // columnIndex starts from 1...
                    System.out.println("=== Row " + r + " =============================");
                    for (int i = 1; i <= columnCount; i++) {
                        Object o = rs.getObject(i);
                        String col = "Null";
                        if (o != null) {
                            col = o.toString();
                        }
                        System.out.println("  " + metaData.getColumnLabel(i) + " : " + o);
                    }
                    r++;
                }
                rs.close();
                stmt.close();
            }
            conn.close();

            System.err.println("INFO: Completed!");
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}