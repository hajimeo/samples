/**
 * Modified ProxyAuthTest.java
 * <p>
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 * <p>
 * http://www.apache.org/licenses/LICENSE-2.0
 * <p>
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package hadoop;

import java.io.*;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;

import org.apache.commons.io.FileUtils;
import org.apache.commons.io.IOUtils;
import org.apache.hadoop.conf.Configuration;
import org.apache.hive.jdbc.HiveConnection;
import org.apache.hive.beeline.BeeLine;
import org.apache.hadoop.hive.shims.ShimLoader;
import org.apache.hadoop.hive.shims.Utils;
import org.apache.hive.service.auth.HiveAuthFactory;
import org.apache.hadoop.security.UserGroupInformation;

/**
 * javaenvs <port>  # in my alias
 * $JAVA_HOME/bin/javac HiveDelToken.java
 * $JAVA_HOME/bin/java HiveDelToken `hostname -f` 10000 hive/_HOST@UBUNTU.LOCALDOMAIN testuer
 */
public class HiveDelToken {
    private static final String driverName = "org.apache.hive.jdbc.HiveDriver";
    private static final String BEELINE_EXIT = "beeline.system.exit";
    private static Connection con = null;
    private static boolean noClose = false;
    private static String tabDataFileName;
    private static String scriptFileName;
    private static String[] dmlStmts;
    private static String[] dfsStmts;
    private static String[] selectStmts;
    private static String[] cleanUpStmts;
    private static InputStream inpStream = null;
    private static int tabCount = 1;
    private static File resultFile = null;

    public static void main(String[] args) throws Exception {
        if (args.length < 3) {
            System.out.println("Usage HiveDelToken <host> <port> <server_principal> [<proxy_user>] [<action>] [<param:token|ms>]");
            System.exit(1);
        }

        File currentResultFile = null;
        String[] beeLineArgs = {};

        Class.forName(driverName);
        String host = args[0];
        String port = args[1];
        String renewer = args[2];
        String owner = UserGroupInformation.getCurrentUser().getShortUserName();
        String url = null;
        String action = "";
        String token = "";
        if (args.length > 4) {
            action = args[4];
        }

        try {
            if (args.length > 3 && args[3].length() > 0) {
                owner = args[3];
                url = "jdbc:hive2://" + host + ":" + port + "/default;principal=" + renewer + ";hive.server2.proxy.user=" + args[3];
            } else {
                url = "jdbc:hive2://" + host + ":" + port + "/default;principal=" + renewer;
            }
            con = DriverManager.getConnection(url);
            System.out.println("Connected successfully to " + url);

            if (action.equals("renew")) {
                if (args.length > 5) {
                    token = args[5];
                }
                ((HiveConnection) con).renewDelegationToken(token);
                System.out.println("Renewed token: " + token);
            } else if (action.equals("delete")) {
                if (args.length > 5) {
                    token = args[5];
                }
                ((HiveConnection) con).cancelDelegationToken(token);
                System.out.println("Cancelled token: " + token);
            } else if (action.equals("wait")) {
                int wait_ms = 10000;
                if (args.length > 5) {
                    wait_ms = Integer.parseInt(args[5]);
                }
                Thread.sleep(wait_ms);
                Statement stmt = con.createStatement();
                ResultSet res = stmt.executeQuery("show databases");
                if (res.next()) {
                    System.out.println(res.getString(1));
                }
                System.out.println("Waited and executed a query for " + owner);
            } else {
                token = ((HiveConnection) con).getDelegationToken(owner, renewer);
                System.out.println("Got token for " + owner + " : " + token);
            }

            con.close();
        } catch (Exception e) {
            System.out.println("*** Exception: " + e.getMessage());
            e.printStackTrace();
        }
    }
}