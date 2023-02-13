import com.google.gson.Gson;
import org.json.JSONObject;
import org.jline.reader.*;
import org.jline.reader.impl.DefaultHighlighter;
import org.jline.reader.impl.completer.StringsCompleter;
import org.jline.reader.impl.history.DefaultHistory;
import org.jline.terminal.Terminal;
import org.jline.terminal.TerminalBuilder;

import java.io.*;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.sql.*;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Main {
    static final private String PROMPT = "=> ";
    static private Terminal terminal;
    static private History history;
    static private String historyPath;
    static private String paging = "";
    static private int pageCount = 1;
    static private String ridName = "_rowid_";
    static private int lastRows = 0;
    static private String lastRid = "0";
    static private String dbUser = "sa";
    static private String dbPwd = "";
    static private Boolean isDebug;
    private static final Gson gson = new Gson();
    private static Connection conn;
    private static Statement stat;

    private Main() {
    }

    public static final Pattern describeNamePtn =
            Pattern.compile("(info|describe|desc) (table|class|index) ([^;]+)", Pattern.CASE_INSENSITIVE);

    private static void usage() {
        System.err.println("https://github.com/hajimeo/samples/blob/master/java/h2-console/README.md");
    }

    private static String getCurrentLocalDateTimeStamp() {
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"));
    }

    private static void log(String msg) {
        // TODO: proper logging
        System.err.println(getCurrentLocalDateTimeStamp() + " " + msg);
    }

    private static void log(String msg, Boolean debug) {
        if (debug) {
            log("DEBUG: " + msg);
        }
    }

    // TODO: changing to List<?> breaks toJSON()
    private static void printRsAsJson(ResultSet rs, boolean isPaging) throws SQLException {
        ResultSetMetaData meta = rs.getMetaData();
        lastRows = rs.getFetchSize();
        //int longestLabel = 0;
        int colLen = meta.getColumnCount();
        String[] columns = new String[colLen];
        for (int i = 0; i < colLen; i++) {
            String s = meta.getColumnLabel(i + 1);
            columns[i] = s;
            //longestLabel = Math.max(longestLabel, s.length());
        }

        if (!isPaging) {
            terminal.writer().print("\n[");
        }
        int rowCount = 0;
        while (rs.next()) {
            terminal.writer().print("\n  ");
            // Not first row
            if (rowCount > 1) {
                terminal.writer().print(",");
            }
            rowCount++;
            JSONObject obj = new JSONObject();

            try {
                for (int i = 0; i < colLen; i++) {
                    String label = columns[i];
                    if (i == 0) {
                        lastRid = rs.getRowId(label).toString();
                        obj.put(ridName, lastRid);
                    }
                    obj.put(label, rs.getObject(label));
                }
                terminal.writer().println(gson.toJson(obj));
            } catch (Exception e) {
                System.err.println("ERROR: printing result failed (lastRid = " + lastRid + ") with " + e.getMessage());
                //e.printStackTrace();
            }
            terminal.flush();
        }
        if (!isPaging) {
            terminal.writer().println("]");
        }
        // TODO: not working?  and not organised properly
        terminal.flush();
    }

    private static void execQueries(String input) {
        String[] queries = input.split(";");
        for (String q : queries) {
            if (q == null || q.trim().isEmpty()) {
                continue;
            }

            Instant start = Instant.now();
            try {
                boolean isPaging = false;
                if (paging != null && paging.trim().length() > 0 && q.toLowerCase().startsWith("select ")) {
                    // TODO: expecting H2 'OFFSET' would work with 'order by' and limit?
                    //if (q.toLowerCase().contains(" order by ") || q.toLowerCase().contains(" limit ")) {
                    //    log("\nERROR: 'paging' is given but query contains 'order by' or 'limit'.");
                    //    continue;
                    //}
                    if (q.toLowerCase().contains(" offset ")) {
                        log("\nWARN: 'paging' is given but query contains 'offset'. Skipping this query: " + q);
                        continue;
                    }
                    log("\nINFO: pagination is enabled with paging size:" + paging + "");
                    isPaging = true;
                }

                execQuery(q, isPaging);
                while (isPaging && lastRows > 0) {
                    pageCount += 1;
                    log("Fetching page:" + pageCount + " with lastRows:" + lastRows + " | lastRid:" + lastRid);
                    execQuery(q, isPaging);
                }
                // Catch ignorable exceptions in here
            } catch (ClassCastException e) {
                System.err.println(e.getMessage());
                e.printStackTrace();
            } finally {
                Instant finish = Instant.now();
                long timeElapsed = Duration.between(start, finish).toMillis();
                System.err.printf("Elapsed: %d ms\n", timeElapsed);
            }
        }
    }

    private static void execQuery(String query, boolean isPaging) {
        if (isPaging) {
            if (query.toLowerCase().contains(" offset ")) {
                // Probably below doesn't work well but anyway trying
                query = query.replaceAll(" (?i)limit ", " LIMIT " + paging + "");
            } else {
                query += " LIMIT " + paging;
            }
            query += " OFFSET " + lastRows;
        }

        try {
            ResultSet rs;
            if (stat.execute(query)) {
                rs = stat.getResultSet();
                printRsAsJson(rs, isPaging);
            } else {
                int updateCount = stat.getUpdateCount();
                System.err.printf("Rows: %d, ", updateCount);
            }
        } catch (SQLException e) {
            throw new RuntimeException(e);
        }
    }

    // TODO: use this method when some exceptions happen
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
                } catch (IllegalArgumentException ee) {
                    // It's OK to ignore most of the errors/exception from matches
                    log(ee.getMessage());
                    continue;
                }
                writer.write(currentLine + System.getProperty("line.separator"));
            }
            tempFile.renameTo(inputFile);
        } catch (IOException e) {
            e.printStackTrace();
        } finally {
            try {
                if (writer != null) {
                    writer.close();
                }
                if (reader != null) {
                    reader.close();
                }
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
    }

    private static boolean isSpecialQueryAndProcess(String input) throws SQLException {
        if (input.startsWith("--")) {
            return true;
        }
        if (input.toLowerCase().startsWith("set autocommit true")) {
            log(input, isDebug);
            conn.setAutoCommit(true);
            System.err.print("OK");
            return true;
        }
        if (input.toLowerCase().startsWith("set autocommit false")) {
            log(input, isDebug);
            conn.setAutoCommit(false);
            System.err.print("OK");
            return true;
        }
        if (input.toLowerCase().startsWith("describe table") || input.toLowerCase().startsWith("desc table") ||
                input.toLowerCase().startsWith("info ")) {
            Matcher matcher = describeNamePtn.matcher(input);
            if (matcher.find()) {
                // Not in use as not sure how to do 'desc <non table>'
                String descType = matcher.group(2);
                String tableName = matcher.group(3);
                String query = "SHOW COLUMNS FROM " + tableName + ";";
                log(query, isDebug);
                execQuery(query, false);
                query = "SELECT * FROM INFORMATION_SCHEMA.CONSTRAINTS where table_name = '" + tableName + "'";
                log(query, isDebug);
                execQuery(query, false);
            }
            return true;
        }
        if (input.toLowerCase().startsWith("list classes") || input.toLowerCase().startsWith("list tables")) {
            String query = "SELECT TABLE_SCHEMA, TABLE_NAME, ROW_COUNT_ESTIMATE FROM INFORMATION_SCHEMA.TABLES ORDER BY TABLE_SCHEMA, TABLE_NAME";
            log(query, isDebug);
            execQuery(query, false);
            return true;
        }
        return false;
    }

    private static void readLineLoop(LineReader reader) {
        String input = reader.readLine(PROMPT);
        while (input != null && !input.startsWith("exit")) {
            try {
                if (!isSpecialQueryAndProcess(input)) {
                    log("execQueries: " + input, isDebug);
                    execQueries(input);
                }
                input = reader.readLine(PROMPT);
            } catch (SQLException e) {
                // User hit ctrl-C, just clear the current line and try again.
                System.err.println(e.getMessage());
                removeLineFromHistory(input);
                history.load();
                input = "";
            } catch (UserInterruptException e) {
                // User hit ctrl-C, just clear the current line and try again.
                System.err.println("^C");
                input = "";
            } catch (EndOfFileException e) {
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
        try (BufferedReader br = new BufferedReader(new InputStreamReader(Files.newInputStream(Paths.get(fileName))))) {
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

    private static LineReader setupReader() throws IOException {
        terminal = TerminalBuilder.builder()
                .system(true)
                .dumb(true)
                .build();
        history = new DefaultHistory();
        historyPath = System.getProperty("user.home") + "/.h2-console_history";
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

    private static void setGlobals() {
        isDebug = Boolean.getBoolean("debug");
        paging = System.getProperty("paging", "");
        log("paging       = " + paging, isDebug);
        ridName = System.getProperty("ridName", "_rowid_");
        log("ridName      = " + ridName, isDebug);
        lastRid = System.getProperty("lastRid", "0");
        log("lastRid      = " + lastRid, isDebug);
        String envH2DBUser = System.getenv("_H2DB_USER");
        if (envH2DBUser != null) {
            dbUser = envH2DBUser;
        }
        String envH2DBPwd = System.getenv("_H2DB_PWD");
        if (envH2DBPwd != null) {
            dbPwd = envH2DBPwd;
        }
    }

    public static void main(final String[] args) throws SQLException {
        if (args.length < 1) {
            usage();
            System.exit(1);
        }

        setGlobals();

        String path = args[0];
        if (new File(path).isFile()) {
            path = path.replaceAll("\\.(h2|mv)\\.db.*", "");
        }
        String h2Opt = "MV_STORE=FALSE;DATABASE_TO_UPPER=FALSE;LOCK_MODE=0;DEFAULT_LOCK_TIMEOUT=600000";
        if (args.length > 1) {
            h2Opt = args[1];
        }
        try {
            org.h2.Driver.load();
            conn = DriverManager.getConnection("jdbc:h2:" + path + ";" + h2Opt, dbUser, dbPwd);
            System.err.println("# Connected with jdbc:h2:" + path + ";" + h2Opt);
            // Making sure auto commit is on as default
            conn.setAutoCommit(true);
            stat = conn.createStatement();

            System.err.println("# Type 'exit' or Ctrl+D to exit. Ctrl+C to cancel current query");
            readLineLoop(setupReader());
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
            log("Exiting.");
            if (conn != null) {
                conn.close();
            }
        }
    }
}
