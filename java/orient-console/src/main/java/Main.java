//import com.google.gson.GsonBuilder;
//import com.google.gson.Gson;

import com.fasterxml.jackson.core.type.TypeReference;
import com.google.gson.Gson;
import com.orientechnologies.orient.core.Orient;
import com.orientechnologies.orient.core.conflict.OVersionRecordConflictStrategy;
import com.orientechnologies.orient.core.db.document.ODatabaseDocumentTx;
import com.orientechnologies.orient.core.exception.OCommandExecutionException;
import com.orientechnologies.orient.core.record.impl.ODocument;
import com.orientechnologies.orient.core.record.impl.ORecordBytes;
import com.orientechnologies.orient.core.sql.OCommandSQL;
import com.orientechnologies.orient.core.sql.OCommandSQLParsingException;
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
  static final String PROMPT = "=> ";

  static Terminal terminal;

  static History history;

  static String historyPath;

  static String extractDir;

  static String exportPath;

  static String binaryField;

  static String[] fieldNames;

  private static final ObjectMapper objectMapper = new ObjectMapper(new SmileFactory());

  private static final Gson gson = new Gson();

  private static void usage() {
    System.err.println("USAGE EXAMPLES:\n" +
        "# start interactive console:\n" +
        "  java -jar ./orient-console.jar ./sonatype-work/nexus3/db/component\n" +
        " or with small .bak (zip) file:\n" +
        "  java -jar ./orient-console.jar ./component-2021-08-07-09-00-00-3.30.0-01.bak\n" +
        " or with larger .bak file (or env:_EXTRACT_DIR):\n" +
        "  java -DextractDir=./component -jar ./orient-console.jar ./component-2021-08-07-09-00-00-3.30.0-01.bak\n" +
        "\n" +
        "# batch processing (or env:_EXPORT_PATH):\n" +
        "  echo \"SQL SELECT statement\" | java -DexportPath=./result.json -jar orient-console.jar <directory path|.bak file path>");
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
  private static void printListAsJson(List<ODocument> oDocs) {
    if (oDocs == null || oDocs.isEmpty()) {
      terminal.writer().println("\n[]");
      terminal.flush();
      return;
    }
    terminal.writer().println("\n[");
    for (int i = 0; i < oDocs.size(); i++) {
      if (i == (oDocs.size() - 1)) {
        terminal.writer().println("  " + oDocs.get(i).toJSON());
      }
      else {
        terminal.writer().println("  " + oDocs.get(i).toJSON() + ",");
      }
      terminal.flush();
    }
    terminal.writer().println("]");
    // TODO: not working?  and not organised properly
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

  private static void writeListAsJson(List<ODocument> oDocs, String exportPath) {
    System.err.println("");
    try {
      File fout = new File(exportPath);
      FileOutputStream fos = new FileOutputStream(fout);
      BufferedWriter bw = new BufferedWriter(new OutputStreamWriter(fos));
      if (oDocs == null || oDocs.isEmpty()) {
        bw.write("[]");
        bw.newLine();
        bw.close();
        return;
      }
      bw.write("[\n");
      for (int i = 0; i < oDocs.size(); i++) {
        if (i == (oDocs.size() - 1)) {
          bw.write("  " + oDocs.get(i).toJSON());
        }
        else {
          bw.write("  " + oDocs.get(i).toJSON() + ",");
        }
        bw.newLine();
      }
      bw.write("]");
      bw.newLine();
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
    for (int i = 0; i < queries.size(); i++) {
      String q = queries.get(i);
      if (q == null || q.isEmpty()) {
        continue;
      }

      Instant start = Instant.now();
      try {
        final List<ODocument> oDocs = db.command(new OCommandSQL(q)).execute();
        if (oDocs.size() > 0) {
          fieldNames = oDocs.get(0).fieldNames();
        }
        if (exportPath != null && exportPath.length() > 0) {
          writeListAsJson(oDocs, exportPath);
          System.err.printf("Wrote %d rows to %s, ", oDocs.size(), exportPath);
        }
        else {
          printListAsJson(oDocs);
          System.err.printf("Rows: %d, ", oDocs.size());
        }
        // Currently using below if the result is only one record.
        if (oDocs.size() == 1) {
          printBinary(oDocs.get(0));
        }
      }
      catch (java.lang.ClassCastException e) {
        // TODO: 'EXPLAIN' causes com.orientechnologies.orient.core.record.impl.ODocument cannot be cast to java.util.List
        System.err.println(e.getMessage());
        e.printStackTrace();
      }
      catch (OCommandSQLParsingException | OCommandExecutionException ex) {
        removeLine(input);
        history.load();
      }
      finally {
        Instant finish = Instant.now();
        long timeElapsed = Duration.between(start, finish).toMillis();
        System.err.printf("Elapsed: %d ms\n", timeElapsed);
      }
    }
  }

  private static void removeLine(String inputToRemove) {
    BufferedReader reader = null;
    BufferedWriter writer = null;

    try {
      File inputFile = new File(historyPath);
      File tempFile = Files.createTempFile(null, null).toFile();

      reader = new BufferedReader(new FileReader(inputFile));
      writer = new BufferedWriter(new FileWriter(tempFile));
      String currentLine;

      while ((currentLine = reader.readLine()) != null) {
        if (currentLine.matches("^[0-9]+:" + inputToRemove + "$")) {
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

  private static void readLineLoop(ODatabaseDocumentTx db, LineReader reader) {
    // TODO: prompt and queries from STDIN are always printed in STDOUT which is a bit annoying when redirects to a file.
    //System.err.print(PROMPT);
    //String input = reader.readLine((String) null);
    String input = reader.readLine(PROMPT);
    while (input != null && !input.equalsIgnoreCase("exit")) {
      try {
        execQueries(db, input);
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

  private Main() { }

  public static void main(final String[] args) throws IOException {
    if (args.length < 1) {
      usage();
      System.exit(1);
    }

    String path = args[0];
    String connStr = "";
    Path tmpDir = null;
    extractDir = System.getProperty("extractDir", System.getenv("_EXTRACT_DIR"));
    exportPath = System.getProperty("exportPath", System.getenv("_EXPORT_PATH"));
    binaryField = System.getProperty("binaryField", "");

    // Preparing data (extracting zip if necessary)
    if (!(new File(path)).isDirectory() && !(new File(path)).isDirectory()) {
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

    // Somehow without an ending /, OStorageException happens
    if (!path.endsWith("/")) {
      path = path + "/";
    }
    if (path.startsWith("remote ")) {
      connStr = path + " admin admin";
    }
    else {
      connStr = "plocal:" + path + " admin admin";
    }
    System.err.println("# connection string = " + connStr);

    LineReader lr = setupReader();

    // Below does not work with 2.1.14
    Orient.instance().getRecordConflictStrategy()
        .registerImplementation("ConflictHook", new OVersionRecordConflictStrategy());
    try (ODatabaseDocumentTx db = new ODatabaseDocumentTx(connStr)) {
      try {
        db.open("admin", "admin");
        System.err.println("# Type 'exit' or Ctrl+D to exit. Ctrl+C to cancel current query");
        readLineLoop(db, lr);
      }
      catch (Exception e) {
        e.printStackTrace();
      }
    }

    delR(tmpDir);
    System.err.println("");
  }
}
