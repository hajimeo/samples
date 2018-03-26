/**
 * curl -O https://raw.githubusercontent.com/hajimeo/samples/master/java/CauseLeaking.java
 * javac CauseLeaking.java
 * java -verbose:gc -XX:+PrintGCDetails -Xmx4m CauseLeaking
 * java -XX:+PrintClassHistogramBeforeFullGC -Xmx4m CauseLeaking 2>&1 | grep Socket
 */

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;

public class CauseLeaking {
    private static int port = 18000;
    private static HttpServer server;

    static class MyHandler implements HttpHandler {
        @Override
        public void handle(HttpExchange t) throws IOException {
            String response = "Hello World!!";
            t.sendResponseHeaders(200, response.length());
            OutputStream os = t.getResponseBody();
            os.write(response.getBytes());
            os.close();
        }
    }

    private static void startWebServer(int port) throws IOException {
        server = HttpServer.create(new InetSocketAddress(port), 0);
        server.createContext("/test.txt", new MyHandler());
        server.setExecutor(null);
        server.start();
    }

    private static void stopWebServer() throws IOException {
        server.stop(0);
    }

    private void OOMEing(int maxIteration) throws Exception {
        for (int i = 0; i < maxIteration; i++) {
            if ((i % 100) == 0) {
                log("Free Mem: " + Runtime.getRuntime().freeMemory() + " (loop " + (i + 1) + ")");
                Thread.sleep(1000);
            }

            Socket s = new Socket(InetAddress.getLocalHost(), port);
            // I'm supposed to try clearing this object (but not right way)...
            s = null;
        }
    }

    private static String getCurrentLocalDateTimeStamp() {
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"));
    }

    private static void log(String msg) {
        System.err.println("[" + getCurrentLocalDateTimeStamp() + "] " + msg);
    }

    public static void main(String[] args) throws Exception {
        port = (args.length > 0) ? Integer.parseInt(args[0]) : 18000;
        int maxIteration = (args.length > 1) ? Integer.parseInt(args[1]) : 10000;
        startWebServer(port);

        CauseLeaking test = new CauseLeaking();
        log("Starting test with port " + port + " / loop=" + maxIteration + "...");
        try {
            test.OOMEing(maxIteration);
        } catch (OutOfMemoryError e) {
            e.printStackTrace();
        }

        log("Completed test.");
        stopWebServer();
    }
}