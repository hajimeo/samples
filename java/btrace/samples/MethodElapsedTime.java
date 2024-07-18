import org.openjdk.btrace.core.BTraceUtils;
import org.openjdk.btrace.core.annotations.*;

import static org.openjdk.btrace.core.BTraceUtils.*;

@BTrace
public class MethodElapsedTime {
    @OnMethod(
            clazz = "org.sonatype.nexus.blobstore.file.internal.SimpleFileOperations",
            method = "create",
            location = @Location(Kind.ENTRY)
    )
    public static void createEntry(@ProbeClassName String pcn, @ProbeMethodName String pmn) {
        println("Entering " + pcn + ":" + pmn + " at: " + Time.millis());
    }

    @OnMethod(
            clazz = "org.sonatype.nexus.blobstore.file.internal.SimpleFileOperations",
            method = "create",
            location = @Location(Kind.RETURN)
    )
    public static void createReturn(@ProbeClassName String pcn, @ProbeMethodName String pmn) {
        println("Return " + pcn + ":" + pmn + " at: " + Time.millis());
    }

    @OnMethod(
            clazz = "com.google.common.io.ByteStreams",
            method = "copy",
            location = @Location(Kind.ENTRY)
    )
    public static void copyEntry(@ProbeClassName String pcn, @ProbeMethodName String pmn) {
        println("Entering " + pcn + ":" + pmn + " at: " + Time.millis());
    }

    @OnMethod(
            clazz = "com.google.common.io.ByteStreams",
            method = "copy",
            location = @Location(Kind.RETURN)
    )
    public static void copyReturn(@ProbeClassName String pcn, @ProbeMethodName String pmn) {
        println("Return " + pcn + ":" + pmn + " at: " + Time.millis());
    }

    @OnMethod(
            clazz = "com.google.common.io.CountingInputStream",
            method = "read",
            location = @Location(Kind.ENTRY)
    )
    public static void readEntry(@ProbeClassName String pcn, @ProbeMethodName String pmn) {
        //StackTraceElement[] stackTrace = Thread.currentThread().getStackTrace();
        String stackTraceStr = Threads.jstackStr();
        stackTraceStr = Strings.substr(stackTraceStr, 0, 400);
        if (Strings.strstr(stackTraceStr, "com.google.common.io.ByteStreams.copy") <= 0) {
            println("Entering " + pcn + ":" + pmn + " at: " + Time.millis());
            println("StackTrace: " + stackTraceStr);
        }
    }
}