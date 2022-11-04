// TODO: Probably does NOT work.
/*
 * java -Djavax.net.ssl.keyStore=/var/tmp/share/cert/standalone.localdomain.jks -Djavax.net.ssl.keyStorePassword=password -Djavax.net.ssl.trustStore=$JAVA_HOME/jre/lib/security/cacerts -Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.keyStoreType=jks -jar ./TLSServer-1.0-SNAPSHOT.jar
 */

import java.io.FileInputStream;
import java.io.InputStream;
import java.io.PrintWriter;
import java.net.ServerSocket;
import java.net.Socket;
import java.security.KeyStore;
import java.security.SecureRandom;
import java.util.Objects;

import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLServerSocket;
import javax.net.ssl.SSLServerSocketFactory;
import javax.net.ssl.TrustManagerFactory;

/*
 * keytool -genkeypair -alias server -keyalg EC \
 * -sigalg SHA384withECDSA -keysize 256 -keystore servercert.p12 \
 * -storetype pkcs12 -v -storepass abc123 -validity 10000 -ext san=ip:127.0.0.1
 */

public class TLSServer
{
  public static void main(String[] args) {
    String keyStorePath = System.getProperty("javax.net.ssl.keyStore");
    String keyStorePwd = System.getProperty("javax.net.ssl.keyStorePassword", "changeit");
    String trustStorePath = System.getProperty("javax.net.ssl.trustStore", keyStorePath);
    String trustStorePwd = System.getProperty("javax.net.ssl.trustStorePassword", keyStorePwd);
    String storeType = System.getProperty("javax.net.ssl.keyStoreType", "jks");

    try {
      int port = 8080;
      if (args.length > 1) {
        port = Integer.parseInt(args[1]);
      }
      String tlsV = "TLSv1.2";
      if (args.length > 2) {
        tlsV = args[2];
      }

      TLSServer tlss = new TLSServer();
      tlss.serve(port, tlsV, trustStorePath, trustStorePwd.toCharArray(), keyStorePath,
          trustStorePwd.toCharArray(), storeType);
    }
    catch (Exception e) {
      e.printStackTrace();
    }
  }

  public void serve(
      int port, String tlsVersion, String trustStoreName,
      char[] trustStorePassword, String keyStoreName, char[] keyStorePassword, String storeType)
      throws Exception
  {
    Objects.requireNonNull(tlsVersion, "TLS version is mandatory");

    if (storeType.isEmpty()) {
      storeType = KeyStore.getDefaultType();
    }
    // TODO: not working. tstore becomes null
    KeyStore trustStore = KeyStore.getInstance(storeType);
    InputStream tstore = new FileInputStream(trustStoreName);
    trustStore.load(tstore, trustStorePassword);
    tstore.close();
    TrustManagerFactory tmf = TrustManagerFactory
        .getInstance(TrustManagerFactory.getDefaultAlgorithm());
    tmf.init(trustStore);

    KeyStore keyStore = KeyStore.getInstance(KeyStore.getDefaultType());
    InputStream kstore = TLSServer.class
        .getResourceAsStream("/" + keyStoreName);
    keyStore.load(kstore, keyStorePassword);
    KeyManagerFactory kmf = KeyManagerFactory
        .getInstance(KeyManagerFactory.getDefaultAlgorithm());
    kmf.init(keyStore, keyStorePassword);
    SSLContext ctx = SSLContext.getInstance("TLS");
    ctx.init(kmf.getKeyManagers(), tmf.getTrustManagers(),
        SecureRandom.getInstanceStrong());

    SSLServerSocketFactory factory = ctx.getServerSocketFactory();
    try (ServerSocket listener = factory.createServerSocket(port)) {
      SSLServerSocket sslListener = (SSLServerSocket) listener;

      sslListener.setNeedClientAuth(true);
      sslListener.setEnabledProtocols(new String[]{tlsVersion});
      // NIO to be implemented
      while (true) {
        try (Socket socket = sslListener.accept()) {
          PrintWriter out = new PrintWriter(socket.getOutputStream(), true);
          out.println("Connected!");
        }
        catch (Exception e) {
          e.printStackTrace();
        }
      }
    }
  }
}