/**
 * export JAVA_HOME=/usr/jdk64/jdk1.7.0_67; ./btrace `lsof -nPi:11000 | grep ^java | awk '{print $2}'` ../CatchOozieRun.java
 */
import com.sun.btrace.AnyType;
import static com.sun.btrace.BTraceUtils.*;
import com.sun.btrace.annotations.*;

@BTrace
public class CatchOozieRun {
    @OnMethod(clazz="org.apache.oozie.action.ssh.SshActionExecutor",
            method="/.*/",
            location=@Location(value=Kind.CALL, clazz="/.*/", method="/.*/")
    )
    public static void m1(@Self Object self, @TargetMethodOrField String method, @ProbeMethodName String probeMethod) {
        if(method == "getRemoteFileName") {
            println("=== CALL   " + method + " in " + probeMethod + " ========================");
            //printArray(args); # TODO: args doesn't work
            //println(" ");
            if(probeMethod == "end") {
                jstack();
                println(" ");
            }
        }
    }

    @OnMethod(clazz="org.apache.oozie.action.ssh.SshActionExecutor",
            method="getRemoteFileName",
            location=@Location(value=Kind.RETURN)
    )
    public static void m4(@Return String path) {
        println("=== RETURN getRemoteFileName    ========================");
        jstack();
        println(strcat("Path: ", path));
        println(" ");
    }
}