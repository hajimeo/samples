/* DID NOT WORK !! */

import org.openjdk.btrace.core.annotations.*;
import static org.openjdk.btrace.core.BTraceUtils.*;

@BTrace(trusted = true)
public class NexusFlushDelay {
    private static final long DELAY_MS = 60000;

    @OnMethod(
            clazz = "org.sonatype.nexus.content.maven.internal.browse.Maven2BrowseNodeGenerator",
            method = "computeAssetPaths"
    )
    public static void onEntry() {
        println("[NexusFlushDelay] computeAssetPaths entered on thread "
                + Thread.currentThread().getName()
                + " -- holding flushMutex, sleeping " + DELAY_MS + "ms to simulate a slow DB lazy-load");
        try {
            Thread.sleep(DELAY_MS);
        } catch (InterruptedException e) {
            println("[NexusFlushDelay] sleep interrupted");
        }
        println("[NexusFlushDelay] computeAssetPaths resuming after delay on thread "
                + Thread.currentThread().getName());
    }
}