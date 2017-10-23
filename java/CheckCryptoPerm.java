/**
 * To troubleshoot the "Illegal Key Size"
 * @see https://community.hortonworks.com/questions/37429/ranger-kms-crashes-with-illegal-key-size-exception.html
 *
 * NOTE: works with Java8 at this moment
 * Or TODO: use /usr/hdp/2.4.2.0-258/ranger-kms/ews/webapp/lib/xmlenc-0.52.jar
 */

//import com.sun.org.apache.xml.internal.security.utils.Base64;
import java.util.Base64;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.PBEParameterSpec;
import java.security.Key;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

public class CheckCryptoPerm {
    private static final String MK_CIPHER = "AES";
    private static final int MK_KeySize = 256;
    private static final int SALT_SIZE = 8;
    private static final String PBE_ALGO = "PBEWithMD5AndTripleDES";
    private static final String MD_ALGO = "MD5";

    private Key generateMasterKey() throws NoSuchAlgorithmException{
        KeyGenerator kg = KeyGenerator.getInstance(MK_CIPHER);
        kg.init(MK_KeySize);
        return kg.generateKey();
    }

    private PBEKeySpec getPBEParameterSpec(String password) throws Throwable {
        MessageDigest md = MessageDigest.getInstance(MD_ALGO);
        byte[] saltGen = md.digest(password.getBytes());
        byte[] salt = new byte[SALT_SIZE];
        System.arraycopy(saltGen, 0, salt, 0, SALT_SIZE);
        int iteration = password.toCharArray().length + 1;
        return new PBEKeySpec(password.toCharArray(), salt, iteration);
    }

    private SecretKey getPasswordKey(PBEKeySpec keyspec) throws Throwable {
        SecretKeyFactory factory = SecretKeyFactory.getInstance(PBE_ALGO);
        return factory.generateSecret(keyspec);
    }

    public static void main(String[] args) {
        int allowedKeyLength = 0;

        try {
            String key_name = args[0];
            String password = args[1];

            allowedKeyLength = Cipher.getMaxAllowedKeyLength(key_name);
            System.out.println("The allowed key length for "+ key_name+" is: " + allowedKeyLength);

            CheckCryptoPerm ccp = new CheckCryptoPerm();

            Key secretKey = ccp.generateMasterKey();
            PBEKeySpec pbeKeySpec = ccp.getPBEParameterSpec(password);
            SecretKey key = ccp.getPasswordKey(pbeKeySpec);
            PBEParameterSpec paramSpec = new PBEParameterSpec(pbeKeySpec.getSalt(), pbeKeySpec.getIterationCount());
            Cipher c = Cipher.getInstance(key.getAlgorithm());
            c.init(Cipher.ENCRYPT_MODE, key,paramSpec);
            byte[] masterKeyToDB = c.doFinal(secretKey.getEncoded());

            //String final_result = Base64.encode(masterKeyToDB);
            String final_result = Base64.getEncoder().encodeToString(masterKeyToDB);
            System.out.println("Encoded Master Key is: " + final_result);
        } catch (NoSuchAlgorithmException e) {
            e.printStackTrace();
        } catch (Throwable e) {
            e.printStackTrace();
        }
    }
}
