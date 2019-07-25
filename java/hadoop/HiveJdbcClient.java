/*
 * https://cwiki.apache.org/confluence/display/Hive/HiveServer2+Clients#HiveServer2Clients-JDBC
 *
 * mkdir hadoop     # Then copy jars and java file
 * export CLASSPATH=.:./hadoop/hive-jdbc-client-1.2.1.jar
 * $JAVA_HOME/bin/javac hadoop/HiveJdbcClient.java
 *
 * Supported command arguments: -u, -e, -f, -n, -p, -l
 *
 * $JAVA_HOME/bin/java hadoop.HiveJdbcClient -u "jdbc:hive2://`hostname -f`:10000/default" -e [queries] -n [username] -p [password]
 *
 * If SSL/TLS/HTTPS:
 *  ;ssl=true;sslTrustStore=<trust_store_path>;trustStorePassword=<trust_store_password>
 *
 * If Kerberos:
 * create "login.conf" like below (or use xxxx-jaas.conf or jaas.conf):
echo 'Client {
  com.sun.security.auth.module.Krb5LoginModule required
  useTicketCache=true debug=true debugNative=true;
};' > ./login.conf

 * # If not in classpath: export CLASSPATH="${CLASSPATH%:}:/hadoop-shared/lib/impala/lib/hadoop-auth.jar"
 * $JAVA_HOME/bin/java -Djava.security.auth.login.config=./login.conf -Dsun.security.krb5.debug=true \
 *   hadoop.HiveJdbcClient -u "jdbc:hive2://`hostname -f`:10000/default;principal=hive/_HOST@UBUNTU.LOCALDOMAIN" ... -l Client
 */
package hadoop;

import javax.security.auth.Subject;
import javax.security.auth.callback.*;
import javax.security.auth.login.LoginContext;
import javax.security.auth.login.LoginException;
import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.security.PrivilegedExceptionAction;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;
import java.util.Scanner;

import org.apache.hadoop.security.UserGroupInformation;

public class HiveJdbcClient {
    private static String driverName = "org.apache.hive.jdbc.HiveDriver";
    private static String JDBC_DB_URL = "";
    private static String QUERY = "select 1";
    private static String FILEPATH = "";
    private static String USER = "admin";
    private static String PASS = "admin";

    // KERBEROS Related.
    static String KERBEROS_PRINCIPAL = "";
    static String KERBEROS_PASSWORD = "";
    static String LOGIN_CONTEXT_NAME = "Client";

    public static class MyCallbackHandler implements CallbackHandler {
        public void handle(Callback[] callbacks)
                throws IOException, UnsupportedCallbackException {
            Scanner reader = new Scanner(System.in);

            for (int i = 0; i < callbacks.length; i++) {
                if (callbacks[i] instanceof NameCallback) {
                    NameCallback nc = (NameCallback) callbacks[i];
                    System.out.println("Enter User Principal: ");
                    KERBEROS_PRINCIPAL = reader.next();
                    nc.setName(KERBEROS_PRINCIPAL);
                } else if (callbacks[i] instanceof PasswordCallback) {
                    PasswordCallback pc = (PasswordCallback) callbacks[i];
                    System.out.println("Enter password: ");
                    KERBEROS_PASSWORD = reader.next();
                    pc.setPassword(KERBEROS_PASSWORD.toCharArray());
                } else throw new UnsupportedCallbackException
                        (callbacks[i], "Unrecognised callback");
            }
        }
    }

    static Subject getSubject() {
        Subject signedOnUserSubject = null;

        // create a LoginContext based on the entry in the login.conf file
        LoginContext lc;
        try {
            System.err.println("Creating LoginContext with " + LOGIN_CONTEXT_NAME);
            lc = new LoginContext(LOGIN_CONTEXT_NAME, new HiveJdbcClient.MyCallbackHandler());
            // login (effectively populating the Subject)
            lc.login();
            // get the Subject that represents the signed-on user
            signedOnUserSubject = lc.getSubject();
        } catch (LoginException e1) {
            e1.printStackTrace();
            System.exit(1);
        }
        return signedOnUserSubject;
    }

    static Connection getConnection(Subject signedOnUserSubject) throws Exception {

        Connection conn = (Connection) Subject.doAs(signedOnUserSubject, new PrivilegedExceptionAction<Object>() {
            public Object run() {
                Connection con = null;
                try {
                    Class.forName(driverName);
                    con = DriverManager.getConnection(JDBC_DB_URL, USER, PASS);
                } catch (SQLException e) {
                    e.printStackTrace();
                } catch (ClassNotFoundException e) {
                    e.printStackTrace();
                }
                return con;
            }
        });

        return conn;
    }

    private static StringBuilder readFile(String filename) {
        StringBuilder records = new StringBuilder();
        ;
        try {
            BufferedReader reader = new BufferedReader(new FileReader(filename));
            String line;
            while ((line = reader.readLine()) != null) {
                records.append(line + System.getProperty("line.separator"));
            }
            reader.close();
            return records;
        } catch (Exception e) {
            System.err.format("Exception occurred trying to read '%s'.", filename);
            e.printStackTrace();
            return null;
        }
    }

    /**
     * @param args
     * @throws SQLException
     */
    public static void main(String[] args) throws SQLException {
        try {
            Class.forName(driverName);
        } catch (ClassNotFoundException e) {
            e.printStackTrace();
            System.exit(1);
        }

        if (args.length == 0) {
            System.err.println("Please provide JDBC connection strings");
            System.exit(1);
        }

        // Supported command arguments: -u, -e, -n, -p, -l
        // TODO: no validation
        for (int i = 0; i < args.length; i++) {
            if (args[i].equals("-u")) {
                i++;
                JDBC_DB_URL = args[i];
                continue;
            }
            if (args[i].equals("-e")) {
                i++;
                QUERY = args[i];
                continue;
            }
            if (args[i].equals("-f")) {
                i++;
                FILEPATH = args[i];
                continue;
            }
            if (args[i].equals("-n")) {
                i++;
                USER = args[i];
                continue;
            }
            if (args[i].equals("-p")) {
                i++;
                PASS = args[i];
                continue;
            }
            if (args[i].equals("-l")) {
                i++;
                LOGIN_CONTEXT_NAME = args[i];
                continue;
            }
        }

        if (FILEPATH.length() > 0) {
            QUERY = readFile(FILEPATH).toString();
        }

        /* To test just how many connections it can open.
        List<Connection> _list = new ArrayList<Connection>();
        for (int i = 0; i < 1000; i++) {
            System.err.println(i);
            _list.add(DriverManager.getConnection(JDBC_DB_URL, USER, PASS));
            Thread.sleep(10);
        }
        */

        Connection con = null;
        try {
            String login_config = System.getProperty("java.security.auth.login.config");
            if (login_config != null && !login_config.isEmpty()) {
                Subject sub = getSubject();
                con = getConnection(sub);
            } else {
                con = DriverManager.getConnection(JDBC_DB_URL, USER, PASS);
            }
        } catch (Exception e) {
            e.printStackTrace();
            System.exit(1);
        }

        String[] queries = QUERY.split(";");
        for (String q : queries) {
            if(q.trim().length() < 2) continue;

            System.err.println("# DEBUG: Executing " + q);
            Statement stmt = con.createStatement();
            ResultSet res;
            try {
                res = stmt.executeQuery(q);
            } catch (SQLException e) {
                e.printStackTrace();
                stmt.close();
                continue;
            }
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
}