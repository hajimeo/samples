/**
 * TODO: If easy to implement, keep reading the stdin until ";"
 */

import org.json.JSONObject;
import org.jline.reader.*;
import org.jline.reader.impl.DefaultHighlighter;
import org.jline.reader.impl.completer.StringsCompleter;
import org.jline.reader.impl.history.DefaultHistory;
import org.jline.terminal.Terminal;
import org.jline.terminal.TerminalBuilder;
import org.postgresql.util.PSQLException;

import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.sql.*;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class PgConsole {
    static private Boolean isDebug;
    static final private String PROMPT = "=> ";
    static final private List<String> numTypes = Arrays.asList("smallint", "integer", "int", "int4", "bigint", "decimal", "numeric", "real", "smallserial", "serial", "bigserial");
    static private String outputFormat = "csv";    // or json
    static private Terminal terminal;
    static private String historyPath;
    static private String dbUser = "";
    static private String dbPwd = "";
    private static Connection conn;
    private static Statement stat;
    private static final String sep = System.getProperty("file.separator");

    private PgConsole() {
    }

    public static final Pattern describeNamePtn =
            Pattern.compile("(info|describe|desc) (table|class|index) ([^;]+)", Pattern.CASE_INSENSITIVE);
    //TODO: public static final Pattern exportNamePtn = Pattern.compile("export ([^ ]+) to ([^;]+)", Pattern.CASE_INSENSITIVE);
    //TODO: public static final Pattern importNamePtn = Pattern.compile("import (.+)", Pattern.CASE_INSENSITIVE);
    //TODO: public static final Pattern setPagingPtn = Pattern.compile("(set) (page|paging|offset) ([0-9]+)", Pattern.CASE_INSENSITIVE);
    public static final Pattern setSchemaPtn = Pattern.compile("set schema ([^ ]+)", Pattern.CASE_INSENSITIVE);

    private static void usage() {
        System.err.println("https://github.com/hajimeo/samples/blob/master/java/pg-console/README.md");
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

    private static Hashtable<String, String> getColumnsWithType(ResultSet rs) throws SQLException {
        ResultSetMetaData meta = rs.getMetaData();
        //int longestLabel = 0;
        int colLen = meta.getColumnCount();
        Hashtable<String, String> columns = new Hashtable<>();
        for (int i = 1; i <= colLen; i++) {
            String s = meta.getColumnName(i);
            String t = meta.getColumnTypeName(i).toLowerCase();
            columns.put(s, t);
        }
        log("Columns: " + columns, isDebug);
        return columns;
    }

    private static int printRsAsJson(ResultSet rs) throws SQLException {
        // TODO: changing to List<?> breaks toJSON()
        List<String> columns = (List<String>) getColumnsWithType(rs).keys();

        terminal.writer().print("\n[");
        int rowCount = 0;
        while (rs.next()) {
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
                terminal.writer().print(obj);
            } catch (Exception e) {
                log("WARN: printing result failed with Exception: " + e.getMessage());
                e.printStackTrace();
            }
            terminal.flush();
        }

        terminal.writer().println("\n]");
        terminal.flush();
        return rowCount;
    }

    private static List<String> dictKeys(Hashtable<String, String> dict) {
        List<String> keys = new ArrayList<>();
        Enumeration<String> enumeration = dict.keys();
        for (Map.Entry<String, String> entry : dict.entrySet()) {
            keys.add(entry.getKey());
        }
        return keys;
    }

    private static String fixedWidth(String value, String label, Hashtable<String, Integer> maxLen, Boolean isNumType) {
        if (isNumType) {
            return String.format("%-" + (maxLen.get(label) + 3 + 2) + "s", value + ",");
        }
        return String.format("%-" + (maxLen.get(label) + 3) + "s", ("\"" + value.replace("\"", "\\\"") + "\","));
    }

    private static int printRsAsFixedWidth(ResultSet rs) throws SQLException {
        Hashtable<String, String> columnsWithType = getColumnsWithType(rs);
        List<String> columns = dictKeys(columnsWithType);

        List<Hashtable<String, String>> resultUpto100 = new ArrayList<>();
        Hashtable<String, Integer> maxLen = new Hashtable<>();
        int rowCount = 0;
        while (rs.next()) {
            Hashtable<String, String> row = new Hashtable<>();
            for (String label : columns) {
                Object obj = rs.getObject(label);
                String value = "null";
                if (obj != null) {
                    value = obj.toString();
                }
                log(label + " = " + value, isDebug);
                if (!maxLen.containsKey(label)) {
                    maxLen.put(label, label.length());
                }
                if (maxLen.get(label) < value.length()) {
                    maxLen.put(label, value.length());
                }
                row.put(label, value);
            }
            resultUpto100.add(row);
            // sample only first 100
            rowCount++;
            if (rowCount >= 100) {
                break;
            }
        }

        StringBuilder header = new StringBuilder();
        for (String label : columns) {
            if (!maxLen.containsKey(label)) {
                continue;
            }
            header.append(fixedWidth(label, label, maxLen, true));
        }
        terminal.writer().println(header.toString().replaceAll(",\\s*$", ""));
        terminal.flush();
        /*StringBuilder hr = new StringBuilder();
        for (String label : columns) {
            hr.append(String.format("%" + (maxLen.get(label) + 2) + "s", " ").replace(" ", "-")).append(" ");
        }
        terminal.writer().println(hr);
        terminal.flush();*/

        for (Hashtable<String, String> row : resultUpto100) {
            StringBuilder line = new StringBuilder();
            for (String label : columns) {
                line.append(fixedWidth(row.get(label).toString(), label, maxLen, numTypes.contains(columnsWithType.get(label))));
            }
            terminal.writer().println(line.toString().replaceAll(",\\s*$", ""));
            terminal.flush();
        }

        while (rs.next()) {
            StringBuilder line = new StringBuilder();
            for (String label : columns) {
                line.append(fixedWidth(rs.getString(label), label, maxLen, numTypes.contains(columnsWithType.get(label))));
            }
            terminal.writer().println(line.toString().replaceAll(",\\s*$", ""));
            terminal.flush();
            rowCount++;
        }
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
            int fetchedRows = 0;

            try {
                fetchedRows = execQuery(q);
                // Catch ignorable exceptions in here
            } catch (java.lang.RuntimeException e) {
                System.err.println(e.getMessage());
            } finally {
                Instant finish = Instant.now();
                long timeElapsed = Duration.between(start, finish).toMillis();
                System.err.printf("\nElapsed: %d ms  Rows: %d\n", timeElapsed, fetchedRows);
            }
        }
    }

    private static int execQuery(String query) {
        try {
            ResultSet rs;
            int lastRows = 0;
            if (stat.execute(query)) {
                rs = stat.getResultSet();
                if (outputFormat.equalsIgnoreCase("json")) {
                    lastRows = printRsAsJson(rs);
                } else {
                    lastRows = printRsAsFixedWidth(rs);
                }
            } else {
                lastRows = stat.getUpdateCount();
            }
            return lastRows;
        } catch (SQLException e) {
            throw new RuntimeException(e);
        }
    }

    private static void execute(String query) {
        // NOTE: this method is not for large result set
        log(query, isDebug);
        try {
            ResultSet rs;
            if (stat.execute(query)) {
                rs = stat.getResultSet();
                printRsAsFixedWidth(rs);
            }
        } catch (PSQLException e) {
            System.out.println();
            log("ERROR: " + e.getMessage());
            throw new RuntimeException(e);
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

        log(input, isDebug);
        if (input.toLowerCase().startsWith("set autocommit true")) {
            conn.setAutoCommit(true);
            System.err.println("OK.");
            return true;
        }
        if (input.toLowerCase().startsWith("set autocommit false")) {
            conn.setAutoCommit(false);
            System.err.println("OK.");
            return true;
        }
        if (input.toLowerCase().startsWith("set output text")) {
            outputFormat = "text";
            System.err.println("OK.");
            return true;
        }
        if (input.toLowerCase().startsWith("set output json")) {
            outputFormat = "json";
            System.err.println("OK.");
            return true;
        }
        if (input.toLowerCase().startsWith("set output csv")) {
            outputFormat = "csv";
            System.err.println("OK.");
            return true;
        }
        if (input.toLowerCase().startsWith("describe table") || input.toLowerCase().startsWith("desc table") ||
                input.toLowerCase().startsWith("info table")) {
            Matcher matcher = describeNamePtn.matcher(input);
            if (matcher.find()) {
                // Not in use as not sure how to do 'desc <non table>'
                //String descType = matcher.group(2);
                String[] names = matcher.group(3).toLowerCase().split("\\.", 2);
                String query = "SELECT column_name, data_type, column_default, is_nullable, is_updatable FROM INFORMATION_SCHEMA.COLUMNS";
                String where = " WHERE LOWER(TABLE_NAME) = '" + names[0] + "'";
                if (names.length > 1) {
                    where = " WHERE LOWER(TABLE_SCHEMA) = '" + names[0] + "' AND LOWER(TABLE_NAME) = '" + names[1] + "'";
                }
                execute(query + where + " ORDER BY ordinal_position");
            } else {
                log("No match found from " + input, isDebug);
            }
            return true;
        }
        if (input.toLowerCase().startsWith("list classes") || input.toLowerCase().startsWith("list tables")) {
            String query = "SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES ORDER BY TABLE_SCHEMA, TABLE_NAME";
            execQuery(query);
            return true;
        }
        if (input.toLowerCase().startsWith("set schema")) {
            Matcher matcher = setSchemaPtn.matcher(input);
            if (matcher.find()) {
                conn.setSchema(matcher.group(1));
            } else {
                log("No match found from " + input);
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

    // TODO: rewrite for PostgreSQL
    private static void exportTables(String[] schema_and_table, String exportToPath) {
        String query = "SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES";
        String where = " WHERE LOWER(TABLE_SCHEMA) NOT IN ('information_schema')";
        if (schema_and_table.length == 1) {
            if (!schema_and_table[1].equals("%")) {
                where += " AND LOWER(TABLE_SCHEMA) like LOWER('" + schema_and_table[0] + "')";
            }
        } else if (schema_and_table.length == 2) {
            where += " AND LOWER(TABLE_SCHEMA) like LOWER('" + schema_and_table[0] + "') AND LOWER(TABLE_NAME) like LOWER('" + schema_and_table[1] + "')";
        } else {
            log("Incorrect schema_and_table:" + schema_and_table.toString());
            return;
        }

        ResultSet rs;
        try {
            Boolean probablyExported = false;
            if (stat.execute(query + where)) {
                rs = stat.getResultSet();
                Statement _stat = conn.createStatement();
                while (rs.next()) {
                    String export_query = "SCRIPT SIMPLE TO '" + exportToPath + sep + "tbl_" + rs.getString(1).toLowerCase() + "_" + rs.getString(2).toLowerCase() + ".sql' TABLE " + rs.getString(1) + "." + rs.getString(2) + ";";
                    try {
                        log(export_query);
                        _stat.execute(export_query);
                        probablyExported = true;
                    } catch (SQLException e) {
                        log(e.getMessage());    // but keep going
                    }
                }
            }
            if (!probablyExported) {
                log("Nothing to export for " + schema_and_table.toString());
            }
        } catch (SQLException e) {
            log(e.getMessage());
        }
    }

    private static void importFromFile(String importFromPath) {
        log("TODO: not implemented. " + importFromPath);
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
        History history = new DefaultHistory();
        historyPath = System.getProperty("user.home").replaceAll(sep + "$", "") + sep + ".pg-console_history";
        Path path = Paths.get(historyPath);
        if (!Files.isWritable(path)) {
            System.err.println("# " + System.getProperty("user.home") + " is not writable for history file. Using java.io.tmpdir.");
            historyPath = System.getProperty("java.io.tmpdir").replaceAll(sep + "$", "") + sep + ".pg-console_history";
        }
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

        String envPgDBUser = System.getenv("_PGDB_USER");
        if (envPgDBUser != null) {
            dbUser = envPgDBUser;
        }
        String envPgDBPwd = System.getenv("_PGDB_PWD");
        if (envPgDBPwd != null) {
            dbPwd = envPgDBPwd;
        }
    }

    public static void main(final String[] args) throws SQLException {
        if (args.length < 1) {
            usage();
            System.exit(1);
        }

        setGlobals();

        String jdbcUrl = args[0];
        if (args.length > 1) {
            dbUser = args[1];
        }
        if (args.length > 2) {
            dbPwd = args[2];
        }
        try {
            System.err.println("# " + jdbcUrl);
            conn = DriverManager.getConnection(jdbcUrl, dbUser, dbPwd);
            // https://stackoverflow.com/questions/28217044/process-a-large-amount-of-data-from-postgresql-with-java
            conn.setAutoCommit(false);
            stat = conn.createStatement();
            stat.setFetchSize(1000);

            LineReader lr = setupReader();
            System.err.println("# Type 'exit' or Ctrl+D to exit. Ctrl+C to cancel current query");
            readLineLoop(lr);
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
