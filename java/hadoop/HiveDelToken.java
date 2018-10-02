/** Modified ProxyAuthTest.java **/
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

/**
 * export CLASSPATH=`f_classpath <PID>`:.
 * $JAVA_HOME/bin/javac ProxyAuthTest.java
 * $JAVA_HOME/bin/java ProxyAuthTest `hostname -f` 10000 hive/_HOST@UBUNTU.LOCALDOMAIN testuer
 */
public class HiveDelToken {
    private static final String driverName = "org.apache.hive.jdbc.HiveDriver";
    private static final String BEELINE_EXIT = "beeline.system.exit";
    private static Connection con = null;
    private static boolean noClose = false;
    private static String tabName = "jdbc_test";
    private static String tabDataFileName;
    private static String scriptFileName;
    private static String [] dmlStmts;
    private static String [] dfsStmts;
    private static String [] selectStmts;
    private static String [] cleanUpStmts;
    private static InputStream inpStream = null;
    private static int tabCount = 1;
    private static File resultFile= null;

    public static void main(String[] args) throws Exception {
        if (args.length < 4) {
            System.out.println("Usage HiveDelToken <host> <port> <server_principal> <proxy_user>");
            System.exit(1);
        }

        File currentResultFile = null;
        String[] beeLineArgs = {};

        Class.forName(driverName);
        String host = args[0];
        String port = args[1];
        String serverPrincipal = args[2];
        String proxyUser = args[3];
        String url = null;
        if (args.length > 4) {
            tabName = args[4];
        }

        try {
            url = "jdbc:hive2://" + host + ":" + port + "/default;principal=" + serverPrincipal
                    + ";hive.server2.proxy.user=" + proxyUser;
            con = DriverManager.getConnection(url);
            System.out.println("Connected successfully to " + url);
            String token = ((HiveConnection) con).getDelegationToken(proxyUser, serverPrincipal);
            System.out.println("Got token: " + token);

            ((HiveConnection) con).cancelDelegationToken(token);
            System.out.println("Cancelled token: " + token);
            con.close();
        } catch (SQLException e) {
            System.out.println("*** SQLException: " + e.getMessage() + " : " + e.getSQLState());
            e.printStackTrace();
        }
    }
}