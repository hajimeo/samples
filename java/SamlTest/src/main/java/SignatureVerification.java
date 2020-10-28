/*
 * from
 *  https://wiki.shibboleth.net/confluence/plugins/viewsource/viewpagesrc.action?pageId=3277047
 *  https://stackoverflow.com/questions/17890642/opensaml-2-0-signature-validation-not-working
 *  http://www.java2s.com/Tutorials/Java/org.w3c.dom/Document/0280__Document.getDocumentElement_.htm
 *  Invalid signature file digest for Manifest main attributes
 *  https://stackoverflow.com/questions/42540485/how-to-stop-maven-shade-plugin-from-blocking-java-util-serviceloader-initializat
 *
 *  http://xacmlinfo.org/2015/04/02/saml2-signature-validation-tool-for-saml2-response-and-assertion/
 *
 *  export CLASSPATH=$(echo $PWD/lib/*.jar | tr ' ' ':'):$PWD/target/SamlTest-1.0-SNAPSHOT.jar:.
 *  java -Dorg.slf4j.simpleLogger.defaultLogLevel=debug SignatureVerification ./cert3.crt ./test2.xml
 */

import org.apache.xml.security.signature.XMLSignature;
import org.opensaml.Configuration;
import org.opensaml.DefaultBootstrap;
import org.opensaml.saml2.core.Assertion;
import org.opensaml.saml2.core.Response;
import org.opensaml.xml.XMLObject;
import org.opensaml.xml.io.Unmarshaller;
import org.opensaml.xml.io.UnmarshallerFactory;
import org.opensaml.xml.security.x509.BasicX509Credential;
import org.opensaml.xml.signature.Signature;
import org.opensaml.xml.signature.SignatureValidator;
import org.opensaml.xml.signature.impl.SignatureImpl;
import org.w3c.dom.Document;
import org.w3c.dom.Element;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import java.io.*;
import java.security.KeyFactory;
import java.security.PublicKey;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.security.spec.X509EncodedKeySpec;
import java.util.Scanner;

public class SignatureVerification {
    public static void main(String[] args) {
        try {
            String saml_resp_path = args[0];
            String idp_cert_path = null;
            if (args.length > 1) {
                idp_cert_path = args[1];
            }

            String saml = readfile(saml_resp_path);
            //System.err.println(saml);

            DefaultBootstrap.bootstrap();
            XMLObject xmlObject = unmarshall(new String(saml.getBytes()));
            Assertion assertion = null;
            if (xmlObject instanceof Response) {
                assertion = ((Response) xmlObject).getAssertions().get(0);
            } else if (xmlObject instanceof Assertion) {
                assertion = (Assertion) xmlObject;
            }

            Signature signature = assertion.getSignature();
            System.err.println("Assertion SignatureAlgorithm: " + signature.getSignatureAlgorithm());
            XMLSignature xmlSignature = ((SignatureImpl) signature).getXMLSignature();

            X509Certificate certificate = null;
            if (idp_cert_path != null) {
                System.err.println("Using " + idp_cert_path);
                InputStream fileStream = new FileInputStream(new File(idp_cert_path));
                certificate = (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(fileStream);
                fileStream.close();
            } else {
                certificate = xmlSignature.getKeyInfo().getX509Certificate();
            }
            System.err.println("Certificate SigAlgName: " + certificate.getSigAlgName());
            //boolean validate = xmlSignature.checkSignatureValue(certificate);
            //if (!validate) {
            //    System.out.println("xmlSignature.checkSignatureValue is false.");
            //}

            X509EncodedKeySpec publicKeySpec = new X509EncodedKeySpec(certificate.getPublicKey().getEncoded());
            KeyFactory keyFactory = KeyFactory.getInstance("RSA");
            PublicKey key = keyFactory.generatePublic(publicKeySpec);
            BasicX509Credential publicCredential = new BasicX509Credential();
            publicCredential.setPublicKey(key);
            SignatureValidator signatureValidator = new SignatureValidator(publicCredential);
            signatureValidator.validate(signature);

            // No error meas all good
            System.out.println("All good.");
        } catch (Exception e) {
            System.err.println("=== Exception ========================");
            e.printStackTrace();
        }
    }

    private static String readfile(String filePath) throws FileNotFoundException {
        Scanner scanner = new Scanner(new File(filePath));
        scanner.useDelimiter("\\Z");
        String contents = scanner.next();
        scanner.close();
        return contents;
    }

    private static XMLObject unmarshall(String samlString) {
        DocumentBuilderFactory documentBuilderFactory = DocumentBuilderFactory.newInstance();
        documentBuilderFactory.setNamespaceAware(true);
        try {
            DocumentBuilder docBuilder = documentBuilderFactory.newDocumentBuilder();
            ByteArrayInputStream is = new ByteArrayInputStream(samlString.getBytes());
            Document document = docBuilder.parse(is);
            Element element = document.getDocumentElement();
            UnmarshallerFactory unmarshallerFactory = Configuration.getUnmarshallerFactory();
            Unmarshaller unmarshaller = unmarshallerFactory.getUnmarshaller(element);
            return unmarshaller.unmarshall(element);
        } catch (Exception e) {
            e.printStackTrace();
        }

        return null;
    }
}
