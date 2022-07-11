/*
 * (PoC) Simple duplicate checker for Asset records
 *
 * curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/asset-dupe-checker-v2.jar"
 * java -Xms4g -Xmx4g [-Ddebug=true] [-DextractDir=./path] -jar ./asset-dupe-checker-v2.jar <component directory path|.bak file path> | tee asset-dupe-checker.sql
 *
 * After above, in the OrientDB Console, "LOAD SCRIPT ./asset-dupe-checker.sql"
 *
 * NOTE:
 *  If export/import-ed, then RID will be changed.
 *    This command outputs fixing SQL statements in STDOUT.
 *    "extractDir" is the path used when a .bak file is given. If extractDir is empty, use the tmp directory and the extracted data will be deleted on exit.
 *
 * TODO: Add tests. Cleanup the code (too messy...)
 *
 * My note:
 *  mvn clean package && cp -v ./target/asset-dupe-checker-2.0-SNAPSHOT-jar-with-dependencies.jar ../../misc/asset-dupe-checker-v2.jar
 */

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Comparator;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import com.orientechnologies.orient.core.Orient;
import com.orientechnologies.orient.core.conflict.OVersionRecordConflictStrategy;
import com.orientechnologies.orient.core.db.document.ODatabaseDocumentTx;
import com.orientechnologies.orient.core.id.ORID;
import com.orientechnologies.orient.core.id.ORecordId;
import com.orientechnologies.orient.core.index.OIndex;
import com.orientechnologies.orient.core.record.impl.ODocument;
import com.orientechnologies.orient.core.storage.ORecordDuplicatedException;
import net.lingala.zip4j.ZipFile;

public class AssetDupeCheckV2
{
  private static String EXTRACT_DIR = "";

  private static String LOG_PATH = "";

  private static Path TMP_DIR = null;

  private static String TABLE_NAME;

  private static String INDEX_NAME;

  private static boolean IS_REMOVING;

  private static boolean IS_REBUILDING;

  private static boolean IS_DEBUG;

  private AssetDupeCheckV2() { }

  private static void usage() {
    System.out.println("Usage:");
    System.out.println(
        "  java -Xmx4g -jar asset-dupe-checker-v2.jar <component directory path> | tee asset-dupe-checker.sql");
    System.out.println("System properties:");
    System.out.println("  -DextractDir=<extracting path>  Directory used for extracting component-*.bak file");
    System.out.println("  -DremoveDupes=true              Remove duplicates if detected");
    System.out.println("  -DrebuildIndex=true             Rebuild asset_bucket_component_name_idx");
    System.out.println("  -Ddebug=true                    Verbose outputs");
  }

  private static String getCurrentLocalDateTimeStamp() {
    return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"));
  }

  private static void log(String msg) {
    log(msg, false);
  }

  private static void log(String msg, Boolean noPrint) {
    // TODO: proper logging
    String message = getCurrentLocalDateTimeStamp() + " " + msg + "\n";
    if (!noPrint) {
      System.err.print(message);
    }
    if (LOG_PATH != null && LOG_PATH.length() > 1) {
      try {
        Files.write(Paths.get(LOG_PATH), message.getBytes(StandardCharsets.UTF_8),
            StandardOpenOption.CREATE,
            StandardOpenOption.APPEND);
      }
      catch (Exception logE) {
        System.err.println("log() got Exception: " + logE.getMessage());
      }
    }
  }

  private static void debug(String msg) {
    if (IS_DEBUG) {
      log("[DEBUG] " + msg);
    }
  }

  private static void out(String msg) {
    System.out.println(msg);
    log(msg, true);
  }

  private static void unzip(String zipFilePath, String destPath) throws IOException {
    Path source = new File(zipFilePath).toPath();
    File destDir = new File(destPath);
    if (!destDir.exists()) {
      if (!destDir.mkdirs()) {
        throw new IOException("Couldn't create " + destDir);
      }
    }
    new ZipFile(source.toFile()).extractAll(destPath);
  }

  private static boolean prepareDir(String dirPath, String zipFilePath) throws IOException {
    // if dirPath is empty, use a temp directory
    if (dirPath.trim().isEmpty()) {
      TMP_DIR = Files.createTempDirectory(null);
      TMP_DIR.toFile().deleteOnExit();
      EXTRACT_DIR = TMP_DIR.toString();
      return true;
    }

    File destDir = new File(dirPath);
    if (!destDir.exists()) {
      if (!destDir.mkdirs()) {
        log("[ERROR] Couldn't create " + destDir);
        return false;
      }
    }
    else if (!isDirEmpty(destDir.toPath())) {
      log("[ERROR] " + dirPath + " is not empty.");
      return false;
    }
    // TODO: properly check if the dirPath has enough space (currently just requesting 10 times of .bak file).
    long usable_space = Files.getFileStore(new File(dirPath).toPath()).getUsableSpace();
    long zip_file_size = (new File(zipFilePath)).length();
    if (zip_file_size * 10 > usable_space) {
      log("[ERROR] " + dirPath + " (usable:" + usable_space + ") may not be enough for extracting " + zipFilePath +
          " (size:" +
          zip_file_size + ")");
      return false;
    }
    return true;
  }

  private static boolean isDirEmpty(final Path directory) throws IOException {
    try (DirectoryStream<Path> dirStream = Files.newDirectoryStream(directory)) {
      return !dirStream.iterator().hasNext();
    }
  }

  // deleteOnExit() does not work, so added this...
  private static void delR(Path path) throws IOException {
    if (path == null || !path.toFile().exists()) {
      return;
    }
    Files.walk(path)
        .sorted(Comparator.reverseOrder())
        .forEach(p -> {
          try {
            Files.delete(p);
          }
          catch (IOException e) {
            log("[ERROR] " + e.getMessage());
          }
        });
  }

  private static void rebuildIndex(ODatabaseDocumentTx db, String indexName) {
    OIndex<?> index = db.getMetadata().getIndexManager().getIndex(indexName);
    index.rebuild();
  }

  private static Boolean addToIndexFromTable(ODatabaseDocumentTx db, String indexName, String tableName, Boolean isRemoving) {
    OIndex<?> index = db.getMetadata().getIndexManager().getIndex(indexName);
    long count = 0L;
    int deleted = 0;
    long total = db.countClass(tableName);
    log("Count for " + tableName + " is " + total);
    for (ODocument doc : db.browseClass(tableName)) {
      count++;
      deleted += _addToIndexWithDelete(db, index, doc, isRemoving);
      if (count % 2500 == 0) {
        index.flush();
        log("Checked " + count + "/" + total + " (deleted:" + deleted + ")");
      }
    }
    return true;
  }

  private static int _addToIndexWithDelete(ODatabaseDocumentTx db, OIndex<?> index, ODocument doc, Boolean isRemoving) {
    int deleted = 0;
    while (true) {
      ORecordId maybeDupeId = _addToIndex(index, doc);
      if (maybeDupeId == null) {
        return deleted;
      }
      if (!isRemoving) {
        out("TRUNCATE RECORD " + maybeDupeId + ";");
        return deleted;
      }
      if (deleted > 10) {
        log("[ERROR] Tried to add index:" + index + " " + deleted + " times but failed.");
        return deleted;
      }
      db.delete(maybeDupeId);
      db.commit();    // TODO: not sure if this helps to reduce heap
      deleted++;
      log("[WARN] Deleted duplicate ID: " + maybeDupeId + " for index: " + index + " (" + deleted + ")");
    }
  }

  private static ORecordId _addToIndex(OIndex<?> index, ODocument doc) {
    List<String> fields = index.getDefinition().getFields();
    Object[] vals = new Object[fields.size()];
    for (int i = 0; i < vals.length; i++) {
      vals[i] = doc.field(fields.get(i));
    }
    Object indexKey = index.getDefinition().createValue(vals);
    ORID docId = doc.getIdentity();
    debug("key: " + indexKey.toString() + ", values: " + docId.toString());
    try {
      index.put(indexKey, docId);
    }
    catch (ORecordDuplicatedException e) {
      // TODO: should use index.get(indexKey)?
      String error = e.getMessage();
      // 'Cannot index record' to delete newer
      Pattern CANNOT_ASSET_RID_REGEX =
          Pattern.compile("(?s).*previously assigned to the record #(?<iClusterId>[0-9]+):(?<iPositionId>[0-9]+).*");
      Matcher myMatcher = CANNOT_ASSET_RID_REGEX.matcher(error);
      if (myMatcher.matches()) {
        int iClusterId = Integer.parseInt(myMatcher.group("iClusterId"));
        long iPositionId = Long.parseLong(myMatcher.group("iPositionId"));
        return new ORecordId(iClusterId, iPositionId);
      }
      else {
        log("[WARN] +" + error);
      }
    }
    return null;
  }

  private static void setGlobals() {
    IS_DEBUG = Boolean.getBoolean("debug");
    IS_REMOVING = Boolean.getBoolean("removeDupes");
    debug("removeDupes: " + IS_REMOVING);
    IS_REBUILDING = Boolean.getBoolean("rebuildIndex");
    debug("rebuildIndex: " + IS_REBUILDING);
    TABLE_NAME = System.getProperty("tableName", "asset");
    debug("tableName: " + TABLE_NAME);
    INDEX_NAME = System.getProperty("indexName", "asset_bucket_component_name_idx");
    debug("tableName: " + TABLE_NAME);
    EXTRACT_DIR = System.getProperty("extractDir", "");
    debug("extDir: " + EXTRACT_DIR);
    LOG_PATH = System.getProperty("logPath", "./asset-dupe-checker-v2.log");
    debug("logPath: " + LOG_PATH);
  }

  public static void main(final String[] args) throws IOException {
    if (args.length < 1) {
      usage();
      System.exit(1);
    }
    setGlobals();

    String path = args[0];
    String connStr;

    log("main() started with " + path);

    if (!(new File(path)).isDirectory()) {
      try {
        if (!prepareDir(EXTRACT_DIR, path)) {
          System.exit(1);
        }
        log("Unzip-ing " + path + " to " + EXTRACT_DIR);
        unzip(path, EXTRACT_DIR);
        path = EXTRACT_DIR;
      }
      catch (Exception e) {
        log("[ERROR] " + path + " is not a right archive.");
        log(e.getMessage());
        delR(TMP_DIR);
        System.exit(1);
      }
    }

    // Somehow without an ending /, OStorageException happens
    if (!path.endsWith("/")) {
      path = path + "/";
    }
    connStr = "plocal:" + path + " admin admin";

    Orient.instance().getRecordConflictStrategy()
        .registerImplementation("ConflictHook", new OVersionRecordConflictStrategy());
    try (ODatabaseDocumentTx db = new ODatabaseDocumentTx(connStr)) {
      try {
        db.open("admin", "admin");
        log("Connected to " + connStr);
        Boolean result = addToIndexFromTable(db, INDEX_NAME, TABLE_NAME, IS_REMOVING);
        log("Added records to indexName: " + INDEX_NAME + " from tableName: " + TABLE_NAME);
        if (result && IS_REBUILDING) {
          rebuildIndex(db, INDEX_NAME);
          log("Rebuilt indexName: " + INDEX_NAME);
        }
      }
      catch (Exception e) {
        e.printStackTrace();
      }
    }

    log("main() completed.");
    // Cleaning up the temp dir if used
    delR(TMP_DIR);
  }
}
