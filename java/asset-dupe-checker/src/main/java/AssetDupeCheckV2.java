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
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import com.orientechnologies.orient.core.Orient;
import com.orientechnologies.orient.core.command.OCommandOutputListener;
import com.orientechnologies.orient.core.config.OGlobalConfiguration;
import com.orientechnologies.orient.core.conflict.OVersionRecordConflictStrategy;
import com.orientechnologies.orient.core.db.ODatabase;
import com.orientechnologies.orient.core.db.document.ODatabaseDocumentTx;
import com.orientechnologies.orient.core.db.tool.ODatabaseExport;
import com.orientechnologies.orient.core.db.tool.ODatabaseImport;
import com.orientechnologies.orient.core.id.ORID;
import com.orientechnologies.orient.core.index.ODefaultIndexFactory;
import com.orientechnologies.orient.core.index.OIndex;
import com.orientechnologies.orient.core.index.OIndexDefinition;
import com.orientechnologies.orient.core.index.OIndexDefinitionFactory;
import com.orientechnologies.orient.core.index.OIndexException;
import com.orientechnologies.orient.core.index.OIndexRebuildOutputListener;
import com.orientechnologies.orient.core.index.OIndexes;
import com.orientechnologies.orient.core.metadata.OMetadataDefault;
import com.orientechnologies.orient.core.metadata.schema.OClass.INDEX_TYPE;
import com.orientechnologies.orient.core.metadata.schema.OClassImpl;
import com.orientechnologies.orient.core.metadata.schema.OType;
import com.orientechnologies.orient.core.record.impl.ODocument;
import com.orientechnologies.orient.core.sql.OCommandSQL;
import com.orientechnologies.orient.core.storage.ORecordDuplicatedException;
import net.lingala.zip4j.ZipFile;

public class AssetDupeCheckV2
{
  private static String EXTRACT_DIR = "";

  private static String LOG_PATH = "";

  private static Path TMP_DIR = null;

  private static String TABLE_NAME = "";

  private static String INDEX_NAME = "";

  private static String INDEX_FIELDS = "";

  private static final List<String> SUPPORTED_INDEX_NAMES =
      Arrays.asList("asset_bucket_component_name_idx", "component_bucket_group_name_version_idx");

  private static final List<String> UPDATED_COMP_IDS = new ArrayList<>();

  private static Long DUPE_COUNTER = 0L;

  private static boolean IS_REPAIRING = false;

  private static boolean IS_REBUILDING = false;

  private static boolean IS_REIMPORTING = false;

  private static boolean IS_NO_INDEX_CHECK = false;

  private static boolean IS_DEBUG = false;

  private AssetDupeCheckV2() { }

  private static void usage() {
    System.out.println("Usage:");
    System.out.println(
        "  java -Xmx4g -XX:MaxDirectMemorySize=8g -jar asset-dupe-checker-v2.jar <component directory path> | tee asset-dupe-checker.sql");
    System.out.println("System properties:");
    System.out.println("  -DextractDir=./component            # Location of extracting component-*.bak file");
    System.out.println("  -Drepair=true                       # Remove duplicates and insert missing index records");
    System.out.println("  -Ddebug=true                        # Verbose outputs");
    System.out.println("Advanced properties (use those carefully):");
    System.out.println("  -DrebuildIndex=true                 # Rebuild index (eg:asset_bucket_component_name_idx)");
    System.out.println("  -DexportImport=true                 # DB Export to current (or extractDir), then import");
    System.out.println("  -DnoCheckIndex=true                 # Does not check index...");
    System.out.println("  -DindexName=component_bucket_group_name_version_idx");
    System.out.println("  -DtableName=component               # NOTE: be careful of repairing component");
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

  private static void exportDb(ODatabaseDocumentTx db, String exportTo) throws IOException {
    if ((new File(exportTo+".gz")).exists()) {
      log("[WARN] " + exportTo+".gz exists. Re-using...");
      return;
    }
    OCommandOutputListener listener = System.out::print;
    ODatabaseExport exp = new ODatabaseExport(db, exportTo, listener);
    exp.exportDatabase();
    exp.close();
    System.err.println("");
  }

  private static void importDb(ODatabaseDocumentTx db, String importName) throws IOException {
    if (!(new File(importName)).exists()) {
      importName = importName + ".gz";
    }
    OCommandOutputListener listener = System.out::print;
    // This automatically appends .gz. If fails, just throw IOException
    ODatabaseImport imp = new ODatabaseImport(db, importName, listener);
    imp.setPreserveClusterIDs(true);
    imp.importDatabase();
    imp.close();
    System.err.println("");
  }

  private static void exportImportDb(ODatabaseDocumentTx db) {
    String exportName = "component-export";
    String exportTo = "." + File.separatorChar + exportName;
    if (!EXTRACT_DIR.isEmpty()) {
      exportTo = EXTRACT_DIR + File.separatorChar + exportName;
    }
    try {
      exportDb(db, exportTo);
      // TODO: it seems to work without dropping, but should I drop?
      importDb(db, exportTo);
    } catch (IOException ioe) {
      log("[ERROR] " + ioe.getMessage());
    }
  }

  private static void setIndexFields(ODatabaseDocumentTx db) {
    if (!SUPPORTED_INDEX_NAMES.contains(INDEX_NAME)) {
      log("[ERROR] " + INDEX_NAME + " is not supported (supported: " + SUPPORTED_INDEX_NAMES + ")");
      return;
    }
    if (TABLE_NAME.isEmpty()) {
      String[] words = INDEX_NAME.split("_", 3);
      if (words.length == 0) {
        log("[ERROR] No table name specified for indexName:" + INDEX_NAME);
        return;
      }
      if (db.getMetadata().getSchema().getClass(words[0]) != null) {
        TABLE_NAME = words[0];
      }
      else if (words.length > 1 && db.getMetadata().getSchema().getClass(words[0] + "_" + words[1]) != null) {
        TABLE_NAME = words[0] + "_" + words[1];
      }
      else {
        log("[ERROR] No table name specified for indexName:" + INDEX_NAME);
        return;
      }
      log("Using TABLE_NAME:" + TABLE_NAME);
    }
    String fieldsStr = INDEX_NAME.replaceFirst("^" + TABLE_NAME + "_", "");
    fieldsStr = fieldsStr.replaceFirst("_idx$", "");
    INDEX_FIELDS = fieldsStr.replaceAll("_", ",");
  }

  private static OIndex<?> createIndex(ODatabaseDocumentTx db, boolean isDummy) {
    OIndex<?> index = null;
    if (INDEX_FIELDS.isEmpty()) {
      log("Index: " + INDEX_NAME + " does not exist and can't create.");
      return null;
    }
    try {
      String[] fields = INDEX_FIELDS.split(",");
      String type = INDEX_TYPE.UNIQUE.name();
      OClassImpl tbl = (OClassImpl) db.getMetadata().getSchema().getClass(TABLE_NAME);
      if (isDummy) {
        // OrientDB hack for setting rebuild = false in index.create()
        OIndexDefinition indexDefinition =
            OIndexDefinitionFactory.createIndexDefinition(tbl, Arrays.asList(fields), tbl.extractFieldTypes(fields),
                null, type, ODefaultIndexFactory.SBTREE_ALGORITHM);
        indexDefinition.setNullValuesIgnored(OGlobalConfiguration.INDEX_IGNORE_NULL_VALUES_DEFAULT.getValueAsBoolean());
        Set<String> clustersToIndex = findClustersByIds(tbl.getClusterIds(), db);
        index = OIndexes.createIndex(db, "dummy_" + INDEX_NAME, type, ODefaultIndexFactory.SBTREE_ALGORITHM,
            ODefaultIndexFactory.NONE_VALUE_CONTAINER, null, -1);
        index.create("dummy_" + INDEX_NAME, indexDefinition, OMetadataDefault.CLUSTER_INDEX_NAME, clustersToIndex,
            false, new OIndexRebuildOutputListener(index));
        debug("Created index:dummy_" + INDEX_NAME + "");
      }
      else {
        // Below rebuild indexes, and it doesn't look like the schema saved when exception.
        index = tbl.createIndex(INDEX_NAME, type, fields);
        // Below is simpler but again, it does not save schema when exception
        //String query = "CREATE INDEX " + INDEX_NAME + " ON " + TABLE_NAME + " (" + fields + ") UNIQUE;";
        //Object oDocs = db.command(new OCommandSQL(query)).execute();
        log("Created unique index:" + INDEX_NAME + " with " + INDEX_FIELDS + "");
      }
    }
    catch (ORecordDuplicatedException eDupe) {
      log("Ignoring ORecordDuplicatedException for index:" + INDEX_NAME + " - " + eDupe.getMessage());
      //eDupe.printStackTrace();
    }
    catch (Exception e) {
      // If table is corrupted, this may cause java.lang.ArrayIndexOutOfBoundsException but not sure what could be done in this code.
      log("[ERROR] Creating index:" + INDEX_NAME + " failed. May need to do DB export/import.");
      e.printStackTrace();
      return null;
    }
    finally {
      if (index != null) {
        db.getMetadata().getIndexManager().save();
      }
      else {
        index = db.getMetadata().getIndexManager().getIndex(INDEX_NAME);
      }
    }
    return index;
  }

  private static Set<String> findClustersByIds(int[] clusterIdsToIndex, ODatabase database) {
    Set<String> clustersToIndex = new HashSet<>();
    if (clusterIdsToIndex != null) {
      for (int clusterId : clusterIdsToIndex) {
        final String clusterNameToIndex = database.getClusterNameById(clusterId);
        if (clusterNameToIndex == null) {
          throw new OIndexException("Cluster with id " + clusterId + " does not exist.");
        }

        clustersToIndex.add(clusterNameToIndex);
      }
    }
    return clustersToIndex;
  }

  private static Boolean checkIndex(ODatabaseDocumentTx db) {
    OIndex<?> index = db.getMetadata().getIndexManager().getIndex(INDEX_NAME);
    boolean isDummyIdxCreated = false;
    if (IS_REPAIRING) {
      if (index == null) {
        log("[WARN] Index: " + INDEX_NAME + " does not exist. Trying to create (notunique, then unique)...");
        index = createIndex(db, true);
        if (index != null) {
          isDummyIdxCreated = true;
        }
      }
      else {
        index.clear();
      }
    }

    if (index == null) {
      log("Index: " + INDEX_NAME + " does not exist.");
      return false;
    }

    long count = 0L;
    long total = db.countClass(TABLE_NAME);
    try {
      log("*Estimate* count for " + TABLE_NAME + " = " + total);
      for (ODocument doc : db.browseClass(TABLE_NAME)) {
        count++;
        DUPE_COUNTER += checkIndexEntry(db, index, doc);
        if (count % 5000 == 0) {
          index.flush();
          log("Checking " + count + "/" + total + " (" + (int) ((count * 100) / total) + "%, duplicates:" +
              DUPE_COUNTER + ")");
        }
      }
      log("Checked indexName:" + INDEX_NAME + " - total:" + count + " duplicates:" + DUPE_COUNTER);

      if (index != null && isDummyIdxCreated) {
        IS_REBUILDING = false;  // no need to re-rebuild
        log("Re-creating index:" + INDEX_NAME);
        createIndex(db, false);
      }
    }
    finally {
      if (index != null && isDummyIdxCreated) {
        index.delete(); // cleaning up unnecessary temp/dummy index
        debug("Deleted index:dummy_" + INDEX_NAME);
      }
    }
    // If dupes found but not fixed, return false, so that it won't trigger index rebuild
    if (DUPE_COUNTER > 0 && !IS_REPAIRING) {
      return false;
    }
    return true;
  }

  private static int checkIndexEntry(ODatabaseDocumentTx db, OIndex<?> index, ODocument doc) {
    int dupeCounter = 0;
    ORID docId = doc.getIdentity();
    // This may cause NullPointerException when index does not exist,
    // or java.lang.ArrayIndexOutOfBoundsException if doc is corrupted
    List<String> fields = index.getDefinition().getFields();
    Object[] vals = new Object[fields.size()];
    try {
      for (int i = 0; i < vals.length; i++) {
        vals[i] = doc.field(fields.get(i));
      }
    }
    catch (ArrayIndexOutOfBoundsException e) {
      log("[WARN] Data corruption for docId: " + docId + "\n" + e.getMessage());
      // can't see the value with doc.toString and can't delete with db.delete.
    }
    Object indexKey = index.getDefinition().createValue(vals);
    boolean needPut = true;
    long c = index.count(indexKey);
    for (int i = 0; i < c; i++) {
      Object maybeDupe = index.get(indexKey);
      // This condition should not happen because of 'c', but just in case ...
      if (maybeDupe == null) {  // No index, so will put later
        break;
      }
      if (c == 1 && maybeDupe.toString().equals(docId.toString())) {  // only one index and same ID, so no put
        needPut = false;
        break;
        // if more than one index, should delete this one, so no extra handling required
      }
      dupeCounter++;
      actionsForDupe(db, (ORID) maybeDupe, docId, index, indexKey);
    }

    if (needPut) {
      try {
        // Regardless of IS_REPAIRING, needs to put to detect next duplicates for same key.
        index.put(indexKey, docId);
        debug("Put key: " + indexKey.toString() + ", values: " + docId.toString());
      }
      catch (ORecordDuplicatedException e) {
        log("[ERROR] " + e.getMessage());
      }
    }
    return dupeCounter;
  }

  private static List<ODocument> logAssets(ODatabaseDocumentTx db, ORID compId) {
    String query = "SELECT @rid as rid, bucket, component, name FROM asset WHERE component = " + compId.toString();
    List<ODocument> oDocs = db.command(new OCommandSQL(query)).execute();
    for (ODocument oDoc : oDocs) {
      log(oDoc.toJSON("rid,attribSameRow,alwaysFetchEmbedded,fetchPlan:*:0"));
    }
    return oDocs;
  }

  private static void actionsForDupe(
      ODatabaseDocumentTx db,
      ORID maybeDupe,
      ORID docId,
      OIndex<?> index,
      Object indexKey)
  {
    log("Duplicate found " + maybeDupe + " indexKey: " + indexKey.toString() + " (docId:" + docId + ")");
    ORID deletingId = maybeDupe;
    ORID keepingId = docId; // This means default is keeping the older one for UPDATE.
    boolean shouldUpdate;
    String updQuery;
    if (TABLE_NAME.equalsIgnoreCase("component")) {
      List<ODocument> docIdAssets = logAssets(db, docId);
      List<ODocument> maybeAssets = logAssets(db, maybeDupe);
      if (docIdAssets.size() < maybeAssets.size()) {
        deletingId = docId;
        keepingId = maybeDupe;
        shouldUpdate = (docIdAssets.size() > 0);
      }
      else {
        shouldUpdate = (maybeAssets.size() > 0);
      }
      if (shouldUpdate && !UPDATED_COMP_IDS.contains(deletingId.toString())) {
        updQuery = "UPDATE asset SET component = " + keepingId + " WHERE component = " + deletingId + ";";
        out(updQuery);
        UPDATED_COMP_IDS.add(deletingId.toString());

        if (IS_REPAIRING) {
          try {
            Object updNum = db.command(new OCommandSQL(updQuery)).execute();
            if (updNum instanceof Integer || updNum instanceof Long) {
              log("[WARN] Updated " + updNum + " assets which component Id = " + deletingId);
            }
            else {
              log("[ERROR] Updating assets which component Id = " + deletingId + " failed: " + updNum.toString());
            }
          }
          catch (Exception updEx) {
            log("[ERROR] Query: \"" + updQuery + "\" failed with Exception: " + updEx.getMessage());
          }
        }
      }
    }
    out("TRUNCATE RECORD " + deletingId + ";");

    if (IS_REPAIRING) {
      db.delete(deletingId);
      log("[WARN] Deleted duplicate: " + deletingId);
    }
    else {
      // Need to remove this one to detect another duplicates for same key (if repairing, above delete() also remove from index
      index.remove(indexKey, deletingId);
    }
  }

  private static boolean validateIndex(ODatabaseDocumentTx db) {
    List<ODocument> oDocs = db.command(new OCommandSQL(
            "select * from (select expand(indexes) from metadata:indexmanager) where name = '" + INDEX_NAME + "'"))
        .execute();
    if (oDocs.isEmpty()) {
      return false;
    }
    String indexDef = oDocs.get(0).toJSON("rid,attribSameRow,alwaysFetchEmbedded,fetchPlan:*:0"); //,prettyPrint
    log(indexDef);
    if (!indexDef.contains("\"" + INDEX_NAME + "\"")) {
      return false;
    }
    if (!indexDef.contains("\"" + INDEX_TYPE.UNIQUE.name() + "\"")) {
      return false;
    }

    String[] fields = INDEX_FIELDS.split(",");
    String testQuery = "EXPLAIN SELECT " + INDEX_FIELDS + " from " + TABLE_NAME + " WHERE 1 = 1";
    OClassImpl tbl = (OClassImpl) db.getMetadata().getSchema().getClass(TABLE_NAME);
    List<OType> fTypes = tbl.extractFieldTypes(fields);
    for (int i = 0; i < fields.length; i++) {
      String val = " IS NOT NULL";
      if (fTypes.get(i).toString().equalsIgnoreCase("LINK")) {
        val = " = #1:1";
      }
      else if (fTypes.get(i).toString().equalsIgnoreCase("STRING")) {
        val = " = 'test'";
      }
      testQuery = testQuery + " AND " + fields[i] + val;
    }
    String explainStr = ((ODocument) db.command(new OCommandSQL(testQuery)).execute()).toJSON(
        "rid,attribSameRow,alwaysFetchEmbedded,fetchPlan:*:0"); //,prettyPrint
    log(explainStr);
    if (!explainStr.contains("\"" + INDEX_NAME + "\"")) {
      return false;
    }
    return true;
  }

  private static void setGlobals() {
    IS_DEBUG = Boolean.getBoolean("debug");
    IS_REPAIRING = Boolean.getBoolean("repair");
    debug("repair: " + IS_REPAIRING);
    IS_REBUILDING = Boolean.getBoolean("rebuildIndex");
    debug("rebuildIndex: " + IS_REBUILDING);
    IS_REIMPORTING = Boolean.getBoolean("exportImport");
    debug("exportImport: " + IS_REIMPORTING);
    IS_NO_INDEX_CHECK = Boolean.getBoolean("noCheckIndex");
    debug("noCheckIndex: " + IS_NO_INDEX_CHECK);
    TABLE_NAME = System.getProperty("tableName", "");
    debug("tableName: " + TABLE_NAME);
    INDEX_NAME = System.getProperty("indexName", "asset_bucket_component_name_idx");
    debug("indexName: " + INDEX_NAME);
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

    long start = System.nanoTime();
    try (ODatabaseDocumentTx db = new ODatabaseDocumentTx(connStr)) {
      try {
        db.open("admin", "admin");
        log("Connected to " + connStr);
        setIndexFields(db);
        boolean result = true;
        if (!IS_NO_INDEX_CHECK) {
          result = checkIndex(db);
        }
        if (IS_REBUILDING) {
          if (!result) {
            log("Index rebuild is requested but not rebuilding as checkIndex returned false (dupes or missing index)");
          }
          else {
            rebuildIndex(db, INDEX_NAME);
            log("Rebuilt indexName: " + INDEX_NAME);
          }
        }
        if (IS_REIMPORTING) {
          exportImportDb(db);
        }

        log("Validating indexName: " + INDEX_NAME);
        if (!validateIndex(db)) {
          log("[ERROR] Validating indexName: " + INDEX_NAME + " failed");
        }
      }
      catch (Exception e) {
        e.printStackTrace();
      }
    }

    log("Completed. Elapsed " + ((System.nanoTime() - start) / 1000_000) + " ms");
    // Cleaning up the temp dir if used
    delR(TMP_DIR);
  }
}
