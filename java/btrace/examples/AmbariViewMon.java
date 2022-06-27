/**
 * export JAVA_HOME=/usr/jdk64/jdk1.7.0_67; ./btrace `lsof -ti:8080` ../AmbariViewMon.java
 * export JAVA_HOME=/usr/jdk64/jdk1.8.0_40; ./btrace `lsof -ti:8080` ../AmbariViewMon.java
 */

import com.sun.btrace.AnyType;

import static com.sun.btrace.BTraceUtils.*;

import com.sun.btrace.annotations.*;

@BTrace
public class AmbariViewMon {
    @TLS
    static Throwable currentException;

    @OnMethod(
            clazz = "java.lang.Throwable",
            method = "<init>"
    )
    public static void onthrow(@Self Throwable self) {
        currentException = self;
    }

    @OnMethod(
            clazz = "java.lang.Throwable",
            method = "<init>"
    )
    public static void onthrow1(@Self Throwable self, String s) {
        currentException = self;
    }

    @OnMethod(
            clazz = "java.lang.Throwable",
            method = "<init>"
    )
    public static void onthrow1(@Self Throwable self, String s, Throwable cause) {
        currentException = self;
    }

    @OnMethod(
            clazz = "java.lang.Throwable",
            method = "<init>"
    )
    public static void onthrow2(@Self Throwable self, Throwable cause) {
        currentException = self;
    }

    // when any constructor of java.lang.Throwable returns
    // print the currentException's stack trace.
    @OnMethod(
            clazz = "java.lang.Throwable",
            method = "<init>",
            location = @Location(Kind.RETURN)
    )
    public static void onthrowreturn() {
        if (currentException != null) {
            println(str(currentException));
            currentException = null;
        }
    }

    @OnMethod(clazz = "org.apache.ambari.view.utils.hdfs.HdfsApi",
            method = "/.*/",
            location = @Location(value = Kind.CALL, clazz = "/.*/", method = "/.*/")
    )
    public static void hello(@Self Object self, @TargetMethodOrField String method, @ProbeMethodName String probeMethod) {
        println("=== CALL   " + method + " in " + probeMethod + " ========================");
        //printArray(args); // TODO: args doesn't work
        //println(" ");
        //if(probeMethod == "end") {
        //jstack();
        println(" ");
        //}
    }

    @OnMethod(clazz = "org.apache.ambari.view.utils.hdfs.HdfsApi",
            method = "getProxyUser",
            location = @Location(value = Kind.RETURN)
    )
    public static void m2(@Return AnyType[] rtn) {
        println("=== RETURN getProxyUser    ========================");
        //jstack();
        if (rtn == null) {
            println("returning: null");
        } else {
            println("===        getLoginUser    ========================");
            printArray(rtn);
        }
        println(" ");
    }
}