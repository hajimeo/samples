/*
 *
 * Copyright (c) 1994, 2004, Oracle and/or its affiliates. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or
 * without modification, are permitted provided that the following
 * conditions are met:
 *
 * -Redistribution of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *
 * Redistribution in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in
 * the documentation and/or other materials provided with the
 * distribution.
 *
 * Neither the name of Oracle nor the names of
 * contributors may be used to endorse or promote products derived
 * from this software without specific prior written permission.
 *
 * This software is provided "AS IS," without a warranty of any
 * kind. ALL EXPRESS OR IMPLIED CONDITIONS, REPRESENTATIONS AND
 * WARRANTIES, INCLUDING ANY IMPLIED WARRANTY OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT, ARE HEREBY
 * EXCLUDED. SUN MICROSYSTEMS, INC. ("SUN") AND ITS LICENSORS SHALL
 * NOT BE LIABLE FOR ANY DAMAGES SUFFERED BY LICENSEE AS A RESULT
 * OF USING, MODIFYING OR DISTRIBUTING THIS SOFTWARE OR ITS
 * DERIVATIVES. IN NO EVENT WILL SUN OR ITS LICENSORS BE LIABLE FOR
 * ANY LOST REVENUE, PROFIT OR DATA, OR FOR DIRECT, INDIRECT,
 * SPECIAL, CONSEQUENTIAL, INCIDENTAL OR PUNITIVE DAMAGES, HOWEVER
 * CAUSED AND REGARDLESS OF THE THEORY OF LIABILITY, ARISING OUT OF
 * THE USE OF OR INABILITY TO USE THIS SOFTWARE, EVEN IF SUN HAS
 * BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
 *
 * You acknowledge that this software is not designed, licensed or
 * intended for use in the design, construction, operation or
 * maintenance of any nuclear facility.
 */

import java.net.*;
import java.io.*;

import javax.net.ssl.*;

import java.security.KeyStore;
import java.security.cert.X509Certificate;

/*
 * This example shows how to set up a key manager to do client
 * authentication if required by server.
 *
 * This program assumes that the client is not inside a firewall.
 * The application can be modified to connect to a server outside
 * the firewall by following SSLSocketClientWithTunneling.java.
 *
 * java -Djavax.net.debug=ssl,keymanager -Djavax.net.ssl.trustStore=some_truststore_to_trust_remote.jks \
 *     SSLSocketClientWithClientAuth ./some_test_keystore.jks password 127.0.0.1 6182 /path/to/request [true]
 */
public class SSLSocketClientWithClientAuth
{
  private static void disableSSLValidation(SSLContext sslContext, KeyManagerFactory kmf) throws Exception {
    X509TrustManager customTm = new X509TrustManager() {
      @Override
      public void checkClientTrusted(final java.security.cert.X509Certificate[] chain, final String authType)
      {

      }

      @Override
      public void checkServerTrusted(final java.security.cert.X509Certificate[] chain, final String authType)
      {

      }

      @Override
      public X509Certificate[] getAcceptedIssuers() {
        return new X509Certificate[0];
      }
    };

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
    String keyPath = "";
    String password = "";
    String host = "";
    int port = -1;
    String path = "";
    boolean ignore = false;

    try {
      keyPath = args[0];
      password = args[1];
      host = args[2];
      port = Integer.parseInt(args[3]);
      path = args[4];
      if (args.length > 5) {
        ignore = true;
      }
    }
    catch (IllegalArgumentException e) {
      System.out.println("USAGE: java SSLSocketClientWithClientAuth idStore.jks passphrase host port /path/to/request");
      System.exit(-1);
    }

    try {
      /*
       * Set up a key manager for client authentication
       * if asked by the server.  Use the implementation's
       * default TrustStore and secureRandom routines.
       */
      SSLSocketFactory factory = null;
      SSLContext ctx;
      KeyManagerFactory kmf;
      KeyStore ks;
      char[] passphrase = password.toCharArray();

      ctx = SSLContext.getInstance("TLS");
      kmf = KeyManagerFactory.getInstance("SunX509");
      ks = KeyStore.getInstance("JKS");
      ks.load(new FileInputStream(new File(keyPath)), passphrase);
      kmf.init(ks, passphrase);
      if (ignore) {
        disableSSLValidation(ctx, kmf);
      }
      else {
        ctx.init(kmf.getKeyManagers(), null, null);
      }
      factory = ctx.getSocketFactory();

      SSLSocket socket = (SSLSocket) factory.createSocket(host, port);

      /*
       * send http request
       *
       * See SSLSocketClient.java for more information about why
       * there is a forced handshake here when using PrintWriters.
       */
      socket.startHandshake();

      PrintWriter out = new PrintWriter(
          new BufferedWriter(
              new OutputStreamWriter(
                  socket.getOutputStream())));
      out.println("GET " + path + " HTTP/1.0");
      out.println();
      out.flush();

      /*
       * Make sure there were no surprises
       */
      if (out.checkError()) {
        System.out.println(
            "SSLSocketClient: java.io.PrintWriter error");
      }

      /* read response */
      BufferedReader in = new BufferedReader(
          new InputStreamReader(
              socket.getInputStream()));

      String inputLine;

      while ((inputLine = in.readLine()) != null) {
        System.out.println(inputLine);
      }

      in.close();
      out.close();
      socket.close();
    }
    catch (Exception e) {
      e.printStackTrace();
    }
  }
}