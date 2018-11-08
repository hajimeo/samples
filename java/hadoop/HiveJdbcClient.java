/*
 * https://cwiki.apache.org/confluence/display/Hive/HiveServer2+Clients#HiveServer2Clients-JDBC
 *
 * mkdir hadoop
 * javaenvs 10000  # in my alias
 * $JAVA_HOME/bin/javac hadoop/HiveJdbcClient.java
 * $JAVA_HOME/bin/java hadoop.HiveJdbcClient "jdbc:hive2://`hostname -f`:10000/default;principal=hive/_HOST@REALM" [sql] [username] [password]
 */
package hadoop;

import java.sql.*;

public class HiveJdbcClient {
    private static String driverName = "org.apache.hive.jdbc.HiveDriver";
    private static String JDBC_DB_URL = "";
    private static String QUERY = "show databases";
    private static String USER = null;
    private static String PASS = null;
    /**
     * @param args
     * @throws SQLException
     */
    public static void main(String[] args) throws SQLException {
        try {
            Class.forName(driverName);
        } catch (ClassNotFoundException e) {
            // TODO Auto-generated catch block
            e.printStackTrace();
            System.exit(1);
        }

        if (args.length == 0) {
            System.err.println("Please provide JDBC connection strings");
            System.exit(1);
        }

        JDBC_DB_URL = args[0];

        if (args.length > 1) {
            QUERY = args[1];
        }
        if (args.length > 2) {
            USER = args[2];
        }
        if (args.length > 3) {
            PASS = args[3];
        }

        //replace "hive" here with the name of the user the queries should run as
        Connection con = DriverManager.getConnection(JDBC_DB_URL, USER, PASS);
        Statement stmt = con.createStatement();
        ResultSet res = stmt.executeQuery(QUERY);
        ResultSetMetaData metaData = res.getMetaData();
        int columnCount = metaData.getColumnCount();

        int r = 1;
        while (res.next()) {
            // columnIndex starts from 1...
            System.out.println("=== Row " + r + " =============================");
            for (int i = 1; i <= columnCount; i++) {
                Object o = res.getObject(i);
                String col = "Null";
                if (o != null) {
                    col = o.toString();
                }
                System.out.println("  " + metaData.getColumnLabel(i) + " : " + o);
            }
            r++;
        }
        res.close();
        stmt.close();
    }
}