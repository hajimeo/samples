/**
 * curl -O https://raw.githubusercontent.com/hajimeo/samples/master/java/CauseOOMEThread.java
 * javac CauseOOMEThread.java
 * ulimit -u 10
 * java CauseOOMEThread 10
 */

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

class CauseOOMEThread {
    public class ConnectCaller implements Callable<String> {
        private String spec;

        public ConnectCaller(String spec) {
            this.spec = spec;
        }

        public String call() throws Exception {
            CauseOOMEThread.log("Called "+spec);
            return this.spec;
        }
    }

    public void OOMEing(int maxThread) throws Exception {
        ExecutorService executor = Executors.newFixedThreadPool(maxThread);
        String spec="";
        for (int i = 0; i < maxThread; i++) {
            spec="" + i;
            executor.submit(new ConnectCaller(spec));
            Thread.sleep(100);
        }
        executor.shutdown();
    }

    private static String getCurrentLocalDateTimeStamp() {
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"));
    }

    private static void log(String msg) {
        System.err.println("[" + getCurrentLocalDateTimeStamp() + "] " + msg);
    }

    public static void main(String[] args) throws Exception {
        int maxThread = (args.length > 0) ? Integer.parseInt(args[0]) : 10000;

        if (maxThread > 0) {
            CauseOOMEThread cl = new CauseOOMEThread();
            log("Starting test with max threads=" + maxThread + " ...");
            try {
                cl.OOMEing(maxThread);
            } catch (OutOfMemoryError e) {
                e.printStackTrace();
                log("You would not see this 'Completed test. (Free Mem: " + Runtime.getRuntime().freeMemory() + ")' message");
                System.exit(100);
            }
        }
    }
}