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
    public void OOMEing(int maxIteration, int interval) throws Exception {
        List<byte[]> _list = new LinkedList<byte[]>();
        int size;
        long maxMem = Runtime.getRuntime().maxMemory();

        for (int i = 0; i < maxIteration; i++) {
            long freeMem = Runtime.getRuntime().freeMemory();
            long freePer = (int) ((float) freeMem / maxMem * 100);

            if (freePer > 10) size = (int) ((maxMem - freeMem) * 0.10);
            else size = (int) ((maxMem - freeMem) * 0.01);

            if (interval > 499)
                log("Free Mem: " + freePer + "% (adding " + size + " bytes | loop " + (i + 1) + ")");

            byte[] b = new byte[size];
            /*
             * Do something against b in here
             */
            _list.add(b);
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

        CauseOOME test = new CauseOOME();
        log("Starting test with max loop=" + maxIteration + " and interval=" + interval + " ...");
        try {
            test.OOMEing(maxIteration, interval);
        } catch (OutOfMemoryError e) {
            e.printStackTrace();
            long f = Runtime.getRuntime().freeMemory();
            log("Completed test. (Free Mem: " + f + ")");
        }
    }
}