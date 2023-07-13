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

import static java.lang.Math.*;

public class AssetDupeCheckV2 {
    private static String EXTRACT_DIR = "";

    private static String LOG_PATH = "";

    private static String DB_DIR_PATH = "";

    private static Path TMP_DIR = null;

    private static String TABLE_NAME = "";

    private static String INDEX_NAME = "";

    private static String[] DROP_TABLES;

    // First one is the default index to be checked
    private static final List<String> SUPPORTED_INDEX_NAMES =
            Arrays.asList("asset_bucket_component_name_idx", "component_bucket_group_name_version_idx");

    private static final List<String> UPDATED_COMP_IDS = new ArrayList<>();

    private static Long DUPE_COUNTER = 0L;

    private static boolean IS_REPAIRING = false;

    private static boolean IS_REBUILDING = false;

    private static boolean IS_REIMPORTING = false;

    private static boolean IS_EXPORTING = false;

    private static boolean IS_REUSING_EXPORTED = false;

    private static boolean IS_NO_INDEX_CHECK = false;

    private static boolean IS_DEBUG = false;

    private AssetDupeCheckV2() {
    }

    private static void usage() {
        System.out.println("Usage:");
        System.out.println(
                "  java -Xmx4g -XX:MaxDirectMemorySize=8g -jar asset-dupe-checker-v2.jar <component directory path> | tee asset-dupe-checker.sql");
        System.out.println("System properties:");
        System.out.println("  -DextractDir=./component            # Location of extracting component-*.bak file");
        System.out.println("  -Drepair=true                       # Remove duplicates and insert missing index records");
        System.out.println("  -Ddebug=true                        # Verbose outputs");
        System.out.println("Advanced properties (use those carefully):");
        System.out.println("  -DrebuildIndex=true                 # Rebuild index (eg:asset_bucket_component_name_idx, '*')");
        System.out.println("  -DexportOnly=true                   # DB Export to current (or extractDir)");
        System.out.println("  -DimportReuse=true                  # If 'true', reuse the component-export.gz if exists");
        System.out.println("  -DexportImport=true                 # DB Export to current (or extractDir), then import");
        System.out.println("  -DnoCheckIndex=true                 # Does not check index...");
        System.out.println("  -DindexName=component_bucket_group_name_version_idx   # or '*'");
        System.out.println("  -DtableName=component               # NOTE: be careful of repairing component");
        System.out.println("  -DdropTables=deleted_blob_index     # Only for export/import");
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
            } catch (Exception logE) {
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
        } else if (!isDirEmpty(destDir.toPath())) {
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
                    } catch (IOException e) {
                        log("[ERROR] " + e.getMessage());
                    }
                });
    }

    private static long getIndexFileSize(String indexName) {
        Path path = Paths.get(DB_DIR_PATH, indexName + ".sbt");
        if (!Files.exists(path)) {
            path = Paths.get(DB_DIR_PATH, indexName + ".hib");
        }
        if (!Files.exists(path)) {
            return 0L;
        }
        try {
            return Files.size(path);
        } catch (IOException ioe) {
            return 0L;
        }
    }

    private static void rebuildIndex(ODatabaseDocumentTx db, String indexName) {
        if (indexName.equals("*")) {
            for (OIndex index : db.getMetadata().getIndexManager().getIndexes()) {
                String _indexName = index.getName();
                try {
                    rebuildIndex(db, _indexName);
                } catch (Exception e) {
                    log("[ERROR] Rebuilding " + _indexName + " failed with " + e.getMessage());
                }
            }
            return;
        }
        long idxSize = getIndexFileSize(indexName);
        log("Rebuilding indexName:" + indexName + " size:" + idxSize + " bytes");
        OIndex<?> index = db.getMetadata().getIndexManager().getIndex(indexName);
        index.rebuild();
        long idxSize2 = getIndexFileSize(indexName);
        int prct = 100;
        if (idxSize > 0) {
            prct = (int) round(((float) idxSize2 / idxSize) * 100.0);
        }
        log("Completed rebuilding indexName:" + indexName + " size:" + idxSize2 + " bytes (" + prct + "%)");
    }

    private static void exportDb(ODatabaseDocumentTx db, String exportTo) throws IOException {
        OCommandOutputListener listener = System.out::print;
        ODatabaseExport exp = new ODatabaseExport(db, exportTo, listener);
        exp.exportDatabase();
        exp.close();
        System.err.println();
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
        System.err.println();
    }

    private static void dropTables(ODatabaseDocumentTx db) {
        if (DROP_TABLES != null) {
            for (String dropTable : DROP_TABLES) {
                try {
                    if (dropTable.isEmpty()) {
                        continue;
                    }
                    log("[WARN] Dropping " + dropTable + " ...");
                    db.getMetadata().getSchema().dropClass(dropTable);
                } catch (Exception ex) {
                    log("[WARN] Ignoring DROP CLASS " + dropTable + " exception: " + ex.getMessage());
                }
            }
        }
    }

    private static void exportImportDb(ODatabaseDocumentTx db) {
        try {
            OClassImpl tbl = (OClassImpl) db.getMetadata().getSchema().getClass("browse_node");
            if (tbl != null) {
                log("[WARN] Truncating browse_node for export/import");
                tbl.truncate();
            }
        } catch (IOException ioe) {
            log("[WARN] Ignoring TRUNCATE browse_node exception: " + ioe.getMessage());
        }
        String url = db.getURL().split("\\s+")[0].replaceFirst("/$", "");
        String exportName = url.substring(url.lastIndexOf('/')+1, url.length()) + "-export";
        String exportTo = "." + File.separatorChar + exportName;
        if (!EXTRACT_DIR.isEmpty()) {
            exportTo = EXTRACT_DIR + File.separatorChar + exportName;
        }
        try {
            if ((new File(exportTo + ".gz")).exists() && IS_REUSING_EXPORTED) {
                log("[WARN] " + exportTo + ".gz exists. Re-using...");
            } else {
                // OrientDB automatically delete the exportTo if exists.
                exportDb(db, exportTo);
            }
            if (IS_EXPORTING) {
                log("[INFO] Export Only is set so not importing.");
            } else {
                // TODO: it seems to work without dropping, but should I drop?
                importDb(db, exportTo);
            }
        } catch (IOException ioe) {
            log("[ERROR] " + ioe.getMessage());
        }
    }

    private static Boolean setTableName(ODatabaseDocumentTx db, String indexName) {
        if (indexName.isEmpty() || indexName.equals("*")) {
            log("[WARN] Can't assume table name from indexName:" + indexName);
            return false;
        }
        String[] words = indexName.split("_", 3);
        if (words.length == 0) {
            log("[WARN] No table name specified in indexName:" + indexName);
            return false;
        }
        if (db.getMetadata().getSchema().getClass(words[0]) != null) {
            TABLE_NAME = words[0];
        } else if (words.length > 1 && db.getMetadata().getSchema().getClass(words[0] + "_" + words[1]) != null) {
            TABLE_NAME = words[0] + "_" + words[1];
        } else {
            log("[WARN] No table name specified for indexName:" + indexName);
            return false;
        }
        log("Using TABLE_NAME:" + TABLE_NAME);
        return true;
    }

    private static String getIndexFields(ODatabaseDocumentTx db, String indexName) {
        if (indexName.isEmpty() || indexName.equals("*")) {
            return "";
        }
        if (TABLE_NAME.isEmpty()) {
            setTableName(db, indexName);
        }
        String fieldsStr = indexName.replaceFirst("^" + TABLE_NAME + "_", "");
        fieldsStr = fieldsStr.replaceFirst("_idx$", "");
        return fieldsStr.replaceAll("_", ",");
    }

    private static OIndex<?> createIndex(ODatabaseDocumentTx db, String indexName, boolean isDummy) {
        String indexFields = getIndexFields(db, indexName);
        OIndex<?> index = null;
        if (indexFields.isEmpty() || indexFields.equals("*")) {
            log("[WARN] Index: " + indexName + " does not have any specific index fields, so can't create.");
            return null;
        }
        try {
            String[] fields = indexFields.split(",");
            String type = INDEX_TYPE.UNIQUE.name();
            OClassImpl tbl = (OClassImpl) db.getMetadata().getSchema().getClass(TABLE_NAME);
            if (isDummy) {
                // OrientDB hack for setting rebuild = false in index.create()
                OIndexDefinition indexDefinition =
                        OIndexDefinitionFactory.createIndexDefinition(tbl, Arrays.asList(fields), tbl.extractFieldTypes(fields),
                                null, type, ODefaultIndexFactory.SBTREE_ALGORITHM);
                indexDefinition.setNullValuesIgnored(OGlobalConfiguration.INDEX_IGNORE_NULL_VALUES_DEFAULT.getValueAsBoolean());
                Set<String> clustersToIndex = findClustersByIds(tbl.getClusterIds(), db);
                index = OIndexes.createIndex(db, "dummy_" + indexName, type, ODefaultIndexFactory.SBTREE_ALGORITHM,
                        ODefaultIndexFactory.NONE_VALUE_CONTAINER, null, -1);
                index.create("dummy_" + indexName, indexDefinition, OMetadataDefault.CLUSTER_INDEX_NAME, clustersToIndex,
                        false, new OIndexRebuildOutputListener(index));
                debug("Created index:dummy_" + indexName);
            } else {
                // Below rebuild indexes, and it doesn't look like the schema saved when exception.
                index = tbl.createIndex(indexName, type, fields);
                // Below is simpler but again, it does not save schema when exception
                //String query = "CREATE INDEX " + indexName + " ON " + TABLE_NAME + " (" + fields + ") UNIQUE;";
                //Object oDocs = db.command(new OCommandSQL(query)).execute();
                log("Created unique index:" + indexName + " with " + indexFields);
            }
        } catch (ORecordDuplicatedException eDupe) {
            log("Ignoring ORecordDuplicatedException for index:" + indexName + " - " + eDupe.getMessage());
            //eDupe.printStackTrace();
        } catch (Exception e) {
            // If table is corrupted, this may cause java.lang.ArrayIndexOutOfBoundsException but not sure what could be done in this code.
            log("[ERROR] Creating index:" + indexName + " failed. May need to do DB export/import.");
            e.printStackTrace();
            return null;
        } finally {
            if (index != null) {
                db.getMetadata().getIndexManager().save();
            } else {
                index = db.getMetadata().getIndexManager().getIndex(indexName);
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

    private static Boolean checkIndex(ODatabaseDocumentTx db, String indexName) {
        if (IS_NO_INDEX_CHECK) {
            log("No index check is specified, so skipping checkIndex for " + indexName);
            return true;
        }
        if (indexName.isEmpty() || indexName.equals("*")) {
            // As this class is for checking asset duplicates, using asset_bucket_component_name_idx if not specified
            indexName = SUPPORTED_INDEX_NAMES.get(0);
        }
        if (!SUPPORTED_INDEX_NAMES.contains(indexName)) {
            log("[WARN] " + indexName + " is not supported for checkIndex (supported: " + SUPPORTED_INDEX_NAMES + ")");
            return true;
        }
        OIndex<?> index = db.getMetadata().getIndexManager().getIndex(indexName);
        boolean isDummyIdxCreated = false;
        if (index == null && IS_REPAIRING) {
            // If no index but repairing, create a real index
            log("Creating the missing index: " + indexName + "...");
            index = createIndex(db, indexName, false);
            IS_REBUILDING = false;  // no need to re-rebuild
        } else if (index != null && IS_REPAIRING) {
            // If index exists and repairing, just clear, then it will be rebuilt later
            index.clear();
            log("Index: " + indexName + " is cleared (= do not terminate this script in the middle)");
        } else {
            // If no index or not repairing, create a dummy index
            log("Creating a temp index from " + indexName + " (notunique, then unique)...");
            index = createIndex(db, indexName, true);
            isDummyIdxCreated = true;
        }

        if (index == null) {
            log("Index: " + indexName + " does not exist.");
            return false;
        }

        if (TABLE_NAME.isEmpty() && !setTableName(db, indexName)) {
            return false;
        }
        long count = 0L;
        long total = db.countClass(TABLE_NAME);
        try {
            log("*Estimate* count for " + TABLE_NAME + " = " + total);
            for (ODocument doc : db.browseClass(TABLE_NAME)) {
                count++;
                DUPE_COUNTER += chkAndPutIndexEntry(db, index, doc);
                if (count % 10000 == 0) {
                    index.flush();
                    log("Checked " + count + "/" + total + " (" + (int) ((count * 100) / total) + "%, duplicates:" +
                            DUPE_COUNTER + ")");
                }
            }
            index.flush();  // probably no need, but just in case
            log("Completed the check of indexName:" + indexName + " - total:" + count + " duplicates:" + DUPE_COUNTER);
        } finally {
            if (index != null && isDummyIdxCreated) {
                index.delete(); // cleaning up unnecessary temp/dummy index
                debug("Deleted index:dummy_" + indexName);
            }
        }
        // If dupes found but not fixed, return false, so that it won't trigger index rebuild
        return DUPE_COUNTER <= 0 || IS_REPAIRING;
    }

    private static int chkAndPutIndexEntry(ODatabaseDocumentTx db, OIndex<?> index, ODocument doc) {
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
        } catch (ArrayIndexOutOfBoundsException e) {
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
            } catch (ORecordDuplicatedException e) {
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
            Object indexKey) {
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
            } else {
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
                        } else {
                            log("[ERROR] Updating assets which component Id = " + deletingId + " failed: " + updNum.toString());
                        }
                    } catch (Exception updEx) {
                        log("[ERROR] Query: \"" + updQuery + "\" failed with Exception: " + updEx.getMessage());
                    }
                }
            }
        }
        out("TRUNCATE RECORD " + deletingId + ";");

        if (IS_REPAIRING) {
            db.delete(deletingId);
            log("[WARN] Deleted duplicate: " + deletingId);
        } else {
            // Need to remove this one to detect another duplicates for same key (if repairing, above delete() also remove from index
            index.remove(indexKey, deletingId);
        }
    }

    private static boolean validateIndex(ODatabaseDocumentTx db, String indexName) {
        List<ODocument> oDocs = db.command(new OCommandSQL(
                        "select * from (select expand(indexes) from metadata:indexmanager) where name = '" + indexName + "'"))
                .execute();
        if (oDocs.isEmpty()) {
            return false;
        }
        String indexDef = oDocs.get(0).toJSON("rid,attribSameRow,alwaysFetchEmbedded,fetchPlan:*:0"); //,prettyPrint
        log(indexDef);
        if (!indexDef.contains("\"" + indexName + "\"")) {
            return false;
        }
        if (!indexDef.contains("\"" + INDEX_TYPE.UNIQUE.name() + "\"")) {
            return false;
        }
        String indexFields = getIndexFields(db, indexName);
        String[] fields = indexFields.split(",");
        StringBuilder testQuery = new StringBuilder("EXPLAIN SELECT " + indexFields + " from " + TABLE_NAME + " WHERE 1 = 1");
        OClassImpl tbl = (OClassImpl) db.getMetadata().getSchema().getClass(TABLE_NAME);
        List<OType> fTypes = tbl.extractFieldTypes(fields);
        for (int i = 0; i < fields.length; i++) {
            String val = " IS NOT NULL";
            if (fTypes.get(i).toString().equalsIgnoreCase("LINK")) {
                val = " = #1:1";
            } else if (fTypes.get(i).toString().equalsIgnoreCase("STRING")) {
                val = " = 'test'";
            }
            testQuery.append(" AND ").append(fields[i]).append(val);
        }
        String explainStr = ((ODocument) db.command(new OCommandSQL(testQuery.toString())).execute()).toJSON(
                "rid,attribSameRow,alwaysFetchEmbedded,fetchPlan:*:0"); //,prettyPrint
        log(explainStr);
        return explainStr.contains("\"" + indexName + "\"");
    }

    private static void setGlobals() {
        IS_DEBUG = Boolean.getBoolean("debug");
        IS_REBUILDING = Boolean.getBoolean("rebuildIndex");
        debug("rebuildIndex: " + IS_REBUILDING);
        IS_EXPORTING = Boolean.getBoolean("exportOnly");
        debug("exportOnly: " + IS_EXPORTING);
        IS_REUSING_EXPORTED = Boolean.getBoolean("importReuse");
        debug("importReuse: " + IS_REUSING_EXPORTED);
        IS_REIMPORTING = Boolean.getBoolean("exportImport");
        debug("exportImport: " + IS_REIMPORTING);
        if (IS_REIMPORTING) {
            IS_REPAIRING = true;
        } else {
            IS_REPAIRING = Boolean.getBoolean("repair");
        }
        debug("repair: " + IS_REPAIRING);
        IS_NO_INDEX_CHECK = Boolean.getBoolean("noCheckIndex");
        debug("noCheckIndex: " + IS_NO_INDEX_CHECK);
        TABLE_NAME = System.getProperty("tableName", "");
        debug("tableName: " + TABLE_NAME);
        String defaultIndexName = "";
        if (!IS_NO_INDEX_CHECK) {
            defaultIndexName = SUPPORTED_INDEX_NAMES.get(0);
        }
        INDEX_NAME = System.getProperty("indexName", defaultIndexName);
        debug("indexName: " + INDEX_NAME);
        String dropTables = System.getProperty("dropTables", "");
        debug("dropTables: " + dropTables);
        DROP_TABLES = dropTables.split(",");
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

        DB_DIR_PATH = args[0];
        String connStr;

        log("main() started with " + DB_DIR_PATH);

        if (!(new File(DB_DIR_PATH)).isDirectory()) {
            try {
                if (!prepareDir(EXTRACT_DIR, DB_DIR_PATH)) {
                    System.exit(1);
                }
                log("Unzip-ing " + DB_DIR_PATH + " to " + EXTRACT_DIR);
                unzip(DB_DIR_PATH, EXTRACT_DIR);
                DB_DIR_PATH = EXTRACT_DIR;
            } catch (Exception e) {
                log("[ERROR] " + DB_DIR_PATH + " is not a right archive.");
                log(e.getMessage());
                delR(TMP_DIR);
                System.exit(1);
            }
        }

        // Somehow without an ending /, OStorageException happens
        if (!DB_DIR_PATH.endsWith("/")) {
            DB_DIR_PATH = DB_DIR_PATH + "/";
        }
        connStr = "plocal:" + DB_DIR_PATH + " admin admin";

        Orient.instance().getRecordConflictStrategy()
                .registerImplementation("ConflictHook", new OVersionRecordConflictStrategy());

        long start = System.nanoTime();
        try (ODatabaseDocumentTx db = new ODatabaseDocumentTx(connStr)) {
            try {
                db.open("admin", "admin");
                log("Connected to " + connStr);
                getIndexFields(db, INDEX_NAME);

                // Doing drop tables first
                dropTables(db);

                boolean result = true;
                if (!IS_NO_INDEX_CHECK) {
                    // checkIndex() returns false if dupe or error
                    result = checkIndex(db, INDEX_NAME);
                }

                if (IS_REBUILDING) {
                    if (!result) {
                        log("[WARN] Index rebuild is skipped as checkIndex returned false (maybe dupes or missing index)");
                    } else {
                        rebuildIndex(db, INDEX_NAME);
                    }
                }

                if (IS_REIMPORTING || IS_EXPORTING) {
                    exportImportDb(db);
                }

                if (!IS_NO_INDEX_CHECK && SUPPORTED_INDEX_NAMES.contains(INDEX_NAME)) {
                    log("Validating indexName: " + INDEX_NAME);
                    if (!validateIndex(db, INDEX_NAME)) {
                        log("[ERROR] Validating indexName: " + INDEX_NAME + " failed");
                    }
                }
            } catch (Exception e) {
                e.printStackTrace();
            }
        }

        log("Completed. Elapsed " + ((System.nanoTime() - start) / 1000_000) + " ms");
        // Cleaning up the temp dir if used
        delR(TMP_DIR);
    }
}
