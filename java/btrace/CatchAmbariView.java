/**
 * export JAVA_HOME=/usr/jdk64/jdk1.7.0_67; ./btrace `lsof -ti:8080` ../AmbariViewMon.java
 * export JAVA_HOME=/usr/jdk64/jdk1.8.0_40; ./btrace `lsof -ti:8080` ../AmbariViewMon.java
 */

import com.sun.btrace.AnyType;
import static com.sun.btrace.BTraceUtils.*;
import com.sun.btrace.annotations.*;
//import org.apache.hadoop.security.UserGroupInformation;

@BTrace
public class CatchAmbariView {
    @OnMethod(clazz = "org.apache.ambari.view.utils.hdfs.HdfsApi",
            method = "getProxyUser",
            location = @Location(value = Kind.RETURN)
    )
    public static void m1(@Return AnyType[] rtn) {
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

    @OnMethod(clazz = "org.apache.hadoop.security.UserGroupInformation",
            method = "createRemoteUser",
            location = @Location(value = Kind.ENTRY)
    )
    public static void m2(@ProbeClassName String pcn, @ProbeMethodName String pmn, AnyType[] args) {
        println("=== ENTRY createRemoteUser    ========================");
        println(pcn);
        println(pmn);
        printArray(args);
        println(" ");
    }

    @OnMethod(clazz = "org.apache.hadoop.security.UserGroupInformation",
            method = "createRemoteUser",
            location = @Location(value = Kind.RETURN)
    )
    public static void m3(@Return AnyType[] rtn) {
        // TODO: doesn't return anything
        println("=== RETURN createRemoteUser    ========================");
        //jstack();
        if (rtn == null) {
            println("returning: null");
        } else {
            println("===        createRemoteUser    ========================");
            printArray(rtn);
        }
        println(" ");
    }
}