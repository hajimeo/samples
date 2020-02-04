// @see: https://www.snaplogic.com/glossary/two-way-ssl-java-example

public class SSLMutualAuthTest
{
  public SSLMutualAuthTest() {
    // TODO Auto-generated constructor stub
  }

  public static void main(String[] args) {

    System.out.println("MagicDude4Eva 2-way / mutual SSL-authentication test");
    try {
      String CERT_ALIAS = "myalias", CERT_PASSWORD = "mypassword";
      KeyStore identityKeyStore = KeyStore.getInstance("jks");
      FileInputStream identityKeyStoreFile = new FileInputStream(new File("identity.jks"));
      identityKeyStore.load(identityKeyStoreFile, CERT_PASSWORD.toCharArray());
      KeyStore trustKeyStore = KeyStore.getInstance("jks");
      FileInputStream trustKeyStoreFile = new FileInputStream(new File("truststore.jks"));
      trustKeyStore.load(trustKeyStoreFile, CERT_PASSWORD.toCharArray());

      SSLContext sslContext = SSLContexts.custom()
          // load identity keystore
          .loadKeyMaterial(identityKeyStore, CERT_PASSWORD.toCharArray(), new PrivateKeyStrategy()
          {
            @Override
            public String chooseAlias(Map<String, PrivateKeyDetails> aliases, Socket socket) {
              return CERT_ALIAS;
            }
          })
          // load trust keystore
          .loadTrustMaterial(trustKeyStore, null)
          .build();

      SSLConnectionSocketFactory sslConnectionSocketFactory = new SSLConnectionSocketFactory(sslContext,
          new String[]{"TLSv1.2", "TLSv1.1"},
          null,
          SSLConnectionSocketFactory.getDefaultHostnameVerifier());

      CloseableHttpClient client = HttpClients.custom()
          .setSSLSocketFactory(sslConnectionSocketFactory)
          .build();

      // Call a SSL-endpoint
      callEndPoint(client, "https://secure.server.com/endpoint",
          new JSONObject()
              .put("param1", "value1")
              .put("param2", "value2")
      );
    }
    catch (Exception ex) {
      System.out.println("Boom, we failed: " + ex);
      ex.printStackTrace();
    }
  }

  private static void callEndPoint(CloseableHttpClient aHTTPClient, String aEndPointURL, JSONObject aPostParams) {
    try {
      System.out.println("Calling URL: " + aEndPointURL);
      HttpPost post = new HttpPost(aEndPointURL);
      post.setHeader("Accept", "application/json");
      post.setHeader("Content-type", "application/json");
      StringEntity entity = new StringEntity(aPostParams.toString());
      post.setEntity(entity);
      System.out.println("**POST** request Url: " + post.getURI());
      System.out.println("Parameters : " + aPostParams);
      HttpResponse response = aHTTPClient.execute(post);
      int responseCode = response.getStatusLine().getStatusCode();
      System.out.println("Response Code: " + responseCode);
      System.out.println("Content:-\n");
      BufferedReader rd = new BufferedReader(new InputStreamReader(response.getEntity().getContent()));
      String line = "";
      while ((line = rd.readLine()) != null) {
        System.out.println(line);
      }
    }
    catch (Exception ex) {
      System.out.println("Boom, we failed: " + ex);
      ex.printStackTrace();
    }
  }
}