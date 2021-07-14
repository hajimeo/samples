/*
 * Original: https://stackoverflow.com/questions/21223084/how-do-i-use-an-ssl-client-certificate-with-apache-httpclient
 *
 * java -Djavax.net.debug=ssl,keymanager -Djavax.net.ssl.trustStore=some_truststore_to_trust_remote.jks \
 *      -Ddebug=true -DkeyStore=./some_test_keystore.jks -DkeyStoreType=JKS -DkeyStorePassword=password \
 *      SSLSocketClientWithClientAuth https://127.0.0.1:6182/path/to/request [ignore]
 */

import java.io.FileInputStream;
import java.security.KeyStore;
import java.security.cert.X509Certificate;

import javax.net.ssl.HostnameVerifier;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSession;
import javax.net.ssl.X509TrustManager;

import org.apache.http.HttpEntity;
import org.apache.http.HttpResponse;
import org.apache.http.client.HttpClient;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.util.EntityUtils;

public class SSLClientWithKeyStore
{
  public static KeyStore readStore(String keypath, String keypwd, String keytype) throws Exception {
    KeyStore keyStore = KeyStore.getInstance(keytype);
    keyStore.load(new FileInputStream(keypath), keypwd.toCharArray());
    return keyStore;
  }

  public static void performClientRequest(String url, String keypath, String keypwd, String keytype, boolean ignore)
      throws Exception
  {
    KeyStore keyStore = readStore(keypath, keypwd, keytype);
    SSLContext sslContext = org.apache.http.ssl.SSLContexts.custom()
        .loadKeyMaterial(keyStore, keypwd.toCharArray())
        .build();
    if (ignore) {
      disableSSLValidation(sslContext, keyStore, keypwd);
    }

    HttpClient httpClient = HttpClients.custom().setSSLContext(sslContext).build();
    HttpResponse response = httpClient.execute(new HttpGet(url));
    HttpEntity entity = response.getEntity();

    System.err.println("# " + response.getStatusLine());
    //EntityUtils.consume(entity);
    String respBody = EntityUtils.toString(entity);
    System.out.println(respBody);
  }

  private static void disableSSLValidation(SSLContext sslContext, KeyStore keyStore, String keypwd) throws Exception {
    X509TrustManager customTm = new X509TrustManager()
    {
      @Override
      public void checkClientTrusted(final java.security.cert.X509Certificate[] chain, final String authType) {}

      @Override
      public void checkServerTrusted(final java.security.cert.X509Certificate[] chain, final String authType) {}

      @Override
      public X509Certificate[] getAcceptedIssuers() {
        return new X509Certificate[0];
      }
    };
    KeyManagerFactory kmf = KeyManagerFactory.getInstance("SunX509");
    kmf.init(keyStore, keypwd.toCharArray());
    sslContext.init(kmf.getKeyManagers(), new X509TrustManager[]{customTm}, null);

    HttpsURLConnection.setDefaultSSLSocketFactory(sslContext.getSocketFactory());
    HttpsURLConnection.setDefaultHostnameVerifier(new HostnameVerifier()
    {
      public boolean verify(String hostname, SSLSession session) {
        return true;
      }
    });
  }

  public static void main(String[] args) throws Exception {
    String debug = System.getProperty("debug", "false");
    if (debug.equalsIgnoreCase("true")) {
      System.setProperty("org.apache.commons.logging.Log", "org.apache.commons.logging.impl.SimpleLog");
      System.setProperty("org.apache.commons.logging.simplelog.showdatetime", "true");
      System.setProperty("org.apache.commons.logging.simplelog.log.org.apache.http", "DEBUG");
    }

    boolean ignore = false;
    String keypath = System.getProperty("keyStore", "./keystore.p12");
    String keypwd = System.getProperty("keyStorePassword", "password");
    String keytype = System.getProperty("keyStoreType", "PKCS12"); // "JKS" or "PKCS12"
    String url = args[0];
    if (args.length > 1) {
      ignore = true;
    }

    performClientRequest(url, keypath, keypwd, keytype, ignore);
  }
}