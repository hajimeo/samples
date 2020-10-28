/*
 * from
 *  https://wiki.shibboleth.net/confluence/plugins/viewsource/viewpagesrc.action?pageId=3277047
 *  https://stackoverflow.com/questions/17890642/opensaml-2-0-signature-validation-not-working
 *  http://www.java2s.com/Tutorials/Java/org.w3c.dom/Document/0280__Document.getDocumentElement_.htm
 *  Invalid signature file digest for Manifest main attributes
 *  https://stackoverflow.com/questions/42540485/how-to-stop-maven-shade-plugin-from-blocking-java-util-serviceloader-initializat
 *
 *  export CLASSPATH=$(echo $PWD/lib/*.jar | tr ' ' ':'):$PWD/target/SamlTest-1.0-SNAPSHOT.jar:.
 *  java SignatureVerification ./cert3.crt ./test2.xml
 */

import org.opensaml.Configuration;
import org.opensaml.DefaultBootstrap;
import org.opensaml.saml2.core.Response;
import org.opensaml.xml.io.Unmarshaller;
import org.opensaml.xml.io.UnmarshallerFactory;
import org.opensaml.xml.security.x509.BasicX509Credential;
import org.opensaml.xml.signature.Signature;
import org.opensaml.xml.signature.SignatureValidator;
import org.w3c.dom.Document;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import java.io.*;
import java.security.KeyFactory;
import java.security.PublicKey;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.security.spec.X509EncodedKeySpec;

public class SignatureVerification {
    public static void main(String[] args) {
        try {
            String idp_cert_path = args[0];
            String saml_resp_path = args[1];

            DocumentBuilderFactory builderFactory = DocumentBuilderFactory.newInstance();
            builderFactory.setNamespaceAware(true);       // Set namespace aware
            builderFactory.setValidating(true);           // and validating parser feaures
            builderFactory.setIgnoringElementContentWhitespace(true);
            DocumentBuilder builder = null;
            builder = builderFactory.newDocumentBuilder();  // Create the parser

            File samlXmlFile = new File(saml_resp_path);
            Document document = builder.parse(samlXmlFile);

            DefaultBootstrap.bootstrap();
            UnmarshallerFactory unmarshallerFactory = Configuration.getUnmarshallerFactory();
            Unmarshaller unmarshaller = unmarshallerFactory.getUnmarshaller(document.getDocumentElement());
            Response response = (Response) unmarshaller.unmarshall(document.getDocumentElement());
            //System.err.println("response: "+response.getDOM().getTextContent());
            //System.err.println("response: "+response.isSigned());

            //Get Public Key
            BasicX509Credential publicCredential = new BasicX509Credential();
            File publicKeyFile = new File(idp_cert_path);

            CertificateFactory certificateFactory = CertificateFactory.getInstance("X.509");
            InputStream fileStream = new FileInputStream(publicKeyFile);
            X509Certificate certificate = (X509Certificate) certificateFactory.generateCertificate(fileStream);
            fileStream.close();

            X509EncodedKeySpec publicKeySpec = new X509EncodedKeySpec(certificate.getPublicKey().getEncoded());
            KeyFactory keyFactory = KeyFactory.getInstance("RSA");
            PublicKey key = keyFactory.generatePublic(publicKeySpec);

            //Validate Public Key against Signature
            if (key == null) {
                System.err.println(idp_cert_path + " is not a correct X.509 certificate");
                return;
            }

            publicCredential.setPublicKey(key);
            SignatureValidator signatureValidator = new SignatureValidator(publicCredential);
            Signature signature = response.getSignature();
            if (signature == null) {
                signature = response.getAssertions().get(0).getSignature();
            }
            if (signature == null) {
                System.err.println("signature from the SAML response is null");
                return;
            }
            signatureValidator.validate(signature);

            // No error meas all good
            System.out.println("All good.");
        } catch (Exception e) {
            System.out.println("Not good.");
            e.printStackTrace();
        }
    }
}
