/**
 * curl -O https://raw.githubusercontent.com/hajimeo/samples/master/java/CauseOOMEOverhead.java
 * javac CauseOOME.java
 * java -Xmx100m -XX:+UseParallelGC -XX:+PrintClassHistogramAfterFullGC CauseOOMEOverhead | grep -F '#instances' -A
 *
 * Ref: https://plumbr.io/outofmemoryerror/gc-overhead-limit-exceeded
 */

import java.util.Map;
import java.util.Random;

class CauseOOMEOverhead {
    public static void main(String args[]) {
        Map map = System.getProperties();
        Random r = new Random();
        // Create small instances many times
        while (true) {
            map.put(r.nextInt(), "value");
        }
    }
}