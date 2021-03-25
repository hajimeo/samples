/*
 * (PoC) Simple duplicate checker for Asset records
 *
 * curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/asset-dupe-checker.jar"
 * java -Xmx4g -XX:MaxDirectMemorySize=4g [-Ddebug=true] [-DextractDir=./path] [-DrepoNames=xxx,yyy,zzz] -jar asset-dupe-checker.jar <component directory path|.bak file path> | tee asset-dupe-checker.sql
 *
 *    This command outputs fixing SQL statements in STDOUT.
 *    "extractDir" is the path used when a .bak file is given. If extractDir is empty, use the tmp directory and the extracted data will be deleted on exit.
 *    "repoNames" is a comma separated repository names to check these repositories only.
 *
 * TODO: add tests. Cleanup the code (main)..., convert to Groovy.
 *
 * My note:
 *  mvn clean package && cp -v ./target/asset-dupe-checker-1.0-SNAPSHOT-jar-with-dependencies.jar ../../misc/asset-dupe-checker.jar
 */

import com.orientechnologies.orient.core.Orient;
import com.orientechnologies.orient.core.conflict.OVersionRecordConflictStrategy;
import com.orientechnologies.orient.core.db.document.ODatabaseDocumentTx;
import com.orientechnologies.orient.core.id.ORecordId;
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
  private static long maxMb;

  private static boolean isDebug;

  private Main() {}

  private static String getCurrentLocalDateTimeStamp() {
    return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"));
  }

  private static void log(String msg) {
    // TODO: proper logging
    System.err.println(getCurrentLocalDateTimeStamp() + " " + msg);
  }

  private static void debug(String msg) {
    if (isDebug) {
      log(msg);
    }
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

  private static boolean prepareDir(String dirPath, String zipFilePath) throws IOException {
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
    // TODO: check if dirPath has enough space properly (currently just requesting 10 times of .bak file).
    long usable_space = Files.getFileStore(new File(dirPath).toPath()).getUsableSpace();
    long zip_file_size = (new File(zipFilePath)).length();
    if (zip_file_size * 10 > usable_space) {
      log(dirPath + " (usable:" + usable_space + ") may not be enough for extracting " + zipFilePath + " (size:" +
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
      debug("Query: " + input + " elapsed: " + Duration.between(start, finish).toMillis() + " ms");
    }
    return results;
  }

  public static void printMissingIndex(List<ODocument> docs) {
    List<String> expected_idxs = Arrays
        .asList("asset_bucket_component_name_idx", "asset_bucket_name_idx", "asset_component_idx", "asset_name_ci_idx",
            "bucket_repository_name_idx", "component_bucket_group_name_version_idx",
            "component_bucket_name_version_idx", "component_ci_name_ci_idx", "component_group_name_version_ci_idx",
            "browse_node_asset_id_idx", "browse_node_component_id_idx",
            "browse_node_repository_name_parent_path_name_idx", "component_tags_idx",
            "docker_foreign_layers_digest_idx", "statushealthcheck_node_id_idx", "tag_name_idx");
    List<String> current_idxs = new ArrayList<String>();
    for (ODocument doc : docs) {
      current_idxs.add(doc.field("name").toString());
    }
    for (String idx : expected_idxs) {
      if (!current_idxs.contains(idx)) {
        out("-- Missing index: " + idx);
      }
    }
  }

  public static boolean checkDupes(ODatabaseDocumentTx tx, List<String> repoNames) {
    boolean is_dupe_found = false;
    StringBuilder where = new StringBuilder();
    if (repoNames != null && repoNames.size() > 0) {
      // Can't use " in ['...','...'] when we suspect asset_bucket_component_name_idx
      where = new StringBuilder("WHERE (");
      for (int i = 0; i < repoNames.size(); i++) {
        if (i > 0) {
          where.append(" OR ");
        }
        where.append("bucket.repository_name like '").append(repoNames.get(i)).append("'");
      }
      where.append(")");
    }
    // Not expecting more than 1000 duplicates per repository / repositories
    List<ODocument> dups = execQueries(tx,
        "SELECT FROM (SELECT bucket.repository_name as repo_name, component, name, list(@rid) as dupe_rids, max(@rid) as keep_rid, COUNT(*) as c FROM asset " +
            where +
            " GROUP BY bucket, component, name) WHERE c > 1 LIMIT 1000;");

    for (ODocument doc : dups) {
      log(doc.toJSON());
      // output TRUNCATE RECORD statements
      ODocument keep_rid = doc.field("keep_rid");
      List<ORecordId> dupe_rids = doc.field("dupe_rids");
      for (ORecordId dr : dupe_rids) {
        if (!dr.getIdentity().toString().equals(keep_rid.getIdentity().toString())) {
          // TODO: not good idea to output SQLs in a function.
          out("TRUNCATE RECORD " + dr + ";");
          is_dupe_found = true;
        }
      }
    }

    return is_dupe_found;
  }

  public static boolean checkDupesForRepos(
      ODatabaseDocumentTx tx,
      List<String> repoNames,
      Map<String, Long> repoCounts)
  {
    boolean is_dupe_found = false;
    long current_ttl = 0L;
    List<String> sub_repo_names = new ArrayList<String>();

    for (String repo_name : repoNames) {
      if (repo_name.trim().isEmpty()) {
        continue;
      }

      // if adding this may be going to exceed the limit
      current_ttl += repoCounts.get(repo_name);
      long est = estimateSize(current_ttl);
      debug(
          "Adding " + repoCounts.get(repo_name) + " for " + repo_name + " = " + current_ttl + " (estimate_size:" + est +
              " / " + maxMb + ", sub_repo_names.size:" + sub_repo_names.size() + ")");
      if (sub_repo_names.size() > 0 && est > maxMb) {
        log("Checking (" + sub_repo_names.size() + "): " + sub_repo_names.toString());
        if (checkDupes(tx, sub_repo_names)) {
          is_dupe_found = true;
        }
        current_ttl = 0;
        sub_repo_names = new ArrayList<String>();
      }

      sub_repo_names.add(repo_name);
    }

    if (sub_repo_names.size() > 0) {
      log("Checking (" + sub_repo_names.size() + "): " + sub_repo_names.toString());
      if (checkDupes(tx, sub_repo_names)) {
        is_dupe_found = true;
      }
    }
    return is_dupe_found;
  }

  public static long estimateSize(long c) {
    return (c * 3) / 1024 + 1024;
  }

  public static void main(final String[] args) throws IOException {
    if (args.length < 1) {
      System.out.println(
          "Usage: java -Xmx4g -XX:MaxDirectMemorySize=4g -jar asset-dupe-checker.jar <component directory path> | tee asset-dupe-checker.sql");
      System.exit(1);
    }

    String extDir = System.getProperty("extractDir", "");
    String repoNames = System.getProperty("repoNames", "");
    isDebug = Boolean.getBoolean("debug");

    String path = args[0];
    String connStr = "";
    Path tmpDir = null;
    Long abn_idx_c = 0L;
    Long abcn_idx_c = 0L;
    List<String> repo_names = new ArrayList<String>();
    List<String> repo_names_skipped = new ArrayList<String>();
    Map<String, Long> repo_counts = new HashMap<String, Long>();

    maxMb = Runtime.getRuntime().maxMemory() / 1024 / 1024;

    log("main() started.");

    if (!(new File(path)).isDirectory()) {
      try {
        if (!extDir.trim().isEmpty()) {
          if (!prepareDir(extDir, path)) {
            System.exit(1);
          }
        }
        else {
          tmpDir = Files.createTempDirectory(null);
          tmpDir.toFile().deleteOnExit();
          extDir = tmpDir.toString();
        }

        log("Unzip-ing " + path + " to " + extDir);
        unzip(path, extDir);
        path = extDir;
      }
      catch (Exception e) {
        log(path + " is not a right archive.");
        log(e.getMessage());
        delR(tmpDir);
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
    try (ODatabaseDocumentTx tx = new ODatabaseDocumentTx(connStr)) {
      try {
        tx.open("admin", "admin");

        List<ODocument> docs = execQueries(tx, "select count(*) as c from asset");
        Long ac = docs.get(0).field("c");
        if (ac == 0) {
          log("Asset table/class is empty.");
          System.exit(1);
        }
        log("Asset count: " + ac.toString());

        long estimateMb = estimateSize(ac);
        boolean check_all_repo = false;

        if (!repoNames.trim().isEmpty()) {
          repo_names = Arrays.asList(repoNames.split(","));
          log("Repository names: " + repo_names.toString() +
              " are provided, so that not checking the record counts per repo.");
        }
        else if (maxMb > estimateMb) {
          log("Asset count is small, so not checking each repositories.");
          check_all_repo = true;
        }
        else {
          // At this moment, probably not interested in the component count
          //docs = execQueries(tx, "select count(*) as c from component");
          //log("Component count: " + docs.get(0).field("c"));

          // Just in case, counting browse_node (should count per repo?)
          docs = execQueries(tx, "select count(*) as c from browse_node");
          long bnc = docs.get(0).field("c");
          log("Browse_node count: " + bnc);
          double ratio = (double) bnc / (double) ac;
          if (ac > 0 && bnc > 0 && (ratio < 0.8 || ratio > 1.2)) {
            out("-- [WARN] may need 'TRUNCATE CLASS browse_node;'");
          }

          // Counting Indexes.
          docs = execQueries(tx,
              "select name from (select expand(indexes) from metadata:indexmanager) where name like '%_idx' ORDER BY name");
          long idx_size = docs.size();
          if (idx_size < 16) {
            log("[WARN] Indexes size (" + idx_size + ") is less then expected (16). Some Index might be missing.");
            printMissingIndex(docs);
          }
          if (idx_size != 16) {
            log(docs.toString());
          }

          for (ODocument idx : docs) {
            String iname = idx.field("name");
            List<ODocument> _idx_c = execQueries(tx, "select count(*) as c from index:" + iname);
            if (iname.equals("asset_bucket_name_idx")) {
              abn_idx_c = _idx_c.get(0).field("c");
            }
            else if (iname.equals("asset_bucket_component_name_idx")) {
              abcn_idx_c = _idx_c.get(0).field("c");
            }
            log("Index: " + iname + " count: " + _idx_c.get(0).field("c").toString());
          }

          // Current limitation/restriction: asset_bucket_name_idx is required (accept 10% difference as this is for estimation).
          if (abn_idx_c > 0 && (abn_idx_c * 1.1) < ac) {
            log("[ERROR] asset_bucket_name_idx count is too small. Please do 'REBUILD INDEX asset_bucket_name_idx' first.");
            System.exit(1);
          }

          // Get repository names to count records per repos with alphabetical order
          List<ODocument> bkts =
              execQueries(tx, "select @rid as r, repository_name from bucket ORDER BY repository_name");

          for (ODocument bkt : bkts) {
            String q =
                "select count(*) as c from index:asset_bucket_name_idx where key = [" +
                    ((ODocument) bkt.field("r")).getIdentity().toString() + "]";
            List<ODocument> c_per_bkt = execQueries(tx, q);
            String repoName = bkt.field("repository_name");
            Long c = c_per_bkt.get(0).field("c");
            log("Repository: " + bkt.field("repository_name") + " estimated count: " + c.toString());
            // super rough estimate. Just guessing one record would use 3KB (+1GB).
            estimateMb = estimateSize(c);
            if (maxMb < estimateMb) {
              debug("Heap: " + maxMb + " MB may not be enough for " + repoName + " (estimate: " + estimateMb + " MB).");
              repo_names_skipped.add(repoName);
            }
            else if (c == 0) {
              debug("No record for " + repoName + ", so skipping.");
              //repo_names_skipped.add(repoName); but not adding into repo_names_skipped
            }
            else {
              repo_names.add(repoName);
              repo_counts.put(repoName, c);
            }
          }
          log("Repository names to check (" + repo_names.size() + "):\n" + repo_names.toString());
        }

        if (ac.equals(abcn_idx_c)) {
          // TODO: Not so good logic. Currently if -DrepoNames is given, abcn_idx_c is 0 (if ac is 0, already exit)
          log("Asset count (" + ac.toString() +
              ") is equal to the asset_bucket_component_name_idx count, so not checking duplicates." +
              "\nTo force, rerun with -DrepoNames=xxx,yyy,zzz");
        }
        else {
          boolean is_dupe_found = false;

          if (check_all_repo) {
            is_dupe_found = checkDupes(tx, null);
          }
          else {
            is_dupe_found = checkDupesForRepos(tx, repo_names, repo_counts);
          }

          if (is_dupe_found) {
            out("-- REPAIR DATABASE --fix-links;");
            out("REBUILD INDEX asset_bucket_component_name_idx;");
            out("-- REBUILD INDEX *;");
          }

          if (repo_names_skipped.size() > 0) {
            out("-- [WARN] Skipped repositories: " + repo_names_skipped.toString() +
                "\n--        To force, rerun with -Xmx*g -DrepoNames=xxx,yyy,zzz");
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
