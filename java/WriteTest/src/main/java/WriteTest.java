import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import com.google.common.io.ByteStreams;

public class WriteTest
{
  public static void main(String[] args) {
    //String inPath = "/opt/sonatype/sonatype-work/nexus3/log/jvm.log";
    //String outPath = "/opt/sonatype/sonatype-work/nexus3/blobs/default/content/tmp/test.out";
    String inPath = args[0];
    String outPath = args[1];

    try {
      InputStream input = Files.newInputStream(Paths.get(inPath));
      OutputStream output = Files.newOutputStream(Paths.get(outPath), StandardOpenOption.CREATE_NEW);
      ByteStreams.copy(input, output);
    }
    catch (Exception e) {
      System.err.println(e.getMessage());
      e.printStackTrace();
    }
  }
}
