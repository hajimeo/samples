/**
 * curl -O https://raw.githubusercontent.com/hajimeo/samples/master/java/CauseOOMEThread.java
 * javac CauseOOMEThread.java
 * java CauseOOMEThread
 */

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

class CauseOOMEThread {
    private void OOMEing(int maxThread, int waitIntervalMs) throws Exception {
        for (int i = 0; i < maxThread; i++) {
            try {
                if (i % 1000 == 0) {
                    CauseOOMEThread.log("Creating thread " + (i + 1));
                    if (waitIntervalMs > 0)
                        Thread.sleep(waitIntervalMs);
                }
                new Thread(() -> {
                    try {
                        Thread.sleep(600000);
                    } catch (InterruptedException e) {
                        CauseOOMEThread.log("Interrupted " + this.toString());
                    }
                }).start();
            } catch (OutOfMemoryError e) {
                e.printStackTrace();
                log("Completed test. (thread: " + i + ")");
                System.exit(100);
            }
        }
        CauseOOMEThread.log("Finished creating " + maxThread + " threads");
    }

    private static String getCurrentLocalDateTimeStamp() {
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"));
    }

    private static void log(String msg) {
        System.err.println("[" + getCurrentLocalDateTimeStamp() + "] " + msg);
    }

    public static void main(String[] args) throws Exception {
        int maxThread = (args.length > 0) ? Integer.parseInt(args[0]) : 100000;
        int waitIntervalMs = (args.length > 1) ? Integer.parseInt(args[1]) : 100;

        if (maxThread > 0) {
            CauseOOMEThread cl = new CauseOOMEThread();
            log("Starting test with max threads=" + maxThread + " with interval=" + waitIntervalMs + " ms (every 100 threads) ...");
            cl.OOMEing(maxThread, waitIntervalMs);
            System.exit(0);
        }
    }
}