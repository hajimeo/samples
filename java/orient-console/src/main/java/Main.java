//import com.google.gson.GsonBuilder;
//import com.google.gson.Gson;

import com.fasterxml.jackson.core.type.TypeReference;
import com.google.common.collect.Lists;
import com.google.gson.Gson;
import com.orientechnologies.orient.client.remote.OStorageRemote;
import com.orientechnologies.orient.core.Orient;
import com.orientechnologies.orient.core.config.OGlobalConfiguration;
import com.orientechnologies.orient.core.conflict.OVersionRecordConflictStrategy;
import com.orientechnologies.orient.core.db.document.ODatabaseDocumentTx;
import com.orientechnologies.orient.core.exception.OCommandExecutionException;
import com.orientechnologies.orient.core.record.impl.ODocument;
import com.orientechnologies.orient.core.record.impl.ORecordBytes;
import com.orientechnologies.orient.core.sql.OCommandSQL;
import com.orientechnologies.orient.core.sql.OCommandSQLParsingException;
import com.orientechnologies.orient.server.OServer;
import com.orientechnologies.orient.server.config.OServerConfiguration;
import com.orientechnologies.orient.server.config.OServerEntryConfiguration;
import com.orientechnologies.orient.server.config.OServerNetworkConfiguration;
import com.orientechnologies.orient.server.config.OServerNetworkListenerConfiguration;
import com.orientechnologies.orient.server.config.OServerNetworkProtocolConfiguration;
import com.orientechnologies.orient.server.config.OServerSecurityConfiguration;
import com.orientechnologies.orient.server.config.OServerStorageConfiguration;
import com.orientechnologies.orient.server.config.OServerUserConfiguration;
import com.orientechnologies.orient.server.network.protocol.binary.ONetworkProtocolBinary;
import net.lingala.zip4j.ZipFile;
import org.jline.reader.*;
import org.jline.reader.impl.DefaultHighlighter;
import org.jline.reader.impl.completer.StringsCompleter;
import org.jline.reader.impl.history.DefaultHistory;
import org.jline.terminal.Terminal;
import org.jline.terminal.TerminalBuilder;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.smile.SmileFactory;

import java.io.*;
import java.lang.reflect.InvocationTargetException;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import javax.management.InstanceAlreadyExistsException;
import javax.management.MBeanRegistrationException;
import javax.management.MalformedObjectNameException;
import javax.management.NotCompliantMBeanException;

public class Main
{
  static final private String PROMPT = "=> ";

  static final private String DEFAULT_JSON_FORMAT = "rid,attribSameRow,alwaysFetchEmbedded,fetchPlan:*:0";

  static private String jsonFormat = DEFAULT_JSON_FORMAT;

  static private Terminal terminal;

  static private History history;

  static private String historyPath;

  static private String extractDir;

  static private String exportPath;

  static private String binaryField;

  static private String[] fieldNames;

  static private String paging = "";

  static private int pageCount = 1;

  static private String ridName = "rid";

  static private int lastRows = 0;

  static private String lastRid = "#-1:-1";

  static private String dbUser = "admin";

  static private String dbPwd = "admin";

  static private Boolean isServer;

  static private OServer server;

  private static final ObjectMapper objectMapper = new ObjectMapper(new SmileFactory());

  private static final Gson gson = new Gson();

  public static final Pattern indexNamePtn = Pattern.compile( "(rebuild|list) indexes ([^;]+)", Pattern.CASE_INSENSITIVE);

  private static void usage() {
    System.err.println("https://github.com/hajimeo/samples/blob/master/java/orient-console/README.md");
  }

  private static String getCurrentLocalDateTimeStamp() {
    return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"));
  }

  private static void log(String msg) {
    // TODO: proper logging
    System.err.println(getCurrentLocalDateTimeStamp() + " " + msg);
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

  // TODO: changing to List<?> breaks toJSON()
  private static void printListAsJson(List<ODocument> oDocs, boolean isPaging) {
    if (oDocs == null || oDocs.isEmpty()) {
      if (!isPaging) {
        terminal.writer().println("\n[]");
      }
      terminal.flush();
      return;
    }
    if (!isPaging) {
      terminal.writer().println("\n[");
    }
    for (int i = 0; i < oDocs.size(); i++) {
      if (!isPaging && i == (oDocs.size() - 1)) {
        terminal.writer().println("  " + oDocs.get(i).toJSON(jsonFormat));
      }
      else {
        terminal.writer().println("  " + oDocs.get(i).toJSON(jsonFormat) + ",");
      }
      terminal.flush();
    }
    if (!isPaging) {
      terminal.writer().println("]");
    }
    // TODO: not working?  and not organised properly
    terminal.flush();
  }

  private static void printDocAsJson(ODocument oDoc) {
    // NOTE: Should check null, like 'if (oDoc == null) {'?
    // Default; rid,version,class,type,attribSameRow,keepTypes,alwaysFetchEmbedded,fetchPlan:*:0
    terminal.writer().println(oDoc.toJSON(DEFAULT_JSON_FORMAT + ",prettyPrint"));
    terminal.flush();
  }

  private static void printBinary(ODocument oDoc) {
    if (binaryField.isEmpty()) {
      return;
    }
    if (fieldNames.length == 0) {
      fieldNames = oDoc.fieldNames();
    }
    List<String> fieldList = new ArrayList<>(Arrays.asList(fieldNames));
    if (fieldList.contains(binaryField)) {
      System.out.println(bytesToStr(oDoc.field(binaryField)));
    }
  }

  private static String bytesToStr(ORecordBytes rawBytes) {
    String str = "";
    try {
      //rawBytes.toOutputStream(System.out);
      final Map<String, Object> raw = objectMapper.readValue(rawBytes.toStream(),
          new TypeReference<Map<String, Object>>() { });
      str = gson.toJson(raw);
    }
    catch (Exception e) {
      e.printStackTrace();
    }
    return str;
  }

  private static void writeListAsJson(List<ODocument> oDocs, String exportPath, boolean isPaging) {
    System.err.println("");
    try {
      File fout = new File(exportPath);
      FileOutputStream fos = new FileOutputStream(fout, true);
      BufferedWriter bw = new BufferedWriter(new OutputStreamWriter(fos));
      if (oDocs == null || oDocs.isEmpty()) {
        bw.close();
        return;
      }
      if (!isPaging && oDocs.size() == 1) {
        bw.write("[" + oDocs.get(0).toJSON(jsonFormat) + "]");
        bw.newLine();
        bw.close();
        return;
      }
      if (!isPaging) {
        bw.write("[\n");
      }
      for (int i = 0; i < oDocs.size(); i++) {
        if (!isPaging && i == (oDocs.size() - 1)) {
          bw.write("  " + oDocs.get(i).toJSON(jsonFormat));
        }
        else {
          bw.write("  " + oDocs.get(i).toJSON(jsonFormat) + ",");
        }
        bw.newLine();
      }
      if (!isPaging) {
        bw.write("]");
      }
      if (!isPaging) {
        bw.newLine();
      }
      bw.close();
    }
    catch (IOException e) {
      e.printStackTrace();
    }
    finally {
      System.err.println("");
    }
  }

  private static void execQueries(ODatabaseDocumentTx db, String input) {
    List<String> queries = Arrays.asList(input.split(";"));
    for (String q : queries) {
      if (q == null || q.isEmpty()) {
        continue;
      }

      Instant start = Instant.now();
      try {
        boolean isPaging = false;
        if (paging != null && paging.trim().length() > 0 && q.toLowerCase().startsWith("select ")) {
          if (q.toLowerCase().contains(" order by ") || q.toLowerCase().contains(" limit ")) {
            log("\nERROR: 'paging' is given but query contains 'order by' or 'limit'.");
            continue;
          }
          if (!q.toLowerCase().contains(" where ")) {
            log("\nWARN: 'paging' is given but OrientDB 2.x pagination may not work with 'where' clause ... :(");
          }
          if (!q.toLowerCase().contains(" " + ridName + ",")) {  // TODO: should use regex
            log("\nWARN: 'paging' is given but query may not contain '@rid as " + ridName + "'");
          }
          log("\nINFO: pagination is enabled with paging size:" + paging + "");
          isPaging = true;
        }

        execQuery(db, q, isPaging);
        while (isPaging && lastRows > 0) {
          pageCount += 1;
          log("Fetching page:" + pageCount + " with last_rid:" + lastRid + " last_rows:" + lastRows);
          execQuery(db, q, isPaging);
        }
      }
      catch (ClassCastException e) {
        System.err.println(e.getMessage());
        e.printStackTrace();
      }
      catch (OCommandSQLParsingException | OCommandExecutionException ex) {
        removeLineFromHistory(input);
        history.load();
      }
      finally {
        Instant finish = Instant.now();
        long timeElapsed = Duration.between(start, finish).toMillis();
        System.err.printf("Elapsed: %d ms\n", timeElapsed);
      }
    }
  }

  private static void execQuery(ODatabaseDocumentTx db, String query, boolean isPaging) {
    if (isPaging) {
      if (query.toLowerCase().contains(" where ")) {
        query = query.replaceAll(" (?i)where ", " WHERE @rid > " + lastRid + " AND ");
      }
      else {
        query += " WHERE @rid > " + lastRid;
      }
      query += " LIMIT " + paging;
    }

    //Object oDocs = db.query(new OCommandSQL(query));
    Object oDocs = db.command(new OCommandSQL(query)).execute();
    //final List<ODocument> oDocs = db.command(new OCommandSQL(query)).execute();
    if (oDocs instanceof Integer || oDocs instanceof Long) {
      // this means UPDATE/INSERT etc., so not updating last_rows
      System.err.printf("Rows: %d, ", oDocs);
    }
    else if (oDocs instanceof ODocument) {
      // NOTE: 'EXPLAIN' causes com.orientechnologies.orient.core.record.impl.ODocument cannot be cast to java.util.List
      printDocAsJson((ODocument) oDocs);
    }
    else {
      if (((List<ODocument>) oDocs).size() > 0) {
        fieldNames = ((List<ODocument>) oDocs).get(0).fieldNames();
      }
      if (exportPath != null && exportPath.length() > 0) {
        writeListAsJson(((List<ODocument>) oDocs), exportPath, isPaging);
        if (!isPaging) {
          System.err.printf("Wrote %d rows to %s.\n", ((List<ODocument>) oDocs).size(), exportPath);
        }
      }
      else {
        printListAsJson(((List<ODocument>) oDocs), isPaging);
        if (!isPaging) {
          System.err.printf("Rows: %d, ", ((List<ODocument>) oDocs).size());
        }
      }
      // Currently using below if the result is only one record.
      if (((List<ODocument>) oDocs).size() == 1) {
        printBinary(((List<ODocument>) oDocs).get(0));
      }

      lastRows = ((List<ODocument>) oDocs).size();
      if (isPaging && lastRows > 0) {
        lastRid = ((ODocument) ((ODocument) ((List<ODocument>) oDocs).get((lastRows - 1))).field(ridName)).getIdentity()
            .toString();
      }
    }
  }

  private static void removeLineFromHistory(String inputToRemove) {
    BufferedReader reader = null;
    BufferedWriter writer = null;

    try {
      File inputFile = new File(historyPath);
      File tempFile = Files.createTempFile(null, null).toFile();

      reader = new BufferedReader(new FileReader(inputFile));
      writer = new BufferedWriter(new FileWriter(tempFile));
      String currentLine;

      while ((currentLine = reader.readLine()) != null) {
        try {
          if (currentLine.matches("^[0-9]+:" + inputToRemove + "$")) {
            continue;
          }
        }
        catch (IllegalArgumentException ee) {
          // It's OK to ignore most of the errors/exception from matches
          log(ee.getMessage());
          continue;
        }
        writer.write(currentLine + System.getProperty("line.separator"));
      }
      tempFile.renameTo(inputFile);
    }
    catch (IOException e) {
      e.printStackTrace();
    }
    finally {
      try {
        if (writer != null) {
          writer.close();
        }
        if (reader != null) {
          reader.close();
        }
      }
      catch (IOException e) {
        e.printStackTrace();
      }
    }
  }

  private static List<ODocument> listIndexes(ODatabaseDocumentTx db, String indexName) {
    String whereAppend = "";
    if (indexName.length() > 0) {
      whereAppend = " AND name like '" + indexName.replaceAll("\\*", "%") +"'";
    }
    String query = "SELECT indexDefinition.className as table, name from (select expand(indexes) from metadata:indexmanager) where indexDefinition.className is not null "+whereAppend+" order by table, name LIMIT -1";
    //log(query);
    List<ODocument> oDocs = db.command(new OCommandSQL(query))
        .execute();
    printListAsJson(oDocs, false);
    return oDocs;
  }

  private static void rebuildIndexes(ODatabaseDocumentTx db, String indexName) {
    log("Rebuilding the following indexes:");
    List<ODocument> oDocs = listIndexes(db, indexName);
    for (ODocument oDoc : oDocs) {
      execQueries(db, "REBUILD INDEX " + oDoc.field("name"));
    }
  }

  private static boolean isSpecialQueryAndProcess(ODatabaseDocumentTx db, String input) {
    if (input.startsWith("--")) {
      return true;
    }
    if (input.toLowerCase().startsWith("set pretty true")) { // TODO: not property implementing my own 'set'
      jsonFormat = DEFAULT_JSON_FORMAT + ",prettyPrint";
      return true;
    }
    if (input.toLowerCase().startsWith("set pretty false")) {
      jsonFormat = DEFAULT_JSON_FORMAT;
      return true;
    }
    if (input.toLowerCase().startsWith("list indexes")) {
      Matcher matcher = indexNamePtn.matcher(input.toLowerCase());
      String indexName = "";
      if (matcher.find()) {
        indexName = matcher.group(2);
      }
      listIndexes(db, indexName);
      return true;
    }
    if (input.toLowerCase().startsWith("rebuild indexes")) { // NOT 'rebuild index *'
      Matcher matcher = indexNamePtn.matcher(input);
      String indexName = "";
      if (matcher.find()) {
        indexName = matcher.group(2);
      }
      rebuildIndexes(db, indexName);
      return true;
    }
    return false;
  }

  private static void readLineLoop(ODatabaseDocumentTx db, LineReader reader) {
    // TODO: prompt and queries from STDIN are always printed in STDOUT which is a bit annoying when redirects to a file.
    //System.err.print(PROMPT);
    //String input = reader.readLine((String) null);
    String input = reader.readLine(PROMPT);
    while (input != null && !input.startsWith("exit")) {
      try {
        if (!isSpecialQueryAndProcess(db, input) && db != null) {
          execQueries(db, input);
        }
        input = reader.readLine(PROMPT);
      }
      catch (UserInterruptException e) {
        // User hit ctrl-C, just clear the current line and try again.
        System.err.println("^C");
        input = "";
        continue;
      }
      catch (EndOfFileException e) {
        System.err.println("^D");
        return;
      }
    }
  }

  private static Set<String> genAutoCompWords(String fileName) {
    // at this moment, not considering some slowness by the file size as DEFAULT_HISTORY_SIZE should take care
    Set<String> wordSet = new HashSet<>(Arrays
        .asList("CREATE", "SELECT FROM", "UPDATE", "INSERT INTO", "DELETE FROM", "FROM", "WHERE", "BETWEEN", "AND",
            "DISTINCT", "DISTINCT", "LIKE", "LIMIT", "NOT"));
    try (BufferedReader br = new BufferedReader(new InputStreamReader(new FileInputStream(fileName)))) {
      String line;
      while ((line = br.readLine()) != null) {
        StringTokenizer st = new StringTokenizer(line, " ,.;:\"");
        while (st.hasMoreTokens()) {
          String w = st.nextToken();
          if (w.matches("^[a-zA-Z]*$")) {
            wordSet.add(w);
          }
        }
      }
    }
    catch (IOException e) {
      System.err.println(e.getMessage());
    }
    return wordSet;
  }

  private static LineReader setupReader() throws IOException {
    terminal = TerminalBuilder.builder()
        .system(true)
        .dumb(true)
        .build();
    history = new DefaultHistory();
    historyPath = System.getProperty("user.home") + "/.orient-console_history";
    System.err.println("history path: " + historyPath);
    Set<String> words = genAutoCompWords(historyPath);
    LineReader lr = LineReaderBuilder.builder()
        .terminal(terminal)
        .highlighter(new DefaultHighlighter())
        .history(history)
        .completer(new StringsCompleter(words))
        .variable(LineReader.HISTORY_FILE, new File(historyPath))
        .build();
    history.attach(lr);
    return lr;
  }

  private static void startServer(String dbPath)
      throws MalformedObjectNameException, NotCompliantMBeanException, InstanceAlreadyExistsException,
             ClassNotFoundException, MBeanRegistrationException, IOException, InvocationTargetException,
             NoSuchMethodException, InstantiationException, IllegalAccessException
  {
    File databaseDir = new File(dbPath).getCanonicalFile().getParentFile();
    Path homeDir = databaseDir.toPath();
    System.setProperty("orient.home", homeDir.toString());
    System.setProperty(Orient.ORIENTDB_HOME, homeDir.toString());

    server = new OServer();
    OServerConfiguration config = new OServerConfiguration();
    config.location = "DYNAMIC-CONFIGURATION";  // Not sure about this, just took from OrientDbEmbeddedTrial
    // TODO: Still couldn't avoid 'SEVER ODefaultServerSecurity.loadConfig() Could not access the security JSON file'
    File securityFile = new File(databaseDir, "orient-console-security.json");
    config.properties = new OServerEntryConfiguration[]{
        new OServerEntryConfiguration("server.database.path", databaseDir.getPath()),
        new OServerEntryConfiguration("server.security.file", securityFile.getPath())
    };
    config.handlers = Lists.newArrayList();
    config.hooks = Lists.newArrayList();
    config.network = new OServerNetworkConfiguration();
    config.network.protocols = Lists.newArrayList(
        new OServerNetworkProtocolConfiguration("binary", ONetworkProtocolBinary.class.getName())
    );
    OServerNetworkListenerConfiguration binaryListener = new OServerNetworkListenerConfiguration();
    binaryListener.ipAddress = "0.0.0.0";
    binaryListener.portRange = "2424-2430";
    binaryListener.protocol = "binary";
    binaryListener.socket = "default";
    config.network.listeners = Lists.newArrayList(
        binaryListener
    );

    config.storages = new OServerStorageConfiguration[]{};
    config.users = new OServerUserConfiguration[]{
        new OServerUserConfiguration(dbUser, dbPwd, "*")
    };

    config.security = new OServerSecurityConfiguration();
    config.security.users = Lists.newArrayList();
    config.security.resources = Lists.newArrayList();

    server.startup(config);
    // Using 'null' for iPassword generates a random password
    server.addUser(OServerConfiguration.DEFAULT_ROOT_USER, "SomeRootPassword", "*");
    server.activate();

    ByteArrayOutputStream baos = new ByteArrayOutputStream();
    OGlobalConfiguration.dumpConfiguration(new PrintStream(baos, true));
    log("Global configuration:\n" + baos.toString("UTF8"));
  }

  private Main() { }

  private static void setGlobals() {
    extractDir = System.getProperty("extractDir", System.getenv("_EXTRACT_DIR"));
    exportPath = System.getProperty("exportPath", System.getenv("_EXPORT_PATH"));
    binaryField = System.getProperty("binaryField", "");
    paging = System.getProperty("paging", "");
    ridName = System.getProperty("ridName", "rid");
    lastRid = System.getProperty("lastRid", "#-1:-1");
    String envOrientDBUser = System.getenv("ORIENTDB_USER");
    if (envOrientDBUser != null) {
      dbUser = envOrientDBUser;
    }
    String envOrientDBPwd = System.getenv("ORIENTDB_PWD");
    if (envOrientDBPwd != null) {
      dbPwd = envOrientDBPwd;
    }
    isServer = Boolean.getBoolean("server");
  }

  public static void main(final String[] args) throws IOException {
    if (args.length < 1) {
      usage();
      System.exit(1);
    }

    setGlobals();

    String path = args[0];
    Path tmpDir = null;

    // if exportPath is given, create the path
    if (exportPath != null && exportPath.length() > 0) {
      File yourFile = new File(exportPath);
      yourFile.createNewFile(); // if file already exists, this method does nothing
      FileOutputStream fos = new FileOutputStream(yourFile, false);
      fos.close();
    }

    // Preparing data (extracting zip if necessary)
    if (!path.startsWith("remote:") && !(new File(path)).isDirectory() && !(new File(path)).isDirectory()) {
      try {
        if (extractDir != null && !extractDir.trim().isEmpty()) {
          if (!prepareDir(extractDir, path)) {
            System.exit(1);
          }
        }
        else {
          tmpDir = Files.createTempDirectory(null);
          tmpDir.toFile().deleteOnExit();
          extractDir = tmpDir.toString();
        }

        log("Unzip-ing " + path + " to " + extractDir);
        unzip(path, extractDir);
        path = extractDir;
      }
      catch (Exception e) {
        log(path + " is not a right archive.");
        e.printStackTrace();
        delR(tmpDir);
        System.exit(1);
      }
    }
    // TODO: above should have more proper error check.
    String dbName = new File(path).getName();

    ODatabaseDocumentTx db = null;
    try {
      if (isServer != null && isServer) {
        startServer(path);
        System.err.println("# Service started for " + path);
        path = "remote:127.0.0.1/" + dbName;
      }

      if (path.startsWith("remote:")) {
        System.err.println("# connecting to " + path);
        db = new ODatabaseDocumentTx(path);
        db.setProperty(OStorageRemote.PARAM_CONNECTION_STRATEGY,
            OStorageRemote.CONNECTION_STRATEGY.STICKY.toString());
      }
      else {
        // Somehow without an ending /, OStorageException happens
        if (!path.endsWith("/")) {
          path = path + "/";
        }
        System.err.println("# connecting to plocal:" + path);
        db = new ODatabaseDocumentTx("plocal:" + path);
      }

      // Below hook does not work with 2.1.14
      Orient.instance().getRecordConflictStrategy()
          .registerImplementation("ConflictHook", new OVersionRecordConflictStrategy());

      try {
        db.open(dbUser, dbPwd);
      }
      catch (NullPointerException e) {
        log("NullPointerException happened (and ignoring)");
        e.printStackTrace();
      }

      System.err.println("# Type 'exit' or Ctrl+D to exit. Ctrl+C to cancel current query");
      readLineLoop(db, setupReader());
    }
    catch (Exception e) {
      e.printStackTrace();
    }
    finally {
      // If not closing or proper shutdown, OrientDB rebuilds indexes at next connect...
      if (db != null) {
        db.close();
      }
      if (server != null) {
        server.shutdown();
      }
      if (tmpDir != null) {
        log("Clearing temp directory: " + tmpDir + " ...");
        delR(tmpDir);
      }
    }
    log("Exiting.");
  }
}
