/**
 * curl -O https://raw.githubusercontent.com/hajimeo/samples/master/java/CauseOOMEOverhead.java
 * javac CauseOOMEOverhead.java
 * java -Xmx100m -XX:+UseParallelGC -verbose:gc -XX:GCTimeLimit=50 -XX:GCHeapFreeLimit=50 CauseOOMEOverhead
 * java -Xmx100m -XX:+UseParallelGC -XX:+PrintClassHistogramAfterFullGC CauseOOMEOverhead | grep -F '#instances' -A 4
 * <p>
 * Ref: https://plumbr.io/outofmemoryerror/gc-overhead-limit-exceeded
 */

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Map;
import java.util.Random;

class CauseOOMEOverhead {
    private static String getCurrentLocalDateTimeStamp() {
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"));
    }

    private static void log(String msg) {
        System.err.println("[" + getCurrentLocalDateTimeStamp() + "] " + msg);
    }

    public static void main(String args[]) {
        Map map = System.getProperties();
        Random r = new Random();
        // Create small instances many times
        while (true) {
            try {
                map.put(r.nextInt(), "value");
            } catch (OutOfMemoryError e) {
                e.printStackTrace();
                long f = Runtime.getRuntime().freeMemory();
                log("You would not see this 'Completed test. (Free Mem: " + f + ")' message");
                System.exit(100);
            }
        }
    }
}