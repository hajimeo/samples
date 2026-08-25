/**
 * _PID=`cat /var/run/ranger/rangeradmin.pid`
 * export JAVA_HOME="$(dirname $(dirname `readlink /proc/${_PID}/exe`))"
 * ./btrace ${_PID} ./CatchAny.java
 */
import org.openjdk.btrace.core.annotations.*;
import static org.openjdk.btrace.core.BTraceUtils.*;


import org.openjdk.btrace.core.types.AnyType;

@BTrace
public class CatchAny {
    //@OnMethod(clazz="org.apache.ranger.security.web.filter.RangerKRBAuthenticationFilter",
    @OnMethod(clazz="org.sonatype.nexus.content.maven.internal.browse.Maven2BrowseNodeGenerator",
            method="computeAssetPaths",
            location=@Location(value=Kind.CALL, clazz="/.*/", method="/.*/")
    )
    public static void m1(@ProbeClassName String pcn, @ProbeMethodName String pmn, AnyType[] args) {
        println("=== CALL closeQuietly ========================");
        println(pcn);
        println(pmn);
        printArray(args);
    }

    // TODO: does not work?
    //@OnMethod(clazz = "/.*InvalidCacheLoadException/",
    //        method = "/.*/",
    //        location = @Location(Kind.RETURN))
    //public static void endMethod(@Self Exception self) {
    //    jstack();
    //}
}