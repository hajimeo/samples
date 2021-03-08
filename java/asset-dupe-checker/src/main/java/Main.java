/*
 * Simple duplicate checker for Asset records
 *
 * curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/asset-dupe-checker.jar"
 * java [-DextractDir=....] [-DrepoNames=xxx,yyy,zzz] -jar asset-dupe-checker.jar <directory path|.bak file path>
 *
 *    extractDir is the path string used when .bak file is given. If extractDir is empty, use tmp directory.
 *    repoNames is the comma separated repository names to check these repositories only.
 *
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
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

public class Main
{
  private Main() {
  }

  private static String getCurrentLocalDateTimeStamp() {
    return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"));
  }

  private static void log(String msg) {
    // TODO: proper logging
    System.err.println("[" + getCurrentLocalDateTimeStamp() + "] " + msg);
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
    // TODO: check if dirPath has enough space
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

    log("main() started.");
    String path = args[0];
    String connStr = "";
    String extDir = "";
    Path tmpDir = null;

    if ((new File(path)).isDirectory()) {
      if (!path.endsWith("/")) {
        // Somehow without ending /, OStorageException happens
        path = path + "/";
      }
      connStr = "plocal:" + path + " admin admin";
    }
    else {
      extDir = System.getProperty("extractDir", "");
      if (!extDir.trim().isEmpty()) {
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

      try {
        log("Unzip-ing " + path + " to " + extDir);
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

        // At this moment, probably not interested in the component count
        //docs = execQueries(db, "select count(*) as c from component");
        //out("Component count: " + docs.get(0).field("c"));

        docs = execQueries(db, "select count(*) as c from asset");
        Long ac = docs.get(0).field("c");
        out("Asset count: " + ac.toString());

        // Just in case, counting browse_node
        docs = execQueries(db, "select count(*) as c from browse_node");
        out("Browse_node count: " + docs.get(0).field("c"));
        docs = execQueries(db,
            "select name, indexDefinition from (select expand(indexes) from metadata:indexmanager) where name like '%_idx' ORDER BY name");
        out("Index count: " + docs.size() + " / 16");

        // Counting Indexes.
        Long abn_idx_c = 0L;
        Long abcn_idx_c = 0L;
        for (ODocument idx : docs) {
          String iname = idx.field("name");
          //out(idx.toString());
          List<ODocument> _idx_c = execQueries(db, "select count(*) as c from index:" + iname);
          if (iname.equals("asset_bucket_name_idx")) {
            abn_idx_c = _idx_c.get(0).field("c");
          }
          else if (iname.equals("asset_bucket_component_name_idx")) {
            abcn_idx_c = _idx_c.get(0).field("c");
          }
          out("Index: " + iname + " count: " + _idx_c.get(0).field("c").toString());
        }

        // Current limitation/restriction: asset_bucket_name_idx is required (accept 10% difference as this is for estimation).
        if (abn_idx_c > 0 && (abn_idx_c * 1.1) < ac) {
          out("ERROR: asset_bucket_name_idx count is too small for this tool. Please rebuild asset_bucket_name_idx first.");
          System.exit(1);
        }

        // Counting records per repository (alphabetical order)
        List<ODocument> bkts =
            execQueries(db, "select @rid as r, repository_name from bucket ORDER BY repository_name");
        List<String> repo_names = Arrays.asList(System.getProperty("repoNames", "").split(","));

        if (repo_names.size() == 0) {
          long maxBytes = Runtime.getRuntime().maxMemory();
          for (ODocument bkt : bkts) {
            String q =
                "select count(*) as c from index:asset_bucket_name_idx where key = [" +
                    ((ODocument) bkt.field("r")).getIdentity().toString() + "]";
            List<ODocument> c_per_bkt = execQueries(db, q);
            String repoName = bkt.field("repository_name");
            Long c = c_per_bkt.get(0).field("c");
            out("Repository: " + bkt.field("repository_name") + " count: " + c.toString());
            // super rough estimate. Just guessing one record uses 2kb. If asset_bucket_name_idx is broken, less accurate.
            if (maxBytes < (c * 1024 * 2)) {
              out("WARN: Heap size:" + maxBytes + " may not be enough so not checking " + repoName);
            }
            else if (c == 0) {
              log("No record for " + repoName + ", so skipping.");
            }
            else {
              repo_names.add(repoName);
            }
          }
        }
        else {
          log("Repository names: " + repo_names.toString() +
              " are provided so that not checking the record counts per repo.");
        }

        if (!ac.equals(abcn_idx_c)) {
          for (String repo_name : repo_names) {
            log("Dupe check query started for repository: " + repo_name);
            List<ODocument> dups = execQueries(db,
                "SELECT FROM (SELECT list(@rid) as dupe_rids, max(@rid) as keep_rid, COUNT(*) as c FROM asset WHERE bucket.repository_name like '" +
                    repo_name + "' GROUP BY bucket, component, name) WHERE c > 1 LIMIT 1000;");
            log("Dupe check query completed for repository: " + repo_name + " with the result size: " + dups.size());
            for (ODocument doc : dups) {
              log(doc.toJSON());
              // TODO: output TRUNCATE RECORD statements. May need to use .getIdentity().toString()
            }
          }
        }
      }
      catch (Exception e) {
        e.printStackTrace();
      }
    }

    log("main() completed.");
    // Cleaning up the temp dir if used
    delR(tmpDir);
  }
}
