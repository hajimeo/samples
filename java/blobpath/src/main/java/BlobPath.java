import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.util.Objects;
import java.util.Scanner;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import org.apache.commons.lang3.StringUtils;

/**
 * The BlobPath program returns the blobpath if the argument is only one. Otherwise, expecting json strings from stdin, then generate .properties and .bytes files
 */
class BlobPath
{
  public static final Pattern BLOB_REF_PATTERN = Pattern.compile("([^@]+)@([^:]+):(.*)");

  // f3fb8f3a-1cd4-494d-855f-75820aabbf2a
  public static final Pattern BLOB_ID_PATTERN =
      Pattern.compile("^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$");

  public static void main(String[] args)
  {
    if (args.length == 1 && isBlobId(args[0])) {
      String bp = blobPath(args[0]);
      System.out.print(bp);
      System.exit(0);
    }

    try {
      processInputs(System.in, ".");
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

  private static void processInputs(InputStream is, String outDir) throws IOException {
    Scanner scanner = new Scanner(is);
    // At this moment, one exception stops the loop (no try/catch)
    while (scanner.hasNextLine()) {
      JsonObject js = new JsonParser().parse(scanner.nextLine()).getAsJsonObject();
      saveJs(js, outDir);
    }
  }

  private static void saveJs(JsonObject js, String outDir) throws IOException {
    String blobRef = get(js, "blob_ref");
    Matcher matcher = BLOB_REF_PATTERN.matcher(blobRef);
    String blobName = matcher.group(1);
    String blobId = matcher.group(3);
    String propContent = genPropertiesContent(js);
    String filePathBase = StringUtils.stripEnd(outDir, "/") + "/" + blobName + "/content";
    File contentDir = new File(filePathBase);
    if (!contentDir.exists()) {
      contentDir.mkdirs();
    }
    save(filePathBase + "/" + blobPath(blobId) + ".properties", propContent);
    genDummy(filePathBase + "/" + blobPath(blobId) + ".bytes", 0);
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

  public static String genPropertiesContent(JsonObject js) {
    // TODO: creationTime should be Unix Timestamp with milliseconds
    // TODO: The first line (modified date) is using last_updated which does not have milliseconds and timezone
    // TODO: The second line does not match with the first line
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
        get(js, "blob_created"), get(js, "created_by_ip"),
        get(js, "content_type"), get(js, "name"), get(js, "sha1"));
  }

  public static String get(JsonObject js, String memberName) {
    if (Objects.isNull(js.get(memberName))) {
      return "<null>";
    }
    return js.get(memberName).getAsString();
  }
}