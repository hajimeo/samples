/**
 * NOTE:
 * Do not forget to replace 'clazz' values (and 'OnTimer' integer)
 * May want to append " | tee btraceProfiling.tsv"
 */

import org.openjdk.btrace.core.Profiler;
import org.openjdk.btrace.core.BTraceUtils;
import org.openjdk.btrace.core.annotations.BTrace;
import org.openjdk.btrace.core.annotations.Duration;
import org.openjdk.btrace.core.annotations.Kind;
import org.openjdk.btrace.core.annotations.Location;
import org.openjdk.btrace.core.annotations.OnMethod;
import org.openjdk.btrace.core.annotations.OnTimer;
import org.openjdk.btrace.core.annotations.ProbeMethodName;
import org.openjdk.btrace.core.annotations.Property;

import static org.openjdk.btrace.core.BTraceUtils.*;


@BTrace
class Profiling {
    //final static String CLAZZ="/javax\\.swing\\..*/"; // Doesn't work

    @Property
    Profiler p = BTraceUtils.Profiling.newProfiler();

    // Can't use variable in 'clazz' because of static variables are not allowed (using BTrace short syntax)
    @OnMethod(clazz = "/com\\.sonatype\\.insight\\.brain\\.api\\.v2\\.service\\.legal\\.ApiLicenseLegalService/", method = "/.*/")
    void entry(@ProbeMethodName(fqn = true) String probeMethod) {
        BTraceUtils.Profiling.recordEntry(p, probeMethod);
    }

    @OnMethod(clazz = "/com\\.sonatype\\.insight\\.brain\\.api\\.v2\\.service\\.legal\\.ApiLicenseLegalService/", method = "/.*/", location = @Location(value = Kind.RETURN))
    void exit(@ProbeMethodName(fqn = true) String probeMethod, @Duration long duration) {
        BTraceUtils.Profiling.recordExit(p, probeMethod, duration);
    }

    @OnTimer(20000)
    void timer() {
        BTraceUtils.Profiling.printSnapshot("# [" + Time.timestamp("yyyy-MM-dd hh:mm:ss") + "] performance profile", p);
    }
}