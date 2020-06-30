/*
 * Testing 2-way SSL (Client Certificate Authentication)
 * @see: https://www.snaplogic.com/glossary/two-way-ssl-java-example
 *
 * Example command with output:
 * =================================================
 * $ java -Djavax.net.debug=ssl,keymanager -Djavax.net.ssl.trustStore="../../misc/standalone.localdomain.jks" \
 *    -Djavax.net.ssl.keyStore="../../misc/standalone.localdomain.jks" -Djavax.net.ssl.keyStorePassword="password" \
 *    -jar target/SSLMutualAuth-1.0-SNAPSHOT.jar "standalone.localdomain" https://dh1.standalone.localdomain:28070/
 * POST request Url: https://dh1.standalone.localdomain:28070/
 *  with parameters: {}
 * Response Code: 200
 *       Content: (below)
 * hello
 * =================================================
 */

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.net.Socket;
import java.security.KeyStore;
import java.util.Map;

import javax.net.ssl.SSLContext;

import org.apache.http.HttpResponse;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.conn.ssl.SSLConnectionSocketFactory;
import org.apache.http.entity.StringEntity;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.ssl.PrivateKeyDetails;
import org.apache.http.ssl.PrivateKeyStrategy;
import org.apache.http.ssl.SSLContexts;
import org.apache.http.ssl.SSLContextBuilder;
import org.json.JSONObject;

public class SSLMutualAuthTest
{
  public SSLMutualAuthTest() {
    // TODO Auto-generated constructor stub
  }

  static String CERT_ALIAS;

  public static void main(String[] args) {
    try {
      String certAlias = args[0];
      String aEndPointURL = args[1];
      String[] supportedProtocols = {"TLSv1.2", "TLSv1.1"};

      String idStorePath = System.getProperty("javax.net.ssl.keyStore");
      String idStorePwd = System.getProperty("javax.net.ssl.keyStorePassword", "changeit");
      String trustStorePath = System.getProperty("javax.net.ssl.trustStore", idStorePath);
      String trustStorePwd = System.getProperty("javax.net.ssl.trustStorePassword", idStorePwd);
      String storeType = System.getProperty("javax.net.ssl.keyStoreType", "jks");

      SSLMutualAuthTest.CERT_ALIAS = certAlias;
      KeyStore identityKeyStore = KeyStore.getInstance(storeType);
      FileInputStream identityKeyStoreFile = new FileInputStream(new File(idStorePath));
      identityKeyStore.load(identityKeyStoreFile, idStorePwd.toCharArray());
      KeyStore trustKeyStore = KeyStore.getInstance(storeType);
      FileInputStream trustKeyStoreFile = new FileInputStream(new File(trustStorePath));
      trustKeyStore.load(trustKeyStoreFile, trustStorePwd.toCharArray());

      SSLContext sslContext = SSLContexts.custom()
          .loadKeyMaterial(identityKeyStore, idStorePwd.toCharArray(), new PrivateKeyStrategy()
          {
            @Override
            public String chooseAlias(Map<String, PrivateKeyDetails> aliases, Socket socket) {
              return SSLMutualAuthTest.CERT_ALIAS;
            }
          })
          // load trust keystore
          .loadTrustMaterial(trustKeyStore, null)
          .build();

      SSLConnectionSocketFactory sslConnectionSocketFactory =
          new SSLConnectionSocketFactory(sslContext, supportedProtocols, null,
              SSLConnectionSocketFactory.getDefaultHostnameVerifier());

      CloseableHttpClient client = HttpClients.custom()
          .setSSLSocketFactory(sslConnectionSocketFactory)
          .build();

      // Call a SSL-endpoint
      callEndPoint(client, aEndPointURL, new JSONObject());
    }
    catch (Exception ex) {
      log("Exception: " + ex.getMessage());
      ex.printStackTrace();
      log("USAGE:" +
          "java -Djavax.net.debug=ssl,keymanager -Djavax.net.ssl.trustStore=some_truststore_to_trust_remote.jks \\\n" +
          "   -Djavax.net.ssl.keyStore=\"/path/to/yourIdStore.jks\" -Djavax.net.ssl.keyStorePassword=\"password\" \\\n" +
          "   -jar target/SSLMutualAuth-1.0-SNAPSHOT.jar \"certificate-alias-name\" https://some-sever-fqdn:port/");
      System.exit(1);
    }
  }

  private static void callEndPoint(CloseableHttpClient aHTTPClient, String aEndPointURL, JSONObject aPostParams) {
    try {
      HttpPost post = new HttpPost(aEndPointURL);
      post.setHeader("Accept", "application/json");
      post.setHeader("Content-type", "application/json");
      StringEntity entity = new StringEntity(aPostParams.toString());
      post.setEntity(entity);
      log("POST request Url: " + post.getURI());
      log(" with parameters: " + aPostParams);
      HttpResponse response = aHTTPClient.execute(post);
      int responseCode = response.getStatusLine().getStatusCode();
      log("Response Code: " + responseCode);
      log("      Content: (below)");
      BufferedReader rd = new BufferedReader(new InputStreamReader(response.getEntity().getContent()));
      String line = "";
      while ((line = rd.readLine()) != null) {
        log(line);
      }
    }
    catch (Exception ex) {
      log("Exception: " + ex.getMessage());
      ex.printStackTrace();
    }
  }

  private static void log(String msg) {
    System.err.println(msg);
  }
}