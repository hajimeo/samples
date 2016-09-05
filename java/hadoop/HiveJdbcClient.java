/**
 * https://cwiki.apache.org/confluence/display/Hive/HiveServer2+Clients#HiveServer2Clients-JDBC
 */
package hadoop;

import java.sql.SQLException;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.DriverManager;

public class HiveJdbcClient {
    private static String driverName = "org.apache.hive.jdbc.HiveDriver";
    private static String JDBC_DB_URL = "";
    private static String QUERY = "show databases;";
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
        if (res.next()) {
            System.out.println(res.getString(1));
        }
    }
}