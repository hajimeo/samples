/**
 * curl -O https://raw.githubusercontent.com/hajimeo/samples/master/java/CauseOOMEDirect.java
 * javac CauseOOMEDirect.java
 * java -verbose:gc -Xms8m -Xmx8m CauseOOMEDirect
 * java -XX:+PrintClassHistogramBeforeFullGC -Xmx8m CauseOOMEDirect | grep -F '#instances' -A 20
 */

import java.nio.ByteBuffer;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

public class CauseOOMEDirect {
    public void OOMEing(int maxIteration, int interval) throws Exception {

        for (int i = 1; i <= maxIteration; i++) {
            log("Allocating " + i * 1024 * 1024 + " (loop " + i + ")");
            ByteBuffer buffer = ByteBuffer.allocateDirect(i * 1024 * 1024);
            if (interval > 499) {
                log("Free Mem(heap): " + Runtime.getRuntime().freeMemory()/1024 + "KB | Native used: " + sun.misc.SharedSecrets.getJavaNioAccess().getDirectBufferPool().getMemoryUsed()/1024 + "KB / Max Direct: " + sun.misc.VM.maxDirectMemory()/1024 + "KB");
            }
            if (interval > 0)
                Thread.sleep(interval);
        }
    }

    private static String getCurrentLocalDateTimeStamp() {
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"));
    }

    private static void log(String msg) {
        System.err.println("[" + getCurrentLocalDateTimeStamp() + "] " + msg);
    }

    public static void main(String[] args) throws Exception {
        int maxIteration = (args.length > 0) ? Integer.parseInt(args[0]) : 10000;
        int interval = (args.length > 1) ? Integer.parseInt(args[1]) : 500;

        CauseOOMEDirect test = new CauseOOMEDirect();
        log("Starting test with max loop=" + maxIteration + " and interval=" + interval + " ...");
        try {
            test.OOMEing(maxIteration, interval);
        } catch (OutOfMemoryError e) {
            e.printStackTrace();
            log("Completed test. (Free Mem (heap): " + Runtime.getRuntime().freeMemory() + ")");
            System.exit(100);
        }
    }
}