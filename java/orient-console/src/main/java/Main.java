/**
 * Simple OrientDB client
 * Limitation: only standard SQLs. No "info classes" etc.
 * TODO: add tests
 *
 * java -jar orient-console.jar <directory path|.bak file path> [permanent extract dir]
 * or
 * echo "query1;query2" | java -jar orient-console.jar <directory path|.bak file path>
 */

import com.orientechnologies.orient.core.Orient;
import com.orientechnologies.orient.core.command.OCommandExecutorNotFoundException;
import com.orientechnologies.orient.core.conflict.OVersionRecordConflictStrategy;
import com.orientechnologies.orient.core.db.document.ODatabaseDocumentTx;
import com.orientechnologies.orient.core.record.impl.ODocument;
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
import java.util.*;

public class Main {
    static final String PROMPT = "=> ";
    static Terminal terminal;

    private Main() {
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

    private static void printListAsJson(List<ODocument> oDocs) {
        if (oDocs.isEmpty()) {
            terminal.writer().println("\n[]");
            terminal.flush();
            return;
        }
        System.out.println("\n[");
        for (int i = 0; i < oDocs.size(); i++) {
            if (i == (oDocs.size() - 1)) {
                terminal.writer().println("  " + oDocs.get(i).toJSON());
            } else {
                terminal.writer().println("  " + oDocs.get(i).toJSON() + ",");
            }
            terminal.flush();
        }
        terminal.writer().println("]");
        terminal.flush();
    }

    private static void execQueries(String query, ODatabaseDocumentTx db) {
        List<String> queries = Arrays.asList(query.split(";"));
        for (int i = 0; i < queries.size(); i++) {
            try {
                String q = queries.get(i);
                if (q.isEmpty()) {
                    continue;
                }
                Instant start = Instant.now();
                final List<ODocument> results = db.command(new OCommandSQL(q)).execute();
                Instant finish = Instant.now();
                printListAsJson(results);
                long timeElapsed = Duration.between(start, finish).toMillis();
                System.err.printf("Elapsed: %d ms\n", timeElapsed);
            } catch (OCommandExecutorNotFoundException | OCommandSQLParsingException ex) {
                System.err.println(ex.getMessage());
                // NO continue;
            }
        }
    }

    private static void readLineLoop(ODatabaseDocumentTx db, LineReader reader) {
        // TODO: highlight (.highlighter(new DefaultHighlighter()))
        // TODO: prompt is always stdout which is annoying when redirects to file.
        String input = reader.readLine(PROMPT);
        while (input != null && !input.equalsIgnoreCase("exit")) {
            try {
                execQueries(input, db);
                input = reader.readLine(PROMPT);
            } catch (UserInterruptException e) {
                // User hit ctrl-C, just clear the current line and try again.
                System.err.println("^C");
                input = "";
                continue;
            } catch (EndOfFileException e) {
                System.err.println("^D");
                return;
            }
        }
    }

    private static boolean isDirEmpty(final Path directory) throws IOException {
        try (DirectoryStream<Path> dirStream = Files.newDirectoryStream(directory)) {
            return !dirStream.iterator().hasNext();
        }
    }

    private static Set<String> genAutoCompWords(String fileName) {
        // at this moment, not considering some slowness by the file size as DEFAULT_HISTORY_SIZE should take care
        Set<String> wordSet = new HashSet<>(Arrays.asList("CREATE", "SELECT FROM", "UPDATE", "INSERT INTO", "DELETE FROM", "FROM", "WHERE", "BETWEEN", "AND", "DISTINCT", "DISTINCT", "LIKE", "LIMIT", "NOT"));
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
        } catch (IOException e) {
            System.err.println(e.getMessage());
        }
        return wordSet;
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
                        System.err.println(e.getMessage());
                    }
                });
    }

    public static void main(final String[] args) throws IOException {
        if (args.length < 1) {
            System.err.println("Usage: java -jar orient-console.jar <directory path|.bak file path> [permanent extract dir]");
            System.exit(1);
        }

        String path = args[0];
        String connStr = "";
        String extDir = "";
        Path tmpDir = null;

        // Preparing data (extracting zip if necessary)
        if ((new File(path)).isDirectory()) {
            connStr = "plocal:" + path + " admin admin";
        } else {
            if (args.length > 1) {
                extDir = args[1];
                File destDir = new File(extDir);
                if (!destDir.exists()) {
                    if (!destDir.mkdirs()) {
                        System.err.println("Couldn't create " + destDir);
                        System.exit(1);
                    }
                } else if (!isDirEmpty(destDir.toPath())) {
                    System.err.println(extDir + " is not empty.");
                    System.exit(1);
                }
            } else {
                try {
                    tmpDir = Files.createTempDirectory(null);
                    tmpDir.toFile().deleteOnExit();
                    extDir = tmpDir.toString();
                } catch (IOException e) {
                    throw new RuntimeException(e);
                }
            }

            System.err.println("# unzip-ing " + path + " to " + extDir);
            try {
                unzip(path, extDir);
                if (!extDir.endsWith("/")) {
                    // Somehow without ending /, OStorageException happens
                    extDir = extDir + "/";
                }
                connStr = "plocal:" + extDir + " admin admin";
            } catch (IOException e) {
                System.err.println(path + " is not a right archive.");
                System.err.println(e.getMessage());
                delR(tmpDir);
                System.exit(1);
            }
        }
        System.err.println("# connection string = " + connStr);

        terminal = TerminalBuilder
                .builder()
                .system(true)
                .build();
        History history = new DefaultHistory();
        String historyPath = System.getProperty("user.home") + "/.orient-console_history";
        Set<String> words = genAutoCompWords(historyPath);
        StringsCompleter sqlComps = new StringsCompleter(words);
        LineReader lr = LineReaderBuilder.builder().terminal(terminal).history(history).completer(sqlComps).variable(LineReader.HISTORY_FILE, new File(historyPath)).build();
        history.attach(lr);

        Orient.instance().getRecordConflictStrategy().registerImplementation("ConflictHook", new OVersionRecordConflictStrategy());
        try (ODatabaseDocumentTx db = new ODatabaseDocumentTx(connStr)) {
            try {
                db.open("admin", "admin");
                System.err.println("# Type 'exit' or Ctrl+D to exit. Ctrl+C to cancel current query");
                readLineLoop(db, lr);
            } catch (Exception e) {
                e.printStackTrace();
            }
        }

        delR(tmpDir);
        System.err.println("");
    }
}
