/*
 * from
 *  https://wiki.shibboleth.net/confluence/plugins/viewsource/viewpagesrc.action?pageId=3277047
 *  https://stackoverflow.com/questions/17890642/opensaml-2-0-signature-validation-not-working
 *  http://www.java2s.com/Tutorials/Java/org.w3c.dom/Document/0280__Document.getDocumentElement_.htm
 */

import org.opensaml.saml2.core.Response;
import org.opensaml.xml.io.Unmarshaller;
import org.opensaml.xml.io.UnmarshallerFactory;
import org.opensaml.*;
import org.opensaml.xml.io.UnmarshallingException;
import org.opensaml.xml.security.x509.BasicX509Credential;
import org.opensaml.xml.signature.SignatureValidator;
import org.opensaml.xml.validation.ValidationException;
import org.w3c.dom.Document;
import org.xml.sax.SAXException;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.ParserConfigurationException;
import java.io.*;
import java.security.KeyFactory;
import java.security.NoSuchAlgorithmException;
import java.security.PublicKey;
import java.security.cert.CertificateException;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.security.spec.InvalidKeySpecException;
import java.security.spec.X509EncodedKeySpec;

public class SignatureVarification {
    public static void main(String[] args) {
        try {
            String cert_path = args[0];
            String saml_xml = args[1];

            DocumentBuilderFactory builderFactory = DocumentBuilderFactory.newInstance();
            builderFactory.setNamespaceAware(true);       // Set namespace aware
            builderFactory.setValidating(true);           // and validating parser feaures
            builderFactory.setIgnoringElementContentWhitespace(true);
            DocumentBuilder builder = null;
            builder = builderFactory.newDocumentBuilder();  // Create the parser

            File samlXmlFile = new File(saml_xml);
            Document document = builder.parse(samlXmlFile);
            UnmarshallerFactory unmarshallerFactory = Configuration.getUnmarshallerFactory();
            Unmarshaller unmarshaller = unmarshallerFactory.getUnmarshaller(document.getDocumentElement());
            Response response = (Response) unmarshaller.unmarshall(document.getDocumentElement());

            //Get Public Key
            BasicX509Credential publicCredential = new BasicX509Credential();
            File publicKeyFile = new File(cert_path);

            if (publicKeyFile.exists()) {
                CertificateFactory certificateFactory = CertificateFactory.getInstance("X.509");
                InputStream fileStream = new FileInputStream(publicKeyFile);
                X509Certificate certificate = (X509Certificate) certificateFactory.generateCertificate(fileStream);
                fileStream.close();

                X509EncodedKeySpec publicKeySpec = new X509EncodedKeySpec(certificate.getPublicKey().getEncoded());
                KeyFactory keyFactory = KeyFactory.getInstance("RSA");
                PublicKey key = keyFactory.generatePublic(publicKeySpec);

                //Validate Public Key against Signature
                if (key != null) {
                    publicCredential.setPublicKey(key);
                    SignatureValidator signatureValidator = new SignatureValidator(publicCredential);
                    signatureValidator.validate(response.getSignature());
                }
            }

            // No error meas all good
            System.out.println("All good.");
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
