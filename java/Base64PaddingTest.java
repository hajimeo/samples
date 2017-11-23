//import org.apache.commons.codec.binary.Base64;
import java.util.Base64;

public class Base64PaddingTest {

    public static void main(String[] args) {
        // TODO code application logic here

        if (args.length < 1) {
            String atest = "adi-test-adi-tes";

            String kv = Base64.getEncoder().encodeToString(atest.getBytes());
            byte[] a = Base64.getDecoder().decode(kv);

            System.out.println("javaapplication3.JavaApplication3.main()");
            System.out.println(8 * a.length);
            System.out.println(new String(atest));
            System.out.println(new String(Base64.getEncoder().withoutPadding().encode(atest.getBytes())));

        } else {
            System.out.println("Base64 Decode:: " + args[0]);
            System.out.println("What is this ===>" + new String(java.util.Base64.getDecoder().decode(args[0])));
        }
    }
}