/*
 * (PoC) Simple duplicate checker for Asset records
 *
 * curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/asset-dupe-checker.jar"
 * java -Xms4g -Xmx4g [-Ddebug=true] [-DextractDir=./path] [-DrepoNames=xxx,yyy,zzz] -jar ./asset-dupe-checker.jar <component directory path|.bak file path> | tee asset-dupe-checker.sql
 *
 * After above, in the OrientDB Console, "LOAD SCRIPT ./asset-dupe-checker.sql"
 *
 * NOTE:
 *  If export/import-ed, then RID will be changed.
 *    This command outputs fixing SQL statements in STDOUT.
 *    "extractDir" is the path used when a .bak file is given. If extractDir is empty, use the tmp directory and the extracted data will be deleted on exit.
 *  "repoNames" is a comma separated repository names to force checking these repositories only.
 *
 * TODO: Add tests. Cleanup the code (too messy...)
 *
 * My note:
 *  mvn clean package && cp -v ./target/asset-dupe-checker-1.0-SNAPSHOT-jar-with-dependencies.jar ../../misc/asset-dupe-checker.jar
 */

import com.orientechnologies.orient.core.Orient;
import com.orientechnologies.orient.core.conflict.OVersionRecordConflictStrategy;
import com.orientechnologies.orient.core.db.document.ODatabaseDocumentTx;
import com.orientechnologies.orient.core.exception.OCommandExecutionException;
import com.orientechnologies.orient.core.exception.ODatabaseException;
import com.orientechnologies.orient.core.id.ORecordId;
import com.orientechnologies.orient.core.record.impl.ODocument;
import com.orientechnologies.orient.core.sql.query.OSQLSynchQuery;
import net.lingala.zip4j.ZipFile;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

public class Main
{
  private static long MAXMB;
  private static String EXTRACT_DIR = "";
  private static String LOG_PATH = "";
  private static List<String> REPO_NAMES_INCLUDE = new ArrayList<>();
  private static List<String> REPO_NAMES_EXCLUDE = new ArrayList<>();
  private static Map<String, Long> REPO_COUNTS = new HashMap<>();
  private static String LIMIT = "-1";
  private static Path TMP_DIR = null;
  private static double MAGNIFY_PERCENT = 300.0;
  //private static boolean CHECK_PER_COMP;
  private static boolean NO_DUPE_CHECK;

  //private static boolean DUPE_CHECK_WITH_INDEX;
  private static boolean IS_DEBUG;
  private static long SUBTTL;

  private Main() { }

  private static void usage() {
    System.out.println("Usage:");
    System.out.println("  java -Xmx4g -jar asset-dupe-checker.jar <component directory path> | tee asset-dupe-checker.sql");
    System.out.println("System properties:");
    System.out.println("  -DextractDir=<extracting path>  Directory used for extracting component-*.bak file");
    System.out.println("  -DrepoNames=<repo1,repo2,...>   To specify (force) the repositories to check");
    System.out.println("  -DrepoNamesExclude=<repo1,...>  To exclude specific repositories");
    System.out.println("  -DmagnifyPercent=<int>          0 disables estimations/validations, and checks one repository each");
    //System.out.println("  -DcheckPerComp=true For extremely large repository");
    System.out.println("  -Dlimit=<int>                   Limit the duplicate row result (this is for testing)");
    System.out.println("  -DnoDupeCheck=true              For testing/debugging this code");
    //System.out.println("  -DdupeCheckWithIndex=true       In case you would like to avoid 'REBUILD INDEX'");
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
    // If magnify_percent is 300%, assuming 1 row = 3KB + 1KB = 4KB
    return (long) Math.ceil(((c * MAGNIFY_PERCENT / 100) + 1024) / 1024);
  }

  public static List<ODocument> execQueries(ODatabaseDocumentTx tx, String input) {
    List<ODocument> results = null;
    debug("Query: executing '" + input + "' ...");
    Instant start = Instant.now();
    try {
      results = tx.query(new OSQLSynchQuery(input));
    }
    // TODO: Not sure if these are catchable. Also BufferUnderflowException tends to cause 'OutOfMemoryError: Java heap space'
    catch (ODatabaseException | OCommandExecutionException | ClassCastException | java.nio.BufferUnderflowException | java.lang.NullPointerException e) {
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
        .asList("asset_bucket_component_name_idx", "asset_bucket_name_idx", "asset_component_idx", "asset_name_ci_idx", //asset_bucket_rid_idx??
            "browse_node_asset_id_idx", "browse_node_component_id_idx", "browse_node_repository_name_parent_path_name_idx",
            "bucket_repository_name_idx",
            "component_bucket_group_name_version_idx", "component_bucket_name_version_idx", "component_ci_name_ci_idx", "component_group_name_version_ci_idx", "component_tags_idx",
            "coordinate_download_count_namespace_name_version_ip_address_idx", "coordinate_download_count_namespace_name_version_repository_name_idx", "coordinate_download_count_namespace_name_version_username_idx", "coordinate_download_count_repository_name_namespace_name_version_date_ip_address_username_idx",
            "deleted_blob_index_blobstore_blob_id_idx",
            "docker_foreign_layers_digest_idx",
            "statushealthcheck_node_id_idx",
            "tag_name_idx");
    List<String> current_idxs = new ArrayList<>();
    for (ODocument doc : docs) {
      current_idxs.add(doc.field("name").toString());
    }
    for (String idx : expected_idxs) {
      if (!current_idxs.contains(idx)) {
        out("-- [WARN] Missing index (not considering version): " + idx);
      }
    }
  }

  public static boolean checkDupes(ODatabaseDocumentTx tx, List<String> repoNames) {
    boolean is_dupe_found = false;
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
        "SELECT FROM (SELECT bucket, LIST(@rid) as dupe_rids, MAX(@rid) as keep_rid, count(*) as c FROM asset " +
            where + " GROUP BY bucket, component, name) WHERE c > 1 LIMIT " + LIMIT + ";");
    if (dups != null && repoNames != null) {
      log("Found " + dups.size() + " duplicates from " + repoNames.size() + " repositories with LIMIT " + LIMIT);
    }
    if (outputTruncate(dups)) {
      is_dupe_found = true;
    }
    return is_dupe_found;
  }

  private static boolean checkDupesPerComp(ODatabaseDocumentTx tx, String repoName) {
    // TODO: too slow, so stopped using this.
    boolean is_dupe_found = false;
    if (repoName != null && !repoName.trim().isEmpty()) {
      List<ODocument> comps = execQueries(tx,"SELECT @rid as r FROM component WHERE bucket.repository_name = '" + repoName +"' LIMIT -1;");
      debug("Component size for " + repoName + " = " + comps.size());
      Boolean current_debug = IS_DEBUG;
      IS_DEBUG = false;
      long progress = 1;
      for (ODocument comp : comps) {
        String rid = ((ODocument) comp.field("r")).getIdentity().toString();
        // TODO: using LIKE makes below query extremely slow, however, without LIKE, OrientDB doesn't return correct result...
        List<ODocument> dups = execQueries(tx,
            "SELECT FROM (SELECT LIST(@rid) as dupe_rids, MAX(@rid) as keep_rid, count(*) as c FROM asset WHERE component LIKE " +
                rid + " AND bucket.repository_name LIKE '" + repoName + "' GROUP BY bucket, component, name) WHERE c > 1 LIMIT " + LIMIT +
                ";");
        if (outputTruncate(dups)) {
          is_dupe_found = true;
        }

        if (progress % 1000 == 0) {
          log("Checked " + progress + " / " + comps.size() + " ...");
        }
        progress++;
      }
      IS_DEBUG = current_debug;
    }
    return is_dupe_found;
  }

  private static boolean outputTruncate(List<ODocument> dups) {
    boolean is_dupe_found = false;
    for (ODocument doc : dups) {
      log(doc.toJSON());
      // output TRUNCATE RECORD statements
      ODocument keep_rid = doc.field("keep_rid");
      List<ORecordId> dupe_rids = doc.field("dupe_rids");
      for (ORecordId dr : dupe_rids) {
        //if (DUPE_CHECK_WITH_INDEX) { TODO }
        if (!dr.getIdentity().toString().equals(keep_rid.getIdentity().toString())) {
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
      long maxMb,
      boolean checkEachRepo
  )
  {
    boolean isDupeFound = false;
    SUBTTL = 0L;
    List<String> subRepoNames = new ArrayList<>();

    for (String repoName : repoNames) {
      if (repoName.trim().isEmpty()) {
        continue;
      }

      // NOTE: shouldRunCheckDupes() updates subRepoNames if force check mode (it's inconsistent but SUBTTL as well).
      boolean runCheckDupes = shouldRunCheckDupesNow(repoName, subRepoNames, maxMb);
      if (subRepoNames.size() > 0 && repoNames.size() > 0 && (checkEachRepo || runCheckDupes)) {
        log("Running checkDupes() against " + subRepoNames.size() + " repositories.\n" + subRepoNames);
        if (checkDupes(tx, subRepoNames)) {
          isDupeFound = true;
        }
        SUBTTL = 0L;
        subRepoNames = new ArrayList<>();
      }

      if (REPO_COUNTS.containsKey(repoName) && !REPO_NAMES_EXCLUDE.contains(repoName) && !subRepoNames.contains(repoName)) {
        SUBTTL += REPO_COUNTS.get(repoName);
        subRepoNames.add(repoName);
      }
    }

    // In case the subRepoNames is still not empty.
    if (subRepoNames.size() > 0) {
      log("Running the checkDupes() against " + subRepoNames.size() + " repositories.\n" + subRepoNames);
      if (checkDupes(tx, subRepoNames)) {
        isDupeFound = true;
      }
    }
    return isDupeFound;
  }

  private static boolean shouldRunCheckDupesNow(
      String repoName,
      List<String> subRepoNames,
      long maxMb
  )
  {
    // Force checking *current* repoName if below condition matches.
    // I don't think REPO_COUNTS == null is possible but just in case, also REPO_COUNTS.get(repoName) = -1L means force.
    if (REPO_COUNTS == null || REPO_COUNTS.isEmpty() ||
        (REPO_COUNTS.containsKey(repoName) && REPO_COUNTS.get(repoName) < 0)) {
      return true;
    }
    // If this repo doesn't have any records, skip this repo (so not adding into subRepoNames and no point of increasing SUBTTL)
    if (!REPO_COUNTS.containsKey(repoName) || REPO_COUNTS.get(repoName) == 0) {
      if (!REPO_NAMES_EXCLUDE.contains(repoName)) {
        REPO_NAMES_EXCLUDE.add(repoName);
      }
      return false;
    }

    long c = REPO_COUNTS.get(repoName);
    // super rough estimate. Just guessing one record would use 3KB (+1KB).
    long estimateMb = estimateSizeMB(c);
    if (maxMb < estimateMb) {
      log("[WARN] Heap: " + maxMb + " MB may not be enough for " + repoName + " (count:" + c + ", estimate:" +
          estimateMb + " MB).");
      if(REPO_NAMES_INCLUDE == null || !REPO_NAMES_INCLUDE.contains(repoName)) {
        log("       To force, rerun with higher '-Xmx*g' and '-DrepoNames=" + repoName + "' (and save output to a different file)");
        out("-- [WARN] Skipped '" + repoName + "' repository (" + c + ")");
        if (!REPO_NAMES_EXCLUDE.contains(repoName)) {
          REPO_NAMES_EXCLUDE.add(repoName);
        }
        return false;
      }
    }

    long estimateSubTtlSize = estimateSizeMB((SUBTTL + c));
    debug("Repository name:" + repoName + ", rows:" + REPO_COUNTS.get(repoName) + ", subTtl:" + (SUBTTL + c) +
        ", estimate_size:" + estimateSubTtlSize + "/" + maxMb);
    if (subRepoNames.size() > 0 && estimateSubTtlSize > maxMb) {
      log("Running checkDupes() as adding " + repoName + " (count:" + c + ", estimate:" + estimateMb +
          " MB) may exceed the limit (" +
          subRepoNames.size() + " repositories / subTtlBefore:" + (SUBTTL) + ").");
      return true;
    }

    // Avoiding too long "IN" so set max 300 to the sub repository names.
    if (subRepoNames.size() >= 300) {
      return true;
    }
    // If false, that means checking next repo, so increase the subtotal now.
    return false;
  }

  public static void getRepoNamesCounts(ODatabaseDocumentTx tx, List<String> repoNamesInclude, List<String> repoNamesExclude, boolean noEstimateCheck) {
    REPO_COUNTS = new HashMap<>();
    // Intentionally sorting with repository_name
    List<ODocument> bkts = execQueries(tx, "select @rid as r, repository_name from bucket ORDER BY repository_name");
    // NOTE: 'where key = [bucket.rid]' works, but 'select key, count(*) as c from index:asset_bucket_name_idx group by key;' does not, so looping...
    for (ODocument bkt : bkts) {
      String repoId = ((ODocument) bkt.field("r")).getIdentity().toString();
      String repoName = bkt.field("repository_name");

      if (repoNamesInclude != null && repoNamesInclude.size() > 0 && !repoNamesInclude.contains(repoName)) {
        debug("Repository name:" + repoName + " is not in the repoNames (include). Skipping...");
        continue;
      }
      if (repoNamesExclude != null && repoNamesExclude.size() > 0 && repoNamesExclude.contains(repoName)) {
        debug("Repository name:" + repoName + " is in the repoNamesExclude. Skipping...");
        continue;
      }

      long c = -1L;
      if(!noEstimateCheck) {
        // NOTE: To check count: "select bucket, count(*) as c from asset group by bucket;" might be faster???
        String q = "select count(*) as c from index:asset_bucket_name_idx where key = [" + repoId + "]";
        List<ODocument> c_per_bkt = execQueries(tx, q);
        c = c_per_bkt.get(0).field("c");
        log("Repository:" + repoName + "(" + repoId + ") estimated count:" + c);
        if (c == 0) {
          debug("No record for " + repoName + ".");
          continue;
        }
      }
      REPO_COUNTS.put(repoName, c);
    }
  }

  private static Long getIndexCount(ODatabaseDocumentTx tx, String iname) {
    Long c = 0L;
    try {
      List<ODocument> _idx_c = execQueries(tx, "select count(*) as c from index:" + iname);
      c = _idx_c.get(0).field("c");
      log("Index: " + iname + " count: " + c.toString());
    } catch (Exception e) {
      log("[ERROR] getIndexCount exception:" + e.getMessage());
    }
    return c;
  }

  private static void setGlobals() {
    IS_DEBUG = Boolean.getBoolean("debug");
    EXTRACT_DIR = System.getProperty("extractDir", "");
    debug("extDir: " + EXTRACT_DIR);
    String repoNamesStr = System.getProperty("repoNames", "");
    if (!repoNamesStr.trim().isEmpty()) {
      REPO_NAMES_INCLUDE = Arrays.asList(repoNamesStr.trim().split(","));
    }
    debug("repoNames: " + REPO_NAMES_INCLUDE);
    String repoNamesExcludeStr = System.getProperty("repoNamesExclude", "");
    if (!repoNamesExcludeStr.trim().isEmpty()) {
      REPO_NAMES_EXCLUDE = Arrays.asList(repoNamesExcludeStr.trim().split(","));
    }
    debug("repoNamesExclude: " + REPO_NAMES_EXCLUDE);
    MAGNIFY_PERCENT = Double.parseDouble(System.getProperty("magnifyPercent", "300"));
    debug("magnifyPercent: " + MAGNIFY_PERCENT);
    LIMIT = System.getProperty("limit", "-1");
    debug("limit: " + LIMIT);
    //CHECK_PER_COMP = Boolean.getBoolean("checkPerComp");
    //debug("checkPerComp: " + CHECK_PER_COMP);
    NO_DUPE_CHECK = Boolean.getBoolean("noDupeCheck");
    debug("noDupeCheck: " + NO_DUPE_CHECK);
    //DUPE_CHECK_WITH_INDEX = Boolean.getBoolean("dupeCheckWithIndex");
    //debug("dupeCheckWithIndex: " + DUPE_CHECK_WITH_INDEX);
    LOG_PATH = System.getProperty("logPath", "./asset-dupe-checker.log");
    debug("logPath: " + LOG_PATH);
    MAXMB = Runtime.getRuntime().maxMemory() / 1024 / 1024;
    debug("maxMb: " + MAXMB);
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
    Long bnrpn_idx_c = 0L;
    Map<String, Long> repo_counts = new HashMap<>();
    List<String> repoNames = new ArrayList<>();

    log("main() started with maxMb = " + MAXMB);

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
        boolean needTrunBrowse = false;

        if (MAGNIFY_PERCENT == 0.0) {
          log("magnifyPercent is 0%, so cannot do the estimation. Skipping various checks.");
          getRepoNamesCounts(tx, REPO_NAMES_INCLUDE, REPO_NAMES_EXCLUDE, true);
          repoNames.addAll(REPO_COUNTS.keySet());
        }
        else if (MAXMB > estimateMb) {
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
          }
          // NOTE: This also populate MISSING_INDEXES list
          printMissingIndex(docs);
          if (idx_size != 16) {
            log(docs.toString());
          }

          // Checking each index count
          for (ODocument idx : docs) {
            String iname = idx.field("name");
            if (iname.equals("asset_bucket_name_idx")) {
              abn_idx_c = getIndexCount(tx, iname);
            }
            else if (iname.equals("asset_bucket_component_name_idx")) {
              abcn_idx_c = getIndexCount(tx, iname);
            }
            else if (iname.equals("component_bucket_group_name_version_idx")) {
              cbgnv_idx_c = getIndexCount(tx, iname);
            }
            else if (iname.equals("browse_node_repository_name_parent_path_name_idx")) {
              bnrpn_idx_c = getIndexCount(tx, iname);
            }
          }

          // Current limitation/restriction: asset_bucket_name_idx is required (10% difference as this is estimation).
          if (abn_idx_c > 0 && (abn_idx_c * 1.1) < ac) {
            log("[ERROR] asset_bucket_name_idx count is too small against the asset count. Please do 'REBUILD INDEX asset_bucket_name_idx' first.");
            System.exit(1);
          }

          // Extra checks
          docs = execQueries(tx, "select count(*) as c from component");
          Long cc = docs.get(0).field("c");
          debug("Component count: " + cc);
          if (cbgnv_idx_c > 0 && cbgnv_idx_c < cc ) {
            log("[WARN] component_bucket_group_name_version_idx (" + cbgnv_idx_c + ") < component count (" + cc + "). Component may have duplicates");
          }

          // Just in case, counting browse_node
          docs = execQueries(tx, "select count(*) as c from browse_node");
          long bn_c = docs.get(0).field("c");
          debug("Browse_node count: " + bn_c + " / index: " + (bnrpn_idx_c));
          if (ac > 0 && bn_c > 0 && (bnrpn_idx_c > 0 && bnrpn_idx_c < bn_c)) {
            log("[WARN] browse_node_repository_name_parent_path_name_idx (" + bnrpn_idx_c + ") < browse_node count (" + bn_c + "). Browse_node may have duplicates");
            needTrunBrowse = true;
          }
          getRepoNamesCounts(tx, REPO_NAMES_INCLUDE, REPO_NAMES_EXCLUDE, NO_DUPE_CHECK);
          repoNames.addAll(REPO_COUNTS.keySet());
        }

        if (abcn_idx_c > 0 && ac.equals(abcn_idx_c) && (REPO_NAMES_INCLUDE == null || REPO_NAMES_INCLUDE.size() == 0)) {
          log("Asset count (" + ac + ") is same as asset_bucket_component_name_idx, so not checking duplicates.\n" +
              "To force, rerun with -DrepoNames=xxx,yyy,zzz");
        }
        else {
          boolean is_dupe_found = false;
          if (NO_DUPE_CHECK) {
            log("Not checking any duplicates for (this is for testing)\n" + repoNames);
          }
          else if (check_all_repo) {
            is_dupe_found = checkDupes(tx, null);
          }
          else {
            log("Starting checkDupesForRepos for total " + repoNames.size() + " repositories:\n" + repoNames);
            is_dupe_found = checkDupesForRepos(tx, repoNames, MAXMB, (MAGNIFY_PERCENT == 0.0));
          }

          if (is_dupe_found) {
            out("--REPAIR DATABASE --fix-links;");
            //out("--REBUILD INDEX *;");
            out("--REBUILD INDEX asset_bucket_component_name_idx;");
            if (needTrunBrowse) {
              out("TRUNCATE CLASS browse_node;");
            }
            else {
              out("--TRUNCATE CLASS browse_node;");
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
    delR(TMP_DIR);
  }
}
