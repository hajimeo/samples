/**
 * To test Metaspace OOME
 *
 * java -verbose:gc -XX:+PrintGCDetails -Xmx128m -XX:MaxMetaspaceSize=16m CauseOOMEMeta
 * java -verbose:gc -XX:+PrintGCDetails -Xmx128m -XX:MaxMetaspaceSize=16m -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp/ CauseOOMEMeta
 *
 * Ref: https://stackoverflow.com/questions/2320404/creating-classes-dynamically-with-java
 */

import java.io.*;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import javax.tools.*;

public class CauseOOMEMeta {
    private String tmpClassName = "";
    private String tmpClassSource = "";

    public CauseOOMEMeta(int classId) {
        this.tmpClassName="z_"+classId;
        this.tmpClassSource="z_"+classId+".java";
    }

    private void createIt() {
        try {
            FileWriter aWriter = new FileWriter(this.tmpClassSource, true);
            aWriter.write("public class " + this.tmpClassName + "{");
            aWriter.write(" public void doit() {");
            aWriter.write(" System.out.println(\"Hello World!\");");
            aWriter.write(" }}\n");
            aWriter.flush();
            aWriter.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private boolean compileIt() {
        String[] source = {new String(this.tmpClassSource)};
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ByteArrayOutputStream err = new ByteArrayOutputStream();
        JavaCompiler javac = ToolProvider.getSystemJavaCompiler();
        int rc = javac.run(null, out, err, source);
        return (rc == 0);
    }

    private void runIt() {
        try {
            Class params[] = {};
            Object paramsObj[] = {};
            Class thisClass = Class.forName(this.tmpClassName);
            Object iClass = thisClass.newInstance();
            // For this test, doesn't need to run
            //Method thisMethod = thisClass.getDeclaredMethod("doit", params);
            //thisMethod.invoke(iClass, paramsObj);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void deleteIt() {
        try {
            new File(this.tmpClassName + ".class").delete();
            new File(this.tmpClassSource).delete();
        } catch (Exception e) {
            log("deleteIt had exception for " + this.tmpClassName + ", but ignoring... ");
        }
    }

    public static void OOMEing(int maxIteration) throws Exception {
        for (int i = 0; i < maxIteration; i++) {
            if (i % 100 == 0)
                log("Free Mem: " + Runtime.getRuntime().freeMemory() + " (loop " + (i + 1) + ")");
            CauseOOMEMeta m = new CauseOOMEMeta(i);
            m.createIt();
            if (m.compileIt()) {
                m.runIt();
                m.deleteIt();
            } else {
                log(m.tmpClassSource + " is failed to compile.");
            }
            Thread.sleep(10);
        }
    }

    private static String getCurrentLocalDateTimeStamp() {
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"));
    }

    private static void log(String msg) {
        System.err.println("[" + getCurrentLocalDateTimeStamp() + "] " + msg);
    }

    public static void main(String args[]) {
        int maxIteration = (args.length > 1) ? Integer.parseInt(args[1]) : 1000000;

        try {
            OOMEing(maxIteration);
        } catch (OutOfMemoryError e) {
            e.printStackTrace();
            long f = Runtime.getRuntime().freeMemory();
            log("Completed test. (Free Mem: " + f +")");
        } catch (Exception e) {
            e.printStackTrace();
            System.exit(1);
        }
    }
}