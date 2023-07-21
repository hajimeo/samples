/**
 * https://www.codejava.net/java-se/jdbc/connect-to-h2-database-examples
 */

import org.h2.jdbc.JdbcSQLException;
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
    static final private String H2_DEFAULT_OPTS = "DATABASE_TO_UPPER=FALSE;LOCK_MODE=0;DEFAULT_LOCK_TIMEOUT=600000";
    static final private String PROMPT = "=> ";
    static private String h2ExtraOpts = "";
    static private Terminal terminal;
    static private History history;
    static private String historyPath;
    static private int paging = 0;
    static private int pageCount = 0;
    static private int offset = 0;
    static private String ridName = "_ROWID_";
    static private int lastRows = 0;
    static private String lastRid = "0";
    static private String dbUser = "";
    static private String dbPwd = "";
    static private Boolean isDebug;
    private static Connection conn;
    private static Statement stat;

    private Main() {
    }

    public static final Pattern describeNamePtn =
            Pattern.compile("(info|describe|desc) (table|class|index) ([^;]+)", Pattern.CASE_INSENSITIVE);
    public static final Pattern exportNamePtn =
            Pattern.compile("export (.+) to (.+)", Pattern.CASE_INSENSITIVE);
    public static final Pattern setPagingPtn =
            Pattern.compile("(set) (page|paging|offset) ([0-9]+)", Pattern.CASE_INSENSITIVE);

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

    private static List<String> getColumns(ResultSet rs) throws SQLException {
        ResultSetMetaData meta = rs.getMetaData();
        //int longestLabel = 0;
        int colLen = meta.getColumnCount();
        List<String> columns = new ArrayList();
        for (int i = 0; i < colLen; i++) {
            String s = meta.getColumnLabel(i + 1);
            columns.add(s);
        }
        log("Columns: " + columns, isDebug);
        return columns;
    }

    // TODO: changing to List<?> breaks toJSON()
    private static int printRsAsJson(ResultSet rs, boolean isPaging) throws SQLException {
        List<String> columns = getColumns(rs);

        if (pageCount == 0) {
            terminal.writer().print("\n[");
        }
        int rowCount = 0;
        while (rs.next()) {
            if (columns.contains(ridName.toUpperCase())) {
                lastRid = rs.getObject(ridName.toUpperCase()).toString();
            } else if (columns.contains(ridName.toLowerCase())) {
                lastRid = rs.getObject(ridName.toLowerCase()).toString();
            } else
                terminal.writer().print("\n  ");
            // Not first row
            if (rowCount > 0) {
                terminal.writer().print(",");
            }
            rowCount++;
            JSONObject obj = new JSONObject();

            try {
                for (String label : columns) {
                    obj.put(label, rs.getObject(label));
                }
                terminal.writer().print(obj.toString());
            } catch (Exception e) {
                log("WARN: printing result failed (lastRid = " + lastRid + ") Exception: " + e.getMessage());
                e.printStackTrace();
            }
            terminal.flush();
        }
        if (!isPaging || rowCount < paging) {
            terminal.writer().println("\n]");
        }
        // TODO: not working?  and not organised properly
        terminal.flush();
        return rowCount;
    }

    private static void execQueries(String input) {
        String[] queries = input.split(";");
        //boolean needHistoryReload = false;
        for (String q : queries) {
            if (q == null || q.trim().isEmpty()) {
                continue;
            }

            Instant start = Instant.now();
            pageCount = 0;
            int fetchedRows = 0;

            try {
                boolean isPaging = false;
                if (paging > 0 && q.toLowerCase().startsWith("select ")) {
                    // TODO: expecting H2 'OFFSET' would work with 'order by' and limit?
                    //if (q.toLowerCase().contains(" order by ") || q.toLowerCase().contains(" limit ")) {
                    //    log("ERROR: 'paging' is given but query contains 'order by' or 'limit'.");
                    //    continue;
                    //}
                    if (q.toLowerCase().contains(" offset ")) {
                        log("\nWARN: 'paging' is given but query contains 'offset'. Skipping this query: " + q);
                        continue;
                    }
                    if (q.toLowerCase().contains(" limit ")) {
                        log("\nWARN: 'paging' is given but query contains 'limit'. Skipping this query: " + q);
                        continue;
                    }
                    log("\nINFO: pagination is enabled with paging size:" + paging + "");
                    isPaging = true;
                }

                fetchedRows = execQuery(q, isPaging);
                while (isPaging && lastRows >= paging) {
                    pageCount += 1;
                    fetchedRows += execQuery(q, isPaging);
                    System.out.println();
                    log("Fetched page:" + pageCount + " with paging:" + paging + " | lastRid:" + lastRid);
                }
                // Catch ignorable exceptions in here
            } catch (java.lang.RuntimeException e) {
                System.err.println(e.getMessage());
                //removeLineFromHistory(q);
                //needHistoryReload = true;
            } finally {
                Instant finish = Instant.now();
                long timeElapsed = Duration.between(start, finish).toMillis();
                System.err.printf("\nElapsed: %d ms  Rows: %d\n", timeElapsed, fetchedRows);
            }
        }
    }

    private static int execQuery(String query, boolean isPaging) {
        if (isPaging) {
            if (!query.toLowerCase().contains(" " + ridName + " ")) {
                query = query.replaceAll("^(?i)SELECT ", "SELECT " + ridName + ", ");
            }
            if (query.toLowerCase().contains(" limit ")) {
                // Probably below doesn't work well but anyway trying
                query = query.replaceAll(" (?i)limit ", " LIMIT " + paging + "");
            } else {
                query += " LIMIT " + paging;
            }
            query += " OFFSET " + (pageCount * paging + offset);
            log(query, isDebug);
        }

        try {
            ResultSet rs;
            if (stat.execute(query)) {
                rs = stat.getResultSet();
                lastRows = printRsAsJson(rs, isPaging);
            } else {
                lastRows = stat.getUpdateCount();
            }
            return lastRows;
        } catch (JdbcSQLException e) {
            if (e.getMessage().contains("corrupted while reading record")) {
                System.out.println();
                log("ERROR: '" + query + "' failed with " + e.getMessage() + "(" + lastRid + ")");
            }
            throw new RuntimeException(e);
        } catch (SQLException e) {
            throw new RuntimeException(e);
        }
    }

    private static void execute(String query) {
        log(query, isDebug);
        try {
            ResultSet rs;
            if (stat.execute(query)) {
                rs = stat.getResultSet();
                List<String> columns = getColumns(rs);
                while (rs.next()) {
                    for (String label : columns) {
                        String value = rs.getObject(label).toString();
                        log(label + " = " + value, isDebug);
                        terminal.writer().println(value);
                    }
                }
                terminal.flush();
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
        if (input.trim().startsWith("--")) {
            return true;
        }
        if (input.toLowerCase().startsWith("set autocommit true")) {
            log(input, isDebug);
            conn.setAutoCommit(true);
            System.err.println("OK.");
            return true;
        }
        if (input.toLowerCase().startsWith("set autocommit false")) {
            log(input, isDebug);
            conn.setAutoCommit(false);
            System.err.println("OK.");
            return true;
        }
        if (input.toLowerCase().startsWith("set debug true")) {
            isDebug = true;
            System.err.println("OK. isDebug=" + isDebug);
            return true;
        }
        if (input.toLowerCase().startsWith("set debug false")) {
            isDebug = false;
            System.err.println("OK. isDebug=" + isDebug);
            return true;
        }
        if (input.toLowerCase().startsWith("set paging")) {
            Matcher matcher = setPagingPtn.matcher(input);
            if (matcher.find()) {
                String pageSize = matcher.group(3);
                if (pageSize != null && !pageSize.trim().isEmpty()) {
                    paging = Integer.parseInt(pageSize);
                }
            }
            System.err.println("OK. paging=" + paging);
            return true;
        }
        if (input.toLowerCase().startsWith("set offset")) {
            Matcher matcher = setPagingPtn.matcher(input);
            if (matcher.find()) {
                String offsetSize = matcher.group(3);
                if (offsetSize != null && !offsetSize.trim().isEmpty()) {
                    offset = Integer.parseInt(offsetSize);
                }
            }
            System.err.println("OK. (start) offset=" + offset);
            return true;
        }
        if (input.toLowerCase().startsWith("describe table") || input.toLowerCase().startsWith("desc table") ||
                input.toLowerCase().startsWith("info table")) {
            Matcher matcher = describeNamePtn.matcher(input);
            if (matcher.find()) {
                // Not in use as not sure how to do 'desc <non table>'
                //String descType = matcher.group(2);
                String[] names = matcher.group(3).split("\\.", 2);
                String query = "SELECT SQL FROM INFORMATION_SCHEMA.TABLES";
                String where = " WHERE TABLE_NAME = '" + names[0] + "'";
                if (names.length > 1) {
                    where = " WHERE TABLE_SCHEMA = '" + names[0] + "' AND TABLE_NAME = '" + names[1] + "'";
                }
                execute(query + where);
                query = "SELECT SQL FROM INFORMATION_SCHEMA.CONSTRAINTS";
                execute(query + where);
            } else {
                log("No match found from " + input, isDebug);
            }
            return true;
        }
        if (input.toLowerCase().startsWith("list classes") || input.toLowerCase().startsWith("list tables")) {
            String query = "SELECT TABLE_SCHEMA, TABLE_NAME, ROW_COUNT_ESTIMATE FROM INFORMATION_SCHEMA.TABLES ORDER BY TABLE_SCHEMA, TABLE_NAME";
            execQuery(query, false);
            return true;
        }
        if (input.toLowerCase().startsWith("export")) {
            Matcher matcher = exportNamePtn.matcher(input);
            if (matcher.find()) {
                String[] names = matcher.group(1).replace("*", "%").split("\\.", 2);
                String exportTo = matcher.group(2);
                exportTables(names, exportTo);
            } else {
                log("No match found from " + input, isDebug);
            }
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
                log(e.getMessage());
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

    private static void exportTables(String[] schema_and_table, String exportToPath) {
        String query = "SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES";
        String where = " WHERE TABLE_NAME LIKE '" + schema_and_table[0] + "'";
        if (schema_and_table.length > 1) {
            if (schema_and_table[1].equals("%")) {
                where = " WHERE TABLE_SCHEMA like '" + schema_and_table[0] + "'";
            } else {
                where = " WHERE TABLE_SCHEMA like '" + schema_and_table[0] + "' AND TABLE_NAME like '" + schema_and_table[1] + "'";
            }
        }

        ResultSet rs;
        try {
            if (stat.execute(query + where)) {
                rs = stat.getResultSet();
                while (rs.next()) {
                    String export_query = "SCRIPT SIMPLE TO '" + exportToPath + "/tbl_" + rs.getString(1) + "_" + rs.getString(2) + ".sql' TABLE " + rs.getString(1) + "." + rs.getString(2) + ";";
                    try {
                        log(export_query);
                        stat.execute(export_query);
                    } catch (SQLException e) {
                        log(e.getMessage());
                    }
                }
            }
        } catch (SQLException e) {
            log(e.getMessage());
        }
    }

    private static Set<String> genAutoCompWords(String fileName) {
        // at this moment, not considering some slowness by the file size as DEFAULT_HISTORY_SIZE should take care
        Set<String> wordSet = new HashSet<>(Arrays
                .asList("CREATE", "SELECT FROM", "UPDATE", "INSERT INTO", "DELETE FROM", "FROM", "WHERE", "BETWEEN", "AND",
                        "DISTINCT", "DISTINCT", "LIKE", "LIMIT", "NOT"));
        if (new File(fileName).isFile()) {
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
                log(e.getMessage());
            }
        }

        if (conn != null && stat != null) {
            ResultSet rs;
            try {
                if (stat.execute("SELECT DISTINCT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE <> 'SYSTEM TABLE'")) {
                    rs = stat.getResultSet();
                    while (rs.next()) {
                        wordSet.add(rs.getString(2));
                        wordSet.add(rs.getString(1) + "." + rs.getString(2));
                    }
                }
                if (stat.execute("SELECT DISTINCT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS")) {
                    rs = stat.getResultSet();
                    while (rs.next()) {
                        wordSet.add(rs.getString(1));
                    }
                }
            } catch (SQLException e) {
                log(e.getMessage());
            }
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
        System.err.println("# history path: " + historyPath);
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
        paging = Integer.parseInt(System.getProperty("paging", "0"));
        log("paging       = " + paging, isDebug);
        ridName = System.getProperty("ridName", "_ROWID_");
        log("ridName      = " + ridName, isDebug);
        lastRid = System.getProperty("lastRid", "0");
        log("lastRid      = " + lastRid, isDebug);
        h2ExtraOpts = System.getProperty("h2ExtraOpts", "");
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
        // As the default option doesn't have MV_STORE to support Repo Manager's H2, automatically add MV_STORE=FALSE
        if (h2ExtraOpts.isEmpty() && path.endsWith(".h2.db")) {
            h2ExtraOpts = "MV_STORE=FALSE";
            if (path.endsWith("ods.h2.db")) {
                h2ExtraOpts = h2ExtraOpts + ";SCHEMA=insight_brain_ods";
            }
            // TODO: this is not good logic but assuming ".h2.db" is for IQ
            if (dbUser.isEmpty()) {
                dbUser = "sa";
            }
        }
        if (new File(path).isFile()) {
            // TODO: not perfect to avoid "A file path that is implicitly relative to the current working directory is not allowed in the database UR"
            path = new File(path).getAbsolutePath();
            path = path.replaceAll("\\.(h2|mv)\\.db", "");
        }
        String h2Opt = H2_DEFAULT_OPTS;
        if (!h2ExtraOpts.isEmpty()) {
            h2Opt = h2Opt + ";" + h2ExtraOpts;
        }
        try {
            System.err.println("# jdbc:h2:" + path + ";" + h2Opt);
            org.h2.Driver.load();
            conn = DriverManager.getConnection("jdbc:h2:" + path + ";" + h2Opt, dbUser, dbPwd);
            // Making sure auto commit is on as default
            conn.setAutoCommit(true);
            stat = conn.createStatement();
            stat.setFetchSize(1000);

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
