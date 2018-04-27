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
            if (i % 100 == 0)
                CauseOOMEThread.log("Creating thread "+i);
            new Thread(() -> {
                try {
                    Thread.sleep(600000);
                } catch (InterruptedException e) {
                    CauseOOMEThread.log("Interrupted "+this.toString());
                }
            }).start();
            if (waitIntervalMs > 0)
                Thread.sleep(waitIntervalMs);
        }
        CauseOOMEThread.log("Finished creating "+maxThread+" threads");
    }

    private static String getCurrentLocalDateTimeStamp() {
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"));
    }

    private static void log(String msg) {
        System.err.println("[" + getCurrentLocalDateTimeStamp() + "] " + msg);
    }

    public static void main(String[] args) throws Exception {
        int maxThread = (args.length > 0) ? Integer.parseInt(args[0]) : 100000;
        int waitIntervalMs = (args.length > 1) ? Integer.parseInt(args[1]) : 0;

        if (maxThread > 0) {
            CauseOOMEThread cl = new CauseOOMEThread();
            log("Starting test with max threads=" + maxThread + " ...");
            try {
                cl.OOMEing(maxThread, waitIntervalMs);
            } catch (OutOfMemoryError e) {
                e.printStackTrace();
                log("Completed test. (Free Mem: " + Runtime.getRuntime().freeMemory() + ")");
                System.exit(100);
            }
        }
    }
}