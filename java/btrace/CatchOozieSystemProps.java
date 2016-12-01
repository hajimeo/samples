/**
 * export JAVA_HOME=/usr/jdk64/jdk1.7.0_67; ./btrace `lsof -nPi:11000 | grep ^java | awk '{print $2}'` ../CatchOozieSystemProps.java
 */
import com.sun.btrace.AnyType;
import static com.sun.btrace.BTraceUtils.*;
import com.sun.btrace.annotations.*;

@BTrace
public class CatchOozieSystemProps {
    @OnMethod(clazz="java.lang.System",
            method="getProperty",
            location=@Location(value=Kind.CALL)
    )
    public static void m1(@ProbeClassName String pcn, @ProbeMethodName String pmn, AnyType[] args) {
        println("=== CALL   getProperty    ========================");
        println(pcn);
        println(pmn);
        printArray(args);
    }

    @OnMethod(clazz="java.lang.System",
            method="getProperty",
            location=@Location(value=Kind.RETURN)
    )
    public static void m2(@Return String s) {
        println("=== RETURN getProperty    ========================");
        //jstack();
        if(s == null) {
            println("returning: null");
        }
        else {
            println(strcat("returning: ", s));
        }
        println(" ");
    }
}