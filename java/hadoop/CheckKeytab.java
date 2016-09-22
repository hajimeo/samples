package hadoop;

import java.util.HashMap;
import java.util.Map;
import javax.security.auth.Subject;
import com.sun.security.auth.module.Krb5LoginModule;

/**
 * Created by hosako on 22/09/2016.
 * Simplest way to test keytab with java
 *
 * $JAVA_HOME/bin/javac hadoop/CheckKeytab.java
 * $JAVA_HOME/bin/java hadoop.CheckKeytab /etc/security/keytabs/httpfs.service.keytab httpfs/node1.localdomain@HO-UBU02
 *
 */
public class CheckKeytab {
    private static String KEYTAB = "";
    private static String PRINCIPAL = "";
    private static String KRB5_CONF = "/etc/krb5.conf";

    private void kinit(final String keyTab, final String principal, final String krb5Conf) throws Exception {
        System.out.println(System.getProperty("java.version"));
        System.setProperty("java.security.krb5.conf", krb5Conf);

        // DEBUG
        System.setProperty("sun.security.krb5.debug", "true");

        final Subject subject = new Subject();

        final Krb5LoginModule krb5LoginModule = new Krb5LoginModule();
        final Map<String, String> optionMap = new HashMap<String, String>();

        optionMap.put("keyTab", keyTab);
        System.out.println("Using keytab:  " + keyTab);
        optionMap.put("principal", principal);
        System.out.println("Using principal:  " + principal);
        optionMap.put("doNotPrompt", "true");
        optionMap.put("refreshKrb5Config", "true");
        optionMap.put("useTicketCache", "true");
        optionMap.put("renewTGT", "true");
        optionMap.put("useKeyTab", "true");
        optionMap.put("storeKey", "true");
        optionMap.put("isInitiator", "true");

        // DEBUG
        optionMap.put("debug", "true");

        krb5LoginModule.initialize(subject, null, new HashMap<String, String>(), optionMap);

        boolean result = krb5LoginModule.login();

        System.out.println("Login result:  " + result);

        result = krb5LoginModule.commit();
        System.out.println("Commit result: " + result);

        System.out.println("Subject: " + subject);
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("Please provide a keytab path and principal (and krb5.conf if no default)");
            System.exit(1);
        }

        KEYTAB = args[0];
        PRINCIPAL = args[1];

        if (args.length > 2) {
            KRB5_CONF = args[2];
        }

        final CheckKeytab krb = new CheckKeytab();
        krb.kinit(KEYTAB, PRINCIPAL, KRB5_CONF);
    }
}
