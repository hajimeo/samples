# REQUIREMENTS:
#   # recommend to run in a virtual environment
#   pip install -U streamlit duckdb requests "mcp[cli]<2" #watchdog
#
# HOW TO RUN (Streamlit UI):
#   1. Start Ollama with AI_MODEL on AI_API_URL
#   2. `cd` to the extracted support zip which has (nexus.log, clm-server.log, request.log, outbound-request.log, audit.log)
#   3. Run this script: streamlit run python/support_app.py --client.toolbarMode="viewer"
#
# HOW TO RUN (MCP server, Streamable HTTP - for an AI agent instead of a human):
#   1. `cd` to the extracted support zip (same as above)
#   2. python python/support_app.py --mcp   # optional: MCP_HOST / MCP_PORT env vars, default 127.0.0.1:8931
#
# HOW TO RUN (both at once):
#   Set MCP_ENABLE=1 and run the Streamlit command above; the MCP server then also listens on
#   MCP_HOST/MCP_PORT in a background thread of the same Streamlit process, sharing its DuckDB connection/cache.

import gzip
import os
import re
import sys
import tempfile
import threading
from datetime import datetime, timezone

import streamlit as st
import duckdb
import requests

### Command arguments:
MCP_MODE = "--mcp" in sys.argv[1:]


def _config(key, default):
    """Config lookup that works with or without a running Streamlit context (MCP mode has none)."""
    return os.environ.get(key, default)


### Global variables: #################################################################################
# 0. Model and API Configuration
# If the environment variable AI_API_URL is set, use it; otherwise default to localhost
AI_API_URL = _config("AI_API_URL", "http://localhost:11434/api/generate")
AI_MODEL = _config("AI_MODEL", "qwen2.5-coder:7b")  # "gemma4:12b"

# Default Log sources are matching all files under the current directory or `./log/` directory, and file name ends with `.log` or `.log.gz`
# This can be overridden by LOG_APP_REGEX environment variable, which should be a regex pattern matching the log file paths to include.
LOG_APP_REGEX = _config("LOG_APP_REGEX", "(nexus|clm-server).*(log|log.gz)$")  # category `application`
LOG_REQ_REGEX = _config("LOG_REQ_REGEX", "(?<!outbound-)request.*(log|log.gz)$")  # category `request`
LOG_OUTBOUND_REGEX = _config("LOG_OUTBOUND_REGEX", "outbound-request.*(log|log.gz)$")  # category `outbound`
LOG_AUDIT_REGEX = _config("LOG_AUDIT_REGEX", "audit.*(log|log.gz)$")  # category `audit`

LOG_CATEGORY_REGEXES = {
    "application": LOG_APP_REGEX,
    "request": LOG_REQ_REGEX,
    "outbound": LOG_OUTBOUND_REGEX,
    "audit": LOG_AUDIT_REGEX,
}

# Where parsed views get cached as Parquet, so the (regex/JSON) parsing pass runs once instead of on every
# query/Streamlit rerun (or MCP server restart), and repeat queries read from disk (with column pruning/predicate
# pushdown) instead of holding every category fully materialized in memory at once.
# Default location should be current directory. Can't be shared with other directories as the cache would conflict.
DB_CACHE_DIR = _config("DB_CACHE_DIR", os.path.join(tempfile.gettempdir(), "__spt-app_db_cache"))
# Default should be OS's temp dir (e.g. /tmp/ if Linux, Mac, or %TEMP% if Windows)
LOG_CACHE_DIR = _config("LOG_CACHE_DIR", os.path.join(tempfile.gettempdir(), "spt-app_log"))
MCP_REQUEST_LOG_FILE = os.path.join(LOG_CACHE_DIR, "mcp_requests.log")
########################################################################################################


### Initialize DuckDB connection
con = duckdb.connect(database=':memory:')


def _warn(msg):
    """Reports a non-fatal setup problem to the console always, and to the Streamlit UI when running there."""
    print("WARNING: " + msg)
    if not MCP_MODE:
        st.warning(msg)


def _is_cache_fresh(cache_file, source_paths):
    """True if cache_file exists and is newer than every file in source_paths."""
    if not os.path.isfile(cache_file):
        return False
    cache_mtime = os.path.getmtime(cache_file)
    return all(os.path.getmtime(p) <= cache_mtime for p in source_paths if os.path.isfile(p))


def materialize_view_via_parquet(con, view_name, select_sql, source_paths, cache_dir=DB_CACHE_DIR):
    """Runs `select_sql` once (unless a fresh cache already exists) and writes the result to a Parquet
    file under cache_dir, then points `view_name` at that file via read_parquet."""
    os.makedirs(cache_dir, exist_ok=True)
    cache_file = os.path.join(cache_dir, f"{view_name}.parquet")
    if not _is_cache_fresh(cache_file, source_paths):
        con.execute(f"COPY ({select_sql}) TO '{cache_file}' (FORMAT PARQUET)")
    con.execute(f"CREATE OR REPLACE VIEW {view_name} AS SELECT * FROM read_parquet('{cache_file}')")


def find_log_files():
    """Walks the current directory and groups matching file paths by category."""
    compiled = {category: re.compile(pattern) for category, pattern in LOG_CATEGORY_REGEXES.items()}
    matches = {category: [] for category in LOG_CATEGORY_REGEXES}
    for root, _, files in os.walk("."):
        for fname in files:
            path = os.path.join(root, fname)
            for category, pattern in compiled.items():
                if pattern.search(path):
                    matches[category].append(path)
    return matches


def setup_log_views(con, file_categories):
    """Creates a unified `logs` view over the categorized log files, one row per line."""
    union_parts = []
    all_paths = []
    for category, paths in file_categories.items():
        if not paths:
            continue
        all_paths.extend(paths)
        # it seems read_text has 4GB limit, so changed to read_csv but not tested yet.
        union_parts.append(f"""
            SELECT
                line,
                '{category}' AS category,
                filename AS source_file
            FROM read_csv(
                {paths},
                columns={{'line': 'VARCHAR'}},
                sep='\\x01',
                quote='',
                escape='',
                header=false,
                filename=true,
                strict_mode=false
            )
            WHERE line != ''
        """)
    if not union_parts:
        raise Exception("No log files found matching the configured LOG_*_REGEX patterns.")
    materialize_view_via_parquet(con, "logs", " UNION ALL ".join(union_parts), all_paths)


_matched_log_files = find_log_files()

try:
    setup_log_views(con, _matched_log_files)
except Exception as e:
    # report error but continue; the user may not have logs yet
    _warn("Some log files are missing or could not be read. The AI assistant may have limited data: " + str(e))

# Column layouts + regexes for nexus.log/clm-server.log and request.log/outbound-request.log,
# so the AI can query real columns instead of regex-parsing the raw `line` itself.
# Ported from python/support-app/jn_utils_v2.py (_gen_regex_for_app_logs / _gen_regex_for_request_logs)
# so this script stays a single file with no extra dependency.
APP_SUPERSET_COLUMNS = ["date_time", "loglevel", "thread", "node", "user", "class", "message"]
APP_LOG_PATTERNS = [
    (["date_time", "loglevel", "thread", "node", "user", "class", "message"],
     r'^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[.,0-9]*)[^ ]* +([^ ]+) +\[([^]]+)\][^ ]* ([^ ]*) ([^ ]*) ([^ ]+) - (.*)'),
    (["date_time", "loglevel", "thread", "user", "class", "message"],
     r'^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[.,0-9]*)[^ ]* +([^ ]+) +\[([^]]+)\][^ ]* ([^ ]*) ([^ ]+) - (.*)'),
]
APP_LOG_DEFAULT = (["date_time", "loglevel", "message"],
                   r'^(\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d[.,0-9]*)[^ ]* +([^ ]+) +(.+)')

REQUEST_SUPERSET_COLUMNS = ["clientHost", "l", "user", "date", "requestURL", "statusCode", "headerContentLength",
                            "bytesSent", "elapsedTime", "headerUserAgent", "thread", "misc"]
REQUEST_LOG_PATTERNS = [
    (["clientHost", "l", "user", "date", "requestURL", "statusCode", "headerContentLength", "bytesSent",
      "elapsedTime", "headerUserAgent", "thread"],
     r'^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]*)" ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) "([^"]*)" \[([^\]]+)\]'),
    (["clientHost", "l", "user", "date", "requestURL", "statusCode", "headerContentLength", "bytesSent",
      "elapsedTime", "headerUserAgent", "thread", "misc"],
     r'^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]*)" ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) "([^"]*)" \[([^\]]+)\] (.+)'),
    (["clientHost", "l", "user", "date", "requestURL", "statusCode", "bytesSent", "elapsedTime", "headerUserAgent",
      "thread"],
     r'^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]*)" ([^ ]+) ([^ ]+) ([^ ]+) "([^"]*)" \[([^\]]+)\]'),
    (["clientHost", "l", "user", "date", "requestURL", "statusCode", "headerContentLength", "bytesSent",
      "elapsedTime", "headerUserAgent"],
     r'^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]*)" ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) "([^"]*)"'),
    (["clientHost", "l", "user", "date", "requestURL", "statusCode", "bytesSent", "elapsedTime", "headerUserAgent"],
     r'^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]*)" ([^ ]+) ([^ ]+) ([^ ]+) "([^"]+)'),
    (["clientHost", "l", "user", "date", "requestURL", "statusCode", "bytesSent", "elapsedTime", "misc"],
     r'^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]*)" ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+)'),
    (["clientHost", "l", "date", "requestURL", "statusCode", "bytesSent", "elapsedTime", "user", "misc"],
     r'^([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]*)" http_status=([^ ]+) http_content_length=([^ ]+) latency=([^ ]+) user=([^ ]+) (.+)'),
    # Nexus outbound-request.log
    (["date", "user", "requestURL", "statusCode", "bytesSent", "elapsedTime", "misc"],
     r'^\[([^\]]+)\] ([^ ]+) "([^"]*)" ([^ ]+) ([^ ]+) ([^ ]+) (.+)'),
]
REQUEST_LOG_DEFAULT = (["clientHost", "l", "user", "date", "requestURL", "statusCode", "bytesSent", "elapsedTime"],
                       r'^([^ ]+) ([^ ]+) ([^ ]+) \[([^\]]+)\] "([^"]*)" ([^ ]+) ([^ ]+) ([0-9]+)')


def _detect_log_pattern(filepath, candidates, default, line_filter=None, max_lines=200, max_checks=5):
    """Reads a handful of sample lines from filepath and returns the (columns, pattern) of the first
    candidate whose regex matches at least one of them; falls back to `default` if none match."""
    opener = gzip.open if filepath.endswith(".gz") else open
    checking_lines = []
    try:
        with opener(filepath, "rt", errors="ignore") as f:
            for i, raw_line in enumerate(f):
                if i >= max_lines or len(checking_lines) >= max_checks:
                    break
                candidate_line = raw_line.rstrip("\n")
                if not candidate_line:
                    continue
                if line_filter is not None and not line_filter(candidate_line):
                    continue
                checking_lines.append(candidate_line)
    except Exception:
        return default
    if not checking_lines:
        return default
    for columns, pattern in candidates:
        if any(re.search(pattern, l) for l in checking_lines):
            return columns, pattern
    return default


def _build_extract_sql(paths, pattern, columns, superset, category_label):
    """Builds a SELECT that extracts `columns` from `line` via regexp_extract (as a named struct, since
    DuckDB's integer-group form of regexp_extract only supports up to 9 groups), aligned to `superset`
    (missing columns become NULL), plus a `matched` flag and the raw `line`/`source_file` as a fallback."""
    select_cols = [(f"ext.{c} AS {c}" if c in columns else f"CAST(NULL AS VARCHAR) AS {c}") for c in superset]
    names_list = "[" + ", ".join(f"'{c}'" for c in columns) + "]"
    escaped_pattern = pattern.replace("'", "''")
    return f"""
        SELECT {', '.join(select_cols)}, matched, '{category_label}' AS category, source_file, line
        FROM (
            SELECT
                line,
                filename AS source_file,
                regexp_extract(line, '{escaped_pattern}', {names_list}) AS ext,
                regexp_matches(line, '{escaped_pattern}') AS matched
            FROM read_csv(
                {paths},
                columns={{'line': 'VARCHAR'}},
                sep='\\x01',
                quote='',
                escape='',
                header=false,
                filename=true,
                strict_mode=false
            )
            WHERE line != ''
        )
    """


def setup_typed_log_views(con, file_categories):
    """Creates `application_logs` (nexus/clm-server) and `request_logs` (request/outbound-request) views
    with real, typed columns extracted from `line`, instead of the AI having to regex the raw line itself.
    Rows that don't match any known log format keep `matched=false` and their raw `line`."""

    def is_app_log_line_start(line):
        return re.match(r'^\d\d\d\d-\d\d-\d\d.\d\d:\d\d:\d\d', line) is not None

    def build_view(view_name, categories, candidates, default, superset, numeric_cols, line_filter=None):
        groups = {}  # (columns tuple, pattern, category) -> [paths]
        for category in categories:
            for path in file_categories.get(category, []):
                columns, pattern = _detect_log_pattern(path, candidates, default, line_filter=line_filter)
                groups.setdefault((tuple(columns), pattern, category), []).append(path)
        if not groups:
            return
        union_parts = [_build_extract_sql(paths, pattern, list(columns), superset, category)
                       for (columns, pattern, category), paths in groups.items()]
        cast_cols = [(f"TRY_CAST({c} AS BIGINT) AS {c}" if c in numeric_cols else c) for c in superset]
        inner_sql = " UNION ALL ".join(union_parts)
        select_sql = f"SELECT {', '.join(cast_cols)}, matched, category, source_file, line FROM ({inner_sql})"
        all_paths = [p for paths in groups.values() for p in paths]
        materialize_view_via_parquet(con, view_name, select_sql, all_paths)

    build_view("application_logs", ["application"], APP_LOG_PATTERNS, APP_LOG_DEFAULT, APP_SUPERSET_COLUMNS,
               numeric_cols=set(), line_filter=is_app_log_line_start)
    build_view("request_logs", ["request", "outbound"], REQUEST_LOG_PATTERNS, REQUEST_LOG_DEFAULT,
               REQUEST_SUPERSET_COLUMNS, numeric_cols={"statusCode", "headerContentLength", "bytesSent", "elapsedTime"})


def setup_audit_log_view(con, file_categories):
    """Creates an `audit_logs` view from audit.log / audit-YYYY-MM-DD.log.gz, which is newline-delimited JSON (ndjson).
    NXRM3 and IQ Server use different top-level shapes for this file (NXRM3: nodeId/initiator/context/attributes;
    IQ: username/remoteIpAddress/userAgent/data), so rather than pinning one schema's columns (which would silently
    lose the other product's fields), each line is kept as a single `json` column (DuckDB's native JSON type) via
    read_json_objects - no schema inference, so nothing is dropped due to a shape mismatch. `timestamp`/`domain`/`type`
    are pulled out as plain columns since both products use those same three key names; everything else (initiator vs.
    username, attributes vs. data, etc.) should be reached via json_extract_string(json, '$.fieldName') on demand.
    Lines that aren't valid JSON get json=NULL/parsed=false, so nothing is silently dropped."""
    paths = file_categories.get("audit", [])
    if not paths:
        return
    select_sql = f"""
        SELECT
            json_extract_string(json, '$.timestamp') AS timestamp,
            json_extract_string(json, '$.domain') AS domain,
            json_extract_string(json, '$.type') AS type,
            json,
            json IS NOT NULL AS parsed,
            'audit' AS category,
            filename AS source_file
        FROM read_json_objects(
            {paths},
            format='newline_delimited',
            ignore_errors=true,
            filename=true
        )
    """
    materialize_view_via_parquet(con, "audit_logs", select_sql, paths)


try:
    setup_typed_log_views(con, _matched_log_files)
except Exception as e:
    _warn(
        "Could not build typed application_logs/request_logs views. The AI assistant may have limited data: " + str(e))

try:
    setup_audit_log_view(con, _matched_log_files)
except Exception as e:
    _warn("Could not build typed audit_logs view. The AI assistant may have limited data: " + str(e))

# Schema description shared between the AI system prompt (ask_local_ai) and the MCP `logs://schema` resource,
# so the two never drift apart.
LOG_SCHEMA_DESCRIPTION = """
Four views are available:

1. `logs` - every log line, raw text. Columns: line (raw log line text), category ('application', 'request', 'outbound', or 'audit'), source_file.
   Use this for free-text search (e.g. `SELECT * FROM logs WHERE category = 'audit' AND line ILIKE '%password%'`).

2. `application_logs` - parsed nexus.log / clm-server.log lines. Columns: date_time, loglevel, thread, node, user, class, message,
   matched (true if the line was successfully parsed into these columns), category, source_file, line (raw fallback).
   Example: `SELECT date_time, class, message FROM application_logs WHERE loglevel = 'ERROR' ORDER BY date_time`

3. `request_logs` - parsed request.log / outbound-request.log lines. Columns: clientHost, l, user, date, requestURL, statusCode
   (integer), headerContentLength (integer), bytesSent (integer), elapsedTime (integer, ms), headerUserAgent, thread, misc,
   matched, category, source_file, line (raw fallback).
   Example: `SELECT requestURL, AVG(elapsedTime) AS avg_ms FROM request_logs WHERE matched GROUP BY requestURL ORDER BY avg_ms DESC LIMIT 10`

4. `audit_logs` - parsed audit.log / audit-YYYY-MM-DD.log.gz entries (newline-delimited JSON, one audit event per
   line; NXRM3 and IQ Server use different field names for this file). Columns: timestamp, domain (e.g.
   'security.user', 'governance.proprietary-components'), type (e.g. 'CREATED', 'UPDATED', 'add'), json (the full
   raw JSON object for that line - use `json_extract_string(json, '$.fieldName')` for anything else, e.g.
   '$.initiator'/'$.context'/'$.attributes' on NXRM3 or '$.username'/'$.remoteIpAddress'/'$.data' on IQ Server),
   parsed, category, source_file.
   Example: `SELECT domain, type, COUNT(*) FROM audit_logs WHERE parsed GROUP BY domain, type ORDER BY 3 DESC`

Not every log line matches the known formats (multi-line stack traces, unusual banners, non-JSON lines, etc.) - for
those rows, matched/parsed=false and the typed columns are NULL; filter with `WHERE matched`/`WHERE parsed` when you
only want successfully parsed rows, or fall back to the `logs` view for full-text search across everything.
""".strip()


# 2. Local AI Query Generator (Ollama API)
def ask_local_ai(user_prompt):
    """Asks Qwen2.5-Coder to translate a natural language question into DuckDB SQL."""
    ollama_url = AI_API_URL

    # We guide the AI with a strict system prompt so it only returns valid SQL
    system_context = f"""
    You are an expert data engineer translating questions into DuckDB SQL queries.
    {LOG_SCHEMA_DESCRIPTION}

    CRITICAL: Return ONLY the raw SQL code block. Do not include markdown formatting like ```sql. Do not include explanations.
    """

    payload = {
        "model": AI_MODEL,
        "prompt": f"{system_context}\n\nUser Question: {user_prompt}\n\nSQL Query:",
        "stream": False
    }

    try:
        response = requests.post(ollama_url, json=payload)
        return response.json()['response'].strip()
    except Exception as e:
        return f"Error connecting to Ollama: {str(e)}"


def run_sql(sql):
    """Executes SQL against DuckDB and renders the results/chart in the main panel."""
    try:
        df_result = con.execute(sql).df()

        st.subheader("📊 Analysis Results")
        st.dataframe(df_result, use_container_width=True)

        # Dynamic Charting: If there's numerical data, show a chart automatically
        if len(df_result.columns) >= 2 and df_result.dtypes.iloc[1] in ['int64', 'float64']:
            st.subheader("📈 Visual Timeline / Metric Breakdowns")
            st.line_chart(df_result.set_index(df_result.columns[0]))

    except Exception as sql_error:
        st.error(f"SQL Execution Failed: {str(sql_error)}")


def _log_mcp_request(prompt, sql, summary):
    """Appends one line per MCP `query_logs` call to MCP_REQUEST_LOG_FILE: timestamp, prompt (if any),
    resolved SQL, and a short result summary (row count/truncated, or the error)."""
    os.makedirs(LOG_CACHE_DIR, exist_ok=True)
    timestamp = datetime.now(timezone.utc).isoformat()
    prompt_part = f"prompt={prompt!r} " if prompt else ""
    with open(MCP_REQUEST_LOG_FILE, "a") as f:
        f.write(f"{timestamp} {prompt_part}sql={sql!r} {summary}\n")


def run_mcp_server(con):
    """Runs this same log database as an MCP server (Streamable HTTP) instead of the Streamlit UI, so an AI
    agent can query it directly. One long-lived process keeps `con` and the cached views warm, so repeat
    tool calls have no per-call startup cost."""
    from mcp.server.fastmcp import FastMCP

    host = _config("MCP_HOST", "127.0.0.1")
    port = int(_config("MCP_PORT", "8931"))
    app = FastMCP("nexus-support-log-analyzer", host=host, port=port)

    @app.resource("logs://schema")
    def schema() -> str:
        return LOG_SCHEMA_DESCRIPTION

    @app.tool()
    def query_logs(prompt: str | None = None, sql: str | None = None) -> str:
        """Query the support-zip log views. Pass `sql` to run a DuckDB query directly, or `prompt` for a
        natural-language question (translated to SQL via the local model). Views: logs, application_logs,
        request_logs, audit_logs - see the logs://schema resource for their columns."""
        if not sql:
            if not prompt:
                return "ERROR: provide `sql` or `prompt`."
            sql = ask_local_ai(prompt)
            if sql.startswith("```sql"):
                sql = sql.replace("```sql", "").replace("```", "").strip()
        try:
            cur = con.execute(f"SELECT * FROM ({sql}) LIMIT 501")
            cols = [d[0] for d in cur.description]
            rows = cur.fetchall()
            truncated = len(rows) > 500
            rows = rows[:500]
            _log_mcp_request(prompt, sql, f"rows={len(rows)}" + (" (truncated at 500)" if truncated else ""))
            lines = [f"SQL: {sql}", f"rows: {len(rows)}" + (" (truncated at 500)" if truncated else "")]
            lines.append(" | ".join(cols))
            lines.extend(" | ".join("" if v is None else str(v) for v in r) for r in rows)
            return "\n".join(lines)
        except Exception as e:
            _log_mcp_request(prompt, sql, f"ERROR: {e}")
            return f"SQL ERROR: {e}"

    print(f"Starting MCP server (Streamable HTTP) on http://{host}:{port}/mcp ...")
    app.run(transport="streamable-http")


@st.cache_resource
def start_mcp_server_background(_con):
    """Runs run_mcp_server in a daemon thread so it can serve alongside the Streamlit UI in the
    same process/DuckDB connection. @st.cache_resource ensures this only happens once per process,
    since Streamlit re-executes the whole script on every rerun (widget click, etc.)."""
    thread = threading.Thread(target=run_mcp_server, args=(_con,), daemon=True)
    thread.start()
    return thread


if MCP_MODE:
    run_mcp_server(con)
else:
    if _config("MCP_ENABLE", ""):
        start_mcp_server_background(con)

    # 1. UI Configuration/customization
    st.set_page_config(page_title="Local SupportZip Analyzer", layout="wide")
    st.title("🔍 Local SupportZip Analyzer")

    # Hide the Streamlit "Deploy" button in the top-right corner
    st.markdown(
        r"""
        <style>
        .stAppDeployButton {
            visibility: hidden;
        }
        </style>
        """,
        unsafe_allow_html=True
    )

    if _config("MCP_ENABLE", ""):
        st.sidebar.caption(
            f"🔌 MCP server also live at http://{_config('MCP_HOST', '127.0.0.1')}:{_config('MCP_PORT', '8931')}/mcp")

    # 3. Sidebar Chat Interface (The "Support AI" Panel)
    st.sidebar.header("Ask AI Assistant")
    user_query = st.sidebar.text_area("Ask a question about your logs:",
                                      placeholder="e.g., Show me the top 5 errors sorted by frequency")

    if "sql_editor" not in st.session_state:
        st.session_state.sql_editor = ""

    run_now = False
    if st.sidebar.button("Analyze Logs"):
        if user_query:
            with st.spinner("AI is analyzing log structure and writing query..."):
                generated_sql = ask_local_ai(user_query)
                # Even though instructed to remove ```sql ... ```, some AI still returns it, so we clean it up
                if generated_sql.startswith("```sql"):
                    generated_sql = generated_sql.replace("```sql", "").replace("```", "").strip()
                st.session_state.sql_editor = generated_sql
                run_now = True
        else:
            st.sidebar.warning("Please enter a question first.")

    st.sidebar.subheader("SQL Query (editable)")
    st.sidebar.text_area("Edit or write raw SQL, then run it:", key="sql_editor", height=150)

    if run_now or st.sidebar.button("Run SQL"):
        if st.session_state.sql_editor.strip():
            run_sql(st.session_state.sql_editor)
        else:
            st.sidebar.warning("Enter or generate a SQL query first.")

    # 4. Main Panel Static Analytics (Observe-style Health Overview)
    st.header("🌐 System Overview")
    col1, col2, col3 = st.columns(3)

    try:
        # Use DuckDB to quickly populate high-level dashboard metrics from the categorized logs
        total_logs = con.execute("SELECT COUNT(*) FROM logs").fetchone()[0]
        try:
            # application_logs may not exist if no nexus.log/clm-server.log was found
            total_errors = con.execute("SELECT COUNT(*) FROM application_logs WHERE loglevel = 'ERROR'").fetchone()[0]
        except Exception:
            total_errors = 0

        col1.metric("Total Logs Processed", f"{total_logs:,}")
        col2.metric("ERROR count", f"{total_errors:,}")
        col3.metric("Model used by: " + AI_API_URL, AI_MODEL)

        st.subheader("📂 Logs by Category")
        category_df = con.execute(
            "SELECT category, COUNT(*) AS count FROM logs GROUP BY category ORDER BY category").df()
        st.bar_chart(category_df.set_index("category"))
    except Exception as e:
        col1.metric("Total Logs Processed", "0")
        col2.metric("Critical Anomalies Detected", "0")
        col3.metric("Log Ingestion Engine", "DuckDB (Waiting for logs)")
        st.info(
            "Place your log files at `./log/nexus.log` (application), "
            "`./log/request.log` and `./log/outbound-request.log` (request/outbound), "
            "and `./log/audit.log` (audit) to populate the dashboards."
        )
        st.error(f"Error reading logs or creating views: {str(e)}")
        st.exception(e)
