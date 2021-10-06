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
    TLSServer tlss = new TLSServer();
    try {
      tlss.serve(Integer.parseInt(args[1]), args[2], args[3], args[4].toCharArray(), args[5], args[6].toCharArray());
    }
    catch (Exception e) {
      e.printStackTrace();
    }
  }

  public void serve(
      int port, String tlsVersion, String trustStoreName,
      char[] trustStorePassword, String keyStoreName, char[] keyStorePassword)
      throws Exception
  {

    Objects.requireNonNull(tlsVersion, "TLS version is mandatory");

    if (port <= 0) {
      throw new IllegalArgumentException(
          "Port number cannot be less than or equal to 0");
    }

    KeyStore trustStore = KeyStore.getInstance(KeyStore.getDefaultType());
    InputStream tstore = TLSServer.class
        .getResourceAsStream("/" + trustStoreName);
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