/**
 * HOW TO:
 * <p>
 * 1) create login.conf file which contents is like below:
 * SampleClient {
 * com.sun.security.auth.module.Krb5LoginModule required
 * useTicketCache=true debug=true debugNative=true;
 * };
 * <p>
 * 2) Copy necessary jar files in same directory as this code
 * commons-configuration-*.jar
 * hadoop-annotations-*.jar
 * hadoop-auth-*.jar
 * hadoop-common-*.jar
 * hive-exec-*.jar
 * hive-jdbc-*-standalone.jar
 * -- core-site.xml         # probably don't need
 *
 * NOTE: HS2's jars can be used like below, but it won't help when troubleshooting classpath issue:
 * eval "export `cat /proc/$(cat /var/run/hive/hive-server.pid)/environ | tr '\0' '\n' | grep ^CLASSPATH`"
 * <p>
 * 3) Compile
 * javac -cp $(echo *.jar | tr ' ' ':'):. Hive2KerberosTest.java
 * <p>
 * 4) Run
 * kinit
 * java -cp $(echo *.jar | tr ' ' ':'):. -Djava.security.auth.login.config=./login.conf -Dsun.security.krb5.debug=true Hive2KerberosTest "jdbc:hive2://node2.localdomain:10000/default;principal=hive/node2.localdomain@HO-UBU14"
 * <p>
 * <p>
 * ./hive-jdbc-1.2.1.2.3.2.0-2950-standalone.jar:hadoop-common-2.7.1.2.3.2.0-2950.jar:hive-exec-1.2.1.2.3.2.0-2950.jar:./hadoop-annotations-2.7.1.2.3.2.0-2950.jar:./commons-configuration-1.6.jar:hadoop-auth-2.7.1.2.3.2.0-2950.jar
 *
 * @see https://issues.apache.org/jira/secure/attachment/12633984/TestCase_HIVE-6486.java
 */

import org.apache.hadoop.security.UserGroupInformation;

import java.io.IOException;
import java.io.PrintStream;
import java.security.PrivilegedExceptionAction;
import java.sql.*;
import java.util.Scanner;

import javax.security.auth.Subject;
import javax.security.auth.callback.Callback;
import javax.security.auth.callback.CallbackHandler;
import javax.security.auth.callback.NameCallback;
import javax.security.auth.callback.PasswordCallback;
import javax.security.auth.callback.UnsupportedCallbackException;
import javax.security.auth.login.LoginContext;
import javax.security.auth.login.LoginException;

import org.apache.hive.jdbc.HiveStatement;

public class Hive2KerberosTest {

    //  JDBC credentials
    static final String JDBC_DRIVER = "org.apache.hive.jdbc.HiveDriver";
    static String JDBC_DB_URL = "";
    static String QUERY = "";

    static final String USER = null;
    static final String PASS = null;

    // KERBEROS Related.
    static String KERBEROS_PRINCIPAL = "";
    static String KERBEROS_PASSWORD = "";

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
            lc = new LoginContext("SampleClient", new MyCallbackHandler());
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
                    Class.forName(JDBC_DRIVER);
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

    // Print the result set.
    private static int traverseResultSet(ResultSet rs, int max) throws SQLException {
        ResultSetMetaData metaData = rs.getMetaData();
        int rowIndex = 0;
        while (rs.next()) {
            for (int i = 1; i <= metaData.getColumnCount(); i++) {
                System.out.print("  " + rs.getString(i));
            }
            System.out.println();
            rowIndex++;
            if (max > 0 && rowIndex >= max)
                break;
        }
        return rowIndex;
    }

    private static Runnable createLogRunnable(Statement statement) {
        final PrintStream errorStream = new PrintStream(System.err, true);
        final HiveStatement hiveStatement = (HiveStatement) statement;

        Runnable runnable = new Runnable() {
            @Override
            public void run() {
                while (hiveStatement.hasMoreLogs()) {
                    try {
                        // fetch the log periodically and output to beeline console
                        for (String log : hiveStatement.getQueryLog()) {
                            errorStream.println(log);
                        }
                        Thread.sleep(10 * 1000);
                    } catch (SQLException e) {
                        errorStream.println(new SQLWarning(e));
                        return;
                    } catch (InterruptedException e) {
                        errorStream.println("...");
                        return;
                    }
                }
            }
        };
        return runnable;
    }

    static boolean getMoreResults(Statement stmnt) {
        try {
            return stmnt.getMoreResults();
        } catch (Throwable t) {
            return false;
        }
    }

    public static void main(String[] args) {
        Connection conn = null;

        try {
            if (args.length == 0) {
                System.err.println("Please provide JDBC connection strings");
                System.exit(1);
            }

            JDBC_DB_URL = args[0];

            Subject sub = getSubject();

            org.apache.hadoop.conf.Configuration conf = new org.apache.hadoop.conf.Configuration();
            conf.set("hadoop.security.authentication", "Kerberos");
            UserGroupInformation.setConfiguration(conf);
            UserGroupInformation.loginUserFromSubject(sub);
            conn = getConnection(sub);

            if (args.length > 1) {
                QUERY = args[1];
                Statement stmt = conn.createStatement();

                // Tracking the progress (copy and paste from BeeLine.java and Commands.java)
                Thread logThread = new Thread(createLogRunnable(stmt));
                logThread.setDaemon(true);
                logThread.start();
                boolean hasResults = stmt.execute(QUERY);
                logThread.interrupt();

                if (hasResults) {
                    System.out.println("### Printing the result set...");
                    do {
                        ResultSet rs = stmt.getResultSet();
                        try {
                            traverseResultSet(rs, 10);
                        } finally {
                            if (logThread != null) {
                                logThread.join(10 * 1000);
                                //showRemainingLogsIfAny(stmt);
                                logThread = null;
                            }
                            rs.close();
                        }
                    } while (getMoreResults(stmt));
                }

                //ResultSet rs = stmt.executeQuery( QUERY );
                //traverseResultSet(rs, 10);
            } else {
                System.out.println("Successfully Connected!");
            }
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
            try {
                if (conn != null) conn.close();
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }
}