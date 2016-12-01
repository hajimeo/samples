/**
 * export JAVA_HOME=/usr/jdk64/jdk1.8.0_40; ./btrace `lsof -nPi:10000 | grep ^java | awk '{print $2}'` ../AmbariHiveView.java
 */
import com.sun.btrace.AnyType;
import static com.sun.btrace.BTraceUtils.*;
import com.sun.btrace.annotations.*;

@BTrace
public class AmbariHiveView {
    @OnMethod(clazz="org.apache.hive.service.auth.LdapAuthenticationProviderImpl",
            method="Authenticate",
            location=@Location(value=Kind.CALL, clazz="/.*/", method="/.*/")
    )
    public static void hello(@Self Object self, @TargetMethodOrField String method, @ProbeMethodName String probeMethod, AnyType[] args) {
        println("=== CALL   " + method + " in " + probeMethod + " ========================");
        //println(strcat("password: ", args[1]));
        printArray(args);
        println(" ");
    }
}