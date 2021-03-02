/**
 * Simple Asset record duplicate checker
 * <p>
 * curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/asset-dupe-checker.jar" java -jar
 * asset-dupe-checker.jar <directory path|.bak file path> [permanent extract dir]
 * <p>
 * TODO: add tests
 */

import com.orientechnologies.orient.core.Orient;
import com.orientechnologies.orient.core.conflict.OVersionRecordConflictStrategy;
import com.orientechnologies.orient.core.db.document.ODatabaseDocumentTx;
import com.orientechnologies.orient.core.record.impl.ODocument;
import com.orientechnologies.orient.core.sql.query.OSQLSynchQuery;
import net.lingala.zip4j.ZipFile;

import java.io.*;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.*;

public class Main
{
  private Main() {
  }

  private static void log(String msg) {
    // TODO: proper logging
    System.err.println(msg);
  }

  private static void out(String msg) {
    // TODO: proper stdout writing
    System.out.println(msg);
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

  private static boolean prepareDir(String dirPath) throws IOException {
    File destDir = new File(dirPath);
    if (!destDir.exists()) {
      if (!destDir.mkdirs()) {
        log("Couldn't create " + destDir);
        return false;
      }
    }
    else if (!isDirEmpty(destDir.toPath())) {
      log(dirPath + " is not empty.");
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
            log(e.getMessage());
          }
        });
  }

  public static List<ODocument> execQueries(ODatabaseDocumentTx tx, String input) {
    List<ODocument> results = null;
    Instant start = Instant.now();
    try {
      results = tx.query(new OSQLSynchQuery(input));
    }
    catch (java.lang.ClassCastException e) {
      log(e.getMessage());
      //e.printStackTrace();
    }
    finally {
      Instant finish = Instant.now();
      log("Query: " + input + " elapsed: " + Duration.between(start, finish).toMillis() + " ms");
    }
    return results;
  }

  public static void main(final String[] args) throws IOException {
    if (args.length < 1) {
      System.out.println("Usage: java -jar asset-dupe-checker.jar <directory path|.bak file path> [extract dir]");
      System.exit(1);
    }

    String path = args[0];
    String connStr = "";
    String extDir = "";
    Path tmpDir = null;

    // Preparing data (extracting zip if necessary)
    if ((new File(path)).isDirectory()) {
      if (!path.endsWith("/")) {
        // Somehow without ending /, OStorageException happens
        path = path + "/";
      }
      connStr = "plocal:" + path + " admin admin";
    }
    else {
      if (args.length > 1) {
        extDir = args[1];
        if (!prepareDir(extDir)) {
          System.exit(1);
        }
      }
      else {
        try {
          tmpDir = Files.createTempDirectory(null);
          tmpDir.toFile().deleteOnExit();
          extDir = tmpDir.toString();
        }
        catch (IOException e) {
          throw new RuntimeException(e);
        }
      }

      log("# unzip-ing " + path + " to " + extDir);
      try {
        unzip(path, extDir);
        if (!extDir.endsWith("/")) {
          // Somehow without ending /, OStorageException happens
          extDir = extDir + "/";
        }
        connStr = "plocal:" + extDir + " admin admin";
      }
      catch (IOException e) {
        log(path + " is not a right archive.");
        log(e.getMessage());
        delR(tmpDir);
        System.exit(1);
      }
    }

    Orient.instance().getRecordConflictStrategy()
        .registerImplementation("ConflictHook", new OVersionRecordConflictStrategy());
    try (ODatabaseDocumentTx db = new ODatabaseDocumentTx(connStr)) {
      try {
        db.open("admin", "admin");
        List<ODocument> docs = null;

        //docs = execQueries(db, "select count(*) as c from component");
        //out("Component count: " + docs.get(0).field("c"));
        docs = execQueries(db, "select count(*) as c from asset");
        Long ac = docs.get(0).field("c");
        out("Asset count: " + ac.toString());
        docs = execQueries(db, "select count(*) as c from browse_node");
        out("Browse_node count: " + docs.get(0).field("c"));
        docs = execQueries(db,
            "select name, indexDefinition from (select expand(indexes) from metadata:indexmanager) where name like '%_idx'");
        out("Index length: " + docs.size() + " / 16");
        docs = execQueries(db,
            "select name, indexDefinition from (select expand(indexes) from metadata:indexmanager) where name like '%_idx'");
        out("Index length: " + docs.size() + " / 16");

        boolean asset_checked = false;

        // Looping to output the index names and sizes (count)
        for (ODocument idx : docs) {
          String iname = idx.field("name");
          //out(idx.toString());
          List<ODocument> _idx_c = execQueries(db, "select count(*) as c from index:" + iname);
          Long ic = _idx_c.get(0).field("c");
          out("Index: " + iname + " count: " + ic.toString());

          if (!asset_checked && ((ODocument) idx.field("indexDefinition")).field("className").toString().equals("asset") && !ac.equals(ic)) {
            List<ODocument> bkts = execQueries(db, "select from bucket");
            for (ODocument bkt : bkts) {
              String bname = bkt.field("repository_name");
              log("Dupe check query started for bucket: " + bname);
              List<ODocument> dups = execQueries(db,"SELECT FROM (SELECT list(@rid) as dupe_rids, max(@rid) as keep_rid, COUNT(*) as c FROM asset WHERE bucket.repository_name like '" + bname + "' GROUP BY bucket, component, name) WHERE c > 1 LIMIT 1000;");
              log("Dupe check query completed for bucket: "+ bname);
            }
            asset_checked = true;
          }
        }
      }
      catch (Exception e) {
        e.printStackTrace();
      }
    }

    // Cleaning up the temp dir if used
    delR(tmpDir);
  }
}
