package hadoop;

/*
create "login.conf" file which contents is like below:

SampleClient {
  com.sun.security.auth.module.Krb5LoginModule required
  useTicketCache=true debug=true debugNative=true;
};

java -Djava.security.auth.login.config=./login.conf -cp ... HdfsKerberosTest2
 */

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.LocatedFileStatus;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.fs.RemoteIterator;
import org.apache.hadoop.security.UserGroupInformation;
import org.apache.hadoop.fs.FileStatus;

import javax.security.auth.Subject;
import javax.security.auth.callback.*;
import javax.security.auth.login.LoginContext;
import javax.security.auth.login.LoginException;
import java.io.IOException;
import java.util.Scanner;
import java.security.PrivilegedExceptionAction;


public class HdfsKerberosTest2 {
    public static void main(String[] args) throws Exception {
        //System.setProperty("java.security.krb5.realm","");
        //System.setProperty("java.security.krb5.kdc","");
        //System.setProperty("java.security.krb5.conf", "");

        Configuration configuration = new Configuration();

        configuration.set("hadoop.security.authentication", "kerberos");

        UserGroupInformation.setConfiguration(configuration);
        Subject sub = getSubject();


        System.out.println("ticket present: "+ UserGroupInformation.HADOOP_TOKEN_FILE_LOCATION);
        System.out.println(UserGroupInformation.getCurrentUser());
        UserGroupInformation.loginUserFromSubject(sub);

        UserGroupInformation ugi =
                UserGroupInformation.createProxyUser("root", UserGroupInformation.getLoginUser());
        System.out.println("User name"+UserGroupInformation.getLoginUser().getUserName() );
        System.out.println("Credentials*****: "+ugi.getRealAuthenticationMethod());
        ugi.doAs(new PrivilegedExceptionAction<String>(){
            public String run() throws Exception {

                FileSystem fs = FileSystem.get(configuration);
                FileStatus[] fsStatus = fs.listStatus(new Path("/"));
                for(int i = 0; i < fsStatus.length; i++){
                    System.out.println(fsStatus[i].getPath().toString());
                }
                // fs.mkdirs(ne);
                return "jst a value";

            }
        });
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
}