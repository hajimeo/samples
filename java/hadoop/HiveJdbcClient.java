/*
 * https://cwiki.apache.org/confluence/display/Hive/HiveServer2+Clients#HiveServer2Clients-JDBC
 *
 * mkdir hadoop
 * javaenvs 10000  # in my alias
 * $JAVA_HOME/bin/javac hadoop/HiveJdbcClient.java
 * $JAVA_HOME/bin/java hadoop.HiveJdbcClient "jdbc:hive2://`hostname -f`:10000/default" [sql] [username] [password]
 * $JAVA_HOME/bin/java -Djava.security.auth.login.config=/usr/local/atscale/conf/krb/atscale-jaas.conf -Dsun.security.krb5.debug=true hadoop.HiveJdbcClient "jdbc:hive2://`hostname -f`:10000/default;principal=hive/_HOST@UBUNTU.LOCALDOMAIN" [sql] [logincontext]
 *
 * TODO: support kerberos
 */
package hadoop;

import javax.security.auth.Subject;
import javax.security.auth.callback.*;
import javax.security.auth.login.LoginContext;
import javax.security.auth.login.LoginException;
import java.io.IOException;
import java.security.PrivilegedExceptionAction;
import java.sql.*;
import java.util.Scanner;
import org.apache.hadoop.security.UserGroupInformation;

public class HiveJdbcClient {
    private static String driverName = "org.apache.hive.jdbc.HiveDriver";
    private static String JDBC_DB_URL = "";
    private static String QUERY = "show databases";
    private static String USER = null;
    private static String PASS = null;

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
            System.err.println("Creating LoginContext with "+LOGIN_CONTEXT_NAME);
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

        JDBC_DB_URL = args[0];

        if (args.length > 1) {
            QUERY = args[1];
        }
        if (args.length > 2) {
            USER = args[2];
            LOGIN_CONTEXT_NAME = args[2];
        }
        if (args.length > 3) {
            PASS = args[3];
        }


        Connection con = null;
        try {
            String login_config = System.getProperty("java.security.auth.login.config");
            if (login_config.length() > 0) {
                Subject sub = getSubject();
                con = getConnection(sub);
            }
            else {
                con = DriverManager.getConnection(JDBC_DB_URL, USER, PASS);
            }
        } catch (Exception e) {
            e.printStackTrace();
            System.exit(1);
        }

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