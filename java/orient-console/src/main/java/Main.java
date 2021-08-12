/**
 * Simple OrientDB client
 * Limitation: only standard SQLs. No "info classes" etc.
 * TODO: add tests
 * TODO: Replace jline3
 *
 * curl -O -L "https://github.com/hajimeo/samples/raw/master/misc/orient-console.jar"
 * java -jar orient-console.jar <directory path|.bak file path> [permanent extract dir]
 * or
 * echo "query1;query2" | java -jar orient-console.jar <directory path|.bak file path>
 */

/*
TODO: => DELETE FROM healthcheckconfig WHERE @rid in (SELECT rid FROM (SELECT MIN(@rid) as rid, property_name, COUNT(*) as c FROM healthcheckconfig GROUP BY property_name) WHERE c > 1)
 java.lang.ClassCastException: java.lang.Integer cannot be cast to java.util.List
	at Main.execQueries(Main.java:84)
	at Main.readLineLoop(Main.java:141)
	at Main.main(Main.java:277)
 */

import com.orientechnologies.orient.core.Orient;
import com.orientechnologies.orient.core.conflict.OVersionRecordConflictStrategy;
import com.orientechnologies.orient.core.db.document.ODatabaseDocumentTx;
import com.orientechnologies.orient.core.exception.OCommandExecutionException;
import com.orientechnologies.orient.core.sql.OCommandSQL;
import com.orientechnologies.orient.core.sql.OCommandSQLParsingException;
import net.lingala.zip4j.ZipFile;
import org.jline.reader.*;
import org.jline.reader.impl.completer.StringsCompleter;
import org.jline.reader.impl.history.DefaultHistory;
import org.jline.terminal.Terminal;
import org.jline.terminal.TerminalBuilder;

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

  private Main() {
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

  private static void printListAsJson(List<?> oDocs) {
    if (oDocs == null || oDocs.isEmpty()) {
      terminal.writer().println("\n[]");
      terminal.flush();
      return;
    }
    System.out.println("\n[");
    for (int i = 0; i < oDocs.size(); i++) {
      if (i == (oDocs.size() - 1)) {
        terminal.writer().println("  " + oDocs.get(i).toString());
      }
      else {
        terminal.writer().println("  " + oDocs.get(i).toString() + ",");
      }
      terminal.flush();
    }
    terminal.writer().println("]");
    terminal.flush();
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
        final List<?> results = db.command(new OCommandSQL(q)).execute();
        printListAsJson(results);
        System.err.printf("Rows: %d, ", results.size());
      }
      catch (java.lang.ClassCastException e) {
        // TODO: 'EXPLAIN' causes com.orientechnologies.orient.core.record.impl.ODocument cannot be cast to java.util.List
        System.err.println(e.getMessage());
        e.printStackTrace();
      }
      catch (OCommandSQLParsingException | OCommandExecutionException ex) {
        // TODO: why it's so hard to remove the last history with jline3? items should be exposed.
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
    // NOTE: highlight (.highlighter(new DefaultHighlighter()))
    // but this may output extra control characters which need to be removed when the result is redirected into a file
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
    terminal = TerminalBuilder
        .builder()
        .system(true)
        //.dumb(true)
        .build();
    history = new DefaultHistory();
    historyPath = System.getProperty("user.home") + "/.orient-console_history";
    System.err.println("history path: " + historyPath);
    Set<String> words = genAutoCompWords(historyPath);
    LineReader lr =
        LineReaderBuilder.builder().terminal(terminal).history(history).completer(new StringsCompleter(words))
            .variable(LineReader.HISTORY_FILE, new File(historyPath)).build();
    history.attach(lr);
    return lr;
  }

  public static void main(final String[] args) throws IOException {
    if (args.length < 1) {
      System.err.println("Usage: java -jar orient-console.jar <directory path|.bak file path> [permanent extract dir]");
      System.exit(1);
    }

    String path = args[0];
    String connStr = "";
    Path tmpDir = null;
    String extDir = System.getProperty("extractDir", "");

    // Preparing data (extracting zip if necessary)
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
    System.err.println("# connection string = " + connStr);

    LineReader lr = setupReader();

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
