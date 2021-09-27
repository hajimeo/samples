import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Date;
import java.util.Objects;
import java.util.Scanner;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.google.gson.JsonSyntaxException;
import org.apache.commons.lang3.StringUtils;

/**
 * Returns a blobpath if the argument is only one.
 * Otherwise, expecting json strings from stdin, then generate .properties and .bytes files.
 */
class BlobPath
{
  public static final Pattern BLOB_REF_PATTERN = Pattern.compile("([^@]+)@([^:]+):(.*)");

  public static boolean outputOnly = false;

  public static boolean useRealSize = false;

  // f3fb8f3a-1cd4-494d-855f-75820aabbf2a
  public static final Pattern BLOB_ID_PATTERN =
      Pattern.compile("^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$");

  public static void usage() {
    System.out.println("Returns a blobpath if the argument is only one.\n" +
        "Otherwise, reads json strings from stdin, then generate .properties and .bytes files.\n" +
        "\n" +
        "    blobpath [blobs dir *FULL* path]\n" +
        "\n" +
        "NOTE: *repository_name* is required to save it into .properties file.\n" +
        "echo \"select bucket.repository_name as repository_name, * from asset where blob_ref like '%666c9fab-4334-4f1f-bb76-0db0c474a371'\" | orient-console ./component | grep '^  {' | blobpath /tmp/sptBoot/support-20210604-150957-1_tmp/sonatype-work/nexus3/blobs\n" +
        "\n" +
        "OPTIONS:\n" +
        "  --output-only    If true, do not generate .properties and .bytes files\n" +
        "  --use-real-size  If true, read the value from 'size' in the properties file and generate .bytes with this size.\n" +
        "  --help|-h        Display this message.\n" +
        "");
  }

  public static void main(String[] args)
  {
    if (args.length == 1 && isBlobId(args[0])) {
      String bp = blobPath(args[0]);
      System.out.print(bp);
      System.exit(0);
    }

    String outDir = ".";
    if (args.length > 0) {
      if (Arrays.asList(args).contains("--help") && !Arrays.asList(args).contains("-h")) {
        usage();
        System.exit(0);
      }

      outDir = args[0];

      if (Arrays.asList(args).contains("--output-only") && !Arrays.asList(args).contains("--output-only=false")) {
        BlobPath.outputOnly = true;
      }

      if (Arrays.asList(args).contains("--use-real-size") && !Arrays.asList(args).contains("--use-real-size=false")) {
        BlobPath.useRealSize = true;
      }
    }

    try {
      processInputs(System.in, outDir);
    }
    catch (IOException e) {
      e.printStackTrace();
    }
  }

  public static boolean isBlobId(final String blobId) {
    Matcher matcher = BLOB_ID_PATTERN.matcher(blobId);
    return matcher.matches();
  }

  public static String blobPath(String blobId)
  {
    int hc = blobId.hashCode();
    int t1 = Math.abs(hc % 43) + 1;
    int t2 = Math.abs(hc % 47) + 1;
    return String.format("vol-%02d/chap-%02d/%s", t1, t2, blobId);
  }

  public static String blobDir(String blobId)
  {
    int hc = blobId.hashCode();
    int t1 = Math.abs(hc % 43) + 1;
    int t2 = Math.abs(hc % 47) + 1;
    return String.format("vol-%02d/chap-%02d", t1, t2, blobId);
  }

  private static void processInputs(InputStream is, String outDir) throws IOException {
    Scanner scanner = new Scanner(is);
    // At this moment, one exception stops the loop (no try/catch)
    while (scanner.hasNextLine()) {
      // NOTE: ignore if just "[" or "]", and remove the ending ","
      String l = StringUtils.stripEnd(scanner.nextLine(), ",");
      try {
        JsonObject js = new JsonParser().parse(l).getAsJsonObject();
        saveJs(js, outDir);
      }
      catch (JsonSyntaxException e) {
        System.err.println("JsonSyntaxException: " + e.getMessage() + " for \"" + l + "\"");
        continue;
      }
    }
  }

  private static void saveJs(JsonObject js, String outDir) throws IOException {
    String blobRef = get(js, "blob_ref");
    if (blobRef == null || blobRef.isEmpty() || blobRef.equals("<null>")) {
      System.err.println(js + " does not have 'blob_ref'. so skipping...");
      return;
    }
    Matcher matcher = BLOB_REF_PATTERN.matcher(blobRef);
    if (!matcher.find()) {
      System.err.println(blobRef + " does not match with the pattern. so skipping...");
      return;
    }
    String blobName = matcher.group(1);
    String blobId = matcher.group(3);
    String filePathBase = StringUtils.stripEnd(outDir, "/") + "/" + blobName + "/content";

    if (BlobPath.outputOnly) {
      System.out.println(filePathBase + "/" + blobPath(blobId) + ".properties");
      System.out.println(filePathBase + "/" + blobPath(blobId) + ".bytes");
      return;
    }

    File contentDir = new File(filePathBase + "/" + blobDir(blobId));
    if (!contentDir.exists()) {
      if (!contentDir.mkdirs()) {
        System.err.println("Could not create directory:" + contentDir.toString());
        return;
      }
    }

    String propContent = genPropertiesContent(js);
    save(contentDir.getPath() + "/" + blobId + ".properties", propContent);
    int sizeByte = 0;
    if (BlobPath.useRealSize) {
      sizeByte = Integer.parseInt(get(js, "size"));
    }
    genDummy(contentDir.getPath() + "/" + blobId + ".bytes", sizeByte);
    System.err.println("Saved " + contentDir.getPath() + "/" + blobId + ".*");
  }

  private static void save(String filePath, String content) throws IOException {
    FileWriter fw = new FileWriter(filePath, false);
    fw.write(content);
    fw.close();
  }

  private static void genDummy(String filePath, int sizeByte) throws IOException {
    // TODO: if file exists? should overwrite?
    RandomAccessFile raf = new RandomAccessFile(filePath, "rw");
    raf.setLength(sizeByte);
    raf.close();
  }

  // To convert OrientDB date-time to timestamp
  private static Number convertStringToTimestamp(String strDate) {
    try {
      SimpleDateFormat dateFormat = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");  // No milliseconds
      Date date = dateFormat.parse(strDate);
      return date.getTime();
    }
    catch (ParseException e) {
      System.out.println("Exception :" + e);
      return null;
    }
  }

  public static String genPropertiesContent(JsonObject js) {
    // TODO: The first line (modified date) is using last_updated which does not have milliseconds and timezone
    // TODO: The second line does not match with the first line
    String created = convertStringToTimestamp(get(js, "blob_created")).toString();
    return String.format("#%s,000+0000\n"
            + "#Mon Jan 01 00:00:00 UTC 2020\n"
            + "@BlobStore.created-by=%s\n"
            + "size=%s\n"
            + "@Bucket.repo-name=%s\n"
            + "creationTime=%s\n"
            + "@BlobStore.created-by-ip=%s\n"
            + "@BlobStore.content-type=%s\n"
            + "@BlobStore.blob-name=%s\n"
            + "sha1=%s", get(js, "last_updated"), get(js, "created_by"),
        get(js, "size"), get(js, "repository_name"),
        created, get(js, "created_by_ip"),
        get(js, "content_type"), get(js, "name"), get(js, "sha1"));
  }

  public static String get(JsonObject js, String memberName) {
    if (Objects.isNull(js.get(memberName))) {
      return "<null>";
    }
    return js.get(memberName).getAsString();
  }
}