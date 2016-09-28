/**
 * source /etc/hadoop/conf/hadoop-env.sh
 * $JAVA_HOME/bin/javac -cp `hadoop classpath` ./hadoop/HdfsKerberosTest.java
 * $JAVA_HOME/bin/java -cp `hadoop classpath` hadoop.HdfsKerberosTest [principal] [keytab] [uri_to_namenode]
 */
package hadoop;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.LocatedFileStatus;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.fs.RemoteIterator;
import org.apache.hadoop.security.UserGroupInformation;

import java.io.IOException;
import java.net.URI;
import java.util.Collection;

public class HdfsKerberosTest {

    public static void main(String[] args) throws IOException, InterruptedException {
        Configuration conf = new Configuration(false);
        String dirname = "testdir";
        String filename = "testfile.txt";
        URI uri;

        if (args.length >= 2) {
            System.out.println("Using Kerberos...");
            String user = args[0];  // hdfs@HO-UBUNTU14
            String path = args[1];  // /etc/security/keytabs/hdfs.headless.keytab
            conf.set("hadoop.security.authentication", "Kerberos");
            UserGroupInformation.setConfiguration(conf);
            UserGroupInformation ugi = UserGroupInformation.loginUserFromKeytabAndReturnUGI(user, path);
            //System.out.println(ugi.toString());
            //Collection tkn = ugi.getTokens();
            //System.out.println(tkn.toString());
            //ugi.checkTGTAndReloginFromKeytab();
        }

        if (args.length == 3) {
            uri = URI.create(args[3]);
        } else {
            uri = FileSystem.getDefaultUri(conf);
        }

        Path dir = new Path(dirname);
        FileSystem fs = FileSystem.get(conf);
        //FileSystem fs = FileSystem.get(uri, conf, "hdfs");

        if (!fs.exists(dir)) {
            fs.mkdirs(dir);
            System.out.println("WRITE TEST: Created " + dirname + " direcoty in HDFS");
        }

        System.out.println("WRITE TEST: Creating " + filename + " in HDFS");
        Path dest = new Path(dirname + "/" + filename);
        fs.create(dest);

        System.out.println("READ TEST: listing " + dirname + " direcoty in HDFS");
        RemoteIterator<LocatedFileStatus> ritr = fs.listFiles(dir, false);
        while (ritr.hasNext()) {
            System.out.println(ritr.next().toString());
        }
    }
}
