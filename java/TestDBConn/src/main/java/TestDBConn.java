/*
 * Test DB connection with a simple code
 *
 * curl -O https://raw.githubusercontent.com/hajimeo/samples/master/java/TestDBConn.java
 * javac TestDBConn.java
 * java -cp .:/jar_contains_DB_driver.jar TestDBConn org.postgresql.Driver jdbc:postgresql://`hostname -f`:5432/database username password "select * from insight_brain_ods.schema_version;"
 */

import java.sql.*;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class TestDBConn
{
  // NOTE: use small letters.
  static String[] needQuotesTypes = new String[]{"string", "pgobject"};

  public static void main(String[] args) {
    if (args.length < 4) {
      System.err.println("Usage:");
      System.err.println(
          "    java -cp .:path_to_jdbc.jar TestDBConn driver_class_name jdbc_str username password [sql]");
      System.err.println(
          "    java -jar ./TestDBConn-1.0-SNAPSHOT.jar org.postgresql.Driver jdbc:postgresql://localhost:5432/mydatabase dbuser dbuserpwd \"SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'insight_brain_ods' AND TABLE_NAME = 'schema_version'\"");
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
        System.out.print("No");
        // columnIndex starts from 1...
        for (int i = 1; i <= columnCount; i++) {
          System.out.printf(",%s", metaData.getColumnLabel(i));
        }
        System.out.println();

        List<String> needQuotesList = new ArrayList<>(Arrays.asList(needQuotesTypes));
        int r = 1;
        while (rs.next()) {
          System.out.printf("%d", r);
          for (int i = 1; i <= columnCount; i++) {
            Object o = rs.getObject(i);
            String col = "Null";
            String type = "Null";
            if (o != null) {
              col = o.toString();
              type = o.getClass().getSimpleName();
            }
            if (needQuotesList.contains(type.toLowerCase())) {
              System.out.printf(",\"%s\"", col.replace("\"", "\\\""));
            }
            else {
              System.out.printf(",%s", col.replace(",", "\\,"));
            }
          }
          System.out.println();
          r++;
        }
        rs.close();
        stmt.close();
      }
      conn.close();

      System.err.println("INFO: Completed!");
    }
    catch (Exception e) {
      e.printStackTrace();
    }
  }
}