/**
 * Replace clazz values, and timer integer, then
 *
 * _PID=`lsof -ti:10502 -sTCP:LISTEN`
 * export JAVA_HOME="$(dirname $(dirname `readlink /proc/${_PID}/exe`))"
 * ./btrace ${_PID} ./Profiling.java
 */

import com.sun.btrace.BTraceUtils;
import com.sun.btrace.Profiler;
import com.sun.btrace.annotations.*;

@BTrace
class Profiling {
    @Property
    Profiler p = BTraceUtils.Profiling.newProfiler();

    // Can't use variable in 'clazz' because of static variables are not allowed (using BTrace short syntax)
    @OnMethod(clazz="/javax\\.swing\\..*/", method="/.*/")
    void entry(@ProbeMethodName(fqn=true) String probeMethod) {
        BTraceUtils.Profiling.recordEntry(p, probeMethod);
    }

    @OnMethod(clazz="/javax\\.swing\\..*/", method="/.*/", location=@Location(value=Kind.RETURN))
    void exit(@ProbeMethodName(fqn=true) String probeMethod, @Duration long duration) {
        BTraceUtils.Profiling.recordExit(p, probeMethod, duration);
    }

    @OnTimer(10000)
    void timer() {
        BTraceUtils.Profiling.printSnapshot("performance profile", p);
    }
}