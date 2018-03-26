/**
 * curl -O https://raw.githubusercontent.com/hajimeo/samples/master/java/CauseOOME.java
 * javac CauseOOME.java
 * java -verbose:gc -Xmx16m CauseOOME
 * java -verbose:gc -XX:+PrintGCDetails -Xmx16m CauseOOME
 * java -verbose:gc -XX:+PrintClassHistogramBeforeFullGC -Xmx16m CauseOOME
 */

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

public class CauseOOME {
    private void OOMEing(int initSize, int maxIteration) throws Exception {
        List<long[]> _list = new LinkedList<long[]>();
        int size = initSize;
        for (int i = 1; i < maxIteration; i++) {
            log("Free Mem: " + Runtime.getRuntime().freeMemory() + " (adding " + size + ")");
            _list.add(new long[size]);
            Thread.sleep(1000);
            size = (int)(size * Math.sqrt(i))+initSize;
        }
    }

    private static String getCurrentLocalDateTimeStamp() {
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"));
    }

    private static void log(String msg) {
        System.err.println("[" + getCurrentLocalDateTimeStamp() + "] " + msg);
    }

    public static void main(String[] args) throws Exception {
        int size = (args.length > 0) ? Integer.parseInt(args[0]) : 1024;
        int maxIteration = (args.length > 1) ? Integer.parseInt(args[1]) : 100;

        CauseOOME test = new CauseOOME();
        log("Starting test with initial size=" + size + " / loop=" + maxIteration + "...");
        try {
            test.OOMEing(size, maxIteration);
        } catch (OutOfMemoryError e) {
            e.printStackTrace();
            log("Completed test.");
        }
    }
}