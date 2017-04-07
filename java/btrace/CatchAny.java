/**
 * _PID=`cat /var/run/ranger/rangeradmin.pid`
 * export JAVA_HOME="$(dirname $(dirname `readlink /proc/${_PID}/exe`))"
 * ./btrace ${_PID} ./CatchAny.java
 */
import com.sun.btrace.AnyType;
import static com.sun.btrace.BTraceUtils.*;
import com.sun.btrace.annotations.*;

@BTrace
public class CatchAny {
    //@OnMethod(clazz="org.apache.ranger.security.web.filter.RangerKRBAuthenticationFilter",
    @OnMethod(clazz="org.apache.ambari.server.controller.internal.UserPrivilegeResourceProvider",
            method="toResource",
            location=@Location(value=Kind.CALL, clazz="/.*/", method="/.*/")
    )
    public static void m1(@ProbeClassName String pcn, @ProbeMethodName String pmn, AnyType[] args) {
        println("=== CALL toResource ========================");
        println(pcn);
        println(pmn);
        printArray(args);
    }

    // TODO: does not work?
    @OnMethod(clazz = "/.*InvalidCacheLoadException/",
            method = "/.*/",
            location = @Location(Kind.RETURN))
    public static void endMethod(@Self Exception self) {
        jstack();
    }
}