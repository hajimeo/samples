/* Copy of https://issues.apache.org/jira/secure/attachment/12617227/ProxyAuth.java */

package hadoop;

/**
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import java.io.*;

import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.DriverManager;
import java.sql.DriverPropertyInfo;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Types;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import org.apache.hadoop.conf.Configuration;
import org.apache.hive.jdbc.HiveConnection;
import org.apache.hive.beeline.BeeLine;
import org.apache.hadoop.hive.shims.ShimLoader;
import org.apache.hadoop.hive.thrift.DelegationTokenIdentifier;
import org.apache.hadoop.security.token.Token;
import org.apache.hive.service.auth.HiveAuthFactory;

// import org.apache.hadoop.security.UserGroupInformation;

/**
 * Simple client application to test various direct and proxy connection to HiveServer2
 */
public class ProxyAuth {

    private static final String driverName = "org.apache.hive.jdbc.HiveDriver";
    private static final String BEELINE_EXIT = "beeline.system.exit";
    private static Connection con = null;
    private static boolean noClose = false;
    private static String tabName = "jdbc_test";
    private static String tabDataFileName;
    private static String scriptFileName;
    private static String [] dmlStmts;
    private static String [] selectStmts;
    private static String [] cleanUpStmts;
    private static InputStream inp = null;
    private static int tabCount = 1;

    public static void main(String[] args) throws Exception {
        if (args.length < 4) {
            System.out.println("Usage ProxyAuth <host> <port> <server_principal> <proxy_user> [testTab]");
            System.exit(1);
        }

        Class.forName(driverName);
        String host = args[0];
        String port = args[1];
        String serverPrincipal = args[2];
        String proxyUser = args[3];
        if (args.length > 4) {
            tabName = args[4];
        }

        generateData();
        generateSQL(null);

        try {
    /*
     * Connect via kerberos and get delegation token
     */
            String url = "jdbc:hive2://" + host + ":" + port + "/default;principal=" + serverPrincipal;
            con = DriverManager.getConnection(url);
            System.out.println("Connected successfully to " + url);
            // get delegation token for the given proxy user
            String token = ((HiveConnection)con).getDelegationToken(proxyUser, serverPrincipal);
            System.out.println("Got token: " + token);
            con.close();

            // so that beeline won't kill the JVM
            System.setProperty(BEELINE_EXIT, "true");

            // connect using principal via Beeline with inputStream
            url = "jdbc:hive2://" + host + ":" + port + "/default;principal=" + serverPrincipal;
            generateSQL(null);
            String [] beeLineArgs = { "-u", url, "-n", "foo", "-p", "bar"};
            System.out.println("Connection with kerberos, user/password via args, using input rediction");
            BeeLine.mainWithInputRedirection(beeLineArgs, inp);

            // connect using principal via Beeline with inputStream
            url = "jdbc:hive2://" + host + ":" + port + "/default;principal=" + serverPrincipal;
            generateSQL(null);
            beeLineArgs = new String[] { "-u", url, "-n", "foo", "-p", "bar", "-f" , scriptFileName};
            System.out.println("Connection with kerberos, user/password via args, using input script");
            BeeLine.main(beeLineArgs);

            // connect using principal via Beeline with inputStream
            url = "jdbc:hive2://" + host + ":" + port + "/default;principal=" + serverPrincipal;
            generateSQL(url+ " foo bar ");
            beeLineArgs = new String[] { "-u", url, "-f" , scriptFileName};
            System.out.println("Connection with kerberos, user/password via connect, using input script");
            BeeLine.main(beeLineArgs);

            // connect using principal via Beeline with inputStream
            url = "jdbc:hive2://" + host + ":" + port + "/default;principal=" + serverPrincipal;
            generateSQL(url+ " foo bar ");
            beeLineArgs = new String[] { "-u", url, "-f" , scriptFileName};
            System.out.println("Connection with kerberos, user/password via connect, using input redirect");
            BeeLine.mainWithInputRedirection(beeLineArgs, inp);

    /*
     * Connect using the delegation token passed via configuration object
     */
            System.out.println("Store token into ugi and try");
            storeTokenInJobConf(token);
            url = "jdbc:hive2://" + host + ":" + port + "/default;auth=delegationToken";
            con = DriverManager.getConnection(url);
            System.out.println("Connecting to " + url);
            runTest();
            con.close();

            // connect using token via Beeline with inputStream
            url = "jdbc:hive2://" + host + ":" + port + "/default";
            generateSQL(null);
            beeLineArgs = new String[] { "-u", url, "-n", "foo", "-p", "bar", "-a", "delegationToken" };
            System.out.println("Connection with token, user/password via args, using input redirection");
            BeeLine.mainWithInputRedirection(beeLineArgs, inp);

            // connect using token via Beeline using script
            url = "jdbc:hive2://" + host + ":" + port + "/default";
            generateSQL(null);
            beeLineArgs = new String[] { "-u", url, "-n", "foo", "-p", "bar", "-a", "delegationToken",
                    "-f", scriptFileName};
            System.out.println("Connection with token, user/password via args, using input script");
            BeeLine.main(beeLineArgs);

            // connect using token via Beeline using script
            url = "jdbc:hive2://" + host + ":" + port + "/default";
            generateSQL(url + " foo bar ");
            beeLineArgs = new String [] {"-a", "delegationToken", "-f", scriptFileName};
            System.out.println("Connection with token, user/password via connect, using input script");
            BeeLine.main(beeLineArgs);

            // connect using token via Beeline using script
            url = "jdbc:hive2://" + host + ":" + port + "/default";
            generateSQL(url + " foo bar ");
            System.out.println("Connection with token, user/password via connect, using input script");
            beeLineArgs = new String [] {"-f", scriptFileName, "-a", "delegationToken"};
            BeeLine.main(beeLineArgs);

    /*
     * Connect via kerberos with trusted proxy user
     */
            url = "jdbc:hive2://" + host + ":" + port + "/default;principal=" + serverPrincipal
                    + ";hive.server2.proxy.user=" + proxyUser;
            con = DriverManager.getConnection(url);
            System.out.println("Connected successfully to " + url);
            runTest();
        } catch (SQLException e) {
            System.out.println("*** SQLException: " + e.getMessage() + " : " + e.getSQLState());
            e.printStackTrace();
        }
    }

    private static void storeTokenInJobConf(String tokenStr) throws Exception {
        ShimLoader.getHadoopShims().setTokenStr(ShimLoader.getHadoopShims().getUGIForConf(new Configuration()),
                tokenStr, HiveAuthFactory.HS2_CLIENT_TOKEN);
// HiveConnection.HIVE_CONF_TOKEN);
/*
    Token<DelegationTokenIdentifier> delegationToken = new Token<DelegationTokenIdentifier>();
    delegationToken.decodeFromUrlString(tokenStr);
    ShimLoader.getHadoopShims().getUGIForConf(new Configuration()).addToken(delegationToken);
*/
        System.out.println("Stored token " + tokenStr);
    }

    // run sql operations
    private static void runTest() throws Exception {
        // craete table and check dir ownership
        runDMLs();

        // run queries
        for (String stmt: selectStmts) {
            runQuery(stmt);
        }

        // delete all the objects created
        cleanUp();
    }

    // create tables and load data
    private static void runDMLs() throws Exception {
        for (String stmt : dmlStmts) {
            exStatement(stmt);
        }
    }

    // drop tables
    private static void cleanUp() throws Exception {
        for (String stmt : cleanUpStmts) {
            exStatement(stmt);
        }
    }
    private static void runQuery(String sqlStmt) throws Exception {
        Statement stmt = con.createStatement();
        ResultSet res = stmt.executeQuery(sqlStmt);

        ResultSetMetaData meta = res.getMetaData();
        System.out.println("Resultset has " + meta.getColumnCount() + " columns");
        for (int i = 1; i <= meta.getColumnCount(); i++) {
            System.out.println("Column #" + i + " Name: " + meta.getColumnName(i) +
                    " Type: " + meta.getColumnType(i));
        }

        while (res.next()) {
            for (int i = 1; i <= meta.getColumnCount(); i++) {
                System.out.println("Column #" + i + ": " + res.getString(i));
            }
        }
        res.close();
        stmt.close();
    }

    // Execute the given sql statement
    private static void exStatement(String query) throws Exception {
        Statement stmt = con.createStatement();
        stmt.execute(query);
        if (!noClose) {
            stmt.close();
        }
    }

    // generate SQL stmts to execute
    private static void generateSQL(String url) throws Exception {
        String current = new java.io.File( "." ).getCanonicalPath();
        String currentDir = System.getProperty("user.dir");
        String queryTab = tabName + "_" + (tabCount++);
        dmlStmts = new String[] {
                "USE default",
                "drop table if exists  " + queryTab,
                "create table " + queryTab + "(id int, name string) " +
                        "ROW FORMAT DELIMITED FIELDS TERMINATED BY '|'",
                "load data local inpath '" + tabDataFileName + "' into table " + queryTab
        };
        selectStmts = new String[] {
                "select * from " + queryTab + " limit 5",
//      "select name, id from " + queryTab + " where id < 3"
        };
        cleanUpStmts = new String[] {
                "drop table if exists  " + queryTab
        };

        // write sql statements to file
        writeArrayToByteStream(url);
    }

    // generate data file for test
    private static void generateData() throws Exception {
        String fileData[] = {
                "1|aaa",
                "2|bbb",
                "3|ccc",
                "4|ddd",
                "5|eee",
        };

        File tmpFile = File.createTempFile(tabName, ".data");
        tmpFile.deleteOnExit();
        tabDataFileName = tmpFile.getPath();
        FileWriter fstream = new FileWriter(tabDataFileName);
        BufferedWriter out = new BufferedWriter(fstream);
        for (String line: fileData) {
            out.write(line);
            out.newLine();
        }
        out.close();
        tmpFile.setWritable(true, true);
    }

    // Create a input stream of given name.ext  and write sql statements to to it
    private static void writeArrayToByteStream(String url) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();

        if (url != null) {
            String connCmd = "!connect " + url;
            out.write(connCmd.getBytes());
            out.write(System.getProperty("line.separator").getBytes());
        }

        for (String stmt: dmlStmts) {
            writeSqlLine(stmt, out);
        }

        for (String stmt: selectStmts) {
            writeSqlLine(stmt, out);
        }

        for (String stmt: cleanUpStmts) {
            writeSqlLine(stmt, out);
        }
        out.write("!quit".getBytes());
        out.write(System.getProperty("line.separator").getBytes());

        File tmpFile = File.createTempFile(tabName, "q");
        tmpFile.deleteOnExit();
        scriptFileName = tmpFile.getPath();
        FileOutputStream fstream = new FileOutputStream(scriptFileName);
        out.writeTo(fstream);

        inp = new ByteArrayInputStream(out.toByteArray());
    }

    // write stmt + ";" + System.getProperty("line.separator")
    private static void writeSqlLine(String stmt, OutputStream out) throws Exception {
        out.write(stmt.getBytes());
        out.write(";".getBytes());
        out.write(System.getProperty("line.separator").getBytes());
    }
}
