/**
 * curl -O https://raw.githubusercontent.com/hajimeo/samples/master/java/CauseOOME.java
 * javac CauseOOME.java
 * java -verbose:gc -XX:+PrintGCDetails -Xmx8m CauseOOME
 * java -XX:+PrintClassHistogramBeforeFullGC -Xmx8m CauseOOME | grep -F '#instances' -A 20
 */

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

public class CauseOOME {
    private void OOMEing(int initSize, int maxIteration) throws Exception {
        List<byte[]> _list = new LinkedList<byte[]>();
        int size = initSize;
        long f;
        for (int i = 0; i < maxIteration; i++) {
            f = Runtime.getRuntime().freeMemory();
            if (f > (10*size))
                size = initSize * (i + 1);
            else
                size = (int) (initSize * Math.sqrt((i + 1)));

            log("Free Mem: " + f + " (adding " + size + " bytes / loop " + (i + 1) + ")");
            byte[] b = new byte[size];
            _list.add(b);
            Thread.sleep(500);
        }
    }

    private static String getCurrentLocalDateTimeStamp() {
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"));
    }

    private static void log(String msg) {
        System.err.println("[" + getCurrentLocalDateTimeStamp() + "] " + msg);
    }

    public static void main(String[] args) throws Exception {
        int size = (args.length > 0) ? Integer.parseInt(args[0]) : 10240;
        int maxIteration = (args.length > 1) ? Integer.parseInt(args[1]) : 10000;

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