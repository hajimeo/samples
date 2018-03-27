/**
 * curl -O https://raw.githubusercontent.com/hajimeo/samples/master/java/CauseLeaking.java
 * javac CauseLeaking.java
 * java -verbose:gc -XX:+PrintGCDetails -Xmx4m CauseLeaking
 * java -XX:+PrintClassHistogramBeforeFullGC -Xmx4m CauseLeaking | grep -F '#instances' -A 20
 *
 * Ref: https://qiita.com/mmmm/items/f33b757119fc4dbd6aa1
 */

import java.io.*;
import java.net.*;
import java.util.*;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.*;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;

public class CauseLeaking {
    private static HttpServer httpServer;
    private static String httpPath = "/test.txt";
    private static String httpResponse = "Hello World!\n";

    public static class MyHandler implements HttpHandler {
        @Override
        public void handle(HttpExchange he) throws IOException {
            int loop = 5;
            he.sendResponseHeaders(200, (httpResponse.length() * loop));
            OutputStream os = he.getResponseBody();
            for (int i = 0; i < loop; i++) {
                os.write(httpResponse.getBytes());
                try {
                    Thread.sleep(200);
                } catch (InterruptedException e) {
                    log("InterruptedException happened. but ignoring...");
                }
            }
            os.close();
        }
    }

    public class ConnectCaller implements Callable<InputStream> {
        private String spec;

        public ConnectCaller(String spec) {
            this.spec = spec;
        }

        public InputStream call() throws Exception {
            URL url = new URL(this.spec);
            InputStream is = url.openStream();
            return is;
        }
    }

    private static void startWebServer(int port) throws IOException {
        httpServer = HttpServer.create(new InetSocketAddress(port), 0);
        httpServer.createContext(httpPath, new MyHandler());
        httpServer.setExecutor(null);
        httpServer.start();
    }

    private static void stopWebServer() throws IOException {
        httpServer.stop(0);
    }

    private void OOMEing(int maxIteration, String spec) throws Exception {
        int numThreads = 50;
        List<Future<InputStream>> _list = new ArrayList<Future<InputStream>>();
        ExecutorService executor = Executors.newFixedThreadPool(numThreads);
        for (int i = 0; i < maxIteration; i++) {
            if (i % numThreads == 0)
                log("Free Mem: " + Runtime.getRuntime().freeMemory() + " (loop " + (i + 1) + ")");
            _list.add(executor.submit(new ConnectCaller(spec)));
            Thread.sleep(100);
        }
    }

    private static String getCurrentLocalDateTimeStamp() {
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"));
    }

    private static void log(String msg) {
        System.err.println("[" + getCurrentLocalDateTimeStamp() + "] " + msg);
    }

    public static void main(String[] args) throws Exception {
        int port = (args.length > 0) ? Integer.parseInt(args[0]) : 18000;
        int maxIteration = (args.length > 1) ? Integer.parseInt(args[1]) : 10000;
        startWebServer(port);

        if (maxIteration > 0) {
            String spec = "http://localhost:" + port + httpPath;
            CauseLeaking cl = new CauseLeaking();
            log("Starting test with port " + port + " / loop=" + maxIteration + " / url=" + spec + " ...");
            try {
                cl.OOMEing(maxIteration, spec);
            } catch (OutOfMemoryError e) {
                e.printStackTrace();
                log("Completed test.");
                stopWebServer();
                System.exit(0);
            }
        }
    }
}