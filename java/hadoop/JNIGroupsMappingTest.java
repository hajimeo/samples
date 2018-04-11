/**
 * To test JniBasedUnixGroupsMappingWithFallback
 * <p>
 * javac -cp `hadoop classpath` ./hadoop/JNIGroupsMappingTest.java
 * java -cp `hadoop classpath` -Djava.library.path=/usr/hdp/current/hadoop-client/lib/native hadoop.JNIGroupsMappingTest
 * java -cp `hadoop classpath` -Djava.library.path=/usr/hdp/current/hadoop-client/lib/native -Dhadoop.root.logger=DEBUG,console hadoop.JNIGroupsMappingTest $USER
 */
package hadoop;

import java.io.IOException;
import java.util.Arrays;
import java.util.List;

import org.apache.hadoop.security.GroupMappingServiceProvider;
import org.apache.hadoop.security.JniBasedUnixGroupsMapping;
import org.apache.hadoop.security.ShellBasedUnixGroupsMapping;
import org.apache.hadoop.security.UserGroupInformation;

public class JNIGroupsMappingTest {

    private void getGroups(String user) throws Exception {
        GroupMappingServiceProvider shell = new ShellBasedUnixGroupsMapping();
        List<String> shellBasedGroups = shell.getGroups(user);
        System.out.println("# shellBasedGroups");
        System.out.println(Arrays.toString(shellBasedGroups.toArray()));

        GroupMappingServiceProvider jni = new JniBasedUnixGroupsMapping();
        List<String> jniBasedGroups = jni.getGroups(user);
        System.out.println("# jniBasedGroups");
        System.out.println(Arrays.toString(jniBasedGroups.toArray()));
    }

    public static void main(String[] args) throws IOException {
        try {
            JNIGroupsMappingTest c = new JNIGroupsMappingTest();
            String user = (args.length > 0) ? args[0] : UserGroupInformation.getCurrentUser().getShortUserName();
            System.out.println("# Using user=" + user);
            String sp = System.getProperty("java.library.path");
            System.out.println("# Using sys prop=" + sp);

            c.getGroups(user);
        } catch (Exception e) {
            e.printStackTrace();
            System.err.println("jcmd `cat /var/run/hadoop/hdfs/hadoop-hdfs-namenode.pid` VM.system_properties | grep 'java.library.path'");
            System.exit(1);
        }
    }
}
