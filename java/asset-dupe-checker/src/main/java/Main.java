/*
 * (PoC) Simple duplicate checker for Asset records
 *
 * curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/asset-dupe-checker.jar"
 * java -Xmx4g -XX:MaxDirectMemorySize=4g [-Ddebug=true] [-DextractDir=./path] [-DrepoNames=xxx,yyy,zzz] -jar asset-dupe-checker.jar <component directory path|.bak file path> | tee asset-dupe-checker.sql
 *
 * In the OrientDB Console, "LOAD SCRIPT ./asset-dupe-checker.sql"
 *
 *    This command outputs fixing SQL statements in STDOUT.
 *    "extractDir" is the path used when a .bak file is given. If extractDir is empty, use the tmp directory and the extracted data will be deleted on exit.
 *    "repoNames" is a comma separated repository names to check these repositories only.
 *
 * TODO: add tests. Cleanup the code (main)..., convert to Groovy.
 * TODO: Check component table too, because deleting component may require to update asset.component column.
 *
 * My note:
 *  mvn clean package && cp -v ./target/asset-dupe-checker-1.0-SNAPSHOT-jar-with-dependencies.jar ../../misc/asset-dupe-checker.jar
 */

import com.orientechnologies.orient.core.Orient;
import com.orientechnologies.orient.core.conflict.OVersionRecordConflictStrategy;
import com.orientechnologies.orient.core.db.document.ODatabaseDocumentTx;
import com.orientechnologies.orient.core.exception.ODatabaseException;
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
  private static String extDir = "";
  private static String repoNames = "";
  private static String repoNamesExclude = "";
  private static String limit = "1000";
  private static Path tmpDir = null;
  private static double magnifyPercent = 400.0;
  private static boolean noDupeCheck;
  private static boolean isDebug;

  private Main() { }

  private static void usage() {
    System.out.println("Usage:");
    System.out.println("  java -Xmx4g -jar asset-dupe-checker.jar <component directory path> | tee asset-dupe-checker.sql");
    System.out.println("Acceptable System properties:");
    System.out.println("  -DrepoNames=<repo1,repo2,... to specify repositories to check>");
    System.out.println("  -DrepoNamesExclude=<repo1,repo2,... to exclude specific repositories>");
    System.out.println("  -DmagnifyPercent=<int. For estimating size (default 400). Higher makes conservative but using 0 checks one repository each>");
    System.out.println("  -Dlimit=<int. Currently duplicates over 1000 per query is ignored as not expecting so many duplicates>");
    System.out.println("  -DextractDir=<extracting path for component-*.bak>");
    System.out.println("  -DnoDupeCheck=true");
    System.out.println("  -Ddebug=true");
  }

  private static String getCurrentLocalDateTimeStamp() {
    return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"));
  }

  private static void log(String msg) {
    // TODO: proper logging
    System.err.println(getCurrentLocalDateTimeStamp() + " " + msg);
  }

  private static void debug(String msg) {
    if (isDebug) {
      log("[DEBUG] " + msg);
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
    // if dirPath is empty, use a temp directory
    if (dirPath.trim().isEmpty()) {
      tmpDir = Files.createTempDirectory(null);
      tmpDir.toFile().deleteOnExit();
      extDir = tmpDir.toString();
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
    // TODO: check if dirPath has enough space properly (currently just requesting 10 times of .bak file).
    long usable_space = Files.getFileStore(new File(dirPath).toPath()).getUsableSpace();
    long zip_file_size = (new File(zipFilePath)).length();
    if (zip_file_size * 10 > usable_space) {
      log("[ERROR] " + dirPath + " (usable:" + usable_space + ") may not be enough for extracting " + zipFilePath + " (size:" +
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

  private static long estimateSizeMB(long c) {
    // If magnify_percent is 400%, assuming 1 row = 5KB
    return (long) Math.ceil(((c * magnifyPercent / 100) + 1024) / 1024);
  }

  public static List<ODocument> execQueries(ODatabaseDocumentTx tx, String input) {
    List<ODocument> results = null;
    debug("Query: executing '" + input + "' ...");
    Instant start = Instant.now();
    try {
      results = tx.query(new OSQLSynchQuery(input));
    }
    catch (ODatabaseException | ClassCastException e) {
      log("[ERROR] " + e.getMessage());
      //e.printStackTrace();
    }
    finally {
      Instant finish = Instant.now();
      debug("Query: '" + input + "', Elapsed: " + Duration.between(start, finish).toMillis() + " ms");
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
    List<String> current_idxs = new ArrayList<>();
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
    StringBuilder where_repos = new StringBuilder();
    if (repoNames != null && repoNames.size() > 0) {
      // Can't use " in ['...','...'] when we suspect asset_bucket_component_name_idx
      where_repos = new StringBuilder("(");
      for (int i = 0; i < repoNames.size(); i++) {
        if (i > 0) {
          where_repos.append(" OR ");
        }
        // Using 'LIKE' is intentional, so that this query won't use the potentially broken index (but slow)
        where_repos.append("bucket.repository_name LIKE '").append(repoNames.get(i)).append("'");
      }
      where_repos.append(")");
    }
    String where = "";
    if (where_repos.length() > 0) {
      where = "WHERE " + where_repos;
    }
    List<ODocument> dups = execQueries(tx,
        // Seems reducing columns reduce heap usage, so not using "bucket.repository_name as repo_name, component, name"
        "SELECT FROM (SELECT LIST(@rid) as dupe_rids, MAX(@rid) as keep_rid, COUNT(*) as c FROM asset " +
            where +
            " GROUP BY bucket, component, name) WHERE c > 1 LIMIT " + limit + ";");

    boolean is_dupe_found = false;
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
    long sub_ttl = 0L;
    List<String> sub_repo_names = new ArrayList<>();
    List<String> repo_names_exclude = Arrays.asList(repoNamesExclude.split(","));

    for (String repo_name : repoNames) {
      if (repo_name.trim().isEmpty()) {
        continue;
      }
      if (repo_names_exclude.contains(repo_name.trim())) {
        log("Repository name:" + repo_name + " is in the repoNamesExclude. Skipping...");
        continue;
      }

      boolean runCheckDupes = false;
      if(magnifyPercent == 0.0 && sub_repo_names.size() > 0) {
        runCheckDupes = true;
      }
      else if (magnifyPercent > 0.0 && repoCounts.containsKey(repo_name)) {
        sub_ttl += repoCounts.get(repo_name);
        long est = estimateSizeMB(sub_ttl);
        debug("Repository name:" + repo_name + ", rows:" + repoCounts.get(repo_name) + ", sub_ttl:" + sub_ttl + ", estimate_size:" + est + "/" + maxMb );
        if (sub_repo_names.size() > 0 && est > maxMb) {
          runCheckDupes= true;
        }
      }

      if (runCheckDupes) {
        log("Running checkDupes() against (" + sub_repo_names.size() + "): " + sub_repo_names);
        if (checkDupes(tx, sub_repo_names)) {
          is_dupe_found = true;
        }
        sub_ttl = 0L;
        sub_repo_names = new ArrayList<>();
      }
      sub_repo_names.add(repo_name);
    }

    if (sub_repo_names.size() > 0) {
      log("Running checkDupes() against (" + sub_repo_names.size() + "): " + sub_repo_names);
      if (checkDupes(tx, sub_repo_names)) {
        is_dupe_found = true;
      }
    }
    return is_dupe_found;
  }

  private static void setGlobals() {
    extDir = System.getProperty("extractDir", "");
    repoNames = System.getProperty("repoNames", "");
    repoNamesExclude = System.getProperty("repoNamesExclude", "");
    magnifyPercent = Double.parseDouble(System.getProperty("magnifyPercent", "400"));
    limit = System.getProperty("limit", "1000");
    noDupeCheck = Boolean.getBoolean("noDupeCheck");
    isDebug = Boolean.getBoolean("debug");
    maxMb = Runtime.getRuntime().maxMemory() / 1024 / 1024;
  }

  public static void main(final String[] args) throws IOException {
    if (args.length < 1) {
      usage();
      System.exit(1);
    }
    setGlobals();

    String path = args[0];
    String connStr;
    Long abn_idx_c = 0L;
    Long abcn_idx_c = 0L;
    Long cbgnv_idx_c = 0L;
    List<String> repo_names = new ArrayList<>();
    List<String> repo_names_skipped = new ArrayList<>();
    Map<String, Long> repo_counts = new HashMap<>();

    log("main() started with maxMb = " + maxMb);

    if (!(new File(path)).isDirectory()) {
      try {
        if (!prepareDir(extDir, path)) {
          System.exit(1);
        }
        log("Unzip-ing " + path + " to " + extDir);
        unzip(path, extDir);
        path = extDir;
      }
      catch (Exception e) {
        log("[ERROR] " + path + " is not a right archive.");
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
          log("[ERROR] Asset table/class is empty.");
          System.exit(1);
        }
        log("Asset count: " + ac);

        long estimateMb = estimateSizeMB(ac);
        boolean check_all_repo = false;
        if (!repoNames.trim().isEmpty()) {
          repo_names = Arrays.asList(repoNames.split(","));
          log("Repo names: " + repo_names + " are provided, so not checking the record counts per repo.");
        }
        else if (magnifyPercent == 0.0) {
          log("magnifyPercent is 0%, so checking each repository.");
          List<ODocument> bkts =
              execQueries(tx, "select @rid as r, repository_name from bucket ORDER BY repository_name");
          for (ODocument bkt : bkts) {
            repo_names.add(bkt.field("repository_name"));
          }
        }
        else if (maxMb > estimateMb) {
          log("Asset count is small, so not checking each repositories.");
          check_all_repo = true;
        }
        else {
          // Checking how many Indexes.
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

          // Checking each index count
          for (ODocument idx : docs) {
            String iname = idx.field("name");
            List<ODocument> _idx_c = execQueries(tx, "select count(*) as c from index:" + iname);
            if (iname.equals("asset_bucket_name_idx")) {
              abn_idx_c = _idx_c.get(0).field("c");
            }
            else if (iname.equals("asset_bucket_component_name_idx")) {
              abcn_idx_c = _idx_c.get(0).field("c");
            }
            else if (iname.equals("component_bucket_group_name_version_idx")) {
              cbgnv_idx_c = _idx_c.get(0).field("c");
            }
            log("Index: " + iname + " count: " + _idx_c.get(0).field("c").toString());
          }

          // Current limitation/restriction: asset_bucket_name_idx is required (10% difference as this is estimation).
          if (abn_idx_c > 0 && (abn_idx_c * 1.1) < ac) {
            log("[ERROR] asset_bucket_name_idx count is too small against the asset count. Please do 'REBUILD INDEX asset_bucket_name_idx' first.");
            System.exit(1);
          }

          // Extra checks
          docs = execQueries(tx, "select count(*) as c from component");
          Long cc = docs.get(0).field("c");
          log("Component count: " + cc);
          if (cbgnv_idx_c > 0 && cbgnv_idx_c < cc ) {
            log("[WARN] component_bucket_group_name_version_idx is smaller than the component count. Please check if the component has any duplicates.");
          }

          // Just in case, counting browse_node (should count per repo?)
          docs = execQueries(tx, "select count(*) as c from browse_node");
          long bnc = docs.get(0).field("c");
          log("Browse_node count: " + bnc);
          double ratio = (double) bnc / (double) ac;
          if (ac > 0 && bnc > 0 && (ratio < 0.8 || ratio > 1.2)) {
            out("-- [WARN] may need 'TRUNCATE CLASS browse_node;'");
          }

          // Intentionally sorting with repository_name
          List<ODocument> bkts = execQueries(tx, "select @rid as r, repository_name from bucket ORDER BY repository_name");
          // NOTE: 'where key = [bucket.rid]' works, but 'select key, count(*) as c from index:asset_bucket_name_idx group by key;' does not, so looping...
          for (ODocument bkt : bkts) {
            String repoId = ((ODocument) bkt.field("r")).getIdentity().toString();
            String repoName = bkt.field("repository_name");
            String q = "select count(*) as c from index:asset_bucket_name_idx where key = [" + repoId + "]";
            List<ODocument> c_per_bkt = execQueries(tx, q);
            Long c = c_per_bkt.get(0).field("c");
            log("Repository: " + repoName + " estimated count: " + c.toString());
            // super rough estimate. Just guessing one record would use 3KB (+1GB).
            estimateMb = estimateSizeMB(c);
            if (maxMb < estimateMb) {
              debug("Heap: " + maxMb + " MB may not be enough for " + repoName + " (estimate: " + estimateMb + " MB).");
              repo_names_skipped.add(repoName);
            }
            else if (c == 0) {
              debug("No record for " + repoName + ".");
            }
            else {
              repo_names.add(repoName);
              repo_counts.put(repoName, c);
            }
          }
        }

        if (ac.equals(abcn_idx_c)) {
          // TODO: Not so good logic. Currently if -DrepoNames is given, abcn_idx_c is 0 (if ac is 0, already exit)
          log("Asset count (" + ac + ") is same as asset_bucket_component_name_idx, so not checking duplicates.\n" +
              "To force, rerun with -DrepoNames=xxx,yyy,zzz");
        }
        else {
          boolean is_dupe_found = false;

          if (noDupeCheck) {
            log("Not checking any duplicates for\n" + repo_names);
          }
          else if (check_all_repo) {
            is_dupe_found = checkDupes(tx, null);
          }
          else {
            log("Repository names to check (" + repo_names.size() + "):\n" + repo_names);
            is_dupe_found = checkDupesForRepos(tx, repo_names, repo_counts);
          }

          if (is_dupe_found) {
            out("--TRUNCATE CLASS browse_node;");
            out("--REPAIR DATABASE --fix-links;");
            out("--REBUILD INDEX *;");
            out("REBUILD INDEX asset_bucket_component_name_idx;");
          }

          if (repo_names_skipped.size() > 0) {
            out("-- [WARN] Skipped repositories: " + repo_names_skipped +
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
