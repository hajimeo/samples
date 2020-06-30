/*
 * Testing 2-way SSL (Client Certificate Authentication)
 *
 * @see: https://www.snaplogic.com/glossary/two-way-ssl-java-example
 *
 * Example output
 * $ java -jar target/SSLMutualAuth-1.0-SNAPSHOT.jar https://dh1.standalone.localdomain:28070/ ../../misc/standalone.localdomain.jks "standalone.localdomain" "password"
 * MagicDude4Eva 2-way / mutual SSL-authentication test
 * Calling URL: https://dh1.standalone.localdomain:28070/
 * **POST** request Url: https://dh1.standalone.localdomain:28070/
 * Parameters : {}
 * Response Code: 200
 * Content:-
 *
 * hello
 *
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
    log("MagicDude4Eva 2-way / mutual SSL-authentication test");
    try {
      String aEndPointURL = args[0];
      String idStorePath = args[1]; // Currently using as TrustStore as well
      String certAlias = args[2];
      String idStorePwd = args[3];
      String[] supportedProtocols = {"TLSv1.2", "TLSv1.1"};

      SSLMutualAuthTest.CERT_ALIAS = certAlias;
      KeyStore identityKeyStore = KeyStore.getInstance("jks");
      FileInputStream identityKeyStoreFile = new FileInputStream(new File(idStorePath));
      identityKeyStore.load(identityKeyStoreFile, idStorePwd.toCharArray());
      KeyStore trustKeyStore = KeyStore.getInstance("jks");
      FileInputStream trustKeyStoreFile = new FileInputStream(new File(idStorePath));
      trustKeyStore.load(trustKeyStoreFile, idStorePwd.toCharArray());

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
    }
  }

  private static void callEndPoint(CloseableHttpClient aHTTPClient, String aEndPointURL, JSONObject aPostParams) {
    try {
      log("Calling URL: " + aEndPointURL);
      HttpPost post = new HttpPost(aEndPointURL);
      post.setHeader("Accept", "application/json");
      post.setHeader("Content-type", "application/json");
      StringEntity entity = new StringEntity(aPostParams.toString());
      post.setEntity(entity);
      log("**POST** request Url: " + post.getURI());
      log("Parameters : " + aPostParams);
      HttpResponse response = aHTTPClient.execute(post);
      int responseCode = response.getStatusLine().getStatusCode();
      log("Response Code: " + responseCode);
      log("Content:-\n");
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