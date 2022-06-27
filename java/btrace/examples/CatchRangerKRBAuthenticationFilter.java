/**
 * _PID=`cat /var/run/ranger/rangeradmin.pid`
 * export JAVA_HOME="$(dirname $(dirname `readlink /proc/${_PID}/exe`))"
 * ./btrace ${_PID} ./CatchRangerKRBAuthenticationFilter.java
 */
import com.sun.btrace.AnyType;
import static com.sun.btrace.BTraceUtils.*;
import com.sun.btrace.annotations.*;

@BTrace
public class CatchRangerKRBAuthenticationFilter {
    //@OnMethod(clazz="org.apache.ranger.security.web.filter.RangerKRBAuthenticationFilter",
    @OnMethod(clazz="/org\\.apache\\.ranger\\.security\\..*/",
            method="/.*/",
            location=@Location(value=Kind.CALL, clazz="/.*/", method="/.*/")
    )
    public static void m1(@ProbeClassName String pcn, @ProbeMethodName String pmn, AnyType[] args) {
        println("=== CALL *  ========================");
        println(pcn);
        println(pmn);
        printArray(args);
    }
}