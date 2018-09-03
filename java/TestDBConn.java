/*
 * Test DB connection with a simple code
 */

import java.sql.*;

public class TestDBConn {
    public static void main(String[] args) {
        Connection conn = null;
        Statement stmt = null;

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

            System.err.println("Connecting to database...");
            conn = DriverManager.getConnection(jdbc_conn_str, db_user, db_pass);

            if (sql.length() > 0) {
                System.err.println("Executing statement...");
                stmt = conn.createStatement();
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

            System.out.println("Completed!");
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}